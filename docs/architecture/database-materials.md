# 数据库设计书：材料、阅读与考试

状态：2026-09-25，DBDESIGN3，阶段1中的数据库设计文档切片；本文新增结构均为**待实现设计**，没有建表、迁移或数据库验收。入口与公共规则见[数据库设计书](database-design.md)，已存在的 `libraries` 由[身份分册](database-identity.md)登记。本文把[源结构契约](../contracts/material-structures.md)、[材料](../modules/materials-reading.md)、[小说](../modules/novels.md)、[课本](../modules/textbooks.md)、[考试](../modules/exams.md)及[双端原型](../../prototype/README.md)映射为物理表，不改变它们的产品边界。

DESIGN20的小说逐句NLP与章节准备映射：基础标注按DESIGN23升级为§2.7的统一analysis/unit/sentence及token值对象，读音及语言特征保留来源/不确定信息；章批次复用Job/Outbox及注册检查点，逐句成品复用学习分册的解释/音频/源绑定。[章节准备协议](../contracts/novel-preparation.md)只增加任务载荷与聚合投影，不增加整章缓存表，本轮未执行DDL。

## 1. 字典约定与分层

表名表达材料域、直接父对象或关联端点；全部表的归属、关系基数和唯一约束摘要见[关系清单](database-relations.md#22-材料阅读与考试46张)。本轮只改物理目标表名，`source_asset_id`、`content_block_id`、`exam_answer_id`等列名与接口逻辑ID保持既有含义。

- `B` = `id uuid NN`（服务端 uuid4，PK）、`created_at/updated_at timestamptz NN DEFAULT now()`；`U` = B + `user_id uuid NN`；`L` = B + `owner_user_id/library_id uuid NN`；`R` = `revision bigint NN DEFAULT 1 CHECK >= 1`。公共时间更新遵循[数据库规范](../engineering/database.md)，只读历史行的 updated_at 不随访问改变。
- `M` = L + `material_id uuid NN`；`V` = M + `material_revision_id uuid NN`。下文逐表写明列组，列组字段属于该表真实物理字段，不是 ORM 隐式关系。`NN` 为 NOT NULL，`NULL` 为允许 NULL；未写 DEFAULT 的列无服务端默认值。逗号分隔列在同一行表示各列具有所列相同类型/空值规则，语义按列名次序说明。
- `S` 代表索引前缀 `(owner_user_id, library_id)`，`SU` 代表 `(user_id)`；所有作用域内 UQ/IX 都完整展开该前缀。UQ 为唯一约束/唯一索引，IX 为普通索引，部分谓词在括号后明确。主键和 UQ 已提供的索引不重复创建。约束命名按数据库规范自动确定性生成。
- 类型、状态使用有界 varchar + 命名 CHECK；允许值由本分册所链接的契约单一维护，迁移展开为明确集合，不以任意文本作为合法状态。所有 ordinal 和schema版本从 1 起，计数/字节/偏移非负，generation 从 0 起；单行 CHECK 可以验证范围，不能验证关联归属。
- `source_locator/provenance/source_refs` 是[出处协议](../contracts/content-locator.md)的有界、版本化 JSONB 值对象，包含 `locator_schema_version`，不是任意 JSON。材料表由实体列确定材料/版本，§2.7统一标注由分析头注册的source分支确定实际资源/版本；其 spans 中的块/segment/unit ID 仍须按注册 JSON 路径完整校验和纳入 GC 关系遍历。不得把题目、权限、状态、关键去重键藏进 JSON。
- 其他 JSONB 由同一行 `schema_version smallint NN` 指定注册的 Pydantic 模型；必要参数不得以空对象冒充缺失。以“可选”标注的 JSONB 为 NULL，发布时依领域类型检查必需结构和大小。小型摘要必须能从明细重建，不作为发布/评分真相。
- 所有关联均为**逻辑关联，无物理外键、无隐式级联、无 RLS**。L/M/V 表的库归属从认证 ScopeContext 和已锁父记录派生，创建后不可转移。上传 U 表按用途验证目标聚合，不能凭 `file_object_id` 获得读取授权。

### 持久化边界与原型映射

| 原型中的信息/动作 | 真实持久事实 | 不直接入库的演示值 |
| --- | --- | --- |
| 材料标题、类型、语言、解析状态 | materials、material_revisions、专用 manifest、Job | 卡片颜色、图标、格式化“今天09:42”由界面派生 |
| 小说章节/段落、选区、书签 | novel_*、material_content_blocks、material_reading_progress、material_bookmarks | 字号/行距/主题归本人设置，不复制到每个章节 |
| 课本单元、对话/词表/语法/习题 | textbook_*、公共 exercise_questions | 原型数组下标不能成为长期 option_id |
| 试卷准备、脚本勾选、生成状态 | candidate/确认记录、script版本、audio binding、冻结卷 | 一个内存布尔值不能替代人工确认版本 |
| 答题卡、已保存、标记、计时 | exam_sessions、exam_session_answers、服务端 deadline_at | 演示42:18、原卷38题/可操作3题不作默认值 |
| 听力播放与续播 | 每场次 usage/play_attempt 账本 | 按钮点击/前端播放器事件不能扣次或退次 |

文件二进制留在 MinIO；PG 保存权威对象引用和摘要。源结构、小说编排、课本编排、试卷冻结保持独立。公共题目、答案/rubric、普通作答和评分见[学习分册](database-learning.md)：`exercise_questions.id` 是不可变题目版本行，`question_grading_bases.id` 是独立隐藏依据；本分册不复制另一套公共题目/评分表。

## 2. 上传、书库与不可变来源

### 2.1 `upload_intents` — 专用临时上传

列组 U + R，scope=user_owned；通用上传服务操作，读取文件仍以目标用途权限为准。

| 列 | PG类型/空值/默认 | 语义 |
| --- | --- | --- |
| purpose | varchar(40) NN | primary_document / exam_listening_script / query_image / avatar / vocabulary_csv / vocabulary_photo；P0不接受原始听力音频用途 |
| target_kind | varchar(40) NN | material_import / exam_paper / agent_thread / user_extension / csv_import / photo_word_import |
| target_resource_id | uuid NN | 本人已存在的目标聚合；与 purpose 对应 |
| material_type | varchar(16) NULL | 仅 primary_document 为三类之一，其余 NULL |
| original_filename | text NN | 显示名称，不能作为对象路径 |
| declared_format | varchar(32) NN | 受支持能力目录格式，不当作实际检测结果 |
| expected_size_bytes | bigint NN | 用户原始上传字节的声明大小 > 0；不是重编码输出大小 |
| storage_reservation_id | uuid NN | 身份分册user_storage_reservations中的本人容量预留 |
| expected_sha256 | bytea NN | 原始上传字节的声明 SHA-256，32字节；在固定的服务端输入副本上验证 |
| staging_object_key | text NN | 独占临时键，不接受客户端构造 |
| status | varchar(24) NN | 上传合同状态 |
| completion_generation | bigint NN DEFAULT 0 | 每次完成领取代次，阻挡失租/取消后的发布 |
| completion_lease_token | uuid NULL | 领取 finalizing 后的服务端 fence |
| completion_lease_until_at | timestamptz NULL | 完成领取期限，与 token 成对存在 |
| candidate_input_object_key | text NULL | 当前代次独占的稳定输入副本键，客户端无写入或读取能力 |
| validated_input_size_bytes | bigint NULL | 稳定输入副本实际大小；验证成功后与expected_size_bytes相等 |
| validated_input_sha256 | bytea NULL | 稳定输入副本实际摘要；验证成功后与expected_sha256相等 |
| input_validated_at | timestamptz NULL | 原始声明与稳定副本一致、基础类型检查通过的时间 |
| transformation_profile | varchar(80) NN | 服务端按purpose选定的处理版本，明确无变换或受控图像规范化/重编码，不接受客户端任意转换指令 |
| candidate_final_object_key | text NULL | 当前代次独占输出键，未验证不能读取 |
| file_object_id | uuid NULL | completed 后已验证的 final 对象 |
| expires_at | timestamptz NN | 意图和配额预留截止 |
| failure_code | varchar(80) NULL | 安全错误码，无正文/对象凭据 |

UQ `staging_object_key`、`candidate_input_object_key WHERE ... IS NOT NULL`、`candidate_final_object_key WHERE ... IS NOT NULL`；IX `(user_id,status,expires_at,id)` 清理/本人未完成上传。CHECK 大小正数、摘要32字节、lease两列同空同有、输入验证三列全空或全有且成功值等于声明、purpose/type/target合法组合；completed 必须有 file_object_id。本人user_storage_states与目标聚合共同保护配额/意图，user_storage_reservations记录每次预留；并发预留不能仅查无锁 SUM 或仅依赖 Redis。签名/复制/解码在事务外，发布重验 generation、租约、权限、取消与期限。完成/取消/超时释放预留一次，失败对象与staging延迟回收。

完成处理先将可变staging流式复制到本代次独占、服务端控制的输入副本，在该固定副本上计算完整摘要/实际大小、核对原始声明并检查真实类型，不能只校验staging HEAD。后续处理只读取该副本，旧上传签名不能改变它。按purpose执行：primary_document、exam_listening_script、vocabulary_csv等不变换原始字节的路径，可在完整格式验证后把该对象作为final，最终大小/摘要仍与输入一致；avatar和query_image必须受限真实解码、规范方向、去元数据及重编码，写入另一独占final键，再对输出重新做真实格式/像素/解码/摘要/大小验证。vocabulary_photo若配置受控图像规范化，也采用相同的输入/输出分离规则。输出不再与原始expected_sha256/expected_size_bytes作相等要求，`file_objects.sha256/size_bytes`只描述最终输出；容量服务在发布前按输出实际大小重新核对/结算预留，不能用输入声明跳过输出限额。未变换与重编码两类都只有验证后的final能发布为FileObject；内部输入副本不能作为可读业务资产，未作为final使用时按临时对象规则清理。

purpose与target_kind为按上表顺序的一对一白名单，不能任意组合。CSV/照片词表的受理服务先由服务端分配批次ID，在同一短事务中写本人批次占位、容量预留和上传意图，再返回签名；占位阶段的file_object_id必须NULL，文件验证后原子绑定。CSV进入预览后才允许确认导入，照片识词在有权且用户显式确认的视觉模型任务中执行，上传完成不等于执行识别。对应范围和表字段见学习分册，不借这两个purpose扩展材料格式。

### 2.2 `file_objects` — 服务端发布的不可变对象

列组 U；scope=user_owned。本表不开放“按ID下载所有文件”的通用接口。

| 列 | PG类型/空值/默认 | 语义 |
| --- | --- | --- |
| upload_intent_id | uuid NULL | 上传来源；服务端受控派生资产可空 |
| parent_file_object_id | uuid NULL | 派生输入，存在时必须同本人且同允许用途 |
| purpose | varchar(40) NN | 与业务投影一致的受控用途，派生题图/音频及内部vision_recognition_result、text_analysis_input分别登记；内部OCR结果/NLP输入快照不可由客户端UploadIntent提交 |
| bucket_name, object_key | text NN | Haruka私有bucket和独占final键，无签名URL |
| object_version | varchar(128) NULL | 对象存储启用版本时的确切版本，不以ETag代替摘要 |
| media_type | varchar(127) NN | 后端验证的实际Content-Type |
| format_code | varchar(32) NN | 实际检测格式 |
| size_bytes | bigint NN | 验证后的实际字节数 > 0 |
| sha256 | bytea NN | 实际对象完整摘要，32字节 |
| validation_profile, processor_version | varchar(80) NN | 格式/尺寸/解码或重编码检查版本 |
| validated_at | timestamptz NN | 验证完成时间 |
| pixel_width, pixel_height | integer NULL | 图像成品实际像素，成对非空且>0；非图像为空 |
| retention_state | varchar(24) NN | referenced / gc_pending / deleting / deleted |
| gc_not_before_at, deleted_at | timestamptz NULL | 延迟GC资格与已确认删除时间 |

UQ `(bucket_name,object_key)`；UQ `(user_id,upload_intent_id) WHERE upload_intent_id IS NOT NULL` 限定一个正式完成结果；IX `(user_id,sha256,size_bytes)` 只用于本人重复提示，不全局去重私有内容；IX `(retention_state,gc_not_before_at,id)` 供限定维护入口。正式对象字节与定位不原位更改；retention状态可受控更新。GC同时检查下游实际引用和在途任务，不把本行状态/缓存计数当作引用真相。用途变更需新派生对象并重新验证。

AvatarAsset直接映射purpose=avatar的本表行，asset_id就是file_objects.id，不另建avatar_assets。avatar必须有专用upload_intent_id、像素正方形且满足配置上限；validation_profile/processor_version记录解码、去元数据和重编码规则，不重复保存transform_version。上传、当前头像指针与GC按user_extensions→file_objects的共同锁序并核对本人/用途；合表不产生通用下载授权。

### 2.3 `material_imports` — 显式类型与阶段意图

列组 L + R；scope=library_owned，库根锁保护创建，受理后以 materials 根保护。

| 列 | PG类型/空值/默认 | 语义 |
| --- | --- | --- |
| material_type | varchar(16) NN | novel / textbook / exam，创建后不改 |
| primary_upload_intent_id, reused_material_id | uuid NULL | 新上传或复用本人原件两种互斥来源 |
| reused_file_object_id | uuid NULL | 复用服务在源材料锁内解析的确切对象，客户端不指定 |
| requested_title | text NULL | 用户标题意图，AI不能覆盖 |
| target_language | varchar(35) NULL | 未知可空，不用空串 |
| schema_version | smallint NN | 请求阶段载荷版本 |
| requested_stages | jsonb NN | 已显式确认的确定提取/视觉/后续分析及上限；不含Key |
| status | varchar(24) NN | 本模块导入状态 |
| idempotency_record_id | uuid NN | 同scope/action请求摘要与返回映射 |
| material_id, initial_job_id | uuid NULL | 受理同事务创建的结果，两列同空同有 |
| expires_at | timestamptz NN | 待上传意图期限 |

UQ `(S,idempotency_record_id)`；IX `(S,status,created_at,id)`。CHECK 两个来源恰有一个、复用来源与对象成对、结果成对。上传路径在服务端先分配import/intent/预留ID，在同一创建事务按每条INSERT立即满足CHECK的形状写入，事务内复核双向逻辑目标；不先插违反约束的壳再UPDATE，不假设CHECK可延迟到提交。复用路径完整原件权限含源试卷校对动作，受理/Worker/提交均重验；按另一类型处理创建新材料，历史关联不搬家。

### 2.4 `materials` — 三类共用书库身份

列组 L + R；scope=library_owned，材料根是源内容/领域版本/删除GC的共同保护行。

| 列 | PG类型/空值/默认 | 语义 |
| --- | --- | --- |
| material_type | varchar(16) NN | 固定三类之一 |
| title | text NN | 非空显示标题，确定回退为文件名 |
| title_origin | varchar(24) NN | filename / extracted / user；用户标题优先 |
| language | varchar(35) NULL | 已识别/已确认语言 |
| author | text NULL | 原书信息缺失就空 |
| source_format | varchar(32) NN | 与验证源对象一致 |
| primary_file_object_id | uuid NN | 本人不可变主文件 |
| current_revision_id | uuid NULL | 完整源发布后原子切换，新解析失败不切换 |
| source_status, analysis_status | varchar(32) NN | 源可用性与额外分析分开，不代表试卷ready |
| analysis_generation, delete_generation | bigint NN DEFAULT 0 | 候选/删除隔离代次 |
| deleted_at | timestamptz NULL | tombstone；不提供回收站恢复功能 |

IX `(S,material_type,updated_at DESC,id DESC) WHERE deleted_at IS NULL` 支撑类型列表；IX `(S,language,updated_at DESC,id DESC) WHERE deleted_at IS NULL` 支撑语言筛选。标题首版有界本人范围匹配，不先建GIN或宣称全文搜索达标；实现需按真实查询与样本确定是否补表达式/文本索引。源对象不UQ，允许本人显式再导入。删除推进delete_generation、停止新引用/签名、Outbox同事务；收藏/冻结场次快照独立保留。

### 2.5 `material_revisions` — 不可变内容版本

列组 M；scope=library_owned。源字段组和小说/课本结构字段组分别首次发布；源一经发布即不可改，尚未发布的结构组仍可完成自己的候选/校验流程。

| 列 | PG类型/空值/默认 | 语义 |
| --- | --- | --- |
| revision_number | bigint NN | 同材料版本序号，>=1 |
| parent_revision_id | uuid NULL | 上一来源版本，不能跨材料 |
| source_schema_version | smallint NN | 来源结构schema |
| text_protocol_version | varchar(40) NN | canonical-text-v1 |
| processor_version | varchar(80) NN | 确定解析器/管线版本 |
| origin_job_id | uuid NN | 已授权创建来源 |
| input_delete_generation | bigint NN | 发布必须匹配 materials |
| status | varchar(24) NN | building / published / failed / sealed |
| published_at | timestamptz NULL | published时必需 |
| content_digest | bytea NULL | 发布源结构摘要，发布时32字节 |
| material_type | varchar(16) NN | 从材料根派生的固定类型，服务复核相等 |
| structure_schema_version | smallint NULL | 小说/课本manifest的独立结构schema；exam为空 |
| structure_status | varchar(24) NULL | 小说/课本building/readable/degraded/failed；exam为空 |
| structure_revision | bigint NULL | 小说/课本初值1，结构候选/确认CAS；exam为空 |
| structure_generation | bigint NULL | 小说/课本初值0，新候选/重试代次；exam为空 |
| quality_summary | jsonb NULL | 小说/课本同版本有界质量摘要 |
| required_capabilities | jsonb NULL | 小说/课本同版本能力代码数组 |
| structure_published_at | timestamptz NULL | 小说/课本结构发布时刻 |

UQ `(S,material_id,revision_number)`；IX `(S,material_id,status,id)` 查候选/旧版本。源发布在材料根锁内验证源子表、类型、generation并切current指针；该指针不直接代表专用阅读结构ready。正文修订必建新版。失败/失权产物可封存但不成为当前可读版本。

小说/课本原单例manifest头合入本行：NovelManifest/TextbookManifest的逻辑id均映射material_revisions.id，各自仍用独立Pydantic schema、发布服务和章节/单元表。CHECK novel/textbook时结构schema/status/summary/capabilities/structure_revision/structure_generation非空，revision>=1且generation>=0；exam时这些列及structure_published_at全空；readable/degraded需发布时间。两个字段组按[解析流水线](../contracts/material-structures.md#6-解析校对与发布流水线)分两次提交：源发布冻结source_schema/text_protocol/processor/content_digest等源列及SourceAsset/Unit/Block，结构初始仍building；后续类型候选/必要校对只更新尚未发布的结构组及自己的节点，使用structure_revision/generation并共锁material→revision，绝不重写已发布原文。首次结构发布同时冻结头和章节/课本节点；其后改结构必须新建MaterialRevision。结构任务失败可在首次结构发布前建立新代次重试，旧代次不得覆盖新候选/人工确认；不能因为源status=published就禁止首次结构发布，也不能因此开放源列更新。这里只合并小型一对一头，不把三类正文塞进一个JSON，也不将考试草稿生命周期并入源版本。

### 2.6 公共来源明细

以下均为 V、scope=library_owned，由 materials 根保护；版本发布后内容不可改，GC与所有下游引用共同检查。各表的 ordinal 必须正数。

| 表 | 列（PG类型；空值/默认；语义） | 唯一、检查与索引 |
| --- | --- | --- |
| `material_source_assets` | `file_object_id uuid NN` 本人验证对象；`purpose varchar(40) NN` 主文档/内嵌图/受控派生图等；`ordinal integer NN` 版本内序；`source_locator jsonb NULL` 原件位置；`pixel_width,pixel_height integer NULL` 实际图像像素；`duration_ms bigint NULL` 实际媒体时长 | UQ `(S,material_revision_id,ordinal)`；IX `(S,file_object_id,id)` GC反查；像素成对且正数，时长非负；资产purpose与对象真实格式匹配，由服务验证 |
| `material_source_units` | `parent_source_unit_id uuid NULL` 层级；`unit_kind varchar(32) NN` spine/区段/获准页区域；`ordinal integer NN` 版本内全序；`source_asset_id uuid NN` 原件；`original_locator jsonb NN` EPUB路径/MD范围/获准页坐标；`schema_version smallint NN` 定位载荷版本 | UQ `(S,material_revision_id,ordinal)`；IX `(S,parent_source_unit_id,ordinal)`；拒绝自父，树无环/同版本由服务验证；不以页号猜测格式已开放 |
| `material_content_blocks` | `source_unit_id uuid NN` 来源容器；`ordinal integer NN` unit内序；`block_kind varchar(32) NN` paragraph/title/list/table/caption等注册值；`canonical_text text NN` 规范文本（纯图块可为空文本）；`scalar_length integer NN` scalar长度；`content_origin varchar(32) NN` deterministic/vision/user_correction；`recognition_run_id uuid NULL` 视觉来源AiRun；`original_locator jsonb NN` 源范围；`schema_version smallint NN`；`presentation_payload jsonb NULL` 受控source_ruby/列表/表格样式而非脚本；原书注音协议见[提取契约](../contracts/source-extraction.md) | UQ `(S,source_unit_id,ordinal)`；IX `(S,material_revision_id,id)`；长度非负，vision需recognition_run_id；发布程序校验scalar_length与正文、原位范围/字素边界；非文字块不制造句子 |
| `material_import_issues` | 另含R；`stage_code,kind varchar(64) NN` 阶段/问题；`severity varchar(16) NN` warning/blocking；`status varchar(24) NN` open/resolved/accepted；`source_refs jsonb NN` 有界出处；`schema_version smallint NN`；`resolution_code varchar(64) NULL`；`resolved_by_user_id uuid NULL`；`resolved_at timestamptz NULL` | IX `(S,material_revision_id,status,severity,id)`；关闭字段成对，用户确认与确定修复须可追溯；人工确认不得把不可用必要题面直接改成ready |

### 2.7 全应用派生语言标注

DESIGN23把原材料专用3表调整为下列3表，仍在本分册计数，覆盖全部学习资源；此处不再继承V，不强制AI卡片具有material_id。均为L、scope=library_owned，按[统一文本分析](text-analysis.md)的注册SourceAdapter复核源父/版本/字段及删除代次。每表含B的PK和created_at/updated_at，无物理外键。

| 表 / 列组 | 列（PG类型；空值/默认；语义） | 唯一、检查与索引 |
| --- | --- | --- |
| `text_analysis_versions` / L+R | `source_kind varchar(32) NN`；`source_resource_id uuid NN`；`source_version bigint NN`；`input_digest,pipeline_digest bytea NN`；`schema_version integer NN`；`pipeline_version varchar(80) NN`；`engine_manifest jsonb NN` 各语言分句/分词/词典版本 | UQ `(S,source_kind,source_resource_id,source_version,pipeline_digest)`；source枚举/版本映射见专题；digest32字节、版本正、manifest对象 |
| 同表 | `input_mode varchar(24) NN` immutable_source/file_snapshot；`input_snapshot_file_object_id uuid NULL` | CHECK file_snapshot必须有引用、immutable_source必须为空；对象须同本人且为text_analysis_input用途；IX `(S,input_snapshot_file_object_id) WHERE input_snapshot_file_object_id IS NOT NULL` 支撑GC |
| 同表 | `status varchar(16) NN DEFAULT 'queued'`；`job_id uuid NN`；`input_delete_generation bigint NN`；`unit_manifest_digest bytea NULL`；`expected_unit_count bigint NULL`；`desired_for_read,selected_for_read boolean NN DEFAULT false`；`published_at timestamptz NULL` | 状态queued/running/partial/ready/failed/sealed；manifest两列同空同有，非空时摘要32字节/数量非负，partial/ready必有manifest及published_at；selected仅partial/ready；两条部分UQ分别为 `(S,source_kind,source_resource_id,source_version) WHERE desired_for_read` / `WHERE selected_for_read`；IX `(S,job_id)`及`(S,source_kind,source_resource_id,source_version,status)` |
| `text_analysis_units` / L | `analysis_version_id uuid NN`；`ordinal bigint NN`；`field_code varchar(128) NN`；`item_identity varchar(160) NN` 非数组固定single；`source_start_scalar,source_end_scalar integer NN`；`unit_identity_digest bytea NN`；`source_locator jsonb NN` | UQ `(S,analysis_version_id,unit_identity_digest)`及`(S,analysis_version_id,ordinal)`；字段/稳定项/技术分片范围构成identity；范围非空，禁止任意JSONPath |
| 同表 | `text_snapshot text NN`；`text_digest,source_ruby_digest bytea NN`；`schema_version integer NN`；`semantic_role varchar(32) NN`；`state varchar(16) NN DEFAULT 'pending'`；`annotation_payload jsonb NULL`；`serialized_size_bytes bigint NN DEFAULT 0`；`stage_generation bigint NN DEFAULT 0`；`error_code varchar(96) NULL`；`published_at timestamptz NULL` | state pending/ready/failed/unsupported；ready要求payload对象、发布时间及正字节数；错误状态要求error_code；语义角色按分支注册，不作为授权；IX `(S,analysis_version_id,state,ordinal)` |
| `text_analysis_sentences` / L | `analysis_version_id,anchor_unit_id uuid NN`；`ordinal integer NN` 锚定单元内句序；`sentence_identity_digest bytea NN`；`language varchar(35) NN`；`schema_version integer NN`；`spans jsonb NN` | UQ `(S,analysis_version_id,sentence_identity_digest)`及`(S,analysis_version_id,anchor_unit_id,ordinal)`；spans非空有序数组，含unit_id/start/end；digest32字节、ordinal/schema正；IX `(S,anchor_unit_id,ordinal)` |

unit快照与源字段范围长度/内容必须完全对应；枚举清单由确定性SourceAdapter冻结，空/非学习字段不造空unit。`source_locator`保存原资源字段身份及出处，不将模型输出字段改写成原书范围。token/ruby/language_spans/coverage字段保存在unit的有界annotation_payload，细节唯一见专题；跨unit句子允许多个spans，服务校验同分析/语义流、顺序、字素及所有引用。读取某unit相关句子可从token的sentence_id集合按PK批取，非token片段用anchor与source范围查找，不默认给JSON加GIN。当前界面按句/块整体读取，无确认的逐词SQL检索需求，因此不保留物理token行。

input_digest含源版本实际可学习字段及原书ruby，pipeline_digest含所有影响标注的规则/词典/schema。相同唯一身份收到不同input_digest视为源版本或协议错误，不覆盖重算；显式升级pipeline建新行。分析头source身份/输入清单不可改；任务状态/desired/selected/revision可更新，ready单元、已发布句子及其快照不可变。当前无删除代次的不可变源分支冻结0且由其实际业务根检查存在性/删除状态，不能凭0跳过校验。

初始化与重投同源根锁下创建/复用分析头和Job，不在锁中运行NLP。受理前在锁外准备实际字段清单摘要，事务内核对源版本后同时建立分析头和Job；可编辑来源同时绑定已验证的实际输入快照及JobStage引用，不能在异步阶段回读当前行冒充旧revision。immutable_source只用于可完整重读的不可变版本；exam_paper_version仅接受已冻结ready卷。

input_digest先冻结源字段清单；unit清单在锁外分句/分词后形成，pending单元按确定性身份有界幂等插入。unit_manifest_digest/expected_unit_count在完整核验前均NULL；完整核验、fence复核后原子首次设置，禁止先写0/假摘要或提前发布unit。只有已知无学习字段时数量才为0。实际计算在锁外，提交共锁源根→分析头→涉及unit，并验证JobStage generation/fence、已冻结源输入和当前删除代次/权限。file_snapshot旧revision可从自己的受理快照恢复历史分析，不得选为新revision当前标注；immutable_source按确切版本复核。发布组原子提交unit及完整句子，局部成功不伪装全书ready，进度由封存清单明细聚合。

desired与selected分别表示最新选用意图和当前可读版本，均在同源根锁下维护。新请求清旧desired、设新desired并CAS头revision；完成回调只有仍为desired的行才可清旧selected、设新selected。旧任务不能自己重设desired，故A旧pipeline晚于B完成不覆盖B；B失败保留既有selected，重选必须显式操作。切换涉及的头按ID排序加锁，GC不得直接清除desired/selected或仍被任务引用的头；源版本退役/删除时先在源根锁内清选用意图/当前标记、封存分析并停止任务，再按实际剩余引用判断GC，不能让旧版本标记导致永久保留。旧页面仍按原analysis_id读取有权旧版。

输入快照引用按本人/用途/大小及完整摘要验证；源根→分析头→FileObject共锁新增引用和GC，受理前的JobStage引用同样计入保留，业务只经已授权标注投影读取。输入仍被分析或任务引用时不按TTL删除，不开放通用快照下载。

反向GC以analysis头的source_kind/resource_id/version索引查归属；sentence的spans、token.sentence_id与source_locator按注册JSON路径遍历。删除/改源/发布使用共同业务根，其他成品引用旧句/单元时纳入GC；独立收藏需留正文则建立自己的获权快照及标注，不能以标注快照恢复已失权原书。库/owner及头-单元-句子的跨表一致性由服务校验，不能依赖单行CHECK或JSON内容证明。

## 3. 小说、课本和阅读记录

### 3.1 小说专用结构

以下为 V、scope=library_owned。NovelManifest头位于material_revisions，只允许 material_type=novel；发布后明细不可改，所有逻辑关系同 manifest/源版本，材料根保护发布与GC。

| 表 | 列（PG类型；空值/默认；语义） | 唯一、检查与索引 |
| --- | --- | --- |
| `novel_chapters` | `ordinal integer NN`；`title text NN`；`source_title text NULL`；`title_origin varchar(24) NN` original/unsegmented；`source_refs jsonb NN`；`schema_version smallint NN` | UQ `(S,material_revision_id,ordinal)`；无目录使用明确“未分章正文”标记；来源标题缺失不AI捏造 |
| `novel_chapter_blocks` | `chapter_id,content_block_id uuid NN`；`ordinal integer NN`；`start_scalar,end_scalar integer NULL` 同空表示整个非文字块；`display_role varchar(32) NN` paragraph/dialogue/quote/footnote/illustration；`schema_version smallint NN`；`presentation_payload jsonb NULL` 样式引用 | UQ `(S,chapter_id,ordinal)`；IX `(S,content_block_id,id)`；可选范围同空同有且合法；连续章序、真实来源与范围由服务验证 |

句子/范围到音频的 SpeechSegmentBinding 由[学习分册](database-learning.md)的持久结果/音频映射维护，不将音频URL写回小说正文。

### 3.2 课本专用结构

均为 V、scope=library_owned；只允许 textbook 类型。manifest发布后目录/关系不可改，纠正结构创建新MaterialRevision。普通课本人工块编辑仍属既有后续范围，本设计不开放通用编辑器。

| 表 | 列（PG类型；空值/默认；语义） | 唯一、检查与索引 |
| --- | --- | --- |
| `textbook_units` | `parent_unit_id uuid NULL` 可选原书层级；`ordinal integer NN` material_revision内稳定全序；`title text NN`；`title_origin varchar(24) NN` original/unstructured；`source_refs jsonb NN`；`schema_version smallint NN`；`quality_state varchar(24) NN` | UQ `(S,material_revision_id,ordinal)`；IX `(S,parent_unit_id,ordinal)`；禁自父、服务验无环；无可靠Unit使用“待整理内容”而非伪造原课程 |
| `textbook_lessons` | `unit_id uuid NULL` 无显式Unit时为书下根级课；`ordinal integer NN` 父容器内顺序；`title text NN`；`source_refs jsonb NN`；`schema_version smallint NN`；`quality_state varchar(24) NN` | 部分UQ `(S,unit_id,ordinal) WHERE unit_id IS NOT NULL`；部分UQ `(S,material_revision_id,ordinal) WHERE unit_id IS NULL`；Unit/Lesson是领域身份，不借小说章节 |
| `textbook_content_nodes` | `lesson_id uuid NN`；`ordinal integer NN`；`role varchar(32) NN` 八类受控角色；`source_refs jsonb NN`；`schema_version smallint NN`；`typed_payload jsonb NN` 小型角色载荷/结构引用；`quality_state varchar(24) NN` | UQ `(S,lesson_id,ordinal)`；role映射见展示契约，未知保留源与issue，不硬归第九类；大正文仍引用material_content_blocks，不整本JSON |
| `textbook_content_node_links` | `from_node_id,to_node_id uuid NN`；`relation_kind varchar(32) NN` translation_of/caption_of/example_of/exercise_for/answer_for；`evidence_refs jsonb NN`；`schema_version smallint NN`；`confirmation_status varchar(24) NN` | UQ `(S,from_node_id,to_node_id,relation_kind)`；IX `(S,to_node_id,relation_kind,id)`；CHECK from!=to，服务验同manifest/允许跨Lesson关系；answer_for不作为普通正文投影 |
| `textbook_dialogue_turns` | `content_node_id uuid NN`；`ordinal integer NN`；`speaker_label text NULL`；`source_locator jsonb NN`；`schema_version smallint NN` | UQ `(S,content_node_id,ordinal)`；说话人缺失为空，不按相同姓名合并发言；声音映射归生成spec |
| `textbook_vocabulary_rows` | `content_node_id uuid NN`；`ordinal integer NN`；`term text NN`；`reading,part_of_speech,meaning,example text NULL` 原书对应列；`source_locator jsonb NN`；`schema_version smallint NN`；`extra_columns jsonb NULL` 具稳定列键的原书额外列 | UQ `(S,content_node_id,ordinal)`；缺列保持NULL；同词多行不去重，收藏另建本人collection，不把本表当词汇掌握 |
| `textbook_table_cells` | `content_node_id uuid NN`；`row_index,column_index integer NN` 从1起；`row_span,column_span integer NN DEFAULT 1`；`is_header boolean NN DEFAULT false`；`source_locator jsonb NN`；`schema_version smallint NN`；`display_payload jsonb NN` 受控单元格内容 | UQ `(S,content_node_id,row_index,column_index)`；行列/跨度>0，发布服务验合并格不重叠/越界；不能展平丢列关系 |
| `textbook_content_node_question_links` | `content_node_id uuid NN`；`exercise_question_id uuid NN` 不可变公共题版本；`grading_basis_id uuid NULL` 无依据可空；`ordinal integer NN`；`readiness varchar(24) NN` ready/needs_review/unavailable；`schema_version smallint NN`；`source_refs jsonb NN` | UQ `(S,content_node_id,ordinal)`、`(S,content_node_id,exercise_question_id)`；IX `(S,exercise_question_id,id)`；题面、选项/空位、题组与隐藏依据见学习分册，不复制评分；无依据不伪装标准答案 |

根级Lesson直接由继承V列的material_revision_id确定归属，不创建虚构Unit或借“待整理内容”包装已知课程。unit_id存在时服务在material→revision共同锁内核对Unit与Lesson同owner/library/material/revision；空值时按根级Lesson的部分唯一索引约束顺序，不依赖NULL相等语义。目录允许根Unit与根Lesson并列，根项ordinal在该版本的两类根项间由发布服务统一校验不重复并按原书顺序编排；Unit子层及课内节点仍按各自父容器排序。无Unit教材、混合根目录、同序并发写入与跨版本Unit引用均纳入阶段2验收。

### 3.3 阅读、书签、出处重绑

scope=library_owned；临时选区不持久建行，不设置“继续阅读/最近在读”推荐表。考试不用本组表记录答题进度。

| 表/列组 | 列（PG类型；空值/默认；语义） | 唯一、检查与索引/生命周期 |
| --- | --- | --- |
| `material_reading_progress` / V+R | `material_type varchar(16) NN` 仅novel/textbook；`last_locator jsonb NN`；`furthest_locator jsonb NULL` 仅小说；`last_order_key bigint NN`；`furthest_order_key bigint NULL` 小说源序度量；`accepted_at timestamptz NN` 服务接受时间；`client_instance_id uuid NN` 已验证设备/安装范围；`client_operation_seq bigint NN` 当前提交端递增序号 | UQ `(S,material_id,material_revision_id)`；IX `(S,material_id,accepted_at DESC,id)`；CHECK 序号非负、小说furthest配对且>=last_order_key、课本furthest全空。材料根+进度行锁/CAS；回读只改last，同版最远单调；新版本另行记录，旧定位不静默搬移 |
| `material_bookmarks` / V | `locator jsonb NN`；`locator_digest bytea NN` 精确规范定位摘要32字节；`title text NULL` 短标题；`schema_version smallint NN` | UQ `(S,material_revision_id,locator_digest)`；IX `(S,material_id,created_at,id)`；摘要命中再比规范locator防碰撞，删除通过服务显式解除，不新增文件夹/全文搜索；原材料删除时书签可保留快照但禁回跳 |
| `material_reading_open_events` / V | `open_request_id uuid NN` 业务去重；`opened_at timestamptz NN` 服务接受时间；`locator jsonb NN`；`schema_version smallint NN` | UQ `(S,open_request_id)`；IX `(S,opened_at,id)` 有界本人历史/计数；追加只读，不以遥测重放制造学习事实；留存上限由操作配置锁定，不建无限点击流水 |
| `material_source_rebindings` / M | `source_kind varchar(32) NN` material_content/exam_listening_script；`source_version_id,target_version_id uuid NN` 同种版本；`source_locator jsonb NN`；`target_locator jsonb NULL` 仅resolved有值；`source_locator_digest bytea NN` 32字节；`schema_version smallint NN`；`status varchar(24) NN` resolved/ambiguous/unresolved；`mapping_method varchar(40) NN`；`validated_at timestamptz NN` | UQ `(S,source_kind,source_version_id,target_version_id,source_locator_digest)`；目标为唯一且程序验证才resolved，其他保留旧快照；文本相同不跨材料匹配 |

CHECK `material_source_rebindings.status='resolved'` 时必需target_locator，反向禁止非resolved携带可直接导航目标。源/目标版本、隐藏听力投影与quote范围由服务逐个验证，普通sources接口不能借重绑返回隐藏稿。位置/书签创建和材料删除均锁材料根；阅读冲突由expected_revision显式处理，离线只保留本次页面位置，不排队写进度。

## 4. 试卷准备与冻结

### 4.1 `exam_papers` — 试卷聚合根

列组 M + R，scope=library_owned；material_type必须为exam。材料根 → paper根为准备/发布共同锁顺序。

| 列 | PG类型/空值/默认 | 语义 |
| --- | --- | --- |
| current_draft_version_id, current_ready_version_id | uuid NULL | 当前可编辑草稿和最近可开考版本分开 |
| preparation_generation, listening_generation | bigint NN DEFAULT 0 | 新解析/听力候选隔离代次 |

UQ `(S,material_id)`。新草稿不使旧ready场次改版；删除材料后不允许新开考/准备，但旧场次从冻结引用读取。

### 4.2 `exam_paper_versions` — 草稿到不可变冻结卷

列组 V + R；scope=library_owned。ready前以expected_revision校对，ready后冻结所有内容/关联/播放策略；修订需创建新版本。

| 列 | PG类型/空值/默认 | 语义 |
| --- | --- | --- |
| exam_paper_id | uuid NN | 同材料试卷根 |
| version_number | bigint NN | >=1，同paper编号 |
| parent_version_id | uuid NULL | 修订来源 |
| schema_version | smallint NN | 题面结构协议 |
| status | varchar(24) NN | preparing/needs_review/ready；needs_audio由准备issue表示 |
| title | text NN | 冻结标题 |
| language | varchar(35) NN | 考试题目目标语 |
| instructions | text NULL | 原卷/人工确认说明 |
| duration_seconds | integer NULL | NULL不限时；有值>0；不能默认60分钟 |
| total_points | numeric(10,2) NULL | 校对前可空；ready必有，程序累计叶子 |
| points_origin | varchar(24) NN | original/user_confirmed，默认分必须经确认 |
| schema_payload | jsonb NN | 本行schema的计分/辅助配置与必需客户端能力，不含题目全集 |
| content_digest | bytea NULL | ready时32字节，含冻结子表身份与版本 |
| frozen_at | timestamptz NULL | ready必有 |
| frozen_by_user_id | uuid NULL | 本人确认者，与frozen_at成对 |
| input_delete_generation | bigint NN | 发布验材料未删除及代次 |

UQ `(S,exam_paper_id,version_number)`；IX `(S,exam_paper_id,status,id)`。CHECK finite数值且非负、合法时长、冻结列同空同有；ready的全量子项、sum、必要媒体、人工确认与投影检查由发布服务完成，模型不可自报ready。无答案题允许依据待准备，但初次/后补参考不能根据本场答卷生成标准。

### 4.3 题序、共享材料与受限依据

均为 V，scope=library_owned；冻结后不可更改。所有表带 `exam_paper_version_id uuid NN`，下表不重复列出。ExamItem仅计分叶子，共享材料/Section不计分。

| 表 | 其余列（PG类型；空值/默认；语义） | 唯一、检查与索引 |
| --- | --- | --- |
| `exam_sections` | `parent_section_id uuid NULL`；`ordinal integer NN` 版本内全序；`title text NN`；`instructions text NULL`；`schema_version smallint NN`；`source_refs jsonb NN` | UQ `(S,exam_paper_version_id,ordinal)`；禁自父，服务验无环；任选等未实现规则阻止ready，不存未执行的伪规则 |
| `exam_stimuli` | `section_id uuid NN`；`ordinal integer NN` section内序；`kind varchar(24) NN` reading/image/table/listening；`schema_version smallint NN`；`presentation_payload jsonb NN` 题面专用有界载荷；`source_refs jsonb NN`；`visibility varchar(24) NN` preparation/exam/post_submit；`required boolean NN` | UQ `(S,section_id,ordinal)`；题图只能引用验证的题面资产；listening题面无脚本/答案；必需媒体不能缺失后直接丢弃 |
| `exam_items` | `section_id uuid NN`；`exercise_question_id uuid NN` 公共不可变题版本；`grading_basis_id uuid NULL` 确切隐藏依据版本；`ordinal integer NN` 全卷序；`original_number text NULL` 原题号；`business_type varchar(40) NN`；`interaction_type varchar(24) NN` 五类；`delivery_mode varchar(16) NN` visual/listening/mixed/unknown；`max_points numeric(10,2) NN`；`schema_version smallint NN`；`source_refs jsonb NN` | UQ `(S,exam_paper_version_id,ordinal)`、`(S,exam_paper_version_id,exercise_question_id)`；IX `(S,exercise_question_id,id)`；分值有限非负；ready不可unknown；公共题版本只复用纯题型/正文，分值/依据与试卷快照一致 |
| `exam_stimulus_item_links` | `stimulus_id,exam_item_id uuid NN`；`ordinal integer NN` stimulus内题序；`confirmation_status varchar(24) NN`；`confirmed_by_user_id uuid NULL`；`confirmed_at timestamptz NULL`；`schema_version smallint NN`；`evidence_refs jsonb NN` | UQ `(S,stimulus_id,exam_item_id)`、`(S,stimulus_id,ordinal)`；IX `(S,exam_item_id,id)`；确认列成对；冻结前同版本/题范围完整校验 |
| `exam_preparation_issues` | 另含R；`kind varchar(64) NN`；`exam_item_id,stimulus_id,candidate_id uuid NULL` 类型要求的目标；`severity varchar(16) NN`；`status varchar(24) NN` open/resolved/rejected；`schema_version smallint NN`；`evidence_refs jsonb NN`；`resolution_code varchar(64) NULL`；`resolved_by_user_id uuid NULL`；`resolved_at timestamptz NULL` | IX `(S,exam_paper_version_id,status,severity,id)`；受控kind按[试卷问题代码](../contracts/material-structures.md#51-首版输入与候选结构)注册，包括listening_type_review/listening_binding_review/listening_script_missing/listening_audio_missing/language_confirmation_required；必要问题关闭必须绑定具体改版/确认，不允许只换状态 |

契约逻辑对象 `ExamOption/ExamBlank/ExamGradingBasis` 物理映射到学习分册的公共题目选项/空位及 `question_grading_bases`；`exam_items.exercise_question_id/grading_basis_id` 冻结确切行ID。答案、rubric、隐藏解释不进入题面JSON、题图、朗读、Semantics或题面Redis键；完整原件只在本人校对动作组合下读取。

## 5. 文字听力稿、候选、确认与音频

### 5.1 文字稿版本

各表为 V、scope=library_owned；paper/草稿根与材料根保护来源、候选确认和发布。文件上传稿不改已有MaterialRevision的SourceAsset集合。

| 表 | 列（PG类型；空值/默认；语义） | 唯一、检查与索引 |
| --- | --- | --- |
| `exam_listening_script_sources` | `exam_paper_id,base_paper_version_id uuid NN`；`source_kind varchar(24) NN` uploaded_text/exam_content；`file_object_id uuid NULL` 专用文本用途；`source_locator jsonb NULL` 主卷合法范围；`schema_version smallint NN`；`source_digest bytea NN` 32字节 | IX `(S,exam_paper_id,created_at,id)`；CHECK上传有file无locator、正文有locator无file；同本人/基准版本/专用purpose由服务验；内容不可变，原始音频/任意URL拒绝 |
| `exam_listening_script_versions` | 另含R；`script_source_id uuid NN`；`version_number bigint NN` >=1；`parent_script_version_id uuid NULL`；`language varchar(35) NN`；`text_protocol_version varchar(40) NN`；`origin varchar(24) NN` extracted/user_correction；`confirmation_status varchar(24) NN` candidate/confirmed/rejected；`confirmed_by_user_id uuid NULL`；`confirmed_at timestamptz NULL`；`content_digest bytea NN`；`schema_version smallint NN`；`edit_provenance jsonb NULL` 父版受控编辑操作 | UQ `(S,script_source_id,version_number)`；确认字段配对且CAS revision；正文由segments唯一持有，改字/插入/删段/重排必建新版；确认仅改确认元数据不改文本；digest32字节 |
| `exam_listening_script_segments` | `script_version_id uuid NN`；`ordinal integer NN`；`canonical_text text NN`；`scalar_length integer NN`；`speaker_label text NULL`；`pause_after_ms integer NULL`；`schema_version smallint NN`；`provenance_refs jsonb NN` | UQ `(S,script_version_id,ordinal)`；长度非负、pause非负且受能力上限；本段是当前locator唯一文本容器；FileObject字节/原ContentBlock仅出处，不冒充本段偏移 |

### 5.2 有代次的AI候选与人工绑定

各表为 V、scope=library_owned；候选输出与用户确认保持分离。所有表带 `exam_paper_version_id uuid NN`。

| 表 | 其余列（PG类型；空值/默认；语义） | 唯一、检查与索引 |
| --- | --- | --- |
| `exam_listening_candidates` | 另含R；`ai_run_id uuid NN`；`generation bigint NN`；`ordinal integer NN`；`candidate_kind varchar(24) NN` item_type/script/item_binding；`exam_item_id,script_version_id,stimulus_id uuid NULL` 按kind约束；`proposed_delivery_mode varchar(16) NULL`；`confidence_status varchar(24) NN` 复核标签而非概率；`schema_version smallint NN`；`evidence_refs jsonb NN`；`unresolved_cues jsonb NN`；`status varchar(24) NN` pending/confirmed/rejected/superseded；`reviewed_by_user_id uuid NULL`；`reviewed_at timestamptz NULL` | UQ `(S,ai_run_id,ordinal)`；IX `(S,exam_paper_version_id,generation,status,id)`；非负generation；kind对应字段必需/禁用，item_type有item和候选mode；script有script版本；item_binding有script/stimulus且多题由下表引用；旧generation只历史入库不得覆盖人工确认 |
| `exam_listening_candidate_item_links` | `candidate_id,exam_item_id uuid NN`；`ordinal integer NN` | UQ `(S,candidate_id,exam_item_id)`、`(S,candidate_id,ordinal)`；服务确认同卷、有效题号/范围及证据，模型ID不能直接授予引用 |
| `exam_listening_bindings` | 另含R；`stimulus_id,script_version_id uuid NN`；`source_candidate_id uuid NULL` 人工从合法源建立可空；`confirmed_candidate_generation bigint NN`；`status varchar(24) NN` draft/confirmed/rejected；`confirmed_by_user_id uuid NULL`；`confirmed_at timestamptz NULL` | UQ `(S,exam_paper_version_id,stimulus_id)`；脚本唯一绑定该stimulus，其题目集合由同卷exam_stimulus_item_links提供；确认锁草稿、候选与引用目标，校验expected_revision、generation及人工改稿版本 |
| 同表：音频选用与播放策略 | `selected_synthesis_spec_id uuid NULL`；`play_limit_mode varchar(16) NULL` unlimited/finite；`max_plays integer NULL`；`allow_pause,allow_seek,allow_speed_change boolean NULL`；`transcript_visibility varchar(32) NULL` hidden/post_submit/approved_accessibility；`policy_schema_version smallint NULL`；`accessibility_settings jsonb NULL`；`policy_confirmed_by_user_id uuid NULL`；`policy_confirmed_at timestamptz NULL` | selected_synthesis_spec_id是独立音频指针，允许在策略确认前或后设定；其余列为播放策略组，未确认时全空，确认后除max_plays外齐全，finite需>0，unlimited为空。ready卷要求策略已确认且selected spec属于本binding、状态ready；本行与卷共同冻结，策略变更需新卷版本 |

用户选择题组时服务端展开具体叶子题，正式关联逐项进入 `exam_stimulus_item_links`；不把item_ids永久只保存在JSON。每个疑似听力题和候选关系必须有对应preparation issue。确认、拒绝、改绑更新对应revision/操作者与Outbox；文字稿确认不自动执行模型/TTS调用。

### 5.3 合成规格、音频版本与播放规则

各表为 V、scope=library_owned；所有表带 `exam_paper_version_id uuid NN`。音频资产/manifest与分段时间映射定义在学习分册，必须是本人私有音频，不进入global_word目录。

| 表 | 其余列（PG类型；空值/默认；语义） | 唯一、检查与索引 |
| --- | --- | --- |
| `exam_listening_synthesis_specs` | 另含R；`listening_binding_id,script_version_id uuid NN`；`spec_number bigint NN`；`provider,model varchar(160) NN`；`provider_credential_id uuid NN`；`credential_version bigint NN` 受理版本事实；`output_format varchar(24) NN`；`schema_version smallint NN`；`voice_mapping,parameters jsonb NN` 受控能力参数；`synthesis_digest bytea NN` 严格内容/配置摘要；`generation bigint NN` | UQ `(S,listening_binding_id,spec_number)`；IX `(S,synthesis_digest,id)` 持久结果查找；digest32字节，序号>=1；Key不入行/JSON，换Key不使成功内容缓存失效；调用前仍检查当前凭据权限 |
| 同表：音频发布状态 | `audio_asset_id,playback_manifest_id uuid NULL`；`status varchar(24) NN` pending/generating/ready/failed/sealed；`job_id uuid NN`；`duration_ms bigint NULL`；`validated_at timestamptz NULL` | IX `(S,playback_manifest_id,id)`；ready时audio/manifest/duration/validated全有且duration>0；spec配置列创建后不可变，Worker只更新本组状态，发布核对人工binding/script/generation |

AudioBinding是一份SynthesisSpec的发布状态，逻辑audio_binding_id映射exam_listening_synthesis_specs.id；PlaybackPolicy是一份已确认Binding的值对象，逻辑policy_id映射exam_listening_bindings.id。API仍返回各自白名单DTO，不返回隐藏脚本或凭据。省去两张一对一表后，ready校验仍逐项验证所选spec、本人音频/manifest及播放策略；新规格保留旧行，失败不改旧ready卷的选用。场次使用冻结binding/spec ID读取，不能追随新草稿指针。

speaker/voice映射、SSML等仅经能力目录结构化构造，不接受任意Header/控制指令。TTS源先验证不属于答案/rubric范围；未经确认、缺稿、失败音频均阻止ready。已确认script、spec配置组及已发布manifest均不可变；同配置本人持久命中不新增供应商attempt。

## 6. 考试场次、答卷与听力账本

### 6.1 `exam_sessions` — 计时、编辑端与评分指针

列组 L + R，scope=library_owned；`material_id` 在此作为历史来源引用，材料tombstone后场次仍有独立授权的冻结快照。

| 列 | PG类型/空值/默认 | 语义 |
| --- | --- | --- |
| material_id, exam_paper_id, exam_paper_version_id | uuid NN | 创建时固定来源/试卷/冻结版本 |
| status | varchar(24) NN | in_progress/submitted/abandoned |
| started_at | timestamptz NN | 服务端开始时刻 |
| deadline_at | timestamptz NULL | 服务端截止，NULL不限时 |
| submitted_at, abandoned_at | timestamptz NULL | 终态时间，按状态互斥 |
| submit_reason | varchar(16) NULL | manual/timeout，submitted必有 |
| edit_epoch | bigint NN DEFAULT 1 | 活动编辑端代次，>=1 |
| editor_instance_id | uuid NN | 已验证客户端实例，仅本场持有编辑权 |
| current_exam_item_id | uuid NULL | 已接受答题卡位置，不当作答案 |
| schema_version | smallint NN | 冻结辅助/客户端协议载荷版本 |
| auxiliary_settings | jsonb NN | 开考前确认的题面朗读/可见辅助策略 |
| submission_digest | bytea NULL | 锁卷全部答案规范摘要32字节 |
| grade_generation | bigint NN DEFAULT 0 | 新评分/显式重评代次 |
| active_grade_run_id, effective_grade_run_id | uuid NULL | 公共grading_runs；进行中与有效成绩分开 |
| media_fault_revision | bigint NN DEFAULT 0 | 本场已确认必要媒体事实版本，发布CAS一起检查 |

IX `(S,exam_paper_id,started_at DESC,id DESC)` 历史及查询既有场次；IX `(status,deadline_at,id) WHERE status='in_progress' AND deadline_at IS NOT NULL` 固定职责截止扫描。既有未完成场次优先显示续答，幂等记录防止同一次开考重试重复创建，不额外规定用户永远只能有一场未完成考试。CHECK 终态时间/理由组合、deadline晚于started、代次非负。开始事务锁material→paper→冻结版本，预检必要音频并确认当前动作/客户端能力后建立计时场次；保存/接管/提交/超时共锁session，外部检查在锁外完成再锁内重验。

### 6.2 `exam_session_answers` — 草稿与锁定答卷

列组 L + R，scope=library_owned；服务/API逻辑对象 ExamResponse 映射此表，不另外创建 exam_responses。

| 列 | PG类型/空值/默认 | 语义 |
| --- | --- | --- |
| exam_session_id, exam_paper_version_id, exam_item_id | uuid NN | 同场次同冻结卷叶子 |
| answer_schema_version | smallint NN | 五类答案结构版本 |
| answer_payload | jsonb NULL | NULL明确未答；判断false是有效答案；选项/空位使用稳定ID |
| is_marked | boolean NN DEFAULT false | 稍后检查标记，与作答内容分开 |
| accepted_at | timestamptz NULL | 最近一次服务端接受答案时间 |
| edit_epoch | bigint NN | 最近接受的编辑代次 >=1 |
| client_operation_seq | bigint NN | 本编辑端递增序号，非负 |
| locked_at | timestamptz NULL | 交卷后不允许修改答案/标记 |
| question_attempt_id | uuid NULL | 锁卷时创建的公共question_attempts，不在草稿阶段逐题评分 |

UQ `(S,exam_session_id,exam_item_id)`；UQ `(S,question_attempt_id) WHERE question_attempt_id IS NOT NULL`；IX `(S,exam_session_id,locked_at,id)`。开考可以逐叶子创建空答案行，提交必须对全部叶子形成锁定快照，不能只保存“已答”从而漏计空答/媒体故障。普通草稿保存不分配学习接受序号，锁session检查截止/编辑代次，再CAS本行revision；迟到返回不覆盖新值。交卷/超时创建公共attempt并分配accepted_sequence时，必须在授权外层锁之后先锁本人library的 `library_learning_acceptance_counters`，再锁session→answer，按稳定叶子序在同事务分配序号；不得先持有session再补锁计数器，以免与辅助曝光路径形成反锁。手动交卷、截止任务和幂等重放统一使用这一顺序。锁卷、公共attempt创建、grading请求（若显式要求）与Outbox同事务；纯交卷保留未请求评分。

### 6.3 `exam_session_listening_usages` — 场次×共享听力计数

列组 L + R，scope=library_owned。

| 列 | PG类型/空值/默认 | 语义 |
| --- | --- | --- |
| exam_session_id, exam_paper_version_id, stimulus_id | uuid NN | 冻结场次与共享材料 |
| listening_binding_id, synthesis_spec_id | uuid NN | 精确冻结策略所属binding及音频spec；API逻辑policy/audio_binding的物理映射 |
| play_limit_mode | varchar(16) NN | 冻结unlimited/finite |
| max_plays | integer NULL | finite为>0，unlimited为空 |
| reserved_count, consumed_count | integer NN DEFAULT 0 | 未首字节占位和已消费次数，均>=0 |

UQ `(S,exam_session_id,stimulus_id)`；CHECK finite时 `reserved_count + consumed_count <= max_plays`。创建场次时建立需要的usage，刷新/跨端不重新初始化。计数是PG事务内维护的账本汇总，play_attempts为明细；修复须受控核对，不能从客户端重算。unlimited可保留相同传输attempt以支撑恢复，但不执行有限次数拒绝，不将max_plays设成巨大魔数。

### 6.4 `exam_session_listening_play_attempts` — 首字节、续播与终态事实

列组 L + R，scope=library_owned；id 即接口 play_attempt_id。

| 列 | PG类型/空值/默认 | 语义 |
| --- | --- | --- |
| exam_session_id, usage_id, stimulus_id | uuid NN | 领取归属 |
| idempotency_key_hash, request_digest | bytea NN | 规范键摘要、请求摘要各32字节；scope与动作参与命名 |
| issued_edit_epoch | bigint NN | 最初领取的编辑代次 |
| authorized_edit_epoch | bigint NN | 当前允许媒体请求的代次；显式接管可受控推进 |
| playback_manifest_id, audio_asset_id | uuid NN | 冻结音频确切版本 |
| status | varchar(24) NN | reserved/active/completed/closed_unknown/void |
| reserved_at, reservation_until_at | timestamptz NN | 领取及短期限 |
| first_byte_committed_at | timestamptz NULL | 在发字节前持久CAS为active并计次的时间 |
| resume_until_at | timestamptz NULL | bounded active续播期限，不超过场次截止 |
| delivered_segment_ordinal | integer NULL | 已确认的连续交付segment位置 |
| delivered_byte_offset | bigint NN DEFAULT 0 | 当前segment内已交付游标；非负 |
| final_byte_delivered_at, closed_at | timestamptz NULL | 确认终段/不可逆关闭时间 |
| close_reason | varchar(64) NULL | 完成/无法确认/零字节证明原因 |
| delivery_fence | bigint NN DEFAULT 0 | 媒体领取与持久游标CAS代次，防两个传输者同时失序 |

UQ `(S,exam_session_id,idempotency_key_hash)`；IX `(S,usage_id,status,id)`；IX `(status,reservation_until_at,id) WHERE status='reserved'` 与 `(status,resume_until_at,id) WHERE status='active'` 支撑受控超时关闭。CHECK 摘要长度、代次>=1、reservation期限晚于领取、active/终态时间组合；实际字节范围与Manifest段长由媒体服务验证。

先锁 session，再锁 usage，复核当前动作、edit_epoch、截止与冻结策略，原子 reserved_count++并插入attempt；同键不同摘要冲突，同键重试返回同一attempt。首字节前同事务 reserved--/consumed++并CAS active；只有从未领取的过期reservation或服务端能证明零字节的故障可void释放。active且有界才可签名刷新/按策略续播；completed与closed_unknown保留consumed且不可重开。显式接管锁session并推进edit_epoch，旧端失效，只将尚可续播attempt的authorized_edit_epoch推进给新端，不能重置issued代次、次数或期限。播放策略不允许seek时拒绝回退范围；有限次数音频不进入通用持久离线缓存。

### 6.5 必要媒体故障事实

两表为 L、scope=library_owned；仅服务器确认事实，不接收客户端任意URL或自报受影响题目。session为共同保护行。

| 表 | 列（PG类型；空值/默认；语义） | 唯一、检查与索引 |
| --- | --- | --- |
| `exam_session_media_faults` | 另含R；`exam_session_id,exam_paper_version_id uuid NN`；`asset_kind varchar(24) NN` source_asset/audio_asset；`asset_id uuid NN` 已冻结必需资产；`confirmed_at timestamptz NN`；`reason_code varchar(64) NN`；`status varchar(24) NN` confirmed；`fault_revision bigint NN` 对应session递增事实版本；`idempotency_record_id uuid NN` | UQ `(S,exam_session_id,asset_kind,asset_id)`；IX `(S,exam_session_id,fault_revision)`；asset_kind联合引用按注册目标校验；只在可作答且期限内确认，P0无人工清除/改分状态 |
| `exam_media_fault_item_links` | `fault_id,exam_item_id uuid NN`；`exam_session_id uuid NN` | UQ `(S,fault_id,exam_item_id)`；IX `(S,exam_session_id,exam_item_id,id)` 评分阻断查询；受影响叶子由冻结投影推导，不信任客户端列表 |

故障与session.media_fault_revision同事务提交；锁卷保留事实，资源后来恢复不抹除本场影响。grading_runs领取/恢复/effective发布同时核对当前fault_revision，受影响题needs_review，不能空答零分或发布整卷有效贡献。锁卷后新报告不追认；P0提示新场次重考。评分代次/逐题结果/学习贡献只在学习分册维护，session active/effective 指针遵循[数据事务](data-jobs.md#6-评分代次与学习贡献)。

## 7. 逻辑关系、锁与删除清单

所有新增/重绑/发布/GC先取得授权外层锁，再按本表顺序锁同一聚合；同层多个ID升序。不得为了GC反向先锁子对象再锁材料根。对象传输、模型调用和解码不持有长事务。

| 来源 → 目标 | 所有者/版本校验与共同保护行 | 删除与保留语义 |
| --- | --- | --- |
| material_imports/upload_intents → users/libraries/目标聚合/容量预留 | 授权外层→容量根（同时涉及时global→user）→library/目标根；同用户、用途、有效意图、配额与generation | 未发布可到期；user_storage_reservations幂等释放；已引用final禁止临时TTL清理 |
| materials/material_source_assets/script_sources → file_objects | material→paper（适用）→file；本人/合法purpose/verified final，按目标动作签名 | 解除材料引用不自动删除文件；复用新材料/听力/其他业务引用均需复核 |
| material_source_units/material_content_blocks/三类manifest → material_revisions | material根；同owner/library/material/revision/type，parent无环 | 发布后不可变；有书签/结果/冻结快照/在途任务引用就保留必要范围 |
| text_analysis_versions/units/sentences → 注册来源版本/字段 | SourceAdapter规定的源根→分析头→单元；同scope/版本、合法scalar与完整spans | 原文/源ruby与派生标注版本分开；新分析不改旧句，GC包括成品引用和JSON路径 |
| textbook_content_node_question_links/exam_items → exercise_questions/question_grading_bases | material→paper（适用）→公共题根；同scope/不可变版本/合法用途 | 已提交attempt/冻结场次保留题面、依据及必要题图，不靠删材料级联 |
| listening候选/绑定 → 脚本版本/Stimulus/Item | material→paper→草稿版本；generation、expected_revision及同卷全体关系 | 旧run只历史，人工确认不被迟到覆盖；已冻结绑定不能原地换脚本/音频 |
| synthesis_specs/binding策略 → 私有音频/manifest | material→paper→binding→音频根；本人、严格规格、验证完成 | 持久成功不得按Redis TTL删；历史场次引用保留，允许清理无引用失败产物 |
| exam_sessions/answers → 冻结卷/题/依据 | 新开考先material→paper；草稿保存session→answer；交卷/超时等有学习计序的路径统一library_learning_acceptance_counters→session→answer，验证冻结ID和当前场次动作 | material删除不终止已有合法场次或清除已保存答卷；不提供完整原书读取旁路 |
| usage/attempt/fault → session/冻结媒体 | session→usage→attempt或fault；edit_epoch、状态、deadline、asset版本 | 次数与交付事实持久，不能Redis清空后重置；终态不重开，故障不自动撤销 |
| reading/bookmark/rebindings → 内容/脚本版本 | material→相应paper/script根→记录；同scope/版本/投影/边界 | 原版失效保留快照或明确不可回跳；不能按相同字串猜另一版本 |

材料删除在同事务写deleted_at、递增delete_generation并拒绝新引用/新供应商阶段；Worker发布对比冻结输入generation。GC先列出全部真实关系（含注册JSON locator spans、持久学习结果/音频、共享原件的新材料引用、在途安全处理），再在共同父锁内复核。仅无保留引用对象进入配置的宽限期，不能把推荐7天当不可变业务默认。对象删除与PG分步确认，失败保留重试状态；日志仅记录受限ID/数量/错误码。

既有场次引用从“普通材料读取”转为“冻结考试内容读取”不是修改owner或开放管理员旁路。冻结题面可以在材料删除后复盘，完整原件及删除原文不可重新签名；收藏只保留自身所需快照。已删除材料根至少保留到相关代次检查/冻结引用释放完成，不能提前物理删除保护行。

## 8. 索引落地与未决边界

上述UQ/IX是首版建表候选清单，基于已明确的分页、源加载、冻结查询、超时扫描和GC访问路径；未执行EXPLAIN、容量测试或性能验收。迁移必须将索引名称、JSON关系路径、父锁、默认值、nullable和业务CHECK登记为机器可验数据字典，长名按规范确定性缩短。

实现按阶段拆分：阶段2落上传/源层/三类预览与必要听力校对；阶段3接解释、持久音频/来源映射；阶段4落普通题作答/评分，阶段5落整卷作答、评分、播放次数及故障闭环。不提前把存在字段当作整条功能已交付。首版试卷主文件格式（OPEN-01）、缺答案预生成（OPEN-05）、文字稿容量/能力参数与具体内容保留期限仍按[待决清单](../decisions/pending.md)和配置样本锁定；原始音频上传/转写/自动绑定（OPEN-12）仍为P1，不因存在file_objects就开放。论文式全书JSON、第四材料类型、SRS/复习队列、跨用户私有去重、完整离线考试、手改成绩和商业金额字段均不在本设计范围。
