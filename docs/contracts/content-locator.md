# 内容版本、选区与出处协议

状态：2026-09-23，设计基线，尚未实现。本篇为材料、收藏、卡片、题目与CSV共用的出处协议唯一正文；用户操作见 [材料与阅读](../modules/materials-reading.md)，源层/三类领域结构见 [解析数据结构](material-structures.md)，资源归属见 [认证与隔离](../architecture/authentication.md)。

题目直接收藏引用已校验题目版本及必要的场次/作答身份，服务端按[收藏投影](../modules/vocabulary-practice.md#题目直接收藏)重取可见字段。试卷交卷成功后允许选区引用当前有权复盘文字，未发布评分/隐藏听力稿仍拒绝；提交状态必须从本人场次读取，客户端locator不授予交卷后权限。

DESIGN20解析模式的ruby/rt是展示层注音，复制原文、查询quote、scalar偏移和TTS输入均以基文本为准，不能从包含注音的DOM textContent直接构造来源。点句必须回到已发布Sentence的完整源范围；章准备绑定源/标注版本，校正注音不能静默改写旧句子/音频的含义，见[章节准备](novel-preparation.md)。

DESIGN23的[统一NLP](../architecture/text-analysis.md)使用TextAnalysisSentence有序unit spans和注册业务字段映射；原书ruby按[提取契约](source-extraction.md)单独保存。非材料字段项ID在发布时由应用分配并冻结；版本变化重取相应标注，不能按相同字符位置跨版本绑定。unit快照不授予额外读取权，完整来源与现行权限仍逐次验证。

## 1. 不可变内容与选区

推荐 `source_locator` 使用 `locator_schema_version=1`，并以`target_kind`作为可辨识联合类型。所有分支共用以下信封字段；字段是业务存储与接口契约，不得作为日志自由属性上传。

| 字段 | 含义 |
| --- | --- |
| instance_id / library_id | 原始服务实例/资料库标识，仅作为来源提示，绝不授予访问权 |
| target_kind | 决定目标分支及必需字段；未知分支拒绝解析，不能靠字段为空猜测 |
| text_protocol_version | `canonical-text-v1`：解析后实体解码、换行统一 LF；不做隐式 NFC/NFKC 或语义改写 |
| quote / prefix / suffix | 选区及前后文快照，用于显示和重绑校验；不单凭相同文字跨材料匹配 |
| source_title / node_title | 显示用标题快照，标题不参与身份和归属判断 |

`material_content`分支必须包含`material_id/material_revision_id`、一个或多个按序`spans[{block_id,start,end}]`以及可选`node_id/sentence_id/original_locator`。start/end是对应ContentBlock `canonical_text`的Unicode scalar value左闭右开偏移，禁止负数、反向和越界；跨块选区不能伪造成单块范围。领域回跳字段按类型附加：小说为`novel_chapter_id/chapter_block_id`，课本为`textbook_lesson_id/content_node_id`，试卷正文为`exam_paper_version_id/stimulus_id/item_id`。这些字段只是回跳提示，服务端仍从MaterialRevision和领域聚合验证归属、版本与可见投影。

`exam_listening_script`分支必须包含`exam_paper_version_id/script_source_id/script_version_id`和一个或多个`spans[{segment_id,start,end}]`；偏移目标是该不可变ExamListeningScriptSegment的`canonical_text`，而不是原试卷ContentBlock或上传FileObject。每个ScriptVersion保存自身权威规范文本/有序segment。来源另存为provenance：正文提取稿可指向原MaterialRevision/ContentBlock locator，上传稿可指向专用purpose的不可变FileObject原始字节范围，人工改稿可指向父ScriptVersion和受控编辑操作；这些出处都不改变当前span目标。正式`ExamListeningBinding`另存stimulus/item稳定ID和确认代次，不把模型候选关系塞入locator。生成音频segment映射只能回指已确认ScriptVersion/Segment及经验证的PlaybackManifest时间边界，不能臆造原始音频时间码。题面投影、普通`POST sources/resolve`和Semantics不返回隐藏听力稿，只有获准的准备/复盘端点按冻结可见性解析。

视觉OCR来源遵循 [识别合同](../architecture/vision-recognition.md)：original_locator保存应用确定的源页/裁切区及坐标变换；模型候选字框未经验证不能成为精确原图锚点。source_method=vision的转写块保存其识别版本，字符偏移指向该已发布规范文本；无可靠字框时只回跳源页/区域，重识别不改旧版含义。

Flutter 的 UTF-16 code unit 索引在平台适配层转换为协议偏移，Python 不直接接受未声明单位的客户端整数。文本渲染与 canonical_text 有显式映射：行折叠/换行不改变存储文本；ruby 的基础文字参与原文选区，注音作为独立注释，不混入基础字符串索引。使用字素边界进行人类可见选区，服务端验证 scalar 边界与 quote 一致；组合字符和 emoji 不允许被截成无意义半段。实现时需同时验证索引与字素规则，不能把“Unicode 字符”当作 Dart/Python 相同的索引单位。

选区支持 token、phrase、sentence、excerpt。建议摘录上限为 500 个 scalar value 或 5 句，先到为准；超限要求缩小，不静默截断。英文可按词边界，日文/中文使用语种规则/分词适配并允许扩展选区；代码块、表格等无法形成连续句子的内容仍保留块范围，不捏造 sentence_id。前端把选区引用传给服务端，由服务端重取正文；手工输入明确标记无材料来源。

### 1.1 非材料学习文字的选区

全局朗读/查询同时接纳受控业务资源的已发布文字；它们使用现有请求的 `source_ref`，不伪装成 `material_content`。引用包括资源种类、资源ID、不可变版本/修订号，以及白名单可见文本字段的有序范围；每个范围携带字段标识/数组项稳定身份、scalar `start/end` 与 `quote`。字段路径必须由该资源schema注册，不能接受任意JSONPath或客户端正文作为权威数据。解释、学习卡片、收藏快照、普通习题/已发布反馈、诊断分别验证资源读取动作与字段可见性，校验方法与材料选区的偏移/字素规则一致。

服务端按本人资源版本重取字段文本，检查完整提交、范围、原文和当前可见性，再构建有限上下文或TTS输入。用户看到的格式/标题不替代字段身份；流式半成品、隐藏答案、试卷隐藏听力稿或未发布评分字段不可被引用。跨字段选择保存多个有序span，不能拼成一个虚构正文偏移。AI解释和例句保留生成内容身份；材料locator仅作上游追溯，不能把生成句映射成原书原句。

受控资源选区参与解释/TTS的严格缓存键、幂等摘要与版本校验；修改选区、源版本或可见字段不能命中另一来源的私有结果。权限撤销后，即使命中缓存仍拒绝操作。收藏新查询结果保存完整卡片版本及其来源链，源对象删除时遵循既有快照保留/失权规则。此处不为临时选区增建表或改变物理关系；使用现有来源组与版本化载荷，正式DTO/schema实现需按资源枚举约束。

### 1.2 分词气泡与多范围查询

DESIGN18的气泡是当前句的派生视图，保持原文顺序、标点及稳定范围；自动分词不改canonical_text，也不在点击时创建AI调用或新来源。语种标注/词典版本与原文版本分别保存；缺失或分错时可按字素手动调整，最后仍转换为本篇的scalar偏移。

查询携带受控父句/字段范围与有序选择范围集合，服务端逐项重取并验证归属、版本、字素边界和可见性。没有点词时使用父句范围；相邻词合并为原文连续span（保留之间的空格/标点），不相邻词保持多个查询目标，不把间隔内容伪装成已选短语。结果按目标返回卡片/不可用状态，每张卡保留自己的目标范围及合法原句上下文；收藏只引用完整结果版本。

不连续目标首版每次最多3组，与单轮卡片上限一致；相邻词组计为一组，超限要求减少选择，不能静默丢弃目标。多范围是一项有界语言查询意图，统一幂等摘要包含顺序、每段精确范围/文本、父句及模式，限额按所有目标与上下文累计，不允许逐词拆调用绕过上限。临时分词、选中气泡、原文高亮及播放器位置为客户端状态，不新增数据库表或Redis权威状态。

DESIGN22查询补充前后文按[上下文契约](query-context.md)由服务端另取有权范围；locator的prefix/suffix仍用于显示/重绑，不代替实际ContextPlan，也不受扩大预算授权读取更多资源。上下文与目标范围分别记录，多目标去重后统一计预算。

## 2. 回跳与重新解析

1. 点击来源先请求授权解析 locator；验证当前用户、材料状态、内容版本、块和范围。
2. 精确有效时按服务端确认的材料类型，打开对应版本的小说章节、课本 Lesson/内容区或获准考试来源视图并高亮，不用当前版本相同偏移代替旧版；听力稿仅在获准的试卷准备/复盘投影中解析。三类分派及考试内容投影见 [材料类型契约](material-types.md)。
3. 新MaterialRevision或ScriptVersion发布后，按原格式位置、父版编辑映射、文本指纹和上下文寻找重绑候选；唯一且校验通过才保存映射。替换/插入/删除、组合字符或emoji变化都必须重新计算scalar范围和quote，不能沿用旧数字；多候选/不一致标记 `ambiguous/unresolved`，保留旧版locator和快照，不猜测回跳。
4. 原版本不可读或材料已删除时显示快照和原因，禁用原文导航；不因书名相同自动关联另一材料。失去权限时不返回私有上下文以解释错误。

重新解析永远创建新 MaterialRevision；在对应类型的源内容完整性校验后原子切换 current_revision_id，失败保留当前可读版本。源版本发布不代替课本习题或试卷冻结版本的就绪检查。阅读位置、书签、收藏、题目和考试场次引用原版本，不在切换时覆盖历史。客户端提示有新版并允许重新加载；选区/音频队列不会在后台无提示切换文本版本。仅升级派生语言标注遵循材料类型契约，不重新解释旧 sentence_id，块级选区不依赖最新分词结果。

## 3. 消费与验证

材料阅读、收藏/错题/生成题、AI卡片、CSV导入及考试版本共用此协议；字段校验不能替代当前权限、所有者、用途投影和冻结版本检查。听力候选、正式绑定和音频资产分别保存自身版本/关系，locator只证明可追溯来源，不能作为AI候选已被人工确认或音频已经ready的证据。至少验证上传稿规范化、正文提取、人工替换/插入、组合字符/emoji、旧版回跳、TTS segment映射和隐藏稿拒绝；功能文档引用本篇，不另定义偏移单位、规范化版本或重绑规则。

验收沿用材料模块READ-001、READ-002、READ-004及CSV/考试对应案例；本次仅迁移原协议，未创建新的实现或通过记录。
