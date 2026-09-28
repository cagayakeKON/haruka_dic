import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/features/agent/application/query_images.dart';

void main() {
  final imageBytes = File('test/fixtures/preview/query_image.png').readAsBytesSync();

  test('valid PNG is decoded and retains bytes for local preview', () async {
    final image = await validateQueryImage(RawQueryImage(name: 'photo.png', bytes: imageBytes));
    expect(image.mimeType, 'image/png');
    expect(image.width, 2);
    expect(image.height, 2);
    expect(image.bytes, imageBytes);
  });

  test('non-image and corrupt PNG cannot become an attachment', () async {
    await expectLater(
      validateQueryImage(RawQueryImage(name: 'photo.png', bytes: Uint8List.fromList([1, 2, 3]))),
      throwsA(
        isA<QueryImageException>().having(
          (error) => error.problem,
          'problem',
          QueryImageProblem.unsupported,
        ),
      ),
    );
    await expectLater(
      validateQueryImage(RawQueryImage(name: 'broken.png', bytes: imageBytes.sublist(0, 16))),
      throwsA(
        isA<QueryImageException>().having(
          (error) => error.problem,
          'problem',
          QueryImageProblem.invalid,
        ),
      ),
    );
  });

  test('oversized input is rejected before image decode', () async {
    await expectLater(
      validateQueryImage(
        RawQueryImage(name: 'large.png', bytes: Uint8List(queryImageMaxBytes + 1)),
      ),
      throwsA(
        isA<QueryImageException>().having(
          (error) => error.problem,
          'problem',
          QueryImageProblem.tooLarge,
        ),
      ),
    );
  });
}
