import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/api_client.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/core/api/wire.dart';
import 'package:haruka/core/config/app_config.dart';

import '../test_support/compatibility.dart';
import '../test_support/sample_adapter.dart';

void main() {
  final samples = wireObject(
    jsonDecode(File('../tools/codegen/dart-api/fixtures/samples.json').readAsStringSync()),
  );
  final config = AppConfig.parse(platform: AppPlatform.windows, environment: 'dev');

  test('API-09 Pydantic output preserves UUID UTC exact Decimal and optional tri-state', () {
    final missing = SuccessResponse<CompatibilityRead>.fromJson(
      samples['success_missing'],
      CompatibilityRead.fromJson,
    );
    final nullable = SuccessResponse<CompatibilityRead>.fromJson(
      samples['success_null'],
      CompatibilityRead.fromJson,
    );
    final present = SuccessResponse<CompatibilityRead>.fromJson(
      samples['success_value'],
      CompatibilityRead.fromJson,
    );
    expect(missing.meta.requestId, '018f1234-1234-7123-8123-123456789abc');
    expect(missing.data.resourceId, '018f1234-5678-7123-8123-123456789abc');
    expect(missing.data.createdAt.toIso8601String(), '2026-09-22T01:02:03.123456Z');
    expect(missing.data.exactAmount, '12345678901234567890.123456789');
    expect(missing.data.nullableOptional, isA<AbsentValue<String>>());
    expect(nullable.data.nullableOptional, isA<NullValue<String>>());
    expect((present.data.nullableOptional as PresentValue<String>).value, 'present');
    expect((missing.data.card as TextCard).text, '日本語 / English');
    expect((present.data.card as ChoiceCard).choices, ['A', 'B']);
  });

  test('API-09 pagination and forward compatibility preserve safe behavior', () {
    final page = PageResponse<CompatibilityRead>.fromJson(
      samples['page'],
      CompatibilityRead.fromJson,
    );
    expect(page.data.length, 2);
    expect(page.hasMore, isTrue);
    expect(page.nextCursor, 'cursor-2');
    expect(CompatibilityRead.fromJson(samples['unknown_enum']).status, CompatibilityStatus.unknown);
    final extended = Map<String, Object?>.of(wireObject(samples['unknown_enum']))
      ..['future_field'] = 123;
    expect(CompatibilityRead.fromJson(extended).status, CompatibilityStatus.unknown);
    final broken = {...extended}..remove('resource_id');
    expect(() => CompatibilityRead.fromJson(broken), throwsFormatException);
    expect(() => CompatibilityCard.fromJson({'kind': 'future_card'}), throwsFormatException);
    final empty = {
      'data': <Object?>[],
      'meta': {'request_id': page.meta.requestId, 'has_more': false, 'next_cursor': null},
    };
    expect(
      PageResponse<CompatibilityRead>.fromJson(empty, CompatibilityRead.fromJson).data,
      isEmpty,
    );
    wireObject(empty['meta'])['next_cursor'] = 'inconsistent';
    expect(
      () => PageResponse<CompatibilityRead>.fromJson(empty, CompatibilityRead.fromJson),
      throwsFormatException,
    );
  });

  test('API-09 Python canonicalizes Decimal exponents without precision loss', () {
    final expected = <String, String>{
      '1E+3': '1000',
      '1E-7': '0.0000001',
      '-1E-7': '-0.0000001',
      '0E-10': '0.0000000000',
      '-0.00': '-0.00',
      '12345678901234567890.123456789': '12345678901234567890.123456789',
    };
    final boundaries = samples['decimal_boundaries']! as List<Object?>;
    expect(boundaries.length, expected.length);
    for (final value in boundaries) {
      final boundary = wireObject(value);
      final output = SuccessResponse<CompatibilityRead>.fromJson(
        boundary['output'],
        CompatibilityRead.fromJson,
      );
      expect(output.data.exactAmount, expected[boundary['input']]);
      expect(output.data.exactAmount.toLowerCase(), isNot(contains('e')));
    }
  });

  test('API-10 error fields conflict and unknown codes never expose remote messages', () {
    final error = ApiFailure.fromJson(samples['error']);
    expect(error.code, 'INPUT_INVALID');
    expect(error.fields.single.path, ['items', 0, 'text']);
    expect(error.fields.single.code, 'VALIDATION_TOO_LONG');
    expect(ApiFailure.fromJson(samples['conflict']).currentRevision, 7);
    final unknown = {
      'error': {'code': 'FUTURE_ERROR', 'message': 'private sentinel', 'retryable': true},
      'meta': {'request_id': error.meta!.requestId},
    };
    final failure = ApiFailure.fromJson(unknown);
    expect(failure.code, 'UNKNOWN_ERROR');
    expect(failure.toString(), isNot(contains('private sentinel')));
    expect(failure.fields, isEmpty);
    expect(() => ApiFailure.fromJson('<html>secret</html>'), throwsFormatException);
  });

  test('API-09 malformed wire types fail without lossy coercion', () {
    for (final value in [1.1, 'NaN', 'Infinity', '01.2']) {
      expect(() => wireDecimal(value), throwsFormatException);
    }
    expect(() => wireUuid('not-uuid'), throwsFormatException);
    expect(() => wireUtc('2026-09-22T01:00:00'), throwsFormatException);
    expect(() => wireUtc('2026-09-22T01:00:00+09:00'), throwsFormatException);
    expect(() => wireUtc('2026-02-30T01:00:00Z'), throwsFormatException);
    expect(() => HealthRead.fromJson({'status': 'future'}), throwsFormatException);
    expect(wireUtc('2026-09-22T01:00:00+00:00').isUtc, isTrue);
  });

  test('API client decodes once without retry and closes injected transport', () async {
    final adapter = SampleAdapter((options, _) async {
      expect(options.uri.toString(), 'http://127.0.0.1:8000/health/ready');
      expect(options.headers['Accept-Language'], 'zh-Hans');
      expect(options.followRedirects, isFalse);
      return ResponseBody.fromString(
        jsonEncode({
          'data': {'status': 'ok'},
          'meta': {'request_id': '018f1234-1234-7123-8123-123456789abc'},
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    });
    final api = ApiClient(config, adapter: adapter);
    expect((await api.checkReadiness()).data, isA<HealthRead>());
    expect(adapter.calls, 1);
    await expectLater(
      api.getJson('https://other.test/', HealthRead.fromJson),
      throwsA(isA<ApiFailure>()),
    );
    expect(adapter.calls, 1);
    api.close();
    expect(adapter.closed, isTrue);
  });

  test('API client failure envelopes and proxy HTML have safe typed fallbacks', () async {
    for (final (body, contentType, code) in [
      (jsonEncode(samples['error']), 'application/json', 'INPUT_INVALID'),
      ('<html>private sentinel</html>', 'text/html', 'INVALID_RESPONSE'),
    ]) {
      final adapter = SampleAdapter(
        (_, _) async => ResponseBody.fromString(
          body,
          502,
          headers: {
            Headers.contentTypeHeader: [contentType],
          },
        ),
      );
      final api = ApiClient(config, adapter: adapter);
      addTearDown(api.close);
      await expectLater(
        api.checkReadiness(),
        throwsA(
          isA<ApiFailure>()
              .having((error) => error.code, 'safe code', code)
              .having((error) => error.statusCode, 'HTTP status', 502)
              .having((error) => error.toString(), 'no body', isNot(contains('private sentinel'))),
        ),
      );
      expect(adapter.calls, 1);
    }
  });

  test('HTTP 401 and 403 remain visible when the error envelope cannot be trusted', () async {
    for (final (status, body, contentType, code) in [
      (
        401,
        jsonEncode({
          'error': {'code': 'FUTURE_ERROR', 'status_code': 200},
          'meta': {'request_id': '018f1234-1234-7123-8123-123456789abc'},
        }),
        'application/json',
        'UNKNOWN_ERROR',
      ),
      (403, '<html>private sentinel</html>', 'text/html', 'INVALID_RESPONSE'),
    ]) {
      final adapter = SampleAdapter(
        (_, _) async => ResponseBody.fromString(
          body,
          status,
          headers: {
            Headers.contentTypeHeader: [contentType],
          },
        ),
      );
      final api = ApiClient(config, adapter: adapter);
      addTearDown(api.close);
      await expectLater(
        api.checkReadiness(),
        throwsA(
          isA<ApiFailure>()
              .having((error) => error.code, 'safe code', code)
              .having((error) => error.statusCode, 'transport status', status)
              .having((error) => error.toString(), 'no body', isNot(contains('private sentinel'))),
        ),
      );
    }
  });

  test('API-09 204 binary download and raw upload preserve native transports', () async {
    final transport = wireObject(samples['transports']);
    final binary = wireObject(transport['binary']);
    final bytes = (binary['bytes']! as List<Object?>).cast<int>();
    final adapter = SampleAdapter((options, stream) async {
      if (options.method == 'GET') {
        return ResponseBody.fromBytes(
          bytes,
          200,
          headers: {
            Headers.contentTypeHeader: ['application/octet-stream'],
          },
        );
      }
      if (options.method == 'PUT') {
        expect(options.contentType, 'application/octet-stream');
        expect(await stream!.expand((chunk) => chunk).toList(), bytes);
      }
      return ResponseBody.fromString('', 204);
    });
    final api = ApiClient(config, adapter: adapter);
    addTearDown(api.close);
    await api.deleteEmpty('/compatibility/empty');
    expect(await api.download('/compatibility/binary'), bytes);
    await api.uploadBytes('/compatibility/upload', Uint8List.fromList(bytes));
  });

  test('API cancellation and connection failures cannot become readiness or retry', () async {
    final adapter = SampleAdapter(
      (options, _) async => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'private connection details',
      ),
    );
    final api = ApiClient(config, adapter: adapter);
    addTearDown(api.close);
    await expectLater(
      api.checkReadiness(),
      throwsA(isA<ApiFailure>().having((error) => error.code, 'code', 'NETWORK_UNAVAILABLE')),
    );
    final token = CancelToken()..cancel();
    await expectLater(
      api.checkReadiness(cancelToken: token),
      throwsA(isA<ApiFailure>().having((error) => error.code, 'code', 'CANCELLED')),
    );
    expect(adapter.calls, 1);
  });
}
