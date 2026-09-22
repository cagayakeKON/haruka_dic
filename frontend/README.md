# Haruka 前端

阶段 1 的 B0 前端工程。单个 Flutter 工程包含 Windows、Web、Android 宿主、紧凑/宽屏应用壳、公开配置校验和中文 ARB 本地化。环境页可显式检查真实后端就绪状态；主页明确展示未开放业务。没有账号、材料数据、缓存或模型调用，不代表 B1/B2 已交付。

使用 [工具链清单](../tools/toolchain.json) 的 Flutter 3.47.3（revision `e8113bf45620cbeb8aff64947ee4c93e16adb4cf`）和 Dart 3.13.3，依赖提交在 `pubspec.lock`。Dio 5.11.1 是唯一 HTTP 传输，按实例创建并关闭，页面只消费类型化结果，不自动重试。账号作用域认证、业务控制器和完整遥测随后续切片接入，当前不创建空模块。

## 启动

从本目录运行。首次执行 `flutter pub get --enforce-lockfile`。根目录的 `scripts/dev.py` 提供统一入口，以下命令便于单独调试前端。本文Python命令需要工具清单的Python3.13.6；本机PATH为3.9时，请按 [开发指南](../docs/engineering/development.md) 用仓库uv启动指定Python。

```powershell
flutter run -d chrome --web-port=5173 --dart-define=HARUKA_ENV=dev
flutter run -d windows --dart-define=HARUKA_ENV=dev
flutter run -d emulator-5554 --flavor dev --dart-define=HARUKA_ENV=dev --dart-define=HARUKA_API_BASE_URL=http://10.0.2.2:8000
```

Android 的设备 ID 以 `flutter devices` 为准。模拟器地址必须显式传入，不自动把回环地址或缺失配置替换为生产服务。

公开配置的唯一来源为 [build_targets.json](config/build_targets.json)：

| 参数 | dev | production |
| --- | --- | --- |
| `HARUKA_ENV` | 默认 `dev` | 显式 `production` |
| `HARUKA_INSTANCE_ID` | 默认 `haruka-local-dev`，只接受该隔离实例 | 必填且不能为开发实例 |
| `HARUKA_API_BASE_URL` | Windows/Web 默认 `http://127.0.0.1:8000`；Android 显式传入清单内的地址 | 必填 HTTPS Origin，拒绝凭据、查询参数、路径和回环地址 |

配置只包含公开身份，不接收密码、Token、供应商 Key。无效配置显示不可用页，不发起请求、不回退其他服务。Android flavor 必须与环境一致，dev 与 production 使用不同 applicationId。Windows 区分窗口标题与 AppUserModelID；两环境的文件名均为 `haruka.exe`，最终安装格式、安装目录、签名及升级隔离尚未验收。Android dev release 仅使用开发签名，production 不配置发布签名。

路由 `/` 与 `/environment` 为只读壳；`/admin` 仅在 Web 编译时注册为未开放页，原生深链进入不可用页。Web 使用路径 URL，需要服务器将页面深链回退到 SPA；API 与缺失静态资源不得回退 HTML，正式代理规则由部署切片提供。Web 开发 Origin 为 `http://localhost:5173`。

布局阈值由 `lib/core/layout/adaptive_policy.dart` 单一维护：小于 600 使用底部导航、600～1023 使用窄侧栏、1024 起使用宽侧栏。窗口变化保留当前路由。支持 Tab/Enter 导航及 Alt+1/Alt+2；控件的语义名称保留中文，不用技术 ID 替代。

## 生成与检查

UI 标识来自 [ui_test_ids.json](config/ui_test_ids.json)。Key 与 Semantics.identifier 共用生成常量，Web 正常启动持有 SemanticsHandle；测试检查标识唯一、名称与点击动作。生成脚本同时处理公开配置、Windows 宿主身份、后端错误目录/ARB 对照及 Flutter 本地化。当前集中手写 DTO 过渡和生成器失败证据见 [Dart 原型](../tools/codegen/dart-api/README.md)：只允许到 B1，正式 schema 摘要变化会要求重新审查消费者。

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

随后在 `tools/e2e/` 执行 `npm ci --ignore-scripts`、`npx --no-install playwright install chromium`、`npm run check` 和 `npm test`。浏览器版本由 Playwright 锁控制；runner 自建 5174 端口的隔离静态服务，拒绝复用已占用服务，结束后释放。页面对象读取同一 UI 注册表，先聚焦 Flutter 真实语义 input 再逐键输入，不用坐标点击；无截图、trace、HAR 或登录状态存档。

真实健康页联调使用正式 `lib/main.dart`，由根开发入口显式启动 API `127.0.0.1:18080` 和 Web `localhost:5173` 后，在 `tools/e2e/` 执行 `npx --no-install playwright test --config live.config.ts`。备用18080已登记在公开配置源，适用于默认8000被系统保留或占用的机器，不更改系统保留端口。测试点击“检查连接”，验证真实响应、CORS与DTO消费，重排后不重复请求；它不负责启动、接管或停止外部服务，每次报告写入新的 `artifacts/e2e/live-<UUID>/`。

Android 的真实键盘/系统返回补充：在本任务专用模拟器启动 `flutter run -d emulator-5556 --flavor dev --target=test_support/main.dart --dart-define=HARUKA_ENV=dev --no-resident` 后，执行 `python tool/android_controls.py --device emulator-5556 --output ../artifacts/frontend/android-native.json`。设备 ID 需对应本任务独占模拟器；脚本通过已注册 resource-id 派生当前控件位置，拒绝其他前台应用，恢复修改的 IME 设置并删除临时层级文件。它不使用生产数据或认证旁路，且不代表所有 Android 输入法或真机性能已验收。

每次原生验证必须选择新的报告文件；既有通过/失败证据不覆盖。报告先标记运行中，IME恢复和临时文件清理全部完成后才发布通过；任一交互或清理失败会非零退出并写入安全失败事实，不包含adb原始输出。报告状态机的失败回归可离线执行 `python -m unittest discover -s tool -p test_android_controls.py -v`。
