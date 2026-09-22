# Haruka 系统架构

状态：设计基线 v0.7，2026-09-22，未实现。本篇维护公共系统边界、组件职责与选型状态；产品范围见 [产品总览](../product/overview.md)，用户操作见 [功能模块](../README.md)，字段和状态机由对应契约维护。

## 1. 系统边界与选型状态

已确认 Flutter 用户端覆盖 Windows、Web、Android，Python 前后端分离，学习 Agent 使用 Pydantic AI。多用户、注册登录、管理后台与完整 RBAC 为首版范围；用户使用各自的模型 Key，朗读采用 Gemini TTS 或 OpenRouter TTS。全部来源日志及前端埋点进入 MyHome 的 Alloy/Loki/Grafana。

Haruka 独立维护应用代码、账号、数据库、迁移、镜像、凭据和发布。复用 MyHome 的基础设施与可适配机制，不依赖相邻仓库的运行时导入，不自动共享 MyHome 用户或会话。首版推荐每账号一个私有 Library，不引入组织、共享资料库或跨账号协作。

选型表中的组件是当前推荐基线，只有用户明确确认的 Flutter、Python、Pydantic AI 和供应商边界属于已选要求；具体库、依赖版本、模型能力和平台适配仍需工程验证。推荐理由及变更条件见 [决策记录](../decisions/README.md)，未锁定的产品/平台/部署选项统一见 [待决清单](../decisions/pending.md)，本篇不维护第二份开放问题表。

## 2. 公共系统图

~~~mermaid
flowchart TD
    CLIENT[Flutter Windows / Web / Android] --> API[FastAPI / 认证与授权 / 业务服务]
    ADMIN[Flutter Web 管理端] --> API
    CLIENT --> CACHE[按实例与账号分区的本地缓存]
    API --> PG[PostgreSQL / 身份与权限事实 / 业务与Job]
    API --> REDIS[Redis / 会话材料与短期缓存]
    API --> OBJECT[MinIO / 私有对象]
    API --> AI[Pydantic AI / 文本与视觉适配]
    PG --> OUTBOX[Outbox 发布进程]
    OUTBOX --> KAFKA[Kafka / Haruka事件]
    KAFKA --> WORKER[Python Worker]
    WORKER --> PG
    WORKER --> REDIS
    WORKER --> OBJECT
    WORKER --> AI
    WORKER --> TTS[独立TTS音频适配]
    AI --> PROVIDER[OpenRouter / Gemini]
    TTS --> PROVIDER
    API --> LOG[结构化日志 / Alloy / Loki / Grafana]
    WORKER --> LOG
    OUTBOX --> LOG
    PG --> LOG
~~~

前端遥测经 Haruka 接收入口校验后进入同一日志链路，匿名事件与已认证身份按观测协议区分，客户端不直连 Loki。图中的 PostgreSQL、Redis、Kafka、MinIO 和日志服务可复用 MyHome 实例；独立账号、命名空间、资源限额及采集责任见 [基础设施复用](../operations/myhome-integration.md)。PG 是业务事实来源，缓存、队列和对象存储的持久性责任见 [数据与任务](data-jobs.md)。

## 3. 推荐技术基线

| 部分 | 当前基线 | 职责与待验证边界 |
| --- | --- | --- |
| 客户端 / 管理端 | Flutter / Dart；管理端推荐 Flutter Web | 用户三端共用功能模型，管理端独立布局与 client/admin 受众；不因已有用户登录就放行管理入口 |
| 状态与路由 | Riverpod、go_router | 异步状态、访问快照、菜单/路由/操作守卫、深层跳转 |
| HTTP | Dio | 请求、取消、统一错误和流式接收；Flutter 消费应用协议而非供应商 SDK 事件 |
| 播放 | just_audio | 播放队列、暂停、续播、倍速；Windows 平台实现与中断行为必须专项验证 |
| 本地数据 | Drift + SQLite；Web 使用 WASM | 授权阅读/音频缓存和有界日志队列，不作为第二套服务器事实来源 |
| 前端遥测 | 统一 Telemetry、Flutter 错误钩子及网络/路由/播放器适配 | 正常行为、错误和性能统一采集，平台无法捕获的退出场景如实报告 |
| API | Python 3.13、FastAPI、Pydantic | 参数/结果校验、服务编排、OpenAPI 与流式接口 |
| 认证 | pwdlib/Argon2id；Web opaque Cookie；原生短 JWT + 轮换 refresh | PG 撤销/epoch 与 Redis 会话材料共同校验；算法和时限以 [认证](authentication.md) 为准 |
| 授权 | AuthorizationService + PyCasbin | 多角色/受限继承/allow-deny 匹配；应用承担当前版本、授予边界和对象范围检查 |
| 数据访问 | SQLAlchemy 2 Async、asyncpg、Alembic | PostgreSQL 查询、服务事务及受控迁移 |
| 持久任务 | Kafka、confluent-kafka、独立 Python Worker/Outbox | 投递、阶段恢复、重试/取消和死信；不用 API 进程内后台任务替代持久执行 |
| 缓存与存储 | Redis、MinIO S3 API | 会话材料/限流/通知与私有原书/附件/音频；对象发布和回收以数据契约为准 |
| 格式提取与专用处理 | Markdown 优先 markdown-it-py；EPUB 按包目录/spine 提取；之后分别交小说/课本/试卷处理器和专用页面 | 共用源块/出处，不共用业务阅读器；高保真/竖排、分词及获准PDF/OCR库按样本确定，范围见三类材料契约 |
| Agent / 结构化结果 | Pydantic AI、对应 Provider、Pydantic 业务模型 | 类型化工具、依赖注入、结构化输出、限额；结构正确仍需出处与业务校验 |
| TTS | HTTPX + Gemini/OpenRouter 独立音频适配器 | 区分 speech 字节流与生成接口音频协议，按真实格式处理；具体模型、声音、分句语调/停顿/等待和请求量需验证 |
| 日志 | structlog + 标准 logging → Alloy → Loki → Grafana | 前端接收、API/Worker、AI/TTS、SQL 访问与数据库引擎日志共用平台 |
| 工程工具 | uv、pytest、Ruff、Pyright；Flutter 测试工具按测试专题 | 包/CLI/锁定版本与构建约束见 [脚手架](../engineering/scaffold.md)，检查和平台证据见 [测试规范](../engineering/testing/strategy.md) |

OpenRouter 统一入口是当前推荐，Gemini 官方直连为可选路径；具体文本/视觉/TTS 能力分别验证，不能由聊天可用推断音频或图像可用。首期检索使用章节、出处、收藏和错误标签，嵌入检索在有实际召回需求后引入，不增加首版向量基础设施。复用 MyHome 的配置、Prompt registry 与遥测思路，不直接复用其 ChatOpenAI 客户端或 LangGraph 图作为 Haruka 执行路径。

## 4. 运行职责与调用路径

| 组件 | 负责 | 协议归属 |
| --- | --- | --- |
| Flutter 用户端 | 功能界面、结构化组件、选区显示映射、播放/文件适配、授权缓存与遥测 | [功能模块](../README.md)、[出处](../contracts/content-locator.md)、[前端 E2E](../engineering/testing/frontend-e2e.md) |
| Flutter 管理端 | 授权范围内的管理操作和受控诊断，必须在线 | [管理模块](../modules/admin.md)、[RBAC](authorization.md) |
| API / 业务服务 | 身份、当前权限/所有者/业务状态检查，事务与客户端协议 | [API](../contracts/api.md)、[权限目录](../contracts/permissions.md)、[数据与任务](data-jobs.md) |
| Worker | 解析、批量分析、章节音频及评分等持久阶段；按执行边界复核授权 | [数据与任务](data-jobs.md)、[Agent 运行层](agent-runtime.md) |
| Outbox 发布进程 | 将已提交事件可靠投递，处理租约、重投和积压 | [数据与任务](data-jobs.md) |
| 部署与观测 | Haruka 进程生命周期、配置、健康、采集、发布与恢复；不停止共享服务 | [配置](../operations/configuration.md)、[部署与恢复](../operations/deployment-recovery.md)、[观测](../operations/observability.md) |

即时解释和 Agent 回复由 API 调用模型，将事件转换为应用 SSE/流式协议；最终结果完整校验后才可保存或触发动作。批量解析、整章音频和考试批改先提交 Job/Outbox，再由 Worker 执行。消息历史持久化不等于任意模型步骤自动续跑；首版在已提交业务阶段边界恢复，不另引入持久执行引擎或多 Agent 平台。

Python 文件解析和同步 SDK 调用须隔离阻塞操作，不能卡住 API 事件循环。正式 API/Worker/Outbox 共用包与资源组装、分别运行；部署建议为 haruka-web、haruka-api、haruka-worker、haruka-outbox 与一次性迁移。管理 Web 首版可复用静态服务，在 /admin 使用独立布局和管理 API；Worker 仅在负载需要时再按解析/语音拆分。

## 5. 公共领域与 AI 约束

- **身份、授权和归属分开成立。** 当前用户来自已验证会话；页面隐藏、客户端 ID、CSV 或模型参数不能代替服务端授权。管理权限不产生读取其他用户正文、答卷或个人 Key 的旁路。具体判定在认证/RBAC/权限目录维护。
- **业务事实由应用维护。** 原文、稳定 ID、版本和选区映射不由模型重写。Library/StudyProfile、材料、收藏/作答、学习统计、对话、音频和任务的关系统一在 [数据与任务](data-jobs.md)，定位字段与 Unicode 单位统一在 [出处契约](../contracts/content-locator.md)，不在总览复制 DDL 或 locator 字段表。
- **能确定的不用模型。** 有可靠答案的客观题、总分累计、既有 EPUB 目录切章及可确定的语种规则走程序路径。解释/出题优先引用已入库句子；生成内容与原文分别标识，不将自由规划循环用于考试计时或事务正确性。
- **结构、语义和媒体分别验证。** 解释、抽题、评分、诊断、卡片采用版本化结构模型，随后校验出处、权限、分值与业务状态；TTS 返回音频及结构化元数据，不强套 JSON 文本输出。超时、安全拒绝、低置信度、部分失败均需可识别结果和界面状态。
- **模型只在后端调用。** 每次调用绑定当前任务所有者的配置与额度，凭据不能经共享可变客户端或环境变量切换。文本、视觉、TTS 独立按能力适配，工具逐次授权；无 Key 不回退到其他用户或 MyHome 的 Key。
- **异步执行与付费有明确边界。** Job 状态、业务状态与供应商结果分开；幂等只能保证应用结果不重复提交，不能承诺供应商恰好收费一次。模型/工具/SDK/Worker 重试共享有界预算；复用已完成结果并遵守 unknown、取消、撤权及系统维护职责，详见数据与运行层契约。
- **日志可关联且不成为业务事实。** 正常 info 埋点也进入统一平台；operation/request/job/AI 关联、身份绑定、秘密/正文保护与低基数标签按 [观测协议](../operations/observability.md)。埋点不决定授权、费用或学习成绩。

语种能力按适配边界组织：分句/分词、形态还原、读音表示（如 IPA/拼音/假名）和 TTS voice 映射。可以是现有应用内模块，不要求先建立公共插件平台。P0 为中文界面/母语配置与英日学习；界面语言、母语和目标语是不同字段，韩语、西/法/德等语言属于后续范围。日语选区与断句不能以按空格切词代替；具体库/规则通过语种样本验证，产品优先级与设置行为见 [设置](../modules/settings.md)。

## 6. 三端与部署边界

| 平台 | 必须单独验证的能力 |
| --- | --- |
| Windows | 原生会话安全存储、安装/升级、文件保存、音频后端、选区和系统交互 |
| Android | 会话安全存储、文件选择/保存、音频中断、签名与目标设备 |
| Web | HTTPS、Cookie/CSRF、同源 API、下载、WASM 缓存隔离、自动播放及真实浏览器行为 |
| 管理 Web | 独立 audience、菜单/深链/操作守卫、在线撤权与审计，不提供离线管理 |

三端在线数据以同一后端为准。缓存按实例、账号和内容版本分区，切换账号处理播放器/下载/订阅及迟到响应。首版仅在当前账号有效离线租期内读取已有章节/音频，不提供完整离线编辑或考试；租期与撤权限制见 [RBAC](authorization.md)，具体清理和恢复行为见 [设置](../modules/settings.md)。

Web 与 API 优先同源，原始文件和媒体地址须从三端可达；MinIO 跨域上传仍需允许的 CORS 或代理。反向代理、公开地址、资源限额和健康定义由配置维护，发布/迁移/恢复步骤由运行说明维护。解析和音频设置用户级与全局并发上限，不能因复用基础设施而侵占 MyHome 容量。

用户侧恢复范围只有 [单词 CSV](../contracts/vocabulary-csv.md)，不包括原书、音频或整个资料库。数据库/对象/加密材料的保护是独立运维职责，见 [部署与恢复](../operations/deployment-recovery.md)。

## 7. 继续阅读与验证依据

功能流程分别见 [账号](../modules/accounts.md)、[材料公共能力](../modules/materials-reading.md)、[小说](../modules/novels.md)、[课本](../modules/textbooks.md)、[收藏与练习](../modules/vocabulary-practice.md)、[考试](../modules/exams.md)、[AI 与朗读](../modules/ai-speech.md)、[管理后台](../modules/admin.md) 和 [设置](../modules/settings.md)。它们维护操作/异常/平台体验；公共协议由架构和 contracts 维护，类型/格式及专用边界见 [三类材料](../contracts/material-types.md)。

工程目录和依赖方向见 [项目结构](project-structure.md)，B0/B1/B2 及完整交付证据见 [路线图](../delivery/roadmap.md) 和 [交付验收](../delivery/acceptance.md)。Flutter/Python 应用仍未实现；HTML 视觉原型不计作应用、平台或供应商验收。

选型参考：[Drift Web](https://drift.simonbinder.eu/platforms/web/)、[just_audio](https://pub.dev/packages/just_audio)、[Gemini TTS](https://ai.google.dev/gemini-api/docs/speech-generation)、[OpenRouter TTS](https://openrouter.ai/docs/guides/overview/multimodal/tts)、[OpenRouter 音频输出](https://openrouter.ai/docs/guides/overview/multimodal/audio)、[FastAPI 后台任务](https://fastapi.tiangolo.com/tutorial/background-tasks/)。资料不替代版本锁定与实测；MyHome 源码调查仅证明当时本地配置，未验证服务器运行或容量。
