# Haruka 前端

单个 Flutter 工程包含 Windows、Web、Android 宿主、紧凑/宽屏布局、公开配置校验和中文 ARB 本地化。环境页可显式检查真实后端就绪状态。阶段1已完成，包含账号与收藏、本人资料/头像/设置、身份治理、本人模型凭据和任务；当前按[M1实现方案](../docs/delivery/material-import-implementation.md)接入真实材料导入、材料库与通知。真实模型测试三次 `KEY_REJECTED` 已获用户接受，不再验证模型，模型可用性仍未验证。正式业务按Web和Android必要路径验收，找回密码和前端日志只验Web，不安排Windows原生运行测试。完整材料阅读、导入、NLP、AI生成和TTS继续按后续切片交付；现有mock与参考学习流程不代表这些能力已实现。

2026-09-26 [B0设计对齐](../docs/delivery/reviews/2026-09-26-b0-design-alignment.md)记录当时的账号/角色/授权结构、权限目录与基础壳验收；原 B0 完整矩阵保留历史候选身份，不代替当前切片的最终验收。

使用 [工具链清单](../tools/toolchain.json) 的 Flutter 3.47.3（revision `e8113bf45620cbeb8aff64947ee4c93e16adb4cf`）和 Dart 3.13.3，依赖提交在 `pubspec.lock`。Dio 5.11.1 是 HTTP 传输；页面经账号作用域控制器和仓储消费类型化结果。认证刷新、幂等收藏重试及遥测上传分别遵守各自明确的重试边界。

## 启动

从本目录运行。首次执行 `flutter pub get --enforce-lockfile`。根目录的 `scripts/dev.py` 提供统一入口，以下命令便于单独调试前端。本文Python命令需要工具清单的Python3.13.6；本机PATH为3.9时，请按 [开发指南](../docs/engineering/development.md) 用仓库uv启动指定Python。

```powershell
flutter run -d chrome --web-port=5173 --dart-define=HARUKA_ENV=dev
flutter run -d windows --dart-define=HARUKA_ENV=dev
flutter run -d emulator-5554 --flavor dev --dart-define=HARUKA_ENV=dev --dart-define=HARUKA_API_BASE_URL=http://10.0.2.2:8000
```

Android 的设备 ID 以 `flutter devices` 为准。模拟器地址必须显式传入，不自动把回环地址或缺失配置替换为生产服务。

固定样例数据的前端预览使用独立入口 `lib/main_preview.dart`，仅用于开发和界面对照。正式入口 `lib/main.dart` 始终按公开环境配置装配应用；`HARUKA_MOCK` 不再切换入口。Web 和 Android 预览可分别运行或构建：

```powershell
flutter run -d chrome --web-port=8772 --target=lib/main_preview.dart
flutter run -d emulator-5554 --flavor dev --target=lib/main_preview.dart
flutter build web --target=lib/main_preview.dart --output=build/web-preview --no-web-resources-cdn
```

预览构建输出到独立目录，避免覆盖正式 Web 构建。预览样例不连接正式业务 API，也不作为实际账号、授权或持久化的验收证据。

公开配置的唯一来源为 [build_targets.json](config/build_targets.json)：

| 参数 | dev | production |
| --- | --- | --- |
| `HARUKA_ENV` | 默认 `dev` | 显式 `production` |
| `HARUKA_INSTANCE_ID` | 默认 `haruka-local-dev`；隔离测试仅接受 `haruka-test-` 加 32 位小写十六进制且与服务 `/meta` 精确匹配 | 必填且不能为开发/测试实例 |
| `HARUKA_API_BASE_URL` | Windows/Web 默认 `http://127.0.0.1:8000`；Android 显式传入清单内的地址。测试实例仅允许清单列出的同源Web HTTP/HTTPS、Windows回环和Android模拟器地址；本轮开发实操使用 `http://localhost:18443` | 必填 HTTPS Origin，拒绝凭据、查询参数、路径和回环地址 |

配置只包含公开身份，不接收密码、Token、供应商 Key。无效配置显示不可用页，不发起请求、不回退其他服务。Android flavor 必须与环境一致，dev 与 production 使用不同 applicationId。Windows 区分窗口标题与 AppUserModelID；两环境的文件名均为 `haruka.exe`，最终安装格式、安装目录、签名及升级隔离尚未验收。Android dev release 仅使用开发签名，production 不配置发布签名。

基础路由 `/` 与 `/environment` 保留只读壳。用户端现有账号、本人安全、已发布材料参考阅读与收藏路由；管理登录与注册策略仅在 Web 注册，原生管理路径不可用。Web 使用路径 URL，邮箱链接 fragment 在动作确认前清除；承载方须将页面深链回退到 SPA，而 API 与缺失静态资源不得回退 HTML。隔离集成运行以同源 HTTPS 代理承载 Web 与 API；普通开发 Origin 为 `http://localhost:5173`。

应用壳布局阈值由 `lib/core/layout/adaptive_policy.dart` 单一维护：小于 600 使用底部导航、600～1023 使用窄侧栏、1024 起使用宽侧栏。账号与参考学习页面按实际窄屏/宽屏内容另行排版；窗口变化保留当前路由和账号作用域状态。Tab/Enter 与 Alt+1/Alt+2 保留既有键盘操作。

## 生成与检查

UI 技术定位 ID 来自 [ui_test_ids.json](config/ui_test_ids.json)。Key 与 `Semantics.identifier` 共用生成常量，Web 为功能自动化定位持有 SemanticsHandle；测试验证真实点击、输入与页面结果，不把技术 ID 当作用户文案。生成脚本同时处理公开配置、Windows 宿主身份、后端错误目录/ARB 对照及 Flutter 本地化。当前集中手写 DTO 过渡和生成器失败证据见 [Dart 原型](../tools/codegen/dart-api/README.md)：正式 schema 摘要变化必须重新审查消费者。

```powershell
python tool/generate.py --write
python tool/generate.py --check
python -m unittest discover -s tool -p test_*.py -v
dart format --output=none --set-exit-if-changed lib test integration_test test_driver test_support
flutter analyze --fatal-infos --fatal-warnings
flutter test test --reporter expanded
```

`--check` 在临时目录调用锁定 SDK 生成并比较，不修改受管文件；`--write --output-dir <目录>` 可导出全部目标。不要手改 `lib/generated`；未知生成文件会使检查失败。

三端壳集成入口：

```powershell
flutter test integration_test/shell_test.dart -d windows --dart-define=HARUKA_ENV=dev
flutter test integration_test/shell_test.dart -d emulator-5554 --flavor dev --dart-define=HARUKA_ENV=dev --dart-define=HARUKA_API_BASE_URL=http://10.0.2.2:8000
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/shell_test.dart -d web-server --browser-name=chrome --headless --web-port=5173 --dart-define=HARUKA_ENV=dev
```

Web drive 需要与 Chrome 匹配的 ChromeDriver 在端口 4444 运行；当前机器 Chrome/ChromeDriver 为 153.0.8010.50。锁定 SDK 上使用 `web-server` 驱动入口，普通 `chrome` 入口曾停在调试连接阶段，未记为通过。Android 集成测试结束后，当前 SDK 的卸载动作使用 namespace，需按清单确认并清理本次安装的 dev 包 `app.haruka.dictionary.dev`，不卸载 production 包。

测试入口的启动与导航证据不等于正式安装包、真实账号、原生文件/音频、离线能力或管理授权验收。实际阶段结果与限制由 [脚手架里程碑](../docs/delivery/milestones/scaffold.md) 及对应审查记录归档。

## 控件和浏览器原型

`test_support/main.dart` 是单独编译的测试入口，不被生产 `lib/main.dart` 导入。它提供输入/禁用按钮/确认对话框/虚拟列表/路由刷新，覆盖用户和管理布局原型；不提供任何业务 API、认证或持久写入旁路。共享输入控制器与带身份的表单子树跨断点保留草稿、选区和焦点。

```powershell
flutter test integration_test/controls_test.dart -d windows --dart-define=HARUKA_ENV=dev
flutter test integration_test/controls_test.dart -d emulator-5554 --flavor dev --dart-define=HARUKA_ENV=dev --dart-define=HARUKA_API_BASE_URL=http://10.0.2.2:8000
flutter build web --target=test_support/main.dart --output=build/web-controls --no-web-resources-cdn --dart-define=HARUKA_ENV=dev
```

随后在 `tools/e2e/` 执行 `npm ci --ignore-scripts`、`npx --no-install playwright install chromium`、`npm run check` 和 `npm test`。浏览器版本由 Playwright 锁控制；控件原型 runner 自建 5174 端口的隔离静态服务，拒绝复用已占用服务，结束后释放。页面对象读取同一 UI 注册表，聚焦 Flutter 实际编辑 input 后逐键输入；原型用例不依赖坐标点击，且不保存截图、trace、HAR 或登录状态。

真实健康页联调使用正式 `lib/main.dart`，由根开发入口显式启动 API `127.0.0.1:18080` 和 Web `localhost:5173` 后，在 `tools/e2e/` 执行 `npx --no-install playwright test --config live.config.ts`。备用18080已登记在公开配置源，适用于默认8000被系统保留或占用的机器，不更改系统保留端口。测试点击“检查连接”，验证真实响应、CORS与DTO消费，重排后不重复请求；它不负责启动、接管或停止外部服务，每次报告写入新的 `artifacts/e2e/live-<UUID>/`。

Android 的真实键盘/系统返回补充：在本任务专用模拟器启动 `flutter run -d emulator-5556 --flavor dev --target=test_support/main.dart --dart-define=HARUKA_ENV=dev --no-resident` 后，执行 `python tool/android_controls.py --device emulator-5556 --output ../artifacts/frontend/android-native.json`。设备 ID 需对应本任务独占模拟器；脚本通过已注册 resource-id 派生当前控件位置，拒绝其他前台应用，恢复修改的 IME 设置并删除临时层级文件。它不使用生产数据或认证旁路，且不代表所有 Android 输入法或真机性能已验收。

每次原生验证必须选择新的报告文件；既有通过/失败证据不覆盖。报告先标记运行中，IME恢复和临时文件清理全部完成后才发布通过；任一交互或清理失败会非零退出并写入安全失败事实，不包含adb原始输出。报告状态机的失败回归可离线执行 `python -m unittest discover -s tool -p test_android_controls.py -v`。
