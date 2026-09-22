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
| D1 | 迁移归属、相对链接与原文保全 | 已检查并独立review通过，提交05bac69 |
| D2 | 产品总览、统一模块模板、公共协议和运维职责去重 | 已检查并独立review通过 |
| D3 | 任务导航、代理入口、阶段追踪与收尾检查 | 待执行 |

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

自动文档检查核对基线151个验收/决策定义ID，无丢失或重复；检查模块模板、本地链接/锚点/路径大小写、围栏、冲突标记及diff空白。不运行Flutter/Python应用测试，不把原型、推荐选择或静态检查计作运行验收。OPEN-10为保留的原需求契约缺口，不是本轮迁移丢失或已关闭的工程问题。
