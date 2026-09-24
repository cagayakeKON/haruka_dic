# 文档导航

阶段1的 [完整B0可重复工程基础已验收](delivery/reviews/2026-09-22-b0-acceptance.md)，覆盖Flutter/Python应用壳、锁定构建与开发命令、[本地基础设施](../dev/README.md)、迁移/初始化、契约和完整B0证据矩阵。B1/B2未实现；独立 [HTML原型](../prototype/README.md) 只提供视觉和内存交互示例，不计入正式应用验收。

## 1. 按任务阅读

| 现在要做什么 | 先读 | 再按需查 |
| --- | --- | --- |
| 了解产品 | [产品总览](product/overview.md) | [待决事项](decisions/pending.md) |
| 设计视觉、组件、动效与文案 | [产品设计语言：晴空频率](product/design-language.md) | [手机/电脑独立HTML原型](../prototype/README.md)、[Flutter适配](engineering/flutter.md)、对应模块；正式Flutter视觉仍待落地 |
| 开发一个功能 | 下方对应模块 | [功能与验收追踪](delivery/coverage.md)、该模块引用的公共契约 |
| 实现OCR或拍照识词 | [统一视觉模型OCR](architecture/vision-recognition.md) | [三类材料](contracts/material-types.md)、[Agent运行层](architecture/agent-runtime.md)、对应功能模块 |
| 实现模型调用与Token统计 | [模型用量统计契约](contracts/model-usage.md) | [Agent运行层](architecture/agent-runtime.md)、[数据与任务](architecture/data-jobs.md)、[观测](operations/observability.md) |
| 实现材料上传、解析数据或版本 | [三类解析数据结构](contracts/material-structures.md) | [三类材料](contracts/material-types.md)、[数据与任务](architecture/data-jobs.md)、对应功能模块 |
| 实现教材/试卷解析、听力与展示 | [解析展示契约](contracts/learning-presentation.md) | [解析数据结构](contracts/material-structures.md)、[课本](modules/textbooks.md)、[考试](modules/exams.md)、[AI与朗读](modules/ai-speech.md)、[出处](contracts/content-locator.md) |
| 实现私有解释/TTS缓存和全局单词发音 | [学习结果缓存](architecture/learning-cache.md) | [AI与朗读](modules/ai-speech.md)、[收藏](modules/vocabulary-practice.md)、[设置](modules/settings.md)、[数据与任务](architecture/data-jobs.md) |
| 实现独立查询与卡片收藏 | [查询](modules/query.md) | [AI卡片](modules/ai-speech.md)、[API](contracts/api.md)、[单词本](modules/vocabulary-notebooks.md) |
| 实现任务实时进度 | [WebSocket进度](contracts/job-progress.md) | [任务](architecture/data-jobs.md)、[认证](architecture/authentication.md)、[材料](modules/materials-reading.md) |
| 实现多单词本与自动掌握 | [单词本](modules/vocabulary-notebooks.md) | [学习证据](architecture/vocabulary-learning.md)、[AI习题](modules/ai-exercises.md)、[CSV](contracts/vocabulary-csv.md) |
| 实现AI习题与错题库 | [AI习题与错题库](modules/ai-exercises.md) | [公共作答/评分](modules/vocabulary-practice.md)、[数据与任务](architecture/data-jobs.md)、[Agent运行层](architecture/agent-runtime.md) |
| 初始化工程 | [脚手架](engineering/scaffold.md) | [项目结构](architecture/project-structure.md)、[B0/B1/B2](delivery/milestones/scaffold.md)、[开发指南](engineering/development.md) |
| 编写代码与测试 | [代码规范](engineering/coding.md)、[Lint](engineering/lint.md) | [测试策略](engineering/testing/strategy.md)、[前端E2E](engineering/testing/frontend-e2e.md)、[测试数据](engineering/testing/data.md) |
| 开发Flutter页面或移动端适配 | [Flutter开发与适配规范](engineering/flutter.md) | [项目结构](architecture/project-structure.md)、[前端测试与适配矩阵](engineering/testing/frontend-e2e.md) |
| 开发后端模块或统一接口返回 | [后端开发手册](engineering/backend.md)、[统一返回/异常/多语言](contracts/api-responses.md) | [API总则](contracts/api.md)、[项目结构](architecture/project-structure.md)、[后端测试写法](engineering/testing/strategy.md) |
| 设计表、隔离查询或修改数据库 | [数据库规范](engineering/database.md) | [数据与任务](architecture/data-jobs.md)、[认证隔离](architecture/authentication.md)、[迁移操作](operations/deployment-recovery.md) |
| 接入或部署 | [MyHome复用](operations/myhome-integration.md)、[配置](operations/configuration.md) | [部署与恢复](operations/deployment-recovery.md)、[观测](operations/observability.md) |
| 确认做到哪、能否交付 | [路线图](delivery/roadmap.md) | [交付验收](delivery/acceptance.md)、[审查记录](delivery/reviews/reorganization.md) |

Agent先读根 [AGENTS.md](../AGENTS.md)。开始一项功能无需从头阅读所有文档，但必须读取相关的认证/授权、数据和日志约束。

## 2. 功能模块

每个模块按同一顺序组织：范围/入口/权限 → 流程/状态/异常 → 前端职责 → 后端职责 → 公共契约 → 验收 → 待决/后续。前后端使用同一份模块规格并行开发，不再维护两份功能定义。

| 模块 | 负责的用户行为 | 主要公共依赖 |
| --- | --- | --- |
| [账号](modules/accounts.md) | 注册、登录、会话恢复、改密/退出、首次资料引导 | [认证](architecture/authentication.md)、[设置](modules/settings.md)、[授权](architecture/authorization.md) |
| [材料公共能力](modules/materials-reading.md) | 导入、书库、共用出处/位置/书签操作 | [三类材料](contracts/material-types.md)、[解析数据结构](contracts/material-structures.md)、[出处协议](contracts/content-locator.md)、[数据与任务](architecture/data-jobs.md) |
| [小说](modules/novels.md) | 章节/语言预处理、连续阅读与选词 | [三类材料](contracts/material-types.md)、[出处](contracts/content-locator.md) |
| [课本](modules/textbooks.md) | 单元/内容角色、词表、课文与逐题练习 | [三类材料](contracts/material-types.md)、[公共作答](modules/vocabulary-practice.md) |
| [收藏与公共作答](modules/vocabulary-practice.md) | 词表、CSV/照片、题目作答、评分与诊断 | [CSV](contracts/vocabulary-csv.md)、[API](contracts/api.md) |
| [单词本](modules/vocabulary-notebooks.md) | 混合收藏列表/弹窗、多本组织、每日单词、AI习题选源和只读掌握 | [学习证据](architecture/vocabulary-learning.md)、[AI习题](modules/ai-exercises.md)、[CSV](contracts/vocabulary-csv.md) |
| [AI习题与错题库](modules/ai-exercises.md) | 显式选源生成、所有可靠错题留档/收藏、针对性题目 | [学习证据](architecture/vocabulary-learning.md)、[公共作答](modules/vocabulary-practice.md)、[数据与任务](architecture/data-jobs.md) |
| [考试](modules/exams.md) | 试卷/文字听力稿校对、TTS准备、整卷答题、保存/交卷、成绩与重评 | [解析数据结构](contracts/material-structures.md)、[数据与任务](architecture/data-jobs.md)、[AI与朗读](modules/ai-speech.md)、[出处](contracts/content-locator.md) |
| [查询](modules/query.md) | 无材料自由问答、聊天、完整卡片收藏与归本 | [AI卡片](modules/ai-speech.md)、[运行层](architecture/agent-runtime.md)、[单词本](modules/vocabulary-notebooks.md) |
| [AI与朗读](modules/ai-speech.md) | 解释、对话、卡片、TTS与播放 | [Agent运行层](architecture/agent-runtime.md)、[模型用量](contracts/model-usage.md)、[API事件](contracts/api.md) |
| [管理后台](modules/admin.md) | 用户、角色、菜单、策略、任务与审计 | [RBAC](architecture/authorization.md)、[权限目录](contracts/permissions.md) |
| [设置](modules/settings.md) | 个人资料/头像、语言档案、基础显示、个人Key、服务实例与缓存 | [认证隔离](architecture/authentication.md)、[配置](operations/configuration.md) |

## 3. 内容归属

| 分类 | 唯一负责的正文 | 不在这里重复维护 |
| --- | --- | --- |
| product | 产品目标、范围/优先级、成功指标、非功能目标、范围外及统一产品设计语言 | 详细操作、API字段、实施计划 |
| modules | 具体业务规则、操作/异常、前后端职责、功能验收 | 公共会话算法、权限代码定义、出处字段 |
| architecture | 系统选型与依赖、认证/授权、持久任务、Agent机制 | 逐页操作或部署步骤 |
| contracts | API/权限/CSV/出处等共同协议 | 另一套产品范围或重复生成字段事实 |
| engineering | 编码、数据库建表/隔离规则、开发、脚手架、Lint和测试方法 | 上线操作与历史通过记录 |
| operations | 配置、基础设施、采集、部署/排障/恢复步骤 | 功能交付审批和产品优先级 |
| delivery | 阶段进度、需求/验收映射、制品证据、历史review | 第二套业务契约 |
| decisions | 当前选型理由/状态及待决问题/锁定节点 | 已实现/已验证的虚假结论 |

系统全貌从 [架构总览](architecture/overview.md) 进入。代码目录由 [项目结构](architecture/project-structure.md) 定义；人工协议说明在docs/contracts，未来机器生成OpenAPI/目录在根contracts，字段来源始终单向，不互相手改同步。

## 4. 决策、进度与历史

- [当前决策](decisions/README.md)：区分用户已确认、推荐设计与待原型验证的选择。
- [待决事项](decisions/pending.md)：只在这里维护问题状态、影响及最晚锁定点，模块通过OPEN编号引用。
- [路线图](delivery/roadmap.md) 与 [脚手架里程碑](delivery/milestones/scaffold.md)：只按实际工程证据更新状态。
- [原设计审查](delivery/reviews/2026-09-22-design.md) 与 [本轮重组](delivery/reviews/reorganization.md)：历史检查和修订记录，不作为当前规则的第二正文。
- [原型审查](delivery/reviews/2026-09-22-prototype.md)：独立原型工作记录，不代表本轮重组执行过原型测试。
- [「晴空频率」双端原型审查](delivery/reviews/2026-09-24-clear-signal-prototype.md)：新原型的页面覆盖、独立审查、实际浏览器验证和边界。
- [手机移动优先修订审查](delivery/reviews/2026-09-24-mobile-first-prototype.md)：手机端 DESIGN3 的任务流修订、独立审查与定点浏览器验证。
- [手机排版与文案重构](delivery/reviews/2026-09-24-mobile-refinement.md)：手机端 DESIGN4 的内容层级、触控操作、产品文案清理及局部验证。
- [电脑端排版与交互重构](delivery/reviews/2026-09-24-desktop-refinement.md)：电脑端 DESIGN5 的移动优先布局、手机视觉对齐、键盘与历史导航、文案清理及局部验证。
- [手机登录、注册与找回优化](delivery/reviews/2026-09-24-mobile-auth.md)：DESIGN7 紧凑表单、密码显隐、字段错误和受理页的局部验证。
- [材料库操作层级修订](delivery/reviews/2026-09-24-library-hierarchy.md)：DESIGN8 手机header搜索、右下角导入、两端小型详情入口与局部验证。
- [首个脚手架切片](delivery/reviews/2026-09-22-scaffold-foundation.md)：B0-foundation的实现、局部验证、review与未完成门禁。
- [基础设施切片](delivery/reviews/2026-09-22-scaffold-infrastructure.md)：真实客户端生命周期、隔离Compose、正常日志采集、运行与维护账号边界。

- [数据库与受控初始化](delivery/reviews/2026-09-22-b0-identity.md)：基础表/字典、迁移锁、幂等种子、首管理员与动态readiness。
- [前端契约与控件](delivery/reviews/2026-09-22-b0-frontend.md)：Dio/DTO、Python到Dart兼容样本、三端控件原型、真实健康页及正式管理路由联调。
- [质量门禁](delivery/reviews/2026-09-22-b0-quality.md)：真实测试结果收集、缺项/坏样本阻断、源码覆盖清单及CI参考入口；远端CI尚未执行。
- [开发编排](delivery/reviews/2026-09-22-b0-development.md)：core/jobs资源profile、真实启停、进程所有权及局部跨系统回归的实现记录。
- [Windows安装身份原型](delivery/reviews/2026-09-22-b0-windows-installer.md)：独立安装/凭据service、共存/升级/卸载的真实验证；载荷为无网络探针，不代表正式应用分发。
- [Windows干净检出](delivery/reviews/2026-09-22-b0-windows-clean.md) 与 [Linux干净检出](delivery/reviews/2026-09-22-b0-linux.md)：同候选的锁定构建、负例诊断、重复初始化和完整应用生命周期。
- [B0最终验收](delivery/reviews/2026-09-22-b0-acceptance.md) 与 [独立证据核查](delivery/reviews/2026-09-22-b0-evidence.md)：44个必需节点、11份逐断言签收及统一入口88项检查通过；后续能力仍按所属阶段交付。

## 5. 维护规则

1. 先判断内容归属，再修改唯一正文和必要引用；摘要可以重复解释意图，字段、状态机、默认值和操作规则不复制维护。
2. 改功能同时更新所属模块、受影响契约和覆盖索引；改产品范围同步总览、决策与路线图。
3. 已确认、推荐、待决、未实现、已验证分别表达。所有示例路径和未来命令都有实施前提，不把文档完整等同于工程完成。
4. 统一中文正文与清楚的业务术语；文件名用小写连字符，README.md与根AGENTS.md保留标准名称。
5. 本地链接用相对路径，移动后检查目标与大小写；旧路径和旧章节号只保留在历史迁移映射，不能继续作为开发入口。
6. 变更范围、并行分工、commit、测试选择和review频率只由AGENTS.md规定；本文不另设门禁。
7. 不为凑目录创建空文档。已有内容超出职责时先提取成单一专题，再修复所有消费者引用。

- [收藏、查询与实时进度](delivery/reviews/2026-09-24-collections-query-prototype.md)：DESIGN6 双端条目列表/弹窗、每日单词、聊天卡片、材料直达与本地 WebSocket 验证。
