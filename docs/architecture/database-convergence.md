# 数据库物理结构必要性与实施复杂度收敛

收敛决策：DBDESIGN2，2026-09-25，基线提交 `af87a41`；物理目标名于DBDESIGN3按 `7fed5fc` 更新，原候选列保留历史名称。这是阶段1内的文档小阶段，按用户明确原则收敛DBDESIGN1的全部物理候选。字段以[账号](database-identity.md)、[材料](database-materials.md)、[学习](database-learning.md)分册为准，本页只维护逐表取舍、逻辑映射和实施成本，不复制字段字典。

## 1. 结论与计数口径

**158张候选 → 142张物理目标表，减少16张。** 其中已有B0仍为12张，未实现目标130张；130中包含邮件交付条件表1张，条件未确定时确定目标是141张（12已有+129拟新增）。不计alembic_version、API对象、查询投影、Redis键或把Outbox跨分册重复计数。条件表不是本轮新增范围。

| 领域 | 原候选数 | 收敛后数 | 减少 |
| --- | --- | --- | --- |
| 账号/权限/配置 | 38 | 34 | 4 |
| 材料/阅读/考试 | 50 | 46 | 4 |
| 收藏/学习/AI（不重复Outbox） | 70 | 62 | 8 |
| 合计 | 158 | 142 | 16 |

上表按收敛后物理字典所属分册计数：avatar并入既有候选file_objects、能力测试并入既有候选ai_runs，承接表不重复增加；全量计数以第4节目标名去重为准；当前142表的归属、基数和改名映射见[命名与关系清单](database-relations.md)。

## 2. 拆分判断与实际代价

1. users保留身份/密码/安全版本；user_extensions合并可选资料、单例学习偏好和通用设置，三个字段组版本保持API并发边界。语言、模型、声音、Key、会话保留真实一对多。
2. 同scope、同保留期、相同保护行的一对一附属记录优先合并；独立DTO/Service本身不足以证明需要物理表。低频不同字段组更新用列白名单和组CAS，承认同一物理行会短暂串行。
3. 多版本历史、多条明细、多对多、独立可变状态机、独立授权/清理或实际热点计数保留拆分。不能为减表把明细/关键引用/状态塞进不受约束JSON。
4. 对可重建结构区分实时查询与必要物化：书内查阅索引改为带索引的绑定/lookup查询；掌握、错题和学习统计因版本重放及筛选需求保留投影，仍需幂等消费和重建证据。
5. 每张表都带来scope过滤、无FK引用校验、保护行/GC协议、迁移/字典及验收成本。以下逐表理由是实施输入，不能用“职责清晰”代替；索引和锁性能仍需真实样本证明，当前不承诺少16张就有固定性能收益。

## 3. 合并后的行为边界与验收重点

| 合并 | 减少 | 必须保留的行为 / 实施代价 |
| --- | --- | --- |
| 三个用户单例→user_extensions | 2 | 三组CAS/白名单；不同组写入不整行覆盖；头像/子选择/删词本使用同一扩展父锁；同组冲突仍409 |
| AvatarAsset→file_objects | 1 | 头像专用purpose/尺寸/重编码规则；专用DTO/鉴权；旧图引用及GC仍独立可查 |
| 能力测试摘要→ai_runs | 1 | 每Key版本/精确模型/能力的最近显式测试；无测试不是成功，旧版本迟到只历史 |
| 小说/课本manifest头→material_revisions | 2 | 独立类型schema和子表；源与结构分组首次发布/冻结，后续结构改版另建revision；逻辑manifest ID映射revision ID |
| AudioBinding→synthesis_specs；PlaybackPolicy→listening_bindings | 2 | 配置不可变、结果组可受控发布；确认者/时间分开；ready卷冻结spec/策略，场次不读新草稿 |
| 合并映射/标准词音选择→collection_items | 2 | 源tombstone保留不可变合并去向；词音代次与内容版本校验，异步仅更新词音组 |
| AiExercisePlan→exercise_sets；计划来源复用冻结候选 | 2 | 确认即建集，计划字段不可改；selection被引用即禁止TTL清理，GC和确认共锁selection；显式再次生成另建集 |
| 一次争议反馈→grading_results；错题收藏→occurrences | 2 | 争议不改成绩；收藏拥有独立版本/时间且可取消；错误和评分事实不被表单覆盖 |
| MaterialLearningIndex→binding列+lookup查询 | 1 | 查阅只取当前effective匹配，旧历史合法保留；消除双写/投影Worker，查询两侧仍查scope |
| ModelCallUsage→external_call_attempts | 1 | attempt独立、未知NULL；补齐写绝对值并推进统计版本，不漏无用量调用、不叠加AiRun汇总 |

保留的重点一对一/近一对一结构：Library是既有scope根；ExamPaper有独立于源版本的准备/冻结生命周期；阅读进度、容量状态、接受序号、场次听力计数有实际热点写入；邮件Delivery有与挑战摘要不同的解密访问和销毁窗口。可变草稿ExamAnswer与不可变QuestionAttempt也不合并。它们增加表数，但省表会把锁竞争或状态/权限复杂度转移到更关键的根。

B0没有上述拟合并表，后续迁移直接创建收敛目标，不能先照旧设计建表再做迁移。所有逻辑对象/API仍由专用DTO投影，ID复用仅限本文明确的一对一映射；没有服务端授权的裸ID不能跨用途查询。

## 4. 全量逐表审查

每个DBDESIGN1候选恰好一行；“并入/复用”不是待建表，箭头后的目标才是当前物理承载。阶段是首次相关功能切片及后续完整能力，不代表该阶段一次建立全部目标。B0保持原结构证据，未实现字段随切片增加。

### 账号、权限与配置

| 序号 | 原候选表 | 结论 / 物理目标 | 必要性与实施成本 | 阶段 |
| --- | --- | --- | --- | --- |
| 1 | `users` | 保留 | 身份与密码/安全版本根，和可选偏好隔离 | 1/B0 |
| 2 | `libraries` | 保留 | 每用户虽唯一，仍是库作用域和大量引用的稳定根；已实现，移除会广泛改scope | 1/B0 |
| 3 | `roles` | 保留 | 独立可管理角色，生命周期与用户不同 | 1/B0 |
| 4 | `permission_catalog` | 保留 | 发布权限目录，可被多个角色/页面引用 | 1/B0 |
| 5 | `user_roles` | 保留；目标 `user_role_links` | 用户多角色关系，需唯一与反向影响查询 | 1/B0 |
| 6 | `role_permissions` | 保留；目标 `role_permission_links` | 角色多权限及deny/数据范围，不能数组化省校验 | 1/B0 |
| 7 | `menus` | 保留 | 层级导航元数据，独立版本与管理 | 1/B0 |
| 8 | `auth_policies` | 保留 | 实例身份策略，独立管理且已有B0 | 1/B0 |
| 9 | `authorization_revisions` | 保留 | 全局授权串行化/缓存版本保护行，写频率不同 | 1/B0 |
| 10 | `admin_audit_events` | 保留 | 追加安全审计，保留/不可改语义独立 | 1/B0 |
| 11 | `outbox_events` | 保留 | 业务提交与消息投递解耦的持久事实；B0增量 | 1/B0→B2 |
| 12 | `seed_versions` | 保留 | 受控初始化的幂等版本记录，已有实现 | 1/B0 |
| 13 | `user_profiles` | 并入/复用 `user_extensions` | 与学习偏好/设置同用户同生命周期，小型列组；保留profile_revision | 1/B1 |
| 14 | `study_profiles` | 并入/复用 `user_extensions` | 仅解释语/当前语两个单例字段；保留study_revision | 1/B1 |
| 15 | `study_profile_languages` | 保留；目标 `user_languages` | 一用户多母语/目标语，排序/唯一/能力校验需子行 | 1 |
| 16 | `settings` | 并入/复用 `user_extensions` | 通用偏好与前两组同生命周期；保留settings_revision | 1/B1 |
| 17 | `settings_model_bindings` | 保留；目标 `user_model_bindings` | 一用户多能力配置，凭据反查与唯一约束需要行 | 1 |
| 18 | `settings_voice_bindings` | 保留；目标 `user_voice_bindings` | 语言×用途多选择，引用标准profile或本人模型声音 | 1 |
| 19 | `avatar_assets` | 并入/复用 `file_objects` | 一份已验证头像对应一个file对象；专用purpose/像素/处理版本足够 | 1 |
| 20 | `provider_credentials` | 保留；目标 `user_provider_credentials` | 多Key独立撤销/版本/加密和权限，不入扩展行 | 1/B2 |
| 21 | `credential_capability_checks` | 并入/复用 `ai_runs` | 一次显式测试对应一个AiRun，运行已有结果/版本/结束时间 | 1/B2 |
| 22 | `auth_sessions` | 保留；目标 `user_auth_sessions` | 多设备/受众，独立持久撤销与到期清理 | 1/B1 |
| 23 | `auth_challenges` | 保留；目标 `user_auth_challenges` | 可多次签发，单次消费/过期/安全版本独立 | 1 |
| 24 | `auth_challenge_deliveries` | 条件保留；目标 `user_auth_challenge_deliveries` | 同挑战虽至多一份，短期可解密材料与摘要的访问/销毁边界不同 | 1/条件 |
| 25 | `role_inheritances` | 保留；目标 `role_inheritance_links` | 角色有向关系需无环/影响集合校验 | 1 |
| 26 | `role_grant_boundaries` | 保留 | 授予对象/权限多行上限，防提权需事务校验 | 1 |
| 27 | `permission_dependencies` | 保留；目标 `permission_dependency_links` | 多对多静态依赖，发布注册和反查 | 1 |
| 28 | `menu_permissions` | 保留；目标 `menu_permission_links` | 菜单多权限all/any，关系不同于实际授权 | 1 |
| 29 | `model_catalog_entries` | 保留 | 独立模型能力目录，被多Key绑定/运行引用 | 1 |
| 30 | `voice_catalog_entries` | 保留 | 模型下多语言声音项与独立可用性 | 1 |
| 31 | `language_capabilities` | 保留 | 受控语言及多能力标志，发布版本而非任意字符串 | 1 |
| 32 | `feature_flags` | 保留 | 发布功能开关影响全局策略，独立于个人偏好 | 1 |
| 33 | `runtime_limit_policies` | 保留 | 实例/默认/共享目录多维限额，非计数事实 | 1 |
| 34 | `user_runtime_limits` | 保留 | 每用户多维覆盖，管理权限不同于本人偏好 | 1 |
| 35 | `user_storage_states` | 保留 | 每用户唯一但高频预留/结算锁必须隔离资料写入 | 2 |
| 36 | `global_storage_states` | 保留 | 独立系统容量根，禁止owner为空混入私人表 | 2～3 |
| 37 | `storage_reservations` | 保留；目标 `user_storage_reservations` | 一用户多预留，独立unknown/结算/恢复账本 | 2 |
| 38 | `global_storage_reservations` | 保留 | 共享占用与私人Job的受限映射，目录服务专用 | 3 |

### 材料、阅读与考试

| 序号 | 原候选表 | 结论 / 物理目标 | 必要性与实施成本 | 阶段 |
| --- | --- | --- | --- | --- |
| 39 | `upload_intents` | 保留 | 可变临时上传/租约与不可变文件不同生命周期 | 2（头像切片提前） |
| 40 | `file_objects` | 保留 | 不可变字节身份、验证和GC，被多业务引用 | 2（头像切片提前） |
| 41 | `material_imports` | 保留 | 上传前意图/显式确认，可失败而无正式材料 | 2 |
| 42 | `materials` | 保留 | 库中稳定材料根及删除代次，跨内容版本保护 | 2 |
| 43 | `material_revisions` | 保留 | 一材料多不可变版本，旧结果/书签/冻结卷引用 | 2 |
| 44 | `source_assets` | 保留；目标 `material_source_assets` | 同版本多文件/图像的出处角色，文件可多处使用 | 2 |
| 45 | `source_units` | 保留；目标 `material_source_units` | 可分页加载的来源层级，稳定定位不等于显示节点 | 2 |
| 46 | `content_blocks` | 保留；目标 `material_content_blocks` | 独立稳定正文ID与偏移，多个领域节点可引用 | 2 |
| 47 | `import_issues` | 保留；目标 `material_import_issues` | 多位置/多阶段问题独立关闭，与源版本不同可变性 | 2 |
| 48 | `linguistic_analysis_versions` | 保留；目标 `material_analysis_versions` | 一内容版本多算法版本，重新分词不改原文 | 2 |
| 49 | `sentences` | 保留；目标 `material_sentences` | 一块多句，范围/回跳/音频引用需独立ID | 2 |
| 50 | `tokens` | 保留；目标 `material_tokens` | 多token与词形/读音检索，不把全书标注塞JSON | 2 |
| 51 | `novel_manifests` | 并入/复用 `material_revisions` | 每源版本唯一头，共同父锁；移入可独立首次发布/冻结的结构组 | 2 |
| 52 | `novel_chapters` | 保留 | 一版多章与顺序，小说独立结构 | 2 |
| 53 | `novel_chapter_blocks` | 保留 | 章与源块/范围的多重映射，原文不复制 | 2 |
| 54 | `textbook_manifests` | 并入/复用 `material_revisions` | 每源版本唯一头，源发布后允许结构组首次发布；保留课本schema | 2 |
| 55 | `textbook_units` | 保留 | 独立教材树/顺序，不与小说合万能节点 | 2 |
| 56 | `textbook_lessons` | 保留 | 一单元多课，专用分页/定位与引用 | 2 |
| 57 | `textbook_content_nodes` | 保留 | 一课多角色节点，受控类型载荷而非大文档 | 2 |
| 58 | `textbook_content_edges` | 保留；目标 `textbook_content_node_links` | 翻译/答案等多对多关联，题面裁剪需独立验证 | 2 |
| 59 | `textbook_dialogue_turns` | 保留 | 可变数量轮次、说话人/顺序/朗读定位 | 2 |
| 60 | `textbook_vocabulary_rows` | 保留 | 多词表行需查询/选词，每行保留原书缺列与出处 | 2 |
| 61 | `textbook_table_cells` | 保留 | 多单元格/跨度及源定位，独立结构校验 | 2 |
| 62 | `textbook_exercise_bindings` | 保留；目标 `textbook_content_node_question_links` | 多题版本引用与隐藏依据，供练习选源/GC反查 | 2 |
| 63 | `reading_progress` | 保留；目标 `material_reading_progress` | 每材料版本一行但高频写入且归属阅读者，不能改不可变源版本 | 2 |
| 64 | `bookmarks` | 保留；目标 `material_bookmarks` | 多位置书签，独立增删与去重 | 2 |
| 65 | `reading_open_events` | 保留；目标 `material_reading_open_events` | 服务端接受的打开历史与多端幂等，行为统计依赖；需有界留存 | 2 |
| 66 | `source_rebindings` | 保留；目标 `material_source_rebindings` | 多旧/新版本位置映射，有歧义状态不能覆盖原locator | 2 |
| 67 | `exam_papers` | 保留 | 每材料唯一但草稿/ready指针及编辑代次独立于源版本；专用考试根 | 2 |
| 68 | `exam_paper_versions` | 保留 | 一卷多冻结版本，草稿与已开考历史不能混写 | 2 |
| 69 | `exam_sections` | 保留 | 多层分区/说明与题序，独立卷结构 | 2 |
| 70 | `exam_stimuli` | 保留 | 多题共享材料和媒体，可见性与叶子计分分开 | 2 |
| 71 | `exam_items` | 保留 | 多计分叶子冻结题版本/分值/依据，需逐题查询 | 2 |
| 72 | `exam_stimulus_item_bindings` | 保留；目标 `exam_stimulus_item_links` | 共享材料与多题多对多、人工确认/反查 | 2 |
| 73 | `exam_preparation_issues` | 保留 | 试卷草稿问题生命周期不同于源导入问题 | 2 |
| 74 | `exam_listening_script_sources` | 保留 | 多个外加稿/正文来源，独立于原源资产集合 | 2 |
| 75 | `exam_listening_script_versions` | 保留 | 同稿多校对版本，确认稿不可改 | 2 |
| 76 | `exam_listening_script_segments` | 保留 | 多段独立文本/偏移/说话人，是定位容器 | 2 |
| 77 | `exam_listening_candidates` | 保留 | 多次AI代次/证据与人工状态，迟到不能覆盖确认 | 2 |
| 78 | `exam_listening_candidate_items` | 保留；目标 `exam_listening_candidate_item_links` | 候选多题范围，完整核查/反向依赖 | 2 |
| 79 | `exam_listening_bindings` | 保留 | 每版本×stimulus一项人工选择，需冻结并承载播放值对象 | 2 |
| 80 | `exam_listening_synthesis_specs` | 保留 | 同binding多配置/代次，旧成功结果仍被历史引用 | 2～3 |
| 81 | `exam_listening_audio_bindings` | 并入/复用 `exam_listening_synthesis_specs` | 每spec唯一发布状态，同锁同生命周期，合入spec | 2～3 |
| 82 | `exam_playback_policies` | 并入/复用 `exam_listening_bindings` | 每binding唯一规则，无独立修订历史；随冻结卷改版 | 2 |
| 83 | `exam_sessions` | 保留 | 多考试场次，独立计时/编辑/交卷/有效成绩生命周期 | 4 |
| 84 | `exam_answers` | 保留；目标 `exam_session_answers` | 多题可变草稿→锁卷，不与不可变Attempt合并 | 4 |
| 85 | `exam_session_listening_usages` | 保留 | 每场×stimulus虽唯一，但高频计数和attempt汇总需锁 | 4 |
| 86 | `exam_listening_play_attempts` | 保留；目标 `exam_session_listening_play_attempts` | 多播放领取/首字节/续播/终态事实，不能Redis替代 | 4 |
| 87 | `exam_media_faults` | 保留；目标 `exam_session_media_faults` | 场次多资产故障独立事实，资源恢复也不清除 | 4 |
| 88 | `exam_media_fault_items` | 保留；目标 `exam_media_fault_item_links` | 多受影响叶子固定账本，冻结评分阻断与反查 | 4 |

### 收藏、学习与AI（Outbox已计入账号）

| 序号 | 原候选表 | 结论 / 物理目标 | 必要性与实施成本 | 阶段 |
| --- | --- | --- | --- | --- |
| 89 | `collection_items` | 保留 | 本人多种收藏根，包含原有tombstone及可合并附属列 | 1/B1→3 |
| 90 | `tags` | 保留；目标 `library_tags` | 可复用标签目录，与收藏多对多 | 3 |
| 91 | `collection_tags` | 保留；目标 `collection_tag_links` | 真实多对多，双向筛选/删除校验 | 3 |
| 92 | `vocabulary_notebooks` | 保留 | 独立词本多实例，删除只解除归类 | 3 |
| 93 | `notebook_items` | 保留；目标 `vocabulary_notebook_collection_links` | 同条目入多本，多对多及入本时间 | 3 |
| 94 | `collection_merges` | 并入/复用 `collection_items` | 源收藏壳已经保留且只一个去向，映射移入源行 | 3 |
| 95 | `collection_selection_snapshots` | 保留 | 跨页批量动作需冻结边界，独立失效/幂等 | 3 |
| 96 | `collection_selection_members` | 保留；目标 `collection_selection_item_links` | 选择可很大且逐项校验/执行，需明细而非数组 | 3 |
| 97 | `csv_import_batches` | 保留 | 预览/确认/分批提交/恢复根，与Job不等价 | 5 |
| 98 | `csv_import_rows` | 保留 | 多行独立错误/选择/提交状态，CSV不能当一JSON | 5 |
| 99 | `photo_word_imports` | 保留 | 独立上传/显式识别/预览/确认生命周期 | 3 |
| 100 | `photo_word_candidates` | 保留；目标 `photo_word_import_candidates` | 多候选/代次和逐项收藏结果，支持部分失败 | 3 |
| 101 | `exercise_question_roots` | 保留 | 稳定题根保护多个版本/引用/作废，不能锁不存在概念 | 1/B2→4 |
| 102 | `exercise_questions` | 保留 | 一根多不可变题版本，题面与依据投影分离 | 1/B2→4 |
| 103 | `question_grading_bases` | 保留 | 每题多依据版本/来源/确认，独立隐藏读取 | 1/B2→4 |
| 104 | `question_source_refs` | 保留 | 题目多来源/考察点，删除GC与权限反查 | 1/B2→4 |
| 105 | `assessment_targets` | 保留；目标 `question_assessment_targets` | 一评分叶子可测多个词/技能，学习证据关联 | 4 |
| 106 | `exercise_selection_snapshots` | 保留 | 多来源AI选源/抽样及事实边界，与批量修改快照不混用 | 4 |
| 107 | `exercise_selection_candidates` | 保留 | 多来源候选、排除原因、稳定版本/抽样，计划共享保留 | 4 |
| 108 | `ai_exercise_plans` | 并入/复用 `exercise_sets` | 确认与产出集一对一，同归属/Job；不可变字段组合并 | 4 |
| 109 | `ai_exercise_plan_sources` | 并入/复用 `exercise_selection_candidates` | 重复selected候选快照；改持久引用及同父锁GC防误删 | 4 |
| 110 | `exercise_sets` | 保留 | 确认前不创建，确认后状态与冻结计划同一根 | 1/B2→4 |
| 111 | `exercise_set_items` | 保留 | 一个集多题，发布的固定题序与分值 | 1/B2→4 |
| 112 | `practice_sessions` | 保留 | 同集可多次练习，状态独立于集 | 4 |
| 113 | `practice_session_items` | 保留 | 多题进度/跳过/已提交引用，与原集解耦 | 4 |
| 114 | `question_attempts` | 保留 | 每次提交不可变、重做追加，评分指针独立 | 4 |
| 115 | `learning_acceptance_counters` | 保留；目标 `library_learning_acceptance_counters` | 每库唯一但高频接受顺序锁，不能并入资料/库根 | 4 |
| 116 | `answer_exposures` | 保留 | 多辅助曝光事实，用接受顺序决定训练/测验 | 4 |
| 117 | `grading_runs` | 保留 | 同作答/场次多代次评分，活动/有效分离 | 4 |
| 118 | `grading_results` | 保留 | 每run多评分叶子，分数/依据/反馈独立查询 | 4 |
| 119 | `grading_review_requests` | 并入/复用 `grading_results` | P0每结果一次只读open反馈，无独立处理流；并入结果 | 4 |
| 120 | `learner_contributions` | 保留 | 整场/作答替换贡献的事务单元，与多词证据不同基数 | 4 |
| 121 | `effective_learning_evidence` | 保留 | 一贡献多词/技能证据，独立重放/索引 | 4 |
| 122 | `vocabulary_learning_states` | 保留；目标 `collection_word_learning_states` | 按词内容版本投影，频繁重放不写收藏正文 | 4 |
| 123 | `mistake_occurrences` | 保留 | 多不可变历史错误，纠正后仍保留 | 4 |
| 124 | `mistake_projections` | 保留 | 按根题/考察点当前状态，与多次历史不同基数 | 4 |
| 125 | `mistake_favorites` | 并入/复用 `mistake_occurrences` | 每私有occurrence至多本人收藏，独立字段组已可保留语义 | 4 |
| 126 | `learner_profiles` | 保留；目标 `learner_language_profiles` | 每目标语统计投影，与人工偏好不是同一对象 | 4 |
| 127 | `diagnosis_reports` | 保留 | 多窗口/事实版本报告，模型结果不可变 | 4 |
| 128 | `diagnosis_evidence_refs` | 保留；目标 `diagnosis_report_evidence_refs` | 报告多证据/出处，权限/GC反查 | 4 |
| 129 | `agent_threads` | 保留 | 内部上下文根/轮次/删除代次，不是用户聊天产品 | 4 |
| 130 | `agent_messages` | 保留；目标 `agent_thread_messages` | 多轮/多角色历史，版本化SDK读取 | 4 |
| 131 | `agent_message_attachments` | 保留 | 消息多图及草稿绑定，附件独立过期/版本 | 4 |
| 132 | `cards` | 保留 | 一次运行多卡、逐卡收藏与出处，和消息成功不同 | 4 |
| 133 | `ai_feedback` | 保留 | 一个结果可独立反馈，跨explanation/card两类目标；不污染各结果存储 | 3～4 |
| 134 | `explanations` | 保留 | 完整不可变模型成果，独立于来源/查询绑定 | 3 |
| 135 | `source_result_bindings` | 保留 | 多来源引用同成果，授权/保留/书内查询入口 | 3 |
| 136 | `material_learning_indexes` | 并入/复用 `source_result_bindings` | 每binding唯一且可由binding+当前lookup查询，合入索引列 | 3 |
| 137 | `learning_lookup_states` | 保留 | 稳定查阅键跨配置选用结果，和严格生成键非一对一 | 3 |
| 138 | `generation_slots` | 保留；目标 `learning_generation_slots` | 严格配置调用并发/unknown/fence，独立于查阅选用 | 3 |
| 139 | `audio_assets` | 保留 | 一个合成多片段/状态，独立持久成果根 | 3 |
| 140 | `audio_segments` | 保留；目标 `audio_asset_segments` | 多音频文件/时间映射，真实成品独立验证 | 3 |
| 141 | `playback_manifests` | 保留 | 播放顺序可组合多资产、与单asset不是一对一 | 3 |
| 142 | `playback_manifest_segments` | 保留 | 清单/片段多对多及序号/源映射 | 3 |
| 143 | `global_word_entries` | 保留 | 独立受控公共词音身份，不能私人owner空值混表 | 3 |
| 144 | `global_voice_profiles` | 保留 | 稳定声音profile根/当前指针/默认选择 | 3 |
| 145 | `global_voice_profile_versions` | 保留 | 多不可变声音修订，旧音频保留准确配置 | 3 |
| 146 | `global_word_audios` | 保留 | 共享成品与私有文件权限/保留边界不同 | 3 |
| 147 | `global_word_lookup_states` | 保留 | 跨profile版本选用，独立于严格生成槽 | 3 |
| 148 | `global_word_generation_slots` | 保留 | 共享租约/生产者映射需专用scope，不泄露私人Job | 3 |
| 149 | `collection_word_audio_refs` | 并入/复用 `collection_items` | 每收藏唯一当前词音选择，可并入条目用代次保护 | 3 |
| 150 | `speech_requests` | 保留 | 多来源/多次请求及本人等候关系，不等于共享生产Job | 3 |
| 151 | `jobs` | 保留 | 用户授权长任务/恢复/取消根，调度扫描需要独立状态 | 1/B2 |
| 152 | `job_stages` | 保留 | 一个Job多已提交阶段，重启恢复边界 | 1/B2 |
| 153 | `ai_runs` | 保留 | 一个Job可多模型阶段/运行，也承载短Key测试 | 1/B2 |
| 154 | `external_call_attempts` | 保留 | 一个run多真实供应商尝试，unknown/用量独立事实 | 1/B2 |
| 155 | `model_call_usages` | 并入/复用 `external_call_attempts` | 每attempt一份用量，同锁同保留期；合并免重复元数据与JOIN | 1/B2 |
| 156 | `inbox_events` | 保留 | 消费者×event去重与业务结果同事务，保留重放窗口 | 1/B2 |
| 157 | `idempotency_records` | 保留 | 用户请求重放/响应映射，不等于消息消费去重 | 1/B1→B2 |
| 158 | `notifications` | 保留；目标 `user_notifications` | 一Job可多安全事件提示且独立已读/留存，不并入Job | 2 |

## 5. 实施复杂度与落地门槛

| 切片 | 主要成本 | 收敛后的实施约束 |
| --- | --- | --- |
| B1身份/最小收藏 | 中：安全版本、注册原子性、跨账号隔离 | 一个扩展行、三个组CAS；只实施B1合同用到的收藏列，不提前建完整材料/考试 |
| B2最小任务闭环 | 高：持久阶段、重复投递、unknown、撤权 | Job/Stage/Run/Attempt各自解决一对多和恢复；用量同attempt原子补齐，不引入第二账本 |
| 完整账号/管理 | 高：继承/deny/授予边界/最后管理员 | 关系表保留，采用既有全局授权根；不额外创建可独立修改的Casbin影子策略表 |
| 材料/阅读与准备 | 高：源版本/定位、多类型发布、文件GC | 小说/课本合并头但分别校验；试卷、脚本、候选/确认仍分生命周期。阅读打开历史按现行行为统计要求有界保留 |
| 缓存/TTS/共享词音 | 高：引用保留、跨配置迟到、私有/公共隔离 | 先实现私有路径，再按共享目录功能增加独立scope；lookup与严格slot不可合并；无供应商调用的resolve不能建工作流 |
| 练习/考试/证据 | 高：冻结、计序、评分代次、投影重放 | 保留不可变事实与当前投影；同阶段不重复维护计划来源/评分反馈附表；播放计次必须PG账本 |
| CSV（阶段5） | 中高：预览、逐行幂等、部分失败/恢复 | 到CSV切片才建立批次/行；复用上传和既有收藏，不按材料导入构造万能流程 |

表数并非完成度或工期。剩余复杂度主要由已确认的考试听力、重评学习证据、完整RBAC、可靠任务和共享音频要求产生；本轮不通过删产品要求降低数字。若后续真实访问/并发样本证明某保留拆分无价值，随对应切片再作有证据的局部调整；新增表同样需要基数/生命周期/锁/查询理由。

本次只做文档及映射核对，不执行DDL、并发/故障/EXPLAIN或应用测试。[本轮review记录](../delivery/reviews/2026-09-25-database-convergence.md)登记实际检查与独立复核，不勾选工程验收。
