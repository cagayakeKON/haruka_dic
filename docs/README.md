# 文档导航

状态：2026-09-22，文档重组进行中；Flutter/Python工程与B0/B1/B2尚未实现。各分类维护独立职责，后续阶段整理正文与任务导航。

## 分类与权威来源

| 分类 | 回答的问题 | 入口 |
| --- | --- | --- |
| 产品 | 为谁做、做什么、首版边界 | [产品总览](product/overview.md) |
| 功能模块 | 用户操作、前后端职责、功能验收 | [功能覆盖索引](delivery/coverage.md) |
| 架构 | 公共机制、职责和依赖 | [系统架构](architecture/overview.md)、[项目结构](architecture/project-structure.md) |
| 契约 | API、权限、数据格式 | [API](contracts/api.md)、[权限目录](contracts/permissions.md)、[CSV](contracts/vocabulary-csv.md) |
| 工程 | 编码、开发、检查和测试 | [开发指南](engineering/development.md)、[脚手架](engineering/scaffold.md)、[代码规范](engineering/coding.md)、[Lint](engineering/lint.md)、[测试](engineering/testing/strategy.md) |
| 运维 | MyHome复用、配置和观测 | [基础设施](operations/myhome-integration.md)、[配置](operations/configuration.md)、[日志](operations/observability.md) |
| 交付 | 阶段、进度、验收证据 | [路线图](delivery/roadmap.md)、[脚手架里程碑](delivery/milestones/scaffold.md)、[交付验收](delivery/acceptance.md) |
| 决策 | 当前选择、理由、待决问题 | [决策记录](decisions/README.md) |

## 功能入口

- [账号](modules/accounts.md)：注册、登录和账号操作；公共机制见 [认证](architecture/authentication.md)。
- [材料与阅读](modules/materials-reading.md)：导入、书库、阅读与出处。
- [收藏与练习](modules/vocabulary-practice.md)：词表、CSV入口、练习、诊断。
- [考试](modules/exams.md)：试卷、整卷答题、交卷、评分和复盘。
- [AI与朗读](modules/ai-speech.md)：解释、对话和TTS；公共机制见 [Agent运行层](architecture/agent-runtime.md)。
- [后台](modules/admin.md)：管理操作；公共机制见 [RBAC](architecture/authorization.md)。
- [设置](modules/settings.md)：个人Key、偏好、服务地址与缓存。

## 维护规则

- 每条规则只有一个权威出处，其他文档链接引用。模块不另定义API字段、权限码或公共事务协议。
- 产品范围、推荐、待决、未实现和实测状态分别表达，文档完成不表示应用完成。
- 根 [AGENTS.md](../AGENTS.md) 维护并行、提交、测试与review节奏，本目录不重复另一套执行规则。
- docs/contracts保存协议说明，未来根contracts保存机器生成契约；字段事实不双向手写维护。
- 相对链接随迁移更新，历史审查仅证明当时状态。见 [历史审查](delivery/reviews/2026-09-22-design.md)、[本轮重组记录](delivery/reviews/reorganization.md)。
