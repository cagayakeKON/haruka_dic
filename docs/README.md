# 文档目录

本目录保存当前有效方案。更新日期：2026-09-22。Flutter/Python 正式实现仍处于规划阶段；旧 HTML 原型已按用户要求删除，新的视觉方案正在讨论，尚未制作。

## 目录与职责

~~~text
README.md                         项目入口
AGENTS.md                         代理协作规范（唯一入口）
docs/
  README.md                       文档导航与维护规则
  product/PRD.md                  产品需求、范围、优先级
  architecture/OVERVIEW.md         架构总览、选型、数据流
  architecture/PROJECT_STRUCTURE.md
                                  未来工程目录、依赖与模块职责
  architecture/API_CONTRACTS.md    接口、错误、版本、幂等、文件/事件
  architecture/DATA_AND_JOBS.md    数据约束、事务、任务与评分/删除竞态
  architecture/PERMISSION_CATALOG.md
                                  具体权限代码、依赖与动作映射
  architecture/AGENT_RUNTIME.md    Pydantic AI 运行层、工具与会话
  architecture/ADMIN_AND_RBAC.md   管理后台、角色权限、两端显示与撤权
  architecture/AUTH_AND_ISOLATION.md
                                  注册登录、会话、数据隔离
  features/VOCABULARY_CSV.md       单词 CSV 功能与字段协议
  features/EXAM_MODE.md            试卷导入、模拟考试、AI 批改与成绩
  features/ACCOUNT_FLOWS.md        注册登录、激活、续期、恢复、账号切换
  features/ADMIN_WORKFLOWS.md      后台各模块的操作、权限和失败处理
  features/MATERIALS_AND_READING.md
                                  导入、书库、出处、阅读/教材、删除
  features/COLLECTIONS_AND_PRACTICE.md
                                  收藏/照片/练习/评分/诊断
  features/AI_AND_TTS.md           解释、对话卡片、云端朗读与播放
  features/SETTINGS_AND_CACHE.md   个人Key/设置、三端缓存与离线
  engineering/MYHOME_REUSE.md      基础设施复用、源码证据、部署
  engineering/OBSERVABILITY.md     统一日志、Flutter 埋点、关联与看板
  engineering/CODE_STANDARDS.md    代码分层、类型、异步与安全规范
  engineering/LINT_RULES.md        Ruff/Pyright/Dart/Markdown规则合同
  engineering/TESTING.md           测试分层、矩阵、必需用例与覆盖门禁
  engineering/FRONTEND_E2E.md       Test ID、三端驱动、E2E执行与证据
  engineering/TEST_DATA.md          固定素材、场景、数据工厂及执行隔离
  engineering/DEVELOPMENT.md       工程初始化与日常开发流程
  engineering/SCAFFOLD_BLUEPRINT.md
                                  包与CLI、开发入口、构建身份、生成与种子协议
  engineering/SCAFFOLD_ACCEPTANCE.md
                                  B0/B1/B2参考闭环、SCF验收与实际证据
  engineering/DELIVERY_ACCEPTANCE.md
                                  CI、制品、独立review与交付门禁
  engineering/CONFIGURATION_AND_OPERATIONS.md
                                  配置、部署、故障、密钥与恢复
  planning/ROADMAP.md              阶段、依赖、验收、实际进度
  planning/FEATURE_COVERAGE.md      PRD→功能→技术/验收映射
  planning/DECISIONS_AND_ASSUMPTIONS.md
                                  已确认、推荐、开放决策/实测门禁
  planning/DOCUMENT_REVIEW.md       子Agent审查、修订与实际检查记录
~~~

## 阅读顺序

1. [项目入口](../README.md) 和 [PRD](product/PRD.md)：先了解产品边界。
2. [架构总览](architecture/OVERVIEW.md)、[认证隔离](architecture/AUTH_AND_ISOLATION.md)、[管理后台与 RBAC](architecture/ADMIN_AND_RBAC.md) 和 [Agent 运行层](architecture/AGENT_RUNTIME.md)：了解两端权限、多用户与 AI 约束。
3. [功能细化与验收索引](planning/FEATURE_COVERAGE.md)：定位登录、后台、导入/阅读、收藏/练习、AI/TTS、设置/缓存、CSV和试卷细节。
4. [项目结构](architecture/PROJECT_STRUCTURE.md)、[接口契约](architecture/API_CONTRACTS.md)、[权限目录](architecture/PERMISSION_CATALOG.md)、[数据与任务](architecture/DATA_AND_JOBS.md)：对齐模块、动作和事务边界。
5. [代码规范](engineering/CODE_STANDARDS.md)、[Lint](engineering/LINT_RULES.md)、[测试](engineering/TESTING.md)、[开发指南](engineering/DEVELOPMENT.md)、[交付验收](engineering/DELIVERY_ACCEPTANCE.md)：执行工程质量门禁。
   前端测试另读 [Test ID 与 E2E](engineering/FRONTEND_E2E.md)，夹具与环境准备另读 [测试数据](engineering/TEST_DATA.md)。
   工程初始化先落实 [脚手架蓝图](engineering/SCAFFOLD_BLUEPRINT.md) 与 [脚手架验收](engineering/SCAFFOLD_ACCEPTANCE.md)；B0/B1/B2是阶段1子里程碑，所有运行证据仍待工程阶段取得。
6. [MyHome复用](engineering/MYHOME_REUSE.md)、[日志埋点](engineering/OBSERVABILITY.md)、[配置运维](engineering/CONFIGURATION_AND_OPERATIONS.md)、[实施计划](planning/ROADMAP.md)：接入与交付。
7. [决策清单](planning/DECISIONS_AND_ASSUMPTIONS.md) 与 [文档审查](planning/DOCUMENT_REVIEW.md)：确认推荐、待决、未实测和review状态。

代理开始工作前另读根目录 [AGENTS.md](../AGENTS.md)。

## 当前决策摘要

| 事项 | 当前决定 |
| --- | --- |
| 用户模式 | 多用户，必须注册登录，数据相互隔离 |
| 管理与 RBAC | 已确认管理后台及完整 RBAC；两端登录、页面/菜单/按钮、后端操作与范围统一控制；管理 Web 与 PyCasbin 为推荐实现 |
| 平台与技术 | Flutter 三端 + Python 后端，复用 MyHome 基础设施 |
| Agent 框架 | 已确认 Pydantic AI；工具/输出模型与应用会话存储分工见运行层文档 |
| 试卷模式 | 已确认导入时选择试卷、整卷作答、交卷后 AI 批改；计时、保存、评分版本见专题设计 |
| 日志与埋点 | 统一接入 MyHome 的 Alloy/Loki/Grafana，覆盖三端前端、业务埋点、后端、AI/TTS、数据库与基础设施 |
| 模型凭据 | 各用户填写自己的 Key，由后端按用户加密管理 |
| 朗读 | Gemini TTS 或 OpenRouter TTS |
| 备份/恢复 | 仅单词 CSV 导出与导入，不包含整库和附件 |
| 推荐账号结构 | Haruka 独立账号，每人一个私有 Library；邮箱密码方式 |
| 尚待明确 | 试卷首版文件格式、账号附加流程、EPUB 还原要求、供应商默认值与实际部署条件 |

旧的无登录/个人共用库与完整 ZIP 备份方案已被本次要求替代，不再作为并行选项。旧平铺文件已归类迁移，旧备份文档已由单词 CSV 规范替代。

## 维护规则

- PRD 维护“做什么”，专题规范维护“怎么做”，路线图维护“交付顺序与验收”；字段协议不在多个文件重复定义。
- 具体权限代码以PERMISSION_CATALOG、接口/事件以API_CONTRACTS、跨功能事务以DATA_AND_JOBS为准；功能文档引用并解释流程，不私自另立路径或状态语义。遇到冲突先修正文档，不能靠任选一份实现。
- 脚手架蓝图维护工具/命令/生成物与构建身份的载体，脚手架验收维护SCF范围与证据；不复制测试阈值、认证状态机或产品功能清单。
- 改需求时同步规范与计划，尤其是管理/RBAC、用户边界、CSV 范围、试卷/评分、TTS、平台支持与日志/埋点契约。
- 区分已确认、推荐、待验证与已实现；未运行的检查不得写成通过。
- 使用相对 Markdown 链接，移动文件后检查所有引用。MyHome 链接依赖相邻源码仓库。
- 历史方案不在当前正文中保留为有效需求；需要保留时标注废弃和替代入口。
- 当前没有安装、启动或测试脚本；工程规范中的命令/配置均是标明前置条件的未来合同，初始化时落实并验证后才能报告通过。
