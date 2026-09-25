# 功能与验收追踪

状态：2026-09-23，设计覆盖索引。这里只维护功能→权威正文→验收族的映射，不复制产品优先级或协议字段；B0工程基础已验收，以下业务功能仍按所属阶段交付。产品范围见 [产品总览](../product/overview.md)，实施状态见 [路线图](roadmap.md)。

DESIGN17[题目直接收藏与交卷后学习](reviews/2026-09-25-question-collection.md)覆盖COL-005/006；DESIGN16原型局部证据见[统一选区交互](reviews/2026-09-25-unified-text-selection.md)；SEL-001～003及QRY-10的正式三端/服务端验收仍待实现，不以HTML演示勾选。

DESIGN18补充单词喇叭、句子分词气泡与小说连续朗读；新增SEL-004、TTS-008、NOV-005、LC-11，HTML局部证据见[原型记录](reviews/2026-09-25-sentence-speech.md)，正式服务端/音频/三端验收仍未执行。

DESIGN19原型修订普通划选不自动弹层及句子/dialog动效，沿用SEL-001/003与DESIGN-04/05；[局部记录](reviews/2026-09-25-long-press-motion.md)不代表正式三端验收。

DESIGN20新增[章节准备契约](../contracts/novel-preparation.md)及NPREP-01～06，小说全书基础NLP、ruby解析模式、点句详解和按章多选解析/朗读。HTML局部证据见[章节准备记录](reviews/2026-09-25-novel-preparation.md)，正式阶段2/3验收仍未执行。

DESIGN21修订电脑4K阅读布局与非模态解析panel，沿用NOV-003、SEL-003、TTS-008及NPREP对应交互；[局部记录](reviews/2026-09-25-desktop-reader-panel.md)只证明HTML布局、查询/收藏/播放和返回行为，不勾选正式三端、服务端或NPREP验收。

## 1. 按功能开始开发

| 功能入口 | 公共契约与设计 | 沿用的验收族/证据 |
| --- | --- | --- |
| [账号：注册、登录、恢复与会话](../modules/accounts.md) | [认证](../architecture/authentication.md)、[API](../contracts/api.md)、[授权](../architecture/authorization.md) | ACC；最小注册、三端与管理Web、改密/恢复、会话撤销、首次引导与账号切换 |
| [材料公共能力：上传、书库与出处操作](../modules/materials-reading.md) | [三类材料](../contracts/material-types.md)、[解析数据结构](../contracts/material-structures.md)、[出处](../contracts/content-locator.md)、[数据与任务](../architecture/data-jobs.md) | MAT/READ/TYPE/MSTR；不可变上传、公共来源层与专用领域结构、类型/格式独立、版本/位置/书签 |
| [统一视觉模型OCR](../architecture/vision-recognition.md) | [运行层](../architecture/agent-runtime.md)、[来源定位](../contracts/content-locator.md)、对应材料/照片模块 | OCR-01～OCR-05，按获准格式/消费功能执行；本人Key/上限、页覆盖、识别稿/版本、失败恢复、定位粒度与日志 |
| [小说：预处理与连续阅读](../modules/novels.md) | [材料类型](../contracts/material-types.md)、[出处](../contracts/content-locator.md) | NOV；章序/段落/对话、分句分词、专用阅读和标注降级 |
| [课本：单元结构与学习](../modules/textbooks.md) | [材料类型](../contracts/material-types.md)、[公共作答](../modules/vocabulary-practice.md) | TBK；内容角色/词表/题目关联、单元位置、逐题反馈与独立状态 |
| [教材/试卷解析、听力与展示](../contracts/learning-presentation.md) | [解析数据结构](../contracts/material-structures.md)、[课本](../modules/textbooks.md)、[考试](../modules/exams.md)、[出处](../contracts/content-locator.md)、[Flutter](../engineering/flutter.md) | PRES-01～PRES-10、MSTR；八类内容/五类输入/题组、听力标记/脚本题目匹配/TTS绑定、原文投影、未知结构和媒体故障、三端状态；阶段2解析校对、3音频生成、4作答复盘分别验收 |
| [学习：收藏、照片、公共作答/评分和诊断](../modules/vocabulary-practice.md) | [权限](../contracts/permissions.md)、[数据与任务](../architecture/data-jobs.md) | COL/PHOTO/PRA/DIAG；重复与来源、规则/AI评分、有效贡献 |
| [AI习题与错题库](../modules/ai-exercises.md) | [学习证据](../architecture/vocabulary-learning.md)、[API](../contracts/api.md)、[权限](../contracts/permissions.md) | AIX-01～AIX-10；全部可靠错题留档/收藏/重评状态、单词本/教材/错题/诊断选源、稳定预览与显式生成、针对性原题/变式、无复习调度；阶段4验收 |
| [多单词本与自动掌握](../modules/vocabulary-notebooks.md) | [学习证据/掌握](../architecture/vocabulary-learning.md)、[AI习题](../modules/ai-exercises.md)、[权限](../contracts/permissions.md)、[CSV](../contracts/vocabulary-csv.md) | VNB-01～VNB-12、VL-01～VL-10；混合类型列表/详情与词本弹窗、每日单词、多对多归属、删本/删词、AI习题选源、自动掌握、辅助/多设备、重评重放；阶段3组织、4学习、5CSV分别验收 |
| [单词CSV入口](../modules/vocabulary-practice.md) | [CSV唯一协议](../contracts/vocabulary-csv.md) | 原CSV清单；全部逻辑记录导出、v2词本归属与v1兼容、快照不恢复学习证据、预览/分批/重复策略、公式转义、跨账号往返 |
| [考试：导入、文字听力、校对、答题、交卷与成绩](../modules/exams.md) | [解析数据结构](../contracts/material-structures.md)、[API](../contracts/api.md)、[数据与任务](../architecture/data-jobs.md)、[出处](../contracts/content-locator.md) | 原考试清单、MSTR/PRES及DAT；AI听力标记/匹配、人工确认、TTS冻结、草稿/截止/锁卷、媒体故障、评分恢复与重评 |
| [AI与朗读：解释、卡片、共享运行和TTS](../modules/ai-speech.md) | [Agent运行层](../architecture/agent-runtime.md)、[API事件](../contracts/api.md) | AI/TTS/SEL；普通学习及交卷后复盘文字共用选区朗读/查询、结果收藏，类型校验、权限/上限、流恢复、音频缓存与播放 |
| [模型用量统计](../contracts/model-usage.md) | [数据与任务](../architecture/data-jobs.md)、[设置](../modules/settings.md)、[管理后台](../modules/admin.md)、[观测](../operations/observability.md) | USAGE-01～USAGE-09；attempt幂等、input/output/cache分项、unknown/null与混合组完整性、应用缓存区分、本人/管理聚合和日志边界 |
| [词句解析与TTS的持久保存/缓存](../architecture/learning-cache.md) | [AI/朗读](../modules/ai-speech.md)、[收藏](../modules/vocabulary-practice.md)、[设置](../modules/settings.md)、[数据与任务](../architecture/data-jobs.md) | LC-01～LC-11；未收藏也保存、书内语境索引、跨端复用、全局标准词音与私人关联/用量、生成合并/版本、容量与GC、权限/离线 |
| [后台：用户、角色、菜单、策略和运维](../modules/admin.md) | [RBAC](../architecture/authorization.md)、[权限目录](../contracts/permissions.md) | ADM/PERM；两端显示/接口一致、deny/继承/撤权、防提权与首末管理员 |
| [设置：资料、头像、语言、Key、服务实例与缓存](../modules/settings.md) | [认证与隔离](../architecture/authentication.md)、[API/头像传输](../contracts/api.md)、[运行配置](../operations/configuration.md) | PROFILE/SET/CACHE；资料隐私/并发、头像安全发布、语言组合/历史、显示无障碍、凭据轮换、账号代次、离线租期与迟到响应 |
| [统一日志与业务埋点](../operations/observability.md) | 各模块的事件映射、[MyHome接入](../operations/myhome-integration.md) | 原观测清单；全部来源/info事件、关联、脱敏、补传与采集缺口 |

模块中的验收项是行为要求，测试运行器和required_cases负责将其展开为真实case/平台/runner/参数；本文不能替代运行报告。原来只有检查清单的CSV、考试和观测验收保留原意，不虚构已经存在的编号化测试。

## 2. 公共工程与运行验收

| 范围 | 唯一方法/规则 | 实施验收 |
| --- | --- | --- |
| 产品视觉、组件、动效与文案 | [产品设计语言：晴空频率](../product/design-language.md)、[手机/电脑HTML原型](../../prototype/README.md)、[Flutter适配](../engineering/flutter.md) | DESIGN-01～DESIGN-06为正式页面检查项，随各页面切片验证；HTML原型已按新视觉重建，DESIGN11的导航/收藏/空态局部证据见[体验优化](reviews/2026-09-25-prototype-experience.md)；DESIGN12的查询/习题流程局部证据见[任务流优化](reviews/2026-09-25-task-flow-refinement.md)，Flutter尚未实现，不替代FLT/UIE或业务验收 |
| 目录、依赖与公共服务 | [项目结构](../architecture/project-structure.md)、[架构](../architecture/overview.md) | STR/API/DAT，依赖方向与真实事务/隔离 |
| 后端模块、统一返回/异常和多语言边界 | [后端手册](../engineering/backend.md)、[返回契约](../contracts/api-responses.md) | STR/SCF与API-07～API-10；真实路由/生成模型一致、框架异常/流式例外、语言和安全参数 |
| 建表、时间字段与无外键隔离 | [数据库规范](../engineering/database.md)、[数据库设计书](../architecture/database-design.md)、[Redis字段](../architecture/redis-design.md) | DB-01～DB-12；结构/字典、时间写入、双账号与逻辑关联竞争、迁移证据，按已交付范围执行；DBDESIGN1/2/3仅交付设计、[158→142全表收敛](../architecture/database-convergence.md)、[142表命名与关系](../architecture/database-relations.md)及文档审查，不计业务实现 |
| 包、CLI、构建身份与生成 | [脚手架](../engineering/scaffold.md) | [B0/B1/B2里程碑](milestones/scaffold.md)的SCF |
| 前端定位与端到端测试 | [前端测试](../engineering/testing/frontend-e2e.md) | UIE，不用一种runner证据代替另一种 |
| Flutter独立布局、状态保留与平台优化 | [Flutter开发与适配规范](../engineering/flutter.md) | FLT-01～FLT-08，按阶段证明空间/输入/能力、重排无重复副作用、原生交互与实际性能 |
| 素材、场景、工厂与清理 | [测试数据](../engineering/testing/data.md) | TDS，先合法前置/实际目标动作，再停止写入并清理 |
| 检查与结果判定 | [Lint](../engineering/lint.md)、[测试策略](../engineering/testing/strategy.md) | 必需用例结果；大节点完整覆盖分母/阈值 |
| 配置、部署与恢复 | [配置](../operations/configuration.md)、[操作手册](../operations/deployment-recovery.md) | OPS与[交付验收](acceptance.md)要求的制品/恢复证据 |

开发和review节奏只由根 [AGENTS.md](../../AGENTS.md) 维护；这个索引不新增测试门槛、角色权限或交付承诺。

## 3. 范围变更

功能优先级只在产品总览维护，待决项只在 [决策待办](../decisions/pending.md) 维护。范围确认后，更新对应模块、受影响的公共契约、此映射和路线图；不得仅因为有测试素材或接口草案就扩大P0。

旧PRD章节与新归属的保全映射见 [重组记录](reviews/reorganization.md)。历史章节号只用于追溯，开发应使用上面的有效入口。

## DESIGN6新增正式验收追踪

| 已确认范围 | 唯一正文 / 契约 | 正式交付阶段与状态 |
| --- | --- | --- |
| 材料直接阅读、列表详情及解析WebSocket | [材料](../modules/materials-reading.md)、[WSP-01～WSP-05](../contracts/job-progress.md) | 阶段2，待实现；电脑消息/任务入口分别唯一 |
| 混合收藏、列表/弹窗、每日单词 | [VNB-10～VNB-12](../modules/vocabulary-notebooks.md) | 阶段3，待实现；CSV依旧阶段5且只含单词 |
| AI自动判断的语言图文查询、图片翻译/语法/习题批改与分类型卡片收藏 | [QRY-01～QRY-09](../modules/query.md)、[四种P0卡片](../modules/ai-speech.md) | 阶段4，待实现；不支持自由问答/通用回答类型，不扩展任意外部工具权限 |

DESIGN6仅取得文档与HTML交互证据，不勾选上述正式权限、模型、数据库和跨端验收。
