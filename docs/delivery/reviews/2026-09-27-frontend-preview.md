# 前端原型对照与本机检查记录

状态：2026-09-27，先前 UI 构建已完成原型对照与定点复查；随后按用户反馈重组业务文件，并为材料、查询、通知、收藏与词本接入领域缓存仓储。最新 Android APK 已对五个主入口、通知、词本弹层、查询卡、本机缓存及返回路径实点，见下文新截图。正式服务端、其他业务领域与平台故障路径仍按下文标记。分支 `codex/frontend-cache-mock`，按用户要求未提交，也未编写自动 E2E。先前截图只记录当时的 UI 构建，不充当最新改动的画面对照证据。最新 Web 已编译并在本机 `http://127.0.0.1:8772/` 提供预览；computer use 对本地浏览器地址的安全拦截使 Agent 尚未实点这个最新构建的桌面页面。

## 检查环境

- 原型：`prototype/serve.py` 本地 HTTP，手机 `phone.html`、电脑 `desktop.html`。用 Codex 内置浏览器直接打开、点击导航和弹层；手机视口 390×844，电脑视口 1440×900。
- 正式组件不展示实现说明或隐私提醒式的补充文案。头像、资料、缓存和管理页仅保留完成操作所需的标题、状态、输入提示与确认后果；原型中的说明板已从实装移除。
- 应用页面路径统一由 `frontend/lib/app/routes.dart` 中的 `AppRoutes` 常量维护；账号、邮件动作、材料入口和管理端页面已改为引用常量。
- 前端：`HARUKA_MOCK=true` 的 Flutter Web 预览；Android 14 API 34 模拟器 `Haruka_B0_API34` 安装 dev debug mock APK 后，用 ADB 实际点击及截屏。安卓截图为 1080×2400 物理像素，对应约 360×800 逻辑视口；状态栏/系统导航由模拟器提供。
- 截图内容只含固定演示数据，不含真实账号、密钥或私有材料。下方 `before` 图片记录修正前状态；重组后的 Android 实点另列于新构建表。每次修正仍须重新截屏，旧图不充当新修复的完成证据。

## 手机逐页对照（首次）

| 页面 | 原型 | Android mock | 已见差异与下一步 |
| --- | --- | --- | --- |
| 材料库 | ![材料库原型](assets/frontend-preview/prototype_phone_library.png) | ![材料库初次预览](assets/frontend-preview/mock_android_library_before.png) | 原型顶部同一行是小图标、页名和操作；预览多一行大标题。原型卡片有章/单元/题数及处理进度，预览缺少部分元信息和进度条。调整顶部、卡片密度与 FAB。 |
| 单词本 | ![词本原型](assets/frontend-preview/prototype_phone_notebooks.png) | ![词本初次预览](assets/frontend-preview/mock_android_notebooks_before.png) | 原型搜索由顶部按钮展开，七类筛选分两行，条目在同一面板中紧凑排列；预览常显搜索框、横向滚动筛选、分离大卡。调整手机专用组件。 |
| 查询 | ![查询原型](assets/frontend-preview/prototype_phone_query.png) | ![查询初次预览](assets/frontend-preview/mock_android_query_before.png) | 原型输入框较短、发送空输入禁用，示例为两列小卡；预览表单及示例占用高度明显更大。调整输入状态、尺寸及示例网格。 |
| 练习 | ![练习原型](assets/frontend-preview/prototype_phone_exercise.png) | ![练习初次预览](assets/frontend-preview/mock_android_exercise_before.png) | 原型已有习题为一行紧凑卡，错题/诊断共享一张分隔面板；预览卡片过高且记录拆分。调整手机列表结构。 |
| 我的 | ![设置原型](assets/frontend-preview/prototype_phone_settings.png) | ![设置初次预览](assets/frontend-preview/mock_android_settings_before.png) | 主分组关系基本一致；顶部重复标题带来整体下移，行高和图标尺寸偏大。调整公共手机壳后复核。 |

原型还有详情、导入、对话框、状态与动效；本文件只记录已直接查看的首次画面，不等于 UI-01～35 已完成。逐页点击和修正记录后续追加。

## 电脑材料库对照（首次）

![电脑材料库原型](assets/frontend-preview/prototype_desktop_library.png)

![电脑材料库初次预览](assets/frontend-preview/mock_web_desktop_library_before.png)

预览内容列比原型偏右、搜索独占一行、材料行高度及状态位置不同。已经开始调整桌面壳的左右留白、搜索行和卡片结构；这两张图仍是调整前证据，须在新构建中重新对照。

## 运行检查

- 缓存 Drift/协调器/音频与身份绑定的定点测试覆盖音频恢复、清理恢复和认证暂时重验分支。材料、查询、通知、收藏及词本接线后，`flutter test test/app test/dev test/features test/core/cache --timeout 90s --concurrency 1` **209/209 通过**，`flutter analyze lib test/app test/dev test/features test/support test/core/cache` 无问题。其后修复 Android 实点发现的详情返回底栏缺失，受影响的 `flutter test test/app --concurrency 1` **38/38 通过**，相关文件静态分析无问题。结果和未运行边界见[测试用例记录](../../engineering/testing/frontend-cache-ui-cases.md)。
- mock 数据与 widget 定点测试包含登录、资料、设置、管理和学习详情。组合执行首次 83 项中 82 项通过，剩余 1 项只是“（演示）”旧文案断言；更新断言后该项定点复跑通过。
- 以上是 unit/widget 结果，不含服务端授权、Android 系统选择器、跨设备同步或自动 E2E。
- `flutter run -d emulator-5554` 未指定 flavor 时构建了 dev APK，但 Flutter 工具按默认无 flavor 路径查找而报“未找到 APK”；已从 `build/app/outputs/flutter-apk/app-dev-debug.apk` 安装并启动 mock APK。后续正式运行命令需带 `--flavor dev`。

## 修正后实拍与点击

| 范围 | 原型与实装证据 | 实际点击/差异 |
| --- | --- | --- |
| 手机主入口 | `assets/frontend-preview/prototype_phone_{library,notebooks,query,exercise,settings}.png`；`assets/frontend-preview/mock_android_{library,notebooks,query,exercise,settings}_after.png` | 在 Android 模拟器逐个切主入口、筛选/搜索和详情，修正顶部重复标题、条目密度、筛选与示例卡布局。 |
| 电脑主入口 | `assets/frontend-preview/prototype_desktop_library.png`；`assets/frontend-preview/mock_web_desktop_{library,notebooks,query,exercise}_after.png` | 在 Web 实际点击材料、词本、查询、练习；调整内容列、搜索/卡片层级。 |
| 登录与服务连接 | `assets/frontend-preview/*auth.png` 的手机/电脑成对截图 | 分别点击登录、注册、找回及服务地址，修正手机/桌面为独立组件。表单文案来自 ARB。 |
| 资料与设置 | `assets/frontend-preview/mock_android_profile_no_explainer.png`、`assets/frontend-preview/mock_web_desktop_profile_no_explainer.png`、`assets/frontend-preview/desktop-languages-{prototype,after}.png` | 点击头像、更改个人资料/语言、保存并返回；删除头像私有等说明性正式 UI 文案。桌面语言卡缩到约 700px，接近原型。 |
| 手机本机缓存 | `assets/frontend-preview/prototype_phone_setting_cache.png`、`assets/frontend-preview/android-cache-final.png`、`assets/frontend-preview/android-cache-clear-dialog.png` | Android 实际点击“我的”→本机缓存、解释容量下拉选 50 MB、保存、清理确认弹层。发现中间统计卡窄缩，改为整列；清理按钮改用主题的浅桃色与危险色，复拍后接近原型。确认弹层只保留影响范围与动作。 |
| 电脑本机缓存 | `assets/frontend-preview/prototype_desktop_setting_cache.png`、`assets/frontend-preview/mock_web_desktop_settings_cache_final.png` | 实际点击容量与清理弹层，修正统计卡、清理按钮和弹层宽度；浅桃色清理按钮已在 Web 完整重建后复拍。原型顶部说明性文案按用户新要求移除。 |
| 管理端 | `assets/frontend-preview/mock_web_desktop_admin_*.png`、`assets/frontend-preview/mock_web_desktop_admin_security_no_explainer.png` | 实际点击管理概览、用户、角色、菜单、策略、任务、审计、用量、安全及用户摘要弹层。切换受众的技术说明已移除；安全页在热重载后重新点击并截图。 |
| 词条/教材题/成绩 | `assets/learning-details/` 的 12 张成对截图；`assets/frontend-preview/mock_web_desktop_textbook_practice_final.png` | 手机和电脑均实点词条编辑/归本、教材作答/反馈/重试/收藏、试卷交卷/复盘/收藏。桌面课后题另在原型与预览相同 1280px 视口复查：卡片 x≈355、y≈214、宽≈780、高≈440，两端基本重合；已修正原有横向偏移和约 70px 的按钮纵向偏移。选项文案的换行仍与原型不同。 |
| 图片查询 | `assets/query/` 的手机/电脑原型与实装 JPG，及 `android-{page,camera-open,camera-review,camera-attached,camera-preview,camera-result,gallery-open,gallery-selected}.png` | 手机 Web 实点粘贴 PNG、缩略图、放大、纯图提交的未分析状态与移除；桌面 Web 实点图文查询。Android dev mock APK 重新构建后，真实点“拍照”进入系统相机、拍摄确认、预览和提交，再点“相册”进入系统文件选择器并选图；结果未伪造 AI 卡片。 |
| 每日单词 | `assets/frontend-preview/mock_web_phone_daily_words_rebuilt.png`、`mock_web_phone_daily_words_aligned.png`、`mock_web_phone_daily_words_history_rebuilt.png`、`mock_web_phone_daily_word_detail_rebuilt.png`；原型 `prototype_phone_daily_words.png`、`prototype_desktop_daily_words.png` | 手机实点日期 9 月 27 日→25 日，计数 2→1、仅显示当日加入词，点词打开详情。再调整手机日期按钮高度和列表间距并复拍：标题约 y90、统计卡 y146–406、词行 y474，与原型主要位置吻合；桌面标题、统计卡和首行位置已与原型接近。 |
| 外观与管理策略 | `assets/frontend-preview/mock_web_desktop_appearance_dark.png`、`mock_web_desktop_admin_users_rebuilt.png`、`mock_web_desktop_admin_policy_applied.png`、`mock_web_desktop_admin_security_rebuilt.png`、`mock_web_desktop_admin_password_dialog.png` | 桌面实点深色主题和减少动态开关，主题配色随状态切换；管理端登录、用户表、策略草稿→预览→应用、改密弹层均已实际点击。策略应用后当前值更新，用户表占满卡片宽度；改密提交由 widget 定点测试验证。 |
| Android 材料与小说 | `assets/frontend-preview/mock_android_final_library.png`、`mock_android_final_novel.png`、`mock_android_final_novel_prepare.png`、`mock_android_final_novel_prepare_empty.png` | 本轮 APK 安装后实点材料库→小说→准备本章；两项默认勾选，逐项取消后开始按钮禁用。小说中的长按提示与手机原型逐字相同，属于原型操作引导。 |
| Android 试卷准备 | `assets/frontend-preview/mock_android_final_exam.png`、`mock_android_final_exam_candidate.png` | 实点书库→试卷准备→听力候选校对；未确认时确认按钮禁用，未开始正式音频或评分。 |
| 课本路径修复后实点 | `assets/frontend-preview/mock_android_rebuilt_textbook_{directory,unit02,unit03,back_button}.png`、`mock_android_latest_textbook_{unit02,system_back}.png`；旧 `mock_android_final_textbook.png` 仅作修复前记录 | 新 APK 从材料库可见入口进入课本目录，实际打开 Unit 02/03，左上返回能回目录；下一 APK 再次实点 Android 系统返回键，已先回单元目录。 |
| 查询结果初次复核 | `assets/frontend-preview/prototype_phone_query_{word,sentence,grammar,correction}_result.png`、`prototype_desktop_query_word_result.png`；`mock_web_phone_query_word_result_before.png`、`mock_web_desktop_query_word_result_dev.png` | 手机与电脑原型四类结果已逐一点击；旧预览把通用卡放在完整输入框之后，缺少词条例句、译文分块、语法对比和订正栏。现已改为结果优先、输入框置后、四类专用卡、历史保留与重复收藏反馈。 |
| 查询结果最终 Web 对照 | `assets/frontend-preview/mock_web_phone_query_{word,sentence,grammar,correction}_result_final.png`、`mock_web_desktop_query_word_result_aligned.png`、`mock_web_desktop_query_word_result_final_build.png` | 390×844 手机 Web 逐一提交四类输入，截图与原型同页比对；结果卡在短暂滚动动效后贴近顶栏，细分结构、按钮顺序与原型接近，且从材料库返回仍有历史。桌面以原型截图相同的 1265×712 视口复拍，结果卡左边缘相差约 7px；最终 build 再次实点“そっと”并复拍加粗后的标题。原型的示例/不计入成绩等说明未进入正式 UI。 |
| Android 试卷场次 | `assets/frontend-preview/mock_android_rebuilt_exam_{prepare,question_review,after_question_review,candidate,candidate_checked,script_confirmed,audio_ready,session,answer_card,leave}.png` | 新 APK 逐步点击题分校对、听力候选复核门禁、音频就绪、开考、选答/标记、答题卡、保存与离开确认；状态按操作变化。正式服务端冻结、评分和音频调用未执行。 |
| Android 试卷准备返回 | `assets/frontend-preview/mock_android_final_exam_{prep_state,question_review,prep_restored}.png` | 最新 APK 再次实点题分校对，返回材料库后重新打开同一试卷，准备清单由“已提取 · 待校对”恢复为“已校对”；这仅证明本次进程内 mock 状态，不代表服务端持久化。 |
| Android 小说交互 | 修复前 `assets/frontend-preview/mock_android_latest_novel{,_playing,_selection}.png`；修复后 `mock_android_final_novel_{playing,selection,word_selected,query}.png`、`mock_android_final_window_{analysis,selection,query_card,saved}.png`，最终卡片 `mock_android_final_word_card_{aligned,saved}.png` | 重新构建并安装 APK 后实点连续朗读、逐句青柠高亮、播放中长按、选择“窓”与查询。长按会暂停且收起朗读卡，词泡、范围与查询按钮均可触达；首次查询仅有空结果，补词卡后再次实点并对齐类型栏、独立读音、蓝色释义块，点击收藏后按钮变“已收藏”。 |
| Web 小说词卡最终对照 | `assets/frontend-preview/novel_phone_flutter_word_card_{aligned,saved}.png`、`novel_desktop_flutter_word_card_{aligned,saved}.png`，原型 `novel_phone_prototype_window_query.png` | 手机与电脑 8772 最终 build 分别实点长按、选“窓”、查询与收藏，卡片结构和收藏反馈已复拍；其余具体差异见[小说对照记录](2026-09-27-novel-frontend-comparison.md)。 |

## 重组后 Android 新构建实点

ADB 在新 APK 上逐页打开以下入口并保存截图；原型列指向此前实点的手机原型画面。此轮只证明列出的路径在 Android 模拟器可见、可点击，尚未重新覆盖所有弹层、动效与桌面视口。

| 路径 | 手机原型 | 新构建截图 | 操作及观察 |
| --- | --- | --- | --- |
| 材料库 | [原型](assets/frontend-preview/prototype_phone_library.png) | [Android](assets/frontend-preview/android-refactor-library.png) | 打开材料库，材料目录从缓存仓储的预览来源加载。 |
| 单词本→词详情 | [词本原型](assets/frontend-preview/prototype_phone_notebooks.png) | [词本](assets/frontend-preview/android-refactor-notebooks.png)、[词详情](assets/frontend-preview/android-refactor-word-detail.png) | 点击词本并进入词条详情。 |
| 查询→完整词卡 | [查询原型](assets/frontend-preview/prototype_phone_query.png)、[结果原型](assets/frontend-preview/prototype_phone_query_word_result.png) | [查询](assets/frontend-preview/android-refactor-query.png)、[词卡](assets/frontend-preview/android-refactor-query-result.png) | 提交文字查询并打开完整词卡；预览来源先查已存结果，缺失才生成。 |
| 练习 | [原型](assets/frontend-preview/prototype_phone_exercise.png) | [Android](assets/frontend-preview/android-refactor-exercise.png) | 打开练习主入口。 |
| 我的→本机缓存 | [设置原型](assets/frontend-preview/prototype_phone_settings.png)、[缓存原型](assets/frontend-preview/prototype_phone_setting_cache.png) | [我的](assets/frontend-preview/android-refactor-settings.png)、[缓存](assets/frontend-preview/android-refactor-cache.png)、[查询后缓存](assets/frontend-preview/android-refactor-cache-after-query.png) | 打开本机缓存并在查询后返回查看；发现修复前统计仍显示 0 条本机解释，而虚构保存成果为 1。该图是缺陷证据，不能用于证明统计修复。 |

查询后统计未刷新的原因定位为 `CacheCoordinator` 发布或删除文本条目时未向设置页发出变化通知；代码已补变化事件并增加定点测试。上表 `android-refactor-cache-after-query.png` 保留为缺陷证据，修复后的复拍见下表。

| 最终 Android APK 点击链 | 截图 | 实际结果与界限 |
| --- | --- | --- |
| 材料库→“小说”筛选 | [材料库](assets/frontend-preview/android-final-library.png)、[筛选后](assets/frontend-preview/android-final-library-filter.png) | 材料数由 4 变 2；主题蓝 FAB 可见，筛选经仓储 queryKey 与模拟远端路径取得列表。 |
| 重启后打开“我的→本机缓存” | [我的](assets/frontend-preview/android-final-settings-current.png)、[查询前缓存](assets/frontend-preview/android-final-cache-before-query.png) | 本机缓存显示 1 份解释，虚构“已保存成果”显示 0；前者为 Drift 副本，后者来自随进程重置的预览来源计数。此差异不代表正式服务端成果丢失。 |
| 清理缓存 | [确认弹层](assets/frontend-preview/android-final-cache-clear-dialog.png)、[清理后](assets/frontend-preview/android-final-cache-cleared.png) | 实点清理确认后本机解释从 1 变 0；预览来源仍为进程内数据。 |
| 查询并回设置检查 | [完整词卡](assets/frontend-preview/android-final-query-result.png)、[返回设置](assets/frontend-preview/android-final-settings-after-query.png)、[查询后缓存](assets/frontend-preview/android-final-cache-after-query.png) | 文字查询显示完整词卡，返回“我的→本机缓存”后本机解释与已保存成果均为 1，复拍证实发布通知能刷新设置页统计。 |
| 离开后再回查询 | [查询历史](assets/frontend-preview/android-final-query-history.png) | 原 prompt 气泡与词卡仍显示于本次进程内查询历史。跨进程历史恢复与真实服务端成果仍未验证。 |

这一轮 Web 构建仅确认编译，工具安全策略拦截浏览器访问，因此没有该轮新构建的桌面实点或截图。后续最终构建已在本地静态服务返回 HTTP 200，仍无 Agent 的最新桌面实点；此前桌面截图只证明当时构建。无 Windows 原生运行证据。

明确差异：设置页与材料目录、完整查询卡共用预览身份的 `CacheCoordinator`。预览默认尝试平台持久后端，测试注入内存后端；可变材料列表经过缓存协调器的 `memoryOnly` 策略，只保留本次运行内存，不写入持久条目。完整查询卡按文本、上下文和两种语言隔离来源身份，先 resolve 已保存结果，缺失才生成，再经过 `validatedText` 写入或校验 Drift 副本。保存成果计数仍来自 `PreviewFixtureStore` 的虚构业务状态，未连接真实服务端。模型任务、跨设备更新及正式 API 权限结果没有以固定数据伪称验收。手机设置原型截图是桌面浏览器里居中的手机画框，新构建实装证据来自 Android 模拟器。

本轮将原 `frontend/lib/features/mock/` 页面移到各业务 feature 的 presentation/domain/data；稳定复用的基础组件保留在 `frontend/lib/shared/presentation/`，虚构来源放在 `frontend/lib/dev/preview/`，Mockito 用于 `frontend/test/` 的测试替身。材料目录 widget 使用 Mockito 仓储替身检验确认删除；缓存仓储测试检验可变列表不落盘及导入后重取。查询结果仓储测试检验完整卡片写入、同版本校验复用、本机清理后由模拟来源取回。前端项目内本轮没有保留一次性 Python 迁移脚本，既有 `tool/` 开发脚本未改。上述都是代码和单元/widget 证据，不是本轮重组后页面的实拍验收。

## 独立 Agent Review 与修复

以下先记录文件重组前的 UI 与缓存基础切片审查。非作者 Agent 当时完成两轮审查；该记录不等同于后面的缓存仓储复核。修复证据只按实际运行的定点检查记录，不把未运行平台路径记为通过。

| 缺陷 | 修订与验证 |
| --- | --- |
| 同 storage_epoch 的崩溃下载占据音频容量/下载槽 | 下载从预约至发布持 operation owner 锁；恢复取得失主锁后删除 staging 并释放操作行。原生音频测试覆盖活跃 owner 保留、失主同代次回收，4/4 通过。 |
| 恢复与新标签登记下载竞争，可能误删 staging | 恢复持字节发布锁与分区索引锁完成快照/孤儿处理；在途下载持 owner 锁。原生定点测试覆盖恢复与正在接收字节的下载交错，4/4 通过；真实 Web 两标签交错仍待平台验证。 |
| CSV 导入导出按钮只弹完成提示 | 改为本机文件选择、v2 解析预览/行级确认与真实导出；桌面 Web 导出已实际产生 19 列、4 条词条的 CSV。文件选择器可打开；自动填入文件受本机 Chrome 扩展权限限制，解析与确认以 unit/widget 验证。 |
| 可见文案出现“示例/虚构/仅为预览”说明 | 已从实际使用的 ARB 文案和页面移除元说明；产品内容本身的“模拟试卷”仍是材料标题。截图在最终构建后复拍。 |
| 只比较 user 授权版本，忽略 policy 版本 | scope 与 grant 分别保存/比较两种版本；policy 变动拒绝旧授权。缓存协调器与身份绑定定点 15/15 通过。 |
| 非法错题 ID 显示其他条目、非法设置路由空白 | 路由不再把非数字 ID 改为 0；详情显示不可用状态。设置未知 section 也显示本地化不可用状态，已在浏览器实际打开深链复查。补 widget 实际导航 `/mock/mistakes/abc` 和 `/mock/mistakes/999`，均显示“未找到资源”；设置未知路由同文件回归，2/2 通过。 |

审查另建议对共享 support 页面中差异明显的手机/电脑页面继续拆分展示组件；当时已把每日单词、错题、诊断、通知、任务等支持页按平台拆分并定点复核。该切片未进行第 3 轮审查。

### 本轮缓存仓储第 1/2 轮复核

业务目录重组和首批预览来源接线后，另由非作者 Agent 对当时直接改动做两轮复核，与上表先前 UI 审查分开。下列是当时的缺陷及修复记录；该切片曾执行组合测试 **170/170 通过**。此数为后续通知、收藏与路由修改前的历史证据；新组合结果见上文“运行检查”。正式 API 权限、Web 最新构建实点与跨进程来源仍未验收。

| 轮次 | 发现的问题 | 修订与证据 |
| --- | --- | --- |
| 第 1 轮，8 项 | ① 查询未先 resolve 已保存成果；② 读取动作应为 `agent.read`；③ 材料目录缺入口/前台周期刷新；④ 失权后仍可能保留旧列表；⑤ 详情与列表未共用仓储及查询键；⑥ 上下文和语言变化可能复用错误结果；⑦ 初始化异常可能变成未处理异步错误；⑧ 预览来源计数可能在缓存发布前误增。 | 查询仓储先 resolve、缺失才生成，以 `agent.read` 校验完整卡；材料页面接入同一 `MaterialCatalog`，以 queryKey 区分列表并在入口/前台重读；阻断态清空可见数据，详情由同一仓储取当前条目；查询身份含文本、上下文及两种语言；初始化捕获仓储失败；预览来源只在完成结果写入后更新自身计数，页面不预增。另修复 Android 实点发现的缓存统计刷新缺口：`CacheCoordinator.changes` 在文本发布/删除后通知设置页。Mockito 仓储/远端、协调器 unit/widget 纳入 170 项组合回归；Android 最终 APK 的缓存统计由 0→1 复拍。 |
| 第 2 轮，5 项 | ① 材料列表动作应为 `material.list`；② 筛选 queryKey 需传至模拟来源；③ 查询提交前需等待缓存身份就绪；④ 慢刷新可能触发重复在途读取或旧结果覆盖；⑤ 查询历史不应由页面与预览 Store 各维护一份。 | 材料资源改用 `material.list` 并让模拟远端按 queryKey 过滤；查询仓储提交前等待 readiness 且阻断未确认身份；前台轮询以在途门禁防重入，仓储按请求代次丢弃迟到结果并在同查询刷新时保留当前展示；查询历史由 repository 单一维护。相关定点用例包含在 170/170；Android 最终 APK 实点“小说”筛选 4→2，离开再回查询仍见 prompt 与词卡。 |

第 2 轮提出的问题已按上表修订并做定点测试；未进行修复后的第 3 轮独立 reviewer 复核，不将测试通过写成 reviewer 已签收。

## Android 系统栏与页面动效修订

Android 入口启用 Flutter 的 edge-to-edge 系统 UI 模式，亮色和深色状态栏图标由主题决定，页面背景延伸到状态栏及手势导航区；业务内容仍通过安全区避开系统图标。API 34 模拟器分别实点材料库、我的、外观及深色外观，截图见 `assets/frontend-preview/android-edge-to-edge-{library,settings,appearance,dark}.png`。这组截图只证明背景与系统栏融合，不把状态栏图标或系统导航条误认为应用控件。

五个手机主 tab 现在由持续挂载的官方 Material `NavigationBar` 承载，选中指示器使用约 240ms 的局部切换；页面路由由统一的 `CustomTransitionPage` 在 220ms 内切换。详情路由加入短位移与淡入。应用的“减少动态”及系统偏好会取消路由、导航指示器与弹层过渡。dialog 进入 240ms、退出 150ms；bottom sheet 沿用同一设计时长。查询结果按独立查询轮次入场，同一结果的收藏/页面重绘不重新播放入场。`preview_route_motion_test.dart` 验证 tab 切换时导航栏 Element 持续存在、时长和减少动态行为；`system_ui_theme_test.dart` 验证两套系统栏主题。上述是控件行为与截图证据，不宣称逐帧视觉或性能验收。用户已明确动效无需录屏，本轮不再制作或保留动效录像。

非作者 Agent 的动效第 1 轮 review 发现底栏放在路由 Navigator 外时，bottom sheet 遮罩不能覆盖底栏，弹层开启后还能切 tab。reviewer 先用 widget 点击复现，再将移动预览壳置于外层 Navigator，并让各业务 bottom sheet 使用 root navigator。修复后 `preview_modal_nav_test.dart` 验证遮罩覆盖底栏中心且点击不会切路由；它与路由动效测试组合 **2/2 通过**。通知与词本仓储的后续接线未计入这两项动效测试。

外层 Navigator 增加后又补查系统返回：最初 Android 返回事件被内层 Router 接走，sheet 未关闭。移动预览壳现在先让外层 Navigator 处理尚未关闭的弹层，再交给 Router 处理页面；`preview_modal_nav_test.dart` 新增系统返回断言，单文件 **2/2 通过**。这仍是 widget 层的返回路径，最终 APK 需再用模拟器实点。

## 最新构建：缓存仓储复核与 Android 实点

独立 Agent 对通知、收藏与词本仓储分别做两轮定点 review。通知复核发现账号切换时旧可见快照及在途已读可能留在新账号；仓储在 scope 关闭时同步清空、按绑定代次拒绝迟到写入，通知定点 **10/10** 通过。收藏复核发现 CSV 导入绕过动作权限、外部失效后旧列表可见、A 账号迟到写可能影响 B；CSV 现在经同一领域仓储，在提交时按实际重复项和词本重算权限并原子写入，目录在失效时同步隐藏旧快照、恢复可读后自动重取。第二轮发现跨标签清理的不可读→可读通知遗漏，已补协调器通知和目录刷新；收藏仓储单文件 **12/12** 通过。修复后未开启第三轮 review；正式服务端事务、权限响应和真实双标签仍待联调。

| 最新 Android 路径 | 截图与原型 | 实点结果 |
| --- | --- | --- |
| 材料与筛选 | [材料库](assets/frontend-preview/android-latest-library.png)、[小说筛选](assets/frontend-preview/android-latest-filter.png)、[手机原型](assets/frontend-preview/prototype_phone_library.png) | 首屏 4 份材料；点“小说”后 2 份。应用背景延伸到系统状态栏和手势区，文字/按钮留在安全区。 |
| 通知 | [未读](assets/frontend-preview/android-latest-notifications.png)、[全部已读](assets/frontend-preview/android-latest-notifications-read.png) | 从材料页点铃铛进入，全部标为已读后两条新消息转已读、按钮禁用，返回材料页红点状态相应变化。 |
| 通知返回与主 tab | [修复前缺底栏](assets/frontend-preview/android-latest-after-back.png)、[修复后底栏恢复](assets/frontend-preview/android-latest-back-fixed.png)、[词本](assets/frontend-preview/android-latest-notebooks-fixed.png)、[查询](assets/frontend-preview/android-latest-query.png)、[练习](assets/frontend-preview/android-latest-exercise.png)、[我的](assets/frontend-preview/android-latest-settings.png) | 首次新 APK 实点发现通知页系统返回后底栏消失：壳层只读基础 URI，未取推入路由的顶部匹配。改为监听实际路由匹配并在安全时更新壳层；重新构建安装后，系统返回恢复底栏，五主入口均可切换。`preview_modal_nav_test.dart` 新增该回归，`flutter test test/app` **38/38** 通过。 |
| 词本与弹层 | [词本原型](assets/frontend-preview/prototype_phone_notebooks.png)、[切换/管理弹层](assets/frontend-preview/android-latest-chooser-retry.png)、[选择后](assets/frontend-preview/android-latest-notebook-selected.png) | 点“全部收藏”打开官方 Material dialog，遮罩覆盖底栏；选“日常的细节”后标题及条目数由 6 变 2。 |
| 查询与缓存 | [完整词卡](assets/frontend-preview/android-latest-query-card2.png)、[本机缓存](assets/frontend-preview/android-latest-cache-page.png)、[清理确认](assets/frontend-preview/android-latest-cache-dialog.png)、[系统返回后](assets/frontend-preview/android-latest-cache-dialog-back.png) | 点击示例填入文本并发送，显示完整词卡；本机解释副本为 1。清理弹层的系统返回只关闭弹层，缓存页保留。进程重启后“已保存成果”预览来源计数为 0，因夹具仅驻进程内，不能当正式服务端缓存恢复证据。 |

这些截图与已存原型画面比对了手机内容密度、卡片、主导航、弹层遮罩和系统栏；没有逐帧动画录像，按用户最新要求无需录屏。路由、tab 指示器及 dialog 的时长与减少动态由 widget 用例验证。最新 Web 构建已成功并通过本地静态服务返回 HTTP 200，Agent 的 computer use 工具对本地浏览器地址仍被安全策略拦截，因此电脑端最新页面的人工逐项点击与截图尚未完成；早期桌面实点记录只证明当时构建。Android 上述链路也不等于全部 UI-01～35 分支、真实 API 权限或跨进程数据恢复已验收。

## 追加修订与新 APK 复核

材料/通知列表现在根据缓存依赖标签对已提交失效定向重读，未知或丢失提示可由前台强制校验收敛；材料切换账号后先隐藏旧结果，再读取新作用域。通知页仅在当前路由和应用前台轮询，慢请求在途时不重新发起，返回页面后合并补查。缓存定点 **32/32**、通知页面 **2/2** 通过。独立 reviewer 首轮指出账号重新 attach 可能停在阻断态，以及通知慢请求会被重复轮询取消；修复后第 2 轮定点复核未见阻断。真实双设备与服务端授权仍未验证。

词本新增同条目双本归类与删本只解绑、中文手动词本和收藏。非单词收藏详情改为手机 sheet、电脑 dialog，可编辑内容、释义和笔记；回原文使用明确的材料 ID。词本切片 **49/49** 定点通过，非作者 review 首轮提出的 ID 重号、归本权限与词本名规范化缺口均已修复，第 2 轮无新增阻断。Android 新 APK 实点[词本列表](assets/frontend-preview/android-current-notebooks.png)、[语法收藏 sheet](assets/frontend-preview/android-current-nonword-sheet.png)和[编辑弹层](assets/frontend-preview/android-current-nonword-edit.png)。

新 APK 首次实点“回到原文”时，弹层仍停在屏幕上；[修复前截图](assets/frontend-preview/android-current-source-return-3.png)保留缺陷证据。修订为先让 sheet/dialog 返回目标路径，等退出动画结束后再从原页面路由跳转；手机与电脑实际 UI 点击测试所在文件 **22/22** 通过。重建安装后，从语法收藏点“回到原文”进入[对应课本目录](assets/frontend-preview/android-current-source-fixed.png)。非作者两轮定点 review 已关闭该增量问题。其他收藏来源删除后的真实服务端状态未验。

复盘选句的私有原文从 URL 查询参数移到账号及权限作用域绑定的临时路由数据；测试检查 URL 不含原文、直接访问没有预填、换账号清空草稿，查询 **7/7** 与学习详情 **17/17** 通过。导入步骤条遵守减少动态设置，widget **1/1** 通过；正式 Reference 页 AnimatedSwitcher 也改为遵守系统减少动画，但未单独执行该控件的 widget 用例。AI 习题确认按钮的演示字样已改为正式文案。构建前的组合运行 **223/225**，两项失败仅为测试仍查旧按钮文字；断言更新后受影响文件 **12/12** 通过，没有把后者写成全组合重跑。新 Web 构建仍由本地 `http://127.0.0.1:8772/` 提供，最新桌面人工逐项点击由用户在预览中查看，Agent 未完成新构建的电脑端 computer use 对照。

## 通知安全、缓存竞争与最新预览

通知不再按“同类型第一份材料”临时绑定目标：预览消息固定材料 ID/版本，来源失权、删除、版本变化、状态不可读或未知目标时，模拟来源清掉旧标题和正文，界面显示本地化的通用不可用提示。点消息先确认已读，再强制重验材料目录；路由/前台恢复与 30 秒重读期间先遮旧列表。通知、应用支持页面与材料目录四文件组合 **35/35**，定点静态检查无问题；非作者 Agent 两轮复核已关闭旧标题短暂显示和目标内容泄露两处缺陷。正式服务端的权限/版本响应仍待联调。

收藏与词本在可见前台每 30 秒重读，路由/前台返回立即重验，慢请求只补读一次，无关通知失效不再使收藏目录闪断；定点 **17/17** 通过。缓存协调器新增同 scope 跨资源乱序时间锚、授权变化取消在途和持久资源正向白名单，`test/core/cache` **52/52** 通过；真实 Web 双标签及设备休眠仍未实测。试卷题面与复盘使用独立内存投影，语言切换保留有效评分 run；六文件定点 **48/48**，随后语言切换缺陷两文件 **10/10**，均为局部证据，正式后端裁剪与限次听力账本未实现。

`flutter build web --release --no-web-resources-cdn --dart-define=HARUKA_MOCK=true --dart-define=HARUKA_ENV=dev` 成功。预览服务 `http://127.0.0.1:8772/` 已更新，首页、`/mock/library` 深层地址及启动脚本均返回 HTTP 200；深层地址刷新原先 404 的临时静态服务问题已修复，服务脚本仅放在系统临时目录，不进入 Flutter 工程。HTTP 检查不能代替浏览器人工画面对照，Agent 的 computer use 对此本地地址仍受工具策略限制；用户正在浏览器检查最新电脑画面。

同一源码构建的 Android dev debug mock APK 已在 API 34 模拟器安装并实点：[材料库](assets/frontend-preview/android-current-after-rebuild.png) → [通知](assets/frontend-preview/android-current-notifications.png) → [对应小说](assets/frontend-preview/android-current-notification-target.png)，以及[试卷准备](assets/frontend-preview/android-current-exam-prep.png)并用一次系统返回回到[材料库](assets/frontend-preview/android-after-exam-back.png)。这些截图证明本次入口与返回路径可见；删除/撤权降级由上述 widget/仓储测试模拟，不冒称 Android 实际撤权。没有自动 E2E，也没有提交。

## 材料列表返回与搜索定点修订

材料目录在路由返回时先遮挡旧材料，强制重新校验后才显示；定时刷新未完成时合并补读一次，筛选变化则在 300ms 后启动新查询，不等待旧查询结束。手机列表使用筛选维度的 PageStorageKey 保留返回后的滚动位置。电脑搜索框移到权限门控结果之外，在列表重验期间持续挂载，并由页面持有输入 controller 与焦点。材料 widget 定点 **8/8 通过**，覆盖返回门控、慢刷新排队、挂起旧查询后的新查询、手机返回位置及电脑连续输入/IME 组合/焦点。非作者第 1 轮 review 找到首字后卸载输入框和旧查询阻塞新查询两处缺陷；修订后第 2 轮定点复核确认两处已关闭。列表内容增删后的稳定项目定位、真实服务端权限变化和最新电脑端人工画面对照仍未验。

同批改动的 Web release 构建成功，`http://127.0.0.1:8772/mock/library` 返回 HTTP 200；这只证明新 bundle 和深层地址可提供，不能代替浏览器点击。Android dev debug APK 构建成功。模拟器剩余空间不足使覆盖安装失败，随后卸载本任务的 dev 包并干净重装，**该模拟器内旧 mock 应用数据已清除**。新 APK 从[材料库](assets/frontend-preview/android-material-latest.png)点击[小说筛选](assets/frontend-preview/android-material-filter-latest.png)→[小说阅读](assets/frontend-preview/android-material-detail-latest.png)→系统返回[材料库](assets/frontend-preview/android-material-return-latest.png)，筛选仍为小说且 2 份材料可见。与已存[手机原型材料库](assets/frontend-preview/prototype_phone_library.png)对照了头部、筛选、卡片与底栏；这条链路未模拟真实撤权或列表增删。

缓存并行切片定点证据：收藏/词本依赖失效、慢详情补读与交错持久提交 **21/21**；缓存与 API 的离线 grant、错误状态透传 **70/70**；各自相关静态检查均无问题。非作者两轮定点 review 已关闭收藏慢读/跨代失效，以及 HTTP 401/403 未知错误码遗漏。Web 持久存储增加 Web Locks 实际获取与不安全模式内存降级，定点 `dart analyze` 无问题；Flutter Chrome 单测仍在 loading 阶段未产出断言，真实双标签/存储回收未验证。

材料详情后来补了已删除/不可读状态的手机返回按钮和电脑返回材料库入口；Mockito 在进入详情后撤去该资源并模拟前台恢复，两端均经实际 widget 点击返回材料库。直接跳入缺失详情、没有可弹出的列表路由时，两端也能返回材料库。材料单文件 **12/12** 定点通过，非作者第 2 轮复核关闭返回分支问题；该深链测试由已启动的 widget 路由执行 `go`，未模拟浏览器冷启动 URL。真实服务端撤权、列表前方增删后的稳定锚点仍待验证。私有 API 的 strict 模式补解码后代次复核与错误响应绑定先于正文解码，定点 **8/8**；正式 app 仍使用兼容模式，不能把单测当作服务端已支持会话绑定。

缓存旧 schema/损坏索引在首次打开时失败，协调器会先关闭失败的持久连接，再打开独立内存后端；内存也失败则保持阻断，不改动旧库。非作者首轮复核要求校正内存后端与数据库控制行的代次一致性，并用真实读取与清理路径举证。修复后定点覆盖在线读取、内存验证命中、离线拒绝、清理后重读及旧库原样保留，缓存协调器 **36/36**、相关静态分析无问题，第 2 轮复核未见该切片阻断。Web 浏览器里实际旧库迁移、Wasm/worker 版本不匹配与双标签仍没有运行证据；Flutter Chrome 测试在套件加载握手阶段停住，未执行断言。

设置页接入按本人作用域、资料/学习档案/偏好三组独立 revision 的 mock source 与内存仓储。确认提交后仅失效对应依赖；字段掩码不带入同页未保存草稿；同账号新 revision 只更新未编辑字段，编辑冲突保留草稿并阻止旧值覆盖。个人资料与查询预算输入框也跟随快照修订同步；结构化 409 给出重载入口，只改时区不推进资料 revision，资料成功而时区失败显示部分成功。语言水平、性别与目标语言行转为文档 DTO，非法出生年份在提交前拦截。设置仓储/source/widget 定点组合 **20/20**、最后资料输入及 409 widget **3/3**，受影响静态检查无问题。非作者两轮 review 的首轮枚举与首次水合缺陷已修；第 2 轮发现同账号新 revision 与无效缺省值，作者补定点测试修复，主代理作针对性代码复核，不再扩大 review。固定预览账号的头像字形还来自 fixture store，不作为跨账号头像读取证据；正式 API/头像上传未做。

上述源码的 Web release 构建已成功，`http://127.0.0.1:8772/mock/settings/queryPreferences` 与 bundle 返回 HTTP 200；Android dev debug APK 覆盖安装成功。模拟器实点[我的总览](assets/frontend-preview/android-settings-current.png)→[个人资料](assets/frontend-preview/android-profile-current.png)，性别选择“男”保存后退出重进仍显示“男”，随后恢复“未填写”；[查询预算修复前](assets/frontend-preview/android-query-settings-current.png)选择 5000、保存并退出重进仍显示 5000，随后恢复 10000。与[手机设置原型](assets/frontend-preview/prototype_phone_settings.png)和[查询预算原型](assets/frontend-preview/prototype_phone_setting_queryPreferences.png)对照时发现详情页多了全局通知铃铛；设置详情页现关闭该入口，设置总览仍保留。此后再做 Web release 和 Android APK 构建，均成功；新 Android [查询预算页截图](assets/frontend-preview/android-query-settings-no-bell.png)与 UI 层级证实顶部只显示返回、标题，系统状态/手势栏沿用应用背景。查询预算原型的说明卡与帮助文案未照搬，遵循用户“不把解释性提示文案写在正式前端”的修订要求；页面表单、快捷值与保存动作保持。模拟来源仍驻进程，APK 重装/应用进程重启后预览设置回到夹具初态，不能把这条手动路径解释为服务端持久化验证。电脑端最新构建仍没有 Agent computer use 点击证据。

为定位 Web 缓存测试的 `loading` 停滞，临时创建只有 `expect(1 + 1, 2)` 的 Flutter Chrome 单测；本机 Chrome 启动后该最小套件同样超过 45 秒没有进入断言，手动停止并删除临时测试文件。因此当前 Web 缓存断言未运行，停滞不能归因于 IndexedDB 或 Web Lock 测试正文；真实双标签仍未验。

## 追加定点修复与最新 Android 构建

- 每日单词去掉固定的 2026-09-27 和三个固定 UTC 偏移，以账号 IANA 时区对 `createdAt` 归日，午夜自动更新并在应用恢复时重算。独立 Agent 实现，主 Agent 定点 review；日历与页面 widget **4/4**、受影响静态分析通过。新 Android APK 实点“词本→每日单词→日期 9 月 25 日”，计数 2→1；截图为 `assets/frontend-preview/android-latest-{notebooks,daily,date-picker,daily-history}.png`。
- 小说选句进入查询时用 `QueryPrefill` 带入当前句，URL 不包含原文。材料路由层仅保留章节/句索引，绑定账号授权代次及材料修订；手机从查询返回重开原句 sheet，电脑恢复 panel，账号切换和材料删除不恢复。首次测试发现材料重验会卸载小说页、丢失索引，修复后又排除了 PageStorage 键冲突；最终小说单文件 widget **12/12**、静态分析通过。主 Agent 定点复核了账号/材料失效分支。新 Android APK 实点“小说→解析→点句→查询预填→系统返回原句”，截图为 `assets/frontend-preview/android-latest-{novel,novel-analysis,sentence-sheet,query-prefill,sentence-return}.png`。键盘 Alt+Enter 选句仍未实现。
- 管理预览由显式模拟权限集控制菜单、深链内容、跨模块按钮、策略只读/写入及已开弹层的撤权遮挡。主 Agent 首轮 review 发现进程级管理状态会跨预览 App 重建残留；作者改为每个预览 App 实例创建/销毁状态，第二轮定点复核无阻断。管理 widget **15/15**、相关静态分析通过；这不是服务端 RBAC 验证。
- 上述源码的 Web release 与 Android dev debug mock APK 均构建成功，APK 覆盖安装成功；`http://127.0.0.1:8772/mock/library` 和 bundle 返回 HTTP 200。Android 首页、每日单词与小说链路的截图来自此次 APK。最新电脑端仍无 Agent 的浏览器逐页点击证据：此前 computer use 对 8772 本地地址明确拦截，未绕过限制；旧桌面截图只证明旧构建。

截至上一轮，仍未完成的纯前端项包括小说 Alt+Enter 键盘选句、材料列表前方增删后的 ID 锚点定位、UI-01～35 尚未逐条覆盖的分支与动效对照，以及新业务页面从 opt-in `HARUKA_MOCK=true` 预览入口进入正式前端装配。Web Chrome 测试在最小空白套件也卡在 loading，Web 旧库/双标签/Wasm/worker/休眠路径尚无运行证据。按本次范围未编写后端 API 或自动 E2E，按用户要求未提交。

## 材料定位与小说键盘入口后续定点

材料库返回定位现保存所打开材料的 ID、筛选键和卡片在视口中的位置。刷新后按 ID 对齐；手机更多菜单进入详情也记录锚点，目标材料已删除时不反复跳动。材料单文件 widget **17/17** 通过，覆盖手机/电脑前方插入或删除、手机菜单、目标删除及连续第二次返回；两文件静态分析无问题。主 Agent 作为非作者 review 曾发现连续返回未复位恢复次数，作者修正并补连续返回测试。该改动未改变页面布局，本轮没有最新构建的浏览器或 Android 人工点击证据；真实分页/服务端撤权也未验证。

小说阅读与解析模式增加 Alt+Enter 键盘入口及普通文本选择，首次小说单文件 widget **14/15**，工具条聚焦断言失败后修复，该失败用例定点 **1/1** 通过；静态分析无问题。非作者 Agent 首轮 review 随后发现原生选区范围没有传给浮层、共通词可能误判句子，以及已经打开的 root bottom sheet 在撤权后可能残留私有正文。两处仍在集中修复，不能把键盘选句和撤权路径记为完成。此前 APK 与 Web 构建均早于这些修订。

正式入口审阅确认新页面仍多处直接读取 `PreviewStoreScope`，完整新路由只在 `/mock/*`，正式 `HarukaApp` 尚未装配这些领域仓储与页面；预览固定身份不证明正式账号隔离。后续需在各领域接口解耦页面、按认证上下文注入缓存仓储并注册正式路由，且正式构建不能注入夹具成功响应。本轮未做这项接线。Chrome Web 单测启动了浏览器和测试服务，却停在 `Running test suite`，没有执行断言；锁定 SDK 的 CanvasKit Windows 路径判断高度疑似原因，尚无 HTTP 404 的直接证据。Web 缓存双标签及旧库恢复仍未实测，最新电脑端 Agent 浏览器点击依旧受工具策略限制。

小说非作者 review 的两处阻断已经修复：原生 `SelectionListenerNotifier` 的 UTF-16 范围用于判断双句中的实际位置并保留精确查询文字；已打开的句析和查询结果 root sheet 共用账号、权限代次与材料版本门控，失效时不再渲染私有正文。小说单文件在共用门控抽取前 **18/18** 通过，随后新增的“已开查询结果弹层撤权”定点 **1/1** 通过；三文件静态分析无问题。第 2 轮非作者 Agent 只复核原两处缺陷，未发现残留。本轮没有重跑抽取后整份小说测试，章节准备弹层的失权遮挡仍未覆盖。

预览入口改为独立的 `frontend/lib/main_preview.dart`；正式 `main.dart` 不再直接切换 `HARUKA_MOCK`。预览 Web 独立目录与 Android dev debug APK 构建成功，相关入口静态分析无问题；源码镜像式入口测试经主 Agent review 后删除。为继续提供相同的 8772 链接，另将独立入口构建到当前静态服务所读的 `build/web`，构建成功且 `http://127.0.0.1:8772/mock/library` 与 `main.dart.js` 均返回 HTTP 200。尝试停止/重启现有本地静态服务以切换构建目录时，工具自动审批以 policy 拒绝该进程操作；未继续操作该进程。正式 `routes.dart` 仍间接引用部分预览页面，不能声称生产依赖图已隔离。

新 APK 安装成功后，Android 模拟器实际点击[材料库](assets/frontend-preview/android-new-preview-entry.png)→[小说阅读](assets/frontend-preview/android-new-preview-novel.png)→[解析](assets/frontend-preview/android-new-preview-analysis.png)，状态栏与手势区沿用页面背景。阅读页点第二段后用 `adb shell input keycombination KEYCODE_ALT_LEFT KEYCODE_ENTER`（也试了 300ms 按住）注入快捷键，截图[焦点框](assets/frontend-preview/android-new-preview-alt-enter2.png)可见，但未弹出选句工具条；此 Android 实体键盘路径没有通过。桌面新构建的浏览器点击仍未取得 Agent 证据，HTTP 200 不能代替视觉或交互对照。按用户要求未提交、未编写后端 API 或 E2E。

## 本轮并行收敛与重新构建

小说章节准备、目录和排版的手机/电脑弹层现在共用账号作用域及材料版本门控。展开章节菜单时撤权曾触发 Flutter `DropdownButtonFormField` 路由拆除异常；改用官方 Material 3 `DropdownMenu` 后，展开菜单失权用例和小说全文件 widget **24/24** 通过。非作者第 1 轮 review 又发现查询结果弹层的旧收藏回调可绕过画面遮挡写入；保存动作现逐次复核账号代次、材料修订及当前卡片 ID/版本。新增“捕获词卡按钮→撤权→调用旧回调”用例，小说全文件 **25/25** 通过，三文件 `dart analyze` 无问题；第 2 轮定点复核确认该缺陷关闭。最新 APK 已实点[章节准备](assets/frontend-preview/android-prep-latest.png)及[展开的章节菜单](assets/frontend-preview/android-prep-menu.png)。测试模拟撤权；没有在模拟器上实际改变服务端权限。

Android 快捷键诊断使用临时 debug 日志，随后已从源码移除。段落被点击后 `FocusNode` 是主焦点；`adb shell input keycombination -t 300 KEYCODE_ALT_LEFT KEYCODE_ENTER` 送入 Flutter 的实际顺序为 Alt `KeyDown`、Alt `KeyUp`、Enter `KeyDown`，Enter 到达时 `HardwareKeyboard.isAltPressed=false`。因此此前模拟器不弹浮层证明不了真实物理组合键有缺陷；widget 中按下 Alt 后保持到 Enter 的用例通过。尝试通过 emulator console 注入内核事件未在 Flutter 产生可见按键日志，当前仍缺真实同时按键的 Android 设备证据，也未重现原型的设备级动效。诊断 APK 不作为最终应用构建；本节以源码回退后的测试与 Web 构建为准。

查询页已移除对 `PreviewStoreScope` 的直接读写，发送语言与减少动态来自设置快照；缺快照阻断提交。收藏通过领域接口引用已提交卡片，预览适配器校验作用域、版本、语言与词本后交给收藏目录仓储。新增查询专属 ARB 文案，相关三文件定点 **11/11** 与静态分析通过；非作者 review 仍在进行。此切片没有改正式入口或路由，其他页面仍存在预览夹具依赖。手机/电脑查询原型在修改前已实际点击，本轮 8772 实装仍无 Agent 的 computer use 视觉复核。最新源码（含移除诊断日志）独立预览 Web 构建成功，`http://127.0.0.1:8772/mock/library` 与 `main.dart.js` 均返回 HTTP 200；这不是浏览器交互通过证据。按用户要求未提交、未写后端 API 或自动 E2E。

Web Chrome 定点诊断补证：本机 Flutter 测试服务的 `/canvaskit/canvaskit.js` 和 `/canvaskit/canvaskit.wasm` 均返回 404，`/flutter.js` 返回 200。Windows 上本机 Flutter SDK 测试服务器将请求路径转换为反斜线后，仍用正斜线 `canvaskit/` 前缀判断；最小测试停在 `Running test suite`，中止时显示 `No tests ran.`。这是测试基础设施故障的定位，不是缓存断言结果；Web Flutter 缓存测试仍未执行。本轮未修改共享 Flutter SDK。

每日单词页面的时区现取自账号范围的设置仓储快照，日期选择器在缓存 scope 关闭时退场，重新绑定账号后以新账号时区的今日重建；迟到的旧日期选择不再回写。作者在修改前实点手机/电脑原型的日期切换，定点 widget **2/2**、两文件 `flutter analyze` 无问题。主 Agent 非作者定点审阅该作用域路径，没有发现阻断；最终 APK/浏览器实装仍需重新构建核对。

正式入口只读审计：`HarukaApp` 已装配认证、API、缓存协调器与账号绑定，但正式路由仅覆盖先前账号/材料参考/收藏等页面；完整业务新页面只在独立预览路由中注册。`routes.dart` 仍静态导入预览组件，多个页面直接读取 `PreviewStoreScope`，预览专用 `QueryPrefill` 也读取预览设置缓存。不能把预览 Widget 直接挂到正式路由当作已接线：需要按认证作用域装配对应仓储，并抽离双端页面壳及预填。此次审计未新增一个与原型不同的空 Query 页面，也未改正式路由。
