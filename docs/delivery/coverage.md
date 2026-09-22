# 功能与验收追踪

状态：2026-09-22，设计覆盖索引。这里只维护功能→权威正文→验收族的映射，不复制产品优先级或协议字段；所有应用验收仍待实现。产品范围见 [产品总览](../product/overview.md)，实施状态见 [路线图](roadmap.md)。

## 1. 按功能开始开发

| 功能入口 | 公共契约与设计 | 沿用的验收族/证据 |
| --- | --- | --- |
| [账号：注册、登录、恢复与会话](../modules/accounts.md) | [认证](../architecture/authentication.md)、[API](../contracts/api.md)、[授权](../architecture/authorization.md) | ACC；三端与管理Web、注册竞争、会话撤销与账号切换 |
| [材料：上传、书库、阅读和教材](../modules/materials-reading.md) | [出处](../contracts/content-locator.md)、[数据与任务](../architecture/data-jobs.md) | MAT/READ；不可变上传、Unicode、来源回跳、进度/书签 |
| [学习：收藏、照片、练习、评分和诊断](../modules/vocabulary-practice.md) | [权限](../contracts/permissions.md)、[数据与任务](../architecture/data-jobs.md) | COL/PHOTO/PRA/DIAG；重复与来源、规则/AI评分、有效贡献 |
| [单词CSV入口](../modules/vocabulary-practice.md) | [CSV唯一协议](../contracts/vocabulary-csv.md) | 原CSV清单；全部逻辑记录导出、预览/分批/重复策略、公式转义、跨账号往返 |
| [考试：导入、校对、答题、交卷与成绩](../modules/exams.md) | [API](../contracts/api.md)、[数据与任务](../architecture/data-jobs.md)、[出处](../contracts/content-locator.md) | 原考试清单及DAT；冻结版本、草稿/截止/锁卷、评分恢复与重评 |
| [AI与朗读：解释、卡片、对话和TTS](../modules/ai-speech.md) | [Agent运行层](../architecture/agent-runtime.md)、[API事件](../contracts/api.md) | AI/TTS；类型校验、权限/预算、流恢复、音频缓存与播放 |
| [后台：用户、角色、菜单、策略和运维](../modules/admin.md) | [RBAC](../architecture/authorization.md)、[权限目录](../contracts/permissions.md) | ADM/PERM；两端显示/接口一致、deny/继承/撤权、防提权与首末管理员 |
| [设置：Key、语言、服务实例与缓存](../modules/settings.md) | [认证与隔离](../architecture/authentication.md)、[运行配置](../operations/configuration.md) | SET/CACHE；凭据轮换、账号代次、离线租期、队列及迟到响应 |
| [统一日志与业务埋点](../operations/observability.md) | 各模块的事件映射、[MyHome接入](../operations/myhome-integration.md) | 原观测清单；全部来源/info事件、关联、脱敏、补传与采集缺口 |

模块中的验收项是行为要求，测试运行器和required_cases负责将其展开为真实case/平台/runner/参数；本文不能替代运行报告。原来只有检查清单的CSV、考试和观测验收保留原意，不虚构已经存在的编号化测试。

## 2. 公共工程与运行验收

| 范围 | 唯一方法/规则 | 实施验收 |
| --- | --- | --- |
| 目录、依赖与公共服务 | [项目结构](../architecture/project-structure.md)、[架构](../architecture/overview.md) | STR/API/DAT，依赖方向与真实事务/隔离 |
| 包、CLI、构建身份与生成 | [脚手架](../engineering/scaffold.md) | [B0/B1/B2里程碑](milestones/scaffold.md)的SCF |
| 前端定位与端到端测试 | [前端测试](../engineering/testing/frontend-e2e.md) | UIE，不用一种runner证据代替另一种 |
| 素材、场景、工厂与清理 | [测试数据](../engineering/testing/data.md) | TDS，先合法前置/实际目标动作，再停止写入并清理 |
| 检查与结果判定 | [Lint](../engineering/lint.md)、[测试策略](../engineering/testing/strategy.md) | 必需用例结果；大节点完整覆盖分母/阈值 |
| 配置、部署与恢复 | [配置](../operations/configuration.md)、[操作手册](../operations/deployment-recovery.md) | OPS与[交付验收](acceptance.md)要求的制品/恢复证据 |

开发和review节奏只由根 [AGENTS.md](../../AGENTS.md) 维护；这个索引不新增测试门槛、角色权限或交付承诺。

## 3. 范围变更

功能优先级只在产品总览维护，待决项只在 [决策待办](../decisions/pending.md) 维护。范围确认后，更新对应模块、受影响的公共契约、此映射和路线图；不得仅因为有测试素材或接口草案就扩大P0。

旧PRD章节与新归属的保全映射见 [重组记录](reviews/reorganization.md)。历史章节号只用于追溯，开发应使用上面的有效入口。
