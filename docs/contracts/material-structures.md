# 三类材料解析数据结构

状态：2026-09-23，设计基线，未实现。本文是上传完成后三类材料“保存什么、如何关联、怎样版本化”的唯一详细契约；类型选择与处理边界见[三类材料](material-types.md)，展示分类见[教材与试卷展示](learning-presentation.md)，用户流程分别见[小说](../modules/novels.md)、[课本](../modules/textbooks.md)和[试卷](../modules/exams.md)。

本协议中的Manifest、AudioBinding、PlaybackPolicy是逻辑输出对象，不要求各建一表。物理映射以[材料字典](../architecture/database-materials.md)为准：小说/课本头在各自material_revisions，AudioBinding状态在synthesis spec，播放规则在冻结listening binding；三类专用schema/处理/页面与隐藏字段裁剪保持独立。

DESIGN20小说基础NLP必须覆盖所有已发布正文句子，按章报告覆盖/失败：Sentence与Token保留源范围、词形/词性/活用及可得读音，注音附在范围上并区分原书/派生/不确定来源，不写入canonical_text。AI详解与TTS仍是独立成品，按[章节多选准备](novel-preparation.md)处理；语言标注完成不代表这些成品已就绪。

DESIGN23将[格式提取与原书ruby](source-extraction.md)和[全应用NLP](../architecture/text-analysis.md)接入现有流程：EPUB直接解析，扫描/图像PDF和图片走本人视觉模型；可靠PDF文本层仅在正文/注音对应通过检查时可直接提取。源ruby存ContentBlock.presentation_payload，与NLP补充读音分开；所有已提交学习字段共享标注协议，源类型/版本及领域结构仍独立。

## 1. 分层原则

上传、源提取、领域解析和消费投影是四个不同结果，不能用一个大JSON或一个成功状态代替：

1. 上传只验证并发布不可变源文件，不表示内容已经可读、可学习或可开考。
2. 公共来源层保存原始顺序、规范文本、二进制资产和可回跳定位，只表达“来源中有什么”。
3. 小说、课本、试卷分别把来源编排成 `NovelManifest`、`TextbookManifest`、`ExamPaperVersion`，各自拥有状态、校验和版本。
4. Flutter只消费有版本的类型化DTO，不直接渲染模型JSON、数据库行或未发布候选。

三类可以共用身份、文件、出处、任务、文本标注、TTS和小型无副作用组件；不能共用一个带大量可空字段、`is_exam/is_textbook`分支和统一状态机的万能内容树。关系身份、顺序、状态和版本存PostgreSQL，原文件/图片/音频存MinIO；JSONB只承载已注册且有界的类型化载荷，不把整本书或整张试卷塞入单行JSONB。

## 2. 导入草稿与不可变来源

首版正常导入包含一个 `primary_document`。试卷在材料创建后可另行上传文字版听力稿；它不是第四种材料，也不改变主文件格式范围：

| 对象 | 关键字段/关系 | 规则 |
| --- | --- | --- |
| MaterialImport | owner/library、material_type、primary_upload_intent、requested_stages、idempotency、状态 | 选择类型后不可原地修改；完成只创建对应材料和初始Job |
| UploadIntent/FileObject | purpose、staging/final对象、实际格式/大小/摘要、owner、状态 | 客户端只写staging；服务端发布不可变final对象；P0拒绝exam原始音频用途 |
| Material | owner/library、固定material_type、current_revision_id、delete_generation | 三类共用书库身份，不承载专用正文/题目JSON |
| MaterialRevision | material、source_schema_version、processor_version、源资产集合、状态 | 不可变；修正文/源结构创建新版本，失败不切当前版本 |
| SourceAsset | material_revision、purpose、file_object、媒体事实 | 原书、内嵌图片、受控派生图等；用途不授予额外读取权限 |
| SourceUnit | material_revision、kind、ordinal、parent、locator | EPUB spine、Markdown区段、获准PDF页/区域等；保持原顺序和层级 |
| ContentBlock | source_unit、block_kind、canonical_text、order、source_locator | 标题/段落/列表/表格/图注等可追溯原文单元；不是通用阅读页面 |
| ImportIssue | revision、stage、kind、severity、source_refs、状态 | 缺页、残缺关系、答案混入、听力缺稿等；问题关闭必须有确定修订或用户确认 |

文字听力稿使用专用 `exam_listening_script` UploadIntent，P0只接受后端能力目录允许的UTF-8纯文本/Markdown，不执行HTML/脚本、不加载外部资源、不接受音频伪装；它在完成验证后建立不可变`ExamListeningScriptSource`，不会替换主试卷文件。具体体积和字符上限由配置与真实样本锁定，必须独立于整本TXT材料格式是否开放。

## 3. 公共来源与领域身份

每个领域节点只引用同一owner/library/material/revision下的来源块、文本范围或受控资产。AI可以返回源范围、角色和关系候选，稳定ID由应用创建；服务端验证引用存在、顺序/范围有效、树无环、版本一致和当前状态后才保存候选或发布结果。模型给出的user_id、对象键、外部URL、数据库ID或最终ready结论一律不可信。

规范文本与展示富文本分开。`canonical_text`及字符偏移是选区、分句、出处和TTS的稳定依据；标题样式、注音、表格跨度、说话人等由领域结构引用同一来源。确定性格式提取、视觉转写稿、用户校正和AI生成内容保存不同`content_origin`，不能把AI补写内容标成原文。

本项目不使用数据库物理外键。所有跨表关系仍保留逻辑父ID、owner/library/material_revision和revision；写入、重绑、发布、删除和GC在带ScopeContext的服务事务中校验共同父行/代次并遵守固定锁顺序。本文列出的持久业务对象都按[数据库规范](../engineering/database.md)使用UTC带时区`created_at/updated_at`和公共TimestampMixin；候选确认、批量/upsert及状态变更显式维护`updated_at`，普通修订不能覆盖`created_at`。

## 4. 三类独立领域结构

### 4.1 小说

| 对象 | 主要结构 | 说明 |
| --- | --- | --- |
| NovelManifest | material_revision、schema_version、chapter_order、quality_summary、published_at | 小说当前可读编排；不包含课本角色或考试状态 |
| NovelChapter | manifest、title/source_title、ordinal、source_refs | 原目录优先；无目录可建明确标记的“未分章正文”，不捏造章名 |
| NovelChapterBlock | chapter、ordinal、source_block/range、display_role | paragraph/dialogue/quote/footnote/illustration等；保持连续阅读顺序 |
| TextAnalysisVersion | 已注册source/version、pipeline、各语言引擎/词典版本与覆盖状态 | 小说分支绑定MaterialRevision；共用全应用NLP，不替换正文版本 |
| TextAnalysisUnit/Sentence及token值对象 | 不可变字段/块快照、有序spans、分词/ruby数组 | 句子独立ID可跨有证据连续的unit；表格/图注/脚注不误拼正文；物理粒度见[统一NLP](../architecture/text-analysis.md) |
| SpeechSegmentBinding | sentence/range、playback_manifest/segment | 朗读派生引用，不将音频URL写回正文 |

小说修正章序、规范文本或块归属时创建新的MaterialRevision/NovelManifest；仅重做分句、分词或词形时创建新的分析版本。阅读位置、收藏和解释保留原版本出处及必要快照，不按文本相同自动迁移。

### 4.2 课本

| 对象 | 主要结构 | 说明 |
| --- | --- | --- |
| TextbookManifest | material_revision、schema_version、unit_order、准备摘要 | 课本目录和可靠/受限内容概览 |
| TextbookUnit/Lesson | parent、ordinal、title、source_refs、quality_state | 按原书教学次序组织，不按角色重排整本书 |
| TextbookContentNode | lesson、ordinal、role、source_refs、typed_payload | role限定为展示契约的课文/对话/词表/语法/例译/图注/表格/习题 |
| TextbookContentEdge | from/to、relation_kind、evidence_refs、确认状态 | translation_of、caption_of、example_of、exercise_for、answer_for等有向关系 |
| DialogueTurn/VocabularyRow/TableCell | content_node、稳定行/轮/格身份及顺序 | 保存说话人、词表列、表头和合并跨度，不展平成段落 |
| ExerciseBinding | content_node、exercise/group/stimulus引用、来源/答案状态 | 公共题型服务负责作答；课本只绑定Lesson和展示顺序 |

八类是受控角色而非八个页面。低置信度或未知块保留SourceUnit/ContentBlock和质量问题；可靠课文仍可学习，残缺习题受限。答案附录可以是来源用途，但答案绑定必须与题面分离，不能作为普通正文返回。

### 4.3 试卷

| 对象 | 主要结构 | 说明 |
| --- | --- | --- |
| ExamPaper/ExamPaperVersion | material_revision、schema_version、状态、题序/总分/时限、辅助规则、冻结版本 | preparing/needs_review/ready；已开始场次固定原版本 |
| ExamSection | version、ordinal、说明、分值规则、source_refs | 大题/分区容器，不重复累计子题分数 |
| ExamStimulus | version、kind、source_refs、visibility、ordinal | reading/image/table/listening；作为题组共享材料，不是可评分叶子 |
| ExamItem | section/group、business_type、interaction_type、delivery_mode、ordinal、points、source_refs | `delivery_mode=visual/listening/mixed/unknown`；作答控件与业务题型分开 |
| ExamOption/ExamBlank | item、稳定身份、顺序/位置、题面载荷 | 选项/空位不以数组下标作为长期身份 |
| ExamStimulusItemBinding | stimulus、item、ordinal、evidence_refs、确认状态 | 一份共享材料可对应多题；AI只能提出候选 |
| ExamGradingBasis | item/group、答案/rubric版本、来源、确认状态 | 服务端专用投影；不进入题面、TTS或Semantics |
| ExamPreparationIssue | version、kind、target_refs、状态、resolution | 分值/答案/结构/听力标记/脚本绑定/音频缺失等校对待办 |

试卷不使用NovelChapter或TextbookLesson承载题目。题面、评分依据、听力脚本、生成音频和答卷分别投影；题面DTO不包含答案、rubric、隐藏脚本或完整原件读取能力。

## 5. 文字听力稿、AI候选与TTS绑定

### 5.1 首版输入与候选结构

P0支持两种听力脚本来源：

1. 用户为本人试卷上传文字版听力稿，形成独立`ExamListeningScriptSource/Version`。
2. 试卷主文件正文、附录或已发布视觉转写中存在听力原文时，AI从有权源范围提出脚本候选。

原始音频上传、音频转写、波形切段、根据音频内容自动绑定题目不在P0；相关用途必须在上传/API层拒绝并列入后续待办，不能用通用FileObject或外链绕过。

AI结构化输出至少包含：

| 字段 | 规则 |
| --- | --- |
| listening_item_candidates | 对每道题给出`visual/listening/mixed/unknown`候选、原文证据和需复核原因；不能只在有脚本时才标记听力题 |
| script_candidates | 脚本来源版本/范围、语言、有序段落、可选speaker_label、来源类型和质量问题；不得改写原稿冒充提取 |
| script_item_binding_candidates | script_candidate与题组/小题候选关系、顺序、源证据和`confidence_status`；不使用模型自报概率作为自动发布门槛 |
| unresolved_cues | “听下面材料”等指令存在但缺脚本/题号、题目范围冲突、多脚本竞争或答案泄漏嫌疑 |

应用把AI结果保存为有代次的候选，不直接修改ExamItem或冻结版本。每个疑似听力题必须生成`listening_type_review`，每个脚本/题目匹配生成`listening_binding_review`；缺脚本生成`listening_script_missing`，已确认绑定但未有可播放资产生成`listening_audio_missing`。用户可确认、修正文稿/说话人/顺序、改绑题组或拒绝错误候选；确认动作保存操作者、源候选版本和expected_revision。迟到旧run不能覆盖新一轮候选或人工确认。

### 5.2 领域对象与冻结

| 对象 | 关键字段/关系 | 发布要求 |
| --- | --- | --- |
| ExamListeningScriptSource | exam、基准material/paper revision、source_kind=`uploaded_text/exam_content`、上传稿file_object或正文source_refs、摘要 | 本人来源、不可变；上传文本直接引用专用purpose的不可变FileObject，不修改既有MaterialRevision的SourceAsset集合；上传文本和主卷提取不混成一个身份 |
| ExamListeningScriptVersion | source、language、revision、父版本/编辑来源、规范文本协议、origin/confirmed_at | 每一版保存自身权威规范文本或有序segment集合；人工替换、插入、删除或重排均形成新版本，不改旧版文本/偏移 |
| ExamListeningScriptSegment | script_version、ordinal、canonical_text、可选speaker_label/pause提示、provenance_refs | locator偏移只指向本segment的不可变canonical_text；上传稿的FileObject范围、正文ContentBlock范围或父脚本编辑操作只作为出处，不冒充当前文本容器 |
| ExamListeningBinding | exam_version草稿、stimulus、script_version、item_ids、order、确认状态 | 全部题目同版本/同owner；用户确认后才能用于合成或ready |
| ExamListeningSynthesisSpec | binding、provider/model/credential引用、voice映射、格式/参数、配置摘要 | 从能力目录选择；不把Key/任意SSML/Header放入脚本 |
| ExamListeningAudioBinding | binding、synthesis_spec、AudioAsset/PlaybackManifest、状态、duration/segment映射 | ready音频通过真实格式/解码/完整性验证；绑定精确资产版本 |
| ExamPlaybackPolicy | stimulus、play_limit_mode=`unlimited/finite`、有限时的max_plays、pause/seek/速度/字幕可见策略 | 用户校对确认并随ExamPaperVersion冻结；不由客户端开考后任改，有限次数必须由服务端账本执行 |
| ExamSessionListeningUsage | exam_session、stimulus、冻结上限、reserved/consumed计数、revision | 每场次×Stimulus唯一；随场次创建并持久保存，刷新、重启、布局切换或跨端接管都不能重置 |
| ExamListeningPlayAttempt | usage、play_attempt_id、idempotency_key、edit_epoch、`reserved/active/completed/closed_unknown/void`状态、reservation/resume期限、资产/Manifest版本、持久交付游标与首字节/终段事实 | 每次播放领取的权威记录；并发请求在场次与usage锁内占位，同一幂等键只返回同一attempt；终态不可重新打开 |

听力脚本属于私人考试内容，TTS使用本人`client.speech.generate`、Key和上限，通过统一SpeechService/Job生成私有AudioAsset；不进入global_word共享目录。相同本人、脚本版本、语言、声音/模型/参数和格式可命中持久音频，不因开考、刷新、签名过期或播放器倍速重新调用供应商。修改脚本、合成声音或参数产生新spec/音频绑定；既有场次继续使用冻结资产。

生成前程序确认脚本来源不属于答案/rubric/隐藏解析投影，并把Prompt/控制指令与朗读正文分开；AI匹配和用户确认都不能让答案区借TTS进入题面。多说话人只有能力目录和实际模型验证支持时才开放；不支持时要求用户选择有效方案，不静默合并或改用系统TTS。

脚本locator是可辨识联合类型。`material_content`分支的范围指向MaterialRevision下的ContentBlock规范文本；`exam_listening_script`分支指向确切ScriptVersion/Segment的规范文本。上传FileObject、原试卷ContentBlock和人工编辑操作是provenance，不能替代当前脚本范围。人工改稿后旧locator仍解析旧ScriptVersion；只有应用验证出的唯一映射才可另存重绑候选，不能把相同字符位置直接套到新版。TTS segment映射也固定到确切ScriptVersion/Segment及PlaybackManifest时间范围。

### 5.3 ready、开考与故障

包含听力题的版本只有在下列条件全部满足时才能ready：听力题标记已复核、脚本版本已确认、脚本与全部相关题目的绑定已确认、必要AudioBinding为ready、播放策略已冻结、题面/脚本/评分依据投影无泄漏、版本已记录所需客户端能力。缺Key或TTS失败保留`needs_review/needs_audio`，不能把听力题改成静默文本题；开考时服务端再按客户端协议版本/能力集合校验兼容性，客户端自报不授予权限或绕过ready条件。

开考前服务端重查exam/session/speech.play及来源权限，客户端预检并取得全部必要音频的可用授权；必要听力未就绪时不创建已计时场次。场次冻结paper_version、listening/audio binding和playback policy。作答期间的必要音频故障沿用考试媒体故障事实：保留答案/截止，服务端确认后受影响题待复核且不误记零分；单端网络失败不自行改变权威成绩。

有限播放次数采用服务端领取协议：用户点击“播放/重新播放”时以`Idempotency-Key + stimulus_id + edit_epoch`请求新play attempt；服务端锁定活动场次和usage，复核所有者、当前编辑端、权限、截止、冻结策略及资产版本，再创建带短租期的`reserved` attempt。`reserved + consumed`达到上限时拒绝新领取，因此两个设备不能同时越额；提交结果丢失后用同一幂等键重试只取得原attempt。媒体端在发出首字节前以CAS把reservation改为`active`并计入consumed，写入按冻结音频时长/暂停策略计算且不超过场次截止的`resume_until_at`；从未被媒体端领取且租期到期的reservation可由受控任务`void`并释放。

预检、列出媒体、预载元数据不计次；`active`且未过续播期限时，同一attempt可刷新Manifest/签名、HTTP Range重连或按冻结seek策略从持久交付游标续播，不另计次。媒体服务确认终段/最终字节已经交付后写`completed`；若进程中断、回执丢失或期限届满而无法证明未交付，写`closed_unknown`。`completed/closed_unknown/void`均为不可逆终态，场次快照不得把它们返回为可续播；显式重播、终态后刷新或从头请求必须用新幂等键领取新attempt并受剩余次数限制。只有在任何字节发出前且服务端能证明未交付的故障才可`void`并释放，客户端自报失败不能返还次数，`active/completed/closed_unknown`都保留已消耗次数。媒体请求同时验证当前edit_epoch，接管使旧端授权失效；新端只可在期限内从同一active attempt的受控游标续播。冻结策略禁止seek时服务端拒绝回退范围；允许seek也只在该attempt的有界active期内生效。有限次数场次不把音频交给通用持久离线缓存，现有缓冲区在attempt终态/接管/退出时失效；首版本就不承诺完整离线考试。此机制只保证应用内计次和恢复，不承诺DRM、阻止录音或防止用户从原文件取得内容。

考试中默认不返回听力脚本文本；交卷后是否显示由冻结的`transcript_visibility`控制。无障碍辅助如果展示字幕或改变播放规则，必须在开考前明确并冻结，成绩页面保留辅助标记；不能在客户端私自从缓存、alt、Semantics或日志取回隐藏脚本。

## 6. 解析、校对与发布流水线

```text
上传并发布FileObject
→ 确定性源提取/获准视觉转写
→ 发布MaterialRevision/SourceUnit/ContentBlock
→ 类型专用Pydantic候选
→ 程序结构/归属/版本校验
→ 保存候选与ImportIssue/PreparationIssue
→ 用户校对必要项
├─ 小说/课本：发布NovelManifest/TextbookManifest → 按需建立语言分析、TTS和消费投影
└─ 试卷：确认听力候选/绑定 → 生成并验证必要TTS资产 → 冻结ExamPaperVersion → 建立题面/场次投影
```

每个供应商调用阶段在Job创建、Worker领取和外部调用前检查当前用户权限、Key/credential_version、上限和输入版本。候选run、人工修订和发布使用各自generation/expected_revision；旧run迟到只保留历史，不能覆盖较新候选、人工确认或当前版本。发布事务只引用已经验证的不可变产物，外部模型/TTS调用和文件解码不持有数据库长事务。

## 7. DTO、兼容与查询

共用书库DTO只返回材料元数据、material_type和安全状态摘要。小说章节、课本Lesson、试卷校对/题面/答案/成绩/听力复盘分别使用类型化端点与DTO；同一个数据库结构不要求在一个响应里暴露。DTO携带`schema_version`和必需能力，旧客户端遇到未知必需结构时阻止不完整消费并提示升级。

列表和详情按当前用户/资料库/版本作用域查询，批量ID也逐项校验。来源回跳使用content locator；有相同文字、题号或文件摘要不能推断跨材料关系。缓存键至少包含instance、user、材料/领域版本、资源ID和投影用途；换账号/撤权/版本变化清理相应副本，不能从媒体缓存或题面缓存恢复隐藏答案/脚本。

## 8. 验收

| ID | 通过标准 |
| --- | --- |
| MSTR-01 | 同一来源分别按小说/课本/试卷处理，公共Source事实可追溯但三种领域结构、状态和DTO互不冒充；不存在万能内容JSON/Reader依赖 |
| MSTR-02 | 小说章序/块与独立语言分析版本正确，重新分句不重写原文或旧出处；课本Unit/Lesson、八类节点及关系保留原序/表格/对话/答案边界 |
| MSTR-03 | 试卷Section/Stimulus/Item/交互/评分依据独立，题组只累计叶子，完整原件/答案/rubric不进入题面、TTS或缓存旁路 |
| MSTR-04 | P0文字听力稿只能通过本人exam专用文本用途上传；原始音频、外链、伪格式和任意FileObject ID均拒绝，主试卷文件不被替换 |
| MSTR-05 | AI对全部疑似听力题返回有证据的类型候选，并提出脚本—题组/小题匹配；缺稿、冲突、低可信和答案泄漏嫌疑形成待办，不能自动冻结 |
| MSTR-06 | 用户可确认/修正/拒绝听力标记、脚本和题目绑定；人工改稿保存新ScriptVersion/Segment规范文本，Unicode替换/插入不改旧locator；并发revision和迟到run不覆盖人工确认，A/B交换脚本/候选/绑定ID被拒绝 |
| MSTR-07 | 确认脚本经本人Key生成私有持久TTS，缓存命中不发起供应商调用；音频segment只映射确切脚本版本，改脚本/声音产生新绑定，旧场次仍播放冻结资产且无系统TTS回退 |
| MSTR-08 | 缺脚本/未确认匹配/未生成音频/能力不支持均阻止听力试卷ready；先验证必要音频再冻结版本；开考前预检音频，作答中确认故障不把受影响空答记零 |
| MSTR-09 | 三端不在考试中泄漏隐藏听力稿；播放次数/暂停/拖动/字幕策略随版本冻结，有限次数由持久账本在并发领取、丢响应、Range/签名刷新、刷新/跨端接管后保持一致；active续播有界且只沿持久游标，completed/closed_unknown后从头播放必须新领次数；换账号、撤权和缓存清理不串音频或脚本 |
| MSTR-10 | 原始音频上传、转写、切段及自动绑定明确不在P0，接口不能提前接受；后续实现必须另验格式、版权/隐私、对齐、TTS/原音优先级和迁移 |

## 9. 后续边界

P1待办为用户上传原始听力音频并自动绑定试卷题目。开始前必须锁定允许格式/时长/大小、恶意媒体与转码沙箱、音频转写是否需要、波形/片段对齐、多个音频与题号歧义、用户校对、原音与生成TTS优先级、版权/隐私、缓存/下载和旧试卷迁移；未完成这些契约前，P0只接收文字稿并生成TTS。

录音作答、口语识别/评分、监考、班级发布和完整QTI导入仍不因增加听力播放而进入首版。试卷主文件格式范围继续由OPEN-01维护；文字稿附件不代表开放任意TXT书籍、Word或音频材料导入。
