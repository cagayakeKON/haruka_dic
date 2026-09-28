import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/features/settings/domain/avatar_upload.dart';

void main() {
  test('jpeg, png, and webp are declared from magic bytes', () {
    expect(avatarDeclaredFormat(_bytes([0xff, 0xd8, 0xff, 1, 2, 3, 4, 5, 6, 7, 8, 9])), 'jpeg');
    expect(avatarDeclaredFormat(_bytes([0x89, 0x50, 0x4e, 0x47, 1, 2, 3, 4, 5, 6, 7, 8])), 'png');
    final webp = Uint8List(12);
    webp.setRange(0, 4, ascii.encode('RIFF'));
    webp.setRange(8, 12, ascii.encode('WEBP'));
    expect(avatarDeclaredFormat(webp), 'webp');
    expect(avatarDeclaredFormat(_bytes(ascii.encode('GIF89aGIF89a'))), isNull);
    expect(avatarDeclaredFormat(Uint8List(avatarMaxInputBytes + 1)), isNull);
  });

  test('intent uses the raw digest and complete stays standard base64 json', () {
    final bytes = _bytes([0xff, 0xd8, 0xff, 9, 8, 7, 6, 5, 4, 3, 2, 1]);
    expect(avatarIntentBody(bytes), {
      'declared_format': 'jpeg',
      'expected_size_bytes': bytes.length,
      'expected_sha256': sha256.convert(bytes).toString(),
    });
    final complete = avatarCompleteBody(expectedRevision: 3, bytes: bytes);
    expect(complete['image_base64'], base64Encode(bytes));
    expect((complete['image_base64'] as String).startsWith('data:'), isFalse);
    expect(() => avatarIntentBody(_bytes(ascii.encode('GIF89aGIF89a'))), throwsFormatException);
  });

  test('an unsupported image does not create an upload intent', () async {
    final posts = <String>[];
    await expectLater(
      publishAvatarBytes(
        bytes: _bytes(ascii.encode('GIF89aGIF89a')),
        expectedRevision: 2,
        post: (path, body) async {
          posts.add(path);
          return {'id': 'intent'};
        },
      ),
      throwsFormatException,
    );
    expect(posts, isEmpty);
  });

  test('publish posts the intent and then the same bytes', () async {
    final bytes = _bytes([0xff, 0xd8, 0xff, 1, 1, 1, 1, 1, 1, 1, 1, 1]);
    final calls = <(String, Map<String, Object?>)>[];
    await publishAvatarBytes(
      bytes: bytes,
      expectedRevision: 4,
      post: (path, body) async {
        calls.add((path, body));
        return {'id': '11111111-1111-4111-8111-111111111111'};
      },
    );
    expect(calls[0].$1, '/api/v1/users/me/avatar-upload-intents');
    expect(calls[1].$1, contains('/complete'));
    expect(calls[1].$2['expected_revision'], 4);
    expect(calls[1].$2['image_base64'], base64Encode(bytes));
  });

  test('private read and publish keep the session guard headers', () async {
    final seen = <String, String>{};
    await readOwnerAvatar(
      download: (headers) async {
        seen.addAll(headers);
        return Uint8List(0);
      },
      authorize: <T>(action) => action({'Authorization': 'Bearer secret'}),
    );
    expect(seen['Authorization'], 'Bearer secret');

    Map<String, String>? writeHeaders;
    final jpeg = _bytes([0xff, 0xd8, 0xff, 1, 1, 1, 1, 1, 1, 1, 1, 1]);
    await publishOwnerAvatar(
      bytes: jpeg,
      expectedRevision: 2,
      authorize: <T>(action) => action({'X-CSRF-Token': 'csrf'}),
      post: (path, body, headers) async {
        writeHeaders = headers;
        return {'id': '11111111-1111-4111-8111-111111111111'};
      },
    );
    expect(writeHeaders?['X-CSRF-Token'], 'csrf');
  });
}

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);
