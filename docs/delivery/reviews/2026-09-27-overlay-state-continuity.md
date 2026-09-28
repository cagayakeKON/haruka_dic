# 弹层进出时的页面状态连续性

状态：2026-09-27，阶段1当前 Flutter 固定样例预览的局部修复，由 GPT-6 Sol 修改；以正在运行的 Web/Android 前端为基线。本记录不代表正式材料、收藏、查询或消息业务验收。

后续范围补充：本记录验证的是 `PopupRoute` 与真实页面导航的区别，没有覆盖 Flutter Web 的窗口焦点 `inactive/resumed` 链路。用户后续仍发现点击空白与词句弹层触发重载；该共同生命周期原因及小说阅读布局的补充修复见[双端视觉与交互优化记录](2026-09-27-frontend-visual-refinement.md#42-用户补充的阅读与焦点缺陷)。不得将下述局部结果解释为所有焦点路径已经修复。

用户发现打开材料详情对话框也会刷新整屏，并要求一起修复类似入口。根因是材料、收藏和消息页把 `ModalRoute.isCurrent` 从 `false` 恢复为 `true` 一律视为从其他页面返回；同一 Navigator 上的 dialog、bottom sheet 和弹出菜单同样改变该值，因而错误地关闭私有内容门闩并重复请求。查询页也用该值切换缓存结果可见性，弹层会释放显示 pin 并重新校验。手机材料详情另在打开对话框前调用默认查询的 `refresh(force: true)`，既清空当前列表，又可能丢失用户选中的类型/搜索范围。

现在每个 Navigator 各自观察顶层 `PageRoute`：真实页面进入、返回或替换触发可见性变更；只打开或关闭 `PopupRoute` 不触发材料、收藏、消息整页门禁，也不改变查询结果可见性。手机外层 Navigator、内层 GoRouter 和桌面 GoRouter 分别接线，断点重挂时清空旧导航堆栈。查询页作为对话框内容独立创建时仍保持可见；卸载时先移除仓储监听再释放可见性，避免通知已卸载的 State。账号/仓储源变化、筛选查询变化、真正页面返回、前台恢复及定时复核的既有权限边界保留：复核中仍隐藏未重新授权的私有行，失败或撤权不回显旧内容。

手机材料详情使用当前类型和搜索查询，并以 `preserveCurrent: true` 在后台复核。成功后要求仓储处于 ready、原卡片仍挂载，且 ID、类型、版本及过滤范围仍匹配才显示详情；请求抛错、版本变化或权限失效均提示材料不可读取。材料页真实返回时，恢复 viewport anchor 的卡片不重复播放 8px 入场位移，以保持原滚动位置；首次进入和主动切换分类的动效不变。通知条目点击材料属于真实导航动作，仍保留目标资源授权读取；已读提交与系统通知摘要逻辑未改。

独立审查与真实画面：Web 桌面词本选择框、材料三点菜单及小说排版对话框进出后，原列表或正文节点仍挂载；手机小说分类下打开/关闭详情、取消删除确认后，分类和首卡节点保持。[Web 最终材料详情](assets/overlay-state-continuity/web-final-material-dialog.png)及同目录前后 AX 节点留证。最终 dev preview APK 在 Android 模拟器冷启动后，独立审查者实点小说筛选→菜单→详情→系统返回、菜单外点关闭、词本入口与管理对话框取消、小说排版 sheet 返回：材料首卡仍在 `[53,501][1028,763]`，词本行与正文段落 bounds 不变；[Android 截图](assets/overlay-state-continuity/android-filtered-detail.png)、[词本入口](assets/overlay-state-continuity/android-notebook-nested-dialog.png)和[阅读排版](assets/overlay-state-continuity/android-reader-sheet.png)已保存。没有执行删除、保存或真实 AI 请求。Web 开发热重启时控制台曾有一次 `disposed EngineFlutterView` 事件，之后这些 UI 操作没有新增该错误；不把开发引擎事件记为业务路径通过或失败。

定点验证：`flutter test test/app/page_route_activity_test.dart test/features/library/material_catalog_widget_test.dart` 为 23/23（含详情刷新抛异常后拒绝旧详情）；`flutter test test/features/collections/collection_visibility_refresh_test.dart` 为 3/3；`flutter test test/features/notifications/notification_visibility_refresh_test.dart` 为 5/5；`flutter test test/features/agent/query_page_overlay_visibility_test.dart` 为 1/1，去重 32/32。用例覆盖弹层待刷新帧中同一 Element 与无额外读取、过滤详情与异常/版本拒绝、真实页面返回/前台恢复门禁、顶层页面越过 popup 的导航、Navigator 重挂、查询页在弹层覆盖时持续可见而在真实页面覆盖时暂停，以及材料返回位置 1px 严格断言。通知页定时计数测试临时选用 Windows 平台语义以隔离 Android 系统摘要自己的 30 秒仓储同步；Android 摘要本身不是本次改动。上述仅为受影响局部用例，不是全仓覆盖。

13 个本轮 Dart 源码及测试文件定点 `dart analyze` 无问题。最终 `flutter build apk --debug --flavor dev --target=lib/main_preview.dart` 成功，`frontend/build/app/outputs/flutter-apk/app-dev-debug.apk` 的 SHA256 为 `10BBCEB68452B4F896AA109BBE924FCFD9ABAEF69D8A1A2ACB08BCE04B1C999B`，由独立审查者重新安装并按上文实点。第1轮独立 review 集中指出 Navigator 重挂、异步详情失败和返回锚点的边界；修复后第2轮定点复核通过，无未关闭的本轮缺陷。未运行全仓测试、Windows 原生运行或正式服务联调。

本工作区原本已有大量用户和并行工作的未提交前端、缓存与后端变更。本次只从独立原样快照生成精确增量补丁，存于忽略目录 `artifacts/dev/overlay-revalidation-baseline-20260927/`；遵循用户对此工作区的既有明确要求，不 commit、不 push，也不将其他并行变更纳入补丁。
