# 手机材料库、居中对话框与 Android 本地消息摘要

状态：2026-09-27，阶段1现有固定样例预览的局部界面与系统通知栏验证，由 GPT-6 Sol 修改。以当前实际 Flutter 前端和产品范围为基线，未用旧 HTML 原型或旧设计方案作为本次视觉目标；不代表正式 M1 站内消息或材料业务验收。

## 变更与画面

手机材料库把四类材料筛选收进约 90dp 高的导航区。最初版本曾把当前有权查询结果数量作为次级信息；同日后续按用户反馈移除手机和桌面的“几份材料”统计，详见文末增量记录。材料行压缩封面和垂直间距，保留标题、元数据及明确的可用状态；处理中不展示任务百分比、进度条或任务面板入口。首版把材料更多、详情与删除确认都做成居中对话框；同日后续把手机三点操作改为按钮下方的锚定菜单，只有选择详情或删除后才打开相应对话框。共享对话框表面固定标题、关闭按钮和底部动作，仅正文滚动；一般 `AlertDialog` 使用相同主题表面，`showHarukaDialog` 使用淡入、轻缩放及轻位移的短动画，并响应减少动态。手机壳移除桌面式消息铃铛。

| 画面 | 修改前 | 修改后 |
| --- | --- | --- |
| Android 材料库 | [列表](assets/mobile-material-dialogs/android-before.png) | [列表](assets/mobile-material-dialogs/android-library-after.png) |
| Android 操作/详情 | [底部操作](assets/mobile-material-dialogs/android-material-menu-before.png)、[底部详情](assets/mobile-material-dialogs/android-material-detail-before.png) | [居中操作](assets/mobile-material-dialogs/android-menu-after.png)、[居中详情](assets/mobile-material-dialogs/android-detail-after.png) |
| 窄屏 Web | [390 宽列表](assets/mobile-material-dialogs/web-library-before.png)、[底部详情](assets/mobile-material-dialogs/web-material-detail-before.png) | [390 宽列表](assets/mobile-material-dialogs/web-library-after.png)、[矮视口详情](assets/mobile-material-dialogs/web-detail-small-after.png) |

Web 另以[深色材料库](assets/mobile-material-dialogs/web-library-dark-after.png)和[深色详情](assets/mobile-material-dialogs/web-detail-dark-after.png)实看颜色、状态文字与对话框层级，未见明显溢出。

1440×960 桌面仍保留 header 消息入口，独立审查者实点[词本选择对话框](assets/mobile-material-dialogs/web-desktop-dialog-after.png)打开/关闭；桌面通用 `AlertDialog` 继承统一表面主题。另保存 9 秒的[Android 对话框动效录屏](assets/mobile-material-dialogs/android-dialog-motion.mp4)，独立审查者检查开关过程和退出透明度过渡，未见叠层残留；未作帧率结论。

Android 14/API 34 模拟器为 `Haruka_B0_API34`，实测 1080×2400、420 dpi（约 411×914 逻辑像素）；Web 另在 390×844 和窄高视口检查。截图仅含固定演示数据。实现者亲自查看了修改前、首版及修改后的真实渲染画面；实际按钮、筛选、操作与详情由独立审查者点击复核。

## Android 本地消息范围

仅 `main_preview.dart` 的 Android 前端接入当前通知仓储：应用在前台或恢复时刷新本人有权列表，并把未读数作为无材料名、原文或私人正文的通用系统通知摘要。Android 13 及以后遵循系统 `POST_NOTIFICATIONS` 授权；拒绝时仍可从“我的→消息”打开应用内列表。点击系统通知只进入消息列表，随后沿用现有消息条目的已读提交和材料资源重新授权检查；账号切换或预览退出清除旧系统摘要。这里没有后台服务、FCM、远程推送或正式业务通知源，不能据此声称 M1 已实现。

模拟器实际出现[系统授权弹窗](assets/mobile-material-dialogs/android-notification-permission.png)；授权后已实点[通知栏通用 2 条未读摘要](assets/mobile-material-dialogs/android-notification-shade.png)和[通知点击后站内消息页](assets/mobile-material-dialogs/android-notification-open.png)。最初弹窗的允许操作由外部完成，独立审查者没有将它记为本人点击。独立审查者随后点“全部标为已读”，三条列表均变已读，`dumpsys notification` 中活动的 Haruka `NotificationRecord` 消失；再在系统设置关闭该应用通知，确认 `POST_NOTIFICATIONS` 未授权，仍从“我的→站内消息”进入[完整消息页](assets/mobile-material-dialogs/android-notification-denied-fallback.png)。安装最终重建 APK 后，独立审查者恢复系统通知开关，也再次看到通用摘要。

## 定点检查与 Review

- `flutter analyze` 定点覆盖本次 Dart UI、通知桥及相关测试文件：无问题。
- `flutter test test/app/preview_flows_widget_test.dart --name "mobile library|mobile material"`：3/3 通过。
- `flutter test test/features/library/material_catalog_widget_test.dart --name "library reads|phone material card|removed anchor"`：3/3 通过。
- `flutter test test/features/notifications/notification_shade_controller_test.dart test/app/dialog_surface_widget_test.dart`：初次 4/4 通过（通知控制器 3、短视口键盘对话框 1）；补后台账号切换和启动身份未确认清旧摘要的低层用例后，单独运行通知控制器 5/5 通过。去重合计本次必要 widget 用例 12/12，通过范围不代表全仓覆盖。
- `flutter build apk --debug --flavor dev --target=lib/main_preview.dart`：最终源码成功生成 `frontend/build/app/outputs/flutter-apk/app-dev-debug.apk`。最终 APK 已重新安装，通知栏摘要再次出现；系统权限、点击、已读清除及拒绝后的应用内入口按上文实际验证。后台账号切换清除旧摘要仅有低层定点测试，未做原生双账号实测。

独立审查第1轮聚焦本次增量，指出手机更多热区缩至 40dp、对话框整体滚动且无关闭按钮、元数据首分隔符、分类区压过材料主体、绿封面过亮及动效需要统一。集中修订后更多热区至少 48dp，分类区与对话框按上述结构调整，并补定点边界用例。同轮通知桥审查指出后台时不应轮询、已读提交应立即同步摘要、启动未确认账号与退出时应清旧摘要；已用生命周期门控、仓储状态监听和清除动作集中修复。第2轮已定点实看 Android 与 Web 的最终材料页、操作及详情、亮暗主题、桌面通用对话框和短动画，未发现上述问题复现；原生权限、摘要点击、已读清除与拒绝后的应用内入口按上文实点。无未关闭的本次 UI 缺陷，不扩大全仓审查。

设计依据使用仓库内 `ui-ux-pro-max`：`mobile list filters status compact scannability --domain ux` 的结果不精确，因此仅参考其手机优先原则；`dialog transition list filter animation --stack flutter` 无匹配后，改查 `transitions --stack flutter` 与 `animation --domain ux`，采用 Flutter 隐式筛选/列表动效、短对话框过渡与减少动态处理。实际排版取舍来自上述 Web/Android 渲染画面和当前 Flutter 组件约束。

本工作区开始时已有大量未提交的前端固定样例、缓存与其他并行修改，包含后来更新的认证模型与 Windows runner。依用户对此工作区的既有明确要求，本轮保持未提交；只含本次增量的原样快照、SHA256 清单及审查补丁保存在忽略目录 `artifacts/dev/mobile-material-dialogs-baseline-20260927/`，不将其他未完成工作纳入提交。

文档定点检查中，本次修改的专题和本记录无链接错误；`docs/README.md:9` 由并行工作新增的缓存恢复记录链接在检查时目标文件尚未创建，故全导航检查仍报一处 `missing_or_wrong_case_target`。该链接不属于本次增量补丁，也不计为本轮文档检查通过。

## 同日增量：材料分类与顶部间距

用户反馈切换材料种类时分类栏自身也会消失重载，并要求移除材料数量、收紧 Android header 与状态栏之间的空隙。本轮由 GPT-6 Sol 仅修改材料展示、手机壳额外间距和对应定点测试；旧 HTML 原型没有用作本轮基线。原结构在类型/搜索查询变更后，由 `MaterialCatalogAccess` 卸载整页等待权限复核，分类栏与导入按钮因此一同闪退。现分类栏与导入按钮作为稳定外壳挂载，权限门禁只包私有结果；加载、失败或撤权仍隐藏原材料行，未放宽仓储鉴权。手机和电脑均不再显示“几份材料”，仓储查询与统计契约未变。

Android 模拟器状态栏和挖孔的系统安全区实际为 136px（420 dpi，约 52dp）；根页面此前又加 12dp 顶部间距。本轮只把额外间距收为 4dp，保留系统 `SafeArea`，不裁切状态栏。材料分类条因移除数量而上移，触控和列表末尾可用空间不变。

独立审查者在内置浏览器实点“全部→小说→课本→试卷”：加载帧中[分类按钮和导入](assets/mobile-header-tabs/web-category-loading-state.txt)保持相同语义节点，旧材料结果区域暂时隐藏，随后仅展示新类型结果。[手机修改前](assets/mobile-header-tabs/web-before.png)、[手机修改后](assets/mobile-header-tabs/web-after.png)及[桌面修改后](assets/mobile-header-tabs/web-desktop-after.png)记录了数量移除和版面变化；Android [修改前画面](assets/mobile-header-tabs/android-before.png)显示顶部与统计栏原状态。

最终预览 APK 安装后，独立审查者实看 [Android 全部材料](assets/mobile-header-tabs/android-after.png)，并亲自点选“全部→小说→课本”，保存[分类后的画面](assets/mobile-header-tabs/android-category-after.png)。分类栏始终处在相同屏幕位置，数量文字消失；系统 UI 提供的搜索触控目标从 `[907,168][1033,294]` 变为 `[907,147][1033,273]`，上移 21px（8dp），仍为 48dp 高且保留 136px 系统安全区。Web 手机和 1440×960 桌面均无数量文字或明显溢出。

本次必要检查为 `flutter test test/app/preview_flows_widget_test.dart --name 'mobile library filters|mobile root header|mobile material delete|mobile import wizard'` 的 4/4，以及 `flutter test test/features/library/material_catalog_widget_test.dart --name 'mobile type controls|library reads injected catalog'` 的 2/2、`--name 'desktop detail resolves'` 的 1/1，去重 7/7 通过。延迟仓储响应的用例证明分类和导入保持同一 Element，旧私有行在复核中不可见；顶部安全区用例证明 header 只在系统 inset 后保留必要间距。四个受影响 Dart 文件定点 `flutter analyze` 无问题；`flutter build apk --debug --flavor dev --target=lib/main_preview.dart` 成功，APK SHA256 为 `958EB0809545B030F6790BF676BC0027F8976B8C285A5CDECFD7198F5AA5F85A`。本轮独立审查仅一轮，代码与 Web/Android 实看均通过，无需修订；未扩大到通知、缓存、后端或全仓测试。

用户对此工作区已明确要求保留既有未提交工作，故本轮不 commit、不 push。仅本轮文件的原样基线、哈希清单及 `increment.patch` 保存在忽略目录 `artifacts/dev/material-tabs-header-baseline-20260927/`，不夹带并行缓存与后端改动。

## 同日增量：手机材料三点菜单

用户要求三点只在按钮下方展开紧凑两项菜单，不先显示独立“材料操作”对话框。独立审查者实点的[Android 修改前画面](assets/mobile-material-menu/android-before.png)仍是居中操作对话框。手机卡片现改用本地锚定 `MenuAnchor`，查看详情与删除分别进入既有详情/确认对话框；外点和系统返回先关闭菜单，三点触控区仍为 48dp。锚定层不推入新 `PopupRoute`，避免弹出路由关闭时触发材料目录可见性复核，与详情自身的强制刷新争用同一仓储代次。材料目录、权限门禁、详情与删除实现，以及桌面三点均未改动。

独立第1轮审查先在 Web 与 Android 发现中途的 `PopupMenuButton` 版本虽正确锚定，却在点击“查看详情”后只关闭菜单，不出现详情：弹出路由退出同时触发 `MaterialCatalogAccess` 重新复核，和详情刷新竞争。已集中替换为不切路由的 `MenuAnchor`，并用 `PopScope` 使系统返回先关菜单；详情与删除仍经原仓储及权限路径。必要 widget 定点用例 5/5 通过，覆盖菜单锚点、外点和系统返回、详情与删除、真实 `CachedMaterialCatalog` 加权限列表门禁的详情交接；受影响的两个 Dart 文件定点 `flutter analyze` 无问题。这些是本轮局部结果，不代表全仓测试。

随后用户补充：仅打开三点再点空白处也会让材料列表重新加载。真实 `CachedMaterialCatalog` 加 `MaterialCatalogAccess` 的定点用例已加强：菜单打开与外点关闭前后首卡保持同一 Element，远端请求数不增加；选“查看详情”后原居中对话框可打开。Web R 重启后的独立实点也确认[菜单打开与外点关闭](assets/mobile-material-menu/web-menu-state.txt)仅增删菜单节点、材料节点保持，且[最终菜单画面](assets/mobile-material-menu/web-menu-after.png)与[详情对话框](assets/mobile-material-menu/web-detail-after.png)符合该路径。

中途并行缓存修改使 `cache_coordinator.dart` 的 nullable `diskSnapshot.invalidations` 引用无法编译。为恢复本轮实际预览，已先原样备份该文件，再仅给 `useDisk && mayPublish` 已保证非空的这一处加 `!`；相对备份仅一行差异，独立存放编译修复补丁，不纳入手机菜单 UI 补丁或借此清理其他并行缓存改动。最终 `MenuAnchor` 源码现已成功生成 dev preview debug APK，SHA256 为 `626425F1A6F5F05F11E337B9241508A2BF1E5A089D322A2C0015A44C2D5C9A7D`。此前含 `PopupMenuButton` 的 APK 已被竞态证伪，不作为最终交付。

第2轮独立定点复核已在最终 APK 冷安装后完成：[Android 锚定菜单](assets/mobile-material-menu/android-menu-after.png)保持材料列表可见，实点空白处和系统返回都只关闭菜单，列表与位置保持；点“查看详情”进入[原居中详情](assets/mobile-material-menu/android-detail-after.png)，点“删除材料”进入[原确认对话框](assets/mobile-material-menu/android-delete-after.png)并取消。Web 同样实点外点关闭、详情和删除确认，菜单前后材料语义节点保持，未复现列表重载。无未关闭的本轮 UI 缺陷。

本轮必要 widget 用例去重为 5/5：手机菜单锚点、外点与系统返回、详情、删除，以及真实 `CachedMaterialCatalog` 与 `MaterialCatalogAccess` 的“菜单打开/关闭仍同卡 Element 且远端请求数不增加、随后详情可打开”回归；另有注入仓储删除路径。`flutter analyze` 对菜单 UI 与对应测试两个文件无问题。把并行 `cache_coordinator.dart` 一并纳入 analyze 时，该文件其他位置报告 17 条既有 warning/info，本轮编译修复处无提示，不宣称整个缓存文件静态检查干净。两份独立补丁和原样基线均保存在 `artifacts/dev/material-actions-menu-baseline-20260927/`；依用户既有要求，本增量不 commit、不 push。
