# 全应用学习文字的NLP标注与存储

状态：2026-09-26，DESIGN23，用户确认将统一NLP及存储/缓存方案写入文档；以下为待实现设计。小说全书基础标注、普通学习文字及交卷后学习边界继续有效。本文统一标注合同与发布流程，物理字段唯一维护于[数据库材料与文本分册](database-materials.md#27-全应用派生语言标注)。格式提取和原书注音见[提取契约](../contracts/source-extraction.md)，AI/TTS成品沿用[学习结果缓存](learning-cache.md)。

## 1. 范围与职责

所有已提交、可供学习的自然语言字段进入确定性NLP：断句、分词、词形/词性/活用、可得读音及原文范围。英/日目标语和中文解释文字按对应语言能力处理，混合文字按局部语言标注；中文解释分词不等于增加中文目标语课程。未知语言/无法确定读音明确unsupported/unknown，保留字素选区，不凭空补齐。

| 来源 | 标注单元与范围 | 使用边界 |
| --- | --- | --- |
| 小说 | 全书已发布正文、对话、标题/脚注各自语义块；逐章统计覆盖 | 全书基础NLP自动处理；AI详解/音频按明确所选章节和动作生成 |
| 教材 | 课文段、对话轮次、词表字段、例句/译文、图注、独立表格单元格 | 不跨角色/表格单元格拼句；八类教学结构仍由教材服务拥有 |
| 普通题/试卷 | 有版本的题干、选项、共享材料、已发布反馈 | 答案/脚本等可内部预处理但不能经标注接口泄露；试卷学习操作仅交卷成功后开放 |
| AI解释/卡片/诊断 | 完整结果中的释义、例句、翻译、语法说明和诊断文字 | 保留生成资源/字段身份，不能将生成例句当原书正文；不递归生成新的AI解析 |
| 收藏/用户输入 | 已提交条目的文本/释义/例句/笔记及查询消息文字 | 输入框草稿与流式delta不落永久NLP；编辑按新revision建分析 |

按钮、日期、状态文案、日志和后台运维文字不进入学习NLP。代码/公式/纯数字等注册非自然语言字段保留来源与字素选择，不捏造句子/假名；永久标注只处理有业务保留价值的提交内容。字段是否可读/可学习由领域投影决定，客户端不能用任意JSONPath请求隐藏字段。

`TextAnalysisService`是同一后端工程的公共能力，语种适配器封装分句器/词典/读音规则；不增加独立微服务，不使用用户Key或外部LLM替代基础分词，也不创建零Token AiRun。实际库、词典授权、版本及质量在阶段2样本中锁定，不能将原型Intl.Segmenter当正式日文词形/注音实现。气泡词token与模型计量token不同，不能用于推算10000 tokens查询预算。

## 2. 统一身份、范围与载荷

业务正文仍在原业务表。SourceAdapter枚举可学习字段并建立有界`TextUnit`，保存该字段的不可变文本快照及来源映射；这是标注依据，不是第四种材料或通用题库。不可变来源以其确切版本为准，可编辑收藏/消息则冻结受理时revision；后续编辑不能覆盖快照或让旧标注指向新文字。

分析头唯一识别`owner/library + source_kind + source_resource_id + source_version + pipeline_digest`。source_kind首版登记material_revision/explanation/card/collection_item/exercise_question/exam_paper_version/grading_result/diagnosis_report/agent_message；各分支对应本地实体ID，不使用客户端给定的owner。不可变且无独立修订列的实体版本固定1；其余使用本体的card_revision/revision/question_version/version_number/turn_generation。material_revision直接引用该不可变行ID、source_version=1，不能误把材料根ID当版本ID。

| source_kind | 版本列及新增标注所共锁的来源行 |
| --- | --- |
| material_revision | source_version=1；materials → material_revisions |
| explanation / card | 前者固定1，后者card_revision；沿既有运行/绑定/消息根锁后锁具体explanations/cards行 |
| collection_item | collection_items.revision；锁条目行，标注中不使用只反映掌握输入的learning_revision替代正文revision |
| exercise_question | exercise_questions.question_version；exercise_question_roots → exercise_questions |
| exam_paper_version | 仅冻结ready版本，source_version取version_number；exam_papers → exam_paper_versions；draft/building不可进入此分支 |
| grading_result / diagnosis_report | 固定1；沿既有评分/诊断业务锁后锁具体结果/报告行，只枚举已发布学习文本 |
| agent_message | agent_thread_messages.turn_generation；agent_threads → agent_thread_messages，仅submitted用户文字或committed最终结果 |

既有业务聚合锁在前，分析头/单元锁在后；GC和所有新增引用也锁相同具体来源行，不能由某一SourceAdapter颠倒既有锁序。无材料的源仍属于本人私有library，不使用空owner/假material_id。新来源必须先登记这套读取/版本/锁/删除与字段协议才能接入。

SourceAdapter为每个分支登记：锁定的业务根、精确版本读取、字段白名单/稳定数组项ID、权限/考试可见性、删除代次及GC遍历。未注册分支拒绝；版本不存在/已删/已失权不通过相同字串回找。示例`card:<id>@<revision>/examples/<example_id>/translation`使用发布时应用分配并冻结的example_id；数组重排不能靠index重绑。material分支使用ContentBlock ID与canonical_text字段，课本/试卷派生业务字段使用所属题/卷版本分支。

可编辑来源必须冻结实际输入，不能只记录稍后已无法读取的revision。服务在锁外准备包含字段身份、实际文字、source_ruby和范围映射的不可变私有JSON快照（内部FileObject用途`text_analysis_input`），验证摘要/大小/协议；提交源编辑的事务锁内复核预期revision、权限和删除代次，再同时绑定新源revision、快照引用、NLP Job/Outbox。未提交的候选按对象GC清理，事务内不上传对象或运行NLP。同一事务创建/复用分析头并登记选用意图，JobStage受理结果与分析头均保留快照引用；后续编辑不影响原任务输入。对于真实不可变且可按版本完整重读的来源，允许只引用该版本，不额外保存输入对象。SourceAdapter明确登记这两种模式，不能将仅保存当前行的收藏当作不可变来源。

试卷分支只处理已冻结ready的卷版本，卷ready提交即受理NLP；冻结前仍可做源材料提取/校对，但不按同一个version_number永久标注可变题面。后续改题/脚本创建并冻结新卷版本后再分析，不延迟考试ready直到NLP完成。

AI/收藏schema中的学习文字采用纯文本字段或受控text runs，SourceAdapter用发布版本固定的规则输出基础文字及run到scalar映射；原始Markdown流只作预览，不以删除样式符号后的临时DOM作为权威偏移。text runs项身份及提取协议随源版本冻结，界面换行/折叠不改映射。

| 对象 | 版本化内容 |
| --- | --- |
| TextAnalysisVersion | 具体源版本、输入清单摘要、pipeline/schema、各语言引擎/词典/规则版本、完整性状态、Job及发布代次 |
| TextAnalysisUnit | 注册字段/稳定项身份、原字段scalar范围、text_snapshot、正文及source_ruby摘要、所属可见性角色、技术分片序；分词数组和派生读音等annotation_payload |
| TextAnalysisSentence | 稳定ID、分析版本、锚定unit与句序、有序spans、句子语言；跨连续来源块时指向多个unit，不重建一份虚构正文 |

TextUnit是有界段落/字段分片，不存整书JSON。推荐实施初值每unit最多4096 scalar、标注JSON最多256KiB；最终用样本锁定，字段/技术分片边界不可切断字素。先在同语义范围分句，再按句/词边界分单元；单个超长句以多个spans表示同一sentence，不把技术分片伪造成多句。跨段仅在同章节/同语义流有可靠连续证据时允许，不能跨题、表格格子、对话轮次或把脚注插入主句。

`annotation_payload`由Pydantic版本化校验，包含：

- `tokens[]`：unit内稳定ordinal、start/end scalar、language、lemma、part_of_speech、活用features、可空reading、reading_origin与quality、可空sentence_id。基础表层词直接从快照范围取得，保留空白/标点，不拼接选词造新词组。
- `ruby[]`：基础范围、读音、原书annotation引用或派生来源、有效/不确定状态；跨token的原书整词注音保留为一个范围，不能硬塞每个词的reading。原书有效读音优先、缺失项才补NLP，gloss类注音不自动用于TTS。
- `language_spans/coverage/issues`：局部语种、已处理范围、明确的未支持/失败原因；可信度未知为null，不用模型自报概率当真值。

所有偏移沿[出处协议](../contracts/content-locator.md)的Unicode scalar左闭右开，客户端另做UTF-16/字素转换。发布校验文本摘要、范围、词序及有效覆盖；token不能越界或引用别的分析版本/账号句子。无可靠句子的短标题/独立词可有token但不强造sentence。派生ruby、显示HTML及Markdown标记都不混入canonical_text。

## 3. 物理粒度与读取

用`text_analysis_versions`、`text_analysis_units`、`text_analysis_sentences`替代旧材料专用的3张NLP设计表；原`material_tokens`逐词物理行收敛为unit中的token JSONB，原材料句子改用跨unit spans。合计仍3表，不为AI卡片/题目各建一套NLP表，也不把任务/临时气泡做成表。表名、关系与142表清单同步说明这是未来目标变更，B0实际表不受影响。

分析头1:N单元、1:N句子，单元中的词数组是值对象。读取长按句子时按来源取得句子及其少量unit的完整标注，不为每个词往返数据库。当前无已确认的跨全库词性/词频SQL查询需求，不默认建立token GIN或全库分词倒排索引；未来有实测需求再增加可重建索引，不能反向改变权威文本。记录数和字节、长句/混合语种等性能需样本验证，此方案不是性能验收结论。

为支持可编辑来源的历史定位，unit保留有界原文快照，接受这一份受控复制；AI成品仍只在Explanation/Card等本体保存完整业务结构，不在unit复制模型上下文/整张卡。快照随源版本和合法引用保留；无引用旧版按受控GC回收，不把全部历史无限保存。

## 4. 发布、失败及交互

~~~mermaid
flowchart TD
    A[EPUB等直接提取 或视觉OCR] --> B[校验并发布正文与原书ruby]
    C[AI完整结构化结果] --> D[校验并持久保存Explanation或Card]
    B --> E[事务登记NLP任务及Outbox]
    D --> E
    E --> F[读取冻结输入 分句后封存单元清单]
    F --> G[确定性分句 分词 读音]
    G --> H[校验范围并提交有界单元及句子]
    H --> I[按有权字段返回文字与标注]
    I --> J[本机缓存 长按直接展开]
~~~

源结果提交和NLP Job/Outbox受理在同一业务事务中完成；可编辑源同时绑定上述实际输入快照，供应商调用不在事务内。AI文字可流式预览，半成品不可收藏或作为正式学习源。完整结果先保存，不等NLP成功才落库；已提交结果可收藏，句子气泡/ruby在对应标注ready后启用，原文字段仍可用手动字素范围操作。NLP失败只重试确定性处理，不重新生成AI结果或音频。

初次源发布后后台处理全部目标单元；界面可先阅读已发布正文，并优先处理当前章节/可见字段，不能将优先级解释为放弃剩余全书覆盖。AI结果按注册字段执行相同流程。查询/朗读新的模型任务仍需既有明确动作与权限；自动NLP不授予自动整书AI详解/TTS。

源输入清单和最终unit清单分开：受理前在锁外从待提交数据或锁定版本读取结果计算原字段/实际内容的input_digest，受理事务复核版本并冻结该输入、建立分析头及选用意图；Worker在锁外按固定pipeline分句/分词后确定技术分片，按有界批次插入pending单元。单元清单未全部核验封存前，unit_manifest_digest/expected_unit_count为NULL，不能用0或假摘要表示未知，也不发布ready单元。重投读取冻结输入并确定性复算，按unit身份幂等补齐；核对全清单、连续序号、数量和摘要后，在stage fence及源锁保护下首次设置最终manifest，之后不得改写。已知空清单才可用0，标记无可学习字段；大书无需锁内分词或单笔插入所有unit。

头状态queued/running/partial/ready/failed/sealed，单元状态pending/ready/failed/unsupported。ready必须表示冻结清单全部目标已成功，partial说明仍有未完成/失败/unsupported；百分比分母来自实际清单，不能把遗漏字段当完成。ready单元的快照/标注和已发布句子不可原位改写；失败单元可在当前Job新stage代次重试，发布比较源版本、删除代次和fence。涉及跨unit的一句及其必要token映射在同一有界发布组提交；残缺组不开放整句。超运行硬上限明确failed，不能偷偷截断。

重投按分析严格身份和单元身份唯一约束复用，不重复插入句子。Job按源根→分析头→单元固定顺序锁定，执行计算在锁外；只在当前stage fence下提交。明确升级pipeline新建分析版本；同源版本各pipeline共用受源根保护的desired_for_read唯一选用意图，受理新的选用请求时才清旧意图并设新意图。完成回调不能自行夺取意图；发布可读组时只有仍为desired的分析才能CAS切selected，旧pipeline晚到只保留历史。desired失败时保留原selected，不自动改回意图；显式选择已有ready分析可在同一事务直接切换。旧页面/连续队列固定旧analysis_version直到显式重新加载，不因后台完成改变当前选中范围。所有新处理阶段及读取重查当前来源动作，撤权停止新处理且迟到结果不成为可见成品。

页面首次按可见范围一并加载正文、源ruby、sentence索引及unit标注，后续分页可有界预取。长按直接使用已加载数据，不联网请求分词或调用模型；缺标注时展示准备状态并保留手动范围，不能伪装正式NLP完成。技术分片和分页带回已发布句子剩余spans，缺块时先补读已有片段，不把半句当完整句。

客户端的coverage/state只统计本次有权可见范围，不直接返回分析头的全量expected_unit_count或隐藏字段失败信息。服务端检查句子的全部spans同属当前允许语义范围后才返回；任何跨度不可见则不发布该完整句投影。failed单元可按原pipeline恢复，unsupported等待明确支持该语种/结构的新pipeline，不能无限自动重试。

## 5. 版本、缓存与复用

| 变化 | NLP/解释/音频处理 |
| --- | --- |
| 重新打开/本机或Redis丢失 | 从PG读取同一完整标注和AI结果，从对象存储取已有音频，不重新OCR/NLP/调用模型 |
| 原文或原书ruby校正 | 新内容版本、新NLP；旧源和成品按各自引用保留，当前范围重新匹配 |
| 仅分词/词典/派生读音升级 | 新分析版本；原文不改，旧解释与音频不会被批量删除或自动重新生成 |
| NLP升级但实际选区/上下文及有效发音相同 | 通过原文范围映射复用同一AI查阅结果/合成资产；分析ID只记依赖，不单独强制缓存miss |
| 分句改变导致目标/上下文范围改变，或有效读音改变 | 分别影响语境查阅或TTS严格键，旧版标明差异；需要新生成时仍显式授权 |
| AI重新解析/收藏内容修改 | 保存新成品/源revision并登记NLP；旧标注不套到新文本，收藏与合法历史按原快照保留 |

NLP持久匹配采用源身份/版本、字段清单与text/source_ruby摘要、语言引擎/词典/规则/schema版本；仅换Key、TTS声音或查询预算不重做NLP。基础NLP可能改变句边界，ContextBuilder按固定源范围确定本次ContextPlan，不能把新sentence ID本身当新增语境。解释/TTS严格语义键与当前选用代次仍以[学习缓存](learning-cache.md)为准。

内存、本机Drift及Redis只保留完整PG单元/句子的副本；本机按instance/user/audience/library/source/version/analysis/units分区并计入文本容量。先在线权限或有效离线租期，后读缓存；退出/换账号/失权清范围及迟到响应。R19保存有界热点unit与相关句子投影，键、字段、TTL见[Redis目录](redis-design.md#4-学习结果媒体与幂等字段)。内存/本机/Redis miss依次回源，NLP版本不存在由既有持久任务恢复，不能借缺失触发OCR或AI重生成。

共享词音目录不扩展为跨用户NLP/解释库。内容及来源标注均为私有；即使相同文本也不省略各自来源授权。考试接口在DTO生成前按题面/交卷/反馈状态裁剪unit，题目答案、听力稿、未发布评分及其lemma/ruby/句子数量摘要都不能混进通用响应；禁止只隐藏渲染而下发完整NLP。独立收藏需要可继续阅读时，先以当前合法快照建立自己的标注来源，删除原书后不能靠旧unit读取更多原文。

## 6. AI解释的权威存储

`explanations.result_payload`保存词句/摘录的完整类型化解释，`context_snapshot/generation_config/ai_run_id`保存实际输入和生成依据；`cards.payload`保存独立Word/Sentence/Grammar/ExerciseCard及稳定字段项ID。结果不可变且自动保存，不以收藏为条件，不仅保存HTML/最终Markdown。AI解析引用原句意群时验证合法源span，输出不能自己重写源ID。

同一成品需要卡片外观时优先由既有结果投影，不能只因换页面重复调用模型或复制另一份AI结果；真正独立Card沿用其自身schema/版本，source_result_bindings明确来源和结果。NLP处理本体白名单文本字段，每个unit指回确切结果版本；对AI释义再查词得到新结果和来源链，分词本身不产生第二轮AI解析。真实用量仍只统计供应商attempt。

## 7. 实施与验收

阶段2先落实格式/ruby、统一SourceAdapter、3表标注存储、小说全覆盖及教材结构边界；阶段3将AI解释/查询/卡片输出纳入相同发布/缓存流程，阶段4覆盖题目、评分/诊断及交卷可见性。不预建另一套前端NLP权威数据，不按每个语种新建表。

| ID | 正式必需验证 |
| --- | --- |
| NLP-01 | 小说全书、课本各角色、解释/卡片各字段、收藏、题面/反馈清单完整；无遗漏字段假ready，按钮/非语言字段不造句 |
| NLP-02 | 英/日/中文解释及混合文字、缩写/小数、活用、多音/未知读音、emoji/组合字符、原书ruby不污染偏移；字素调整有效 |
| NLP-03 | 一句跨块/技术分片保持同句及完整spans；不跨题/单元格/对话/脚注拼句；长字段容量和超限降级有样本 |
| NLP-04 | AI流式无正式标注，完整成品先保存；NLP失败/重投/重启只补缺失，无重复AI调用或假模型用量 |
| NLP-05 | 可编辑来源受理后立即再编辑仍可恢复旧输入；manifest未知与已知空区分；新pipeline先完成、旧pipeline迟到不夺selected；冻结前试卷不复用永久标注；版本/删除/fence/GC及同语义复用、改目标/读音隔离 |
| NLP-06 | 长按无分词请求，正文和标注一起加载；本机/Redis清空回PG、离线租期、换账号/实例、旧响应隔离 |
| NLP-07 | A/B、伪字段/任意JSONPath、隐藏答案/脚本/评分/考试未交卷拒绝；日志/队列无全文，缓存不绕过来源权限 |

正式分词质量、索引规模、存储/延迟及原生三端效果尚未验证；文档完成不能勾选以上验收。
