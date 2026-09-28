# 当前前端预览的局部视觉整理

状态：2026-09-27，阶段1现有固定样例预览的局部界面优化；代码与记录由 GPT-6 Sol 修改，不计作材料、收藏或前端缓存的正式业务验收。此次按用户最新要求，以实际运行的 Flutter 前端为视觉基线，未用旧 HTML 原型或旧设计方案决定本轮画面。

## 范围与画面证据

内置浏览器在 1440×1000 桌面及 760 宽窄桌面检查，Android 14/API 34 的 `Haruka_B0_API34` 模拟器运行 `main_preview.dart`。该模拟器实测物理尺寸 1080×2400、密度 420 dpi，约为 411×914 逻辑像素。两端均由协作 Agent 实际点击并截取固定样例页面；实现者随后直接查看这些渲染截图。图片仅含演示数据。

| 页面 | 修改前 | 修改后与实点结果 |
| --- | --- | --- |
| 材料库桌面 | [1440 材料库](assets/visual-polish/web-library-before.png) | [1440 材料库](assets/visual-polish/web-library-after.png)、[760 材料库](assets/visual-polish/web-library-760-after.png)、[搜索](assets/visual-polish/web-library-search-after.png)、[深色主题](assets/visual-polish/web-library-dark-after.png)：内容与其他主入口左缘一致，较宽卡片的状态/解析进度独立居右；760 宽时搜索换行，输入 `N2` 得到 1 份试卷，未见横向溢出。 |
| 材料库手机 | [Android 材料库](assets/visual-polish/android-library-before.png) | [Android 材料库](assets/visual-polish/android-library-after.png)：筛选与统计间距收紧，状态有文字、色点及解析进度；列表末尾增加滚动留空，使悬浮导入按钮不阻断末条阅读。 |
| 单词本 | [Web](assets/visual-polish/web-notebooks-before.png)、[Android](assets/visual-polish/android-notebooks-before.png) | [Web 1440](assets/visual-polish/web-notebooks-after.png)、[Web 760](assets/visual-polish/web-notebooks-760-after.png)、[Web 375](assets/visual-polish/web-notebooks-375-after.png)、[Android](assets/visual-polish/android-notebooks-after.png)：两入口同高，每日单词改为轻量底色；手机七种筛选排为两行 4+3，均保留 48dp 高触控区域。Android 实点[摘录空状态](assets/visual-polish/android-notebooks-excerpt-empty.png)后恢复全部 6 条，再进入[每日单词 2 条历史](assets/visual-polish/android-daily-entry-after.png)；Web 管理弹层可开关，并检查[深色主题](assets/visual-polish/web-notebooks-dark.png)。 |

同时直接查看了 Web 查询/结果、练习、设置和阅读器，以及 Android 查询与练习。它们没有出现本切片必须修复的同级问题，因此未扩大页面修改范围。材料行只更改展示，不改变目录查询、滚动锚点、处理态禁用、更多菜单或进入路径；词本入口、筛选与桌面条目只改排版，搜索刷新时保留输入框与焦点。刷新期间私有列表及统计继续受原访问门禁隐藏，词本名使用公共默认文字，依赖私有数据的入口暂时禁用；未改变筛选条件和数据来源。

第二轮 Android 实点发现词本输入 `glimmer` 时，查询变化会卸载整页，使连续键事件只留下首字；Web 同样失去焦点。修正后 Android 原生连续输入、等待筛选为 1 条、收起键盘，画面中仍是完整 `glimmer`，见[Android 搜索](assets/visual-polish/android-notebooks-search-after.png)；Web 在不重新聚焦的情况下先逐键输入 `gli`、等待刷新后续输 `mmer`，仍保持焦点及 1 条结果，见[Web 搜索](assets/visual-polish/web-notebooks-search-after.png)。Android 关闭搜索后 6 条恢复。

设计判断使用已安装的 `ui-ux-pro-max`：`learning app content hierarchy --domain ux` 中适用的是一致的字号层级与长内容省略；`responsive layout --stack flutter` 返回的 `LayoutBuilder` 按实际约束分支与当前工程相符。首次过窄的 Flutter 查询无匹配，按 skill 要求改为该定点查询。搜索结果仅作建议，最终取舍来自实际页面与本仓库的 Flutter 布局约束。

## 定点验证与独立 Review

- `dart analyze lib/features/library/presentation/library_pages.dart lib/features/collections/presentation/collection_catalog_access.dart lib/features/collections/presentation/notebook_pages.dart test/app/preview_flows_widget_test.dart`：无问题。
- `flutter test test/app/preview_flows_widget_test.dart --name library`：2/2 通过，包括 760 宽搜索及宽窄重排。
- `flutter test test/app/preview_flows_widget_test.dart --name notebook`：6/6 通过，包括窄桌面长词本名/长读音及手机、760 桌面的逐字符键盘续输。
- `flutter test test/features/library/material_catalog_widget_test.dart`：17/17 通过，涵盖长标题、处理中状态、滚动锚点和目录返回。合计本次必要 widget 用例 25/25 通过；没有运行全仓或全平台矩阵。

非作者 Agent 第1轮只审本次增量，指出三个边界：760 宽桌面筛选与固定搜索可能冲突，词本长名称/读音可能挤出，材料库扩宽后中央空白增大。集中修复为局部宽度换行、单行省略与宽卡片右侧状态区，并加 760 宽及长内容操作测试。第2轮按这些点复看 1440 和 760 的材料库及搜索，未见溢出；同轮实际连续输入又揭示词本搜索卸载问题，修复并以两端分字符输入定点复核。此记录没有声明真实后端、离线缓存、正式授权或原生发布包验收。

本仓库在本轮开始时已有大量未提交的固定样例与缓存工作。依用户对该工作区的既有明确要求，本轮仍保持未提交；本次增量的修改前快照、SHA256 清单和补丁保存在忽略目录 `artifacts/dev/visual-polish-baseline-20260927/`，供单独审查，不将其他未完成改动混入提交。
