import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart' as picker;

const queryImageLimit = 4;
const queryImageMaxBytes = 10 * 1024 * 1024;
const queryImageMaxPixels = 24 * 1000 * 1000;

enum QueryImageProblem {
  tooMany,
  tooLarge,
  unsupported,
  invalid,
  cameraUnavailable,
  permissionDenied,
}

class QueryImageException implements Exception {
  const QueryImageException(this.problem);
  final QueryImageProblem problem;
}

class RawQueryImage {
  const RawQueryImage({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

class QueryImageAttachment {
  const QueryImageAttachment({
    required this.name,
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
  });

  final String name;
  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;
}

Future<QueryImageAttachment> validateQueryImage(RawQueryImage source) async {
  final bytes = source.bytes;
  if (bytes.lengthInBytes > queryImageMaxBytes) {
    throw const QueryImageException(QueryImageProblem.tooLarge);
  }
  final mimeType = _mimeType(bytes);
  if (mimeType == null) {
    throw const QueryImageException(QueryImageProblem.unsupported);
  }
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      if (width <= 0 || height <= 0 || width * height > queryImageMaxPixels) {
        throw const QueryImageException(QueryImageProblem.tooLarge);
      }
      return QueryImageAttachment(
        name: source.name,
        bytes: bytes,
        mimeType: mimeType,
        width: width,
        height: height,
      );
    } finally {
      codec.dispose();
    }
  } on QueryImageException {
    rethrow;
  } catch (_) {
    throw const QueryImageException(QueryImageProblem.invalid);
  }
}

String? _mimeType(Uint8List bytes) {
  if (bytes.length >= 8 && listEquals(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10])) {
    return 'image/png';
  }
  if (bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) {
    return 'image/jpeg';
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return 'image/webp';
  }
  return null;
}

abstract class QueryImagePort {
  Future<List<RawQueryImage>> pickImages();
  Future<RawQueryImage?> takePhoto();
  Future<List<RawQueryImage>> recoverLostPhotos();
}

class SystemQueryImagePort implements QueryImagePort {
  const SystemQueryImagePort();

  static const _typeGroup = XTypeGroup(
    label: 'images',
    extensions: ['png', 'jpg', 'jpeg', 'webp'],
    mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
    uniformTypeIdentifiers: ['public.png', 'public.jpeg', 'org.webmproject.webp'],
  );

  @override
  Future<List<RawQueryImage>> pickImages() async {
    final files = await openFiles(acceptedTypeGroups: const [_typeGroup]);
    if (files.length > queryImageLimit) {
      throw const QueryImageException(QueryImageProblem.tooMany);
    }
    return Future.wait(files.map(_readFile));
  }

  @override
  Future<RawQueryImage?> takePhoto() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const QueryImageException(QueryImageProblem.cameraUnavailable);
    }
    try {
      final file = await picker.ImagePicker().pickImage(
        source: picker.ImageSource.camera,
        requestFullMetadata: false,
      );
      return file == null ? null : await _readFile(file);
    } on PlatformException catch (error) {
      if (error.code.toLowerCase().contains('permission') ||
          error.code.toLowerCase().contains('access_denied')) {
        throw const QueryImageException(QueryImageProblem.permissionDenied);
      }
      throw const QueryImageException(QueryImageProblem.cameraUnavailable);
    }
  }

  @override
  Future<List<RawQueryImage>> recoverLostPhotos() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return [];
    final response = await picker.ImagePicker().retrieveLostData();
    if (response.isEmpty) return [];
    if (response.exception != null) {
      throw const QueryImageException(QueryImageProblem.cameraUnavailable);
    }
    return Future.wait((response.files ?? <XFile>[]).map(_readFile));
  }

  Future<RawQueryImage> _readFile(XFile file) async {
    if (await file.length() > queryImageMaxBytes) {
      throw const QueryImageException(QueryImageProblem.tooLarge);
    }
    return RawQueryImage(name: file.name, bytes: await file.readAsBytes());
  }
}
