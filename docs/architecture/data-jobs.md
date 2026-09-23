# 数据约束、事务与持久任务

状态：设计基线 v0.1，2026-09-22，未实现。此文是跨功能的持久化/并发契约，功能细节见 [功能索引](../delivery/coverage.md)，权限见 [RBAC](authorization.md)。不是已经存在的 DDL。

## 1. 通用数据规则

- PostgreSQL 是身份撤销、权限、业务状态、任务和审计的真相；Redis 只承载可丢失的会话材料/缓存/通知/限流，Kafka 只传事件，MinIO 保存被数据库引用的私有对象。
- Haruka 使用独立数据库/账号；P0 用户数据采用同库同 schema 共享表，服务与仓储强制接收由受信任身份构造的 ScopeContext。P0 不启用 RLS，不把数据库描述为能自动阻止任意 SQL 跨用户访问；管理元数据范围与本人私有数据仍分开。
- ID 推荐应用生成 UUID；客户端生成 request/operation/idempotency ID 不等于业务对象所有权。库内私有聚合保存固定的 owner_user_id、library_id；用户级资源按数据库规范登记权威 user_id/owner 列，不重复添加另一套所有者列。两者均不通过修改归属转移记录。数据库不使用物理外键/组合外键；保留 PK、UNIQUE、NOT NULL 和行内 CHECK，跨表引用由服务事务按 ScopeContext 校验所有父/目标适用的归属、版本与状态。
- 时间采用服务端 UTC timestamptz，API 为带 Z 的 ISO 8601。created_at/updated_at 的字段、默认值与更新责任按 [数据库规范](../engineering/database.md) 复用 MyHome 约定，批量/原生 SQL 路径也必须满足，不能仅依赖 ORM 路径。客户端时间只用于体验，考试截止、Token、幂等过期由服务端判断。版本/revision 使用单调整数。
- 计分用 PostgreSQL NUMERIC 与 Python Decimal；协议以十进制字符串传输，推荐最多两位小数，ROUND_HALF_UP 仅在契约指定的评分边界执行。禁止浮点累加后展示错误满分；修改精度需要协议迁移。
- 内容原文与出处 ID 不由模型生成，稳定偏移/Unicode 转换以 [出处协议](../contracts/content-locator.md) 为准。JSONB 用于版本化可变题型/卡片载荷，不把用户、逻辑引用列、状态与幂等约束全部藏在 JSON。
- 常见索引从 owner/library + 列表排序/状态开始；不能上线无限无条件 count/全表管理查询。最终 DDL 和 EXPLAIN 基于样本确认，不在文档阶段猜测性能已达标。

## 2. 领域关系与必要约束

| 聚合 | 关键字段/关系 | 必须保证 |
| --- | --- | --- |
| User/Library/UserProfile/StudyProfile/Settings | User的email_normalized/status/password_version/安全epoch/authz_version；Library.owner；本人资料、语言档案和设置各自revision | 邮箱唯一、每用户一个Library及每类单例聚合；注册同事务初始化；任何密码哈希替换推进password_version；登录身份与可选资料/学习偏好分离，普通用户无跨用户资料读取 |
| AuthSession/AuthChallenge | user、audience、绝对期限、epoch、撤销/消费状态、purpose、摘要 | 会话/挑战不得跨用户/受众/用途；PG 撤销先于任何缓存失效通知 |
| Role/权限关系/Revision | 见 RBAC | 继承 DAG、合法范围、唯一绑定、版本、授予边界、最后管理员约束 |
| Material/Revision/StructureNode/ContentBlock | 固定material_type、当前版本指针、状态、delete_generation、源结构/原文/定位 | revision 不可变；同库引用；节点不能跨版本拼接；AI 不覆盖原文/类型，共用内容不直接构成万能阅读器 |
| NovelManifest/Chapter、TextbookManifest/Unit/Lesson | 各自的内容版本、领域节点、源块/课本Exercise引用与质量状态 | 两套专用产物，只引用匹配类型/版本/所有者的来源；试卷使用下方独立Exam聚合 |
| LinguisticAnalysis/Sentence/Token | 内容版本、分析/规则/词典版本、语言、原文span | 派生标注不改canonical_text；新切句不能静默改变旧sentence_id的含义 |
| FileObject/UploadIntent | owner、临时staging_key、独占final_key、用途、最终摘要/实际大小、状态、到期 | 客户端仅写临时对象；后端固定不可变final对象并验证后才发布；完成幂等 |
| AvatarAsset | owner、源UploadIntent、受控格式/像素/摘要、final_key、revision/状态 | 只从avatar用途临时对象真实解码、去元数据、限制像素并重编码发布；资料指针原子替换，外链/材料对象/他人资产不能充当头像，旧资产受控GC |
| CollectionItem/Tag/Bookmark/ReadingProgress | kind、词/笔记、出处快照、current_position、小说max_progress、revision | 标签关系同库；小说当前/最远分离，课本位置不表示完成度，考试进度另存；删除材料后收藏文本仍存在 |
| VocabularyNotebook/NotebookItem | owner/library、名称/目标语、成员CollectionItem和revision | 多本多对多、单语匹配、关系唯一；同条目多本不复制进度，删本不删词；改词语言与成员增改共用父锁 |
| VocabularyLearningState/EffectiveLearningEvidence | item/learning_revision/skill、有效成绩证据、mastery/策略/证据版本 | [词汇学习](vocabulary-learning.md)只从有效证据派生；客户端/CSV不得写mastery，重评按原接受时间重放；无ReviewSchedule/due/SRS |
| MistakeOccurrence/MistakeProjection/MistakeFavorite | 每次可靠错误事实、根题/考察点当前状态、用户独立收藏关系 | [AI习题](../modules/ai-exercises.md)按effective评分幂等记录；重评/纠正重算不删历史，收藏不改错误状态 |
| Exercise/PracticeSession/Attempt/GradeRun | 冻结题目与依据、答案、提交幂等键、评分代次 | 同一提交不重复 Attempt；规则/AI 成绩有来源；有效成绩与历史分开 |
| ExerciseSelectionSnapshot/AiExercisePlan | 本人规范化单词本/收藏/教材/错题/诊断及时间/掌握/错误条件、as_of/时区、候选/版本/抽样/expiry；不可变生成计划 | [AI习题](../modules/ai-exercises.md)中预览计数/明细同一快照，确认短事务重验后与Job/Outbox提交；无复习计划/机会/日额度 |
| ExamPaper/Version/Item/GradingBasis | 题面/题序/分值与依据版本 | ready 版本不可变；题面 DTO 不含答案/rubric |
| ExamSession/Response/GradeRun | 固定版本、deadline、edit_epoch、response_revision、grade_generation | 保存/交卷在场次行锁内；单题答案唯一；提交后不可修改 |
| LearnerContribution/Profile | source_kind + session/attempt + item 的唯一贡献键、effective_grade_id | 重评替换贡献不追加重复错误；needs_review 不进入正式统计 |
| AgentThread/Message/AiRun/Card | owner、SDK/协议/模型/Prompt版本、run状态、结果引用 | 单线程轮次占用/版本校验；消息与可收藏卡片的提交状态分离 |
| Explanation/SourceResultBinding/MaterialLearningIndex/LearningLookupState/GenerationSlot | 完整结果、源/语境/用途、查阅键/严格生成键；LookupState维护跨配置的选用run/effective/代次 | 成功后同事务建历史绑定，通过共同查阅代次才更新当前索引；不同语境不误用，严格键slot只合并调用；已有结果不依赖Redis或本机存续 |
| AudioAsset/Segment/Manifest | owner、内容/声音/模型/参数摘要、格式、对象与句子引用 | 用户内去重；实际格式与Content-Type匹配；未完成产物不播放 |
| GlobalWordAudio/GlobalWordGenerationSlot | system_catalog标准词条/读音/profile、全局合成键、对象版本及内部生成租约/代次 | 仅[标准收藏词音](learning-cache.md#51-收藏库标准单词发音的全局缓存)跨用户去重；发布/消费走专用目录服务，个人引用/Job/凭据/费用仍隔离，不给私有AudioAsset增加owner空值旁路 |
| ProviderCredential | owner、provider、密文、credential_version、encryption_key_version、row revision | 用户换Key/撤销更新credential_version，主密钥重加密只更新encryption_key_version，二者不混用；DTO只返回掩码，模型能力选择由上方Settings引用 |
| Job/JobStage/ExternalCall | actor/owner/audience、权限引用、输入版本、阶段、租约、预算 | 状态CAS、阶段幂等、调用结果不确定单独记录 |
| Outbox/Inbox/IdempotencyRecord | event_id、schema、资源引用、请求摘要、游标/结果引用 | 已提交事实可重投；重复消费不重复业务；不放秘密/正文 |
| AdminAuditEvent | actor、target、动作、版本/安全差异、结果 | 与成功变更同事务；应用不可更新/删除；留存独立于Loki |

状态细分见各功能；表名是逻辑职责。“必须保证”同时包含服务层逻辑关联校验与数据库行内/唯一约束，并不表示由外键或跨表 CHECK 执行。迁移可以把小型值对象合表，但不能省略相应校验；完整建表、ScopeContext、逻辑引用、锁顺序和字典登记以 [数据库规范](../engineering/database.md) 为准。

### 公共逻辑关系与来源

以下保留产品逻辑模型中的跨功能关系，不复制模块 DTO，也不把字段示意当最终 DDL：

- User拥有私有Library并承载不可由资料接口修改的登录/状态字段；UserProfile保存显示名、头像引用及可选出生年份/性别，StudyProfile保存母语/解释语言、target_languages及各语言水平/目标，Settings保存模型、时区、显示/阅读等偏好，三者各自revision。界面locale、母语与target_languages分开；可选人口字段默认不进入AI。LearnerProfile按学习者与目标语派生词汇、语法和技能统计，并保留更新时间/事实版本；修改语言偏好不改写原Attempt或删除历史。设置字段和诊断口径分别见[设置](../modules/settings.md)、[收藏与练习](../modules/vocabulary-practice.md)。
- Material 的来源格式、唯一业务类型 material_type、语言与导入报告分开。MaterialRevision 保留不可变源结构/ContentBlock，各类型独立编排 NovelManifest、TextbookManifest 或 ExamPaperVersion；语言分析版本中的 Sentence/Token 引用原文 span。类型固定、另类型重新处理及内容/标注版本边界唯一维护在 [三类材料契约](../contracts/material-types.md)。重新解析失败不切当前版本，收藏重绑失败保留快照；保留/删除期限仍按第 7 节处理。
- Selection/Bookmark 关联学习者、句子/内容版本与选区范围，读取和保存仍受本人归属约束。Selection 是逻辑选区职责，不因此要求为每次临时划选创建数据库记录；持久书签/收藏按相应业务流程保存。
- CollectionItem 维护 kind、词句/lemma/语言、上下文、状态、标签、笔记与 origin（selection/agent/exercise/csv_import/photo_import）；来源引用与文本快照分开。CollectionItem、Attempt 和 Card 均能关联可追溯 locator，CSV/拍照导入单词允许为空，不能伪造材料出处。定位编码与重绑规则只在 [出处契约](../contracts/content-locator.md) 定义。
- Exercise 区分 extracted/generated/derived_from_mistake，题面/题型载荷、答案、解析和评分依据各有职责；生成题必须追溯至CollectionItem、MistakeOccurrence、Attempt或ContentBlock，引用由服务事务校验同库归属及版本/状态。Attempt关联题目与本人作答、得分依据、错误标签和用时；冻结版本及评分发布规则防止后续改题/重评改写历史证据。
- AgentMessage 保存结构化文字与卡片结果；Card 保存类型、版本化载荷及合法来源。消息保存和卡片成为可收藏业务结果不是同一成功条件；用户内容、模型候选和生成例句的标识按 [AI 与朗读](../modules/ai-speech.md) 维护。
- CsvImportBatch 保存用户/资料库、协议版本、批次状态、进度与结果引用，不能用外部 CSV ID 决定所有者；导入的 preview/confirm/重复策略字段以 [CSV 契约](../contracts/vocabulary-csv.md) 为准。Job/外部调用记录和 CSV 批次各自表达领域状态，不互相代替。

## 3. 事务边界

| 事务 | 在同一提交内完成 | 事务外执行 |
| --- | --- | --- |
| 注册 | User/Library/UserProfile/StudyProfile/Settings/默认角色/必要通知Outbox | 发邮件、创建登录会话 |
| 资料/学习档案/设置更新 | 本人范围、字段白名单/field mask、expected_revision、单聚合更新与Outbox | 头像文件处理、客户端缓存刷新；一个聚合成功不与另一个页面保存伪装成全局原子 |
| 头像发布/替换 | 完成验证后的AvatarAsset、UserProfile expected_revision、当前指针与Outbox | staging清理、旧无引用资产GC、客户端私有缓存刷新；解码/重编码在短事务外完成 |
| 撤销/改密/禁用 | 改密锁内复核password_version/security_epoch/当前会话；哈希替换、版本/epoch、持久会话撤销或状态/权限版本、审计、Outbox | 密码验证与新哈希计算、Redis删除、客户端通知；提交确认丢失不自动重放 |
| 角色/菜单/策略管理 | 范围检查、预期revision、修改、版本、审计、Outbox | 快照预热/通知/Loki投递 |
| 上传完成/导入 | UploadIntent状态、FileObject验证引用、Material/Job/Outbox | 文件内容解析、AI、对象读取 |
| 收藏/CSV批次 | 权限/归属/版本/幂等、业务记录、批次游标 | 下一批处理、日志转发 |
| AI习题确认 | 本人选择快照/所选来源和错题投影版本/权限、幂等、不可变AiExercisePlan、Job/Outbox | 模型生成；Worker不重跑动态筛选或补入未选来源，开始习题另建会话 |
| 考试保存/交卷 | 场次锁、权限/截止/edit_epoch、最终答案、锁卷、唯一评分请求/Outbox | AI批改与客户端推送 |
| 评分发布 | run/代次验证、有效成绩指针、学习贡献替换、可靠错误的MistakeOccurrence幂等写入、汇总状态、Outbox | 错题/掌握投影重算、诊断/通知，不重复累计 |
| 删除材料 | tombstone/generation、拒绝新引用、取消意图/Outbox | MinIO延迟回收、缓存清理 |
| Worker阶段完成 | 有效租约/代次、状态/版本/权限、阶段产物与下阶段Outbox | 下一次外部调用 |

服务层开启/提交事务，仓储不私自 commit。外部 HTTP、哈希计算、文件解压/渲染和模型等待不持有数据库长事务。并发管理修改锁顺序固定为策略 revision → 用户/会话 → 角色/绑定 → 业务聚合；锁冲突/死锁只重试已经证明安全的短事务，禁止把付费调用包在事务重试里。

新增、合并、重绑逻辑引用时，服务须在提交事务内验证全部父/目标，不能只在预览或路由阶段查一次。引用写入、父对象 tombstone 和物理回收遵守数据库规范的同一父行锁/代次协议及稳定锁顺序，避免检查后删除；Worker 最终写入也不能绕过。这里仅定义适用范围，不另行维护一套无外键并发算法。

### 上传完成与不可变对象

S3预签名上传不等同一次性不可变文件：[S3官方说明](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html)允许有效期内重复使用且同键覆盖；MinIO兼容行为须接入验证。因此首版统一临时上传→服务器独享最终对象→最终校验→事务发布。

UploadIntent从created/uploading到finalizing时取得completion_generation/租约；后端为该代次生成唯一final_key，流式复制时有大小/时间限制，完成后对final对象校验真实格式、完整摘要和预期大小。final_key永不签发客户端PUT且应用不原位覆盖已发布对象。若临时源在复制前/中变化，最终字节与意图声明不符就拒绝；不能仅校验staging HEAD后让Worker读取同一个可变键。

校验完成的PG事务重查所有者/权限、意图未过期、generation和未取消状态，再创建FileObject/Material/Job/Outbox并置completed。重复完成返回同一对象；失去租约/取消后的最终对象不能发布，孤立final和staging进入有界GC。对象拷贝和PG不是一个原子事务，先有对象后有引用，失败只产生待回收私有孤立对象，不产生可读未验证数据。照片识词、试卷和普通材料全部使用该发布协议。

## 4. PG 与 Redis 会话一致性

会话元数据/撤销属于 PG，刷新摘要/空闲状态属于 Redis，具体传输见 [认证设计](authentication.md)。身份成立必须同时满足两者；不是双写最终一致后暂时放行。

新建会话先登记 PG，再初始化 Redis，全部完成才向客户端发凭据；部分失败留不可使用的记录并清理。单会话强退写 revoked_at；所有会话、改密或端登录撤权增加相应安全 epoch。成功响应表示 PG 撤销事务已提交，新请求必须核对它，所以 Redis 删除失败不延迟撤销。后台清理 Redis 只负责收敛和空间，不承担正确性。

Redis 全失、数据库不可用或无法确认当前策略均失败关闭；无需回滚已提交学习数据。每个 API/Worker 的 DB 与缓存版本必须相符；不得从只读副本的滞后数据授权撤权敏感请求。

## 5. Job、Outbox 与外部调用

### 接受与状态

重大异步操作先返回 202 + job_id。Job 基础状态：queued → running → succeeded；可进入 retry_wait、blocked、failed、cancel_requested、cancelled。业务层的“待Key/待复核/部分批改”保留在对应资源中，不能仅用一个Job状态表达成绩。

Job 保存不可变输入版本/摘要、actor/owner/audience、所需权限、预算上限、用户付费意图、取消状态；credential_id仅是引用，开始每个新付费步骤时检查当前凭据所有者、状态/版本和授权。账户正常退出不撤销已提交任务授权；角色/账号变更会阻断后续步骤。

Outbox 发布进程领取带租约事件，Kafka确认后标记发布；发布成功但标记前崩溃可重复发布。消费者使用 event_id/JobStage唯一键、当前状态CAS和租约代次 fence 防重复：过期Worker即使恢复，也不能提交覆盖新Worker结果。Kafka消息确认在DB事务提交后；Inbox去重与业务结果同事务。

推荐每类配置 concurrency、max_attempts、timeout、backoff、lease/heartbeat、预算；429遵循供应商Retry-After。新付费调用次数含SDK/HTTP/Worker所有重试，共享同一计数；重试不能增加用户未授权的总预算。Kafka不可用则Outbox积压、Job维持queued并可见，不丢已受理操作。

### 外部副作用不确定

在调用供应商前写 ExternalCall(attempt_id、input_digest、provider/model/version、预算预留、started)；请求结束后记录 succeeded/failed/unknown 与产物引用。超时、断线或进程在收费后崩溃会形成 unknown，不能当作“没执行过”无限重试。供应商确有可验证幂等接口时才传兼容幂等键；否则默认停止自动付费重试并提示用户可能重复计费，用户显式重试生成新attempt和受控预算。

结果已返回但发生撤权/删除/取消时，固定系统职责可最小保存封存产物/用量用于对账与清理，不使其成为可见业务结果、不继续付费步骤。Key已撤销时不使用旧解密缓存发起调用。取消无法保证撤回在途收费；收到确认的取消结果后不再开始新步骤。

非付费的解析/数据库短事务可在类型化错误白名单内有界重试；确定不可恢复错误进failed/DLQ。恢复只能从持久完成的阶段继续，不重置整个Job后无条件重跑。管理端重试仅重投允许的非付费阶段；涉及新付费attempt由所有者显式确认。

## 6. 评分代次与学习贡献

普通练习和考试共享下列发布规则，各自题目/场次状态独立：

1. 场次/Attempt保存 grade_generation、active_grade_run_id、effective_grade_run_id。初次请求与每次显式重评在聚合行锁中分配新generation；同一generation只有一个run。
2. 首版每聚合只允许一个活动run。重评已有活动run时要求先取消/等待，API返回409而不是悄悄并行。重试未完成题沿用同一run/generation，重评才创建新的版本。
3. 旧run取消后迟到的供应商结果只保存历史，发布要求 active_run_id/generation 和租约代次仍匹配。显式重评不立即删除旧effective指针，页面标“重评中”，旧有效成绩仍可查。
4. 有效成绩切换在单事务内CAS检查最新generation，校验全部必须评分项完成且无needs_review，再切effective指针并按 source + session/attempt + item 替换LearnerContribution；汇总可在同事务更新或由带版本事件重算，禁止对旧贡献再加一遍。
5. 初次部分评分可显示run的部分分数，但尚未作为完整effective成绩。确认的单题是否用于即时学习统计采用一条规则：首版仅整次评分成功发布后回流；needs_review/failed/partial不回流正式掌握度。新一轮失败保留原有效成绩和统计，不混合两轮题分。

考试的[必要媒体故障](../modules/exams.md#必要媒体故障的场次处理)确认事实与锁卷共用场次行锁，只在允许作答时确认提交；确认后才向客户端报告已成立，不能仅存遥测。事实绑定冻结版本/资产和服务端推导的叶子题，锁卷保留其revision。评分领取/恢复和最终发布都读取持久事实，发布CAS除grade_generation外检查故障revision且无受影响项；有确认故障时相关题needs_review，不走空答零分，也不切effective或发出学习贡献。媒体恢复或Worker重启不清除该场次影响，锁卷后新报告不追认历史故障；P0以模块规定的新场次重考处理，不引入人工改分或自动撤销既有有效成绩。

词汇掌握按[学习证据协议](vocabulary-learning.md)消费此发布：普通习题的边界是该Attempt的effective评分，考试是整个场次有效成绩。只有冻结到本人词条/学习版本/能力及评分项的明确映射才能回流，不能从总分猜每词掌握；投影按原接受时间、稳定业务键及策略版本重放，没有时间调度。可靠错误/部分正确同时按[错题账本](../modules/ai-exercises.md#2-服务端错题账本)写入唯一MistakeOccurrence并异步重算状态；重评替换贡献、标记旧错题状态而不删除历史。内容改版/删除阻止迟到结果复活，删词本不删除学习或错题记录。

该规则消除“旧评分最后返回就覆盖新成绩”。允许并发run或逐题提前回流属于未来协议变更，必须补竞态和统计迁移验收。

## 7. 删除、版本保留与对象回收

材料删除采用逻辑tombstone，事务推进 delete_generation，立刻从用户书库和新操作中隐藏，拒绝以旧revision创建新引用。新增引用与父删除共用数据库规范的父行锁/代次协议；只做事务前查询不足以防止并发悬空。owner/library 创建后固定，删除不通过转移所有者实现。解析/音频/AI任务提交必须比较输入的generation/revision与当前有效状态；删除前领取、删除后到达的结果不能复活材料。

收藏保留已存词句/笔记/出处快照，原文回跳显示不可用；已开始考试、已提交答卷、Attempt保留必要不可变题面/评分依据和私有题图引用以支持复盘。删除操作明确说明：移除书库原资料，已生成的个人收藏/考试记录仍保留。不是用户数据“彻底抹除”的实现，也不提供跨账号恢复。

原文件/历史revision不被永久无条件保留：只有仍被活跃场次/成绩/收藏必要回跳策略或在途安全处理引用的对象才retain；没有引用的对象进入延迟GC候选。首版推荐7天宽限，物理回收前按同一父行锁/代次协议再次检查tombstone、实际逻辑引用、generation和任务租约，不能把过期引用计数当删除依据，也不依赖数据库级联删除。GC权限只针对明确对象键与Haruka Bucket。MinIO删除失败重试，不在一个SQL事务中假装对象和数据库原子删除。

单词/句子解释和TTS的已提交版本、书内索引与来源绑定也是权威业务引用，完整规则见 [学习结果缓存](learning-cache.md)。有效业务引用期间不按短TTL/LRU淘汰付费结果；原书删除后仅书属引用可解除，独立收藏/历史业务必要引用仍按各自授权保留，旧版/在途发布也纳入共同父行锁检查。仅清理本机或Redis不触发服务端GC，临时未发布/失效孤立对象与成功结果分开处理。

未完成上传/临时OCR图/废弃生成音频有单独TTL，不能清理仍被其他有效资源引用的对象。私有内容不跨用户去重；已ready的global_word有独立公共目录引用，删除贡献者/任一收藏不移除此引用，GC须在目录父锁内复核版本、个人选用引用和在途占用。共享容量只计一份，生产者私人Job/费用记录按自己的生命周期处理。数据库迁移和运维恢复步骤见 [部署与恢复](../operations/deployment-recovery.md)，保留参数见 [运行配置](../operations/configuration.md)，不属于用户单词CSV功能。

## 8. 验收

- DAT-01：实际业务服务在真实 PostgreSQL 集成测试中，通过 ScopeContext 与事务校验拒绝跨 owner/library、错误父版本/状态及混合批量引用；不存在/他人私有 ID 统一不可访问。数据库 PK/UNIQUE/NOT NULL/行内 CHECK 分别证明主键、唯一/重复和行内条件，不声称由 FK/RLS 自动拒绝跨库引用；重复初始化/提交由相应唯一约束与服务幂等共同保证。
- DAT-02：Redis撤销删除失败、全量丢失与PG不可用时身份失败关闭；已提交学习数据不丢。
- DAT-03：Outbox重复、消费者提交前后崩溃、租约过期Worker迟到，业务仅提交一次且不会覆盖新代次。
- DAT-04：供应商收费后断线标unknown，测试无自动无限重试；取消/撤权/删Key停止后续调用。
- DAT-05：交卷/截止/保存并发、评分A取消后B生效再A迟到，不改写B或重复学习贡献。
- DAT-06：通过真实 PG 并发验证“新增/重绑引用—父 tombstone—物理回收”和解析/音频迟到提交的竞争，共用父行锁/代次协议，不产生新悬空引用或复活材料；历史考试可复盘，GC不删仍有保留引用对象，归属不可转移。
- DAT-07：授权、版本、审计、Outbox故障注入验证事务提交边界，日志平台故障不改变已提交权限。
- DAT-08：预签名重复PUT、校验前后覆盖、复制中源变更、完成/取消竞争及复制后PG失败，Worker只能读已验证final对象，孤立对象可回收。

上述是实现与测试必须满足的约束；本次未创建数据库表或执行迁移。
