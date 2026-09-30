# Haruka 数据库设计书

版本：DBDESIGN3 / v0.3，2026-09-25。所属阶段：阶段1中的数据库设计文档小阶段；设计覆盖已确认首版功能，工程按阶段1～5相关功能切片逐步落地。DBDESIGN3历史基线提交：`7fed5fc`。B0现行代码结构已由`0002_b0_identity_alignment`及生成字典对齐，见[B0增量记录](../delivery/reviews/2026-09-26-b0-design-alignment.md)；仍只有12张基础表。其余目标业务结构与Redis字段仍是设计，按功能切片实施。

DESIGN23扩充全应用NLP和OCR/ruby存储：原材料NLP的3张设计表调整为text_analysis_versions/units/sentences，token改存有界单元JSONB；总计仍142。现有Explanation/Card保存AI成品，OCR阶段成品使用FileObject/JobStage；新增R19热点标注副本。详见[统一文本分析](text-analysis.md)及[提取契约](../contracts/source-extraction.md)，本轮只改文档。

DBDESIGN4（2026-09-26，基线0f031ae）修订[AUDIT1](../delivery/reviews/2026-09-26-business-design-audit.md)的6项数据库设计问题：根级Lesson、直接题目收藏身份/唯一、共享等待请求冻结配置/执行、共享格式派生/容量/GC、实际合成出处及听力问题代码。字段和关系在既有表内补齐，目标仍142、Redis仍19类，B0字典/迁移不改；局部检查与独立复核见[修订记录](../delivery/reviews/2026-09-26-database-audit-fixes.md)。该修订不包含原型、排版协议细化或其他审查待办。

当前实施状态补充（2026-09-30）：账号/资料/身份治理已按各自交付记录验收，B2c 本人凭据与单能力任务正在实现，尚未签署验收。上文 B0 十二表是历史设计基线，不代表当前物理表总数；当前已实现结构以[生成字典](../../contracts/database-schema.json)为准，切片差异见[身份分册](database-identity.md#当前本人模型配置切片2026-09-30)与[任务分册](database-learning.md#当前凭据测试与任务切片2026-09-30)。142 表仍为完整首版目标，未交付表不计已实现。

## 1. 阅读入口与设计状态

| 分册 | 内容 |
| --- | --- |
| 本册 | 依据、公共字段、业务关系、查询/事务边界、分期迁移与待决门槛 |
| [表命名、归属与关系清单](database-relations.md) | 全部142张目标表、父表/端点、1:1/1:N/M:N、唯一约束摘要及46项改名映射 |
| [全表必要性与复杂度收敛](database-convergence.md) | 158个原候选逐项审查，目标142表；合并映射、保留理由与分期成本 |
| [账号、设置与权限表](database-identity.md) | B0 12 表核对及增量；资料、会话、凭据、目录、RBAC 与技术限额 |
| [材料、阅读与考试表](database-materials.md) | 上传与对象、三类不可变内容、出处、位置、试卷、文字听力准备与播放账本 |
| [收藏、学习与 AI 表](database-learning.md) | 单词本/CSV、题目作答、证据错题、内部查询、持久解释与音频、任务与模型用量 |
| [Redis 键与字段](redis-design.md) | 19 类键的类型、字段、TTL 初值、容量、失效、认证和恢复处理 |

**当前物理目标142张：已有B0 12张，拟新增130张（含邮件交付条件表1张）。** 对全部158个原候选审查后减少16张；未启用邮件条件时目标141张。内部alembic_version、Redis键与逻辑DTO/查询投影不计表数。各表取舍见收敛册；下一次迁移只建立当期必需结构。

DBDESIGN3采用业务归属/直接父对象命名，专用多对多关联表使用`_links`；关系基数由[完整清单](database-relations.md)明确标注，不靠表名单复数推断。本轮46项改名不改变142个实体：其中B0的`user_roles`、`role_permissions`已由0002受控迁移更名为`user_role_links`、`role_permission_links`；其余目标名仍属于待实施结构。字段、接口和Redis键保持原有契约。

设计状态严格区分：

- **已有**：当前SQLAlchemy模型、0001→0002迁移链及受管字典中的B0基础表。核对点见账号分册；已有字段的真实来源是[生成数据字典](../../contracts/database-schema.json)，不是本设计书的摘录。
- **拟新增 / 拟修改**：尚未实施的业务表与B0其余拟增列，仅为可审查设计。具体类型/长度/索引属于拟采用方案，需随业务切片验证后写入模型、迁移和生成字典。
- **待决**：产品未确定的注册/恢复、文件格式、词音目录/模型、删题语义和掌握策略等保留既有 OPEN 门槛；本书不替用户关闭。

本书是**未实现结构的设计入口**；[数据库规范](../engineering/database.md)继续维护通用工程规则，[数据与任务](data-jobs.md)维护跨模块事务，[各协议](../README.md)维护 API/出处/CSV/状态行为。实施某表时将字段说明和逻辑关系转入 SQLAlchemy 注释与 `Table.info`，生成字典单向导出；本书改为链接已实现字典并保留设计理由，不维持与模型并行修改的第二份已实现字段真相。

## 2. 设计依据与原型映射

以[产品总览](../product/overview.md)、[功能追踪](../delivery/coverage.md)、模块及专题为业务依据；[当前原型](../../prototype/README.md)用于核对用户实际入口。原型中的示例 ID、掌握百分比、计时器和虚构请求状态均不作数据库事实。

| 页面/操作 | 需要持久化的事实 | 不另建的 UI 数据模型 |
| --- | --- | --- |
| 登录/注册/本人设置 | 用户、私有库、可选资料/学习档案/设置、独立受众会话、授权与凭据版本 | 首次引导不是登录门槛；密码显隐/当前tab不建表 |
| 书库筛选、详情弹窗、直接阅读 | 材料类型/语言/标题、当前可用版本、删除代次、解析任务 | 不存每一组筛选结果，不因详情dialog复制材料 |
| 小说选区、目录与返回位置 | 稳定内容块/版本/Unicode spans、语言标注、当前位置/最远进度、书签 | 不保存每次临时划选，不新增“继续阅读”产品入口 |
| 教材单元、词表/课文/逐题练习 | 独立课本内容角色/关系、题目引用、作答及反馈 | 不用小说章节加皮肤代替教材模型，不把位置算完成度 |
| 单词本列表/详情/管理弹窗 | 六类收藏、版本化快照、词本成员、标签/笔记 | 一条收藏入多个本只增加关联，不复制学习状态 |
| 每日单词 | 本人 `kind=word` 的真实加入时间，结合当前时区换算日界线 | 不建日调度/每日配额/待复习表；CSV 来源时间不改加入日 |
| 自动判断图文查询/四类学习卡片 | 内部 query 上下文、已验证私有附件、服务端推断任务、完整结果与卡片收藏 | 不增用户聊天入口/通用回答类型，不以客户端 task_type 决定执行 |
| AI习题选源/范围/一次确认 | 固定选择快照、候选明细/版本、确认计划、生成任务、不可变题目 | 返回修改只改草稿；未确认不生成，不后台自动出题 |
| 错题详情/收藏与掌握度 | 每次有效错误、当前投影、独立收藏、可重放学习证据 | 不从按钮点击/模型自报/埋点直接写 mastery |
| 试卷准备、文字听力校对、开考/续答 | 已确认脚本与绑定、私有成品音频、冻结版本、服务端截止/编辑代次、答卷、播放 attempt | 原型本地计时不决定交卷；不开放原始音频 P1 流程 |
| 解析进度与任务提示 | Job/阶段状态/持久序号、Outbox、本人站内提示及已读时间；跳转重新验证任务/来源权限 | WebSocket/Redis 通知不成为成功或已读事实，不扩大为邮件/系统推送 |
| 管理端用户/权限/用量与审计 | 版本化关系策略、受限操作范围、供应商 attempt 用量、追加审计 | 不因后台入口建立读取用户私有内容或 Key 的旁路 |

原型样本参考[数据](../../prototype/data.js)、[收藏/查询](../../prototype/collections.js)、[习题选源](../../prototype/exercise-builder.js)、[学习卡片](../../prototype/learning-cards.js)。本次不更改原型或 Flutter 页面，也不把其交互检查算作数据库验证。

## 3. 存储边界与公共字段

| 存储 | 权威职责 | 丢失/失败策略 |
| --- | --- | --- |
| PostgreSQL / Haruka 独立 DB / `public` | 身份撤销、授权、业务内容索引/版本、结果、任务、配额预留、用量、审计 | 通过运维备份/恢复；不能靠 Redis 或埋点补造事实 |
| MinIO / 独立私有 Bucket 与前缀 | 原件、验证后的附件、私有音频及受控 global_word 成品字节 | PG 发布记录绑定校验和/版本；缺失标记 broken、优先恢复，不静默重调模型 |
| Redis | 可丢失副本、会话材料、限流及协调提示 | 普通副本回查 PG；身份材料丢失重新登录；不单独决定业务提交 |
| Kafka | PG Outbox 已提交事件的传输 | 可重投，Inbox/阶段唯一性防重复业务写入 |
| Flutter 本机 | 当前账号权限租期内的允许副本 | 可淘汰；换账号/实例/受众隔离，有限次数试卷音频不进入通用离线缓存 |

P0 不使用数据库外键、级联关系写入或 RLS；PK、UNIQUE、NOT NULL、行内 CHECK 保留。引用检查使用服务事务和共同父行锁，不能用“没有 FK”推导无需关联约束。

### 3.1 分册字段表的公共列组

分册声明某列组即逐项包含以下字段，不是待补省略项；一个字段出现一次。`B+R`、`U+R`、`L+R` 表示组合。既有 B0 表以实际字典为准，不能套组悄悄添加列。

| 组 | 物理列 | PostgreSQL 类型 | NULL / 默认 | 语义 |
| --- | --- | --- | --- | --- |
| B | `id` | uuid | 非空 / 应用 uuid4，无数据库默认 | PK，普通客户端/模型/CSV 不指定实体新 ID |
| B | `created_at` | timestamptz | 非空 / `now()` | 首次落库时间，不被普通更新或 CSV 覆盖 |
| B | `updated_at` | timestamptz | 非空 / `now()` | ORM onupdate；原生 SQL/批量/upsert 显式设数据库时间 |
| U | B 全部列 + `user_id` | uuid（user_id） | 非空 / 无默认 | 用户级权威归属列，映射 ScopeContext.user_id |
| UO | B 全部列 + `owner_user_id` | uuid（owner_user_id） | 非空 / 无默认 | 任务/AI领域沿用 owner 名称的用户级归属；与 U 二选一，不另加 user_id |
| L | B 全部列 + `owner_user_id`、`library_id` | uuid（两列） | 非空 / 无默认 | 库内作用域，由可信上下文与已验证父记录派生，创建后不可转移 |
| R | `revision` | bigint | 非空 / `1` | 可变实体 CAS，CHECK revision ≥1，不是内容版本/执行代次 |

各表仍独立注明 `scope_kind`。U 通常为 `user_owned`，L 为 `library_owned`；身份表按 `identity`，目录按 `system_catalog`，受控运维按 `system_operation`。`libraries` 为 `library_root`，不再加自引用 `library_id`。关联表、目录、审计同样具备公共时间；追加记录创建后不更新，updated_at 保持初值。

字段表中 `NN` 表示 NOT NULL，`Y/可空` 表示允许 NULL，`—/无` 表示无服务器默认；默认值以明确标注为准，不能把示例当默认。组合行列出多个同类型字段时，类型/空值分别适用每一列。状态文本及 JSON schema 由对应协议解释，各表列长度是存储边界，不等于客户端可以提交任意同长度文本。

### 3.2 类型、敏感性与索引记法

- 数量/时长/字节用 integer/bigint 且非负；分数用明确精度的 numeric/Decimal，应用拒绝 NaN/Infinity、超精度及越界输入，不能借数据库舍入掩盖非法输入。
- 语言代码、provider/model 等使用有界 varchar，规范化值与显示原文分离；源文本以不可变 text 保存，不因搜索归一化改写原文。
- JSONB 只保存版本化的题型/卡片载荷、有限设置和确定结构的值对象；JSON schema/version 必须可确定。owner、父资源、状态、代次、唯一键和热点筛选列不能仅藏在 JSON 内。
- 未逐列特记时，库内正文/来源/答案/图片/学习结果为**本人私有**；`password_hash`、凭据密文、挑战摘要等为**秘密材料**；目录为**受控系统元数据**；审计/任务调度为**受限运维元数据**。都禁止默认输出日志。每个实现列需将敏感级别写入模型扩展元数据，管理响应按白名单裁剪。
- 分册 `UQ(...)`、`IX(...)`、`CHECK(...)` 是索引/约束的逻辑规格；实施统一命名为 `uq_/ix_/ck_` 并按数据库规范缩短至 63 字节，生成字典登记最终名。未写 `DESC` 的列为 ASC；部分唯一索引明确谓词。PK/UQ 已覆盖路径不再重复建索引。
- 多态引用须有有限 `kind` 和独立 UUID/版本列，按类型白名单查目标并锁父；可选复合引用要么全空，要么全有。NULL 的唯一性不假定为“只能一条”，需要时拆成部分唯一索引。

## 4. 主要逻辑关系

以下是概念关系图，边表示服务验证的逻辑引用，**不生成数据库 FK，也不表示关系基数**。全部表的父子/多对多关系、可选单例与组合唯一见[关系清单](database-relations.md#2-全部142张目标表)，完整列与约束由字段分册维护。

~~~mermaid
flowchart LR
    U[User] --> L[Library]
    U --> A[AuthSession / UserExtension / Credential]
    U --> R[UserRole / Role / Permission]
    L --> M[Material / Immutable Revision]
    M --> N[Novel Chapters / Blocks]
    M --> T[Textbook Units / Lessons / Nodes]
    M --> E[Exam Paper / Version / Items]
    M --> S[Source Units / Content Blocks / Locators]
    L --> C[CollectionItem / Notebook Membership]
    S --> C
    C --> Q[Exercise Selection / Immutable Questions]
    T --> Q
    E --> X[Exam Session / Frozen Answers / Listening Attempts]
    Q --> P[Practice Session / Question Attempts]
    X --> G[Grading Runs / Effective Results]
    P --> G
    G --> V[Learning Evidence / Mistakes / Projections]
~~~

~~~mermaid
flowchart LR
    F[Explicit feature action] --> I[Idempotency / PG transaction]
    I --> J[Job / Stage / Outbox]
    J --> K[Kafka / Worker]
    K --> RUN[AiRun / ExternalCallAttempt含用量组]
    RUN --> RES[Explanation / Card / Audio Asset]
    RES --> BIND[Source Binding / Lookup effective pointer]
    RES --> OBJ[Verified immutable object]
    BIND --> CACHE[Redis disposable copy]
    J --> EVENT[Committed progress / Redis relay / WS or SSE]
~~~

模型每次真实供应商 attempt 独立记录用量；缓存命中没有供应商调用，不创建零 Token attempt。global_word 共享的是受控标准单词成品与目录占用，发起者的 Job、Key、模型用量及个人收藏仍有所有者，不能沿图中的公共目录取得其他人的任务。

## 5. 查询、事务与删除设计

| 典型查询/操作 | 访问路径与必要边界 |
| --- | --- |
| 书库列表 | owner/library + active + material_type/language + 稳定排序/id 游标；标题检索策略按样本验证，不预先给所有 text/JSON 加 GIN |
| 收藏/词本 | owner/library + kind/目标语/当前状态；成员按 notebook_id/collection_item_id 双向查；笔记/读音检索与原文分开 |
| 每日单词 | 用 IANA timezone 将选定日两端分别转换为 UTC，再查 `[start,end)` 的 created_at；不能固定加 24h 跨越夏令时 |
| 返回阅读位置 | 按 owner/library/material/内容版本查询已接受位置；新旧版本分别保留，版本不匹配按 locator 明确重绑，不能静默套新 sentence_id |
| 开考/保存/交卷 | 锁场次与冻结引用，检查当前动作/时限/edit_epoch/revision；答案锁定、评分请求和 Outbox 同事务 |
| 听力媒体领取 | 锁场次及每场次×Stimulus usage；先 reserved，首字节前提交 consumed/active；终态不重开，Redis 丢失不重置次数 |
| 评分/掌握 | 匹配 active run/generation，原子替换 effective 指针和学习贡献；后续投影按证据版本重放，不因迟到或重评重复累计 |
| 持久解释/音频 resolve | 先当前会话/动作/来源授权，再 PG 当前有效指针与缓存副本；miss 查询持久结果，不自动发模型请求 |
| 管理用量 | 依据 attempt 唯一事实，在有界时间窗按模型/能力/用户范围聚合；未知保持 null/完整性标记，不能重复叠加 AiRun 汇总 |

所有私有 JOIN 的两侧均检查归属；服务验证目标存在/版本/状态和逻辑引用后才能写入。统一锁顺序遵循[数据库规范第7节](../engineering/database.md#7-无外键的逻辑关联与并发协议)，安全/授权变更先策略版本、再用户/会话，再业务父聚合；同类多父按稳定 ID 排序。模型/文件等待不持有数据库事务。

涉及容量预留/结算时，在上述身份锁之后、业务资源锁之前，统一按 `global_storage_states → user_storage_states → 对应 reservation → 业务资源父行` 的顺序取得本事务实际需要的锁；不相关的容量根不强行加锁。上传、生成受理、发布、取消和GC遵守同序，不能一个入口先锁资源、另一个入口先锁容量而形成环。

材料删除先 tombstone 并推进 delete_generation；阻止新增引用及迟到发布。冻结考试、已提交作答/评分、独立收藏必要快照、已成功解释和音频的合法引用按原规则保留。GC 同父锁下复核实际引用、任务占用/代次与宽限，不能依赖 Redis/陈旧计数或 ORM cascade。未绑定草稿附件、孤立 staging 和仍有业务引用的成品分别处理。

## 6. 实施顺序与兼容

本次建立完整目标视图，**不要求下一次迁移一次性创建全部设计表**。每个小阶段只落地当前服务需要的字段/表及可运行验收。

| 交付单元 | 必要结构及验证重点 |
| --- | --- |
| 阶段1 B1 | 既有 users/RBAC 增量、会话/user_extensions三个字段组、可信 scope、最小收藏关联；注册单例/撤销版本/隔离与 Redis 会话故障验证 |
| 阶段1 B2 | 本人凭据、Job/Stage/Outbox/Inbox、AiRun/含用量字段的attempt、本人凭据单能力异步测试结果（不建习题）；Fake供应商、重投/unknown/撤权与事务验证 |
| 阶段1 B2a/b | 完整继承/deny/授予边界、目录/技术限额、审计；按各功能切片落地，不把 B1 最小链路当完整 RBAC |
| 阶段2 | 上传/配额、三类内容版本与结构、出处/阅读、试卷准备/听力文字稿候选与确认；OPEN-01/03 及来源/版本/删除竞争 |
| 阶段3 | 完整收藏/词本、CSV批次/行、查询附件/四类卡片、解释投影/绑定/lookup、私有及公共词音持久资产；OPEN-04、双账号缓存隔离、无隐式新调用 |
| 阶段4 | AI选源/公共评分/学习证据/错题/诊断；OPEN-05/10/11、重评与跨端并发 |
| 阶段5～6 | 阶段5考试场次/冻结答卷/播放账本与评分复用；阶段6复验已交付结构的边界、性能/索引、恢复和发布验收；不在本书预建商业化、组织租户或新产品 |

B1既定合法来源/已提交卡片夹具所需的最小材料版本/源/卡片及直接关联必须随B1建成；字段按实际路径最小化，不预建完整上传/查询。阶段2教材/试卷预览首次需要公共题根/版本/依据/来源引用时即交付，OPEN-10兼容语义须在首次冻结前解决，不能等P2再补。Agent内部线程/消息仅在实际卡片来源依赖时随建，完整查询在L2。具体逐表阶段见[收敛矩阵](database-convergence.md)。

迁移采用 expand → 回填 → 核对 → 收紧顺序。B0 旧用户新增 password_version/security_epoch 等需在迁移说明中明确中性起点及现有会话处理；不把默认 1 当成密码或授权历史。旧角色数据范围、菜单权限关系转换必须保留人工授权/deny/保护边界，不能种子重跑覆盖。

每个实施切片需交付：受控 Alembic revision、同步模型/字典、旧版本升级与空库路径、当前相关真实 PG 约束/并发测试、受影响 Redis 故障验证及独立 review。迁移必须同一物理 PG 连接持维护锁，不能绕过现有维护入口；本书不提供误导为已可执行的裸建表脚本。

## 7. 待决与设计验证边界

未决项唯一状态仍在[待决清单](../decisions/pending.md)。本书受影响点：OPEN-01/03 决定来源格式/阅读还原样本；OPEN-02 决定挑战用途启用和恢复流程；OPEN-04 决定真实模型/词表/声音目录；OPEN-05 决定无答案教材依据；OPEN-06 决定容量与留存参数；OPEN-10/11 决定题目无效化及掌握策略。P1 原始听力音频遵循 OPEN-12，本次没有提前开放上传/转写模型。

暂不新增：SRS/FSRS/复习队列/每日新词额度、通用聊天/通用回答卡片、第四类材料、套餐/余额/金额结算、用户整库备份、私有材料跨用户共享或管理旁路。

本次检查范围仅是文档链接/围栏/路径、B0 已有字段与生成字典一致性、跨分册引用、产品/契约/阶段一致性及独立设计 review；DBDESIGN1原交付见[初版记录](../delivery/reviews/2026-09-25-database-design.md)，物理收敛见[DBDESIGN2记录](../delivery/reviews/2026-09-25-database-convergence.md)，本轮命名与关系更新见[DBDESIGN3记录](../delivery/reviews/2026-09-25-database-naming.md)。没有运行建库迁移、真实 PostgreSQL/Redis 业务测试、性能 EXPLAIN 或应用测试，因此不勾选 DB/DAT/LC 等工程验收。
