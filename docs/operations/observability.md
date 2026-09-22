# 统一日志与前端埋点

| 字段 | 内容 |
| --- | --- |
| 决策 | Haruka 全部日志和埋点接入 MyHome 的 Alloy → Loki → Grafana |
| 状态 | Draft v0.3，2026-09-22；新增管理端与 RBAC 审计，尚未实现或部署 |
| 范围 | Flutter Windows/Web/Android、管理 Web、API、Worker、AI/TTS、数据库、网关与共享基础设施 |
| 配套 | [架构总览](../architecture/overview.md)、[认证与隔离](../architecture/authentication.md)、[管理后台与 RBAC](../architecture/authorization.md)、[Agent 运行层](../architecture/agent-runtime.md)、[MyHome 复用](myhome-integration.md) |

## 1. 已确认要求与复用现状

所有来源共用现有日志平台，在同一个 Grafana 中查询、关联和建立 Haruka 看板。前端运行日志、错误、性能事件和业务埋点都属于首版范围；正常操作、成功请求和 info 事件也必须上报，不能只收集错误。

全量采集指各来源已产生且符合脱敏协议的日志进入同一链路，不按来源或 warn/error 门槛遗漏。debug/info/warn/error/fatal 均有采集路径；产生日志的级别配置需显式记录，业务埋点默认全量，不做隐式采样。队列、磁盘和网络有容量边界，超限、拒收、过期与丢弃必须可观测，不能承诺离线设备或被强制终止的进程永不丢日志。

本机 MyHome 源码核对结果如下，线上实际配置仍需验证：

| 现有能力 | Haruka 的适配要求 |
| --- | --- |
| structlog 与 Python 标准 logging 汇合为 JSON stdout，附带上下文与脱敏 | 延续统一出口，覆盖 FastAPI、ASGI、Worker、第三方库及迁移命令 |
| 前端调用 /api/v1/frontend-logs，由后端重新输出到容器日志 | 保持这个路径模式；增加 Flutter 三端、业务埋点、批量队列与未登录采集 |
| Web logger 的上送函数仅发送 warn/error，默认开关与开发环境相关 | Haruka 发布配置显式启用上报，正常日志和埋点一并发送，不能照搬过滤条件 |
| 前端入口验证 Web 日志 Cookie/来源或 Android Bearer，会限流和清理上下文 | 扩展 Windows；归属由服务端确定；补匿名入口；不能只靠客户端声明身份 |
| SQLAlchemy 记录成功 SQL 的耗时与截断语句，失败钩子清理计时状态 | 增加失败、连接池与事务事件，改为安全的 SQL 模板/指纹，不输出绑定参数 |
| LangChain 回调记录模型耗时、状态和 Token，不记录 Prompt/回复 | 字段和看板思路可复用，采集适配到 Pydantic AI 并覆盖工具、重试和 TTS |
| Alloy 按 myhome-prod 和服务白名单采集，包含 PostgreSQL 等容器 | 增加 Haruka 项目规则，并对实际服务清单逐项核对；共享容器只采集一次 |
| Alloy 丢弃超过 1 小时的旧 Docker 日志；Loki 配置保留 168 小时 | 明确积压重放与留存策略，不能直接把旧规则当作完整性保障 |

源码入口见 [MyHome 复用证据](myhome-integration.md)。MyHome 已有运维与 AI 看板，但 Haruka 的前端埋点、字段和看板需要实现。

## 2. 统一采集链路

~~~mermaid
flowchart LR
    F[Flutter 三端与管理 Web 日志 / 埋点 / 性能 / 异常] --> Q[Telemetry 本地队列]
    Q --> I[Haruka 日志接收 API]
    I --> J[结构化 JSON stdout]
    B[FastAPI / Worker / Outbox / 迁移] --> J
    A[Pydantic AI / 模型 / 工具 / TTS] --> J
    S[SQLAlchemy 查询 / 事务 / 连接池] --> J
    J --> D[Docker 日志]
    P[PostgreSQL / Redis / Kafka / MinIO / 网关] --> D
    D --> AL[共享 Alloy]
    AL --> L[共享 Loki]
    L --> G[现有 Grafana 内的 Haruka 看板与查询]
~~~

Flutter 只访问 Haruka 的接收 API，接收端完成校验、限流、归属绑定与脱敏。Loki 留在内部网络；MyHome 当前配置为 auth_enabled: false，不能向客户端暴露写入或任意查询接口。Grafana 由独立运维身份访问，Haruka 的管理登录、auditor 或 super_admin 角色均不自动授予 Grafana/Loki 全局权限。

生产应用使用一个 JSON stdout 出口，避免同一记录同时通过文件与 Docker 重复采集。开发控制台可以另外格式化显示，但不能把“控制台可见”当作“已进入 Loki”。前端逻辑来源与转发它的 API 容器分别保留，Grafana 能按真实来源筛选。

ASGI/原生依赖/基础设施的 stderr 和非 JSON 输出也必须有采集路径：按来源解析、合并异常多行并脱敏；无法解析时输出带 parse_error 标识的安全摘要，不能因 JSON 解析失败整条丢弃。遗留文件日志需登记专门采集源并去重。

首版通过结构化日志关联整个操作，现有 Loki 保存日志。Pydantic AI 的 OpenTelemetry spans 如需使用，由适配器提取允许的摘要字段为日志；不能直接把 trace 数据发往 Loki 日志接口，也不把完整 tracing 瀑布图当作现有能力。无需为了接入 Pydantic AI 自动开通另一个云端观测平台。

## 3. 来源覆盖清单

| 来源 | 必须采集的内容 | 出口 |
| --- | --- | --- |
| Flutter 运行 | 启动、生命周期、路由、状态错误、缓存/文件/播放故障、Dart/Flutter 异常、可取得的插件诊断 | 三端 Telemetry → 日志 API |
| Flutter 网络 | 方法、路由模板、状态、耗时、重试、取消、超时、SSE 断连与恢复 | Dio/流式适配器 → Telemetry |
| 前端埋点 | 注册登录、导入、阅读、解释、朗读、收藏、练习、考试/批改、Agent、CSV 的关键行为与结果 | track 接口 → 同一 Telemetry |
| 管理前端 | 管理登录、页面/按钮交互、权限快照刷新与拒绝、表单提交体验，不包含表单正文 | 同一 Telemetry，按 admin 受众分区 |
| 权限与管理审计 | 登录/越权拒绝、账号/角色/菜单/策略变化、会话撤销、首管理员初始化 | 安全事件 → structlog；成功管理变更另以数据库审计/Outbox 保证持久记录 |
| 前端性能/崩溃 | 首屏、章节加载、首文本/首音频、卡顿摘要、异常堆栈、可恢复的原生退出诊断 | 平台适配器 → 同一队列 |
| Python 全部进程 | 请求访问/错误、业务服务、权限拒绝、生命周期、第三方库、Outbox/Worker、取消/重试/DLQ、迁移与初始化 | logging/structlog → stdout |
| AI 全部路径 | Agent run、每次模型请求、工具、校验失败、重试、预算、中断、TTS 合成与缓存 | AI 遥测适配器 → structlog |
| 数据库访问 | 查询成功/失败、耗时、模板/指纹、连接获取失败、池等待、事务失败/回滚 | SQLAlchemy/服务适配器 → structlog |
| PostgreSQL 引擎 | 启停、连接/认证故障、死锁/锁等待、检查点、数据库错误和启用的慢查询诊断 | PostgreSQL 输出 → Alloy 专用解析 |
| 网关与基础设施 | Web 静态服务与代理的访问/错误，Redis、Kafka、MinIO、各初始化容器运行日志 | Docker → Alloy |

所有部署服务需要登记采集来源、解析方式和负责人；新增 Worker 不得因服务白名单未更新而消失。Alloy/Loki/Grafana 自身的故障和采集健康也纳入运维检查；它们的自日志采用独立规则和重复故障汇总，避免写入失败产生无限反馈。日志平台中断期间仍需本机 Docker 日志作为故障诊断来源。

## 4. 公共字段与操作关联

以下为首版契约，业务事件的 attributes 按事件单独定义白名单，禁止任意对象直接序列化：

| 字段组 | 字段与规则 |
| --- | --- |
| 记录 | schema_version、event_id、record_type、event、level、message；record_type 为 log/analytics/performance/crash；event 使用受控的点分名称 |
| 时间 | occurred_at 为来源发生时间，received_at 为接收时间；统一 UTC；耗时由单调时钟计算，不依赖客户端时钟准确 |
| 来源 | project=haruka、environment、service、emitter_service、client_platform、release、build；project/环境由部署或接收端确定，客户端 service/platform 只能使用限定枚举 |
| 身份 | user_id 表示发起用户；actor_user_id、owner_user_id、library_id、audience 由认证/已验证 Job 绑定，管理目标另存 target_type/target_id；匿名身份与私有引用为空；client_session_id 仅为随机分析标识 |
| 授权 | permission_code、user_authz_version、policy_revision、decision/reason 为服务端判断，前端不能自报为真实授权结果；不把权限差异或账号 ID 作为 Loki 标签 |
| 关联 | operation_id 表示一次用户操作；request_id 表示一次服务端请求；client_request_id 表示客户端请求尝试；job_id、ai_run_id、model_call_id、tool_call_id 按需填充 |
| 可选 tracing | trace_id、span_id、parent_span_id，启用相应适配时填充；不能将任意 request_id 当作有效 OTel trace_id |
| 业务 | 经授权的资源引用、路由模板、状态、错误分类、duration_ms、retry_count、结果计数等；不带自由输入正文 |
| 接收 | origin=client/server/infrastructure；前端原始事件与服务端核实的业务结果分开，日志批次的请求 ID 为 ingest_request_id |

服务端为每次业务请求生成 request_id，在响应头和错误响应中返回；前端同时保存自己的 client_request_id。跨域时显式暴露响应头。一次点击产生 operation_id，贯穿 API、Job/Outbox、Kafka、Worker、AiRun、工具和数据库访问日志；每个重试保留 operation_id 并生成独立调用 ID。

客户端传入的关联 ID 必须校验格式与长度，仅用于排查，不能成为身份或授权依据。转发日志时保留原业务 request_id，不能被日志批次自己的请求 ID 覆盖。异步任务从已验证 Job 恢复归属，每个请求/任务开始绑定、结束清理 contextvars，避免跨账号污染。

Loki 索引标签限定为低基数字段，例如 project、environment、service、client_platform、level、record_type。event 仅在受控枚举内才可提升为标签；模型名、版本、用户/请求/任务/资源 ID、SQL 指纹放 JSON 或 structured metadata，不逐一建立索引流。该区分符合 [Loki structured metadata 的设计](https://grafana.com/docs/loki/latest/get-started/labels/structured-metadata/)。

## 5. Flutter 日志与埋点实现

### 统一入口与捕获点

建立跨平台 Telemetry 服务，向业务暴露 log、captureException、track、recordTiming 四类入口，共用字段、脱敏和上报队列。普通 print/debugPrint 不能成为业务模块唯一日志出口；框架、插件与宿主日志通过各自适配器接入。

- FlutterError.onError 捕获框架回调错误，PlatformDispatcher.instance.onError 处理根 isolate 的其他未处理错误；自己创建的 isolate 还需监听并转发错误。三端 release 模式分别注入异常验证，Web 补验异步与 JS 互操作错误；必要的 Zone 捕获须保持初始化与 runApp 的 Zone 一致并去重。依据：[Flutter 错误处理](https://docs.flutter.dev/testing/errors)、[根 isolate 错误边界](https://api.flutter.dev/flutter/dart-ui/PlatformDispatcher/onError.html)。
- Dio 拦截器记录正常/失败请求与关联 ID；go_router 观察页面切换；播放器、文件选择/保存、缓存、SSE 分别记录领域事件。
- 页面使用路由名称/模板，网络使用方法与模板路径；不记录完整 URL 查询参数、请求/响应正文、Header 全量转储或输入框内容。
- 异常保存经过脱敏和限长的堆栈、错误类型、release/build 与有限上下文。MyHome 接收器会抹去 stack/stack_trace，Haruka 需为安全堆栈定义专用字段，不能直接复用这一行为导致线上无法定位。
- 发布流程保存匹配版本的 Dart 符号与 Web source maps，限制访问；用实际发布包验证堆栈还原。原生 Android/Windows 崩溃需要宿主层适配与下次启动补报，不能宣称 Dart handler 覆盖原生崩溃、OOM、系统强杀或浏览器进程退出；支持边界在阶段 1 原型和阶段 6 发布验收记录。

### 业务事件字典

事件在交互或业务状态发生时记录一次，不在 widget build 中反复记录。下面是首版必需的事件族；具体 schema 版本、字段和负责人随功能契约一起维护。

| 场景 | 事件示例 | 允许的业务字段/统计口径 |
| --- | --- | --- |
| 启动/页面 | app.started、screen.viewed、app.lifecycle.changed | 平台、版本、screen_name、启动/加载耗时 |
| 账号 | auth.register.submitted、auth.login.result、auth.logout.completed、auth.session.revoked | client/admin 受众、成功/失败类别、传输方式；不含邮箱、密码或令牌 |
| RBAC / 管理 | access.snapshot.updated、authz.denied、admin.change.committed、admin.change.rejected | 权限代码、目标类型/ID、版本、影响数量、安全状态差异；成功变更以服务端审计事务为准，覆盖用户/角色/继承/菜单/策略 |
| 材料 | material.import.requested、material.import.completed、material.import.failed | 格式、大小区间、阶段、耗时、错误分类；服务端确认导入结果 |
| 阅读 | reading.chapter.opened、reading.session.ended、source.navigation.result | 材料/章节引用、有效前台阅读时长、回跳结果；不收集逐字选区或逐帧滚动 |
| 解释/收藏 | explanation.requested、explanation.completed、collection.saved | 内容类别、语言、引用、耗时；不记录原词句、笔记或解释正文 |
| TTS/播放 | speech.requested、speech.generated、speech.cache.hit、playback.started、playback.failed | 模型/声音、缓存结果、首音频耗时、时长、平台错误 |
| 练习 | practice.started、answer.submitted、answer.scored、practice.completed | 题型、来源、题数、规则/AI 评分方式；答案与学习事实留在业务库 |
| 试卷考试 | exam.import.reviewed、exam.session.started、exam.response.saved、exam.session.submitted、exam.grading.started/completed/failed、exam.result.viewed | 场次/试卷版本/评分运行引用、题数、状态、耗时、manual/timeout；详细口径见试卷专题 |
| Agent | agent.message.submitted、agent.run.completed、agent.run.failed、agent.card.action | run 引用、卡片类型、操作类型、耗时、失败类别；不记录消息正文 |
| CSV | vocabulary.csv.export.completed、vocabulary.csv.import.previewed、vocabulary.csv.import.completed | 导出/有效/错误/重复/新增行数、处理策略、耗时；不含 CSV 内容 |

前端记录用户意图与实际体验，后端记录已提交的业务结果。借助 origin、operation_id 和 event_id 区分，不能把点击成功、API 接收成功和数据库提交成功算成同一个转化。导出接口完成传输与客户端实际保存完成也分别记录。

业务库继续承担已提交学习数据和业务统计的权威来源。埋点用于使用路径、成功率和性能分析；客户端事件可重试、缺失或被伪造，不能直接用作权限、账单或评分依据。PRD 的学习活跃与导入后转化指标需结合服务端记录计算。

试卷过程按 [试卷模式](../modules/exams.md) 关联 exam_session_id、exam_paper_version_id、grading_run_id 和 Job/AiRun；这些 ID 不作索引标签。保存/交卷以服务端确认事件为准，超时自动交卷也必须记录；原卷题干、作答、参考答案、rubric 与个人成绩明细不进入日志。批改失败/待复核单独统计，不记为答错或零分。

### 队列与批量上送

- 三端维护有界持久队列，适配现有 Drift 缓存能力；内存入队快速返回，不让网络发送阻塞阅读或播放。启动早期/队列不可用时保留最小内存回退。
- 推荐初始值：每批不超过 20 条且不超过 128 KiB；正常每 5 秒或满批发送，error/fatal 优先；队列每账号最多 5,000 条/10 MiB，最长 24 小时，任一上限到达触发既定淘汰与计数。这些值要在阶段 1 用三端流量、堆栈长度和服务限流共同验证。
- event_id 在入队时生成，重试保持不变。429 按 Retry-After 延迟，网络/5xx 使用带抖动退避；400/过大/非法事件返回明确逐项拒收原因，拆批或隔离坏事件，避免阻塞整条队列。
- 接收响应逐项标明 accepted、duplicate、rejected；客户端只移除已确认或不可重试条目。服务端以用户/匿名会话 + event_id 做有限窗口去重，窗口覆盖允许的补传周期；记录重试、拒收、队列积压及 dropped_count/reason。
- 接收成功只表示 API 已处理并输出该记录，不代表 Loki 已持久化；去重缓存与 stdout 之间也没有分布式原子提交。用端到端探针核对可查询性，不将此链路表述成恰好一次或零丢失存储。
- Web pagehide、Android 后台、Windows 退出时尽力刷新；正常周期上送才是主要保障。页面退出发送必须保持认证/CSRF 契约，不能为了 sendBeacon 省略保护；强制结束无法保证最后一批上传。
- 日志上传使用独立传输通道，排除自身的普通网络埋点，避免“上传失败 → 产生日志 → 再上传失败”递归。故障状态通过本地计数与恢复后摘要上报，采集异常不能破坏业务执行。

## 6. 接收 API 与用户归属

沿用 MyHome 的路径风格，推荐用户端 POST /api/v1/frontend-logs、管理端 POST /api/v1/admin/frontend-logs，两者进入同一接收服务但校验各自 audience。Haruka 使用自己的入口、会话与 schema。增加 POST /api/v1/frontend-logs/anonymous，专门接收未登录启动、注册/登录失败和经过严格裁剪的崩溃记录。

已登录入口：Web 使用对应受众的 Haruka Cookie + CSRF/Origin 校验；Windows/Android 使用有效 Bearer。按认证基础能力登记，要求账号 active、当前会话和对应 client.login/admin.login 权限，不依赖某个业务菜单权限；写遥测不授予读日志权。服务端绑定身份、受众、部署环境和允许的客户端服务名，拒绝客户端覆盖这些字段。认证请求 ID 与日志声称的原业务请求 ID 分别保存；客户端时间和属性始终视为不可信数据。

匿名入口：只允许明确的事件/字段枚举与小体积批次；设置 IP、短期匿名会话和全局限流，不接受账号、资料、任务、模型调用结果等私有引用。user_id 始终为空。Web 检查来源但不把 Origin 当身份；原生平台声明也不能免除校验。公开入口只能写受限遥测，不能查询日志或获得业务访问权。

前端队列按后端实例、登录用户、受众和账号代次分区。登录前事件保持匿名；登录后不追认成已认证历史。退出时在会话撤销前尽力发送，随后清除原用户队列；禁用/撤销登录资格、会话失效、切入口或换账号同样不允许用另一受众/新账号凭据补发旧队列。清除数量可用不含旧账号/资源信息的摘要记录，不能借匿名入口补传私有队列。服务端独立记录禁用、撤权和拒绝事件，不依赖已失去登录资格的前端补报。

有限队列导致的数据缺口在看板中显式呈现。需要保证保留的安全审计或业务事实在服务端事务中保存，再输出同平台日志，不依赖客户端尽力上报。

### 管理审计的持久保证

成功管理变更与 AdminAuditEvent、授权 revision 和 Outbox 同事务提交；审计写入失败则管理修改回滚。Outbox 按稳定 event_id 投递脱敏日志，允许重试去重；Loki 中断不回滚已经提交的权限，也不丢失数据库中的审计事实。拒绝/失败操作记录安全原因，不虚构成功变更。审计查询使用 admin.audit.read 和专用字段白名单，应用接口不可修改/删除历史，运维归档/留存策略另行明确。

## 7. 后端、AI 与数据库细节

### 后端统一输出

复用 MyHome 的 structlog + 标准 logging 桥接、UTC 时间、服务字段、contextvars 与脱敏处理器。API 请求成功/失败、ASGI 访问/错误、HTTPX/供应商库、Worker 和迁移全部进入统一出口；同时处理第三方 handler 的传播与重复输出。日志格式异常不得让正常请求失败。

一次异常以明确的 error_id 关联，避免中间件、异常处理器和服务层把同一异常重复计入错误率。SSE 记录首事件、完成/取消/中断与耗时；不逐 token 打日志。反向代理记录请求 ID、路由模板和上游耗时，剔除查询参数、认证头与签名媒体地址。

### Pydantic AI 与 TTS

- AgentService 记录 run 开始、完成、失败、取消、预算耗尽；模型适配层记录每次真实请求及 attempt；工具适配层记录工具开始/结果/校验失败。普通解释、视觉识词、生成题、评分、诊断和后台批处理均必须经过这些入口。
- 记录 ai_run_id、model_call_id、tool_call_id、provider、请求/实际模型、提示模板版本、状态、耗时、首内容等待、重试和供应商返回的用量。供应商请求 ID 只有在确认不含秘密时才保存。
- Token/字符/音频用量缺失时标记 unknown，不记作 0；费用如为估算需记录价格版本/币种，并明确非最终账单。看板按模型请求统计用量，run 的汇总字段不能再次相加；每次重试费用独立观察。
- Pydantic AI 提供基于 OpenTelemetry 的 instrumentation，可以不用 Logfire 服务；采用时关闭内容捕获，例如 include_content=False，并用字段白名单适配日志。官方说明见 [Pydantic AI 观测接入](https://pydantic.dev/docs/ai/integrations/logfire/)。原始 Prompt、回复、工具入参/结果、音频和图片不写入日志，异常消息也要防止回显这些内容。
- TTS 独立记录合成、缓存命中/未命中、合并请求、格式转换、文件保存、取消和失败；关联同一 operation_id/job_id。缓存命中不算模型调用。Flutter 记录真实首音频与播放错误，服务端生成耗时不能代替用户听到声音的等待时间。

### 数据库双层采集

SQLAlchemy 层负责与业务请求关联的每次查询计时、失败与事务结果。记录操作类别、参数化模板或指纹、duration_ms、SQLSTATE、数据库名、连接诊断标识；不输出参数值、行内容或自动展开的异常 SQL。MyHome 的语句空白压缩/截断不等于脱敏，含字面值的语句需规范化后才能记录。

PostgreSQL 层采集引擎本身的 stderr；共享实例只保留一个采集源，保留实际宿主 project/service，再通过 database_name、db_application_name 区分 haruka 访问与 MyHome/共享引擎事件，不能把整个共享数据库改标成 Haruka。

Haruka API/Worker 使用独立数据库账号，并配置稳定 application_name。引擎日志解析保留时间、数据库、应用名、PID/会话、SQLSTATE；ORM 层按需记录可验证的连接标识和时间段帮助定位。连接池复用时必须重置事务级上下文；不能声称每条 PostgreSQL 启停或后台维护日志都有用户 request_id。

实施时核对 log_line_prefix、连接事件、log_lock_waits 和慢查询策略；SQLAlchemy 的全查询计时已经覆盖应用访问，不能把“容器已采集”当作“数据库自动产生了所有 SQL 日志”。设置绑定参数日志长度为 0，并核对错误详情与 SQL 字面值的脱敏；不启用会暴露秘密的全量原始语句转储。若以后改用 PostgreSQL jsonlog，必须另配文件采集，因为它依赖 logging_collector，不能假定仍从 Docker stderr 取得。依据：[PostgreSQL 18 日志配置](https://www.postgresql.org/docs/18/runtime-config-logging.html)。共享实例参数变更须评估对 MyHome 的影响；本次未修改任何配置。

## 8. 脱敏、留存与 Grafana

脱敏在客户端入队前、后端输出前和基础设施解析时分别执行。禁止密码、Token、API Key、Cookie、预签名 URL、完整材料、聊天/作答正文、笔记、CSV 行和音频/图片载荷进入日志。错误堆栈去掉用户目录、URL 秘密和可能回显的业务内容；未知异常只保留安全类型/摘要。正则替换作为补充，不能代替事件字段白名单。

Loki 中保留内部用户 ID 仅用于获授权的故障排查，不记录邮箱或显示名。project/user_id 标签筛选和 Grafana 文件夹不构成数据权限隔离；应用角色无隐含的数据源查询权。管理端 admin.diagnostics.read 只访问后端限定的 Haruka 查询模板、时间/条数范围与脱敏 DTO，不能提交任意 LogQL，也不能查看 MyHome 日志或个人正文。确需开放用户自己的诊断时，另建本人范围的窄接口。

当前 MyHome 源码配置的留存是 7 天，Haruka 首次接入可沿用，但必须在发布说明明确窗口与容量。PRD 的导入后 7 日转化不能仅依赖恰好保留 7 天的原始日志，需要从业务记录计算并保存必要聚合；更长周期的日志分析要先调整留存和磁盘预算。学习数据与日志分别管理，日志不纳入用户单词 CSV。

管理授权历史以 PostgreSQL 审计为准，留存/归档单独配置，不能随 Loki 的 7 天窗口一起消失；权限差异仅记录权限代码/ID 和安全状态，不保存密码、Key 或完整用户表单快照。

Haruka 的采集规则不沿用“超过 1 小时即丢弃”的固定 Docker 时间过滤；按实际可回放的 Docker 日志、Alloy 进度与 Loki 接收窗口验证故障恢复。客户端补传使用接收时间进入 Loki，原发生时间保留为字段，防止旧客户端时钟影响入库；旧 Docker 日志重放仍需匹配 Loki 允许的历史窗口。无法恢复的间隔和丢弃原因必须标记。

| Grafana 看板 | 主要内容 |
| --- | --- |
| 总览与操作排查 | 三端/版本、API/Worker 错误率和延迟，operation/request/job/AI 关联搜索 |
| 前端质量 | 崩溃与异常、页面/章节加载、网络/SSE、播放器故障、队列积压/丢弃 |
| 使用与转化 | 注册登录、导入 → 阅读 → 解释/朗读/收藏 → 练习，前端意图与服务端结果区分 |
| 登录与授权 | 两端登录成功/拒绝、权限拒绝、禁用/撤权、管理变更、审计投递积压；按 event_id 避免重试重复计数 |
| AI/TTS | 模型与工具成功率、首内容/首音频、Token/音频用量、重试/预算、缓存效果 |
| 数据库与基础设施 | 查询耗时/失败、锁等待/死锁、连接故障、任务积压、网关与存储错误 |
| 采集健康 | 各来源最近到达、接收拒绝/限流、Alloy/Loki 写入失败、回放缺口、端到端探针 |

先用 Loki 日志查询计算必要计数与延迟；独立指标存储和完整 tracing 后端不作为首版隐含依赖。日志缺失不能自动解释为服务健康；定时探针写入无秘密事件并验证其可查询，平台不可用时由平台外健康检查发现。告警规则、接收渠道和容量阈值在部署验收时配置，现有配置文件不能证明告警已经生效。

## 9. 实施与验收

日志基础在 [阶段 1](../delivery/roadmap.md) 与认证、Agent 最小流程一起建立；每个功能提交同时维护事件字典和看板口径，阶段 6 只做全面验证，不能到发布前才补埋点。

- [ ] 三端实际 release 包的 debug/info/warn/error、正常业务埋点、性能与异常样本均在同一 Grafana 可查询；发布开关不遗漏 info 或业务事件。
- [ ] 用一次“选区解释/朗读”操作串起客户端、API、AiRun/模型/工具、Job/Worker、ORM 日志；PostgreSQL 引擎事件可按数据库/应用/连接线索定位。
- [ ] API、Worker、Outbox、迁移/初始化、网关和每项共享基础设施有来源清单与验证样本，不因项目/服务过滤丢失；MyHome 原有查询仍可用。
- [ ] 成功 SQL、失败 SQL、死锁/锁等待与连接故障在隔离测试环境有样本；参数、错误详情、AI 内容和假秘密不会泄露。
- [ ] 未登录启动/登录失败有受限遥测；伪造 user_id/service/事件属性不改变可信身份，匿名接口不能发送私有事件或读取日志。
- [ ] 管理 Web 的正常/错误/权限事件进入同一平台；client/admin 队列不混用，撤权后拒收旧私有队列仍有服务端审计。
- [ ] 角色/菜单/策略/会话变更的审计、版本和业务修改一致；审计数据库失败回滚，Loki 中断后可补发，应用角色不能借诊断接口查询任意共享日志。
- [ ] 断网、429、5xx、重复批次、坏事件、队列满、后台/关闭、重启、A 退出后 B 登录均符合补传和归属规则；丢弃数量可见。
- [ ] 实测各平台 Flutter/Dart/插件/原生崩溃边界、版本堆栈还原与下次启动补报；不可捕获的终止场景记录为明确限制。
- [ ] 日志接收端/Alloy/Loki 中断不阻塞学习功能，恢复/不可恢复区间可判断，日志上传不会递归产生日志风暴。
- [ ] 看板不重复累加前后端结果、Agent 汇总与单次模型用量；缺失用量/丢失事件不当作零。
- [ ] 实测三端到 Grafana 的正常到达延迟（初始目标 15 秒内）、峰值吞吐、磁盘增长与 7 天留存容量，记录最终阈值及告警验证结果。

以上均为待实施验收项。本次仅完善文档，没有创建 SDK、接收路由、看板或部署资源。
