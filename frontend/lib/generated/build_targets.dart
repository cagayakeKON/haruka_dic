// GENERATED from config/build_targets.json; sha256:4146ccba53b399fa2794655703c44ca4c1ce59675ff0048b08fbe46e85612a0f. Do not edit.
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
  static const testInstancePattern = r"^haruka-test-[0-9a-f]{32}$";
  static const testApiBaseUrls = <String, List<String>>{
    "web": ["https://localhost:18443"],
    "windows": ["http://127.0.0.1:18081"],
    "android": ["http://10.0.2.2:18081"],
  };
  static const displayNames = <String, String>{"dev": "Haruka Dev", "production": "Haruka"};
  static const applicationIds = <String, Map<String, String>>{
    "android": {"dev": "app.haruka.dictionary.dev", "production": "app.haruka.dictionary"},
    "windows": {"dev": "haruka.dictionary.dev", "production": "haruka.dictionary"},
  };
}
