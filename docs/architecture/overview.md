# Haruka 技术架构

| 字段 | 内容 |
| --- | --- |
| 状态 | Draft v0.6，新增管理后台与完整 RBAC 设计，未实现 |
| 日期 | 2026-09-22 |
| 产品依据 | [PRD](../product/overview.md) |
| 配套文档 | [Agent 运行层](agent-runtime.md)、[认证与隔离](authentication.md)、[管理后台与 RBAC](authorization.md)、[MyHome 复用](../operations/myhome-integration.md)、[单词 CSV](../contracts/vocabulary-csv.md)、[实施计划](../delivery/roadmap.md) |

## 1. 决策与边界

### 已确认要求

1. Flutter 前端覆盖 Windows、Web、Android。
2. Python 后端，前后端分离，复用 MyHome 基础设施。
3. 多用户、账号注册/登录；用户数据隔离，AI 服务使用各自的 API Key。
4. 朗读使用 Gemini TTS 或 OpenRouter 的 TTS 模型。
5. 单词 CSV 导出/导入承担用户侧备份恢复，不提供整库备份。
6. 应用内学习 Agent 框架使用 Pydantic AI。
7. 全部前端日志与埋点、后端、数据库及 AI/TTS 日志集中到 MyHome 的 Alloy/Loki/Grafana。
8. 导入可选择试卷模式，考试式整卷答题，交卷后 AI 批改与评分；格式范围待明确。
9. 提供管理后台；完整 RBAC 控制登录资格、用户端与管理端显示、操作、接口及数据范围。

### 当前推荐方案

- Haruka 作为独立应用维护代码、数据库迁移、镜像和发布流程。
- PostgreSQL 保存带用户归属的业务数据，MinIO 私有保存原始材料、附件和音频。
- 三端连接同一后端；同一账号访问自己的资料，客户端缓存按服务实例和账号分区。
- 文件解析、批量 AI、章节音频由持久任务执行；即时词句解释与对话通过流式响应提供。
- 试卷解析/批改复用持久任务；试卷版本、考试场次、答卷、评分依据与成绩分开存储，交卷以服务端事务为准。
- CSV 导出优先使用经过授权的流式下载，导入采用预览/确认，不新增整库备份服务。
- 管理后台采用 Flutter Web，在同一账号体系下区分 client/admin 会话；AuthorizationService 统一授权，推荐 PyCasbin 计算角色与权限规则。

### 推荐实现与未决项

首版推荐每位用户一个私有 Library，通过 user_id/library_id 做归属约束，不引入组织、共享书库或跨账号协作。注册采用邮箱 + 密码；邮箱验证、找回方式和注册开放策略待明确。

账号会话和供应商 Key 分开管理。Haruka 使用独立账号、签名密钥和 Cookie 名称；复用 MyHome 的认证实现思路，不自动接入其用户数据库或会话。详见 [认证与隔离](authentication.md)。

## 2. 总体架构

~~~mermaid
flowchart TD
    F[Flutter Windows / Web / Android] --> AUTH[注册登录 / 会话验证]
    ADMIN[Flutter Web 管理后台] --> AUTH
    AUTH --> AUTHZ[AuthorizationService / RBAC / audience]
    AUTHZ --> API[Haruka FastAPI / 数据范围与业务状态检查]
    F --> CACHE[按账号隔离的章节与音频缓存]
    API --> DB[PostgreSQL 业务数据与任务]
    API --> OBJ[MinIO 私有文件]
    API --> AGENT[Pydantic AI 文本 / 视觉 Agent]
    AGENT --> MODEL[OpenRouter / Gemini]
    DB --> OUTBOX[Outbox 发布进程]
    OUTBOX --> KAFKA[Kafka Haruka Topics]
    KAFKA --> WORKER[Haruka Worker]
    WORKER --> DB
    WORKER --> OBJ
    WORKER --> AGENT
    WORKER -->|TTS| MODEL
    AUTH --> REDIS[Redis 会话 / 缓存 / 限流]
    API --> REDIS
    WORKER --> REDIS
~~~

图中的数据、队列和日志服务复用 MyHome 实例，但 Haruka 使用自己的数据与命名空间。应用内部还必须按用户隔离。部署边界见 [MyHome 复用](../operations/myhome-integration.md)。

## 3. 技术选型

| 部分 | 推荐技术 | 职责与限制 |
| --- | --- | --- |
| 客户端 | Flutter / Dart | 三端 UI、文本交互、播放器与缓存 |
| 管理后台 | Flutter Web，推荐 | 独立管理布局与入口，复用 API 客户端、设计组件和授权组件 |
| 状态与路由 | Riverpod、go_router | 异步状态、权限快照、菜单/路由/操作守卫与深层跳转 |
| HTTP | Dio | 请求、取消、错误处理、流式内容接收 |
| 音频播放 | just_audio | 播放队列、暂停、续播、倍速；Windows 需要平台实现 |
| 客户端缓存 | Drift + SQLite；Web 使用 WASM | 缓存不是服务器数据的第二套权威来源 |
| 前端遥测 | 项目统一 Telemetry 服务、Flutter 错误钩子、Dio/路由/播放器适配 | 三端日志、异常、性能、业务埋点与有界补传队列，共用后端日志入口 |
| API | Python 3.13、FastAPI、Pydantic | 参数校验、服务编排、OpenAPI 与流式接口 |
| 认证 | pwdlib/Argon2id；Web opaque会话Cookie；原生短JWT+轮换refresh | PG会话撤销/epoch + Redis会话材料，检查两端登录资格；详见账号流程 |
| 授权 | AuthorizationService + PyCasbin，推荐 | 多角色、继承、allow/deny；应用负责数据库策略版本、授权边界和对象范围 |
| 数据访问 | SQLAlchemy 2 Async、asyncpg、Alembic | PostgreSQL 查询、事务、迁移 |
| 长任务 | Kafka、confluent-kafka、独立 Python Worker | 持久任务、重试、取消、恢复、死信处理 |
| 缓存/控制 | Redis | 会话、限流、短期进度、通知、锁；不承载唯一学习数据 |
| 文件存储 | MinIO S3 API | 原书、导入图片、生成音频；按用户前缀组织，后端鉴权 |
| Agent / 文本与视觉 AI | Pydantic AI + 对应模型 Provider | 类型化工具、依赖注入、结构化输出、流式事件与调用限额 |
| 卡片与模型结果 | Pydantic 业务模型 | 校验结构，配合应用检查出处、权限和内容版本 |
| TTS | HTTPX + Gemini/OpenRouter 适配器 | 音频合成与格式处理，和文本模型客户端分离 |
| 统一日志 | structlog + 标准 logging → Alloy → Loki → Grafana | 前端转发、API/Worker、AI/TTS、SQL 访问和数据库引擎日志共用平台 |
| 开发工具 | uv、pytest、Ruff、Pyright | 沿用 MyHome Python 开发习惯 |

具体依赖版本在工程初始化时按兼容性锁定。EPUB 渲染引擎、Windows 音频实现、日语分词及试卷 PDF/OCR 解析库仍需按确认范围与样本验证后决定。

## 4. 前后端职责

### Flutter

- 注册/登录、会话续期、书库、阅读器、教材习题、试卷答题/答题卡/成绩、收藏、练习、Agent、设置和 CSV 导入导出。
- 根据服务端权限快照控制三端页面、按钮和只读状态；管理 Web 提供用户、角色/权限、两端菜单、注册策略、配额、任务与审计界面。
- 用户端与管理端分别校验登录资格；路由直达、刷新、返回和运行中撤权都经过权限守卫，默认不渲染尚未确认授权的内容。
- 统一文本选区工具条，维护显示文本与服务器定位之间的映射。
- 根据结构化卡片/题目渲染原生组件。
- 试卷模式提供整卷答题、草稿保存状态、服务端计时显示和交卷；考试期间不展示答案/即时反馈，交卷后复盘。
- 播放、倍速、当前句高亮、已下载音频管理。
- 输入个人模型 Key，通过 HTTPS 提交；显示掩码和连接测试结果；退出时清除账号状态和缓存。
- 下载已解析章节与音频；第一版仅在有效离线权限租约内阅读/播放已有缓存，管理后台要求在线。
- 采集运行日志、网络/播放错误、性能与业务埋点，脱敏后批量上报；队列按账号分区，退出/换账号处理旧记录。

### Python

- 账号注册、两端登录、密码验证、会话撤销、当前权限与所有资源的归属检查。
- 提供用户/角色/权限/菜单管理，执行授予边界、禁止提权、最后管理员保护，以及权限版本与审计事务；生成前端访问快照。
- 材料上传校验、解析、版本管理、内容定位和图片识词。
- AI 解释、生成题、主观评分、Agent 工具与业务校验。
- 试卷结构化与校对、冻结版本、草稿冲突、时限/自动交卷、幂等锁卷、分题 AI 批改和程序总分校验。
- 客观题评分和学习统计，保证诊断依据来自实际记录。
- TTS 生成、结果去重、缓存索引和文件服务。
- 按所有者调度任务、导出单词 CSV、预览与提交 CSV 导入。
- 按用户加密保存供应商 Key，执行用户配额、全局限流和日志脱敏。
- 接收三端日志/埋点并绑定身份，统一输出后端、AI 与数据库访问日志，维护跨请求/任务的操作关联。

### 三端一致性

同一账号的在线读写以服务器为准。当前用户从已验证会话获取，不能信任请求体自报的 user_id。客户端操作携带稳定请求 ID，幂等键按用户划分；更新采用版本检查，冲突时重新获取数据。

阅读位置与“最远阅读进度”分开。缓存按服务实例、用户、材料版本和内容 ID 区分；换账号或退出时清理旧账号缓存、下载、播放器和订阅，并丢弃旧请求的迟到响应。

P0 不承诺完整离线写入和多设备离线合并。离线缓存仅供本设备先前登录且未退出的当前账号，在有效离线权限租约内读取，推荐最长 24 小时、部署可收紧；不支持离线注册/首次登录或管理操作。恢复网络后重新校验会话和权限，明确拒绝时清理失去权限的内容，不能降级绕过在线鉴权。离线设备无法即时收到撤权，限制见 [RBAC 一致性设计](authorization.md)。

考试短时未同步草稿明确显示状态，仅在服务端场次/版本/时限允许时补交，不扩展为完整离线考试。退出/换账号清除私有草稿，服务器已保存答卷和限时场次保持原用户归属。

## 5. 数据组织与出处

| 数据域 | 主要逻辑对象 |
| --- | --- |
| 账号与会话 | User/AuthSession/AuthChallenge元数据、epoch与撤销事实在PostgreSQL；Redis保存会话摘要/轮换材料与idle TTL |
| 授权与管理 | Role、PermissionCatalog、UserRole、RoleInheritance、RolePermission、RoleGrantBoundary、MenuItem/MenuPermission、AuthorizationRevision、AdminAuditEvent；以 RBAC 专题为准 |
| 资料库与偏好 | Library（owner_user_id）、StudyProfile、Settings |
| 材料 | Material、MaterialRevision、StructureNode、ContentBlock、Sentence、FileObject |
| 收藏与阅读 | CollectionItem、Tag、Bookmark、ReadingProgress |
| 练习与统计 | Exercise、PracticeSession、Attempt、LearnerProfile |
| 试卷与考试 | ExamPaper/Version、ExamSection/Item、ExamGradingBasis、ExamSession、ExamResponse、ExamGradeRun/ItemGrade；职责见试卷专题 |
| AI 与对话 | AgentThread、AgentMessage、Card、AiRun |
| 朗读 | AudioAsset、AudioSegment、PlaybackManifest |
| 执行记录 | Job、OutboxEvent、CsvImportBatch，均带用户归属 |
| 凭据 | ProviderCredential，按 user_id 加密存储，不进入 CSV |

这是领域划分，尚不是最终数据库 DDL。Library 从属于 User；所有子记录通过归属字段及同库引用约束隔离。StudyProfile 是账号下的学习偏好，不能代替身份验证。

出处至少保存材料 ID、内容版本、结构节点/块/句 ID、选区范围、原格式定位和上下文快照。原格式定位按 EPUB 文档位置、MD 结构位置、PDF 页码等适配；试卷额外保留题号、小题/共享材料和答案出处，PDF 支持范围按 PRD 确定。

Python 与 Dart 对 Unicode 字符索引的处理不能默认一致。接口必须声明唯一的选区偏移单位和文本规范化版本，在前后端显式转换，并用日文、组合字符和 emoji 验证。

ID、原始文本和内容版本由应用生成。AI 提供分类、解释、习题候选等补充结果，不能重写原文或随意替换出处 ID。

重新解析生成新内容版本，并尝试重新绑定旧锚点；无法绑定时保留快照并显示状态。材料删除后，收藏和作答仍保留其上下文。

## 6. 材料导入、阅读器与试卷

1. API 验证当前账号、导入权限与资料库归属，创建上传意图，客户端仅能上传到指定私有对象位置。
2. 后端校验实际对象、大小、格式和摘要，保存用户选择的学习材料/试卷模式，提交材料记录与 Outbox 事件。
3. 解析 Worker 提取确定的目录和正文，保存稳定内容块；普通材料可先阅读，试卷进入题组/小题/分值/答案抽取与校对准备。
4. 普通材料继续执行分类、抽题和语义分析；试卷显式模式不被 AI 覆盖，题目/分值/必要材料通过校验后生成 ready 版本。
5. 展示阶段进度、低置信度和失败原因；用户能改类型、重试或取消。

Markdown 优先使用 MyHome 已有的 markdown-it-py。EPUB 按包内目录和 spine 解析，保留图片、基础结构和注音信息；原文件始终保留。试卷推荐将文本型 PDF 提前到 P0，格式范围待确认；通用 PDF/OCR 暂按后续规划。解析库与版面策略在格式确定后用跨页/题图样本验证，不默认已支持扫描试卷。

阅读器先验证 Flutter 内容块方案，小说和教材共用同一内容模型。若复杂注音、竖排或高保真 EPUB 是硬要求，再评估三端阅读引擎；无论选择何种引擎，必须遵守同一出处协议。

初版英/日学习体验仍需可用的选区、断句和必要分词支持。高级形态分析可以迭代，但不能用按空格切词实现日语验收。

### 试卷考试与评分

primary_type=exam 使用独立考试流程，复用 Exercise 题目控件与评分能力。场次冻结试卷/题目/分值与计时设置；草稿保存带 revision 与编辑代次，交卷事务锁定答案并在请求批改时创建 Job/Outbox。截止由服务端校验与 Worker 扫描保证，不能只依赖客户端倒计时。

Pydantic AI 按固定题面/评分依据逐题或题组输出结果，应用校验分值并累计总分。无答案标注 AI 评估，失败/待复核保留部分成绩和原答卷，显式重评形成版本且不重复回流学习统计。题面与答案/成绩使用不同 DTO，考试内不提供即时答案提示；详细状态与验收以 [试卷模式](../modules/exams.md) 为准。

## 7. 接口与任务

普通 REST 使用版本化路径与统一结果/错误模型，可参考 MyHome 的 ApiBody、分页和 request_id。音频、文件和流式回复使用适合其媒体类型的响应，不套普通 JSON 包装。

建议接口资源分组为 auth、users/me、materials、collections、practice、exams、exam-sessions、agent、speech、jobs、settings，并增加 admin 下的用户/角色/菜单/策略/审计等管理资源。试卷版本/答卷/评分运行作为考试相关资源，CSV 位于单词收藏资源下，遥测沿用 frontend-logs 路径模式。两端分别通过 me/access 与 admin/me/access 获取权限快照。每个接口登记所需权限或明确的公共/认证基础能力例外；业务接口同时检查会话 audience、当前权限与对象范围，不能只判断登录成功。最终契约在阶段 1 固定。

### 即时路径

词句解释、Agent 回复等由 API 通过 Pydantic AI 异步调用模型，将 SDK 事件转为应用 SSE/流式 HTTP 协议。结构化卡片完整校验后才允许保存或触发后续动作；未完成的 JSON 只能作为临时展示状态。

### 持久路径

批量解析、整章语音与试卷批改先落含 actor/owner、audience、所需权限引用与 library_id 的 Job/Outbox，再投递 Kafka。Worker 在领取、工具调用、付费步骤与结果提交前检查当前权限、业务状态和对象归属，禁止仅信任消息或入队时权限快照。客户端按权限查询/取消自己的任务，管理端仅通过专用权限访问任务元数据和受限运维动作，不能借用用户 Key 发起新付费调用。

任务至少区分 queued、running、succeeded、failed、cancelled；重试次数、阶段进度和结果引用持久化。Worker 使用领取/租约与数据库幂等检查处理重复投递、进程崩溃和重启；失败进入可检查的死信流程。

Kafka 的重复投递处理不等于供应商“恰好收费一次”。外部 AI 请求超时但结果未知时标记不确定状态，限制重试，不能保证供应商支持幂等。

AgentThread/Message/AiRun 持久化到 PostgreSQL；首版从已提交的业务阶段边界恢复，未提交的 Agent 轮次中断后按策略重试。不把消息存储等同于 Pydantic AI 任意调用步骤的自动续跑，也不默认新增持久执行引擎，详见 [运行层设计](agent-runtime.md)。

关闭页面或普通退出不取消已提交的持久任务；主动取消、账号禁用或权限撤销时停止后续不再授权的步骤。已保存数据保留，截止锁卷与已返回结果的最低限度落盘由固定系统职责处理并审计，不能继续生成付费请求。Python 文件解析和同步 SDK 调用须隔离阻塞操作，避免卡住 API 事件循环。

## 8. AI、TTS 与凭据

### 模型适配

分别记录文本、视觉和朗读能力，不能因为模型支持聊天就认定它支持图片或 TTS。OpenRouter 统一入口是推荐默认值，Gemini 官方直连作为可选路径；具体模型/声音不在文档中锁死。

模型调用层确定采用 Pydantic AI，使用对应 Provider 接入 OpenRouter/Gemini。复用 MyHome 的配置、Prompt registry 和调用遥测设计，模型工厂与调用代码适配到 Pydantic AI，不直接复用其 ChatOpenAI 客户端或 LangGraph 图。

首版推荐核心 Agent + 类型化领域工具 + Pydantic 卡片模型，用户范围与授权服务通过运行依赖注入。工具可用性按权限过滤，每次执行仍校验当前权限，模型不能授予权限或扩大数据范围。独立 Harness 扩展包和多 Agent 编排按实际需求另行评估。具体职责、会话与重试见 [Agent 运行层](agent-runtime.md)。

首期检索以章节、出处、收藏和错误标签查询为主；嵌入检索在有实际召回需求后引入，不作为首版基础设施依赖。

### TTS 路径

文本/句子 ID → 缓存查询 → 合成任务 → 供应商音频 → 格式校验 → MinIO + 元数据 → Flutter 播放。

- 适配专用 speech 字节流与通过生成/聊天接口返回音频的不同协议。
- 依据实际返回格式解码；裸 PCM 需要正确的采样率/声道/位深及封装或播放适配，不能仅修改文件扩展名。
- 优先验证单句音频与句子 ID 一一对应，支持预取和连续播放；短段合成时只有取得可靠对齐信息才承诺段内逐句高亮。
- 不假定供应商返回词级时间戳。分句合成需验证语调一致性、停顿、首音频等待和请求数量。
- 缓存键包含用户/资料库、文本摘要、语言、模型、声音、合成参数、提示版本及音频格式。播放倍速不影响合成缓存键；首版不跨用户复用私有内容或合并请求。
- 相同请求合并，限制预取和并发；网络抖动不能触发无限重新生成。
- MinIO 保存已完成音频供该用户三端播放，客户端副本可以按容量清理；单词 CSV 不包含音频。
- 音频支持正确 Content-Type、Range/拖动和过期下载地址刷新。Windows 播放实现需专项验证。

### Key 管理

Key 在前端输入，后端按用户加密保存；主密钥由独立部署 Secret 提供。只有其所有者可管理，读取仅返回掩码/状态。任务引用 credential_id，执行时校验凭据所有者等于任务所有者；无有效 Key 就暂停相关调用。

账号密码、会话令牌和模型 Key 不进入日志、分析事件、Kafka 消息、CSV 或媒体 URL。Key 轮换后清理该用户旧配置缓存；不能回退使用其他账号、环境默认或 MyHome 的付费 Key。

## 9. 单词 CSV 导出与导入

后端在当前用户范围内导出 kind=word 的全部收藏，使用 UTF-8 BOM CSV；客户端执行平台保存。导入先解析、映射列、校验和预览，再按选择的重复策略提交。

CSV 是字段级单词迁移，不包含材料和音频文件，也不替换整个资料库。来源定位需要在当前账号重新鉴权；导入外部记录使用新业务 ID，不能借用 CSV 内的 ID 更新他人记录。

协议和验收以 [单词 CSV](../contracts/vocabulary-csv.md) 为准。运维层的数据库保护与灾难恢复仍由部署方管理，不作为产品中的备份恢复功能。

## 10. 三端与部署要求

| 平台 | 需要验证 |
| --- | --- |
| Windows | 原生会话安全存储、账号切换、CSV 保存、音频后端、选区、安装与升级 |
| Android | 会话安全存储、系统文件选择/保存、音频中断、签名安装包 |
| Web | HTTPS、Cookie/CSRF、同源 API、CSV 下载、账号缓存隔离、自动播放限制 |
| 管理 Web | 独立 audience、两端权限快照、菜单/深链/操作控制、撤权与审计、禁止离线管理 |

Web 与 API 优先同源部署；原始文件和媒体 URL 也需可从三端访问。供应商调用移到后端后，浏览器无需直接连接 AI 服务，但 MinIO 跨域上传仍需正确的 CORS 配置或代理路径。

生产服务建议至少分为 haruka-web、haruka-api、haruka-worker、haruka-outbox 和一次性迁移服务；管理 Web 首版可与用户 Web 共用静态资源服务，通过 /admin 独立布局和管理 API 实现，不必新增基础设施。Worker 可按实时语音、解析的负载再拆分。退出登录不取消仍有授权的已提交任务，但不会把结果推送给新登录的其他账号。

统一日志与前端埋点属于首版基础能力，从阶段 1 接入 MyHome 的 Alloy → Loki → Grafana。Flutter 三端与管理 Web 经各自受众的后端接收入口上报，API/Worker/Pydantic AI/TTS/SQLAlchemy 统一输出结构化日志，PostgreSQL 引擎和其他基础设施日志由容器采集。管理变更先持久审计再投递日志，共享数据库只采集一次，按数据库/应用字段定位 Haruka。

一次操作通过 operation_id、request_id、job_id、ai_run_id 关联；用户等高基数字段留在 JSON/metadata，身份由服务端绑定，不记录秘密或完整材料正文。前端包含正常行为埋点、性能、错误、未登录采集和离线补传，详细协议与看板以 [统一日志与前端埋点](../operations/observability.md) 为准。采集范围、拒收/丢弃和留存窗口都需验收。

解析和音频并发同时设置用户级与全局上限，以免影响其他用户和 MyHome。

## 11. 参考与验证状态

- 本地 MyHome 代码调查日期：2026-09-22；具体证据见 [复用文档](../operations/myhome-integration.md)。未验证服务器当前运行状态或容量。
- [Drift Web](https://drift.simonbinder.eu/platforms/web/)
- [just_audio](https://pub.dev/packages/just_audio)
- [Gemini TTS](https://ai.google.dev/gemini-api/docs/speech-generation)
- [OpenRouter TTS](https://openrouter.ai/docs/guides/overview/multimodal/tts)
- [OpenRouter 音频输出](https://openrouter.ai/docs/guides/overview/multimodal/audio)
- [FastAPI 后台任务](https://fastapi.tiangolo.com/tutorial/background-tasks/)

上述资料用于选型参考，具体供应商路由、模型能力和平台行为需在实现时实测。
