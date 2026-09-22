# 决策、推荐基线与待确认项

状态：2026-09-22设计记录，不代表工程验证。需求冲突时用户最新明确要求优先；[PRD](../product/PRD.md)定义范围，各专题定义详细契约。

## 1. 已确认

Flutter用户端Windows/Web/Android；Python前后端分离；复用MyHome基础设施；多用户注册登录；管理后台与完整RBAC；学习Agent采用Pydantic AI；Gemini/OpenRouter TTS；试卷模式/整卷考试/AI批改；全量来源日志与前端埋点汇入MyHome Alloy/Loki/Grafana；用户侧导出恢复仅单词CSV。本阶段只文档化，并要求子Agent独立审查。

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
| DEC-12 | flutter_test/integration_test为主，Playwright补Web、Patrol补Android；Windows原生驱动原型或明确人工验收 | 分工见[前端E2E](../engineering/FRONTEND_E2E.md)；Patrol已有Web能力但不支持Windows，版本与具体定位/系统能力仍须实测 |
| DEC-13 | UI Test ID前端JSON单源生成Dart并供Playwright读取；测试数据分资产/场景/执行实例 | 见[测试数据](../engineering/TEST_DATA.md)；按执行身份隔离，工厂不代做目标动作，秘密另传，清理先处理在途写入 |

## 3. 开放产品选项与安全默认边界

这些不是已知文档缺陷；共同流程已设计，最终选择进入对应专题与验收范围。未选择时不得自行声称某项已经确认或实现。

| ID | 待明确 | 当前建议/未确定时的边界 | 最晚锁定 |
| --- | --- | --- | --- |
| OPEN-01 | 试卷首版格式 | 推荐MD/EPUB+文本PDF；扫描/多图暂P1；用户尚未确认文本PDF提前 | 解析样本与首版工期冻结前 |
| OPEN-02 | 注册开放/审批、邮箱验证和恢复方式 | 已请求选择；推荐开放注册+邮箱验证/邮件找回；未有邮件服务则不公开承诺邮件能力，封闭开发用受控测试账号 | 账号工程契约冻结、公开注册前 |
| OPEN-03 | EPUB竖排/复杂注音还原要求 | 首版横排内容块、保留必要注音；不承诺高保真排版 | 阅读器样本/引擎选型前 |
| OPEN-04 | 默认供应商/具体模型与声音 | 推荐OpenRouter统一入口，Gemini直连可选；能力按实际验证结果启用 | 模型/TTS兼容测试前 |
| OPEN-05 | 普通教材无答案处理 | 显示待依据/AI参考来源，不伪装原答案；是否导入时生成由授权步骤配置，试卷按冻结依据规则 | 教材评分验收冻结前 |
| OPEN-06 | 实际部署网络/TLS/容量/恢复目标 | 仅核对MyHome源码，没有连接生产；任何资源上限/耗时目标均为待验证 | 接入/发布前 |
| OPEN-07 | Flutter/SDK依赖版本、Windows音频插件、代码生成器与CI托管 | 由原型兼容测试锁文件；当前不指定未经验证最新版 | 工程初始化阶段 |
| OPEN-08 | 应用发行身份、Windows安装格式与签名主体 | Android/Windows逻辑身份建议及dev/production隔离见脚手架蓝图；安装格式经原型选择，渠道身份不得当作已经注册 | B0固定开发构建矩阵；正式安装/签名发布前锁定发行项 |
| OPEN-09 | E2E工具具体版本、Web语义定位/性能、Android系统交互与Windows原生驱动 | 已确定工具分工，原型验证输入/焦点/文件/权限后锁定；Windows无驱动时采用结构化人工证据 | B0/B1定位与runner原型；具体原生能力交付前 |

无需等这些答案才能完成文档共同契约，但依赖项未锁定时不能签署相应工程交付通过。UI母语当前中文，目标语英/日；“中文在MVP支持”指界面/母语支持，不扩大成三套界面翻译承诺。

新增工程建议的具体入口与验收见 [脚手架蓝图](../engineering/SCAFFOLD_BLUEPRINT.md) 和 [阶段验收](../engineering/SCAFFOLD_ACCEPTANCE.md)。B0/B1允许的生成器评估/手写DTO过渡有明确期限，B2前必须锁定长期方案；待选库与未实现状态不等于功能已验收。

## 4. 设计假设与状态维护

所有数值初值（会话/日志队列/上传/任务限额/测试门槛）属于本项目建议，不是供应商保证或MyHome生产事实。改动时只在对应权威专题修改数值，其他文件链接，避免多份默认值互相冲突。

审查问题和修复记录放 [文档审查记录](DOCUMENT_REVIEW.md)。文档完成表示覆盖与一致性达到审查门槛；工程lint、测试、模型质量、平台发布与部署仍按 [交付验收](../engineering/DELIVERY_ACCEPTANCE.md) 提供真实证据。
