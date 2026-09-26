# 当前原型功能与实施切片

状态：2026-09-26，PLAN2。用户已确认：当前手机、电脑 HTML 原型表达的全部产品功能都属于当前 v0.1 必须实现范围。B0、B1沿用既定范围与证据；B2之后按[路线图](roadmap.md)重排。本文是功能追踪清单，不表示正式应用已经实现。

基线：[手机原型](../../prototype/phone.html)、[电脑原型](../../prototype/desktop.html)及其当前脚本，检视基线提交 `246a980`。详见[走查与审查记录](reviews/2026-09-26-prototype-implementation-plan.md)。后续修改原型时同步本表，新增操作不能只留在演示里。模块中的全部既有P0要求仍由[覆盖索引](coverage.md)追踪，不能以原型没有画出为由删除。

## 1. 判定方式

- “当前范围”指本次 v0.1 的完整交付范围，不意味着把所有功能塞进正在实施的B1；全部必需项在阶段6发布签收前关闭。
- 每行的按钮、选择项、弹窗、状态及返回行为均须实现。行是功能组，不能只完成一个按钮就勾选整行；工程开始时拆成可定位的UI/API/平台用例并链接证据。
- 模拟生成、预览策略、头像说明、书签提示、固定示例题等表达的是正式能力需求。生产实现必须具备真实保存/授权/任务/结果，不能用toast、定时器或固定样本代替。
- 原型的虚构账号、原型说明、状态样例切换、模拟计时及固定1/3道示例数据属于演示工具；不作为生产旁路。它们呈现的错误/空态、正式计时、题量配置和恢复行为仍须验收。
- 手机原型代表紧凑布局需求；正式手机端须另外取得Android相册/相机、权限拒绝、返回/进程恢复等真机证据。电脑原型代表宽屏/键盘需求，Windows与Web各自验收。
- 文件选择器未限制扩展名，不构成“支持全部格式”的承诺。材料格式沿用产品范围与OPEN-01门禁；完整试卷导入功能不得省略。已有查询图片/拍照、单图识词、CSV仍为当前范围。

## 2. 全量功能分配

所有行初始状态均为“待正式实现/验收”；B1部分能力的实际完成状态由B1工程记录维护。下表只指定首交付和收口位置，不提前勾选。

| ID | 原型功能及必须覆盖的操作 | 首交付 → 完整收口 | 权威正文 / 验收 |
| --- | --- | --- | --- |
| UI-01 | 五个主入口、手机详情隐藏全局导航、电脑宽窄布局；返回/前进/刷新/深链、原列表位置和焦点恢复、资源已删的安全返回 | B1壳内既定路径；各页面切片 → R1 | [Flutter](../engineering/flutter.md)、[设计语言](../product/design-language.md)，FLT/UIE/DESIGN |
| UI-02 | 登录、注册、所选激活、找回/重置与受理状态；密码显隐/确认、字段错误、密码不恢复；本人安全、退出、首次引导完成/跳过 | B1账号不变；B2a引导；B2b审批/人工恢复扩展 | [账号](../modules/accounts.md)，SCF-B1/ACC |
| UI-03 | 原生服务地址校验、无凭据探测、实例/版本兼容提示、切实例清理与重新登录；Web显示当前部署 | B2a | [设置](../modules/settings.md)，SET/CACHE |
| UI-04 | 材料类型筛选、标题/语言搜索、手机展开/清空/关闭、无材料与无匹配空态、重置筛选、三类直接进入专用页 | M1 | [材料](../modules/materials-reading.md)，MAT/TYPE/READ |
| UI-05 | 三步导入：类型、文件/可选AI结构建议、确认；返回修改/取消、校验失败、持久任务受理与进度 | M1；试卷M4 | [材料](../modules/materials-reading.md)、[结构](../contracts/material-structures.md)，MAT/TYPE/MSTR |
| UI-06 | 材料更多菜单、详情/来源/状态、删除确认与取消；保留合法收藏/历史，迟到任务不能复活 | M1 → E2冻结引用回归 | [材料](../modules/materials-reading.md)、[数据](../architecture/data-jobs.md)，MAT/DAT |
| UI-07 | 手机任务页/电脑任务抽屉、连接状态、分阶段进度、未就绪不可进入、完成后跳转、失败恢复 | B2c任务基础 → M1及后续任务 | [进度](../contracts/job-progress.md)，WSP-01～05 |
| UI-08 | 小说章节目录/位置、阅读与解析模式/ruby、宽屏非模态panel与手机dialog；字体/字号/行高/阅读主题、书签 | M2；AI内容L2 | [小说](../modules/novels.md)、[设置](../modules/settings.md)，NOV/READ/SET |
| UI-09 | 点句详解：原句、翻译、分块/语法、上/下一句、来源、已准备/未准备状态、朗读、完整收藏及嵌套查询返回 | L2 → L4/L5 | [AI朗读](../modules/ai-speech.md)、[缓存](../architecture/learning-cache.md)，AI/SEL/LC |
| UI-10 | 章节选择、解析/朗读两个checkbox默认全选、空选禁用、开始/暂停/继续/失败重试、分项进度/服务端和本机就绪、只补缺项 | L5，依赖M2/L2/L4 | [章节准备](../contracts/novel-preparation.md)，NPREP-01～06 |
| UI-11 | 长按/Alt+Enter整句浮层、正文高亮、相邻或非相邻词气泡多选、起止范围调整、整句喇叭/查询/关闭；普通划选不自动弹层 | M2定位 → L2/L4；P1/P4/E2新增文字 | [选区](../modules/ai-speech.md)、[NLP](../architecture/text-analysis.md)，SEL/NLP/QRY-10 |
| UI-12 | 单词小喇叭、单句朗读、从当前句到章末连续播放、句级高亮与进度、暂停/继续/停止、0.7–1.5倍速；查询/长按/短音频打断后手动继续、离页清理 | L4/L5 → E2复盘来源 | [朗读](../modules/ai-speech.md)、[小说](../modules/novels.md)，TTS/TTSA/NOV-005 |
| UI-13 | 教材单元目录、课文/词表/语法/例句译文和来源弹窗、词发音；独立课后题、选择/提交/反馈/重做、作答前后直接收藏 | M3结构 → L2/L4辅助 → P1作答 | [课本](../modules/textbooks.md)、[展示](../contracts/learning-presentation.md)，TBK/PRES/PRA/COL |
| UI-14 | 试卷准备清单、题号/题组/分值校对、听力脚本候选确认/改绑/拒绝、生成音频、就绪/冻结与考前说明；缺条件阻断 | M4结构 → L5音频 → E1开考 | [试卷](../modules/exams.md)、[结构](../contracts/material-structures.md)，MSTR/PRES |
| UI-15 | 整卷单栏/宽屏并看、题号/答题卡、已答状态、标记/取消、上下一题、保存/离开确认/继续、听力、交卷确认与返回 | E1 | [试卷](../modules/exams.md)，考试清单/PRES/MSTR-08～09 |
| UI-16 | 交卷后的成绩/完整题面/选项/本人答案/可见参考与反馈、直接收藏、选区查询朗读、错题和材料回跳；交卷前限制学习辅助及未开放参考内容 | E2，复用L/P切片 | [试卷](../modules/exams.md)、[收藏](../modules/vocabulary-practice.md)，COL-005/006/QRY-10 |
| UI-17 | 六类混合收藏列表与类型筛选、按词形/读音/释义搜索、空态恢复、整行键盘/触控详情、词发音、当前本出题入口 | L1 → L4/P2 | [单词本](../modules/vocabulary-notebooks.md)，COL/VNB |
| UI-18 | 切本/全部收藏dialog、新建名称与语言、改名/简介、删本仅解除归类、同一条目归入多个同语种本 | L1 | [单词本](../modules/vocabulary-notebooks.md)，VNB-01～05/10～12 |
| UI-19 | 手动单词/短语/句子/语法/摘录、编辑内容/释义/笔记、AI卡片保留完整快照仅改个人信息；来源/日期/只读掌握、回原文及来源已删提示 | L1，B1保留最小收藏；P3掌握投影 | [收藏](../modules/vocabulary-practice.md)、[单词本](../modules/vocabulary-notebooks.md)，COL/VNB/VL |
| UI-20 | 每日单词按本人时区与实际加入日期、跨本去重、空日期/历史、直接发音 | L1 → L4 | [单词本](../modules/vocabulary-notebooks.md)，VNB-12/TTS |
| UI-21 | CSV选择/预览、重复跳过或补空字段、确认/行级结果、导出与系统保存；恢复协议允许的词本和笔记 | L3，依赖L1 | [CSV](../contracts/vocabulary-csv.md)，CSV清单/VNB-09/VL交叉边界 |
| UI-22 | 独立文字/纯图/图文查询、四类示例填入、输入限制、AI自动判任务、相册/相机/选择/粘贴、缩略图/放大/移除/错误草稿、图片绑定当前输入 | L2 | [查询](../modules/query.md)，QRY-01～10/PHOTO适用分支 |
| UI-23 | Word/Sentence/Grammar/Exercise四类完整卡片，语法对比/例句/翻译分块/习题订正、来源证据、归本/重复反馈/再查一个；未完成或不合法结果不可收藏 | L2；P1/P4/E2新来源回归 | [查询](../modules/query.md)、[卡片](../modules/ai-speech.md)，QRY/AI/COL/NLP/LC |
| UI-24 | 可选补充上下文、结果前后文/当前句/补充内容折叠展示、预算快捷/自定义与保存；仅对新请求生效，缓存复用 | B2a设置 → M2取文 → L2全部查询 | [上下文](../contracts/query-context.md)，QCTX-01～05 |
| UI-25 | 出题两步骤、日英语言、单本/多本/全部词/手选收藏/教材单元/当前或收藏或全部错题/诊断多来源；去重预览、语境填空/词义选择/翻译判断及1/5/10题配置、不足提示与显式允许一源多题、返回保留/条件变更重新确认 | P2基础来源 → P3错题 → P4诊断 | [AI习题](../modules/ai-exercises.md)，AIX-01～10 |
| UI-26 | 已有练习、提交/反馈/重做/直接收藏；错题全部/当前/收藏统计、详情/收藏切换/针对性生成；诊断薄弱点/亮点/依据/原文和出题动作 | P1～P4 → E2补考试事实 | [练习](../modules/vocabulary-practice.md)、[学习证据](../architecture/vocabulary-learning.md)，PRA/AIX/VL/DIAG |
| UI-27 | 显示名/出生年份/性别/时区、头像更换与私有读取、人口资料进AI显式选择；多母语/解释语/学习语/当前语/水平、八类目标、保存与冲突 | B2a | [设置](../modules/settings.md)，ACC-11/12/PROFILE |
| UI-28 | 系统/明/暗主题、减少动态、高对比、阅读预览与保存；键盘/触摸/dialog焦点/退出、新卡片动效/收藏反馈不重复播放 | B2a基础；各页面 → R1 | [设计语言](../product/design-language.md)、[Flutter](../engineering/flutter.md)，DESIGN/FLT/SET |
| UI-29 | 个人Key保存/单能力测试/轮换/撤销、文本/视觉/TTS各自状态；本人用量时间筛选、input/output/cache及未知分项 | B2c基础及各能力测试；M/L/P/E新调用增量 | [设置](../modules/settings.md)、[用量](../contracts/model-usage.md)，SET/USAGE/SCF-B2 |
| UI-30 | 朗读模型及有效声音、本机播放格式、朗读风格、倍速保存；能力不支持明确提示，格式派生/倍速正确复用 | L4 | [设置](../modules/settings.md)、[适配](../architecture/tts-adapters.md)，SET/TTSA/LC |
| UI-31 | 本机解释/音频与服务端已保存成果分开统计、清理确认/部分失败、文本和音频独立容量保存、占用保护/淘汰/按权回源 | L2文本持久缓存 → L4两类容量/统计/清理设置 → L5下载 | [设置](../modules/settings.md)、[缓存](../architecture/learning-cache.md)，CACHE/LC-01～13 |
| UI-32 | 站内消息列表、未读数、打开即读、全部已读、有权资源跳转；撤权/删除后安全降级，刷新/多端已读持久一致 | M1通知完整交付；后续任务逐项接入 | [消息契约](../contracts/notifications.md)，NTF-01～05 |
| UI-33 | 用户/管理安全页、改密、会话撤销与退出、切换受众重新登录 | B1既定范围；B2b完整管理页面 | [账号](../modules/accounts.md)、[后台](../modules/admin.md)，ACC/ADM/PERM |
| UI-34 | 管理概览、用户搜索/运维摘要/会话、角色成员/权限/受保护角色、两端菜单、注册验证/恢复策略、任务资源/审计/用量/安全；预览后真实提交 | B2b治理及审批/人工恢复全流程/B2c任务用量；随M/L/P/E接入 → R2 | [后台](../modules/admin.md)、[授权](../architecture/authorization.md)，ADM/PERM/USAGE/OPS |
| UI-35 | 空态、loading、断网、失权、失败/unknown、取消/重试/返回操作、稳定布局与不丢输入；成功以提交事实判定 | 每个小阶段 → R1/R2 | [返回](../contracts/api-responses.md)、[任务](../architecture/data-jobs.md)、[测试](../engineering/testing/strategy.md) |

## 3. 容易漏掉的范围边界

1. 中文手动词本/收藏选项保留为本人组织与辅助文字能力，在L1实现；不将中文开放为材料上传、正式中文NLP或AI出题目标语。正式能力不足明确降级范围选择，不能擅自隐藏既有组织功能。
2. 缓存容量和本机播放格式/朗读风格为当前范围。P1只保留未呈现的全局下载中心、固定保留、扩展管理，不包括已确认章节准备和分项缓存设置。
3. 语法卡片里的“に/へ对比”属于GrammarCard；个人目标里的“口语”属于档案偏好，不扩成新ContrastCard或口语评分。
4. 查询多图附件与多图批量词表是不同功能；前者当前实现，后者仍按P1。原始试卷音频上传/转写/切段未在当前原型提供，仍受P0拒绝规则约束。
5. 原型只有预览/说明的后台策略、个人Key、头像等均须按既有真实契约实现；不把点击说明视为通过。原型未提供的已确认P0如安全恢复、删错误生成题、完整五类考试输入，同样按覆盖索引交付。

## 4. 工程签收格式

每行在所属小阶段登记：子操作清单 → UI/API/权限/错误/事件契约 → 实现文件/迁移 → 必需case与平台 → 实际结果 → 独立review → commit。跨阶段行单列已关闭分支及剩余切片，不重复累计通过率。阶段6核对UI-01～35和覆盖索引全部P0，任何未关闭必需分支阻断发布签收；不得为了数字通过删行、隐藏入口或改为P1。
