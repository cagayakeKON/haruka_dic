# Repository Guidelines

## 项目与当前状态

Haruka 是以用户自有材料为基础的 AI 语言学习应用。当前仓库包含需求/架构/计划、prototype/ HTML原型，以及frontend/ Flutter应用壳、backend/ Python包、scripts/开发入口和dev/隔离基础设施。阶段1的完整B0可重复工程基础已验收，B1/B2未实现；候选来源、完整矩阵与边界见docs/delivery/reviews/2026-09-22-b0-acceptance.md。现行产品设计语言为[「晴空频率」](docs/product/design-language.md)，整体方向已确认，手机/电脑HTML原型已按该语言重建，Flutter正式界面尚未迁移；不设“继续阅读”，演示边界见prototype/README.md。

文档任务只修改文档；用户要求开始实现时，按实施计划推进必要工程工作。不把计划当成已实现，不为了运行不存在的检查擅自创建项目骨架。

仓库只保留标准文件 AGENTS.md 作为代理规范唯一入口，不维护单数名称或其他重复副本。用户最新明确要求优先于旧文档；变更范围时同步相关文档。

## 开始工作前

先读 [项目入口](README.md) 和 [文档导航](docs/README.md)，确认实际文件、工作区变更、当前阶段与本次范围；保留用户及并行Agent已有工作。只读取当前任务相关正文，不假定未来工程/命令已经存在。

| 任务 | 必须读取的权威正文 |
| --- | --- |
| 产品/功能 | [产品总览](docs/product/overview.md)、对应modules规格、[功能与验收追踪](docs/delivery/coverage.md) |
| 产品视觉、组件、动效与文案 | [产品设计语言](docs/product/design-language.md)、[产品总览](docs/product/overview.md)、相关模块；落地Flutter时再读适配规范 |
| 身份、页面、业务动作与数据 | [认证](docs/architecture/authentication.md)、[RBAC](docs/architecture/authorization.md)、[权限目录](docs/contracts/permissions.md)、[API](docs/contracts/api.md)、[数据与任务](docs/architecture/data-jobs.md) |
| 建表、ORM、逻辑关联、数据隔离与迁移 | [数据库规范](docs/engineering/database.md)、相关数据/认证设计；按DB验收证明已实现范围 |
| 阅读、选区、导入、CSV或考试 | 对应[小说](docs/modules/novels.md)/[课本](docs/modules/textbooks.md)/[考试](docs/modules/exams.md)模块，以及[三类材料](docs/contracts/material-types.md)、[解析数据结构](docs/contracts/material-structures.md)、[出处](docs/contracts/content-locator.md)、[CSV](docs/contracts/vocabulary-csv.md)所涉及的契约 |
| Agent、卡片、会话、AI、TTS或模型Token统计 | [Agent运行层](docs/architecture/agent-runtime.md)、[AI与朗读模块](docs/modules/ai-speech.md)、[模型用量统计](docs/contracts/model-usage.md) |
| 编码、初始化或构建 | [项目结构](docs/architecture/project-structure.md)、[代码规范](docs/engineering/coding.md)、[Lint](docs/engineering/lint.md)、[脚手架](docs/engineering/scaffold.md)、[B0/B1/B2](docs/delivery/milestones/scaffold.md) |
| 后端接口、模块、返回/异常与多语言 | [后端开发手册](docs/engineering/backend.md)、[统一返回契约](docs/contracts/api-responses.md)、相关API/权限/数据设计 |
| Flutter页面、移动端交互与跨平台适配 | [Flutter开发与适配规范](docs/engineering/flutter.md)、[项目结构](docs/architecture/project-structure.md)、对应模块及前端测试 |
| 控件、测试与数据工厂 | [测试策略](docs/engineering/testing/strategy.md)、[前端E2E](docs/engineering/testing/frontend-e2e.md)、[测试数据](docs/engineering/testing/data.md) |
| 前端/API/Worker/数据库日志与部署 | [观测](docs/operations/observability.md)、[MyHome复用](docs/operations/myhome-integration.md)、[配置](docs/operations/configuration.md)、[部署恢复](docs/operations/deployment-recovery.md) |
| 交付或未决方案 | [路线图](docs/delivery/roadmap.md)、[交付验收](docs/delivery/acceptance.md)、[决策待办](docs/decisions/pending.md) |

## 已确认的产品边界

- Flutter：Windows、Web、Android；Python 前后端分离。
- 导入材料只适配小说、课本、试卷；material_type唯一，三类分别处理、建模和使用专属页面/controller，仅复用基础能力。文件格式单独定范围，不保留“其他/混合/文章/笔记”类型或跨类型皮肤切换；选错类型需显式创建新材料重新处理，保留旧记录。
- 材料上传首版暂限日语/英语，三类及追加文字听力稿均由前后端/Worker复核；中文UI、释义和教材辅助说明不扩展材料白名单。日语NLP固定SudachiPy SplitMode.B（中粒度），英语固定spaCy；不提供粒度切换，具体字典/英语模型包及版本需工程验证，第三语言只保留明确降级的范围操作，见[语言准入](docs/contracts/material-types.md#11-首版材料语言)和[NLP适配](docs/architecture/text-analysis.md#11-已确认的日英nlp适配)。
- OCR统一使用用户配置的视觉模型，经过Pydantic AI与统一任务/调用上限/日志入口；不建立或静默回退传统OCR。文件渲染/可用文本层直接提取仍是确定性处理，三类专用校验保持独立，详见[视觉OCR](docs/architecture/vision-recognition.md)。
- EPUB真实文本直接解析，扫描/图像型PDF及图片使用本人视觉模型OCR；必须保留原书ruby的基础文字、注音及对应关系，不混入canonical_text，未可靠识别不以NLP猜测冒充原书读法，见[提取契约](docs/contracts/source-extraction.md)。所有已提交可学习文字（含AI释义/例句/译文/题目反馈）统一做[基础NLP](docs/architecture/text-analysis.md)，随内容预加载和持久保存；NLP失败不重调AI，长按使用已有标注，缺失仍可手动调整。源版本、分析版本、AI结果与TTS规格独立管理，考试可见性和格式开放阶段继续受原边界约束。
- 独立查询界面支持文字/图片/图文混合输入、语言学习查询及单词/句子/语法/习题卡片收藏，查询由AI自动判断任务、输入区不显示类型选择；不支持自由问答或通用回答卡片，图片仅用于语言句段翻译、语法解析和习题批改；Web支持图片选择/粘贴，Android支持相册和直接拍照，附件为本人私有会话资产，含图查询使用本人视觉模型；沿用Agent权限/本人Key，不默认授权联网或任意工具。材料主入口直接阅读/学习/试卷准备，列表另设详情；解析进度使用有权WebSocket。
- 应用内 Agent 框架已确定为 Pydantic AI，作为语言查询、解释、出题、批改和诊断等功能共用的后端能力；用户端不提供独立聊天页面、会话管理或“问学习Agent”入口；使用 Pydantic 业务输出模型，不另建 LangChain/LangGraph Agent 执行路径。
- 普通学习文字及服务端确认交卷后的可见复盘文字长按整句浮起并自动分词，词气泡可多选查询、完整结果可收藏，浮层喇叭朗读整句；单词旁小喇叭直接发音。小说必须处理全书逐句基础NLP/读音，提供阅读/解析模式、ruby及点句详解/朗读/收藏；章节准备以独立checkbox多选AI解析、朗读或两项，默认全选、空选禁用，逐句持久保存并分别显示本机就绪，详见[章节准备](docs/contracts/novel-preparation.md)。小说支持当前句到章末连续朗读、逐句缓存和高亮，长按/查询暂停且手动继续，不能与书库“继续阅读”入口混淆。所有完整有权题目可直接收藏，普通题作答前后均开放，试卷题仅交卷成功后开放且不要求评分完成；不复制隐藏答案/听力稿或未发布评分，收藏不影响作答/成绩/掌握。
- 支持导入时选择试卷模式、整卷作答、交卷后 AI 判断/评分；试卷首版文件格式范围仍待明确，不能将推荐的 PDF/OCR 优先级当作已确认。
- 试卷P0可为既有试卷上传UTF-8文字听力稿，或从试卷正文/已发布视觉转写提取听力脚本候选；AI必须为疑似听力题给出有证据的类型标记并提出脚本与题组/小题候选匹配，用户校对确认后才使用本人Gemini/OpenRouter TTS生成并冻结私有音频。原始音频上传、转写、切段和自动绑定列为P1待办，P0接口必须拒绝。
- 多用户注册登录，资料、学习记录、任务、私有缓存与模型 Key 按用户隔离；收藏库标准单词独立发音为同实例跨用户共享目录，匹配语种/读音/声音配置，个人关联和用量仍隔离。
- 注册仅要求当前身份策略字段；头像、出生年份/性别、母语/解释语言/学习语言、水平/目标和时区属于可选本人资料/学习档案，不得成为登录门槛。资料默认不公开，人口字段默认不进AI；头像走专用临时上传、受限解码/去元数据/重编码和每次鉴权的private/no-store读取，应用副本按实例/账号/资产分区，详见[账号](docs/modules/accounts.md)与[设置](docs/modules/settings.md)。
- 用户可创建多个单词本，单词/短语/语法/句子/摘录/习题卡片均可归本；进入即收藏条目列表，查看详情和切换/管理词本使用dialog。同条目可入多本，单词共用学习状态；删本只移除归类。每日单词只展示按本人时区划分的实际加入历史。单词掌握由有效习题证据自动计算，禁止UI/API/CSV手改mastery。用户端不支持词汇复习、每日/到期队列、SRS/FSRS、ReviewOpportunity或新词额度；单词本只负责组织和AI习题选源，见[单词本](docs/modules/vocabulary-notebooks.md)与[学习证据](docs/architecture/vocabulary-learning.md)。
- P0提供独立[AI习题与错题库](docs/modules/ai-exercises.md)：用户显式选择单词本、收藏、教材、错题或诊断来源并确认后使用本人Key生成，不后台自动出题。服务端对教材题、AI习题和试卷的全部可靠错误/部分正确幂等留档；用户可以收藏任一历史错题，收藏与当前错误/纠正/作废状态独立，针对性生成只消费当前有效且有权的事实。
- 管理后台和完整 RBAC 为 P0；控制用户端/管理端登录、页面/菜单/按钮、接口与数据范围；Flutter Web 管理端及 PyCasbin 为当前推荐实现。
- 用户各自提供 API Key；朗读使用 Gemini TTS 或 OpenRouter TTS，不能静默替换成系统 TTS。
- 当前不建设Haruka商业化系统；不引入套餐、应用余额、购买或金额结算。每个真实供应商attempt按[模型用量统计](docs/contracts/model-usage.md)保存input/output/cache及可得的其他用量，技术限额只用于运行保护。
- 用户侧备份恢复仅为单词 CSV 导出与导入，不新增整库 ZIP、原书/音频打包或全库恢复。
- 复用 MyHome 基础设施与可适配机制，Haruka 维护独立业务、数据库、凭据、账号和部署。
- 所有前端/后端/数据库/AI/TTS 日志及前端业务埋点统一进入 MyHome 的 Alloy/Loki/Grafana；正常事件也要采集，不能仅上报 warn/error。
- 首版离线范围为当前账号有效权限租期内已有阅读、词句解释和允许离线的音频副本，按实际来源与动作权限读取；有限播放次数的试卷听力必须走在线场次attempt账本，不进入通用持久离线音频缓存。管理后台必须在线，不扩展成完整离线编辑同步。

## 文档组织与实现约定

- product放产品范围，modules放功能流程，architecture放公共设计，contracts放协议说明，engineering放开发与测试，operations放运行配置与观测，delivery放阶段与验收，decisions放决策及待决项。
- PRD 定义需求，专题文档定义详细协议；避免复制同一字段表或状态机到多处。
- 使用相对 Markdown 链接，移动或重命名后修复引用；删除过时方案时同步导航和计划。
- 将已确认、推荐、待验证和已实现分开标注。中文用于产品文档和沟通，代码标识保持清晰一致。
- 工程使用frontend/、backend/、scripts/、tools/和根contracts/；所有开发Compose与初始化/采集配置放dev/，deploy/及业务数据/任务工程尚未建立。只创建当前职责需要的模块，不预建后续空目录。
- Flutter 保持功能模块、UI 状态与数据访问分层，平台差异放入适配层；Python 保持路由、服务、仓储和供应商适配分离。
- Flutter共享业务/数据，复杂页面允许独立紧凑/宽屏布局；空间、输入和平台能力分别判断。布局切换保留账号/资源作用域内的状态，不重复请求/发起供应商调用或重置考试；Android专属系统行为与真机优化按Flutter适配规范验收。
- 用户/管理JSON接口统一使用具体化的SuccessResponse[T]、PageResponse[T]与ErrorResponse；服务返回业务结果，路由包装成功，统一处理器包装异常；204/文件/SSE保留原生传输语义，字段/语言/HTTP映射只在返回契约维护。
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
- 幂等键、模型配置、解释/私有TTS缓存及通知按用户分区；仅受控global_word目录资产和生成占用按实例共享，不用owner为空扩大私有查询。换账号处理旧本机缓存、下载和迟到响应；全局命中不暴露他人Job/Key，缺失不自动借他人Key生成。
- 完整成功的词句/AI解释与TTS自动持久保存，不要求收藏；有效引用期间不按TTL/LRU删除。Redis/本机只是可淘汰副本，miss先查持久结果；匹配、重生成与跨配置迟到发布以[学习结果缓存](docs/architecture/learning-cache.md)为准，不因换Key/默认模型升级或清本机缓存隐式重新调用供应商。
- 密码哈希存储；任何哈希替换推进password_version，改密提交锁内复核password_version/security_epoch/当前会话，提交后结果未知不得自动重放或宣称未修改；模型 Key 按用户加密；密码、Token、Key 不进入日志、队列或 CSV。
- credential_version与部署encryption_key_version分开；部署旧密钥不能因在线重加密完成就销毁，仍需保留依赖历史备份的恢复能力。
- 缺少用户 Key 时不回退到其他用户或 MyHome 的 Key。常规测试使用模拟供应商，真实调用只在任务需要且已获授权的范围内执行。
- 稳定内容 ID、内容版本和选区偏移由应用维护；AI 不得重写原文或绕过 schema/归属校验。
- 长任务先持久化 Job/Outbox；重复投递和重启不得重复提交业务结果，不承诺外部供应商恰好只执行一次。
- Pydantic AI 的运行依赖按用户注入，不能通过全局环境变量或共享可变模型客户端切换个人 Key；对话存储不等于任意步骤自动续跑，首版在已提交业务阶段边界恢复。
- Worker/Agent 工具与每个新的供应商调用阶段重查当前权限；撤权保留已提交数据，固定系统维护主体只做允许的封存/清理，不能变成任意用户调用。
- CSV 导入先预览确认，重复处理和来源回跳遵循规范，不能借导入 ID 覆盖他人数据。
- 单词CSV当前草案v2兼容v1，词本归属按本人权限恢复，导入掌握快照不是有效学习证据；内容学习版本、跨端辅助记录及重评重放遵循学习状态专题，不能用模型自报或埋点判掌握。CSV不备份错题、作答或AI习题历史。
- 考试使用冻结试卷版本，答卷由服务端保存，时限由服务端判定，交卷幂等且锁定答案；题面接口不返回答案/解析，普通练习仍可逐题反馈。
- AI 评分用类型化契约，分值/归属校验和总分累计由程序完成；无标准答案标记 AI 评估，失败/待复核不能计作零分，重评保留历史且不重复累计学习记录。
- 评分active/effective和generation分开，旧run迟到不能覆盖新成绩；材料删除用tombstone/代次阻止复活，冻结考试引用由受控GC保留。
- 上传只向客户端开放临时对象，后端发布验证后的不可变final对象；Worker不读取可被旧上传签名覆盖的来源。
- Flutter 使用统一 Telemetry，Python 使用统一 logging/structlog 出口；保持 operation/request/job/AI 关联，新增服务同步采集清单，禁止上传请求递归产生日志。
- 前端日志和埋点按事件白名单脱敏，身份由接收端绑定；队列按账号隔离，换账号不能补发为新用户。用户/请求等高基数字段不能成为 Loki 索引标签。
- AI 日志不记录原始 Prompt/回复/工具正文，SQL 日志不记录绑定参数；业务成功以服务端提交为准，模型Token用量以持久attempt记录为准，不能把埋点当权限、用量或学习数据的权威来源。
- 应用缓存命中不创建零Token模型调用；供应商Prompt缓存读取/写入仍属于真实attempt，分别记录cache_read_tokens/cache_write_tokens。未知用量为null，不用0代替，也不把AiRun汇总与attempt重复累加。

## 开发节奏、并行协作与提交

- 大阶段指 [路线图](docs/delivery/roadmap.md) 的阶段1～6及明确登记的发布大节点；小阶段指大阶段内可独立验收的工作单元，例如B0/B1/B2或一项功能切片。开始工作时明确所属阶段、交付范围和必要检查，不能为触发全量测试临时把小改动称作大节点。
- 前端与后端并行开发：先对齐API、DTO、权限/错误/事件契约与验收行为，再由不同Agent或开发者分别实现前端和后端，按小阶段联调。分工标明文件归属和共享契约负责人，避免并发覆盖同一文件；有依赖的契约/迁移变更先协调，不能让双方各自定义不兼容协议。文档任务不因此创建应用工程。
- 每个小阶段完成后必须创建一次本地Git commit，包含该阶段实现、相关测试和文档；先完成必要检查及本阶段review，说明行为变化与实际验证，再提交。不得积攒多个已完成小阶段到最后一起提交，也不默认push。
- 提交前检查工作区和暂存区，只暂存本阶段归属明确的改动，不夹带用户或并行Agent未完成的修改，不用无差别git add .。不要重写既有提交或伪造Git身份；尚未初始化Git或提交失败时如实报告，不能声称已提交。工程初始化必须建立版本控制，后续小阶段以实际commit哈希作为完成证据。

## 检查与测试

- 小阶段完成或修复bug时，只允许执行证明本次变更所必需的测试：优先最低有效层的回归用例、直接受影响模块/契约和必要的跨端或集成路径。先说明影响范围与选择依据，不默认运行全仓、全平台或所有E2E。
- 只有大阶段/大节点完成时才执行全量测试，范围为截至该节点已交付能力的完整必需矩阵和约定平台；不得因用例失败、设备缺失或准备不足缩小已承诺范围。尚未实现的后续阶段不冒充已通过，真实模型测试仍遵守既有授权边界。
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
