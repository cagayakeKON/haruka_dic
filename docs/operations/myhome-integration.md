# MyHome 基础设施复用方案

| 字段 | 内容 |
| --- | --- |
| 状态 | Draft v0.6，新增管理后台与 RBAC 的复用边界，未执行 |
| 调查日期 | 2026-09-22 |
| 调查范围 | 本机相邻 MyHome 仓库的代码、Compose、Nginx 和 CI 文件 |
| 未验证 | 服务器运行版本、网络、权限、容量、证书和可用端口 |

产品约束见 [PRD](../product/overview.md)，应用设计见 [架构总览](../architecture/overview.md) 和 [认证与隔离](../architecture/authentication.md)。本次文档化没有修改 MyHome，也没有使用其实际凭据连接服务。

## 1. 已检查的本地实现

下列链接指向当前工作区的相邻 MyHome 仓库；单独复制 Haruka 仓库后，这些外部工作区链接需要对应源码才能打开。

| 证据 | 检查结果 |
| --- | --- |
| [backend/pyproject.toml](../../../MyHome/backend/pyproject.toml) | Python 3.13、FastAPI、SQLAlchemy Async、Redis、Kafka、MinIO、HTTPX、LangChain/LangGraph、structlog、markdown-it-py、pwdlib[argon2]、uv 工具链；此处是 MyHome 现状 |
| [生产 Compose](../../../MyHome/deploy/docker-compose.prod.yml) | myhome-prod 项目，PostgreSQL、Redis、Kafka、MinIO、API、多个 Worker、迁移与初始化服务 |
| [部署说明](../../../MyHome/deploy/README.md) | GHCR 镜像、独立部署目录、生产日志和服务健康检查 |
| [构建部署工作流](../../../MyHome/.github/workflows/build-and-deploy.yml) | 构建镜像、Android 包和远端部署；没有 pytest/Flutter 测试阶段 |
| [认证路由](../../../MyHome/backend/app/api/routes/auth.py) | 预置用户的邮箱密码登录、刷新、退出、个人资料；区分 Web Cookie 与 Android Token 响应，未见自助注册路由 |
| [认证服务](../../../MyHome/backend/app/services/auth_service.py) | Redis 刷新会话、令牌轮换、会话撤销、账号状态/租户成员检查和登录限流 |
| [租户角色](../../../MyHome/backend/app/shared/tenant_role.py) | member/admin/owner 固定等级与最低角色比较；认证服务在租户名称修改时使用该判断，不等同于 Haruka 所需的动态完整 RBAC |
| [密码与令牌](../../../MyHome/backend/app/core/security.py) | pwdlib 密码哈希、JWT、随机刷新令牌及其摘要 |
| [租户仓储范围](../../../MyHome/backend/app/repositories/tenant_scope.py) | 统一附加 tenant_id 条件；可借鉴为 Haruka 用户/资料库作用域 |
| [文件上传服务](../../../MyHome/backend/app/services/file_upload_service.py) | 预签名上传、文件校验、对象记录与 Outbox，含 MyHome 业务和认证依赖 |
| [MinIO 客户端](../../../MyHome/backend/app/core/minio.py) | 内部存储地址与客户端可达的签名地址分开配置 |
| [Outbox 服务](../../../MyHome/backend/app/services/outbox_publish_service.py) | 待发布事件领取、发布和恢复，含账本/采集任务的分支 |
| [模型配置](../../../MyHome/backend/app/services/effective_llm_settings.py) | 租户配置覆盖环境默认值，模型配置短期缓存；Haruka 需要改为用户范围且禁止共享 Key 回退 |
| [OpenRouter 客户端](../../../MyHome/backend/app/ai/clients/openrouter.py) | 现有 ChatOpenAI 适配、超时、重试、遥测；Haruka 借鉴机制，调用实现改用 Pydantic AI |
| [命名约定](../../../MyHome/backend/app/infra/naming.py) | Redis Key、Channel、Kafka Topic 和 MinIO 路径集中管理 |
| [Nginx 配置](../../../MyHome/frontend/nginx.conf) | 静态页面、API 代理与 WebSocket；当前文件监听 HTTP 80 |
| [Alloy 配置](../../../MyHome/deploy/observability/alloy/config.alloy) | 按 myhome-prod 项目及列举的服务名过滤日志 |
| [后端日志](../../../MyHome/backend/app/core/logging.py) | structlog 与标准 logging 汇合、contextvars、JSON stdout、递归脱敏；可选本地 JSONL 镜像 |
| [Web logger](../../../MyHome/frontend/src/shared/logging/logger.ts) | 统一日志入口；后端上送只允许 warn/error，默认是否上送与开发环境有关 |
| [前端日志路由](../../../MyHome/backend/app/api/routes/frontend_logs.py) / [接收服务](../../../MyHome/backend/app/services/frontend_log_service.py) | Web 日志 Cookie/来源和 Android Bearer 验证、Redis 限流、上下文裁剪、重新输出后端日志 |
| [SQL 耗时采集](../../../MyHome/backend/app/core/db_sql_timing.py) / [数据库引擎](../../../MyHome/backend/app/core/db.py) | SQLAlchemy 事件记录成功查询耗时和截断语句；失败钩子仅清理计时状态 |
| [AI 回调](../../../MyHome/backend/app/ai/telemetry/langchain_callback.py) / [用量汇总](../../../MyHome/backend/app/ai/telemetry/llm_telemetry.py) | 每次模型调用的状态、耗时、Token 及工作流汇总，不记录 Prompt/回复正文 |
| [日志服务 Compose](../../../MyHome/deploy/docker-compose.observability.yml) / [Loki 配置](../../../MyHome/deploy/observability/loki/config.yml) | 共享 Alloy/Loki/Grafana、Docker socket proxy；Loki 源码配置 auth_enabled=false、保留 168 小时 |
| [运维看板](../../../MyHome/deploy/observability/grafana/dashboards/myhome-production.json) / [AI 看板](../../../MyHome/deploy/observability/grafana/dashboards/myhome-ai.json) | API、Worker、关联查询、Android 故障，以及模型用量/失败/延迟看板的参考 |

仓库配置表明已有可参考的能力，但不能据此断言生产服务器已经具有相同状态。MyHome 的部分文字说明可能落后于源码，实施时优先核对实际配置和运行状态。

## 2. 复用范围

### 共享服务实例

| 服务 | Haruka 计划 | 需要新增的隔离 |
| --- | --- | --- |
| PostgreSQL | 同一实例 | haruka 数据库、专用账号、独立 Alembic 迁移和测试库 |
| Redis | 同一实例 | haruka: Key 前缀、独立 Pub/Sub Channel；配置允许时使用专用 ACL 用户 |
| Kafka | 同一实例 | haruka.* Topics、独立消费者组和死信队列 |
| MinIO | 同一实例 | 私有 haruka-files Bucket、仅能访问该 Bucket 的应用凭据 |
| 日志平台 | 同一 Loki/Grafana/Alloy；全部日志与埋点统一收集 | Haruka 接收 API、三端采集、低基数标签、元数据与看板；运维访问权限单独控制 |
| Docker/GHCR | 相同部署工具 | Haruka 镜像、Compose 项目、发布配置和回滚版本 |

Topic/Key 前缀是命名隔离，不自动构成权限或资源隔离。需要结合专用凭据、网络范围、连接数和并发限制。Haruka 不使用 MyHome 的生产数据库超级账号或 MinIO root 凭据作为应用运行凭据。

### 复用代码模式

优先提取和适配以下通用机制：

- 配置加载、数据库 Session、基础设施客户端和关闭流程。
- 统一 API 错误、request_id、分页、国际化错误消息和日志脱敏。
- 密码哈希、会话轮换/撤销、Cookie/CSRF、原生端令牌响应、限流与作用域查询；扩展原生端适配到 Flutter Windows 和 Android。
- 上传意图 → 对象校验 → 完成确认 → 任务投递。
- Job/Outbox 的状态推进、领取、超时恢复和失败观察。
- 模型配置、Prompt registry、业务输出校验和用量记录机制，适配到 Pydantic AI 的模型/工具调用。
- structlog/标准 logging 桥接、前端日志接收、SQL 耗时和 AI 遥测机制，补全正常事件、三端埋点与关联字段。

第一版将需要的通用机制整理为 Haruka 自己的模块，保留来源说明和相应验证。若两个项目后续都需要稳定共享，再评估提取公共 Python 包；目前不创建通用平台仓库，也不让 Haruka 在运行时导入 MyHome 工作目录。

Haruka 的 Agent 框架已确定为 Pydantic AI。MyHome 的 LangChain/ChatOpenAI 调用和 LangGraph 图保留在原项目；Haruka 不因复用基础设施继承这些依赖。独立选择并锁定 Pydantic AI 的兼容版本，不要求升级或修改 MyHome。运行依赖、会话与任务边界见 [Agent 运行层](../architecture/agent-runtime.md)。

### Haruka 独立实现

- 语言材料、章节、句子、出处、收藏、练习、评分和学习统计。
- 试卷结构/版本、校对、考试场次/草稿/服务端截止、事务交卷与 AI 批改；复用既定 PostgreSQL/MinIO/Job/Outbox/Kafka/Worker，业务契约见 [试卷模式](../modules/exams.md)。
- Gemini/OpenRouter TTS 协议、音频切段、缓存、播放定位。
- 账号注册、个人资料库初始化和单词 CSV 导入导出。
- 管理后台、动态角色/权限/继承/拒绝、授予边界、两端菜单与登录资格、授权版本/撤权、首管理员初始化和持久审计；详见 [管理后台与 RBAC](../architecture/authorization.md)。
- Flutter 三端 UI、客户端缓存和文件保存适配。
- Flutter Telemetry、前端事件字典、有界补传队列、匿名采集和用户归属；不直接移植 React logger 的只上报警告/错误策略。
- Haruka 的服务访问边界和供应商凭据管理。
- Pydantic AI 的个人模型工厂、领域工具、卡片输出、应用流式事件和会话存储。

MyHome 的 React 前端、原生 Android UI、账本和餐食业务不是复用目标。认证机制可以适配，但不共用账号表、租户成员关系、会话或 JWT Secret。Haruka 首版无组织/租户切换页面，文件/Worker 服务需改为自身的用户和资料库归属。

现有认证路由面向预置用户，不能将“已有登录”描述成“已有自助注册”。Haruka 新增注册校验、唯一标识约束和用户/资料库事务初始化；参考实现中的平台标识只决定传输方式，不能获得额外权限。

MyHome 已检查的角色机制是固定等级比较。Haruka 需要新增关系化角色/权限策略与 AuthorizationService，推荐以 PyCasbin 执行版本化策略投影；不能把 member/admin/owner 数值比较扩展成前后端各自硬编码角色。Haruka 不继承 MyHome 的角色分配或管理员身份。

本次细化还明确：Haruka以PG会话撤销/安全epoch保障管理审计与强制下线一致，Redis保存可丢失的会话材料；Web采用opaque会话Cookie，原生使用短JWT/轮换refresh。这些是Haruka自己的设计，不宣称MyHome源码已实现同样协议，见 [账号流程](../modules/accounts.md)。

## 3. 网络与部署

### 推荐接入方式

1. 调查 MyHome 实际 Compose 项目、Docker 网络及各服务连接地址。
2. 声明持久的共享 Docker 网络，让需要复用的基础设施与 Haruka 后端/Worker 接入。
3. Haruka 保持独立项目和内部网络；Web 不需要直接连接数据库、Redis 或 Kafka。
4. 使用服务 DNS 名称和专用配置，不写死容器 IP，不以暴露数据库公网端口作为复用手段。
5. 核对 Kafka advertised listeners 中的地址，从 Haruka Worker 容器实际验证可达。

跨 Compose 共享网络的机制参考 [Docker 官方文档](https://docs.docker.com/compose/how-tos/networking/)。网络成员变更应进入部署配置，避免只执行一次临时 docker network connect 后在升级时丢失。

共享服务仍由明确的部署方管理其生命周期。Haruka 的发布/卸载不停止共享数据库和队列，也不删除 MyHome 的卷。采用共享网络后，MyHome 的升级和停机也可能影响 Haruka，需要纳入维护安排。

### 应用服务

初始拆分建议：

- haruka-web：Flutter Web 用户端与 /admin 管理布局的静态资源、反向代理；管理端推荐先共用该服务。
- haruka-api：FastAPI 请求、配置、流式解释与任务接口。
- haruka-worker：解析、批量 AI、TTS 任务，可按负载拆分。
- haruka-outbox：持久事件发布。
- haruka-migrate：一次性迁移服务。

服务名称是建议值，实际端口、域名、部署目录和网络名在接入阶段确定。后台解析不能占满所有语音处理能力，需同时设置任务类别、用户和全局并发上限。

试卷解析与整卷批改纳入同一任务体系，按题/题组保存阶段结果并限制并发；考试截止扫描由现有 Worker 职责承接，不为此新增一套调度基础设施。原卷/题图归当前用户私有对象，答卷/成绩归其业务数据；批改队列不能携带答案正文或 Key。

## 4. 必须适配的配置

### 网关和文件地址

- Flutter Web 和 API 优先同源；配置 HTTPS。
- 使用 Haruka 独立 Cookie 名称、主机作用域及 JWT issuer/密钥；Cookie 写操作校验 CSRF，不能接受 MyHome 的会话。
- 用户端/管理端分别签发和校验 client/admin audience 与独立会话 Cookie；/admin 路由分区不代替后端授权。
- MyHome 当前 Nginx 文件只有 HTTP 监听，不能据此认为 Haruka 的 TLS 已经具备。
- SSE/流式回复需设置合适的缓冲和超时策略，上传大小需与产品上限一致。
- MinIO 签名必须使用实际客户端可达的 Host；生成签名后再改域名会破坏签名。
- Web 直接上传 MinIO 时配置允许的 Origin；文件/音频下载验证 Content-Type、Range、有效期和断线重试。
- 不让 HTTPS 页面依赖 HTTP 媒体地址。

### 队列与数据

建议按任务用途命名，例如 haruka.imports、haruka.speech，并配套 DLQ 和消费者组。消息只包含用户/资料库/任务/凭据引用等必要信息，不包含明文 Key 或整本材料。不新增整库备份 Topic。

Redis 业务缓存、会话和通知带 Haruka 前缀及用户/会话范围；MinIO 按用户分路径，所有上传与签名下载先检查所有者。仅加 haruka 前缀不能隔离不同 Haruka 用户。

角色策略、授权版本、授予边界和管理审计归 Haruka PostgreSQL；Redis 仅缓存与数据库版本完全对应的授权快照，并提供失效通知。每个受保护请求读取数据库当前版本，不能依赖 Pub/Sub 必达或旧 JWT 权限；日志/队列中断不改变数据库授权真相。

任务去重以 PostgreSQL 已提交结果为准，Redis 只作为辅助。不能因为共享 Redis 存在，就忽略数据库任务状态或恢复流程。

Pydantic AI Agent 在 API/Worker 内调用；Job 重试从应用提交的业务阶段边界处理，不等于 SDK 任意步骤自动恢复。工具写入须有稳定业务幂等键，SDK 与 Worker 重试共同受总预算限制。

### 全部日志与前端埋点

已确认采用现有 Alloy → Loki → Grafana。前端三端日志、性能/异常和业务埋点经 Haruka 接收 API 进入结构化 stdout；后端 API/Worker/Outbox/迁移、Pydantic AI/工具/TTS、SQLAlchemy，以及 PostgreSQL/Redis/Kafka/MinIO/网关日志统一采集。详细字段、事件、重试与权限以 [统一日志与前端埋点](observability.md) 为准。

- Alloy 的项目与服务过滤需显式纳入所有 Haruka 服务，并按实际部署清单验证覆盖，保持 MyHome 原有日志可见。共享 PostgreSQL 等容器只采集一次，按数据库/应用字段识别 Haruka。
- MyHome Web 上送仅有 warn/error，Haruka 必须补全正常日志和 info 埋点、批量队列、Windows 会话适配、未登录入口与账号切换处理；不能只改服务名即认为完成。
- 增加 project/environment/service 等低基数标签；内部用户、operation/request/job/AI ID 等放 JSON/structured metadata。前端不可伪造服务端身份，Grafana 筛选不承担用户授权。
- SQL 计时与 PostgreSQL 引擎日志分开验收，补失败/连接/锁诊断；Pydantic AI 的遥测须重新适配，不能照搬 LangChain 回调。参数、材料/消息正文、密码、Key、Token、签名 URL 不进入日志。
- 当前 Alloy 的旧 Docker 日志过滤为 1 小时，Loki 留存为 7 天。Haruka 采集规则需验证积压恢复、补传时间、容量与丢弃计数；历史窗口和日志增长纳入发布条件，不静默改变 MyHome 的全局策略。
- Loki 当前未启用租户认证，保持内部访问，前端不能直连。告警渠道与采集平台自身故障检测须实测，不能仅因存在看板就认定告警可用。
- 管理端日志、授权拒绝、权限/账号/会话变更也进入同一链路；成功管理变更与审计/Outbox 同事务提交，再投递脱敏日志。审计留存独立于 Loki 7 天窗口，应用管理员不自动成为 Grafana 管理员。

### 凭据

Haruka 使用独立的认证签名密钥与供应商凭据加密主密钥。可参考 MyHome 的掩码展示，但须单独验证按用户加密、权限检查和轮换，不能把 SecretStr 视为落盘加密。模型选择可有非秘密默认值；用户未填 Key 时禁止回退到环境或其他人的 Key。

## 5. CI/CD 计划

参考 MyHome 的 GHCR 构建和 Compose 发布流程，为 Haruka 创建独立工作流：

1. Python 的 Ruff、Pyright、相关 pytest 与迁移检查。
2. Flutter analyze、有效的 widget/业务测试，以及三端构建。
3. 后端和 Web 镜像发布到独立镜像名，使用可追溯标签。
4. Android 构建签名 APK；Windows 使用 Windows Runner 构建发布包。
5. 部署时按运维规程保护受迁移影响的数据，运行迁移，再启动服务。数据库备份属于运维，不增加用户侧全库备份功能。
6. 校验依赖连接、任务消费、应用健康，并验证三端、后端、AI、数据库及基础设施日志在现有 Grafana 可关联查询。

不能直接复用 MyHome 原生 Android 的 Gradle 构建命令来构建 Flutter Android。现有 MyHome 工作流未执行自动化测试，Haruka 需要补上自己的验证阶段。

## 6. 实施前检查清单

- [ ] 按多用户要求确定注册开放策略、会话配置与用户配额。
- [ ] 获得实际服务连接配置，核对网络和 Kafka 广播地址。
- [ ] 检查 PostgreSQL、Redis、Kafka、MinIO 的 CPU、内存、磁盘和连接余量。
- [ ] 创建独立数据库/账号、Bucket/凭据、Topics/组及 Redis 命名与权限。
- [ ] 确定共享网络的管理方和基础设施停机影响。
- [ ] 确认 Haruka 域名、TLS、API 与媒体可达地址。
- [ ] 为解析临时文件和音频留出磁盘空间，确定用户与全局并发/容量限制。
- [ ] 验证两个用户之间的 API、缓存、文件、任务及个人 Key 隔离，MyHome 会话不能登录 Haruka。
- [ ] 验证两端登录与完整 RBAC、授权版本跨进程生效、首/末管理员保护及审计事务，管理后台不能借运维权限读取个人正文或 Key。
- [ ] 增加全部来源采集规则和 Haruka 看板，验证 Flutter 三端正常/错误/业务事件、AI、SQL 与数据库引擎日志，确认 MyHome 原有日志不受影响。
- [ ] 验证断网补传、匿名入口、换账号归属、字段脱敏、积压/丢弃和留存容量，完成端到端采集探针与告警测试。
- [ ] 使用独立测试数据完成接入验证，避免对 MyHome 业务数据进行测试。

以上均为计划项，本次调查没有执行资源创建、迁移、部署或容量验证。
