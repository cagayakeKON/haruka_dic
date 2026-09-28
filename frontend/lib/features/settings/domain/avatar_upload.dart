import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const avatarMaxInputBytes = 5 * 1024 * 1024;

/// JPEG, PNG, or WebP from magic bytes. Anything else is refused before a request.
String? avatarDeclaredFormat(Uint8List bytes) {
  if (bytes.length < 12 || bytes.length > avatarMaxInputBytes) return null;
  if (bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) return 'jpeg';
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e && bytes[3] == 0x47) return 'png';
  try {
    if (ascii.decode(bytes.sublist(0, 4)) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12)) == 'WEBP') {
      return 'webp';
    }
  } on FormatException {
    return null;
  }
  return null;
}

Map<String, Object?> avatarIntentBody(Uint8List bytes) {
  final format = avatarDeclaredFormat(bytes);
  if (format == null) throw const FormatException('Unsupported avatar image');
  return {
    'declared_format': format,
    'expected_size_bytes': bytes.length,
    'expected_sha256': sha256.convert(bytes).toString(),
  };
}

Map<String, Object?> avatarCompleteBody({required int expectedRevision, required Uint8List bytes}) {
  if (expectedRevision < 1) throw const FormatException('Missing profile revision');
  avatarIntentBody(bytes);
  return {'expected_revision': expectedRevision, 'image_base64': base64Encode(bytes)};
}

/// Creates an intent, then completes it with the same bytes. A rejected image never posts.
Future<void> publishAvatarBytes({
  required Uint8List bytes,
  required int expectedRevision,
  required Future<Object?> Function(String path, Map<String, Object?> body) post,
}) async {
  final created = await post('/api/v1/users/me/avatar-upload-intents', avatarIntentBody(bytes));
  if (created is! Map || created['id'] is! String || (created['id'] as String).isEmpty) {
    throw const FormatException('Invalid avatar intent');
  }
  await post(
    '/api/v1/users/me/avatar-upload-intents/${created['id']}/complete',
    avatarCompleteBody(expectedRevision: expectedRevision, bytes: bytes),
  );
}

Future<Uint8List> readOwnerAvatar({
  required Future<Uint8List> Function(Map<String, String> headers) download,
  required Future<T> Function<T>(Future<T> Function(Map<String, String> headers) action) authorize,
}) => authorize(download);

Future<void> publishOwnerAvatar({
  required Uint8List bytes,
  required int expectedRevision,
  required Future<Object?> Function(
    String path,
    Map<String, Object?> body,
    Map<String, String> headers,
  )
  post,
  required Future<T> Function<T>(Future<T> Function(Map<String, String> headers) action) authorize,
}) {
  return publishAvatarBytes(
    bytes: bytes,
    expectedRevision: expectedRevision,
    post: (path, body) => authorize((headers) => post(path, body, headers)),
  );
}
