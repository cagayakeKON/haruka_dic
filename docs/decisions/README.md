# 决策与推荐基线

状态：2026-09-22 设计记录，未代表工程验证。本页保存已确认边界、DEC 选择/理由与导航；OPEN 项及尚未满足的就绪门禁统一在 [待决清单](pending.md)。需求冲突时用户最新明确要求优先；[产品总览](../product/overview.md) 定义范围，各专题维护详细契约。

## 1. 已确认

Flutter用户端Windows/Web/Android；Python前后端分离；复用MyHome基础设施；多用户注册登录；管理后台与完整RBAC；学习Agent采用Pydantic AI；Gemini/OpenRouter TTS；试卷模式/整卷考试/AI批改；全量来源日志与前端埋点汇入MyHome Alloy/Loki/Grafana；用户侧导出恢复仅单词CSV。本阶段只文档化，并要求子Agent独立审查。

2026-09-22补充确认：数据库不使用物理外键；业务表统一created_at/updated_at，参考MyHome公共Mixin。字段/隔离/关联/迁移实施基线见 [数据库规范](../engineering/database.md)，替代旧方案中以数据库外键保证跨表归属的做法。

同日进一步确认：导入材料只适配小说、课本、试卷，各自独立处理及使用体验。文件格式仍单独按原优先级和OPEN-01管理；类型拆分不等于确认所有PDF/TXT/OCR进入P0。

OCR统一使用视觉模型已由用户确认，拍照识词共用视觉调用基础；PDF文本提取/渲染可本地完成，不引入传统OCR或静默回退。具体模型仍待OPEN-04验证，格式范围仍按OPEN-01及产品优先级。

## 2. 当前实现建议

| ID | 选择与理由 | 验证/变更条件 |
| --- | --- | --- |
| DEC-01 | 单仓库Flutter应用+模块化FastAPI，API/Worker共用包不同进程 | 先满足三端和独立管理布局，出现明确规模需求再拆包/服务 |
| DEC-02 | 管理端先Flutter Web，PyCasbin封装于AuthorizationService | 阶段1验证策略投影、继承/deny/授予边界与两端快照，用户尚未单独确认库 |
| DEC-03 | PG保存AuthSession撤销/epoch，Redis保存会话材料 | 消除管理审计与异步删缓存之间的失效窗口 |
| DEC-04 | Web稳定opaque HttpOnly会话Cookie，原生短JWT+轮换refresh | Web普通续期不Set-Cookie，消除刷新迟到回退；身份变更和原生代次仍须竞态验证 |
| DEC-05 | Job/Outbox/Kafka+数据库阶段恢复，无新持久执行服务 | 供应商unknown结果不承诺恰好收费一次，显式受控重试 |
| DEC-06 | 单活动评分run、generation/CAS发布effective成绩 | 新重评失败保留旧结果，防止迟到覆盖与重复统计 |
| DEC-07 | Unicode scalar value偏移+canonical-text-v1 | 前后端用日文/组合字符/emoji往返验证，规范化升级需版本化 |
| DEC-08 | 原文与稳定ID由应用维护，AI输出只提供引用/候选 | 模型结构正确不等于来源正确，原文不让模型重写 |
| DEC-09 | 单Python发行包haruka-backend、app导入包、推荐Hatchling，四个正式CLI共用资源组装 | B0验证wheel与配套资源在仓库外启动；运行lock与直接/传递构建依赖约束分别验证 |
| DEC-10 | scripts/dev.py统一开发入口；后端注册定义单向导出OpenAPI/权限/错误/事件与Dart输出 | 具体载体/语义见脚手架蓝图；Dart生成器原型通过后锁定，临时手写DTO不能长期冒充已完成生成 |
| DEC-11 | 阶段1内分B0工程基础、B1身份/收藏、B2 Fake持久任务参考闭环 | 只验证限定能力，不替代完整注册/后台、真实AI质量或发布验收 |
| DEC-12 | flutter_test/integration_test为主，Playwright补Web、Patrol补Android；Windows原生驱动原型或明确人工验收 | 分工见[前端E2E](../engineering/testing/frontend-e2e.md)；Patrol已有Web能力但不支持Windows，版本与具体定位/系统能力仍须实测 |
| DEC-13 | UI Test ID前端JSON单源生成Dart并供Playwright读取；测试数据分资产/场景/执行实例 | 见[测试数据](../engineering/testing/data.md)；按执行身份隔离，工厂不代做目标动作，秘密另传，清理先处理在途写入 |
| DEC-14 | 用户确认无物理外键和公共创建/更新时间；工程采用共享表+ScopeContext、事务内逻辑关系校验及共同父行锁，不启用首版RLS | [数据库规范](../engineering/database.md) 的DB验收：UTC带时区、所有写入时间路径、实际PG关联/删除竞争；不宣称DB自动阻止任意SQL跨用户 |
| DEC-15 | 三类分别处理/建模/展示为用户已确认；设计采用唯一material_type、专用处理器/manifest/controller，选错类型显式创建新材料重新处理 | [三类材料契约](../contracts/material-types.md) TYPE及NOV/TBK/考试验收；保留原文件/出处基础能力，禁止类型换皮与通用接口泄露考试答案；当前未实现 |
| DEC-16 | 用户确认OCR统一视觉模型；Pydantic AI固定类型化调用，原件/页图准备与三类专用结果校验分开 | [视觉OCR](../architecture/vision-recognition.md) OCR-01～OCR-05按功能/获准格式验收；个人Key/预算、转写版本、定位粒度与失败恢复须验证，不走传统OCR后备 |

## 3. 决策导航与变更

| 阅读目的 | 权威正文 |
| --- | --- |
| 系统图、组件职责和技术基线 | [系统架构](../architecture/overview.md)、[项目结构](../architecture/project-structure.md) |
| 会话、RBAC、数据与持久任务 | [认证](../architecture/authentication.md)、[授权](../architecture/authorization.md)、[数据与任务](../architecture/data-jobs.md) |
| 接口、权限代码与出处 | [API](../contracts/api.md)、[权限目录](../contracts/permissions.md)、[出处契约](../contracts/content-locator.md) |
| 工程入口、生成与阶段边界 | [脚手架](../engineering/scaffold.md)、[B0/B1/B2 验收](../delivery/milestones/scaffold.md) |
| 配置、发布与恢复 | [运行配置](../operations/configuration.md)、[部署与恢复](../operations/deployment-recovery.md) |
| 未选方案、缺少的工程契约及最晚锁定点 | [待决清单](pending.md) |

DEC 编号保持稳定，方案变化时更新理由、影响和验证条件，并同步对应权威专题；不另复制接口字段或运行步骤。被选中、文档化与已实现/实测分别记录，推荐组件不能因写入本表就变成用户已确认或工程已验证。

B0/B1 允许的生成器评估/集中手写 DTO 过渡以脚手架的明确期限为准，B2 前必须锁定长期方案；待选库与未实现状态不等于功能已验收。开放选择不阻止无关工作，但依赖项未决不能签署相应就绪或交付门禁。

## 4. 设计假设与状态维护

所有数值初值（会话/日志队列/上传/任务限额/测试门槛）属于本项目建议，不是供应商保证或MyHome生产事实。改动时只在对应权威专题修改数值，其他文件链接，避免多份默认值互相冲突。

审查问题和修复记录放 [文档审查记录](../delivery/reviews/2026-09-22-design.md)。文档完成表示覆盖与一致性达到审查门槛；工程lint、测试、模型质量、平台发布与部署仍按 [交付验收](../delivery/acceptance.md) 提供真实证据。
