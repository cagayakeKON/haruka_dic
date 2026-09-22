# 文档重组与内容保全记录

状态：2026-09-22，D1～D3文档重组完成。原文基线为本地Git提交01255fc；本轮仅修改文档，应用与原型的独立工作不计入本轮交付。

## 1. 迁移归属

第一小阶段只迁移既有正文、重算相对链接；旧路径在本表中仅作历史映射，不是有效入口。后续正文整理沿用原需求边界与验收ID。

| 原路径 | 新归属 |
| --- | --- |
| docs/product/PRD.md | docs/product/overview.md |
| docs/features/ACCOUNT_FLOWS.md | docs/modules/accounts.md |
| docs/features/ADMIN_WORKFLOWS.md | docs/modules/admin.md |
| docs/features/AI_AND_TTS.md | docs/modules/ai-speech.md |
| docs/features/COLLECTIONS_AND_PRACTICE.md | docs/modules/vocabulary-practice.md |
| docs/features/EXAM_MODE.md | docs/modules/exams.md |
| docs/features/MATERIALS_AND_READING.md | docs/modules/materials-reading.md |
| docs/features/SETTINGS_AND_CACHE.md | docs/modules/settings.md |
| docs/features/VOCABULARY_CSV.md | docs/contracts/vocabulary-csv.md |
| docs/architecture/API_CONTRACTS.md | docs/contracts/api.md |
| docs/architecture/PERMISSION_CATALOG.md | docs/contracts/permissions.md |
| docs/architecture/OVERVIEW.md | docs/architecture/overview.md |
| docs/architecture/AUTH_AND_ISOLATION.md | docs/architecture/authentication.md |
| docs/architecture/ADMIN_AND_RBAC.md | docs/architecture/authorization.md |
| docs/architecture/AGENT_RUNTIME.md | docs/architecture/agent-runtime.md |
| docs/architecture/DATA_AND_JOBS.md | docs/architecture/data-jobs.md |
| docs/architecture/PROJECT_STRUCTURE.md | docs/architecture/project-structure.md |
| docs/engineering/CODE_STANDARDS.md | docs/engineering/coding.md |
| docs/engineering/LINT_RULES.md | docs/engineering/lint.md |
| docs/engineering/DEVELOPMENT.md | docs/engineering/development.md |
| docs/engineering/SCAFFOLD_BLUEPRINT.md | docs/engineering/scaffold.md |
| docs/engineering/SCAFFOLD_ACCEPTANCE.md | docs/delivery/milestones/scaffold.md |
| docs/engineering/DELIVERY_ACCEPTANCE.md | docs/delivery/acceptance.md |
| docs/engineering/TESTING.md | docs/engineering/testing/strategy.md |
| docs/engineering/FRONTEND_E2E.md | docs/engineering/testing/frontend-e2e.md |
| docs/engineering/TEST_DATA.md | docs/engineering/testing/data.md |
| docs/engineering/OBSERVABILITY.md | docs/operations/observability.md |
| docs/engineering/MYHOME_REUSE.md | docs/operations/myhome-integration.md |
| docs/engineering/CONFIGURATION_AND_OPERATIONS.md | docs/operations/configuration.md |
| docs/planning/ROADMAP.md | docs/delivery/roadmap.md |
| docs/planning/FEATURE_COVERAGE.md | docs/delivery/coverage.md |
| docs/planning/DOCUMENT_REVIEW.md | docs/delivery/reviews/2026-09-22-design.md |
| docs/planning/DECISIONS_AND_ASSUMPTIONS.md | docs/decisions/README.md |

## 2. 阶段记录

| 小阶段 | 内容 | 状态 |
| --- | --- | --- |
| D1 | 迁移归属、相对链接与原文保全 | 已检查并独立review通过，提交05bac69 |
| D2 | 产品总览、统一模块模板、公共协议和运维职责去重 | 已检查并独立review通过，提交050d2d7 |
| D3 | 任务导航、代理入口、阶段追踪与收尾检查 | 已检查并独立review通过，本记录与四份入口随本阶段提交 |

## 3. D1检查与review

architecture_review独立对照基线，33份迁移文档除链接目标外正文一致，验收ID及引用次数保留。37份Markdown的459个本地链接有效，其中29个为仓库外参考链接；没有运行应用测试。D1-01为Windows大小写改名未入Git索引问题，已用显式改名修复，reviewer读回overview.md与development.md的暂存路径后关闭；本阶段无遗留缺陷。

## 4. D2正文归属与保全

原文基线用于核对需求，不用于覆盖其他工作的后续明确更新。并行原型工作带来的HTML原型现状、中性底色/Primary和不设继续阅读区域等文档更新予以保留；原型代码及其独立提交不属于本轮实现或测试证据。

| 原PRD内容 | 当前权威归属 |
| --- | --- |
| §1～7 定位、用户、原则、目标/指标、信息架构与核心旅程 | 产品总览保留范围和摘要；操作细节进入相应模块 |
| §8.1/8.2 导入、阅读与教材 | materials-reading模块；原文定位字段独立到content-locator契约 |
| §8.3 选区、解释、朗读、收藏、CSV/照片 | materials-reading、ai-speech、vocabulary-practice模块；CSV格式/重复处理仍在专用契约 |
| §8.4～8.6 练习、评分、错题、学习者与诊断 | vocabulary-practice模块；持久关系/贡献/代次在data-jobs设计 |
| §8.7 Agent与卡片 | ai-speech模块及agent-runtime公共设计 |
| §8.8 账号、Key与偏好/缓存 | accounts/settings模块；Web/原生会话算法集中authentication设计 |
| §8.9 单词备份恢复 | vocabulary-practice入口及vocabulary-csv契约 |
| §8.10 日志与埋点 | operations/observability及各模块事件映射 |
| §8.11/8.12 考试、后台与RBAC | exams/admin模块；授权机制与权限目录各自单源 |
| §9/10 公共领域、AI和语种适配 | data-jobs、架构总览及agent-runtime；产品语种范围仍由产品总览维护 |
| §11～15 隐私、非功能目标、版本范围、范围外与风险 | 产品总览保留产品要求/目标值；执行机制链接对应公共设计与运维 |
| §16 决策及待决 | decisions/README与pending，DEC/OPEN编号保留 |
| §17 下一步 | delivery/roadmap，不再在产品正文复制实施计划 |

额外归并：配置与交付中的部署/回滚/恢复步骤集中到operations/deployment-recovery；交付规范只维护证据与门禁。原账号模块会话节、材料模块出处节原文完整迁入公共权威文档。原PRD“用户可删除AI生成错误题”尚缺具体操作/权限/API合同，保留为原需求并在OPEN-10登记，不擅自降级或发明已实现接口。

## 5. D2检查与review

产品总览整理为173行，七个模块均按范围/入口/权限、流程/状态/异常、前端职责、后端职责、共享契约、验收、待决/后续七节组织。界面与后端共用一份功能规格，认证算法、出处字段、权限代码、CSV及运行流程各有明确权威正文。

architecture_review完成第1轮独立审查：公共抽取原文的字段/数值/算法完整；原PRD独有功能、优先级、成功指标及非功能目标已有承接；旧管理功能表完整进入管理模块；DEC和原OPEN选择未被改变，OPS运行验收保持完整。91个模块验收ID与考试12条未编号清单保留；CSV及观测原验收仍在对应权威文档，不为统一模板删改。未发现需要修订的问题，无需第2轮。

自动文档检查核对基线151个验收/决策定义ID，无丢失或重复；检查模块模板、本地链接/锚点/路径大小写、围栏、冲突标记及diff空白。D2暂存版本的41份Markdown、615个本地链接（含29个外仓参考）及17个围栏通过；没有将D3入口草稿提前纳入D2提交。不运行Flutter/Python应用测试，不把原型、推荐选择或静态检查计作运行验收。OPEN-10为保留的原需求契约缺口，不是本轮迁移丢失或已关闭的工程问题。

## 6. D3入口与收尾

根README提供项目状态和主要入口；docs/README按任务、七个功能模块和八类职责导航；AGENTS保留唯一代理规范并指向权威专题；路线图只维护正式工程阶段、未决门禁和实际进度，文档完成不勾选应用验收。

engineering_specs作为非作者完成第1轮只读review：四份入口的117个本地链接有效；全部39份docs可从根README访问，无孤立专题。从docs/README出发，根README/AGENTS及39份docs共41份文档全部可达，最多2次跳转。相对D1，开发节奏/并行/提交、必要测试及分阶段review的10段关键用户规则原样保留。根目录只有AGENTS.md；原型现状、Primary/杂志式/不设继续阅读与Flutter/Python/B0/B1/B2未实现的区分准确。

最终工作树文档检查覆盖41份Markdown的619个本地链接、锚点、大小写和围栏；入口及记录的提交检查按D3改动范围执行，未重跑应用测试或验证并行原型。D3无需要修订的问题，无需第2轮。D1的大小写问题已关闭；本次重组没有遗留缺陷。当前产品/平台/运行待决及OPEN-10仍由decisions/pending管理，不因整理完成而关闭。

三个小阶段分别提交，实际哈希以Git日志为证据；仅提交归属明确的文档，不纳入prototype的并行改动，不默认推送。

## 7. 后续DB1：数据库规范补全

2026-09-22，用户进一步明确不使用物理外键，业务表参考MyHome统一创建/更新时间，并补齐建表规范和数据隔离。本阶段基线为1e86dae，单独文档小阶段，不改写上面D1～D3的历史结论；规范入口为 [数据库规范](../../engineering/database.md)。

engineering_specs只读核对MyHome：TimestampMixin使用created_at/updated_at及server_default=func.now()，updated_at另有onupdate；Base未配置统一命名；实际源码/迁移存在时间类型差异，TenantOwnedMixin等确有物理外键。Haruka仅采用字段/Mixin思路，保留既有UTC带时区契约，禁外键来自用户本次决定。没有连接数据库、修改MyHome或把源码观察当生产事实。

根Agent负责数据库规范、时间/CSV映射、入口/代码/Lint/脚手架/字典/配置/验收/决策同步；feature_specs负责认证、数据任务、收藏合并、测试策略/工厂及路线图。规范覆盖命名、字段/空值/精度、时间、共享表ScopeContext隔离、事务内逻辑关系、父删除竞争、索引、软删/历史、ORM示意、SQL、迁移、字典与DB-01～DB-12。现有DAT/COL/TDS等编号保留，旧“数据库外键保证跨库关系”的断言按新要求改为实际服务验证。

检查范围为本次文档的本地链接/锚点/大小写、围栏、既有验收ID保全、旧外键断言及示意Python语法。20份正文检查通过414个本地链接/12个围栏，后补配置和记录定点检查15个链接通过，共22份文档；基线157个验收/决策定义ID无丢失或重复，1个Python示意仅AST语法解析通过。有效文档无旧外键要求残留，diff空白检查通过；不安装依赖、运行应用/数据库测试或验证并行原型。

architecture_review完成第1轮非作者审查，未发现需要修订的P1/P2问题，无需第2轮。已复核无外键同父行锁/代次、ScopeContext、完整逻辑引用清单/保守GC、公共时间与CSV来源时间映射、Core/upsert/物理DELETE边界、运行与维护凭据分离，以及DB-01～DB-12分阶段验收均一致。DB1文档闭环完成，随本节创建独立本地commit；实际哈希以Git日志为证据。数据库/服务实现及相应运行验收仍未开始。

## 8. 后续BE1：后端开发与统一返回规范

2026-09-22，基线5a99bed。用户要求补齐后端开发规范，特别是统一API返回模型。本次为阶段1工程准备中的独立文档小阶段；不创建应用工程、部署或改变P0产品范围。

根Agent编写 [统一返回/异常/多语言](../../contracts/api-responses.md) 与 [后端开发手册](../../engineering/backend.md)，并同步API总则、模块结构、代码/Lint/开发/脚手架、设置、导航、AGENTS及阶段验收映射。engineering_specs只负责测试策略中的分层写法、AAA/参数化、fixture与依赖覆盖、mock边界；既有必需行为矩阵、覆盖分母/阈值和运行节奏未改变。

模型规范统一SuccessResponse[T]、PageResponse[T]、ErrorResponse；明确具体泛型、分页/null、请求ID、安全字段错误、异常/HTTP映射、生成OpenAPI、原生流/空体例外和客户端降级。后端手册明确跨模块入口、依赖生命周期与唯一事务提交者，提供未来路由模板和收藏写用例步骤。多语言区分UI文案与学习内容，P0仍仅中文UI，后续邮件模板不意味着新增已启用邮件功能。

初次必要检查覆盖15份正文的325个本地链接（含锚点/大小写）、15组围栏、3个Python示例的AST语法和3个JSON示例解析；受影响文档中原34个验收/决策引用ID均保留。使用仓库既有换行配置的git diff --check通过；未安装依赖、运行应用/数据库测试或验证并行原型。新增模板只有文档/语法证据，运行和生成器兼容性待B0/B1验证。

architecture_review完成第1轮非作者审查，未发现需修订的P1/P2问题，无需第2轮。已确认泛型与JSON模型、分页/null、400/422/500及原生刷新例外、字段清洗和流式边界一致；模块公开入口、唯一事务所有者与既有scope/授权一致；夹具覆盖模板可按既定生命周期实施，语言规则未扩展P0。新增记录另做定点文档检查，随本阶段创建本地commit，实际哈希以Git日志为证据；不默认推送。

## 9. 后续FE1：Flutter开发与适配规范

2026-09-22，基线aed9e6d。用户要求将Flutter移动端专用代码与优化方案文档化。本次是阶段1工程准备中的独立文档小阶段，由根Agent编写 [Flutter规范](../../engineering/flutter.md) 并同步目录、代码/开发/Lint/脚手架、前端测试、材料/考试模块和导航/阶段/验收索引；不修改原型或创建正式工程。

明确共享业务与独立compact/expanded布局，空间/输入/平台能力分开决策；布局切换保留业务身份、编辑/阅读位置且不重复请求/收费。规范覆盖输入法/焦点/系统返回、文件URI、音频中断、账号隔离、条件导入、可访问性、真机性能与埋点。初始断点不是原型CSS的验证结论；后台常驻播放、完整离线编辑/考试等边界未扩张。FLT-01～FLT-08分配到B0/B1/B2及实际功能阶段，未提前勾选工程验收。

必要文档检查覆盖15份正文的358个本地链接（含锚点/路径大小写）、11组围栏及1个既有JSON配置示例；受影响文档原58个验收/决策引用ID均保留，git diff --check通过。没有安装Flutter/插件、编译三端、运行应用测试或测量性能；HTML原型和文档检查不计作正式运行证据。新增记录另做定点检查。

architecture_review完成第1轮非作者只读审查，未发现需修订的P1/P2问题，无需第2轮。已确认独立视图与共享状态、空间/输入/能力分轴、IME/焦点/返回、账号代次与条件导入、真实平台证据及FLT分期一致；600/1024是待B0验证的逻辑像素基线，未冒充原型680px的实现，考试/离线/后台TTS范围未扩大。随本阶段创建本地commit，实际哈希以Git日志为证据，不默认推送。
