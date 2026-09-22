# 文档重组与内容保全记录

状态：2026-09-22，重组进行中，仅文档变更。原文基线为本地Git提交01255fc；不修改应用或原型。

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
| D1 | 迁移归属、相对链接与原文保全 | 已检查并独立review通过，完成后本地提交 |
| D2 | 产品总览、统一模块模板、公共协议和运维职责去重 | 待执行 |
| D3 | 任务导航、代理入口、阶段追踪与收尾检查 | 待执行 |

## 3. D1检查与review

architecture_review独立对照基线，33份迁移文档除链接目标外正文一致，验收ID及引用次数保留。37份Markdown的459个本地链接有效，其中29个为仓库外参考链接；没有运行应用测试。D1-01为Windows大小写改名未入Git索引问题，已用显式改名修复，reviewer读回overview.md与development.md的暂存路径后关闭；本阶段无遗留缺陷。
