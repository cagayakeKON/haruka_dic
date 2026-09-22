// GENERATED from config/build_targets.json; sha256:7295f55862a95aa43d491e0026318261f40c6d071f1f198202b02ae4d0d18414. Do not edit.
abstract final class BuildTargets {
  static const developmentInstanceId = "haruka-local-dev";
  static const developmentApiBaseUrl = "http://127.0.0.1:8000";
  static const developmentApiBaseUrls = <String>[
    "http://127.0.0.1:8000",
    "http://localhost:8000",
    "http://10.0.2.2:8000",
    "http://127.0.0.1:18080",
    "http://localhost:18080",
    "http://10.0.2.2:18080",
  ];
  static const displayNames = <String, String>{"dev": "Haruka Dev", "production": "Haruka"};
  static const applicationIds = <String, Map<String, String>>{
    "android": {"dev": "app.haruka.dictionary.dev", "production": "app.haruka.dictionary"},
    "windows": {"dev": "haruka.dictionary.dev", "production": "haruka.dictionary"},
  };
}
