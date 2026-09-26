# 数据库设计书：表命名、归属与关系清单

版本：DBDESIGN3 / v0.3，2026-09-25；基线提交 `7fed5fc`。本轮只调整设计表名、补齐关系说明，承接DBDESIGN2的142张物理目标，不增删表、不合并字段、不改变业务唯一性。**46个目标名调整，其中2个对应B0已有表的未来改名，44个属于未建表设计。代码、模型、迁移和生成字典保持现状。**

DESIGN23（2026-09-26）进一步将第44～46项材料专用NLP改为全应用分析版本/句子/单元，token收进单元有界JSONB。三项替换仍占3表，总计142不变；本分册分类只表示字典位置，这3表同时服务非材料学习资源。旧命名稿的46项调整说明保留为历史基线，当前三项字段以[文本分册](database-materials.md#27-全应用派生语言标注)为准。

DBDESIGN4（2026-09-26）补齐根级教材课、直接题目收藏、共享词音请求/成品与转码容量约束；global_word_audios内的原件与派生采用受控一层1:N自关联，不新增表。以下对应行的基数/唯一摘要已同步，总计仍142。

## 1. 命名规则与阅读方法

- 表名表达业务归属或直接父对象：个人配置使用 `user_*`，材料源数据使用 `material_*`，场次答案使用 `exam_session_answers`。根实体保留 `users`、`materials`、`jobs` 等业务名称，不把所有库内表机械加上user/library全祖先链。
- 专用多对多关联表采用“两端业务名 + `_links`”，自关联使用“实体 + 关系语义 + `_links`”。例如 `user_role_links`、`collection_tag_links`、`role_inheritance_links`。关联行仍有独立ID、公共时间及业务组合唯一约束。
- 单例扩展、明细、版本、事件和独立状态使用业务名，不添加 `_1to1`、`_1toN` 或 `_MtoN`。多端引用不自动等于专用关联表：含状态的绑定、评分目标及允许重复的编排项保留bindings/targets/items/segments。
- 一对一必须注明相对哪个父对象；组合唯一不等于对其中任一列唯一。例如用户语言是1:N，词条学习状态是按学习版本的1:N，不能称为用户单例。
- 下表方向是“父表 → 当前表”；`1:N`简写父可有0至多条子行，每条子行必须引用一个有效父，除明确可空/分支者。多父每一条关系分别读；`M:N`表示两个端点的业务关系，物理上两端到关联表各为1:N。
- `1:0..1`是可选单例；UNIQUE只保证“至多一条”，注册/初始化事务才保证需要时“恰好一条”。当前指针唯一不把整个历史表改成一对一。
- 全部仍是逻辑关系，**无物理外键/隐式级联**。非空、唯一和CHECK负责行内约束；存在性、同用户/库、版本、分支和删除竞争由ScopeContext服务事务及共同父锁验证。表名前缀不提供授权。
- `S`为库作用域索引前缀 `(owner_user_id,library_id)`；`owner`为 `owner_user_id`。下表UQ/PK用于说明基数，不取代分册完整字段、部分谓词、反向索引、CHECK和冻结规则；不为命名额外添加唯一约束。

每行列出主要归属/业务父及影响基数的引用，并非完整外键清单。操作者、当前指针、历史来源和JSON出处等其余逻辑引用仍按分册登记。本页是当前表名/关系导航，三个字段分册继续作为拟实施字段和约束的唯一详细定义。

## 2. 全部142张目标表

编号延续本轮讨论中的全表顺序；前12项为B0实体，其中第5、6项显示未来目标名。邮件交付条件表是第20项，未选邮件模式时目标为141张。Redis19类键及逻辑DTO不计入表数。

### 2.1 账号、权限、配置与容量（34张）

详细字段与完整约束见[对应分册](database-identity.md)。

| 序号 | 目标表名 | 主要父表 / 关联端点 | 关系类型 | 基数依据与唯一约束摘要 |
| --- | --- | --- | --- | --- |
| 1 | `users` | — | 身份根 | UQ(email_normalized) |
| 2 | `libraries` | users | 1:0..1；有效账号建库后1:1 | UQ(owner_user_id) |
| 3 | `roles` | — | 系统目录根 | UQ(code) |
| 4 | `permission_catalog` | — | 系统目录根 | PK(code) |
| 5 | `user_role_links` | users ↔ roles | M:N关联 | UQ(user_id,role_id) |
| 6 | `role_permission_links` | roles ↔ permission_catalog | M:N关联，按策略维度区分 | 目标UQ(role_id,permission_code,effect,data_scope)；B0尚无data_scope |
| 7 | `menus` | menus（可选父菜单） | 目录根兼自关联1:N | UQ(code)；parent_menu_id为拟增列，同树无环由服务验 |
| 8 | `auth_policies` | — | 实例策略根 | PK(code)，受已注册代码约束 |
| 9 | `authorization_revisions` | — | 全局单例保护根 | PK(code)，CHECK code='global' |
| 10 | `admin_audit_events` | —；users为可选审计对象 | 独立追加事实；用户1:N审计 | PK(id)，不对目标用户唯一 |
| 11 | `outbox_events` | 已注册业务聚合；B0为admin_audit_events | 目标聚合1:N；B0审计1:0..1 | UQ(audit_event_id)保留，新业务可空；其他聚合不强加单例 |
| 12 | `seed_versions` | — | 系统种子版本根 | PK(code) |
| 13 | `user_extensions` | users | 1:0..1；完成扩展初始化后1:1 | UQ(user_id)，注册事务保证新账号扩展行存在 |
| 14 | `user_languages` | user_extensions | 1:N；每用户可选多种语言 | UQ(user_id,language_kind,language_tag)及(user_id,language_kind,sort_order) |
| 15 | `user_model_bindings` | user_extensions | 1:N；每能力至多一个当前选择 | UQ(user_id,capability)，引用本人凭据与模型目录 |
| 16 | `user_voice_bindings` | user_extensions | 1:N；每语言×用途至多一个选择 | UQ(user_id,language_tag,speech_purpose) |
| 17 | `user_provider_credentials` | users | 1:N | PK(id)，不对(user_id,provider)唯一 |
| 18 | `user_auth_sessions` | users | 1:N | PK(id)，不对(user_id,audience)唯一 |
| 19 | `user_auth_challenges` | users | 1:N | UQ(digest_key_version,token_digest) |
| 20 | `user_auth_challenge_deliveries` | user_auth_challenges | 1:0..1，邮件模式条件表 | UQ(user_id,challenge_id) |
| 21 | `role_inheritance_links` | roles ↔ roles | M:N自关联 | UQ(child_role_id,parent_role_id)，禁自指且服务验无环 |
| 22 | `role_grant_boundaries` | roles（grantor） | 1:N授权边界规则；按kind引用角色或权限 | 按boundary_kind分支的部分UQ，见账号分册；不是单一双端点关联 |
| 23 | `permission_dependency_links` | permission_catalog ↔ permission_catalog | M:N自关联 | UQ(permission_code,required_permission_code)，禁止同端点 |
| 24 | `menu_permission_links` | menus ↔ permission_catalog | M:N关联 | UQ(menu_id,permission_code) |
| 25 | `model_catalog_entries` | — | 系统模型目录根 | UQ(provider,model_code) |
| 26 | `voice_catalog_entries` | model_catalog_entries | 1:N | UQ(model_catalog_entry_id,voice_code,language_tag) |
| 27 | `language_capabilities` | — | 系统语言目录根 | UQ(language_tag) |
| 28 | `feature_flags` | — | 系统配置根 | UQ(code) |
| 29 | `runtime_limit_policies` | — | 系统限额策略根 | UQ(subject_kind,limit_code) |
| 30 | `user_runtime_limits` | users | 1:N；每限额维度至多一个覆盖 | UQ(user_id,limit_code) |
| 31 | `user_storage_states` | users | 1:0..1，可延迟初始化的热点计数 | UQ(user_id) |
| 32 | `global_storage_states` | — | 共享词音容量根 | UQ(catalog_code)，CHECK固定global_word |
| 33 | `user_storage_reservations` | users；容量根user_storage_states | 1:N预留账本 | UQ(user_id,request_kind,request_id,purpose) |
| 34 | `global_storage_reservations` | global_storage_states；合成Job或共享audio根 | 1:N预留账本，合成/转码分支 | 合成部分UQ(catalog_code,producer_job_id,reservation_stage)；转码活动部分UQ(catalog_code,source_audio_id,derivation_key_digest) |

### 2.2 材料、阅读与考试（46张）

详细字段与完整约束见[对应分册](database-materials.md)。

| 序号 | 目标表名 | 主要父表 / 关联端点 | 关系类型 | 基数依据与唯一约束摘要 |
| --- | --- | --- | --- | --- |
| 35 | `upload_intents` | users；target_kind指定业务父 | 用户/业务父1:N意图 | 临时及候选对象键UQ；purpose/target_kind由服务校验 |
| 36 | `file_objects` | users；upload_intents为可选来源 | 用户1:N；上传意图1:0..1正式对象 | UQ(bucket_name,object_key)；部分UQ(user_id,upload_intent_id) |
| 37 | `material_imports` | libraries | 1:N导入意图 | UQ(S,idempotency_record_id) |
| 38 | `materials` | libraries | 1:N材料根 | PK(id)；主文件可被多材料合法复用 |
| 39 | `material_revisions` | materials | 1:N版本 | UQ(S,material_id,revision_number) |
| 40 | `material_source_assets` | material_revisions | 1:N来源资产 | UQ(S,material_revision_id,ordinal) |
| 41 | `material_source_units` | material_revisions；material_source_assets | 两者各1:N；单元另有可选自父 | UQ(S,material_revision_id,ordinal)，同版本树由服务验 |
| 42 | `material_content_blocks` | material_source_units | 1:N内容块 | UQ(S,source_unit_id,ordinal) |
| 43 | `material_import_issues` | material_revisions | 1:N问题 | PK(id)，不把某种问题限定为单条 |
| 44 | `text_analysis_versions` | 已注册材料/解释/卡片/收藏/题目等源版本 | 每源版本1:N pipeline分析；当前选用1:0..1 | UQ(S,source_kind,source_resource_id,source_version,pipeline_digest)，desired/selected各自部分唯一见分册 |
| 45 | `text_analysis_sentences` | text_analysis_versions；text_analysis_units为锚定单元 | 分析1:N句；锚定单元1:N，spans可跨单元 | UQ(S,analysis_version_id,sentence_identity_digest)及(S,analysis_version_id,anchor_unit_id,ordinal) |
| 46 | `text_analysis_units` | text_analysis_versions | 1:N有界字段/块单元；词序列为JSONB值对象 | UQ(S,analysis_version_id,unit_identity_digest)及(S,analysis_version_id,ordinal) |
| 47 | `novel_chapters` | material_revisions（novel） | 1:N章节 | UQ(S,material_revision_id,ordinal) |
| 48 | `novel_chapter_blocks` | novel_chapters；material_content_blocks为来源 | 章节1:N编排项；同块可多次/分范围引用 | UQ(S,chapter_id,ordinal)，不添加章节×块唯一 |
| 49 | `textbook_units` | material_revisions（textbook） | 1:N单元，含可选自父 | UQ(S,material_revision_id,ordinal) |
| 50 | `textbook_lessons` | material_revisions；textbook_units可空 | 版本1:N课；有Unit时Unit1:N课 | 非空Unit部分UQ(S,unit_id,ordinal)；根课部分UQ(S,material_revision_id,ordinal) |
| 51 | `textbook_content_nodes` | textbook_lessons | 1:N内容节点 | UQ(S,lesson_id,ordinal) |
| 52 | `textbook_content_node_links` | textbook_content_nodes ↔ textbook_content_nodes | M:N自关联，按关系类型区分 | UQ(S,from_node_id,to_node_id,relation_kind) |
| 53 | `textbook_dialogue_turns` | textbook_content_nodes | 1:N对话轮次 | UQ(S,content_node_id,ordinal) |
| 54 | `textbook_vocabulary_rows` | textbook_content_nodes | 1:N原书词表行 | UQ(S,content_node_id,ordinal)，同词允许多行 |
| 55 | `textbook_table_cells` | textbook_content_nodes | 1:N单元格 | UQ(S,content_node_id,row_index,column_index) |
| 56 | `textbook_content_node_question_links` | textbook_content_nodes ↔ exercise_questions | M:N关联，附题序及准备状态 | UQ(S,content_node_id,exercise_question_id)及(S,content_node_id,ordinal) |
| 57 | `material_reading_progress` | materials；material_revisions | 材料1:N；每本人库×源版本至多一条 | UQ(S,material_id,material_revision_id) |
| 58 | `material_bookmarks` | material_revisions | 1:N书签 | UQ(S,material_revision_id,locator_digest) |
| 59 | `material_reading_open_events` | material_revisions | 1:N实际打开记录 | UQ(S,open_request_id) |
| 60 | `material_source_rebindings` | materials；同kind的源/目标版本 | 1:N定位重绑事实 | UQ(S,source_kind,source_version_id,target_version_id,source_locator_digest) |
| 61 | `exam_papers` | materials（exam） | 1:0..1；完成试卷初始化后1:1 | UQ(S,material_id) |
| 62 | `exam_paper_versions` | exam_papers | 1:N试卷版本 | UQ(S,exam_paper_id,version_number) |
| 63 | `exam_sections` | exam_paper_versions | 1:N题组，含可选自父 | UQ(S,exam_paper_version_id,ordinal) |
| 64 | `exam_stimuli` | exam_sections | 1:N共享题面材料 | UQ(S,section_id,ordinal) |
| 65 | `exam_items` | exam_paper_versions；exam_sections | 各1:N计分叶子，引用公共题版本 | UQ(S,exam_paper_version_id,ordinal)及(S,exam_paper_version_id,exercise_question_id) |
| 66 | `exam_stimulus_item_links` | exam_stimuli ↔ exam_items | M:N关联 | UQ(S,stimulus_id,exam_item_id)及(S,stimulus_id,ordinal) |
| 67 | `exam_preparation_issues` | exam_paper_versions | 1:N准备问题 | PK(id)，可按kind引用题/共享材料/候选 |
| 68 | `exam_listening_script_sources` | exam_papers；exam_paper_versions为基准 | 试卷1:N文字稿来源 | PK(id)，明确上传稿/正文范围两分支 |
| 69 | `exam_listening_script_versions` | exam_listening_script_sources | 1:N稿版本 | UQ(S,script_source_id,version_number) |
| 70 | `exam_listening_script_segments` | exam_listening_script_versions | 1:N稿段 | UQ(S,script_version_id,ordinal) |
| 71 | `exam_listening_candidates` | exam_paper_versions；ai_runs | 各1:N AI候选 | UQ(S,ai_run_id,ordinal) |
| 72 | `exam_listening_candidate_item_links` | exam_listening_candidates ↔ exam_items | M:N候选关联 | UQ(S,candidate_id,exam_item_id)及(S,candidate_id,ordinal) |
| 73 | `exam_listening_bindings` | exam_stimuli；exam_listening_script_versions | 共享材料1:0..1；稿版本1:N绑定 | UQ(S,exam_paper_version_id,stimulus_id)，包含确认/策略状态，保留bindings |
| 74 | `exam_listening_synthesis_specs` | exam_listening_bindings | 1:N合成规格历史 | UQ(S,listening_binding_id,spec_number) |
| 75 | `exam_sessions` | exam_paper_versions | 1:N考试场次 | PK(id)，不把未完成场次设成全用户单例 |
| 76 | `exam_session_answers` | exam_sessions；exam_items | 场次1:N；每场×叶子至多一条 | UQ(S,exam_session_id,exam_item_id)；question_attempt_id非空部分UQ |
| 77 | `exam_session_listening_usages` | exam_sessions；exam_stimuli | 场次1:N；每场×共享听力至多一条 | UQ(S,exam_session_id,stimulus_id) |
| 78 | `exam_session_listening_play_attempts` | exam_session_listening_usages；exam_sessions | 各1:N播放尝试 | UQ(S,exam_session_id,idempotency_key_hash) |
| 79 | `exam_session_media_faults` | exam_sessions | 1:N媒体故障事实 | UQ(S,exam_session_id,asset_kind,asset_id) |
| 80 | `exam_media_fault_item_links` | exam_session_media_faults ↔ exam_items | M:N故障影响关联 | UQ(S,fault_id,exam_item_id) |

### 2.3 收藏、学习、AI与任务（62张）

详细字段与完整约束见[对应分册](database-learning.md)。

| 序号 | 目标表名 | 主要父表 / 关联端点 | 关系类型 | 基数依据与唯一约束摘要 |
| --- | --- | --- | --- | --- |
| 81 | `collection_items` | libraries；卡片或类型化题目来源 | 1:N收藏根；题目按作答上下文区分 | 部分UQ(S,card_id,card_revision)及(S,question_identity_digest)；两来源分支互斥，词形/义项不唯一 |
| 82 | `library_tags` | libraries | 1:N标签 | UQ(S,name_normalized) |
| 83 | `collection_tag_links` | collection_items ↔ library_tags | M:N关联 | UQ(S,collection_item_id,tag_id) |
| 84 | `vocabulary_notebooks` | libraries | 1:N词本 | UQ(S,target_language,name_normalized) |
| 85 | `vocabulary_notebook_collection_links` | vocabulary_notebooks ↔ collection_items | M:N关联 | UQ(S,notebook_id,collection_item_id) |
| 86 | `collection_selection_snapshots` | libraries | 1:N批量操作快照 | PK(id)，相同筛选可创建多次快照 |
| 87 | `collection_selection_item_links` | collection_selection_snapshots ↔ collection_items | M:N快照成员关联 | UQ(S,selection_id,collection_item_id)及(S,selection_id,ordinal) |
| 88 | `csv_import_batches` | libraries | 1:N导入批次 | PK(id) |
| 89 | `csv_import_rows` | csv_import_batches | 1:N逻辑行 | UQ(S,batch_id,ordinal) |
| 90 | `photo_word_imports` | libraries | 1:N照片识词批次 | PK(id) |
| 91 | `photo_word_import_candidates` | photo_word_imports | 1:N候选，保留代次 | UQ(S,photo_import_id,generation,ordinal) |
| 92 | `exercise_question_roots` | libraries | 1:N稳定题根 | PK(id) |
| 93 | `exercise_questions` | exercise_question_roots | 1:N不可变题目版本 | UQ(S,exercise_root_id,question_version) |
| 94 | `question_grading_bases` | exercise_questions | 1:N评分依据版本 | UQ(S,exercise_question_id,basis_version) |
| 95 | `question_source_refs` | exercise_questions | 1:N出处明细 | UQ(S,exercise_question_id,ordinal)，来源类型/范围可多次引用 |
| 96 | `question_assessment_targets` | exercise_questions；collection_items | 题目1:N考察目标；词条1:N目标 | UQ(S,exercise_question_id,scoring_item_key,collection_item_id,learning_revision,skill)；含考察语义，保留targets |
| 97 | `exercise_selection_snapshots` | libraries | 1:N习题选源快照 | PK(id) |
| 98 | `exercise_selection_candidates` | exercise_selection_snapshots | 1:N候选 | UQ(S,selection_id,ordinal)及(S,selection_id,candidate_key) |
| 99 | `exercise_sets` | libraries；exercise_selection_snapshots为可选选源 | 库1:N；选源1:N集，非AI集可无选源 | 部分UQ(S,job_id)，同一选源允许显式再次生成不同集 |
| 100 | `exercise_set_items` | exercise_sets；exercise_questions为冻结引用 | 集1:N编排项，题可被多项引用 | UQ(S,exercise_set_id,ordinal)，不新增集×题唯一 |
| 101 | `practice_sessions` | libraries；exercise_sets为可选来源 | 库/集各1:N练习场次 | PK(id)，直接教材练习可无集 |
| 102 | `practice_session_items` | practice_sessions；exercise_questions为引用 | 场次1:N题项 | UQ(S,practice_session_id,ordinal)，不新增场次×题唯一 |
| 103 | `question_attempts` | practice_session_items 或 exam_session_answers | 每个来源题项/答卷1:0..1提交事实 | 分别对非空practice_session_item_id、exam_answer_id加scope部分UQ；来源分支互斥 |
| 104 | `library_learning_acceptance_counters` | libraries | 1:0..1接受序号根 | UQ(S)，按库初始化 |
| 105 | `answer_exposures` | practice_session_items；collection_items | 题项1:N目标曝光 | UQ(S,practice_session_item_id,collection_item_id,learning_revision,exposure_kind) |
| 106 | `grading_runs` | question_attempts 或 exam_sessions | 各父1:N评分历史；活动run至多一个 | 父ID×generation部分UQ；WHERE active父ID部分UQ，父分支互斥 |
| 107 | `grading_results` | grading_runs；question_attempts | run/attempt各1:N评分叶子 | UQ(S,grading_run_id,question_attempt_id,scoring_item_key) |
| 108 | `learner_contributions` | question_attempts；来源聚合attempt/exam | 1:N叶子贡献 | UQ(S,source_kind,source_aggregate_id,question_attempt_id,scoring_item_key) |
| 109 | `effective_learning_evidence` | question_attempts；collection_items | 两者各1:N当前有效证据 | UQ(S,question_attempt_id,scoring_item_key,collection_item_id,learning_revision,skill) |
| 110 | `collection_word_learning_states` | collection_items（word） | 1:N版本状态；每学习版本至多一条 | UQ(S,collection_item_id,learning_revision) |
| 111 | `mistake_occurrences` | grading_results | 1:N历史错误考察点 | UQ(S,grading_result_id,knowledge_key) |
| 112 | `mistake_projections` | exercise_question_roots | 1:N当前考察点投影 | UQ(S,exercise_root_id,scoring_item_key,knowledge_key) |
| 113 | `learner_language_profiles` | libraries | 1:N按语言的统计档案 | UQ(S,target_language)，不等于用户单例资料 |
| 114 | `diagnosis_reports` | libraries；ai_runs为生成来源 | 库1:N诊断报告 | PK(id)，不据ai_run_id引用自行添加唯一 |
| 115 | `diagnosis_report_evidence_refs` | diagnosis_reports | 1:N证据引用 | UQ(S,diagnosis_report_id,ordinal) |
| 116 | `agent_threads` | libraries | 1:N内部查询上下文 | PK(id)，不新增用户聊天产品 |
| 117 | `agent_thread_messages` | agent_threads | 1:N消息 | UQ(S,agent_thread_id,turn_generation,ordinal) |
| 118 | `agent_message_attachments` | agent_threads；agent_thread_messages可空 | 上下文1:N；绑定后消息1:N | UQ(S,file_object_id)；已绑定时部分UQ(S,agent_message_id,ordinal) |
| 119 | `cards` | ai_runs；agent_thread_messages可空 | 运行1:N卡片版本 | UQ(S,ai_run_id,ordinal,card_revision) |
| 120 | `ai_feedback` | explanations 或 cards的结果版本 | 每本人结果版本1:0..1反馈 | UQ(S,result_kind,result_id,result_version) |
| 121 | `explanations` | ai_runs | 1:0..1完整解释 | UQ(S,ai_run_id) |
| 122 | `source_result_bindings` | learning_lookup_states；类型化来源与结果 | lookup1:N历史绑定 | UQ(S,binding_digest)，包含版本/出处与释放语义，保留bindings |
| 123 | `learning_lookup_states` | libraries | 1:N查阅身份 | UQ(S,artifact_kind,lookup_key_digest)，每身份至多一个effective指针 |
| 124 | `learning_generation_slots` | libraries | 1:N严格生成身份 | UQ(S,artifact_kind,strict_key_digest)，不把lookup与slot误标为1:1 |
| 125 | `audio_assets` | libraries；ai_runs为生成来源 | 库/运行各1:N音频资产 | UQ(S,strict_key_digest,generation) |
| 126 | `audio_asset_segments` | audio_assets | 1:N音频片段 | UQ(S,audio_asset_id,ordinal) |
| 127 | `playback_manifests` | libraries | 1:N播放清单 | PK(id)，跨入口复用本人音频 |
| 128 | `playback_manifest_segments` | playback_manifests；audio_asset_segments为引用 | 清单1:N编排段；同段允许按序重复 | UQ(S,playback_manifest_id,ordinal)，不增加清单×音频段唯一 |
| 129 | `global_word_entries` | — | 共享词条目录根 | UQ(catalog_source,catalog_version,language,dialect,entry_key,pronunciation_variant) |
| 130 | `global_voice_profiles` | — | 共享声音配置根 | UQ(code)；WHERE is_default部分UQ(language) |
| 131 | `global_voice_profile_versions` | global_voice_profiles | 1:N配置版本 | UQ(profile_id,profile_revision) |
| 132 | `global_word_audios` | global_word_entries；global_voice_profile_versions；本表合成根 | 词条/profile各1:N成品；根1:N格式派生，禁止派生链 | synthesized部分UQ(strict_key_digest,generation)；derived部分UQ(source_audio_id,derivation_key_digest) |
| 133 | `global_word_lookup_states` | global_word_entries；global_voice_profiles | 各1:N；每词条×配置一条状态 | UQ(word_entry_id,profile_id)，有独立选用状态，保留states |
| 134 | `global_word_generation_slots` | global_word_entries；global_voice_profile_versions | 各1:N严格生成占用 | UQ(strict_key_digest)，生产者为受限操作引用 |
| 135 | `speech_requests` | libraries；类型化朗读来源；冻结的共享词条/profile/执行 | 来源1:N请求历史 | UQ(S,source_kind,source_resource_id,request_generation)；共享请求代次等于个人选择代次，旧请求不重绑新执行 |
| 136 | `jobs` | users；libraries可空 | 用户1:N持久任务 | PK(id)，账号级Key测试可无库 |
| 137 | `job_stages` | jobs | 1:N阶段及阶段代次 | UQ(owner,job_id,job_generation,stage_key,stage_generation) |
| 138 | `ai_runs` | users；jobs/agent_threads可空 | 用户1:N运行；有父时父1:N | PK(id)，不强加job_id唯一 |
| 139 | `external_call_attempts` | users；ai_runs可空 | 用户/运行各1:N真实调用 | 有run时UQ(owner,ai_run_id,attempt_no)，无run时UQ(owner,operation_id,attempt_no) |
| 140 | `inbox_events` | outbox_events所传输的event_id | 事件1:N消费方去重事实 | UQ(consumer_name,event_id)，不是event_id单列唯一 |
| 141 | `idempotency_records` | users | 1:N幂等受理记录 | UQ(owner,audience,action_code,key_digest) |
| 142 | `user_notifications` | users；outbox_events来源事件 | 用户1:N提示；事件可对应多种提示 | UQ(owner,source_event_id,notification_kind) |

## 3. 改名映射与已实现边界

下列映射只改变物理目标表标识；列名、API路径、DTO、权限代码、事件名、CSV字段、Redis键名和缓存载荷字段不随之自动改名。例如表中的 `source_unit_id`、`exam_answer_id`、`assessment_target_id` 继续是已定义的逻辑引用列，目标表由分册说明；接口 `tags`、`bookmarks`、`explanations` 及 `cards` 继续按API契约。

| DBDESIGN2表名 | DBDESIGN3目标表名 | 实施状态 |
| --- | --- | --- |
| `user_roles` | `user_role_links` | B0已有；未来受控改名，当前仍为旧名 |
| `role_permissions` | `role_permission_links` | B0已有；未来受控改名，当前仍为旧名 |
| `study_profile_languages` | `user_languages` | 尚未建表；功能切片直接使用新目标名 |
| `settings_model_bindings` | `user_model_bindings` | 尚未建表；功能切片直接使用新目标名 |
| `settings_voice_bindings` | `user_voice_bindings` | 尚未建表；功能切片直接使用新目标名 |
| `provider_credentials` | `user_provider_credentials` | 尚未建表；功能切片直接使用新目标名 |
| `auth_sessions` | `user_auth_sessions` | 尚未建表；功能切片直接使用新目标名 |
| `auth_challenges` | `user_auth_challenges` | 尚未建表；功能切片直接使用新目标名 |
| `auth_challenge_deliveries` | `user_auth_challenge_deliveries` | 尚未建表；功能切片直接使用新目标名 |
| `role_inheritances` | `role_inheritance_links` | 尚未建表；功能切片直接使用新目标名 |
| `permission_dependencies` | `permission_dependency_links` | 尚未建表；功能切片直接使用新目标名 |
| `menu_permissions` | `menu_permission_links` | 尚未建表；功能切片直接使用新目标名 |
| `storage_reservations` | `user_storage_reservations` | 尚未建表；功能切片直接使用新目标名 |
| `source_assets` | `material_source_assets` | 尚未建表；功能切片直接使用新目标名 |
| `source_units` | `material_source_units` | 尚未建表；功能切片直接使用新目标名 |
| `content_blocks` | `material_content_blocks` | 尚未建表；功能切片直接使用新目标名 |
| `import_issues` | `material_import_issues` | 尚未建表；功能切片直接使用新目标名 |
| `linguistic_analysis_versions`（DBDESIGN3曾称material_analysis_versions） | `text_analysis_versions` | DESIGN23扩大为已注册学习资源；未建表 |
| `sentences`（DBDESIGN3曾称material_sentences） | `text_analysis_sentences` | DESIGN23支持跨unit范围；未建表 |
| `tokens`（DBDESIGN3曾称material_tokens） | `text_analysis_units`中的token数组 | DESIGN23将逐词行收敛为有界块值对象，原表名额替换为unit；未建表 |
| `textbook_content_edges` | `textbook_content_node_links` | 尚未建表；功能切片直接使用新目标名 |
| `textbook_exercise_bindings` | `textbook_content_node_question_links` | 尚未建表；功能切片直接使用新目标名 |
| `reading_progress` | `material_reading_progress` | 尚未建表；功能切片直接使用新目标名 |
| `bookmarks` | `material_bookmarks` | 尚未建表；功能切片直接使用新目标名 |
| `reading_open_events` | `material_reading_open_events` | 尚未建表；功能切片直接使用新目标名 |
| `source_rebindings` | `material_source_rebindings` | 尚未建表；功能切片直接使用新目标名 |
| `exam_stimulus_item_bindings` | `exam_stimulus_item_links` | 尚未建表；功能切片直接使用新目标名 |
| `exam_listening_candidate_items` | `exam_listening_candidate_item_links` | 尚未建表；功能切片直接使用新目标名 |
| `exam_answers` | `exam_session_answers` | 尚未建表；功能切片直接使用新目标名 |
| `exam_listening_play_attempts` | `exam_session_listening_play_attempts` | 尚未建表；功能切片直接使用新目标名 |
| `exam_media_faults` | `exam_session_media_faults` | 尚未建表；功能切片直接使用新目标名 |
| `exam_media_fault_items` | `exam_media_fault_item_links` | 尚未建表；功能切片直接使用新目标名 |
| `tags` | `library_tags` | 尚未建表；功能切片直接使用新目标名 |
| `collection_tags` | `collection_tag_links` | 尚未建表；功能切片直接使用新目标名 |
| `notebook_items` | `vocabulary_notebook_collection_links` | 尚未建表；功能切片直接使用新目标名 |
| `collection_selection_members` | `collection_selection_item_links` | 尚未建表；功能切片直接使用新目标名 |
| `photo_word_candidates` | `photo_word_import_candidates` | 尚未建表；功能切片直接使用新目标名 |
| `assessment_targets` | `question_assessment_targets` | 尚未建表；功能切片直接使用新目标名 |
| `learning_acceptance_counters` | `library_learning_acceptance_counters` | 尚未建表；功能切片直接使用新目标名 |
| `vocabulary_learning_states` | `collection_word_learning_states` | 尚未建表；功能切片直接使用新目标名 |
| `learner_profiles` | `learner_language_profiles` | 尚未建表；功能切片直接使用新目标名 |
| `diagnosis_evidence_refs` | `diagnosis_report_evidence_refs` | 尚未建表；功能切片直接使用新目标名 |
| `agent_messages` | `agent_thread_messages` | 尚未建表；功能切片直接使用新目标名 |
| `generation_slots` | `learning_generation_slots` | 尚未建表；功能切片直接使用新目标名 |
| `audio_segments` | `audio_asset_segments` | 尚未建表；功能切片直接使用新目标名 |
| `notifications` | `user_notifications` | 尚未建表；功能切片直接使用新目标名 |

现有B0 12张物理表以[账号分册第1节](database-identity.md)及[生成字典](../../contracts/database-schema.json)为准。其中 `user_roles → user_role_links`、`role_permissions → role_permission_links` 是同一实体的未来改名，不是新增两张关联表，也不将当前B0数量改成14。其余10张B0表名保持。

未来实施这两项改名必须新增受控Alembic revision，在同一受维护锁保护的升级中协调模型、表/索引/约束名称、逻辑关系元数据、受管基线和生成字典；保留原ID、数据、人工授权及deny含义，不能修改0001或删建覆盖。本轮不规定运行中双版本并行兼容；如部署要求旧代码继续访问，实施切片必须先明确过渡方案。改名前后行数、业务唯一性、反向查询与权限语义都要在届时真实迁移验收。

DBDESIGN2的[必要性收敛](database-convergence.md)保留158个原候选名称，物理目标列已同步本页新名称；历史review记录与当前生成字典中的旧名是历史/实现证据，不做全文替换。
