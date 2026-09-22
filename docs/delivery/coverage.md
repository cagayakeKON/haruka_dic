# 功能细化与验收索引

状态：2026-09-22，文档覆盖索引；下列验收ID是未来测试/交付追踪标识，不代表已通过。

每个P0功能必须同时具备入口与权限、正常操作、状态/异常、数据与接口、日志、三平台边界和可判定验收。跨功能契约只在一个地方维护：API名称以 [接口契约](../contracts/api.md) 为准；权限代码以 [权限目录](../contracts/permissions.md) 为准；事务/并发以 [数据与任务](../architecture/data-jobs.md) 为准。

| PRD范围 | 详细合同 | 验收族/重点 |
| --- | --- | --- |
| 7.7、8.8 注册/登录/账号 | [账号流程](../modules/accounts.md)、[认证隔离](../architecture/authentication.md) | ACC：注册激活、两端登录、续期/轮换、改密/恢复、强退、账号切换 |
| 8.1 导入与AI结构化 | [材料与阅读](../modules/materials-reading.md) | MAT：上传/确定性解析/授权AI分析、校验、阶段失败/取消、版本与删除 |
| 8.2 普通阅读/教材/题目 | [材料与阅读](../modules/materials-reading.md)、[收藏与练习](../modules/vocabulary-practice.md) | READ/PRA：内容块/出处、选区、进度/书签、题型渲染/反馈 |
| 8.3.1 选区与来源 | [材料与阅读](../modules/materials-reading.md) | READ：Unicode、冻结原文、来源失效/回跳 |
| 8.3.2 云端朗读 | [AI与TTS](../modules/ai-speech.md) | TTS：供应商能力、真实格式、缓存/排队、播放/中断/拖动、费用与三平台 |
| 8.3.3 解释与反馈 | [AI与TTS](../modules/ai-speech.md) | AI：流式、完整卡片、来源、反馈、不确定调用 |
| 8.3.4 收藏/笔记/标签/搜索 | [收藏与练习](../modules/vocabulary-practice.md) | COL：重复/合并/编辑、来源快照、删除不串用 |
| 8.3.5、8.9 CSV | [CSV](../contracts/vocabulary-csv.md) | CSV专题用例：全量导出/转义、预览/合并/分批、无Key、三端保存 |
| 8.3.5 拍照识词 | [收藏与练习](../modules/vocabulary-practice.md) | PHOTO：识别候选、用户修正确认、重复与收费授权 |
| 8.4、8.5 普通练习/评分/错题 | [收藏与练习](../modules/vocabulary-practice.md)、[数据与任务](../architecture/data-jobs.md) | PRA/DAT：已有题/出新题分离、Attempt、评分代次、申诉/待审、贡献替换 |
| 8.6 学习者模型/诊断 | [收藏与练习](../modules/vocabulary-practice.md) | DIAG：依据真实数据、样本不足、维度/窗口、可追溯建议 |
| 8.7 Agent/类型化卡片 | [AI与TTS](../modules/ai-speech.md)、[运行层](../architecture/agent-runtime.md) | AI：会话/工具权限、卡片、流恢复、预算/重试 |
| 8.8 Key/偏好/服务地址/缓存 | [设置与缓存](../modules/settings.md) | SET/CACHE：掩码/轮换/显式测试、按实例隔离、离线租约/换账号 |
| 8.10 全来源日志/埋点 | [观测规范](../operations/observability.md) | 日志专题清单：三端/管理/数据库/AI、来源字段、脱敏、积压/留存、故障探针 |
| 8.11 试卷/考试/成绩 | [试卷模式](../modules/exams.md)、[数据与任务](../architecture/data-jobs.md) | 考试专题用例/DAT：准备、校对、开考、草稿/接管/截止、交卷/批改/重评 |
| 8.12 管理后台 | [管理工作流](../modules/admin.md) | ADM：用户/会话、角色/菜单/策略、配额/任务、审计诊断 |
| 8.12 两端完整RBAC | [RBAC](../architecture/authorization.md)、[权限目录](../contracts/permissions.md) | PERM：每权限/依赖/页面/接口/数据域、撤权、委派边界、首末管理员 |
| 9、10、12 系统与质量 | [项目结构](../architecture/project-structure.md)、[架构](../architecture/overview.md)、[运行配置](../operations/configuration.md) | STR/API/DAT/OPS：分层、契约、幂等、部署与恢复 |

## 工程规范入口

- [代码规范](../engineering/coding.md)：命名、分层、类型、异步、错误/安全、依赖。
- [Lint规则](../engineering/lint.md)：Ruff/Pyright/Dart/Markdown配置草案、命令与豁免。
- [测试规范](../engineering/testing/strategy.md)：单元/集成/契约/widget/三端E2E/AI评估与覆盖门禁。
- [前端E2E](../engineering/testing/frontend-e2e.md)、[测试数据](../engineering/testing/data.md)：UI Test ID、Flutter/Playwright/Patrol分工、场景工厂与隔离清理，实施时映射UIE/TDS必需验收。
- [开发指南](../engineering/development.md)：目标目录、首次搭建、本地依赖和工作流。
- [脚手架蓝图](../engineering/scaffold.md)、[脚手架验收](milestones/scaffold.md)：包与进程入口、开发命令、构建身份、代码生成和20项SCF参考闭环验收。
- [交付验收](acceptance.md)：CI、review、制品、证据、回滚/恢复、签署条件。
- [路线图](roadmap.md)：交付阶段；[决策清单](../decisions/README.md)：尚待选择和验证边界。

## 后续范围

普通PDF/OCR/TXT、匹配/排序/听写、SRS、更多卡片、扩展写作/人工改分、下载管理增强属于PRD的P1；口语录音与完整离线写入等为P2。相关专题说明进入条件/复用结构，但不把尚未承诺功能伪装为P0实现。确认提前范围时同时更新PRD、此表、权限/API和验收。
