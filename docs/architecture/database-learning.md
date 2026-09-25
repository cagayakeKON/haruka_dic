# 数据库设计书：收藏、学习、AI 与持久结果

状态：2026-09-25，DBDESIGN3 命名与关系稿；除 7.5 引用既有 B0 Outbox 基线外，**新增表与扩展列均待实现**。本次只给出 PostgreSQL 物理设计建议，不创建 ORM、迁移或真实业务数据。总则、已实现结构和 Redis 字典见[设计书主册](database-design.md)；材料、文件与考试场次见[材料分册](database-materials.md)，本册全部表的归属和基数见[关系清单](database-relations.md#23-收藏学习ai与任务62张)。本分册承接现行产品/原型，不能把原型中的内存 `mastery`、`correct`、图片 URL 或示例 ID 直接作为数据库事实。

权威业务依据：[收藏与公共作答](../modules/vocabulary-practice.md)、[多单词本](../modules/vocabulary-notebooks.md)、[学习证据](vocabulary-learning.md)、[AI习题与错题](../modules/ai-exercises.md)、[查询](../modules/query.md)、[Agent运行](agent-runtime.md)、[AI与朗读](../modules/ai-speech.md)、[持久结果缓存](learning-cache.md)、[任务与事务](data-jobs.md)、[模型用量](../contracts/model-usage.md)、[CSV](../contracts/vocabulary-csv.md)。表名是本次设计选择，接口中的 ExerciseVersion/Attempt/GradeRun 等逻辑名称按下文映射，不能据此静默改接口。

## 1. 字典记法与关系规则

- `B`：`id uuid NN`（服务端 uuid4，无数据库默认值）、`created_at timestamptz NN DEFAULT now()`、`updated_at timestamptz NN DEFAULT now()`。
- `L`：`B` 加 `owner_user_id uuid NN`、`library_id uuid NN`，登记为 `library_owned`。`UO`：`B` 加 `owner_user_id uuid NN`，登记为 `user_owned`，不再增加 `user_id`。
- `R`：`revision bigint NN DEFAULT 1 CHECK(revision >= 1)`。`NN` 为 NOT NULL，`NULL` 为可空且默认 NULL；除明确列出的默认值外，非空列均由服务端显式赋值。字段行中以逗号并列的字段是分别存在的同类型列，非逗号字符串。
- `scope` 在索引简写中仅指 `(owner_user_id,library_id)`，不是物理字段；`owner` 指 `owner_user_id`。所有表有 B 的主键；`UK` 为 UNIQUE/唯一索引，`IX` 为普通访问索引，未写谓词的唯一键覆盖全生命周期。
- 所有摘要列采用 `bytea`、`CHECK(octet_length(列)=32)`，表示服务端规范化序列化后的 SHA-256 或带版本的服务器摘要；不能接受客户端摘要作为授权。必要摘要不写日志。`*_version`/代次非空时 `>=1`，计数/字节/时长 `>=0`，序号从 1 开始；下文另列零初值的代次允许 0。
- JSONB 必须有下列版本列或载荷内登记的 `schema_version`，并由 Pydantic 验证结构、大小、枚举及引用。JSONB 不承担归属/唯一键/主状态；只给真实过滤路径建索引，不默认建 GIN。
- 全部为**逻辑关联，无物理外键、ORM 级联或 RLS 保证**。每次读取、连接、批量、签名和写入逐表限制 scope。创建/替换引用与删除/GC 使用相同父行锁；先按授权规定锁身份，再按本分册列明聚合及稳定 UUID 顺序锁父对象，不能在锁内调用供应商。
- 行内 CHECK 仅验证本行：类型、字段组合、分数范围、状态形状；跨表所有者、父存在性、版本、作用域及删除代次必须由服务事务验证。表中业务枚举未列穷举时须引用权威 schema，实施迁移前冻结登记，不自行接受任意字符串。

公共可追溯来源组 `S`（按需明确引用）：`source_kind varchar(32) NN`、`source_resource_id uuid NULL`、`source_version bigint NULL`、`source_locator jsonb NULL`、`source_title text NULL`、`source_snapshot jsonb NN`、`source_schema_version integer NN`。资源来源要求 ID/版本成对有值；手工/CSV/照片来源允许无资源 ID。locator 遵循[出处协议](../contracts/content-locator.md)，不能用 JSON 内的 owner 授权；不可访问原材料时只返回当前对象获准保留的快照。

## 2. 收藏、词本与导入

### 2.1 `collection_items` — 收藏条目

公共列：L + R + S。本人收藏入口读写；物理删除前先 tombstone，保留历史题答/错题必要快照。

| 列 | PG类型 / NULL / 默认 | 含义 |
| --- | --- | --- |
| kind | varchar(16) NN | word/phrase/grammar/sentence/excerpt/exercise |
| display_text, normalized_text | text NN | 显示原文与确定性检索值分开 |
| target_language | varchar(35) NN | 经校验的目标语，不等于解释语言 |
| lemma, reading, meaning, context, notes | text NULL | 词典形、读音、释义、上下文与私人笔记 |
| payload, payload_schema_version | jsonb NN / integer NN | 六类完整载荷；exercise 只来自已校验卡片 |
| origin | varchar(24) NN | manual/selection/agent/exercise/csv_import/photo_import |
| card_id, card_revision | uuid NULL / bigint NULL | 原始已提交卡片版本，成对存在 |
| learning_revision | bigint NN DEFAULT 1 | 实质词形/语言/义项/读音变化递增 |
| exercise_control | varchar(16) NN DEFAULT 'active' | active/excluded；不改掌握证据 |
| source_created_at, source_updated_at | timestamptz NULL | CSV 历史时间，不能覆盖公共时间 |
| imported_mastery_snapshot | jsonb NULL | CSV 状态/策略版本的非权威来源声明 |
| deleted_at | timestamptz NULL | 条目 tombstone |
| delete_generation | bigint NN DEFAULT 0 | 删除防迟到代次，CHECK >=0 |

约束/索引：UK `(scope,card_id,card_revision) WHERE card_id IS NOT NULL` 保证同一卡片版本只建一次，已删卡片收藏不因重试复活；若未来允许重新收藏同一卡片需独立显式恢复契约。IX `(scope,kind,created_at,id) WHERE deleted_at IS NULL` 支撑列表和每日单词；IX `(scope,target_language,normalized_text,id) WHERE deleted_at IS NULL` 支撑词形排序；IX `(scope,source_kind,source_resource_id)` 支撑出处检查。不同义项/出处不按 lemma 唯一。含糊匹配/笔记搜索先采用有界作用域过滤；全文/模糊索引需真实样本后决定。

每日单词直接对 `kind='word'` 的实际 `created_at` 使用本人时区转换得到的 UTC 半开区间，分页与计数共用 `as_of`。不建每日调度表；归本/移动/重复收藏/CSV 补空均不改加入日期。mastery 不放在可写条目字段，来自 4.2 的只读投影。

### 2.2 `library_tags`、`collection_tag_links`、`vocabulary_notebooks`、`vocabulary_notebook_collection_links`

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 唯一、索引、生命周期 |
| --- | --- | --- |
| library_tags / L+R | `name text NN`、`name_normalized text NN` | UK `(scope,name_normalized)`；服务控制长度；删除锁 tag 后显式解除成员，不删收藏 |
| collection_tag_links / L | `collection_item_id uuid NN`、`tag_id uuid NN` | UK `(scope,collection_item_id,tag_id)`；IX `(scope,tag_id,collection_item_id)`；锁条目/tag验证双方同库 |
| vocabulary_notebooks / L+R | `name text NN`、`name_normalized text NN`、`target_language varchar(35) NN`、`description text NULL` | UK `(scope,target_language,name_normalized)`；IX `(scope,updated_at,id)`；删本显式删关系后删本，不碰收藏/证据 |
| vocabulary_notebook_collection_links / L+R | `notebook_id uuid NN`、`collection_item_id uuid NN` | UK `(scope,notebook_id,collection_item_id)`；IX `(scope,notebook_id,created_at,id)` 支撑入本时间，IX `(scope,collection_item_id,notebook_id)` 支撑删词检查 |

入本、移动、改词语言、改空本语言及删本均锁涉及的 notebook 和 collection 父行，采用统一顺序；涉及默认词本的选择/解除/删本，先锁user_extensions，再锁notebook→collection，与设置入口一致。修改本语言仅空本允许；移动是目标关系新增与指定来源关系移除的同一事务。系统“全部收藏/未分组”是查询视图，不创建伪 notebook。计数按条目 ID 去重，不存可由客户端改写的 count。

### 2.3 收藏合并字段（位于 collection_items）

每个源条目至多有一次合并去向，原条目已经必须保留tombstone，因此不另建collection_merges。collection_items增加：`merged_into_item_id uuid NULL`、`merged_source_learning_revision,merged_target_learning_revision bigint NULL`、`merge_equivalence_rule_version varchar(64) NULL`、`merged_at timestamptz NULL`；五列全空或全有，CHECK目标不等于本行id，有合并字段必须deleted_at非空。IX `(scope,merged_into_item_id) WHERE merged_into_item_id IS NOT NULL` 支撑反查。创建后合并映射不可改，不清理仍被引用的源壳。

锁源/目标条目验证同库、等价及无循环，成员迁移、tombstone与映射同事务。学习证据按原业务键去重重放，不能取更高掌握值直接覆盖。目标再合并时逐级解析保留链，不重写旧事实；公共时间不替代merged_at。

### 2.4 `collection_selection_snapshots`、`collection_selection_item_links` — 全筛选批量操作

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 约束/访问与生命周期 |
| --- | --- | --- |
| collection_selection_snapshots / L+R | `action_code varchar(128) NN`、`filter_schema_version integer NN`、`filter_payload jsonb NN`、`as_of timestamptz NN`、`expires_at timestamptz NN`、`member_count bigint NN`、`selection_digest bytea NN` | IX `(scope,expires_at,id)`；count >=0，expires_at>as_of；快照不授权执行；过期且无在途批次可回收 |
| collection_selection_item_links / L | `selection_id uuid NN`、`collection_item_id uuid NN`、`expected_revision bigint NN`、`ordinal integer NN` | UK `(scope,selection_id,collection_item_id)` 及 `(scope,selection_id,ordinal)`；锁快照/条目后写，执行重验权限/版本，不只处理当前页 |

### 2.5 `csv_import_batches`、`csv_import_rows`

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 含义 |
| --- | --- | --- |
| csv_import_batches / L+R | `file_object_id uuid NULL`、`csv_schema_version integer NULL`、`escape_protocol varchar(32) NULL`、`mapping_schema_version integer NN`、`mapping_payload jsonb NULL` | 本人已发布 CSV 对象与列映射；待上传尚无对象/映射，外部无版本文件允许版本NULL |
| 同表 | `mode varchar(24) NN`、`duplicate_strategy varchar(24) NN`、`state varchar(24) NN`、`expires_at timestamptz NN` | mode 为 compare/direct_add；策略 skip/fill_empty/new；awaiting_upload/preview/confirmed/running/completed/partial/cancelled/failed/expired |
| 同表 | `preview_digest bytea NULL`、`total_rows bigint NULL`、`cursor_ordinal bigint NN DEFAULT 0`、`created_count,merged_count,skipped_count,failed_count bigint NN DEFAULT 0`、`job_id uuid NULL` | 上传完成并解析前总行数未知NULL；预览版本摘要、真实进度；计数非负且已知时不能超过总行数 |
| csv_import_rows / L+R | `batch_id uuid NN`、`ordinal bigint NN`、`row_schema_version integer NN`、`candidate_payload jsonb NN`、`row_digest bytea NN` | 一条逻辑记录，不按物理换行计行；载荷含映射后词字段、来源时间和非权威状态 |
| 同表 | `action varchar(24) NN`、`state varchar(24) NN`、`matched_item_id uuid NULL`、`expected_item_revision bigint NULL`、`result_item_id uuid NULL`、`error_code varchar(96) NULL` | 选定动作 new/skip/fill_empty/exclude；invalid/pending/committed/skipped/failed；只有有 read 才比较旧词 |

UK 行 `(scope,batch_id,ordinal)`；IX 批次 `(scope,state,created_at,id)`、行 `(scope,batch_id,state,ordinal)`。创建 awaiting_upload 批次、vocabulary_csv UploadIntent及容量预留同事务，无需创建Job占位；CHECK preview/confirmed/running/completed/partial 时对象、映射、摘要、总行数均非空。匹配 ID/revision 成对；direct_add 禁止读取/保存 matched 引用。确认与每批提交锁批次、目标条目和词本，按实际动作验证 create/read/update/本权限；行结果、游标、幂等记录同事务。已提交批次不可用过期重试再次插入；预览载荷按配置期限回收，结果摘要按业务留存配置保留。导出是获权条目快照/流，不另建“全库备份”聚合。

### 2.6 `photo_word_imports`、`photo_word_import_candidates`

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 约束/访问与生命周期 |
| --- | --- | --- |
| photo_word_imports / L+R | `file_object_id uuid NULL`、`job_id,ai_run_id uuid NULL`、`target_language varchar(35) NN`、`state varchar(24) NN`、`preview_generation bigint NN DEFAULT 1`、`expires_at timestamptz NN`、`confirmed_at timestamptz NULL` | P0 每批一个已验证照片；awaiting_upload/queued/recognizing/preview/confirmed/completed/failed/cancelled/unknown_outcome；IX `(scope,state,created_at,id)` |
| photo_word_import_candidates / L+R | `photo_import_id uuid NN`、`generation bigint NN`、`ordinal integer NN`、`payload_schema_version integer NN`、`payload jsonb NN`、`quality varchar(24) NN`、`action varchar(24) NN`、`matched_item_id uuid NULL`、`expected_item_revision bigint NULL`、`result_item_id uuid NULL`、`error_code varchar(96) NULL` | UK `(scope,photo_import_id,generation,ordinal)`；quality valid/needs_confirmation/invalid；action new/skip/fill_empty/exclude；确认重验同 CSV 权限组合，不把预览当收藏 |

创建 awaiting_upload 批次、vocabulary_photo UploadIntent与容量预留同事务；CHECK queued/recognizing/preview/confirmed/completed 时 file_object_id非空，确认识别调用后才创建Job。两表由 photo import 父锁及所涉条目/词本锁保护；识别经本人视觉模型/Pydantic AI，使用公共 attempt/usage，不建传统 OCR 回退。完成幂等；仅草稿/无引用图片可按期限清理，已收藏词快照独立保存。

## 3. 公共题库、AI 习题、作答与评分

### 3.1 `exercise_questions` — 不可变题目版本

公共列 L + S。本表物理 `id` 映射逻辑 ExerciseVersion；不是只保存当前题目的可变行。

共同父表 `exercise_question_roots` 使用 L + R，专有列为 `next_question_version bigint NN DEFAULT 1`。其 id 即下表 exercise_root_id；本表仅供根题版本分配与删除/引用共同锁，不含另一份题面。所有创建题目版本、来源绑定、冻结引用、作废和GC均锁此真实父行；已被历史引用的根行不删除。UK无额外业务键，IX `(scope,id)` 支撑作用域父行检查。

| 列 | PG类型 / NULL / 默认 | 含义 |
| --- | --- | --- |
| exercise_root_id, answer_lineage_id | uuid NN | 稳定根题及答案谱系，辅助记录跨会话绑定 |
| question_version | bigint NN | 根题版本；内容改动创建新行 |
| origin_kind | varchar(24) NN | extracted/generated/derived_from_mistake |
| question_type, interaction_type | varchar(32) NN | 业务题型与五类交互分别登记 |
| target_language | varchar(35) NN | 冻结目标语 |
| prompt_schema_version, presentation_schema_version | integer NN | 题型/展示 schema |
| prompt_payload, presentation_payload | jsonb NN | 题面/选项稳定ID/空位，**不含答案、隐藏稿或泄题 rubric** |
| question_digest | bytea NN | 题面及冻结依赖摘要 |
| publication_state | varchar(24) NN | draft/published/invalidated；发布后正文不可变 |
| published_at, invalidated_at | timestamptz NULL | 正式发布/作废时间 |
| invalidation_reason_code | varchar(96) NULL | 受控作废原因；不能静默删除历史 |

UK `(scope,exercise_root_id,question_version)`，IX `(scope,target_language,publication_state,created_at,id)`。公共教材绑定和 `exam_items.exercise_question_id` 引用此版本行；考试另外冻结分值/依据。题目发布锁来源/根题保护行并验证所有来源；已答题/冻结卷引用时保留版本。用户“删除 AI 错题”的具体 API/权限仍受 OPEN-10 阻断，本设计的 invalidated 支持既定内部作废/重放，不新增未确认人工改分流程。

### 3.2 `question_grading_bases`、`question_source_refs`、`question_assessment_targets`

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 约束/职责 |
| --- | --- | --- |
| question_grading_bases / L+S | `exercise_question_id uuid NN`、`basis_version bigint NN`、`schema_version integer NN`、`mode varchar(16) NN`、`answer_payload jsonb NULL`、`rubric_payload jsonb NN`、`normalization_payload jsonb NN`、`basis_origin varchar(24) NN`、`basis_digest bytea NN` | UK `(scope,exercise_question_id,basis_version)`；mode rule/ai；origin source_answer/user_correction/ai_reference；S精确记录答案区/人工修订/AI生成依据出处与必要快照；隐藏读取接口与题面分离 |
| 同表 | `quality_status varchar(16) NN`、`extraction_confidence numeric(5,4) NULL`、`confirmation_status varchar(24) NN`、`confirmed_by_user_id uuid NULL`、`confirmed_at timestamptz NULL`、`predecessor_basis_id uuid NULL`、`ai_run_id uuid NULL` | quality reliable/uncertain/invalid；confidence仅候选信息且0..1有限；confirmation candidate/confirmed/rejected/not_required，与来源类型独立；确认人/时间成对，确认与修订创建新不可变依据版本 |
| question_source_refs / L+S | `exercise_question_id uuid NN`、`ordinal integer NN`、`role varchar(24) NN` | UK `(scope,exercise_question_id,ordinal)`；IX `(scope,source_kind,source_resource_id)` 支撑删除引用检查；role context/target/mistake/basis；模型引用逐一校验 |
| question_assessment_targets / L | `exercise_question_id uuid NN`、`grading_basis_id uuid NN`、`scoring_item_key varchar(128) NN`、`collection_item_id uuid NN`、`learning_revision bigint NN`、`skill varchar(32) NN`、`allowed_assistance jsonb NN`、`schema_version integer NN` | UK `(scope,exercise_question_id,scoring_item_key,collection_item_id,learning_revision,skill)`；IX `(scope,collection_item_id,learning_revision)`；skill meaning_recognition/word_recall；只关联 kind=word |

依据与目标发布后不可变。rule必须有非空答案且quality=reliable、确认满足当前业务要求；低置信度/未确认抽取不能仅凭模型数字变为规则权威。ai_reference明确显示AI参考/AI评估，不伪称原卷答案；人工确认记录本人操作者并经相应校对动作授权，不提供人工改成绩入口。评分叶子 `scoring_item_key` 由应用分配并在版本内稳定；总分不自动创建所有单词的 targets。题目、依据、源与词条在共同锁内校验作用域/版本，目标删除后历史保留且不能产生新词条。

### 3.3 `exercise_selection_snapshots`、`exercise_selection_candidates`

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 含义 |
| --- | --- | --- |
| exercise_selection_snapshots / L+R | `target_language varchar(35) NN`、`schema_version integer NN`、`normalized_filter jsonb NN`、`generation_settings jsonb NN`、`model_config_ref jsonb NN` | 服务端规范化条件、题型/方向/题量/同源策略/难度与配置引用，不含秘密 |
| 同表 | `as_of timestamptz NN`、`timezone varchar(64) NN`、`window_start_at,window_end_at timestamptz NULL`、`expires_at timestamptz NN`、`authz_version bigint NN`、`fact_revision bigint NN` | 预览截止/时区/UTC窗口/事实版本；版本只是重验依据，不是权限凭证 |
| 同表 | `candidate_count,selected_count integer NN`、`selection_digest bytea NN`、`sampling_version varchar(64) NN`、`sampling_seed bytea NN`、`estimated_usage jsonb NULL` | 预览计数和冻结抽样；预计用量不写金额 |
| exercise_selection_candidates / L+S | `selection_id uuid NN`、`ordinal integer NN`、`candidate_key bytea NN`、`expected_resource_revision bigint NULL`、`expected_projection_revision bigint NULL`、`selected boolean NN`、`selection_reason varchar(64) NN`、`dependency_versions jsonb NN` | 顺序/去重/选择及排除原因；词本、收藏、教材、错题、诊断的实际受权来源 |

UK 候选 `(scope,selection_id,ordinal)` 和 `(scope,selection_id,candidate_key)`；IX 快照 `(scope,expires_at,id)`；IX 候选 `(scope,source_kind,source_resource_id)`。计数非负且 selected<=candidate；窗口全空或两端齐全且 start<end，expires>as_of。预览不需 Key、不创建 Job/证据；任何影响范围/设置的更改重建快照。无结果/不足不扩源。过期且未被计划引用的快照可回收。

### 3.4 `exercise_sets`、`exercise_set_items` — 确认计划与生成结果

计划与产出集原为一对一、同scope、同Job生命周期，合为exercise_sets；逻辑AiExercisePlan是该行确认后不可变字段组，plan_id映射本行id，集状态为另一组。确认时即创建generating集，尚无题目不冒充ready。保留独立选择快照与一对多候选，计划不重复复制一套来源行。

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 唯一/索引/生命周期 |
| --- | --- | --- |
| exercise_sets / L+R | `title text NN`、`target_language varchar(35) NN`、`state varchar(24) NN`、`requested_count integer NN`、`published_count integer NN DEFAULT 0`、`generation_report jsonb NN`、`schema_version integer NN` | IX `(scope,state,created_at,id)`；generating/ready/partial/failed；完成生成不代表完成学习 |
| 同表：冻结计划组 | `selection_id uuid NULL`、`selection_revision bigint NULL`、`selection_digest bytea NULL`、`generation_settings jsonb NULL`、`model_config_snapshot jsonb NULL`、`confirmed_at timestamptz NULL`、`job_id uuid NULL` | AI生成要求本组全有，非AI集全空；UK `(scope,job_id) WHERE job_id IS NOT NULL`；Job/集/Outbox同事务；计划组创建后不可改，状态R不改变计划含义 |
| exercise_set_items / L | `exercise_set_id uuid NN`、`exercise_question_id uuid NN`、`grading_basis_id uuid NULL`、`ordinal integer NN`、`max_score numeric(10,2) NN` | UK `(scope,exercise_set_id,ordinal)`；IX `(scope,exercise_question_id)`；max_score>0且有限；固定题序/当时可得依据，缺依据只允许保存作答待评 |

确认锁selection及全部选中来源并复核摘要，复制有限设置到计划组，来源直接引用该selection中selected=true的不可变候选。候选/快照内容创建后不可改，改条件创建新selection；到期只阻止新确认，任何已确认集/计划（含失败、重试和历史）引用期间都不得TTL删除其快照与候选。清理须先锁selection再复核反向引用，IX `(scope,selection_id) WHERE selection_id IS NOT NULL` 支撑检查。故不另建ai_exercise_plan_sources，也不把选源塞入集的大JSON。

允许用户显式再次生成创建不同集/Job，并可引用同一未过期selection；幂等请求仍只建一次。Worker读取固定candidate_key/版本/来源快照，不重跑动态筛选，逐调用阶段重验当前权限和删除状态；快照保留不授予访问已删原文。发布题目/依据/目标/集状态同一阶段事务，失败候选不伪装有效题。已开始会话保留必要题面。

### 3.5 `practice_sessions`、`practice_session_items`

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 约束/职责 |
| --- | --- | --- |
| practice_sessions / L+R | `exercise_set_id uuid NULL`、`target_language varchar(35) NN`、`state varchar(24) NN`、`started_at,completed_at,abandoned_at timestamptz NULL` | ready/in_progress/completed/abandoned；IX `(scope,state,created_at,id)`；开始已有教材题可不来自AI集；会话完成与评分完成分开 |
| practice_session_items / L+R | `practice_session_id uuid NN`、`exercise_question_id uuid NN`、`grading_basis_id uuid NULL`、`ordinal integer NN`、`max_score numeric(10,2) NN`、`submitted_attempt_id uuid NULL`、`state varchar(16) NN DEFAULT 'unanswered'` | UK `(scope,practice_session_id,ordinal)`；state unanswered/submitted/skipped；IX `(scope,exercise_question_id)`；max_score>0且有限；NULL为尚无可用依据，不阻断仅保存答案 |

锁会话和 session_item 后首次提交仅接受一次；跨端恢复读服务端已提交位置。重做建新会话/新 Attempt，历史答案不修改。未提交草稿只在当前账号页面，数据库不承诺普通练习离线合并。题目、依据、考试 `exam_items` 均引用本分册不可变版本。

### 3.6 `question_attempts` — 提交答案与单题评分聚合

公共列 L + R。不可变 answer；R/评分指针仅用于评分生命周期。

| 列 | PG类型 / NULL / 默认 | 含义 |
| --- | --- | --- |
| source_kind | varchar(16) NN | practice/exam |
| practice_session_item_id | uuid NULL | 普通练习题项 |
| exam_session_id, exam_answer_id | uuid NULL | 冻结考试场次/交卷答案 |
| exercise_question_id | uuid NN | 作答采用的冻结题目版本 |
| grading_basis_id | uuid NULL | 提交当时冻结的依据；无标准答案/稍后独立准备依据时NULL，不阻断交卷 |
| answer_schema_version | integer NN | 回答 schema |
| answer_payload | jsonb NN | 原答案；显式空答有类型化空值，不是网络失败 |
| accepted_at | timestamptz NN | 服务端接受时间，用于证据重放 |
| accepted_sequence | bigint NN | library 共同锁下分配的接受顺序（见下文） |
| elapsed_ms | bigint NULL | 获得的用时，非掌握依据 |
| answer_status | varchar(24) NN | answered/explicit_blank/dont_know |
| assistance_state | varchar(24) NN | none/hinted/revealed/training_only，提交时冻结 |
| grade_generation | bigint NN DEFAULT 0 | 普通单题评分代次，CHECK >=0 |
| active_grade_run_id, effective_grade_run_id | uuid NULL | 活动与有效成绩分别保存 |

CHECK：practice 时 session_item 非空且 exam 两列为空；exam 时 exam 两列非空且 practice 为空。UK `(scope,practice_session_item_id) WHERE practice_session_item_id IS NOT NULL`、`(scope,exam_answer_id) WHERE exam_answer_id IS NOT NULL`，IX `(scope,accepted_at,id)`。考试 Attempt 只在交卷锁定后创建，后续评分由整场 `exam_sessions` 的 run/generation/effective 指针控制，不按单题提前回流。

### 3.7 `library_learning_acceptance_counters`、`answer_exposures`

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 约束/职责 |
| --- | --- | --- |
| library_learning_acceptance_counters / L | `last_sequence bigint NN DEFAULT 0` | UK `(scope)`；只为提交/接受辅助动作分配单调序号，CHECK>=0，不是全库自增主键 |
| answer_exposures / L | `practice_session_item_id uuid NN`、`exercise_root_id,answer_lineage_id uuid NN`、`collection_item_id uuid NN`、`learning_revision bigint NN`、`exposure_kind varchar(16) NN`、`accepted_at timestamptz NN`、`accepted_sequence bigint NN` | kind hint/answer/feedback；UK `(scope,practice_session_item_id,collection_item_id,learning_revision,exposure_kind)`；IX `(scope,exercise_root_id,answer_lineage_id,collection_item_id,learning_revision,accepted_sequence)` |

提交和曝光共同先锁学习接受计数器，再锁会话/题项/目标，分配接受序号；按序号判断“先看答案后提交”，时间同值也无歧义。曝光只在服务接受请求后生效，不用前端点击时间。仅对有 question_assessment_targets 的词写目标曝光，普通题辅助另在 Attempt 冻结。独立新根题不继承曝光，反馈后订正标 training_only；未发生实际测验的查看/播放不写掌握证据。

### 3.8 `grading_runs`、`grading_results`

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 含义 |
| --- | --- | --- |
| grading_runs / L+R | `aggregate_kind varchar(16) NN`、`question_attempt_id,exam_session_id uuid NULL`、`generation bigint NN`、`state varchar(24) NN`、`active boolean NN DEFAULT true` | aggregate attempt/exam；queued/running/scored/needs_review/failed/cancelled/unknown_outcome；active 与 effective 独立 |
| 同表 | `job_id,ai_run_id uuid NULL`、`rule_version varchar(64) NN`、`input_digest bytea NN`、`input_media_fault_revision bigint NULL`、`reason_code varchar(96) NN`、`published_at timestamptz NULL` | 考试冻结必要媒体故障版本；初评/重评原因；重试沿用 run |
| 同表 | `score,max_score numeric(10,2) NULL`、`required_item_count integer NN`、`completed_item_count integer NN DEFAULT 0`、`lease_fence bigint NN DEFAULT 0` | 总分仅程序计算；未完整可靠评分不写正式零分 |
| grading_results / L | `grading_run_id,question_attempt_id,exercise_question_id uuid NN`、`grading_basis_id uuid NULL`、`scoring_item_key varchar(128) NN`、`mode varchar(16) NN`、`state varchar(24) NN` | 评分叶子 rule/ai，pending/scored/needs_review/failed/unknown_outcome；未准备依据可NULL，scored必须有精确不可变basis |
| 同表 | `score numeric(10,2) NULL`、`max_score numeric(10,2) NN`、`verdict varchar(24) NULL`、`schema_version integer NN`、`feedback_payload jsonb NULL`、`normalization_version varchar(64) NN`、`external_call_attempt_id uuid NULL` | verdict correct/partial/incorrect；反馈含维度/受控错误标签/片段/参考及不确定性，不能从题面接口取出 |

run CHECK：aggregate 只绑定一种父；考试有 media fault revision，普通为空。分别 UK `(scope,question_attempt_id,generation)` 和 `(scope,exam_session_id,generation)`（对应非空谓词）；分别部分 UK 父 ID `WHERE active` 保证一个活动 run。result UK `(scope,grading_run_id,question_attempt_id,scoring_item_key)`；IX `(scope,question_attempt_id,grading_run_id)`。分数非负、有限且不超满分；run 两分值同时为空或都有，scored 才有 verdict/score；其他状态得分 NULL。不能用缺失评分补零。

无依据/缺Key时先保留已提交Attempt与待评状态，不创建虚假basis或零分；后续明确请求评分，参考依据仅基于冻结题面独立准备，不使用本次考生答案生成标准。新basis在该run的result绑定后冻结，保留Attempt原始可空依据；首次有原冻结basis则使用它，纠正依据只允许新basis+显式新代次重评。scored结果要求basis非空、可靠性/确认条件成立，needs_review不能发布effective。

发布先锁普通 Attempt 或 ExamSession，再锁 run；校验 generation/active 指针/fence、所有必需评分项和考试媒体故障 revision。切 effective、替换贡献、插入可靠错误 occurrence、Outbox 在同一事务。重评失败保留旧 effective；旧 run 迟到仅历史。考试所有叶子均完成且无 needs_review 才整场发布，单题结果不能先进入掌握/错题。

### 3.9 评分争议字段（位于 grading_results）

P0每个评分结果只有一次“我认为答对”反馈，没有独立复核处理流程。grading_results增加 `review_requested_at timestamptz NULL`、`review_reason text NULL`；CHECK未反馈时reason为空。IX `(scope,review_requested_at,id) WHERE review_requested_at IS NOT NULL` 支撑本人反馈查询/争议计数。逻辑review_request_id映射grading_results.id，状态由非空时间派生open，不预建status/revision供未知未来工作流。

反馈共锁所属Attempt/ExamSession→Run→Result，只能对已发布且本人可读的结果首次写入，并维护updated_at；重试返回原反馈，同一结果不能覆盖原因。评分字段和effective保持原义，争议不改成绩/证据，也不触发模型调用。需要多次申诉或独立处理历史时另行立项迁移，当前不建grading_review_requests。

## 4. 学习证据、错题与诊断

### 4.1 `learner_contributions`、`effective_learning_evidence`

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 约束/职责 |
| --- | --- | --- |
| learner_contributions / L+R | `source_kind varchar(16) NN`、`source_aggregate_id uuid NN`、`question_attempt_id uuid NN`、`scoring_item_key varchar(128) NN`、`effective_grade_run_id,grading_result_id uuid NN`、`contribution_revision bigint NN DEFAULT 1`、`state varchar(16) NN`、`accepted_at timestamptz NN`、`accepted_sequence bigint NN` | source attempt/exam；UK `(scope,source_kind,source_aggregate_id,question_attempt_id,scoring_item_key)`；state effective/invalidated；按父有效评分事务替换，不追加分数 |
| effective_learning_evidence / L+R | `question_attempt_id uuid NN`、`scoring_item_key varchar(128) NN`、`assessment_target_id,collection_item_id uuid NN`、`learning_revision bigint NN`、`skill varchar(32) NN`、`grading_result_id,grade_run_id,learner_contribution_id uuid NN` | UK `(scope,question_attempt_id,scoring_item_key,collection_item_id,learning_revision,skill)`，稳定业务键不含新评分 ID |
| 同表 | `exercise_root_id,answer_lineage_id uuid NN`、`exercise_set_id uuid NULL`、`accepted_at timestamptz NN`、`accepted_sequence bigint NN`、`outcome varchar(24) NN`、`assistance_state varchar(24) NN`、`state varchar(16) NN`、`evidence_revision bigint NN` | outcome correct/partial/incorrect；state effective/invalidated；IX `(scope,collection_item_id,learning_revision,accepted_sequence,id)` 支撑有序重放 |

projection 消费锁目标词/学习状态，复核当前 effective run、贡献版本和 learning_revision，重复事件 upsert 同键。旧证据事实仍可从不可变 Attempt/GradeResult 追溯；本表是可替换的当前证据投影。training_only 保留作答但不形成独立成功组；accepted_at+接受序号稳定，不能按消息抵达时间重放。

### 4.2 `collection_word_learning_states`

公共列 L + R。`collection_item_id uuid NN`、`learning_revision bigint NN`、`mastery_state varchar(24) NN DEFAULT 'new'`、`assessment_status varchar(24) NN DEFAULT 'ready'`、`policy_version varchar(64) NN`、`evidence_revision bigint NN DEFAULT 0`、`reason_schema_version integer NN`、`reason_payload jsonb NN`、`last_effective_attempt_at timestamptz NULL`、`effective_error_count bigint NN DEFAULT 0`、`rebuilt_at timestamptz NULL`。

UK `(scope,collection_item_id,learning_revision)`；IX `(scope,mastery_state,last_effective_attempt_at,collection_item_id)`，IX `(scope,effective_error_count,collection_item_id)` 支撑筛选/常错排序。mastery 为 new/learning/mastered/needs_practice；assessment 为 ready/pending/rebuilding/needs_content。状态只由服务端按[策略 v2](vocabulary-learning.md)投影；首次满足三组独立窗口后的保持、负证据与重评重放遵循专题。旧 learning_revision 状态保留作历史，不直接赋给新内容。策略参数不作为用户设置，也没有 due/SRS/每日额度字段。

### 4.3 `mistake_occurrences`、`mistake_projections`

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 含义 |
| --- | --- | --- |
| mistake_occurrences / L+S | `question_attempt_id,grading_result_id,grade_run_id,exercise_question_id,exercise_root_id uuid NN`、`exam_session_id uuid NULL`、`scoring_item_key varchar(128) NN`、`knowledge_key varchar(128) NN`、`target_language varchar(35) NN`、`question_type varchar(32) NN` | 每个已经 effective 的可靠错误叶子/考察点；快照不能越权恢复原材料 |
| 同表 | `verdict varchar(16) NN`、`occurred_at timestamptz NN`、`accepted_sequence bigint NN`、`snapshot_schema_version integer NN`、`question_snapshot,answer_snapshot,feedback_snapshot jsonb NN` | verdict partial/incorrect；不可变历史，包括后来被重评纠正的旧错误 |
| mistake_projections / L+R | `exercise_root_id uuid NN`、`scoring_item_key,knowledge_key varchar(128) NN`、`target_language varchar(35) NN`、`state varchar(24) NN`、`latest_occurrence_id uuid NULL`、`latest_contribution_id uuid NULL`、`occurrence_count bigint NN DEFAULT 0`、`fact_revision bigint NN`、`last_occurred_at timestamptz NULL`、`reason_code varchar(96) NN` | 按根题/考察点的当前投影；unresolved/improved/invalidated/pending_rebuild |
| occurrence同表：本人收藏组 | `favorited_at,favorite_updated_at timestamptz NULL`、`favorite_notes text NULL`、`favorite_revision bigint NN DEFAULT 1` | 两时间同空同有，未收藏时notes为空；revision>=1；独立于不可变错误事实和projection状态 |

occurrence UK `(scope,grading_result_id,knowledge_key)`，IX `(scope,target_language,occurred_at,id)`、`(scope,exercise_root_id,knowledge_key,occurred_at,id)`；projection UK `(scope,exercise_root_id,scoring_item_key,knowledge_key)`，IX `(scope,target_language,state,last_occurred_at,id)`；本人收藏IX `(scope,favorited_at,id) WHERE favorited_at IS NOT NULL`。若一评分叶子有多个确定考察点，分别记录并在题目维度去重计数；模型不能用任意重复标签放大权重。

一条occurrence本就属于一个用户、至多有一个本人收藏，不另建mistake_favorites。逻辑收藏id映射occurrence.id；收藏API的创建/更新时间来自favorited_at/favorite_updated_at，不能用错误发生时间。收藏/改笔记/取消在occurrence锁内比较favorite_revision，仅更新收藏列及公共updated_at；取消清两时间/笔记并递增版本，再收藏保留同一ID但产生新的收藏时间。重评只更新projection，不覆盖收藏组，允许收藏improved/invalidated历史。错误快照字段创建后仍不可改。

只在 effective 发布事务插入 occurrence；重评替换贡献后重算 projection，保留旧 occurrence及其收藏组。invalidated 历史默认不作当前薄弱点，用户显式选择其收藏时也不能把旧错误答案当真值。删原题/材料保留最小复盘快照，回跳另验当前来源权限；公开读取不会返回他人答案或私人笔记。

### 4.4 `learner_language_profiles`、`diagnosis_reports`、`diagnosis_report_evidence_refs`

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 约束/职责 |
| --- | --- | --- |
| learner_language_profiles / L+R | `target_language varchar(35) NN`、`fact_revision bigint NN`、`data_as_of timestamptz NN`、`schema_version integer NN`、`statistics_payload jsonb NN` | UK `(scope,target_language)`；可重建有证据统计，未知/数据不足不填零能力 |
| diagnosis_reports / L | `target_language,explanation_language varchar(35) NN`、`timezone varchar(64) NN`、`window_start_at,window_end_at,data_as_of timestamptz NN`、`fact_revision bigint NN`、`scope_material_id uuid NULL`、`snapshot_schema_version integer NN`、`statistics_snapshot jsonb NN`、`result_schema_version integer NN`、`result_payload jsonb NN`、`ai_run_id uuid NN` | IX `(scope,target_language,data_as_of,id)`；start<end；保存已提交统计/证据，题目数和待评/争议分开；报告正文不可变 |
| diagnosis_report_evidence_refs / L+S | `diagnosis_report_id uuid NN`、`ordinal integer NN`、`fact_revision bigint NN`、`evidence_role varchar(32) NN` | UK `(scope,diagnosis_report_id,ordinal)`；IX `(scope,source_kind,source_resource_id)`；报告每个结论/动作引用有权事实 |

生成诊断显式授权且使用本人 Key；模型只解释程序统计。事实版本变化时旧报告显示“数据已更新”，不自动重调模型。建议存受控动作及类型化引用（在 result schema 内），点击再授权；不存任意可执行 URL。照片/查询批改卡不进入这些正式贡献。

## 5. 查询、内部会话与结构化结果

DESIGN22复用以下既有结构，不新增物理表。`agent_thread_messages.message_payload`存版本化QueryInput及ContextPlan，`ai_runs.input_refs/generation_config`冻结实际ContextSnapshot/模型预算；`explanations`的上下文快照和`cards.source_refs/payload`保存有界来源及结果上下文引用，详细字段见[上下文契约](../contracts/query-context.md)。`learning_lookup_states/learning_generation_slots`使用新版查阅/严格键。音频资产及全局声音profile的合成配置载荷冻结adapter/API契约及ResolvedSynthesisSpec，沿[适配器](tts-adapters.md)校验，不复制一套查询缓存表或每模型音频表。

### 5.1 `agent_threads`、`agent_thread_messages`、`agent_message_attachments`

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 含义 |
| --- | --- | --- |
| agent_threads / L+R | `mode varchar(16) NN`、`state varchar(16) NN DEFAULT 'active'`、`active_run_id uuid NULL`、`turn_generation bigint NN DEFAULT 0`、`delete_generation bigint NN DEFAULT 0`、`deleted_at timestamptz NULL` | mode query/contextual；state active/deleted；内部功能上下文，不对应聊天页或会话管理产品 |
| agent_thread_messages / L | `agent_thread_id uuid NN`、`turn_generation bigint NN`、`ordinal integer NN`、`role varchar(16) NN`、`state varchar(24) NN`、`text_content text NULL`、`attachment_count integer NN DEFAULT 0` | role user/assistant/tool；submitted/committed/interrupted/rejected；文本与附件至少一项有内容（工具型按其 schema） |
| 同表 | `explanation_language varchar(35) NN`、`target_language varchar(35) NULL`、`inferred_query_task varchar(32) NULL`、`ai_run_id uuid NULL`、`sdk_version varchar(64) NN`、`serialization_version varchar(64) NN`、`message_payload jsonb NULL` | 推断任务由服务端写入，发送输入不要求类型；SDK版本支持确定性历史读取 |
| agent_message_attachments / L+R | `agent_thread_id uuid NN`、`agent_message_id uuid NULL`、`file_object_id,upload_intent_id uuid NN`、`asset_version bigint NN`、`ordinal integer NULL`、`state varchar(16) NN`、`expires_at timestamptz NULL` | draft/bound/removed；草稿可空 message/ordinal，bound 必须齐全；query_image 专用验证静态图；R供API image_refs.revision核对 |

UK message `(scope,agent_thread_id,turn_generation,ordinal)`；IX thread `(scope,mode,updated_at,id)`、message `(scope,agent_thread_id,id)`；attachment UK `(scope,file_object_id)`、`(scope,agent_message_id,ordinal) WHERE agent_message_id IS NOT NULL`，IX `(scope,agent_thread_id,state)`、`(expires_at,id) WHERE state='draft'`。提交/删除锁同一 thread 并比较代次，发送事务冻结文字及有序附件；幂等摘要含附件 ID/版本/顺序与模型配置，不含事后推断任务。图片真实解码、限像素、规范方向、去元数据/重编码与不可变 FileObject 发布由上传服务完成；绑定期间不得普通 TTL 清理。

删除 thread 推进代次，迟到上传/模型不复活；独立收藏/书内解释与音频结果按各自引用保留。消息载荷不含 Key、Token 或带凭据 SDK 对象。图片读取每次本人 agent.read 且 private/no-store；收藏卡片不自动复制原图。

### 5.2 `cards`

公共列 L。`agent_message_id uuid NULL`、`ai_run_id uuid NN`、`card_kind varchar(24) NN`、`card_revision bigint NN`、`schema_version integer NN`、`payload jsonb NN`、`serialized_size_bytes bigint NN`、`target_language varchar(35) NULL`、`explanation_language varchar(35) NN`、`source_schema_version integer NN`、`source_refs jsonb NN`、`ordinal integer NN`、`published_at timestamptz NN`。

UK `(scope,ai_run_id,ordinal,card_revision)`；IX `(scope,agent_message_id,ordinal)`。kind word/sentence/grammar/exercise，phrase 为 WordCard 子型。仅完整 schema/出处/业务校验通过后插入不可变卡；半截流结果只在运行状态，不存可收藏 card。source_refs 是有界类型化来源集合，每项由服务验证；载荷结构只由[卡片契约](../modules/ai-speech.md#31-类型化卡片与流式呈现)维护。

收藏按 card id/revision 重取完整服务端载荷。无明确目标语时的用户确认只写收藏目标语，不改原卡；已有明确目标语禁止覆盖。ExerciseCard 保存订正/依据/不确定性，不自动建立 Attempt/MistakeOccurrence，不能推断分数/掌握。已收藏卡片按独立快照保留。

### 5.3 `ai_feedback`

公共列 L + R。`result_kind varchar(16) NN`、`result_id uuid NN`、`result_version bigint NN`、`verdict varchar(16) NN`、`comment text NULL`。UK `(scope,result_kind,result_id,result_version)`；verdict useful/inaccurate，kind explanation/card；IX `(scope,created_at,id)`。服务按 discriminator 查对应本人结果并锁其父；反馈不改卡片、成绩或掌握，不触发自动重生成。

## 6. 解释、私有 TTS 与全局标准词音

### 6.1 `explanations`、`source_result_bindings`

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 含义 |
| --- | --- | --- |
| explanations / L | `ai_run_id uuid NN`、`task_kind varchar(32) NN`、`source_language,explanation_language varchar(35) NN`、`detail_level varchar(24) NN`、`schema_version integer NN`、`result_payload jsonb NN`、`context_snapshot jsonb NN`、`serialized_size_bytes bigint NN`、`context_digest,strict_key_digest bytea NN`、`generation_config jsonb NN`、`quality varchar(24) NN`、`published_at timestamptz NN` | 不可变完整解释与真实生成配置/Prompt/上下文协议版本；task 词/短语/句/摘录等受控枚举；生成例与原文明确分开 |
| source_result_bindings / L+S | `lookup_state_id uuid NN`、`result_kind varchar(16) NN`、`result_id uuid NN`、`result_version bigint NN`、`binding_digest bytea NN`、`dependency_versions jsonb NN`、`released_at timestamptz NULL` | kind explanation/card/audio；持久授权来源引用，不是浏览埋点 |
| binding同表：材料查阅索引列 | `material_id,material_revision_id uuid NULL`、`entry_kind varchar(24) NULL`、`language varchar(35) NULL`、`surface_text text NULL`、`lemma text NULL`、`chapter_or_lesson_id uuid NULL` | 仅合法材料来源必填前五列，其他来源全空；locator复用S.source_locator及其内嵌locator_schema_version，不用S.source_schema_version冒充定位协议版本；父材料/版本/章节与S出处逐项校验 |

explanation UK `(scope,ai_run_id)`，IX `(scope,strict_key_digest,created_at,id)`；binding UK `(scope,binding_digest)`，IX `(scope,result_kind,result_id)` 与 `(scope,source_kind,source_resource_id)`；binding增加IX `(scope,material_id,material_revision_id,entry_kind,created_at,id)` 与 `(scope,material_id,chapter_or_lesson_id,created_at,id)`，均WHERE material_id IS NOT NULL AND released_at IS NULL。同 lemma 不同语境不共享解释；成功发布事务写历史binding，只有当前代次可切lookup有效指针。MaterialLearningIndex改为作用域查询投影：从未released且有材料列的binding连接learning_lookup_states，仅选result_kind/id/version与当前effective一致的绑定；lookup端也核对scope，旧成功结果仍保留绑定但不进入当前索引。不建material_learning_indexes实体表或独立投影Worker。原书删除只解除书属引用，独立收藏/合法历史仍保留。

### 6.2 `learning_lookup_states`、`learning_generation_slots`

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 含义 |
| --- | --- | --- |
| learning_lookup_states / L+R | `artifact_kind varchar(16) NN`、`lookup_key_digest bytea NN`、`key_schema_version integer NN`、`lookup_identity jsonb NN`、`lookup_generation bigint NN DEFAULT 0`、`selected_strict_key_digest bytea NULL`、`active_run_id uuid NULL`、`effective_result_id uuid NULL`、`effective_result_version bigint NULL` | 跨模型/Prompt配置的当前选用与有效指针；artifact explanation/card/audio；旧有效版在新任务完成前保留 |
| learning_generation_slots / L+R | `artifact_kind varchar(16) NN`、`strict_key_digest bytea NN`、`key_schema_version integer NN`、`active_run_id uuid NULL`、`execution_generation bigint NN DEFAULT 0`、`lease_owner varchar(128) NULL`、`lease_expires_at timestamptz NULL`、`fence bigint NN DEFAULT 0`、`state varchar(24) NN DEFAULT 'idle'` | idle/occupied/unknown；仅合并同配置调用，不决定当前解释指针 |

UK lookup `(scope,artifact_kind,lookup_key_digest)`、slot `(scope,artifact_kind,strict_key_digest)`；IX slot `(lease_expires_at,id) WHERE state='occupied'`。effective ID/version 全空或全有；租约 owner/expires 全空或全有；代次/fence>=0。锁顺序 lookup→slot→run；发布同时比较 lookup_generation/selected key/active run/fence。Redis 锁失效不放行第二有效发布者；unknown 超时不等于可安全重调供应商。

键内容唯一维护在[缓存匹配契约](learning-cache.md#4-命中规则与版本)：lookup 不含 Key/默认模型/Prompt；strict 包含真实语义输入/上下文/生成配置/协议。无材料手工输入包含全文+显式上下文的服务器摘要，不能把 NULL material 的查询合为一项。只读 resolve 不建 Job、不写学习记录、不用缓存缺失驱动模型调用。

### 6.3 `audio_assets`、`audio_asset_segments`、`playback_manifests`、`playback_manifest_segments`

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 含义 |
| --- | --- | --- |
| audio_assets / L | `strict_key_digest bytea NN`、`key_schema_version integer NN`、`synthesis_config jsonb NN`、`source_schema_version integer NN`、`source_identity jsonb NN`、`ai_run_id uuid NN`、`storage_reservation_id uuid NN`、`state varchar(24) NN`、`generation bigint NN`、`published_at timestamptz NULL` | 私有受控合成身份/声音/模型/输出配置与来源；容量引用身份分册 user_storage_reservations；queued/generating/ready/failed/cancelled/unknown_outcome/broken |
| audio_asset_segments / L | `audio_asset_id uuid NN`、`ordinal integer NN`、`file_object_id uuid NULL`、`state varchar(24) NN`、`text_start,text_end integer NN`、`source_spans jsonb NN`、`media_type varchar(64) NULL`、`codec varchar(32) NULL`、`sample_rate_hz,channels,bit_depth integer NULL`、`duration_ms,size_bytes bigint NULL`、`content_digest bytea NULL`、`timing_schema_version integer NN`、`timing_map jsonb NULL` | 真实独立音频或验证过的时间映射；ready 必须有对象/格式/长度/摘要；text_end>text_start>=0 |
| playback_manifests / L | `schema_version integer NN`、`purpose varchar(24) NN`、`manifest_version bigint NN`、`state varchar(16) NN`、`source_identity jsonb NN`、`source_schema_version integer NN`、`config_digest bytea NN`、`published_at timestamptz NULL` | purpose reading/collection/card/exam_listening；building/ready/broken；清单可引用跨入口复用的同本人资产 |
| playback_manifest_segments / L | `playback_manifest_id,audio_segment_id uuid NN`、`ordinal integer NN`、`source_spans jsonb NN`、`schema_version integer NN` | UK `(scope,playback_manifest_id,ordinal)`；IX `(scope,audio_segment_id)`；清单顺序与出处固定 |

asset UK `(scope,strict_key_digest,generation)`，IX `(scope,strict_key_digest,state)`；segment UK `(scope,audio_asset_id,ordinal)`，IX `(scope,file_object_id) WHERE file_object_id IS NOT NULL`；manifest IX `(scope,purpose,created_at,id)`。ready 前对象真实解码/校验；缺失/损坏标 broken，不自动再合成。成功完整片段自动保留，未完成片段不能假称整段已缓存；配置信息内含分段方案版本。signature URL、播放器倍速不入合成身份。

试卷 AudioBinding 引用本人的 audio asset/manifest；`purpose=exam_listening` 只通过场次 PlayAttempt 在线计次路径消费，禁止通用离线完整下载。资产允许同本人等价输入复用，但合法输入必须由 SynthesisSpec、脚本/人工绑定/代次验证，不能把同文本的未确认稿直接命中当前试卷。正常私有解释/TTS与正在发布/被引用资产不按 TTL/LRU 删除。

### 6.4 `global_word_entries`、`global_voice_profiles`、`global_voice_profile_versions`

公共列 B，全部为 `system_catalog`，独立 CatalogScope/维护入口，不带 NULL owner 假装私有通配。

| 表 | 专有列（类型 / 空值 / 默认） | 约束/职责 |
| --- | --- | --- |
| global_word_entries | `catalog_source varchar(128) NN`、`catalog_version varchar(64) NN`、`entry_key varchar(128) NN`、`language varchar(35) NN`、`dialect varchar(35) NN`、`surface_form text NN`、`pronunciation_variant varchar(128) NN`、`controlled_input text NN`、`state varchar(16) NN` | UK `(catalog_source,catalog_version,language,dialect,entry_key,pronunciation_variant)`；IX `(language,surface_form,state)`；active/quarantined/retired；仅验证公共词表/读音，不接收用户“公共”声明 |
| global_voice_profiles | R；`code varchar(96) NN`、`language varchar(35) NN`、`display_name text NN`、`current_version_id uuid NULL`、`is_default boolean NN DEFAULT false`、`state varchar(16) NN` | UK `(code)`，部分UK `(language) WHERE is_default`；IX `(language,state,code)`；draft/published/retired；CHECK默认必须published，published必须有current_version；当前指针及语种默认由目录维护锁发布 |
| global_voice_profile_versions | `profile_id uuid NN`、`profile_revision bigint NN`、`provider varchar(32) NN`、`model_id varchar(256) NN`、`model_revision varchar(128) NULL`、`voice_id varchar(128) NN`、`schema_version integer NN`、`synthesis_parameters jsonb NN`、`prompt_version,normalization_version varchar(64) NN`、`config_digest bytea NN`、`published_at timestamptz NN` | UK `(profile_id,profile_revision)`；不可变真实合成配置；少量标准profile范围待阶段3实测 |

dialect 明确无区域差异时保存经注册的语言默认代码，不能任意空字符串。profile 版本中的 model_id/voice_id 是供应商字符串标识，不是 UUID；发布时依据身份分册 model_catalog_entries/voice_catalog_entries 的已验证能力核对并冻结真实配置，目录下架不改写历史音频元数据。标准词音输入不含私人备注/姓名/上下文/例句；不能匹配受控词条、定制读音或短语整句均走私有路径。词表许可/语种/profile范围仍待验证，设计本身不代表发音质量已验收。

### 6.5 `global_word_audios`、`global_word_lookup_states`、`global_word_generation_slots`

公共列 B，`system_catalog`；目录发布/GC共用 lookup/profile/词条保护行。公共 ready 资产不保存贡献者/收藏/材料引用。

| 表 | 专有列（类型 / 空值 / 默认） | 含义 |
| --- | --- | --- |
| global_word_audios | `word_entry_id,profile_version_id uuid NN`、`strict_key_digest bytea NN`、`generation bigint NN`、`bucket_name varchar(63) NN`、`object_key text NN`、`object_version varchar(256) NULL`、`content_digest bytea NN`、`media_type varchar(64) NN`、`codec varchar(32) NN`、`sample_rate_hz,channels integer NN`、`duration_ms,size_bytes bigint NN`、`validation_version varchar(64) NN`、`validated_at timestamptz NN`、`state varchar(16) NN` | ready/broken/quarantined/retired；对象位于独立公共目录前缀，不能引用私有 FileObject 改标共享 |
| global_word_lookup_states | R；`word_entry_id,profile_id uuid NN`、`lookup_generation bigint NN DEFAULT 0`、`selected_profile_version_id uuid NN`、`effective_audio_id uuid NULL`、`active_slot_id uuid NULL` | 稳定查阅身份跨profile修订维持当前指针；旧结果不覆盖新选择 |
| global_word_generation_slots | R；`word_entry_id,profile_version_id uuid NN`、`strict_key_digest bytea NN`、`producer_job_id uuid NULL`、`producer_run_id uuid NULL`、`global_storage_reservation_id uuid NULL`、`generation bigint NN DEFAULT 0`、`fence bigint NN DEFAULT 0`、`lease_owner varchar(128) NULL`、`lease_expires_at timestamptz NULL`、`state varchar(24) NN DEFAULT 'idle'` | 内部租约映射关联私人生产Job及身份分册共享容量预留，普通目录DTO绝不返回；idle/occupied/unknown |

UK audio `(strict_key_digest,generation)`；UK lookup `(word_entry_id,profile_id)`；UK slot `(strict_key_digest)`；IX audio `(word_entry_id,profile_version_id,state)`，IX slot `(lease_expires_at,id) WHERE state='occupied'`。producer job/run成对；租约字段成对；sample_rate/channels/size/duration>0。相同 strict 的 ready 不由用户强制替换；发现发音问题走固定目录隔离/修复流程，无自动供应商调用。

全局占用新生成前验证实际发起人的本人Key/权限/容量，Job/AiRun/attempt/用量仍为其私有记录。等待者只能拿本人等待引用，不能读取/取消生产Job；取消、失败、撤权、unknown后不自动换用等待者Key。ready目录引用独立于贡献者/收藏，删任何私人条目不删除公共成品。元数据API不返回生产者、首次用户生成时间或引用人数。

### 6.6 收藏词音字段与 `speech_requests`

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 约束/职责 |
| --- | --- | --- |
| collection_items同表：标准词音组 | `word_audio_learning_revision bigint NULL`、`word_audio_entry_id,word_audio_profile_id,word_audio_profile_version_id uuid NULL`、`word_audio_id uuid NULL`、`word_audio_selection_generation bigint NN DEFAULT 0` | 前四列全空或全有，非word必须全空且audio为空；audio非空需有完整选择；generation>=0；IX `(word_audio_id) WHERE word_audio_id IS NOT NULL` 供固定目录GC |
| speech_requests / L+R | `asset_kind varchar(16) NN`、`source_kind varchar(24) NN`、`source_resource_id uuid NN`、`source_version bigint NN`、`request_generation bigint NN`、`state varchar(24) NN`、`audio_asset_id,global_word_lookup_id,global_audio_id,job_id uuid NULL`、`requested_at timestamptz NN` | private/global_word；waiting/ready/missing/failed/cancelled；UK `(scope,source_kind,source_resource_id,request_generation)`；IX `(scope,state,created_at,id)` |

收藏标准词音原是每条collection唯一附属，不另建collection_word_audio_refs。根条目锁内验证本人word/learning_revision及公共词条/profile，改读音/选择推进word_audio_selection_generation；实质词内容变化清旧绑定并推进代次。异步完成按冻结learning_revision与selection_generation更新audio指针，只更新本字段组及updated_at，不能覆盖笔记/归本/内容。用户修改词音选择使用条目R，异步发布不推进供表单使用的R；返回DTO的词音代次单独标识。条目删除解除当前选用，历史请求仍保留原引用；共享成品不随删词删除。

speech 请求形状 CHECK：private 禁用全局列；global_word 禁用 private audio 列；等待他人生产时 job_id 为空，只有本人实际发起的job可关联。客户端读媒体必须同时验证本人来源版本/选用关系和实际资产一致，知道公共 audio id 不授予任意播放权。新个人引用只由已有授权写动作保存，只读 resolve 不写学习事实。

### 6.7 调用前容量预留

容量表唯一维护在[账号分册的技术限制与容量](database-identity.md)：`user_storage_states/user_storage_reservations` 按本人隔离，`global_storage_states/global_storage_reservations` 只由共享目录服务访问。本分册不重复建同名表。生成受理先取得容量根锁，在创建Job/Outbox同一事务写预留；音频资产/阶段使用预留ID，多个输出按同一预留汇总结算一次。上传可在无Job时以 upload_intent 作为预留目标。

private 按本人、global_word 实例只计一份；预留不取代文件/引用事实。PG内完整卡片/解释以 serialized_size_bytes 保存按已登记输出schema确定性UTF-8序列化得到的逻辑内容字节，非PG页面占用；同一结果被多个来源引用不重复计量。其他PG模型成品（题目/诊断等）由其schema的确定性序列化长度进入容量账本，迁移字典须登记计量范围，不能只统计MinIO。过期仅在证明无有效租约/在途安全落盘后释放，unknown不自动退占用。超容量在调用前拒绝，不淘汰仍有引用的成功结果；跨容量根锁序遵循主册，所有新生成入口一致。

## 7. 任务、AI 运行、外部调用与可靠事件

### 7.1 `jobs`、`job_stages`

公共列均 UO + R；私有 Job 可用于不在 library 内的 Key 测试，library 可空，不能用 NULL扩大访问范围。

| 表 | 专有列（类型 / 空值 / 默认） | 含义 |
| --- | --- | --- |
| jobs | `library_id uuid NULL`、`actor_user_id uuid NN`、`audience varchar(16) NN`、`operation_kind varchar(64) NN`、`operation_id,request_id uuid NN`、`state varchar(24) NN DEFAULT 'queued'` | actor/owner由认证受理上下文绑定，client私有调用不允许另指他人 |
| 同表 | `input_schema_version integer NN`、`input_refs jsonb NN`、`input_digest bytea NN`、`required_permissions jsonb NN`、`invocation_intent jsonb NN`、`limit_snapshot jsonb NN`、`credential_id uuid NULL` | 持久输入/依赖版本/明确模型意图/统一总上限；权限快照不能当当前许可 |
| 同表 | `generation bigint NN DEFAULT 1`、`progress_seq bigint NN DEFAULT 0`、`progress_stage varchar(64) NULL`、`progress_completed,progress_total bigint NULL`、`attempt_count integer NN DEFAULT 0`、`max_attempts integer NN`、`not_before timestamptz NN` | 已提交进度快照和WebSocket恢复序号；进度已完成<=总数，两计数齐全或为空 |
| 同表 | `lease_owner varchar(128) NULL`、`lease_expires_at timestamptz NULL`、`heartbeat_at timestamptz NULL`、`fence bigint NN DEFAULT 0`、`cancel_requested_at,finished_at timestamptz NULL`、`error_code varchar(96) NULL` | Worker租约/fence与取消；state queued/running/retry_wait/blocked/succeeded/failed/cancel_requested/cancelled |
| job_stages | `job_id uuid NN`、`job_generation bigint NN`、`stage_key varchar(96) NN`、`stage_generation bigint NN DEFAULT 1`、`state varchar(24) NN`、`input_digest bytea NN`、`result_schema_version integer NN`、`result_refs jsonb NULL`、`fence bigint NN DEFAULT 0`、`started_at,finished_at timestamptz NULL`、`error_code varchar(96) NULL` | pending/running/committed/failed/blocked/cancelled；保存已提交业务阶段，不能把半轮SDK历史当恢复点 |

Job IX `(owner,state,created_at,id)`、`(state,not_before,id) WHERE state IN ('queued','retry_wait')`、`(lease_expires_at,id) WHERE state='running'`；stage UK `(owner,job_id,job_generation,stage_key,stage_generation)`；IX `(owner,job_id,state)`。max_attempts>0且attempt_count<=max；租约字段组合校验。stage提交锁Job并核对owner/library/generation/fence、当前权限/来源及取消。管理入口仅获权元数据和非模型阶段重投；不得用管理身份继续私人模型调用。

### 7.2 `ai_runs`

公共列 UO + R。`library_id,job_id,agent_thread_id uuid NULL`、`operation_id,request_id uuid NN`、`operation_kind varchar(64) NN`、`state varchar(24) NN`、`provider varchar(32) NN`、`model_id varchar(256) NN`、`model_revision varchar(128) NULL`、`credential_id uuid NN`、`credential_version bigint NN`、`sdk_version,prompt_version,context_version varchar(64) NN`、`output_schema_version integer NN`、`input_digest bytea NN`、`input_refs jsonb NN`、`generation_config jsonb NN`、`generation bigint NN DEFAULT 1`、`model_call_limit,tool_call_limit integer NN`、`model_call_count,tool_call_count integer NN DEFAULT 0`、`started_at,finished_at timestamptz NULL`、`result_schema_version integer NN`、`result_refs jsonb NULL`、`error_code varchar(96) NULL`、`aggregation_revision bigint NN DEFAULT 0`。

另增 `capability varchar(12) NN`（text/vision/tts），与本run冻结模型能力一致。credential_test专用安全结果使用已有state/finished_at/error_code；finished_at映射tested_at，取消/中断不投影成成功。新增部分IX `(owner,credential_id,credential_version,model_id,capability,finished_at DESC,id) WHERE operation_kind='credential_test' AND finished_at IS NOT NULL`；测试查询还必须精确匹配provider/model_id/model_revision（NULL明确表示未知修订），模型切换不沿用另一模型测试成功；模型准确标识复用这几列，不复制catalog显示名。保存/轮换Key不会创建test run；当前版本无已结束测试显示untested。旧凭据版本迟到结果保留历史但不覆盖新版本结论，不另建credential_capability_checks。

state accepted/running/succeeded/failed/cancelled/interrupted/unknown_outcome；IX `(owner,operation_kind,created_at,id)`、`(owner,job_id)`、`(owner,agent_thread_id,state)`。非空 credential 引用只记录身份/版本，无密文/Key；每个新模型阶段重取当前本人凭据/能力/权限，不复用失效解密缓存。无Job短请求仅限不产生需容量预留的持久学习成品，例如显式Key能力测试；查询卡片/解释/音频/出题/诊断即使快速返回，也在本设计中由内部Job承载成品预留/发布，不新增用户任务入口。SDK/HTTP/Worker共享计数上限。派生 Token 汇总可由查询计算，不另建与attempt同时相加的权威总计。

### 7.3 `external_call_attempts`

公共列 UO + R。每个**真实供应商尝试**先落盘，Key测试、视觉、TTS同样适用。

| 列 | PG类型 / NULL / 默认 | 含义 |
| --- | --- | --- |
| library_id,job_id,job_stage_id,ai_run_id | uuid NULL | 有则逐项验证本人；Key测试允许无library/job |
| operation_id,request_id | uuid NN | 关联ID，不进 Loki 标签 |
| provider,capability | varchar(32) NN | 实际供应商；text/vision/tts |
| model_id | varchar(256) NN | 实际模型 |
| model_revision | varchar(128) NULL | 不可得为NULL |
| operation_kind | varchar(64) NN | 受控业务动作，含 credential_test |
| credential_id | uuid NN | 本人凭据身份；不存Key |
| credential_version | bigint NN | 本次开始实际版本 |
| attempt_no | integer NN | 同run或独立操作中真实调用序号 |
| input_digest | bytea NN | 请求规范摘要，不存原Prompt |
| provider_idempotency_digest | bytea NULL | 仅供应商确认支持时设置，不宣称本地键保证外部恰好一次 |
| status | varchar(16) NN DEFAULT 'started' | started/succeeded/failed/unknown |
| started_at | timestamptz NN | 真实尝试建立时点 |
| finished_at | timestamptz NULL | 已确认结束时间 |
| provider_request_id | varchar(256) NULL | 受限供应商关联号，不放秘密 |
| outcome_schema_version | integer NN | 封存产物引用schema |
| outcome_refs | jsonb NULL | 已返回产物的受控引用，无Prompt/回复全文 |
| error_code | varchar(96) NULL | 白名单错误码 |
| aggregation_revision | bigint NN DEFAULT 0 | 状态/迟到用量变化推进，触发聚合失效 |

UK `(owner,ai_run_id,attempt_no) WHERE ai_run_id IS NOT NULL`；无run调用 UK `(owner,operation_id,attempt_no) WHERE ai_run_id IS NULL`。IX `(owner,started_at,id)`、`(owner,provider,model_id,capability,started_at,id)`；实例管理按时间有界读取聚合，不新增私人明细旁路。started 后崩溃/超时结果不明转 unknown，不自动当未执行；显式新调用产生新attempt，旧迟到仅补自己，不覆盖新业务指针。

### 7.4 调用用量字段（位于 external_call_attempts）

ModelCallUsage是每attempt至多一份的逻辑值对象，和attempt同scope/保留期，迟到用量原本也必须锁attempt。直接并入external_call_attempts，不另建model_call_usages、重复owner/provider/model/状态/关联列，也不对同一结果做两表写入。

| 同表新增列 | PG类型 / NULL / 默认 | 含义 |
| --- | --- | --- |
| usage_status | varchar(16) NN DEFAULT 'unavailable' | complete/partial/unavailable，与调用status分别判断 |
| usage_received_at | timestamptz NULL | 最近可信用量补全时间；无响应仍NULL |
| input_tokens,output_tokens,total_tokens | bigint NULL | 供应商输入/输出/总量，未知NULL |
| cache_read_tokens,cache_write_tokens,reasoning_tokens | bigint NULL | Prompt缓存与推理分项，不能重复加入total |
| input_audio_tokens,output_audio_tokens | bigint NULL | 音频Token分项 |
| input_images,input_characters | bigint NULL | 可确定/供应商报告的图片及字符数 |
| output_audio_seconds | numeric(16,3) NULL | 时长，有限且非负 |
| provider_usage_schema | varchar(64) NULL | 尚无用量时为空，出现任何可信指标必须有适配版本 |
| safe_usage_details | jsonb NN DEFAULT '{}'::jsonb | 只允许白名单数字/布尔/枚举，无响应正文 |

计数CHECK非负或NULL；不要求total等于分项。逻辑usage id/external_call_attempt_id均映射本行id，call_status映射本行status；运行中的started行也计入attempt总数，按已有统计合同单列状态，不用缺用量过滤它。聚合直接从全部匹配attempt读取，以started_at划桶并复用7.3索引，返回每指标known_sum/known_count/unknown_count；全未知sum=NULL。供应商完全不返回用量、失败/unknown均不丢行。

补齐同一个attempt时锁本行、按适配器的稳定响应/单调补全规则去重；写入已报告绝对值，不重复累加或用迟到NULL清已有可信值。任何状态/指标变化在同事务推进aggregation_revision及updated_at/Outbox，幂等无变化不推进。供应商结果不明与业务发布状态保持分离，晚到用量不改变新run/effective结果。应用缓存命中不创建attempt或零Token用量。字段和统计语义唯一维护在[模型用量契约](../contracts/model-usage.md)。

### 7.5 `outbox_events`、`inbox_events`

| 表 / 公共列 | 专有列（类型 / 空值 / 默认） | 约束/职责 |
| --- | --- | --- |
| outbox_events / B，现有表增量目标 | `scope_kind varchar(24) NN`、`owner_user_id,library_id uuid NULL`、`event_type varchar(128) NN`、`audit_event_id uuid NULL`、`authorization_revision bigint NULL`、`schema_version integer NN`、`aggregate_kind varchar(64) NN`、`aggregate_id uuid NN`、`aggregate_revision bigint NN`、`payload jsonb NN`、`status varchar(16) NN`、`available_at timestamptz NN`、`published_at timestamptz NULL`、`lease_owner varchar(128) NULL`、`lease_expires_at timestamptz NULL`、`fence bigint NN DEFAULT 0`、`publish_attempts integer NN DEFAULT 0` | 保留B0的status列名与审计关联；id即event_id；scope user_owned/library_owned/system_catalog/system_operation；私有scope强制owner，library_owned另强制library；payload仅受控引用/计数/版本，无秘密/正文 |
| inbox_events / B | `consumer_name varchar(96) NN`、`event_id uuid NN`、`scope_kind varchar(24) NN`、`owner_user_id,library_id uuid NULL`、`payload_digest bytea NN`、`processed_at timestamptz NN`、`result_reference jsonb NULL`、`schema_version integer NN` | UK `(consumer_name,event_id)`；只有消费业务结果同事务提交时写入；同event异摘要冲突，不悄悄吞数据 |

现有 B0 结构以[账号分册基线](database-identity.md#outbox_events)为准：event_type varchar(48)、audit_event_id/authorization_revision NN、status仅pending/published，以及公共B列已存在；**上表是扩展目标，不是新建或已实现结构**。迁移保持既有ID、status、审计与时间；增列先可空，旧行回填scope_kind=system_operation、aggregate_kind=authorization_audit、aggregate_id=audit_event_id、aggregate_revision=authorization_revision、schema_version=1、payload为安全审计/授权版本引用、available_at=created_at，再加NN约束。event_type扩宽并将单一authorization.changed检查改为发布注册集合，status扩展publishing；原唯一audit_event_id保留（新业务可NULL），authorization.changed仍CHECK两旧字段非空且版本>=1，其他事件两字段均NULL。不得重发已published行、伪造旧published_at或重建覆盖B0记录。

两表登记 `system_operation`，按固定发布/消费服务读取；不得作为用户跨scope事件订阅接口。Outbox IX `(available_at,id) WHERE status='pending'`、`(lease_expires_at,id) WHERE status='publishing'`、`(owner_user_id,aggregate_kind,aggregate_id)`；Inbox IX `(processed_at,id)`。Kafka确认后标发布，重复投递预期可发生。Inbox去重与业务结果同事务，DB提交后才ACK。保留期需大于最大重放窗口；清理前核对消费位点，不在仍可能重放时删除唯一防重事实。

### 7.6 `idempotency_records`

公共列 UO + R。`library_id uuid NULL`、`audience varchar(16) NN`、`action_code varchar(128) NN`、`key_digest bytea NN`、`request_digest bytea NN`、`state varchar(16) NN`、`result_kind varchar(64) NULL`、`result_id uuid NULL`、`response_schema_version integer NN`、`safe_response jsonb NULL`、`http_status integer NULL`、`expires_at timestamptz NN`、`operation_id uuid NN`。

UK `(owner,audience,action_code,key_digest)`；IX `(expires_at,id)`；state processing/committed/failed/unknown；result kind/id成对，HTTP状态有值时100..599。键只存摘要且动作/本人分区，同键异载荷409；safe_response仅受限结果引用/错误码，不含材料/密码/Token/Key。创建领域对象/结果引用与幂等提交同事务，提交结果未知不得擅自生成新键重放。记录TTL结束不抹去领域业务唯一键；长任务仍在运行时不能回收。认证改密的结果不明遵循专属协议，不以这张通用表自动重放。

### 7.7 `user_notifications` — 本人站内任务提示

公共列 UO + R。`source_event_id uuid NN`、`job_id uuid NN`、`notification_kind varchar(48) NN`、`resource_kind varchar(48) NN`、`resource_id uuid NN`、`resource_version bigint NN`、`message_code varchar(128) NN`、`schema_version integer NN`、`safe_parameters jsonb NN`、`read_at timestamptz NULL`。

UK `(owner,source_event_id,notification_kind)`，IX `(owner,created_at,id)`、`(owner,created_at,id) WHERE read_at IS NULL`。依据[材料完成提示](../modules/materials-reading.md)和原型站内已读流程保存完成/失败/待校对等已提交事件的本人提示；message_code与安全参数由客户端本地化，不包含原文/题答/秘密。事件消费与Inbox同事务幂等创建；Redis只推新消息信号，清空Redis不丢已读事实。

读取/标记本人已读拟沿用 client.job.read 与实际来源read，结果跳转重新授权；明确拒绝时不借提示泄露标题/正文。具体列表/已读API与权限映射尚需在通知功能切片补入API目录后实施，本表不宣称它们已交付。不增加系统推送、邮件学习提醒或通知开关；消息安全保留期由部署配置明确，删除来源显示不可用安全状态，不能通过通知恢复已删材料。

## 8. 引用、生命周期与实施检查

| 聚合/保护行 | 新增与删除共用锁 | 保留/清理规则 |
| --- | --- | --- |
| CollectionItem、Notebook | 触及默认词本先user_extensions；再notebook按ID→collection按ID，同一流程统一顺序 | 删本仅解关系；删词tombstone/代次，题目/作答/错题必要快照继续保留 |
| ExerciseQuestion、依据、来源材料 | 来源材料根→题目根/版本→业务集/会话（实施时统一登记且所有入口一致） | 改题建新版本；已冻结/已作答引用不可丢；OPEN-10未完成前不能宣布用户删题能力ready |
| 作答/曝光/评分 | 接受计数器→会话/题项或ExamSession→Attempt→Run；普通只评分可直接锁Attempt | 不可变答案；effective切换替换贡献；媒体故障revision与整卷边界见材料分册 |
| 学习/错题投影 | CollectionItem→LearningState；根题/投影按稳定ID | 原始事实保留；状态可重算，乱序消费复核事实版本；无独立复习/每日队列表 |
| AgentThread | thread→附件/轮次 | 删除推进代次；绑定有效图片无普通TTL；独立收藏/解释不随thread删除 |
| 私有解释/音频 | 合法来源根→LookupState→GenerationSlot→Run/Asset | 完整成功结果和有效引用持久保留；本机/Redis淘汰仅丢副本 |
| global_word | 词条/profile→lookup→slot | 公共成品独立于贡献者；生产者关联只在内部slot；目录维护不发起个人Key调用 |
| Job/Outbox/attempt | Job→Stage/Run→Attempt（含用量组） | 重复投递按业务唯一/fence拒绝，未知外部结果不自动重试；用量补齐不能改当前业务成绩 |

表级 schema/索引是实施输入，实际 Alembic 迁移需逐切片交付并验证：无FK/隐式级联、UTC更新时间、所有者不可变、单行CHECK与逻辑引用、A/B隔离、父删/新增引用竞争、双端辅助接受顺序、整卷发布/重评重放、Redis丢失不触发重复模型调用、global_word生产者与等待者隔离、unknown/NULL用量及容量/GC。索引列顺序和文本检索性能须以目标PG和合成样本EXPLAIN确认，本设计不宣称已测试。

保留期除权威文档已给出者外由部署配置锁定；不能把临时预览TTL套给成功解释、TTS、评分或合法历史。模型配置/协议精度按既有契约定版；AI错题删除（OPEN-10）、掌握窗口校准（OPEN-11）、公共词表/标准声音profile范围仍是相关阶段的实施前置。本分册未引入商业化、人工改分、自由问答、独立聊天、SRS或全库备份。
