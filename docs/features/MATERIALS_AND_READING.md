# 材料、书库与阅读功能契约

状态：Draft v0.1，2026-09-22；全部为待实现设计。需求依据为 [PRD](../product/PRD.md)，公共响应、版本冲突及幂等以 [API 契约](../architecture/API_CONTRACTS.md) 为准，执行与事务以 [数据与任务](../architecture/DATA_AND_JOBS.md) 为准。本文定义普通材料、阅读与出处；[试卷模式](EXAM_MODE.md) 是考试的唯一详细协议。

## 1. 范围与入口

| 功能 | P0 | 后续边界 |
| --- | --- | --- |
| 文件导入 | MD、EPUB，学习材料/试卷显式模式 | 普通 PDF/OCR/TXT 为 P1；字幕为 P2；文本 PDF/扫描试卷的首版范围仍待确认 |
| 书库 | 最近在读、类型/语言筛选、标题搜索、分页、材料详情、改标题/类型、删除 | 不增加共享书库、公开材料市场或整库导出 |
| 阅读 | 连续阅读、目录、横排基础排版、选区、进度、书签、阅读历史 | 分页、双语层、热力图为 P1；高保真 EPUB 竖排/复杂注音是否必须仍待确认 |
| 教材 | 单元树、正文/词汇表/习题块、按题型原生作答 | 合并/拆分普通章节、完成度、讲练分屏为 P1；试卷必要校对已经是 P0 |
| 出处 | 版本化锚点、跨平台选区、原文回跳、重解析重绑与删除后快照 | 全文语义检索和跨材料关系检索不作为 P0 依赖 |

书库需要 `client.material.list`，阅读/目录/内容需要 `client.material.read`；进入时先取得当前访问快照，再请求本人数据。没有导入权限时空库提供说明，不展示可提交的导入按钮。无 Key 不阻断确定性解析和已经可读的材料；AI 分析单独显示待配置状态。

本专题新增权限草案为 `client.material.reparse/analyze`、`client.reading.progress.update`、`client.bookmark.read/create/delete`（斜线表示独立代码）。全部 scope=self，由 [权限目录](../architecture/PERMISSION_CATALOG.md) 登记；所有入口仍遵守 [RBAC](../architecture/ADMIN_AND_RBAC.md) 和 [认证与隔离](../architecture/AUTH_AND_ISOLATION.md)。读取授权不隐含写进度/书签授权，导入/重解析权限不隐含付费 AI 分析权限。

## 2. 导入：从选择文件到可读

### 正常操作

1. 打开“导入”，选择学习材料或试卷，再通过系统文件选择器选文件。展示格式、大小上限、目标语可选项与 AI 准备说明；明确选择“仅解析原文”或“解析后 AI 分析”，保存 requested_stages。取消文件选择不创建导入任务。
2. 前端检查扩展名和体积供即时提示；后端再次检查真实文件类型、配额、权限与剩余存储。普通材料要求 `client.material.import`；试卷同时要求 `client.exam.import`。
3. 创建短期 `MaterialImport`/上传意图；客户端只获得临时 staging_key 的受限写入能力、大小限制和到期时间。完成确认按 [不可变对象发布协议](../architecture/DATA_AND_JOBS.md) 领取 completion_generation/租约，由服务端复制/流式写入其独占的新 final_key，再校验 final 对象真实字节、大小、完整摘要和格式，不相信客户端 MIME 或先前 staging HEAD 结果。
4. final 对象通过验证后，PG 事务重查所有者/当前权限、意图有效性、completion_generation/租约与未取消状态，再发布 FileObject、Material、初始解析 Job 和 Outbox，返回材料与任务 ID。重复确认同一意图和相同载荷返回同一结果；相同幂等键用于不同载荷返回冲突。客户端从不获得 final_key 的 PUT 权限，重试不覆盖已发布对象。
5. Worker 只读取该已验证的不可变 final 对象，安全解包并解析。MD 保留标题层级、列表、表格和代码；EPUB 按包清单、spine、章节顺序取正文。所有稳定 ID、源文本及定位由应用生成，AI 只能提供语义候选。临时对象被重复 PUT、复制中变更或发布事务失败时按中央协议拒绝/清理，不能将未验证的新字节交给 Worker。
6. 普通材料的完整确定性正文提交为可读版本后，书库显示“可阅读，AI 分析中/待配置”。已有目录的 EPUB 不等待模型重新切章。解析不完整的章节列入质量报告，不静默标成完整成功。
7. 已明确请求的 AI 分类/语言提示/习题抽取，另需 `client.material.analyze`、本人 Key 和预算，在付费前重新检查后异步执行；保存类型化结果、来源和置信度。复合请求没有所需权限时受理前拒绝，界面可让用户另选“仅解析原文”，不得静默付费或默默只做一半。尚无 Key 时可以明确保存为“待配置后由我继续”，补 Key 不自动启动旧付费阶段。返回的 ID 仅可引用本次版本已存在的块，模型不能替换原文。用户已手动确认的标题/类型不得被迟到分析覆盖。
8. 质量页展示可读章节、失败区段、已抽习题和需处理项。普通材料 P0 可修改类型；试卷必须进入独立校对/ready 流程，不能沿用“已有文本即可开考”。

推荐文件上限沿用 PRD：MD 20 MB、EPUB 50 MB；PDF 80 MB/TXT 20 MB 只在对应格式获准上线时生效。服务端配置同时限制解包文件数、解压后总量/单项体积、解析时间、图片尺寸和层级；具体值通过样本与容量测试定版，不能只限制压缩包字节数。上传限额按用户预留，完成/取消/超时释放，防止并行意图绕过配额。

EPUB/嵌入 HTML 不执行脚本、不加载远程 CSS/图片、不允许解包路径穿越或读宿主文件。外部链接作为用户显式打开的链接处理，不由解析 Worker 任意抓取。加密/DRM、损坏包、空正文、不支持格式给出安全错误类别；保留可说明的失败报告，不输出服务器路径或文件正文到日志。

### 状态与恢复

`MaterialImport` 状态为 `awaiting_upload → verifying → accepted`，分支为 `expired/cancelled/rejected`；可读内容状态为 `parsing → readable/degraded/failed`；AI 分析状态独立为 `not_requested/pending_credentials/queued/running/ready/failed/unknown_outcome`。这些是领域状态，不替代 Job 的统一运行状态。未完全验证的上传不允许阅读或分析。

| 情况 | 用户看到的结果 | 技术处理 |
| --- | --- | --- |
| 文件选择取消/尚未完成上传 | 未导入；可重新选文件 | 撤销意图的新签发能力，临时对象按到期规则清理；已签 URL 的剩余有效期限制见认证文档 |
| 上传中断 | 上传失败，可重试 | 同一有效意图重试同一文件；换文件建新意图；完成确认幂等，不按文件名去重 |
| 相同文件已存在 | 提示已有材料，可打开或明确再导入 | 摘要只在本人范围比较；明确再次导入创建新 Material，不泄漏其他用户重复情况 |
| 原始解析失败 | 不显示“可阅读”，提供重试/删除 | 修复输入需新意图；可恢复任务按已提交阶段重试，不重复写正文 |
| AI 缺 Key/失败 | 已解析内容仍可读，明确哪项未准备 | 更新配置后显式继续分析；供应商不确定完成状态不自动无限重试 |
| 取消深度分析 | 原文和已提交分析仍可用 | 停止后续步骤；在途供应商可能已计费；不回滚可读版本 |
| 改类型与 AI 完成竞争 | 手动值保留 | 字段保存 provenance 与 revision；AI 只更新未手动锁定字段，冲突重新读取 |
| 撤权/禁用/删除期间 Worker 运行 | 保留已提交数据，后续受限步骤停止 | 领取、付费及提交前检查当前权限、所有者和 tombstone；无效旧任务不得让材料复活 |

重试需要当前 `client.job.retry` 并重新验证原业务动作、用户意图、来源和预算。取消只需有效身份/当前受众登录、本人的 Job、`client.job.cancel` 及可取消状态，不要求仍持有已撤销的导入/分析/生成权限；它不能启动新步骤或读取失权结果。查询需要 `client.job.read`，读取结果另验所属能力权限。关闭页面不等同取消。对已经存在的材料执行完整重解析还需要 `client.material.reparse`；其目的和影响必须在按钮确认页说明。

## 3. 书库、详情、类型与删除

书库默认“全部”，类型集合包括小说、教材、试卷、其他，语言可多选。最近在读使用已提交的阅读进度和最后打开时间，试卷显示独立开考/继续/成绩状态。标题搜索为当前用户标题匹配，不声称已实现全文或向量搜索。按服务端排序键与 ID 稳定分页，切筛选清空旧游标，迟到响应不能混入新筛选。

材料卡显示标题、类型、语言、解析/分析状态和实际可用计数；估计阅读时长/难度标记为估计。缺元数据使用文件名等确定回退值，不伪造作者。详情页提供目录、质量报告、最近进度和有权执行的编辑/重试/删除操作。

改标题/普通类型使用 `expected_revision`。类型仅改变默认皮肤，不重建正文 ID；`notes` 使用基础阅读器，`textbook/workbook/mixed` 使用教材布局，夹在普通文本中的习题仍由题型控件渲染。普通材料转试卷需同时取得 `client.exam.import` 并创建试卷准备版本；后续校对/确认另需 exam.edit，AI 抽取另需 material.analyze。原有考试场次继续绑定自身冻结版本，更改皮肤不能改写已交答卷或开启未校对试卷。

删除要求 `client.material.delete`，展示“移除原文和阅读入口；收藏/历史作答保留快照”的确认。先事务写 tombstone、停止新增任务/签名并从列表移除，异步清理未被保留业务版本引用的原文件/缓存。其他设备下一次访问返回已删除状态并清除相关缓存；不承诺离线设备即时清除。已有收藏/练习/考试历史的正文快照和必要题图由对应业务版本保留，不级联删除学习记录；保留的考试版本只经考试授权接口访问，不变成普通原文下载旁路。此操作不增加回收站/整库恢复产品功能。

## 4. 内容版本与出处协议

### 不可变内容与选区

推荐 `source_locator` 使用 `locator_schema_version=1`；最低字段如下。字段是业务存储与接口契约，不得作为日志自由属性上传。

| 字段 | 含义 |
| --- | --- |
| instance_id / library_id | 原始服务实例/资料库标识，仅作为来源提示，绝不授予访问权 |
| material_id / material_revision_id | 本账号材料与不可变内容版本 |
| node_id / block_id / sentence_id | 目录、正文块和可选句子；跨块选区使用按顺序的 spans，不能伪造单块偏移 |
| spans[].start / end | 对对应块 canonical_text 的 Unicode scalar value 偏移；左闭右开，禁止负数、反向和越界 |
| text_protocol_version | `canonical-text-v1`：解析后实体解码、换行统一 LF；不做隐式 NFC/NFKC 或语义改写 |
| original_locator | 原格式适配位置，例如 EPUB spine/document/DOM 路径、MD 标题与行区间、未来 PDF 页码/区域 |
| quote / prefix / suffix | 选区及前后文快照，用于显示和重绑校验；不单凭相同文字跨材料匹配 |
| source_title / node_title | 显示用标题快照，标题不参与身份和归属判断 |

Flutter 的 UTF-16 code unit 索引在平台适配层转换为协议偏移，Python 不直接接受未声明单位的客户端整数。文本渲染与 canonical_text 有显式映射：行折叠/换行不改变存储文本；ruby 的基础文字参与原文选区，注音作为独立注释，不混入基础字符串索引。使用字素边界进行人类可见选区，服务端验证 scalar 边界与 quote 一致；组合字符和 emoji 不允许被截成无意义半段。实现时需同时验证索引与字素规则，不能把“Unicode 字符”当作 Dart/Python 相同的索引单位。

选区支持 token、phrase、sentence、excerpt。建议摘录上限为 500 个 scalar value 或 5 句，先到为准；超限要求缩小，不静默截断。英文可按词边界，日文/中文使用语种规则/分词适配并允许扩展选区；代码块、表格等无法形成连续句子的内容仍保留块范围，不捏造 sentence_id。前端把选区引用传给服务端，由服务端重取正文；手工输入明确标记无材料来源。

### 回跳与重新解析

1. 点击来源先请求授权解析 locator；验证当前用户、材料状态、内容版本、块和范围。
2. 精确有效时打开对应版本章节并高亮，不用当前章节的相同偏移代替旧版本。
3. 新版本发布后，按原格式位置、文本指纹和上下文寻找重绑候选；唯一且校验通过才保存映射。多候选/不一致标记 `ambiguous/unresolved`，保留原快照，不猜测回跳。
4. 原版本不可读或材料已删除时显示快照和原因，禁用原文导航；不因书名相同自动关联另一材料。失去权限时不返回私有上下文以解释错误。

重新解析永远创建新 MaterialRevision；在完整基础校验后原子切换 current_revision_id，失败保留当前可读版本。阅读位置、书签、收藏、题目和考试场次引用原版本，不在切换时覆盖历史。客户端提示有新版并允许重新加载；选区/音频队列不会在后台无提示切换文本版本。

## 5. 阅读、教材、进度与书签

进入阅读页先取得材料元数据与目录，再按需加载章节。状态区分加载、就绪、可用缓存、权限失效、版本变化、材料已删除和加载错误；章节失败允许单章重试，不反复重新导入整本书。前端列表使用稳定块 ID，主题/字号变化只触发布局，不重新生成服务器锚点。

连续阅读支持目录跳转、长按/鼠标划选、书签和历史返回。主题/字号/行距来自用户偏好；朗读高亮只表达当前已确认播放的片段，不能仅按估计计时跳句。选区工具栏分别检查解释、收藏、Agent 和朗读动作权限；阅读权限不自动允许任何付费操作。解释/TTS 见 [AI 与朗读](AI_AND_TTS.md)。

阅读进度保存 `last_locator`、`furthest_locator`、当前内容版本、`revision` 和服务端接受时间。当前位置允许向前或向后移动；最远进度仅在同一版本按内容顺序单调增加，不能用它覆盖“我回头读到哪里”。阅读百分比按版本的确定文本顺序估算，不作为学习完成证明。

在线时按停留/章节切换/离开页做有界防抖保存；每次带 `expected_revision` 和本地递增操作序号。多端冲突返回服务器位置，界面提供继续本设备当前位置或跳到服务器位置，显式选择后用最新 revision 再写，不用客户端时间戳悄悄覆盖。没有写进度权限时阅读可用但提示不会跨设备同步；离线仅保留本次视图位置供当前页面使用，不排队业务写入。

书签保存 locator 与可选短标题，创建/删除幂等；重复点击同一精确锚点提示已存在，可直接定位。P0 不做书签全文搜索或层级文件夹。阅读历史记录当前用户的已接受打开事件与位置，计数依据业务表，客户端埋点不直接写学习统计。日后删除/重解析按出处状态显示，不抛出不可恢复页面错误。

教材页按 Unit → Lesson → 课文/语法/词汇/习题导航；大屏侧栏、小屏可折叠顶部/抽屉目录。词汇表每行可点读、收藏、进入手动练习；P0 “加入复习”表示收藏/学习中或加入手动待练集合，不虚构 SRS 到期队列。普通习题提交后逐题反馈，协议见 [收藏与练习](COLLECTIONS_AND_PRACTICE.md)；试卷布局严格走整卷流程。

## 6. 技术映射与事件

以下是未来 API 路径草案，尚无运行端点；方法、DTO、幂等和统一错误由 [API 契约](../architecture/API_CONTRACTS.md) 收口。所有写入校验本人范围，所有对象 ID、游标和嵌套引用都视为不可信。

| 操作与 API 草案 | 权限 | 数据/任务 | 事件（提交与体验分开） |
| --- | --- | --- | --- |
| `POST /api/v1/material-imports`、`POST /uploads/{upload_id}/complete`、`GET /material-imports/{id}` | material.import；exam 模式追加 exam.import | MaterialImport 与 UploadIntent 绑定、FileObject、Material、Job/Outbox | material.import.requested/completed/failed，附 stage |
| `DELETE /api/v1/material-imports/{id}` | material.import，仅本人未接受意图 | 意图取消与临时对象清理 | material.import.cancelled |
| `GET /api/v1/materials`、`GET /materials/{id}` | material.list/read | Material、ReadingProgress、计数投影 | screen.viewed、material.opened |
| `PATCH /api/v1/materials/{id}`、`DELETE /materials/{id}` | material.update/delete | revision、tombstone、清理 Outbox | material.updated/deleted |
| `POST /api/v1/materials/{id}/reparse`、`GET /materials/{id}/revisions` | material.reparse/read；重解析有原动作限制 | 新 MaterialRevision、Job/Outbox | material.reparse.requested/completed |
| `POST /api/v1/materials/{id}/analysis` | material.analyze；来源读权限、个人 Key 和预算 | 类型化分析结果、AiRun、Job/Outbox | material.analysis.requested/completed/failed |
| `GET /api/v1/materials/{id}/revisions/{revision_id}/chapters/{node_id}`、`POST /sources/resolve` | material.read；按引用类型追加其读取权限 | StructureNode、ContentBlock、Sentence、AnchorMapping | reading.chapter.opened、source.navigation.result |
| `GET/PUT /api/v1/materials/{id}/progress` | material.read / reading.progress.update | ReadingProgress、ReadingHistory | reading.progress.saved、reading.session.ended |
| `GET/POST /api/v1/bookmarks`、`DELETE /bookmarks/{id}` | bookmark.read/create/delete，均须 material.read；请求提供本人材料/locator | Bookmark | bookmark.created/deleted |

表内后续省略 `/api/v1` 的路径与首项同前缀，权限省略 `client.`。`sources/resolve` 支持业务引用 ID，返回可访问目标或安全的不可用状态，不能作为任意 locator 读取其他私有对象的代理。登录/audience/当前授权检查不因表格省略而取消。

事件均通过 [统一日志与埋点](../engineering/OBSERVABILITY.md) 白名单，允许阶段、格式、计数、状态、耗时和受控资源 ID；禁止原文、文件名全文、选区、查询词、原文件路径和签名 URL。前端打开体验与后端进度提交分别记录，后台分析结束不等于用户已经阅读。

## 7. 三端与后续功能

| 平台 | P0 操作要求 |
| --- | --- |
| Windows | 文件对话框、鼠标/键盘选区、目录快捷导航、缩放后出处映射；系统取消文件选择无失败弹窗 |
| Web | 文件选择/浏览器刷新/深链接、同源会话与 CSRF；缓存可被浏览器回收，重新联网加载；不能假定可直接读用户磁盘路径 |
| Android | 系统文件选择 URI、长按扩选、小屏目录、后台中断后查询已有任务；不要求宽泛存储权限完成基本导入 |

所有平台只在当前账号有效离线租期内展示已有阅读/音频缓存，失效、重新联网和账号切换见 [设置与缓存](SETTINGS_AND_CACHE.md)。

| 后续功能 | 操作与技术边界 | 启用前验收要求 |
| --- | --- | --- |
| P1 普通 PDF/OCR/TXT | 导入选择相应格式，显示页/文本覆盖与质量；PDF 保留页码/区域，OCR 标记来源；TXT 先保留原行序再建议结构 | MAT-P1-01：缺页/空层/旋转/跨页失败可见，不能静默丢页；格式样本确认后才登记上线 |
| P1 普通章节校正 | 版本编辑草稿 → 合并/拆分/标块 → 预览 → 确认新版本；冲突不覆盖旧版本 | MAT-P1-02：已有收藏/作答仍可定位旧版本，编辑失败不影响当前可读版本 |
| P1 分页/双语/翻译层 | 视图分页不改变锚点；原文对照与生成翻译分开标识；句级翻译需本人 Key、版本与独立预算 | READ-P1-01：字体变化/翻页后选区一致，翻译缺失可继续原文阅读 |
| P1 阅读热力图 | 仅本人已授权的阅读/解释/收藏业务聚合，原文不进埋点；无数据不等于未读 | READ-P1-02：跨用户无数据泄漏、计数不因补传重复、删材料显示安全状态 |
| P1 教材完成度/讲练分屏 | 从已提交阅读/Attempt 计算，未评分单独显示；分屏复用同一题目/来源状态 | READ-P1-03：切布局不重复作答，重评后更新一次统计 |
| P2 字幕 | 保留 cue 时间与文本；导入取消/失败按同一协议；不在 P0 注册可用入口 | MAT-P2-01：时间顺序、重叠 cue 与原文定位具有专门样本后再启用 |

## 8. 可判定验收

以下为验收 ID，均未执行；测试样本和记录方法由项目测试/交付规范收口。

| ID | 操作与通过标准 |
| --- | --- |
| MAT-001 | 无 Key 导入有效 MD/EPUB，完整确定性正文可读，AI 明确待配置，章节顺序与人工样本一致 |
| MAT-002 | 重复上传完成确认、Worker 重投/重启仅创建一次该意图的材料与版本；主动再次导入创建独立材料 |
| MAT-003 | 损坏 EPUB、路径穿越/异常压缩、超限文件、MIME 不符被拒绝或隔离；无宿主文件/远程请求读取 |
| MAT-004 | 用户 A 替换 B 的意图/材料/对象/章节/任务 ID 全部不可访问；批量引用逐项检查 |
| MAT-005 | 手动改类型后迟到 AI 不覆盖；新解析失败保留旧版；取消分析保留已可读原文 |
| MAT-006 | 删除与 Worker 完成竞争不会让材料重新出现；收藏和既有作答保留快照；旧文件下载签发被阻断 |
| MAT-007 | 撤销 material.analyze 后，仍有登录与本人 job.cancel 的用户能停止既有分析任务；不能借取消读取结果、重试或新建付费步骤 |
| MAT-008 | 重复预签名 PUT、校验前后覆盖、复制中改源、完成/取消竞争和发布失败符合 DAT-08：Worker只读验证后的final对象，孤立对象可回收 |
| READ-001 | 日/英/中、组合字符、emoji、ruby 基础字、跨块选区在三端保存并回跳同一文本，越界或 quote 不符拒绝 |
| READ-002 | 改字号/主题和切小说/教材皮肤后正文 ID 不变；混合材料的习题仍为原生控件 |
| READ-003 | 同账号多端进度冲突显式处理，回读不被最远进度覆盖；无写权限可读且不能更新进度/书签 |
| READ-004 | 重解析唯一重绑正确，多候选不猜测；删材料保留来源快照，跨账号/同名材料不得误绑 |
| READ-005 | 受限页面/工具和直接 API 一致；联网撤权及退出清除对应状态，离线租期到期不继续显示私有内容 |
| READ-006 | 操作、解析、阅读和回跳事件可关联到任务；日志不含原文/选区/文件秘密，页面重建不重复记录业务成功 |
