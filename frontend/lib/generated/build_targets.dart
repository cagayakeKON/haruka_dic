// GENERATED from config/build_targets.json; sha256:fe6d618744a7df12c7a6defc4a8809e3b82697291e382439de29f8c9298582d3. Do not edit.
abstract final class BuildTargets {
  static const developmentInstanceId = "haruka-local-dev";
  static const developmentApiBaseUrl = "http://127.0.0.1:8000";
  static const developmentApiBaseUrls = <String>[
    "http://127.0.0.1:8000",
    "http://localhost:8000",
    "http://10.0.2.2:8000",
  ];
  static const displayNames = <String, String>{"dev": "Haruka Dev", "production": "Haruka"};
  static const applicationIds = <String, Map<String, String>>{
    "android": {"dev": "app.haruka.dictionary.dev", "production": "app.haruka.dictionary"},
    "windows": {"dev": "haruka.dictionary.dev", "production": "haruka.dictionary"},
  };
}
