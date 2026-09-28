import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'audio_blob_store.dart';
import 'cache_web_lock.dart';

Future<AudioByteBackend> openAudioByteBackend(String partition) async {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(partition)) {
    throw ArgumentError.value(partition, 'partition', 'Expected a cache scope digest');
  }
  if (!web.window.navigator.hasProperty('locks'.toJS).toDart ||
      !web.window.hasProperty('indexedDB'.toJS).toDart) {
    throw StateError('Persistent browser audio requires Web Locks and IndexedDB');
  }
  final request = web.window.indexedDB.open('haruka_audio_$partition', 1);
  final result = Completer<web.IDBDatabase>();
  request.onupgradeneeded = ((web.Event _) {
    final database = request.result! as web.IDBDatabase;
    database.createObjectStore('manifest');
    database.createObjectStore('chunks');
  }).toJS;
  request.onblocked = ((web.Event _) {
    if (!result.isCompleted) result.completeError(StateError('Audio database upgrade is blocked'));
  }).toJS;
  request.onerror = ((web.Event _) {
    if (!result.isCompleted) result.completeError(StateError('Could not open audio database'));
  }).toJS;
  request.onsuccess = ((web.Event _) {
    final database = request.result! as web.IDBDatabase;
    if (result.isCompleted) {
      database.close();
      return;
    }
    database.onversionchange = ((web.Event _) => database.close()).toJS;
    result.complete(database);
  }).toJS;
  return WebAudioByteBackend(partition, await result.future);
}

final class WebAudioByteBackend implements AudioByteBackend {
  WebAudioByteBackend(this.partition, this.database);

  final String partition;
  final web.IDBDatabase database;
  static final RegExp _reference = RegExp(r'^(stage|ready)-[a-f0-9]{64}$');

  void _check(String reference) {
    if (!_reference.hasMatch(reference)) throw ArgumentError.value(reference, 'reference');
  }

  Future<T> _withLock<T>(
    String name,
    String mode,
    Future<T> Function() action, {
    bool ifAvailable = false,
  }) async {
    final lockName = name == 'publish'
        ? WebCacheLock.partitionPublishName(partition)
        : 'haruka-audio:$partition:$name';
    final acquired = await WebCacheLock.acquire(lockName, mode, ifAvailable: ifAvailable);
    if (acquired == null) throw const _AudioLockUnavailable();
    try {
      return await action();
    } finally {
      await acquired.release();
    }
  }

  Future<void> _write(void Function(web.IDBTransaction) issue) async {
    final tx = database.transaction(['manifest'.toJS, 'chunks'.toJS].toJS, 'readwrite');
    final done = _transactionDone(tx);
    issue(tx);
    await done;
  }

  Future<JSAny?> _get(String store, String key) async {
    final tx = database.transaction(store.toJS, 'readonly');
    final done = _transactionDone(tx);
    JSAny? value;
    final request = tx.objectStore(store).get(key.toJS);
    request.onsuccess = ((web.Event _) => value = request.result).toJS;
    await done;
    return value;
  }

  Future<void> _putManifest(String reference, String base, int count, {bool insert = false}) {
    _check(reference);
    _check(base);
    return _write((tx) {
      final store = tx.objectStore('manifest');
      final value = jsonEncode({'base': base, 'count': count}).toJS;
      if (insert) {
        store.add(value, reference.toJS);
      } else {
        store.put(value, reference.toJS);
      }
    });
  }

  Future<({String base, int count})?> _manifest(String reference) async {
    final value = await _get('manifest', reference);
    if (value == null) return null;
    final json = (jsonDecode((value as JSString).toDart) as Map).cast<String, Object?>();
    final base = json['base'] as String;
    final count = json['count'] as int;
    _check(base);
    if (count < 0) throw const FormatException('Invalid audio chunk manifest');
    return (base: base, count: count);
  }

  @override
  Future<AudioStageWriter> beginStage(String reference) async {
    _check(reference);
    if (!reference.startsWith('stage-')) throw ArgumentError.value(reference, 'reference');
    final lock = await WebCacheLock.acquire('haruka-audio:$partition:$reference', 'exclusive');
    if (lock == null) throw StateError('Audio operation lock unavailable');
    try {
      await _putManifest(reference, reference, 0, insert: true);
      return _WebStageWriter(this, reference, lock);
    } catch (_) {
      await lock.release();
      rethrow;
    }
  }

  Future<void> _addChunk(String reference, int index, List<int> bytes) {
    final blob = web.Blob([Uint8List.fromList(bytes).toJS].toJS);
    return _write((tx) {
      tx.objectStore('chunks').add(blob, '$reference:$index'.toJS);
      tx
          .objectStore('manifest')
          .put(jsonEncode({'base': reference, 'count': index + 1}).toJS, reference.toJS);
    });
  }

  @override
  Future<void> promote(String stagingReference, String readyReference) async {
    _check(stagingReference);
    _check(readyReference);
    if (!stagingReference.startsWith('stage-') || !readyReference.startsWith('ready-')) {
      throw ArgumentError('Expected stage and ready audio references');
    }
    final manifest = await _manifest(stagingReference);
    if (manifest == null) throw StateError('Audio stage is missing');
    await _write((tx) {
      tx
          .objectStore('manifest')
          .add(
            jsonEncode({'base': manifest.base, 'count': manifest.count}).toJS,
            readyReference.toJS,
          );
      tx.objectStore('manifest').delete(stagingReference.toJS);
    });
  }

  @override
  Future<Stream<List<int>>?> open(String reference) async {
    _check(reference);
    final manifest = await _manifest(reference);
    if (manifest == null) return null;
    return (() async* {
      for (var index = 0; index < manifest.count; index++) {
        final value = await _get('chunks', '${manifest.base}:$index');
        if (value == null) throw StateError('Audio Blob chunk is missing');
        final blob = value as web.Blob;
        final buffer = (await blob.arrayBuffer().toDart).toDart;
        yield buffer.asUint8List();
      }
    })();
  }

  @override
  Future<bool> tryDelete(String reference) async {
    _check(reference);
    try {
      await _withLock(reference, 'exclusive', () async {
        final manifest = await _manifest(reference);
        if (manifest == null) return;
        await _write((tx) {
          tx.objectStore('manifest').delete(reference.toJS);
          for (var index = 0; index < manifest.count; index++) {
            tx.objectStore('chunks').delete('${manifest.base}:$index'.toJS);
          }
        });
      }, ifAvailable: true);
      return true;
    } on _AudioLockUnavailable {
      return false;
    }
  }

  @override
  Future<Set<String>> references() async {
    final tx = database.transaction('manifest'.toJS, 'readonly');
    final done = _transactionDone(tx);
    JSAny? keys;
    final request = tx.objectStore('manifest').getAllKeys();
    request.onsuccess = ((web.Event _) => keys = request.result).toJS;
    await done;
    if (keys == null) return {};
    return (keys! as JSArray<JSString>).toDart.map((key) => key.toDart).toSet();
  }

  @override
  Future<T> withPublishLock<T>(Future<T> Function() action) =>
      _withLock('publish', 'exclusive', action);

  @override
  Future<T?> withOperationLock<T>(
    String operationId,
    Future<T> Function() action, {
    bool ifAvailable = false,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9-]{1,80}$').hasMatch(operationId)) {
      throw ArgumentError.value(operationId, 'operationId');
    }
    try {
      return await _withLock(
        'operation:$operationId',
        'exclusive',
        action,
        ifAvailable: ifAvailable,
      );
    } on _AudioLockUnavailable {
      return null;
    }
  }

  @override
  Future<T> withReadLock<T>(String reference, Future<T> Function() action) {
    _check(reference);
    return _withLock(reference, 'shared', action);
  }

  @override
  Future<void> close() async => database.close();
}

final class _WebStageWriter implements AudioStageWriter {
  _WebStageWriter(this.backend, this.reference, this.lock);
  final WebAudioByteBackend backend;
  final String reference;
  final WebCacheLock lock;
  int _index = 0;
  bool _closed = false;

  @override
  Future<void> add(List<int> bytes) async {
    if (_closed) throw StateError('Audio stage is closed');
    await backend._addChunk(reference, _index, bytes);
    _index++;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await lock.release();
  }

  @override
  Future<void> abort() async {
    await close();
    await backend.tryDelete(reference);
  }
}

final class _AudioLockUnavailable implements Exception {
  const _AudioLockUnavailable();
}

Future<void> _transactionDone(web.IDBTransaction transaction) {
  final done = Completer<void>();
  Object failure(String description) => transaction.error?.name == 'QuotaExceededError'
      ? const AudioStorageQuotaExceeded()
      : StateError(description);
  transaction.oncomplete = ((web.Event _) {
    if (!done.isCompleted) done.complete();
  }).toJS;
  transaction.onerror = ((web.Event _) {
    if (!done.isCompleted) done.completeError(failure('Audio IndexedDB transaction failed'));
  }).toJS;
  transaction.onabort = ((web.Event _) {
    if (!done.isCompleted) done.completeError(failure('Audio IndexedDB transaction aborted'));
  }).toJS;
  return done.future;
}
