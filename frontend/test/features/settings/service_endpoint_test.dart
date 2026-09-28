import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haruka/core/api/responses.dart';
import 'package:haruka/features/settings/data/service_endpoint_store_native.dart';
import 'package:haruka/features/settings/domain/service_endpoint.dart';
import 'package:haruka/features/settings/presentation/service_endpoint_form.dart';
import 'package:haruka/generated/l10n/app_localizations.dart';

void main() {
  test('accepts an https origin and only declared development http', () {
    expect(
      parseServiceEndpoint('https://learn.example', allowDevelopmentHttp: false),
      Uri.parse('https://learn.example'),
    );
    expect(
      parseServiceEndpoint('https://user:pass@learn.example', allowDevelopmentHttp: false),
      isNull,
    );
    expect(parseServiceEndpoint('https://learn.example/?x=1', allowDevelopmentHttp: false), isNull);
    expect(
      parseServiceEndpoint('https://learn.example/#frag', allowDevelopmentHttp: false),
      isNull,
    );
    expect(parseServiceEndpoint('https://learn.example/api', allowDevelopmentHttp: false), isNull);
    expect(parseServiceEndpoint('http://learn.example', allowDevelopmentHttp: true), isNull);
    expect(parseServiceEndpoint('http://127.0.0.1:18080', allowDevelopmentHttp: false), isNull);
    expect(
      parseServiceEndpoint('http://127.0.0.1:18080', allowDevelopmentHttp: true),
      Uri.parse('http://127.0.0.1:18080'),
    );
  });

  test('meta probe sends no authorization or cookie', () async {
    final adapter = _CaptureAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://learn.example'))..httpClientAdapter = adapter;
    final probe = await probeServiceEndpoint(Uri.parse('https://learn.example'), client: dio);
    expect(probe.meta.instanceId, 'learn-west');
    final names = adapter.headers.keys.map((key) => key.toLowerCase());
    expect(names, isNot(contains('authorization')));
    expect(names, isNot(contains('cookie')));
    dio.close();
  });

  test('a failed new connection restores the origin and does not restore a session', () async {
    final order = <String>[];
    Uri current = Uri.parse('https://old.example');
    var instance = 'old-instance';
    var restoredSession = false;
    await expectLater(
      commitInstanceSwitch(
        signedIn: true,
        stopOldActions: () => order.add('stop'),
        resumeActions: () => order.add('resume'),
        signOut: () async => order.add('signOut'),
        clearLocalScope: () async => order.add('clear'),
        retarget: (endpoint, id) {
          order.add('retarget:$id');
          current = endpoint;
          instance = id;
        },
        bindInstance: (endpoint, id) => order.add('bind:$id'),
        previousEndpoint: current,
        previousInstanceId: instance,
        probe: ServiceProbe(
          endpoint: Uri.parse('https://new.example'),
          meta: const MetaRead(instanceId: 'new-instance', apiVersion: 'v1', release: '1'),
        ),
        verify: () async {
          order.add('verify');
          throw StateError('down');
        },
      ),
      throwsStateError,
    );
    expect(order, [
      'stop',
      'signOut',
      'clear',
      'retarget:new-instance',
      'bind:new-instance',
      'verify',
      'retarget:old-instance',
      'bind:old-instance',
      'resume',
    ]);
    expect(current, Uri.parse('https://old.example'));
    expect(instance, 'old-instance');
    expect(restoredSession, isFalse);
  });

  test('remote revoke failure still adopts the probed instance', () async {
    final order = <String>[];
    final result = await commitInstanceSwitch(
      signedIn: true,
      stopOldActions: () => order.add('stop'),
      resumeActions: () => order.add('resume'),
      signOut: () async => throw StateError('revoke'),
      clearLocalScope: () async => order.add('clear'),
      retarget: (endpoint, id) => order.add('retarget:$id'),
      bindInstance: (endpoint, id) => order.add('bind:$id'),
      previousEndpoint: Uri.parse('https://old.example'),
      previousInstanceId: 'old-instance',
      probe: ServiceProbe(
        endpoint: Uri.parse('https://new.example'),
        meta: const MetaRead(instanceId: 'new-instance', apiVersion: 'v1', release: '1'),
      ),
      verify: () async => order.add('verify'),
    );
    expect(result.revokeFailed, isTrue);
    expect(order, [
      'stop',
      'clear',
      'retarget:new-instance',
      'bind:new-instance',
      'verify',
      'resume',
    ]);
  });

  test('a failed probe does not sign out or retarget', () async {
    var signedOut = false;
    var retargeted = false;
    final controller = _controller(
      probe: (endpoint, {client}) async => throw StateError('down'),
      signOut: () async => signedOut = true,
      retarget: (endpoint, instanceId) => retargeted = true,
    );
    await controller.probeAddress('https://learn.example');
    expect(signedOut, isFalse);
    expect(retargeted, isFalse);
    expect(controller.pending, isNull);
    expect(controller.failure, 'probe');
    controller.dispose();
  });

  test('web does not probe or change origin', () async {
    var probed = false;
    final controller = _controller(
      canSwitch: false,
      probe: (endpoint, {client}) async {
        probed = true;
        throw StateError('unused');
      },
    );
    await controller.probeAddress('https://other.example');
    expect(await controller.adopt(), isFalse);
    expect(probed, isFalse);
    controller.dispose();
  });

  test('a confirmed endpoint is reloaded and a tampered address is ignored', () async {
    final directory = await Directory.systemTemp.createTemp('haruka-endpoint');
    final store = PlatformServiceEndpointStore(directoryPath: directory.path);
    await store.save(Uri.parse('https://learn.example'), 'learn-west');
    final loaded = await store.read(allowDevelopmentHttp: false);
    expect(loaded?.endpoint, Uri.parse('https://learn.example'));
    expect(loaded?.instanceId, 'learn-west');
    await File('${directory.path}${Platform.pathSeparator}haruka-service-endpoint.json')
        .writeAsString('{"endpoint":"http://learn.example","instance_id":"learn-west"}');
    expect(await store.read(allowDevelopmentHttp: false), isNull);
    await directory.delete(recursive: true);
  });

  testWidgets('web shows the fixed deployment and no address editor', (tester) async {
    final controller = _controller(canSwitch: false);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(body: ServiceEndpointForm(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Web 使用当前部署，不能在应用内更换服务地址。'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    controller.dispose();
  });

  testWidgets('editing or reopening the address form clears stale probe failure', (tester) async {
    final controller = _controller(probe: (endpoint, {client}) async => throw StateError('down'));
    Widget form(Key key) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: ServiceEndpointForm(key: key, controller: controller),
      ),
    );

    await tester.pumpWidget(form(const ValueKey('first')));
    await tester.tap(find.text('检查连接'));
    await tester.pumpAndSettle();
    expect(controller.failure, 'probe');
    expect(find.text('未能连接该服务。'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'https://other.example');
    await tester.pump();
    expect(controller.failure, isNull);
    expect(controller.attempted, isFalse);
    expect(find.text('未能连接该服务。'), findsNothing);

    await tester.tap(find.text('检查连接'));
    await tester.pumpAndSettle();
    expect(find.text('未能连接该服务。'), findsOneWidget);
    await tester.pumpWidget(form(const ValueKey('reopened')));
    await tester.pump();
    expect(controller.failure, isNull);
    expect(controller.attempted, isFalse);
    expect(find.text('未能连接该服务。'), findsNothing);
    controller.dispose();
  });

  testWidgets('a probe completed after reopening cannot publish an old result', (tester) async {
    final oldProbe = Completer<ServiceProbe>();
    final currentProbe = Completer<ServiceProbe>();
    var calls = 0;
    final controller = _controller(
      probe: (endpoint, {client}) => calls++ == 0 ? oldProbe.future : currentProbe.future,
    );
    Widget form(Key key) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: ServiceEndpointForm(key: key, controller: controller),
      ),
    );
    ServiceProbe result(String instanceId) => ServiceProbe(
      endpoint: Uri.parse('https://learn.example'),
      meta: MetaRead(instanceId: instanceId, apiVersion: 'v1', release: '1'),
    );

    await tester.pumpWidget(form(const ValueKey('first')));
    await tester.tap(find.text('检查连接'));
    await tester.pump();
    expect(controller.busy, isTrue);

    await tester.pumpWidget(form(const ValueKey('reopened')));
    expect(controller.pending, isNull);
    oldProbe.complete(result('stale-instance'));
    await tester.pumpAndSettle();
    expect(controller.busy, isFalse);
    expect(controller.pending, isNull);
    expect(controller.failure, isNull);
    expect(find.text('退出并使用此服务'), findsNothing);

    await tester.tap(find.text('检查连接'));
    await tester.pump();
    currentProbe.complete(result('current-instance'));
    await tester.pumpAndSettle();
    expect(controller.pending?.meta.instanceId, 'current-instance');
    expect(find.text('退出并使用此服务'), findsOneWidget);
    controller.dispose();
  });
}

ServiceEndpointController _controller({
  bool canSwitch = true,
  Future<ServiceProbe> Function(Uri endpoint, {Dio? client})? probe,
  Future<void> Function()? signOut,
  void Function(Uri endpoint, String instanceId)? retarget,
}) => ServiceEndpointController(
  canSwitch: canSwitch,
  allowDevelopmentHttp: false,
  currentEndpoint: () => Uri.parse('https://learn.example'),
  currentInstance: () => 'learn-west',
  signedIn: () => false,
  probe: probe ?? ((endpoint, {client}) async => throw StateError('unused')),
  signOut: signOut ?? () async {},
  clearCache: () async {},
  retarget: retarget ?? (endpoint, instanceId) {},
  bindInstance: (endpoint, instanceId) {},
  stopOldActions: () {},
  resumeActions: () {},
  verify: () async {},
);

final class _CaptureAdapter implements HttpClientAdapter {
  Map<String, dynamic> headers = const {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    headers = options.headers;
    return ResponseBody.fromString(
      jsonEncode({
        'data': {'instance_id': 'learn-west', 'api_version': 'v1', 'release': '1'},
        'meta': {'request_id': '00000000-0000-4000-8000-000000000001'},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
