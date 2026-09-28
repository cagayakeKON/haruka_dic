import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'package:haruka/features/agent/application/query_images.dart';
import 'package:haruka/core/platform/query_paste.dart';

QueryPasteSource createQueryPasteSource() => _WebQueryPasteSource();

class _WebQueryPasteSource implements QueryPasteSource {
  JSFunction? _listener;

  @override
  void start({
    required bool Function() canAccept,
    required void Function(List<RawQueryImage>) onImages,
    required void Function(QueryImageProblem) onReadError,
  }) {
    dispose();
    _listener = ((web.Event event) {
      if (!canAccept()) return;
      final data = (event as web.ClipboardEvent).clipboardData;
      if (data == null) return;
      final files = <web.File>[];
      for (var index = 0; index < data.items.length; index++) {
        final item = data.items[index];
        if (item.kind != 'file' || !item.type.startsWith('image/')) continue;
        final file = item.getAsFile();
        if (file != null) files.add(file);
      }
      if (files.isEmpty) return;
      if (files.any((file) => file.size > queryImageMaxBytes)) {
        onReadError(QueryImageProblem.tooLarge);
        return;
      }
      unawaited(
        Future.wait(
          files.map((file) async {
            final buffer = await file.arrayBuffer().toDart;
            return RawQueryImage(
              name: file.name,
              bytes: Uint8List.fromList(Uint8List.view(buffer.toDart)),
            );
          }),
        ).then(onImages).catchError((Object _) => onReadError(QueryImageProblem.invalid)),
      );
    }).toJS;
    web.document.addEventListener('paste', _listener);
  }

  @override
  void dispose() {
    if (_listener case final listener?) {
      web.document.removeEventListener('paste', listener);
      _listener = null;
    }
  }
}
