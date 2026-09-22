# Repository Guidelines

## 项目与当前状态

Haruka 是以用户自有材料为基础的 AI 语言学习应用。当前仓库包含需求、架构、计划文档及 prototype/ 下的新 HTML 交互原型，尚无 Flutter/Python 工程、依赖清单、构建脚本或应用测试。原型采用中性底色、Primary 主色及杂志式排版，不设“继续阅读”；范围与示例边界见 prototype/README.md。B0/B1/B2 均尚未实现。

文档任务只修改文档；用户要求开始实现时，按实施计划推进必要工程工作。不把计划当成已实现，不为了运行不存在的检查擅自创建项目骨架。

仓库只保留标准文件 AGENTS.md 作为代理规范唯一入口，不维护单数名称或其他重复副本。用户最新明确要求优先于旧文档；变更范围时同步相关文档。

## 开始工作前

先读 [项目入口](README.md) 和 [文档导航](docs/README.md)，确认实际文件、工作区变更、当前阶段与本次范围；保留用户及并行Agent已有工作。只读取当前任务相关正文，不假定未来工程/命令已经存在。

| 任务 | 必须读取的权威正文 |
| --- | --- |
| 产品/功能 | [产品总览](docs/product/overview.md)、对应modules规格、[功能与验收追踪](docs/delivery/coverage.md) |
| 身份、页面、业务动作与数据 | [认证](docs/architecture/authentication.md)、[RBAC](docs/architecture/authorization.md)、[权限目录](docs/contracts/permissions.md)、[API](docs/contracts/api.md)、[数据与任务](docs/architecture/data-jobs.md) |
| 建表、ORM、逻辑关联、数据隔离与迁移 | [数据库规范](docs/engineering/database.md)、相关数据/认证设计；按DB验收证明已实现范围 |
| 阅读、选区、导入、CSV或考试 | 对应模块，以及[出处](docs/contracts/content-locator.md)、[CSV](docs/contracts/vocabulary-csv.md)、[考试](docs/modules/exams.md)所涉及的契约 |
| Agent、卡片、会话、AI或TTS | [Agent运行层](docs/architecture/agent-runtime.md)、[AI与朗读模块](docs/modules/ai-speech.md) |
| 编码、初始化或构建 | [项目结构](docs/architecture/project-structure.md)、[代码规范](docs/engineering/coding.md)、[Lint](docs/engineering/lint.md)、[脚手架](docs/engineering/scaffold.md)、[B0/B1/B2](docs/delivery/milestones/scaffold.md) |
| 控件、测试与数据工厂 | [测试策略](docs/engineering/testing/strategy.md)、[前端E2E](docs/engineering/testing/frontend-e2e.md)、[测试数据](docs/engineering/testing/data.md) |
| 前端/API/Worker/数据库日志与部署 | [观测](docs/operations/observability.md)、[MyHome复用](docs/operations/myhome-integration.md)、[配置](docs/operations/configuration.md)、[部署恢复](docs/operations/deployment-recovery.md) |
| 交付或未决方案 | [路线图](docs/delivery/roadmap.md)、[交付验收](docs/delivery/acceptance.md)、[决策待办](docs/decisions/pending.md) |

## 已确认的产品边界

- Flutter：Windows、Web、Android；Python 前后端分离。
- 应用内 Agent 框架已确定为 Pydantic AI；使用 Pydantic 业务输出模型，不另建 LangChain/LangGraph Agent 执行路径。
- 支持导入时选择试卷模式、整卷作答、交卷后 AI 判断/评分；试卷首版文件格式范围仍待明确，不能将推荐的 PDF/OCR 优先级当作已确认。
- 多用户注册登录，资料、学习记录、任务、缓存与模型 Key 按用户隔离。
- 管理后台和完整 RBAC 为 P0；控制用户端/管理端登录、页面/菜单/按钮、接口与数据范围；Flutter Web 管理端及 PyCasbin 为当前推荐实现。
- 用户各自提供 API Key；朗读使用 Gemini TTS 或 OpenRouter TTS，不能静默替换成系统 TTS。
- 用户侧备份恢复仅为单词 CSV 导出与导入，不新增整库 ZIP、原书/音频打包或全库恢复。
- 复用 MyHome 基础设施与可适配机制，Haruka 维护独立业务、数据库、凭据、账号和部署。
- 所有前端/后端/数据库/AI/TTS 日志及前端业务埋点统一进入 MyHome 的 Alloy/Loki/Grafana；正常事件也要采集，不能仅上报 warn/error。
- 首版离线范围为当前账号有效权限租期内已有阅读/音频缓存，管理后台必须在线，不扩展成完整离线编辑同步。

## 文档组织与实现约定

- product放产品范围，modules放功能流程，architecture放公共设计，contracts放协议说明，engineering放开发与测试，operations放运行配置与观测，delivery放阶段与验收，decisions放决策及待决项。
- PRD 定义需求，专题文档定义详细协议；避免复制同一字段表或状态机到多处。
- 使用相对 Markdown 链接，移动或重命名后修复引用；删除过时方案时同步导航和计划。
- 将已确认、推荐、待验证和已实现分开标注。中文用于产品文档和沟通，代码标识保持清晰一致。
- 后续工程建议使用 frontend/、backend/、deploy/；这些目录当前尚未创建，实际布局建立后更新本文件。
- Flutter 保持功能模块、UI 状态与数据访问分层，平台差异放入适配层；Python 保持路由、服务、仓储和供应商适配分离。
- 用现有约定解决当前问题，不先引入多服务拆分、公共平台包或无实际需求的抽象。
- 后端正式入口共用资源组装，非editable安装后不依赖checkout/cwd；PEP517构建依赖另行完整锁定。开发命令与前端环境身份按蓝图统一，生成物单向导出并按清单纳管。
- 数据库结构变化通过 Alembic；接口与 CSV 变更维护版本兼容，不静默丢字段或改出处。
- 迁移通过受控维护入口，同一物理PG连接持迁移锁并执行DDL；断连失败后重新持锁核对，不用裸迁移命令绕过保护。种子升级不覆盖人工授权，Fake/测试seed只允许dev/test。

## 必须保持的技术约束

- 当前用户来自认证上下文，不相信请求体、CSV 或模型提供的 user_id。
- 不使用数据库物理外键或隐式级联；保留主键、唯一、非空及行内CHECK。跨表归属/存在性/版本由带ScopeContext的服务事务及共同父行锁协议校验，删除/GC也遵守同一规则；首版共享表隔离不宣称已启用RLS。
- 所有业务表统一created_at/updated_at，采用UTC带时区类型及MyHome式公共TimestampMixin；原生SQL、批量更新、upsert显式维护更新时间，created_at不被普通更新/CSV覆盖。完整命名、字段、索引、字典、迁移与验收以数据库规范为准。
- PG AuthSession/安全epoch维护持久撤销，Redis保存可丢失会话材料；Web使用opaque Cookie续idle，原生JWT/refresh按代次轮换；会话和权限检查失败关闭。
- 所有资源查询、批量写入、跨表引用、文件签名、SSE、Worker 和 Agent 工具检查当前动作权限与所有者；管理服务仅能访问明确授予的运维元数据/操作范围，不建立超级管理员的私有内容旁路。
- RBAC 默认拒绝，身份/受众、账号状态、登录资格、操作权限、数据范围和业务状态都要满足；页面隐藏不能代替接口授权，业务代码不硬编码角色名称。
- 权限代码由发布注册，用户经多角色/受限继承授权，匹配的显式拒绝优先。授权事务同步版本与审计，缓存只加速匹配版本，新请求不能用旧 JWT/权限快照继续已撤销的权限。
- 管理者授予范围与受保护角色独立校验，防止自提权、继承提权和修改默认注册角色提权；保护最后一个可登录超级管理员，首次管理员由受控部署初始化。
- 幂等键、模型配置、解释/TTS 缓存及通知按用户分区；换账号处理旧缓存、下载和迟到响应。
- 密码哈希存储；模型 Key 按用户加密；密码、Token、Key 不进入日志、队列或 CSV。
- credential_version与部署encryption_key_version分开；部署旧密钥不能因在线重加密完成就销毁，仍需保留依赖历史备份的恢复能力。
- 缺少用户 Key 时不回退到其他用户或 MyHome 的 Key。常规测试使用模拟供应商，真实调用只在任务需要且已获授权的范围内执行。
- 稳定内容 ID、内容版本和选区偏移由应用维护；AI 不得重写原文或绕过 schema/归属校验。
- 长任务先持久化 Job/Outbox；重复投递和重启不得重复提交业务结果，不承诺外部供应商恰好收费一次。
- Pydantic AI 的运行依赖按用户注入，不能通过全局环境变量或共享可变模型客户端切换个人 Key；对话存储不等于任意步骤自动续跑，首版在已提交业务阶段边界恢复。
- Worker/Agent 工具与每个新的付费阶段重查当前权限；撤权保留已提交数据，固定系统维护主体只做允许的封存/清理，不能变成任意用户调用。
- CSV 导入先预览确认，重复处理和来源回跳遵循规范，不能借导入 ID 覆盖他人数据。
- 考试使用冻结试卷版本，答卷由服务端保存，时限由服务端判定，交卷幂等且锁定答案；题面接口不返回答案/解析，普通练习仍可逐题反馈。
- AI 评分用类型化契约，分值/归属校验和总分累计由程序完成；无标准答案标记 AI 评估，失败/待复核不能计作零分，重评保留历史且不重复累计学习记录。
- 评分active/effective和generation分开，旧run迟到不能覆盖新成绩；材料删除用tombstone/代次阻止复活，冻结考试引用由受控GC保留。
- 上传只向客户端开放临时对象，后端发布验证后的不可变final对象；Worker不读取可被旧上传签名覆盖的来源。
- Flutter 使用统一 Telemetry，Python 使用统一 logging/structlog 出口；保持 operation/request/job/AI 关联，新增服务同步采集清单，禁止上传请求递归产生日志。
- 前端日志和埋点按事件白名单脱敏，身份由接收端绑定；队列按账号隔离，换账号不能补发为新用户。用户/请求等高基数字段不能成为 Loki 索引标签。
- AI 日志不记录原始 Prompt/回复/工具正文，SQL 日志不记录绑定参数；业务成功以服务端提交为准，不能把埋点当权限、账单或学习数据的权威来源。

## 开发节奏、并行协作与提交

- 大阶段指 [路线图](docs/delivery/roadmap.md) 的阶段1～6及明确登记的发布大节点；小阶段指大阶段内可独立验收的工作单元，例如B0/B1/B2或一项功能切片。开始工作时明确所属阶段、交付范围和必要检查，不能为触发全量测试临时把小改动称作大节点。
- 前端与后端并行开发：先对齐API、DTO、权限/错误/事件契约与验收行为，再由不同Agent或开发者分别实现前端和后端，按小阶段联调。分工标明文件归属和共享契约负责人，避免并发覆盖同一文件；有依赖的契约/迁移变更先协调，不能让双方各自定义不兼容协议。文档任务不因此创建应用工程。
- 每个小阶段完成后必须创建一次本地Git commit，包含该阶段实现、相关测试和文档；先完成必要检查及本阶段review，说明行为变化与实际验证，再提交。不得积攒多个已完成小阶段到最后一起提交，也不默认push。
- 提交前检查工作区和暂存区，只暂存本阶段归属明确的改动，不夹带用户或并行Agent未完成的修改，不用无差别git add .。不要重写既有提交或伪造Git身份；尚未初始化Git或提交失败时如实报告，不能声称已提交。工程初始化必须建立版本控制，后续小阶段以实际commit哈希作为完成证据。

## 检查与测试

- 小阶段完成或修复bug时，只允许执行证明本次变更所必需的测试：优先最低有效层的回归用例、直接受影响模块/契约和必要的跨端或集成路径。先说明影响范围与选择依据，不默认运行全仓、全平台或所有E2E。
- 只有大阶段/大节点完成时才执行全量测试，范围为截至该节点已交付能力的完整必需矩阵和约定平台；不得因用例失败、设备缺失或准备不足缩小已承诺范围。尚未实现的后续阶段不冒充已通过，真实付费模型测试仍遵守既有授权边界。
- 必要测试通过后停止重复测试；有新改动、失败或明确未消除的影响时，只补相关验证。大节点review修复问题后同样先做定点回归，已有未受影响证据在验证适用性后保留，不机械重跑全量；影响确实覆盖整体时才在该大节点重跑完整矩阵。
- 小阶段报告只声明本次局部结果，不把局部覆盖率当全仓覆盖率，也不为满足全仓覆盖门槛强行触发全量测试。完整覆盖分母和总体/核心组门禁在大节点执行。文档改动仅做必要文档检查，lint/类型检查按受影响范围和工具实际能力执行。

当前文档改动应检查：本地链接、代码围栏、文件路径、失效方案残留、需求与计划一致性。不得报告应用测试已通过。

UI Test ID由前端注册表单一维护，Flutter Key与外部Semantics定位分别验证，不用技术ID替代无障碍标签。flutter_test/integration_test覆盖公共流程，Playwright补Web，Patrol补Android；Windows原生交互另行举证。测试数据分固定资产、声明式场景、执行实例；目标动作经真实UI/授权路径执行，不用工厂预置成功结果，不向生产包或HTTP路由加入测试旁路。

具体静态规则/命令/例外按Lint专题；所选必需用例不能以进程退出0代替真实结果，大节点另执行完整覆盖分母门禁。测试范围和review次数以本文件的分阶段规则为准，专题维护具体方法。待产品决策不等于已知缺陷可豁免。

工程建立后，以真实锁定依赖与CI为准执行相关 [Lint](docs/engineering/lint.md) 和 [测试](docs/engineering/testing/strategy.md)，不在本文件复制命令/配置。优先证明权限隔离、事务/任务、出处、考试评分、账号切换与日志保护；不为纯文档、低风险格式或实现细节增加无意义测试。

## 分阶段 Review

- 小阶段只做1～2轮review：第1轮集中检查本阶段改动及直接影响；需要修订时先集中修复，再用第2轮定点复核。由非作者Agent或独立reviewer执行，不对未改动的整个项目反复审查，不机械开启第3轮。未关闭缺陷不能标为完成或以达到轮数上限为由忽略。
- 每个大阶段开发完成后必须做全盘review，覆盖该节点的前端、后端、两端契约与联调、权限/数据隔离、迁移与任务、日志、测试和文档一致性；并行开发各自通过局部review不能代替这次整体审查。
- Review结果区分缺陷与建议，记录修复和实际复核证据；文档审查按阶段记入 [delivery/reviews](docs/delivery/reviews/reorganization.md)，工程建立后按交付记录归档。大阶段全盘review不能以测试通过代替，review无问题也不能代替运行验收。

## MyHome 与工作区边界

相邻 MyHome 仓库是参考与基础设施来源，不是 Haruka 的运行时导入目录。共享实例仍要使用 Haruka 的独立数据库/账号、Bucket、Redis/Kafka 命名与权限。

当前文档工作不涉及修改 MyHome 或生产服务。后续接入时遵守用户授权范围和目标仓库自身规范；不得借测试修改 MyHome 业务数据，也不得在文档中写入实际秘密。

## 完成与交付

- 完成当前任务必要工作，不顺带部署、修改生产配置或扩展产品范围。
- 更新受影响的需求、专题、导航和路线图；实施完成需有验证依据后再勾选。
- 汇报具体改动、实际检查结果及未验证事项；不伪造测试、运行状态或完成度。
- 按小阶段提交规则提供实际commit哈希；无法提交时说明原因和未完成状态。遵循仓库实际CI约定，不编造既有提交历史或PR模板。
