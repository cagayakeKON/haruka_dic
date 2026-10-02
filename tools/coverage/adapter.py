"""Unique-signature adapter for the independently verified Flutter 3.47.3 platform."""

from pathlib import Path

SDK_SHA256 = "ba42b469c2777ca7338dc64236ddb82693ca6794874ecb21fe318747b4d39885"
SDK_VERSION = "3.47.3"


def patched_source(original: bytes, helper: Path) -> bytes:
    content = original.decode("utf-8").replace("\r\n", "\n")
    replacements = [
        (
            "import 'dart:typed_data';",
            "import 'dart:typed_data';\nimport '" + helper.as_uri() + "';",
        ),
        (
            "final String fullPath = _fileSystem.path.fromUri(request.url);",
            "final String fullPath = request.url.path;",
        ),
        (
            "final String path = _fileSystem.path.fromUri(request.url);",
            "final String path = request.url.path;",
        ),
        ('window.testSelector = "$test";', "window.testSelector = ${jsonEncode(test)};"),
        (
            "    final completer = Completer<BrowserManager>();",
            "    final coverage = await OwnedCoverage.attach(chrome.chromeConnection, url);\n    final completer = Completer<BrowserManager>();",
        ),
        (
            "completer.complete(BrowserManager._(chrome, runtime, webSocket));",
            "completer.complete(BrowserManager._(chrome, runtime, webSocket).._ownedCoverage = coverage);",
        ),
        (
            "    void closeIframe() {",
            "    final suiteClose = AsyncMemoizer<void>();\n    Future<void> closeIframe() => suiteClose.runOnce(() async {\n      await _ownedCoverage?.capture(suiteID);",
        ),
        (
            "      _channel.sink.add(<String, Object>{'command': 'closeSuite', 'id': suiteID});\n    }",
            "      _channel.sink.add(<String, Object>{'command': 'closeSuite', 'id': suiteID});\n      _ownedCoverage?.event('suite-closed', suiteID);\n    });",
        ),
        (
            "      StreamTransformer<dynamic, dynamic>.fromHandlers(\n        handleDone: (EventSink<dynamic> sink) {\n          closeIframe();\n          sink.close();\n          onDone!();\n        },\n      ),",
            "      StreamTransformer<dynamic, dynamic>.fromBind((stream) async* {\n        try {\n          await for (final value in stream) {\n            yield value;\n          }\n        } finally {\n          try { await closeIframe(); } finally { await onDone!(); }\n        }\n      }),",
        ),
        (
            "    _channel.sink.add(<String, Object>{\n      'command': 'loadSuite',",
            "    await _ownedCoverage?.pending;\n    _ownedCoverage?.event('suite-load', suiteID);\n    _channel.sink.add(<String, Object>{\n      'command': 'loadSuite',",
        ),
        (
            "    } catch (_) {\n      closeIframe();",
            "    } catch (_) {\n      await closeIframe();",
        ),
        (
            "    return _closeMemoizer.runOnce(() {",
            "    return _closeMemoizer.runOnce(() async {\n      try { await _ownedCoverage?.close(); } catch (_) { await _browser.close(); rethrow; }",
        ),
        ("class BrowserManager {", "class BrowserManager {\n  OwnedCoverage? _ownedCoverage;"),
    ]
    for old, new in replacements:
        if content.count(old) != 1:
            raise ValueError("SDK adapter signature is missing or ambiguous")
        content = content.replace(old, new)
    return content.encode("utf-8")
