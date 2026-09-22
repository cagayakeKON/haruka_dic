# Haruka（ハルカ）

把用户自己的小说、文章、教材和试卷，变成可阅读、可朗读、可练习、可模拟考试的语言学习资料库。

## 当前方向

- Flutter 前端：Windows、Web、Android。
- Python 后端，前后端分离；复用 MyHome 的基础设施。
- 应用内 Agent 使用 Pydantic AI，卡片和题目使用 Pydantic 结构校验。
- 导入时可选择试卷模式，打开后整卷答题，交卷后 AI 批改评分并复盘。
- 日志沿用 MyHome 的 Alloy → Loki → Grafana；前端三端日志与埋点、后端、AI/TTS、数据库统一收集。
- 多用户注册登录，各自的资料、学习记录和模型 API Key 独立。
- 增加管理后台与完整 RBAC，控制两端登录、页面/菜单/按钮、接口及数据范围；管理端推荐 Flutter Web。
- 朗读使用 Gemini TTS 或 OpenRouter 上的 TTS 模型。
- 单词 CSV 导出与导入承担用户侧备份恢复，不提供整库打包恢复。

2026-09-22：已有需求/架构文档，旧 HTML 原型已按用户要求删除，目前仅讨论新的视觉方案，尚未创建 Flutter/Python 应用工程或部署服务。功能流程、接口/权限/数据契约、项目结构与工程规范已细化，并完成三位子Agent的交叉审查与修订复核；审查记录见下方。邮箱密码、每账号一个私有资料库为推荐设计，未确认产品选项独立登记。

脚手架补强已明确包/CLI、统一开发命令、构建身份、代码生成与阶段验收；新增两份专题并完成独立复审，B0/B1/B2与全部应用验收仍待实现。

## 文档入口

| 文档 | 用途 |
| --- | --- |
| [文档目录与维护规则](docs/README.md) | 分类、阅读顺序、规范归属 |
| [产品需求](docs/product/PRD.md) | 功能、优先级、验收与待确认事项 |
| [功能细化与验收索引](docs/planning/FEATURE_COVERAGE.md) | 每个功能对应的操作逻辑、异常、技术契约与验收ID |
| [架构总览](docs/architecture/OVERVIEW.md) | 技术选型、前后端职责与数据流 |
| [项目结构](docs/architecture/PROJECT_STRUCTURE.md) | 未来目录、模块职责、前后端依赖方向 |
| [脚手架蓝图](docs/engineering/SCAFFOLD_BLUEPRINT.md)、[脚手架验收](docs/engineering/SCAFFOLD_ACCEPTANCE.md) | 包与CLI、统一开发命令、应用身份、生成流程及B0/B1/B2参考闭环 |
| [接口契约](docs/architecture/API_CONTRACTS.md)、[权限目录](docs/architecture/PERMISSION_CATALOG.md)、[数据与任务](docs/architecture/DATA_AND_JOBS.md) | API、组合授权、状态/并发/幂等及持久执行的统一约定 |
| [认证与用户隔离](docs/architecture/AUTH_AND_ISOLATION.md) | 注册登录、三端会话、权限与个人 Key |
| [管理后台与 RBAC](docs/architecture/ADMIN_AND_RBAC.md) | 管理功能、角色权限、两端显示、后端授权、撤权与审计 |
| [Pydantic AI 运行层](docs/architecture/AGENT_RUNTIME.md) | 工具、上下文、卡片、会话存储、流式接口与重试 |
| [单词 CSV](docs/features/VOCABULARY_CSV.md) | 字段、导出、导入、重复处理与往返 |
| [试卷模式](docs/features/EXAM_MODE.md) | 试卷导入校对、考试答题、交卷、AI 批改与成绩 |
| [MyHome 复用](docs/engineering/MYHOME_REUSE.md) | 源码证据、复用边界、部署接入条件 |
| [统一日志与前端埋点](docs/engineering/OBSERVABILITY.md) | 全部来源采集、三端埋点、操作关联、脱敏与 Grafana 看板 |
| [实施计划](docs/planning/ROADMAP.md) | 六阶段交付与三端验收 |
| [代码规范](docs/engineering/CODE_STANDARDS.md)、[Lint规则](docs/engineering/LINT_RULES.md) | 类型、格式、静态分析与例外机制 |
| [测试规范](docs/engineering/TESTING.md)、[交付验收](docs/engineering/DELIVERY_ACCEPTANCE.md) | 测试矩阵、覆盖率/必需用例门禁、发布证据 |
| [前端 Test ID 与 E2E](docs/engineering/FRONTEND_E2E.md)、[测试数据](docs/engineering/TEST_DATA.md) | Flutter/Playwright/Patrol 分工、定位、场景工厂、隔离与清理 |
| [开发指南](docs/engineering/DEVELOPMENT.md)、[配置与运维](docs/engineering/CONFIGURATION_AND_OPERATIONS.md) | 初始化合同、环境、部署/故障/恢复流程 |
| [决策清单](docs/planning/DECISIONS_AND_ASSUMPTIONS.md)、[文档审查](docs/planning/DOCUMENT_REVIEW.md) | 推荐与待确认边界、独立review问题闭环 |
| [代理协作规范](AGENTS.md) | 编码代理的工作约定与检查要求 |

需求以 PRD 为准，技术契约在对应专题维护；已确认需求、推荐方案、待确认事项和实现状态分别标注。

## 推荐技术组合

Flutter + Riverpod + go_router + Dio + just_audio，管理端推荐 Flutter Web；Python 3.13 + FastAPI + Pydantic AI + Pydantic + SQLAlchemy Async + Alembic，RBAC 推荐 PyCasbin + 应用授权服务；共享 PostgreSQL、Redis、Kafka、MinIO。Flutter Telemetry 与 Python structlog 接入共享 Alloy、Loki、Grafana。客户端 Drift 承担本地缓存与有界日志补传队列。

## 下一步

工程阶段先按B0/B1/B2建立可重复脚手架、三端身份/收藏和Fake异步参考闭环，再完成两端登录、管理后台与RBAC及真实Agent/日志验证，继续推进EPUB出处、云端朗读、CSV往返和试卷答题评分。脚手架通过不代表阶段1或完整功能已交付；试卷文件格式范围仍待明确，详见 [实施计划](docs/planning/ROADMAP.md)。
