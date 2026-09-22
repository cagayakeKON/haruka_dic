# 收藏、拍照识词、普通练习与学习诊断

状态：Draft v0.1，2026-09-22；尚未实现。依据 [PRD](../product/PRD.md)，共享 [API 契约](../architecture/API_CONTRACTS.md)、[数据与任务](../architecture/DATA_AND_JOBS.md)、[权限目录](../architecture/PERMISSION_CATALOG.md) 和 [AI 运行层](../architecture/AGENT_RUNTIME.md)。本文不复制 [单词 CSV](VOCABULARY_CSV.md) 字段协议或 [试卷模式](EXAM_MODE.md) 的整卷状态机。

## 1. 功能和授权边界

P0 覆盖词/短语/句/摘录收藏、笔记/标签/筛选/基础搜索/重复合并、单图词表识别、教材题重做、从收藏/错题生成选择/填空/句译、普通逐题评分、错题本、成绩反馈标记、7/30 天或本教材的证据诊断。SRS、匹配/排序/听写、扩展写作、人工改分/申诉裁决、学习计划等仍按 PRD 的 P1/P2 交付。

新增权限草案为 `client.vocabulary.photo.import`、`client.practice.generate`、`client.practice.grade.request`、`client.practice.review.request`、`client.diagnosis.read/generate`（斜线表示独立代码）。已有收藏 CRUD、练习 read/start/answer、Agent、解释和 TTS 权限继续独立检查；新增代码由中央目录登记，全部范围为 self。页面“能打开”不意味着有全部付费/写入能力。

每项操作按当前会话、受众、账号/动作权限、数据归属、业务状态和预算判断。读书时点收藏需要读取该来源的权限与 `client.collection.create`；照片识别需要 photo.import 和视觉配置，确认按选中行的实际动作组合授权：新增需 collection.create，读取/跳过重复预览需 collection.read，补空合并还需 collection.update；开始既有练习不暗含生成新题或 AI 评分授权。

## 2. 收藏：创建、编辑、搜索、合并与删除

### 创建与来源

入口包括阅读选区、解释卡、Agent 卡、教材/练习解析、CSV 和拍照预览。前四类由后端验证业务引用，重取选区/卡片正文并保存上下文；来源协议以 [材料与阅读](MATERIALS_AND_READING.md) 为准。确实由用户在对话中输入的词标记 agent 来源并保存解释快照，不能虚构材料锚点。CSV/照片无需材料也能创建。

创建表单包含 kind、显示文本、目标语、lemma/读音/释义（可空）、笔记、标签及掌握状态。默认 kind 由选区建议，用户可改；多语混排要求确认当前目标语。词典形是建议数据，用户编辑后不会被后续 AI 静默改回；用于搜索/匹配的规范化值与原始显示文本分开。

点击保存带 Idempotency-Key，服务端事务保存 CollectionItem 与来源快照，成功返回稳定 ID 和 revision。保存中禁止重复创建；网络结果未知时查询/重试同一幂等键，不能先显示“已收藏”然后永久丢失。完全相同的既有来源可以提示已收藏，不把相同 lemma 的不同出处自动折叠成一条。

笔记和标签不会作为日志属性或裸 HTML 渲染。字段长度/标签数量限制由 schema 和配置统一发布，前后端一致；超长输入显示限制且保留本次编辑以便修改，不静默截断。标签属于本人库，传入其他用户 tag_id 拒绝。

### 列表与更新

收藏页按类型、目标语、来源材料、标签、掌握状态筛选；基础搜索覆盖本人表面词/lemma/释义/笔记的文本匹配，不增加 P0 向量检索。查询采用稳定游标和服务端过滤；搜索词只在受控 API 请求中处理，不进入 URL 日志或遥测全文。

掌握状态为 `new/learning/mastered/paused`。P0 是用户可解释的显式状态，不由一次正确作答自动变为 mastered；学习统计记录模型估计，和用户自定状态分开。paused 条目默认不参与自动选题，明确选中“包含暂停项”时才加入。修改状态/笔记/标签使用 collection.update 和 expected_revision，冲突展示服务器版本与本次草稿，由用户选择合并后重提，不静默采用最后写入者。

按 lemma 聚合只改变列表展示，每条出处仍可展开和独立跳转。来源失效显示原文已删除/无法精确定位，保留快照；失去材料读取权限则不通过收藏回跳 API 泄漏受限材料，已独立保存且仍有收藏读取权限的收藏快照按自身授权展示。

### 重复合并与删除

推荐 P0 的合并限制为同语言、同 kind、同规范化 lemma 且相同已确认来源指纹的条目。无来源的导入条目另按 CSV/照片预览的重复规则判断；不同材料/不同语境只聚合展示，不自动合并。合并预览明确主记录、保留字段、标签并集与冲突字段，用户确认后事务执行，需要 collection.update 与 collection.delete。

合并不会把已有非空笔记/释义用空值覆盖；冲突须选定或手工合并。被合并 ID 保存指向主记录的本人内部关系，历史 Attempt/卡片的快照保持原样，防止外键悬空。并发修改任何参与记录使 expected_revision 失效，整次合并回滚后重预览。不同账号记录不能参与同一合并。

删除只移除该收藏，已经生成的题目、答题和卡片保留当时的来源快照；不重新扣减历史答题事实。UI 显示此含义，按当前 revision 删除，重复同一删除按幂等策略返回已完成。正在基于该条目生成新题的 Worker 在提交前重查来源；删除使尚未提交的候选跳过并反馈不足，不以旧任务使收藏复活。

## 3. 单词数据入口与拍照识词

收藏页和设置页的“导出全部单词 CSV”“导出当前筛选单词”“导入单词 CSV”共用同一业务服务。只处理 kind=word，不要求模型 Key，具体字段、转义、预览、重复、分批和取消行为完全服从 [CSV 规范](VOCABULARY_CSV.md)。不将其他收藏类型或全库压成额外文件。

### 单图正常流程

1. 入口显示“拍照/选择词表图片”；Android 可调用系统拍照，Windows/Web 至少提供选图。取消相机/文件选择不创建作业；权限拒绝后仍允许选择本地图片。
2. 选择目标语与释义语言，展示图片预览、旋转/重新选择和可能的识别费用。确认识别前检查 photo.import、本人视觉 Key/能力与额度；没有有效配置时不上传后静默调用其他供应商。
3. 后端创建 `PhotoWordImport` 和受控上传意图，复用 [不可变对象发布](../architecture/DATA_AND_JOBS.md)：客户端仅写 staging，服务端固定新 final 对象并验证真实字节/格式/摘要/像素上限，经 generation/权限/未取消状态校验才发布引用。识别 Worker 只读已验证 final；若去除 EXIF 等无业务用途元数据，产生新的受控派生对象，不原位改写已发布原对象，再以 Job/Outbox 执行 OCR/视觉结构化。具体图片上限为部署配置，入口与后端使用同一值。
4. 识别候选保存为版本化预览行：word、reading、meaning、language、confidence/quality_flags、原图区域引用。AI 返回不等于已写入收藏；识别失败保留任务状态，允许换图或有界重试。
5. 预览显示全部候选行及待确认/错误计数；有 collection.read 才查询并展示已有收藏的重复计数/样例，没有该权限可明确选择“直接新增，不比较已有词表”，不能通过预览侧读旧收藏。用户可改词、释义和语种、删行、增行；低置信度行按 PRD 默认勾选但标记待确认，确认页需要明确接受这些行或排除。空词/非法语种等硬错误必须修正或排除，不静默丢行。
6. 从有权执行的跳过/补空合并/新建策略中选择后确认，发送 expected_revision（预览版本）、选中行及 Idempotency-Key；服务端逐行重新校验实际动作、归属、行值与重复条件。新增需 collection.create；引用/判断既有重复需 collection.read；补空合并另需 collection.update。任一所选动作缺权限则整次确认在写入前拒绝，由用户重新选择，不能静默改成新增或丢掉合并行。新增 origin=photo_import，合并保留已有有效来源。
7. 展示本次新增/补全/跳过/排除数量；有 collection.read 才可进入导入单词列表，无读取权限时只显示本次安全结果。P0 单图确认采用受限批量事务；行数超过上限要求缩小/重拍，不悄悄部分写入。

预览状态为 `awaiting_upload/recognizing/review/committing/completed/failed/cancelled/expired`，与 Job 运行状态分开。用户离开预览不自动提交；过期预览必须重新识别或重新预览，旧确认不能写入。确认时与别端收藏修改冲突，重新生成重复预览后再确认。建议未确认图片/预览按短期保留策略清理，正式保留原图缩略为用户明确选择且仍私有；实际 TTL/容量在部署配置记录，不宣称永久保存原图。

照片重试遵循不确定供应商结果的公共预算规则；取消识别停止后续模型调用，已完成预览仍可明确丢弃。删除临时图片不删除已经确认的单词。P0 不支持多图整卷 OCR；P1 多图上限建议 10 张，并须新增页序、重复行跨图合并和失败图独立重试验收后启用。

## 4. 普通练习创建与题型

### 创建与生成分离

“开始练习”选择目标语、来源、题型和题量。来源包括选定收藏、最近错题、教材原题、近期重复解释的词，以及诊断中的薄弱点。读取每类来源须有对应读权限；隐藏于当前权限的数据不进入候选、计数或模型上下文。

重做现成教材题/已有生成题只需 practice.start 与来源读取权限；生成新题还需 practice.generate、本人文本 Key 和预算。复合请求缺少任一权限时在受理前明确拒绝并提供“练已有题”等可选路径，不能自动改为付费生成或悄悄改变题型。建议默认 10 题（在 PRD 8–15 范围内），允许用户在部署限制内改题量；超限返回校验错误，不静默缩减。

服务端先生成不可变 `PracticePlan`：选定题型、目标语、来源引用/版本、数量、考察点、是否允许补充例句、去重策略。生成阶段持久化为 Job/Outbox，Pydantic AI 给出候选，应用验证题型、选项、空位、答案/rubric、出处和难度提示后才能发布。AI 不自行分配其他用户资源或把生成例当原文。

避免连续考相同 lemma；用户指定“专攻”时放宽。来源仅 3 个词时可明确复用语境或生成标有“补充例句”的题目；不足时报告实际生成数和原因，让用户选择按现有题数开始或继续生成，不能显示请求 10 题实际只有 3 题却仍标全部完成。原教材题标 extracted，变式/生成题标 generated 并保留源题/收藏/Attempt 引用。

### P0 题目契约

| 题型 | 题面 DTO 与输入 | 提交后的评分 |
| --- | --- | --- |
| 单选 | 稳定 option_id，单个选项值 | 可信答案精确匹配；不按显示字母或选项顺序匹配 |
| 多选 | 不重复的 option_id 集合，可清空选择 | 默认集合完全匹配；部分分只能来自冻结的明确 rubric，不临时猜测 |
| 判断 | 明确的 true/false/未作答三态 | 可信答案规则匹配，空答不同于 false |
| 填空/完形 | 稳定 blank_id 到文本的映射，多个空独立输入 | 按各空冻结的可接受形式与规范化配置评分；漏空可提交但记未作答 |
| 句译 | 多行文字和目标语言 | AI 按固定 rubric 评估语义、语法、用词等；无 Key 可保留已提交答案待评分 |
| 原文简答/作文 | 已导入文本题可显示文本输入；专项训练不提前 | 试卷基础评分由考试专题定义；P1 扩展普通写作训练，不能用菜单提前承诺完整写作课程 |

所有题面 DTO 在作答前不返回 answer_json、参考译文、隐藏解析或 rubric 中泄题部分；答案存储使用专用服务端模型。题目含原材料答案区时必须从题面内容中剔除/单独保存。客户端看不到的字段不应已存在其缓存。

生成题的填空答案必须是该句实际使用的形式，可另附词典形用于学习；不将 lemma 当唯一标准答案。低置信度的抽取答案进入待确认/AI 评估路径，不当成可靠规则答案。材料重新解析不修改已发布 ExerciseVersion；重新生成创建新题/版本。

## 5. 练习会话、评分与历史

### 作答顺序和状态

`PracticeSession` 绑定有序 ExerciseVersion、来源计划与当前目标语，状态为 `ready/in_progress/completed/abandoned`；生成 Job 状态与会话状态分离。进入第一题才开始会话时长统计，不把生成等待当答题时间。做题页一题一屏，可前后查看，题干点读需独立 TTS 权限；听写尚未上线时不出现专用听写模式。

P0 普通练习的当前未提交输入只在当前账号页面内暂存，不承诺跨端/离线草稿自动合并。点击提交时发送 session_id、exercise_version_id、稳定 session_item_id、answer、expected_revision 和 Idempotency-Key。服务器先保存不可变 Attempt，再规则评分或创建用户已请求的评分阶段；成功回复才显示“已提交”。同一 session_item 首次有效提交后锁定答案；重做创建新 Attempt/新练习会话，不在历史答案上修改。

网络断开时输入保留在当前页面并显示未提交，恢复后同一请求标识重试；退出/切账号丢弃本地私有输入，已保存的 Attempt 可从历史恢复。未得服务器确认前不能凭动画计入正确率。会话跨设备继续先获取最新已提交题号；同一题提交竞争只接受一次，返回既有 Attempt 或明确冲突。

提交前明确本次选择“仅保存/规则评分”或“提交并 AI 评分”；缺少 grade.request 或有效 Key 时不能提交隐含 AI 的复合动作，但仍可明确选择仅保存答案，之后按权限单独请求评分。普通练习提交后立即显示规则结果或“已提交，AI 评分中/待配置”。用户可继续下一题，不强制等待供应商。末题提交后会话可 completed，但成绩状态仍可能 pending/partial/needs_review，界面分开标记“作答完成”和“批改完成”。提前退出可继续；用户明确结束则 abandoned，已经提交的题仍进入历史，未答题不算错误。

### 评分依据与可恢复性

评分实体建议为 `AttemptGradeRun/AttemptGrade`，绑定 Attempt、题目版本、rubric/规范化规则版本、评分方式和 AiRun。可靠规则题在提交事务内或确定任务中处理；AI 评分需 practice.grade.request，以及用户对提交后评分的明确选择，不由仅有 answer 权限触发付费。首次请求、恢复未完成评分和显式重评区分操作意图。

填空规范化是题目冻结的规则：是否区分大小写、Unicode 兼容形式、全半角/假名宽窄、可选拼写和指定标点。保留原答案，另计算比较值；不得全局删除所有标点/重音/空白导致语义不同却判对。接近答案的部分分只在 rubric 明确允许时执行，超出规则能力才走有界 AI 评估，标记 mode=ai。

AI 输出要求 score、max_score、维度得分、错误标签/片段、建议、参考答案、依据来源和复核信号。应用校验有限数值、分值上下界、维度合计、错误片段属于当前作答、题目/用户映射；不接受模型返回的任意用户 ID、总分或不可追溯证据。分数使用定点/Decimal 语义计算，展示舍入不改变业务值。

评分状态为 `not_requested/queued/running/scored/needs_review/failed/unknown_outcome`；失败、结果不确定和待复核没有正式零分。明确空白的已提交客观题可以按冻结规则判零，必须与服务故障区分。重试同一 run 只恢复未提交结果；显式重评新建 run，保留旧评分与原因，不能静默覆盖。

每个 Attempt 首版只允许一个活动评分 run，重试沿用 run/generation，显式重评创建新代次；最终发布和学习贡献的 CAS 规则以 [数据与任务](../architecture/DATA_AND_JOBS.md) 为唯一依据。首次 needs_review/失败/部分结果不进入正式统计，完整且无待复核项才发布有效评分；新重评未完成/失败不撤旧 effective 成绩与贡献。成功切换有效版本替换一次贡献，不新增作答或重复累计。

P0 “我觉得我是对的”只创建独立 review_status=open 的待审反馈，页面/诊断显示争议标记与数量；不自动改分或撤销既有有效成绩，不赋予用户或管理员人工改分流程。P1 裁决需新有效评分版本和明确审计，不直接编辑旧成绩。模型返回 needs_review 与用户提出异议是不同维度，不能混为一个状态。

错题本只收当前有效且可靠的错题/部分分题，提供语言、错误类型、时间、教材筛选，已纠正有效评分随重算移出。再练原题创建新的作答；变式题保持考察点但有新 ExerciseVersion 和原 Attempt 引用。历史分页展示已答/已评/待评数、规则/AI 来源、当时题面/答案和原文入口；不依赖已删除材料仍存在才能复盘。

## 6. 学习诊断与建议动作

诊断入口为 Agent 的报告页/对话动作，支持最近 7 天、30 天、本教材。读取报告要求 diagnosis.read，新建报告需要 diagnosis.generate、所需来源读权限及本人模型配置；没有生成权限仍可按读取权限看既有报告。报告按 target_language 分区，母语用于解释语言，二者不能混用。

后端先从已提交业务事实计算统计快照：时间窗、语言、评分方法、有效 Attempt 数、已评分/待评/争议数、错误标签计数、相关收藏状态和证据 ID。正确率仅用已发布的有效评分题作分母，并显示样本数；未发布的 needs_review/失败/部分评分不进入正式掌握度，已有效但被用户标争议的记录保留贡献并单列争议数。不同尺度题的“正确率”和“平均得分率”分开，部分分不能被误记成完全答对。窗口使用配置的用户时区解释日期，存储 UTC 边界。

阅读习惯与“反复查询”需要来源于服务端已接受的阅读/解释业务记录。解释原文不进日志；允许用来源 ID、次数和日期的业务聚合。客户端停留时长作为估计行为数据，不当作精确能力或费用事实；离线缺报不能解释为零阅读。

模型只解释统计并选择 3–7 条有证据的薄弱点、已掌握亮点和建议。不足 3 条有证据时只显示实际条数；无数据时明确“数据不足”，提供有权访问的导入/阅读/练习入口，不虚构百分比。报告存储 `data_as_of`、窗口、输入事实版本、证据引用、生成配置版本和结构化结果；后续成绩重评使报告标记“数据已更新”，用户显式刷新才新建报告，不悄悄付费重写。

建议动作只能是受控类型：打开本人收藏/原文、从所述考察点生成练习、开始已有练习。按钮点击重新授权和校验当前来源，不能依赖报告生成时权限或直接执行模型拼出的 URL。生成“8 题”必须把报告的 evidence_refs/knowledge_tags 传给计划服务；来源删除/失权显示无法使用并建议重新生成报告，不换成他人或任意题库。

## 7. API、持久化与事件映射

所有路径为待实现草案，表中省略的路径前缀均为 `/api/v1`，权限省略 `client.`；统一规则见 [API 契约](../architecture/API_CONTRACTS.md)。读取操作同样逐项检查来源引用，管理员不通过这些接口取得他人学习内容。

| 操作 / API 草案 | 权限 | 数据与执行 | 事件 |
| --- | --- | --- | --- |
| `GET/POST /api/v1/collections`、`GET/PATCH/DELETE /collections/{id}` | collection.read/create/update/delete | CollectionItem、SourceSnapshot、Tag，revision | collection.saved/updated/deleted |
| `POST /api/v1/collections/merge` | collection.update + collection.delete | 合并预览引用与事务记录 | collection.merged |
| `GET/POST /api/v1/tags`、`PATCH/DELETE /tags/{id}` | collection.read / collection.update | Tag 与本人关联；删除标签不删收藏 | collection.tags.updated |
| `POST /api/v1/photo-word-imports`、`POST /uploads/{upload_id}/complete` | vocabulary.photo.import，视觉配置/预算 | PhotoWordImport 与 UploadIntent 绑定、FileObject、Job/AiRun | vocabulary.photo.requested/recognized/failed |
| `GET/PATCH /api/v1/photo-word-imports/{id}`、`POST /photo-word-imports/{id}/confirm` | photo.import；读既有重复需 collection.read；确认按行追加 create 或 read/update，缺任一所选权限整次拒绝 | 预览 revision，确认事务与幂等 | vocabulary.photo.previewed/completed |
| `DELETE /api/v1/photo-word-imports/{id}` | photo.import，仅本人临时预览 | 取消/到期清理，不删已确认单词 | vocabulary.photo.cancelled |
| `POST /api/v1/practice-generations`、`GET /practice-generations/{id}` | practice.generate / practice.read，来源读权限 | PracticePlan、ExerciseVersion、Job/Outbox | practice.generation.requested/completed/failed |
| `GET/POST /api/v1/practice-sessions`、`GET /practice-sessions/{id}` | practice.read/start | 会话和固定题序 | practice.started |
| `POST /api/v1/practice-sessions/{id}/answers`、`POST /practice-sessions/{id}/finish` | practice.answer | Attempt、会话 revision、规则评分 | answer.submitted、answer.scored、practice.completed |
| `GET /api/v1/attempts/{id}`、`POST /attempts/{id}/grading-runs` | practice.read / practice.grade.request | AttemptGradeRun、Job/AiRun | answer.grading.requested/scored/failed |
| `POST /api/v1/attempts/{id}/review-requests` | practice.review.request | 独立待审反馈，不自动改分/改变贡献 | answer.review.requested |
| `GET /api/v1/mistakes` | practice.read | 有效评分投影，目标语/时间过滤 | screen.viewed |
| `GET/POST /api/v1/diagnoses`、`GET /diagnoses/{id}` | diagnosis.read/generate，来源读权限 | LearnerProfile/事实快照、DiagnosisReport、Job/AiRun | diagnosis.requested/completed/failed |

预览编辑不是确认；GET 不引发付费生成。通用任务查询/重试/取消走 Job 接口：读取结果需要该结果当前读取权限；重试追加原动作、意图/来源和预算检查；取消仅需有效身份/受众登录、本人范围、job.cancel 和可取消状态，不依赖已撤销的原付费权限。取消付费执行不删除已提交的 Attempt，评分失败不会把 Attempt 回到可随意更改答案状态。

事件只传类型、状态、数量、评分方式、耗时和受控引用，禁止单词/笔记/图片/题干/答案/成绩明细进入日志。服务端提交事件是业务完成依据；前端“看到反馈/点再练”是体验埋点，不直接累计作答。全链路字段与投递遵守 [日志规范](../engineering/OBSERVABILITY.md)。

## 8. 平台差异与后续功能

| 平台 | 需要处理 |
| --- | --- |
| Windows | 键盘选项/输入/下一题、文件选图、长列表与表格预览；焦点切换不误提交 |
| Web | 刷新恢复服务端已提交题、照片文件选择、输入法合成结束再防抖；浏览器后退不创建新 Attempt |
| Android | 拍照权限拒绝/取消、相册/系统图片选择、软键盘遮挡、小屏预览编辑、后台回来查询既有任务 |

三端都以服务端确认和账号代次隔离草稿/结果，不用客户端缓存承担跨账号或完整离线练习同步。没有模型 Key 时允许规则评分和已有题作答，明确标记需要 AI 的待评部分；不静默改成错题或零分。

| 后续能力 | 操作/逻辑边界 | 启用前验收 ID 与标准 |
| --- | --- | --- |
| P1 多图词表 | 最多 10 张的页序/图级状态、合并预览，单图失败可排除并明确结果 | PHOTO-P1-01：跨图重复、乱序、取消和部分失败不会静默丢行或双份确认 |
| P1 匹配/排序/听写/变形 | 新题型 schema、原生控件与评分规则分别注册；听写不返回/显示原文提示，音频失败不计错 | PRA-P1-01：题型版本不兼容给明确提示；听写与 TTS 权限/缓存错误区分；日语活用样本验证 |
| P1 SRS | 到期队列是基于有效作答的独立计划投影；算法/参数版本、时区与暂停状态可追溯 | PRA-P1-02：重复投递/重评不重复延长间隔，暂停不入默认队列，时间边界确定 |
| P1 扩展写作/多句翻译与人工覆盖 | 扩展 rubric；待审 → 明确裁决 → 新有效评分版本，保留原结论 | PRA-P1-03：证据/操作者/修改原因可追溯，更新学习贡献一次，不能直接改旧评分行 |
| P1 计划/错因深析/对比 | 诊断证据和作答快照作为输入，建议落为可编辑计划；现有原文解析仍可 P0 查看 | DIAG-P1-01：数据不足不编造计划成绩，动作目标与证据一致，失权来源不进入上下文 |
| P2 口语/跨材料能力/考试等级估计 | 录音、识别、音素/流利度标准和能力校准另建契约；等级仅估计 | PRA-P2-01：有明确样本、误差/隐私/费用规则后启用；当前不提供可用菜单或效果承诺 |

## 9. 可判定验收

| ID | 操作与通过标准（全部待执行） |
| --- | --- |
| COL-001 | 选区/卡片收藏保存文本、语境和精确来源，Agent 手输项不伪造材料；无 Key 仍可收藏 |
| COL-002 | 同 lemma 不同材料为独立来源；合并只处理确认的重复，冲突回滚，历史引用不悬空 |
| COL-003 | 笔记/标签/状态并发编辑返回冲突，筛选/搜索/分页不泄漏 B 的数据；删除材料仍可看收藏快照 |
| COL-004 | 撤销 create/update/delete 分别影响对应按钮与 API；伪造来源/tag/批量 ID 不越权 |
| PHOTO-001 | 英/日印刷词表单图形成可编辑预览，确认前收藏数不变；低置信度、硬错误与排除数可见 |
| PHOTO-002 | 重复确认只写一次；无 create 不能确认新增，无 read/update 不能读取/合并已有行，Key 无效/取消/模型不确定失败不静默入库或借其他 Key |
| PHOTO-003 | Android 拍照与 Windows/Web 选图可完成；换账号、预览过期和并发词表变更不误归属 |
| PHOTO-004 | 新增+合并混合确认缺任一所需权限整次不写；只有 create 的直接新增流程不返回旧词表；上传覆盖竞争符合 DAT-08 |
| PRA-001 | 只持有 start/answer 可做已有规则题，不能生成新题或付费评分；每个来源/工具重新鉴权 |
| PRA-002 | 3 个词生成练习仍可执行，补充例句明确标识，缺题数量可见；每个题引用本人真实来源 |
| PRA-003 | 选项/多选集合/判断空态/多空稳定 ID 校验正确；提交前 DTO 不含答案/隐藏解析 |
| PRA-004 | 填空活用、大小写/全半角、标点与组合字符按冻结规则处理；可靠规则题调用模型次数为零 |
| PRA-005 | 同题重复提交/多端竞争仅一份 Attempt；恢复已答题和新建重做可区分，未答题不计错 |
| PRA-006 | 模型分值越界、未知题 ID、失败/不确定/待复核保留答案且不计零分；重评保留历史并只替换一次统计贡献 |
| PRA-007 | P0 争议标记不提供人工改分且不自动撤旧有效成绩；未发布待评/待复核不进统计，争议数单列，用户仍可继续练习 |
| DIAG-001 | 无数据不生成虚假薄弱点；7/30 天统计分母、语言与窗口有证据；重评后旧报告明确过期 |
| DIAG-002 | 报告按钮生成的题目考察点对应证据；失权/删除来源不会改用他人数据，目标语切换不串库 |
| PRA-008 | 评分/确认/任务中断与撤权不产生重复事实；日志包含关联与计数但无词表、原文、答案或个人成绩明细 |
