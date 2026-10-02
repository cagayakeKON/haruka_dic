# 功能与验收追踪

状态：PLAN2实施映射；B1账号与最小收藏已按[用户最终决定](reviews/2026-09-26-b1-implementation.md)验收通过，[B2a本人资料与设置](reviews/2026-09-28-profile-settings-acceptance.md)在旧错误视觉结论撤回、同一Flutter mock主界面完成接线与双端复核后按当期范围重新验收通过；[B2b身份治理](reviews/2026-09-29-identity-governance-implementation.md)已有代码和切片复核，2026-09-30 正式 Web/Android 实操、集中修复与独立定点复核已完成，B2b当期范围验收通过；[B2c凭据与模型任务](reviews/2026-09-30-model-credentials-tasks.md)当期工程实现、联调与独立review完成；真实测试均KEY_REJECTED，2026-10-01用户确认该结果并要求不再验证模型，B2c按此范围验收通过，模型可用性未验证。阶段1已完成；M1按[实现方案](material-import-implementation.md)完成真实源导入、材料库与持久本人通知，必要局部验证、正式Web/Android实操及独立复核通过；其他业务按后续切片实现。产品范围由[产品总览](../product/overview.md)维护，阶段/状态见[路线图](roadmap.md)，当前手机/电脑所有操作见[UI-01～35清单](prototype-scope.md)。两份覆盖取并集；原型未画出的既有P0也必须实现。

## 1. 功能与阶段

| 功能入口 | 权威正文/契约 | 验收族 | 实施节点与完整收口 |
| --- | --- | --- | --- |
| 注册/激活/登录/恢复/本人安全 | [账号](../modules/accounts.md)、[认证](../architecture/authentication.md) | SCF-B1/ACC | B1保持原范围与SCF-B1-01～08；完整引导/资料ACC-11/12的B2a当期分支已重新验收通过；B2b审批/人工恢复已有实现和切片复核，2026-09-30 正式 Web/Android 实操、集中修复与独立定点复核已完成，B2b当期范围验收通过，见[实现记录](reviews/2026-09-29-identity-governance-implementation.md)；B1已选路径保持 |
| 个人资料/头像/语言/实例/显示 | [设置](../modules/settings.md)、[API](../contracts/api.md) | PROFILE/SET/CACHE | B2a当期资料/设置/头像/语言/实例与对应缓存分支已重新验收通过；阅读/查询偏好先保存，M2/L2接消费；声音/两类缓存L4，CSV入口L3 |
| 完整后台与RBAC | [后台](../modules/admin.md)、[授权](../architecture/authorization.md)、[权限](../contracts/permissions.md) | ADM/PERM | B2b身份治理已有实现和切片复核，2026-09-30 正式 Web/Android 实操、集中修复与独立定点复核已完成，B2b当期范围验收通过，见[实现记录](reviews/2026-09-29-identity-governance-implementation.md)；B2c当期任务/用量/能力已按2026-10-01用户决定验收通过；随M/L/P/E增加运维资源，R2完整候选联验 |
| 本人Key、能力测试与模型用量 | [设置](../modules/settings.md)、[用量](../contracts/model-usage.md)、[任务](../architecture/data-jobs.md) | SCF-B2/SET/USAGE-01～09 | B2c正式单能力测试与attempt已实现、独立review完成；真实3次均KEY_REJECTED，已按2026-10-01用户决定验收通过、停止真实模型验证；各调用入口增量验证真实协议/unknown/null/缓存/聚合，R2汇总 |
| 材料公共能力 | [材料](../modules/materials-reading.md)、[三类](../contracts/material-types.md)、[结构](../contracts/material-structures.md)、[出处](../contracts/content-locator.md) | MAT/READ/TYPE/MSTR | M1三类MD/EPUB/PDF、试卷图片的导入/书库/不可变源/删除；M2～M4专用流程及MAT-P1-01已升级P0的PDF分支，E2补冻结考试引用/GC |
| 小说 | [小说](../modules/novels.md)、[章节准备](../contracts/novel-preparation.md) | NOV/NPREP-01～06 | M2结构/正文/NLP/ruby/位置/布局；L2点句与范围查询，L4音频，L5准备/连续朗读 |
| 课本 | [课本](../modules/textbooks.md)、[展示](../contracts/learning-presentation.md) | TBK/PRES | M3八类内容/顺序/关系/原文对照；L2/L4解释朗读；P1逐题作答反馈/重做/收藏 |
| 视觉OCR与单图识词 | [视觉识别](../architecture/vision-recognition.md)、[收藏学习](../modules/vocabulary-practice.md) | OCR-01～05/PHOTO | M1三类PDF源层，M2～M4各自扫描PDF处理、M4另含试卷图片；L2图文查询，L3独立单图识词预览确认；分别取得模型/权限/平台证据 |
| 收藏/词本/每日单词 | [收藏](../modules/vocabulary-practice.md)、[单词本](../modules/vocabulary-notebooks.md) | COL/VNB-01～12 | B1最小收藏不变；L1完整六类/手动/组织/日期历史；L2四卡片，L4词音；P3掌握，E2考试来源 |
| 单词CSV | [CSV唯一协议](../contracts/vocabulary-csv.md) | CSV清单/VNB-09/VL交叉边界 | L3完整导入导出/三端文件；P3补真实学习证据并存回归，R1正式制品文件路径复验 |
| 独立与上下文查询/卡片 | [查询](../modules/query.md)、[AI朗读](../modules/ai-speech.md)、[运行层](../architecture/agent-runtime.md) | QRY-01～10/AI/SEL/COL | L2文字/纯图/混合/四卡片含ExerciseCard、附件/拍照/粘贴、持久结果/SSE；P1/P4/E2补题目/诊断/复盘来源，不延迟独立查询 |
| TTS与学习结果缓存 | [AI朗读](../modules/ai-speech.md)、[缓存](../architecture/learning-cache.md)、[适配](../architecture/tts-adapters.md) | TTS/LC-01～13/TTSA-01～05 | L2文本持久复用；L4私有/共享词音/逐模型/本机格式风格容量；L5章节与试卷准备；P/E新增来源边界 |
| 公共作答与评分 | [收藏学习](../modules/vocabulary-practice.md)、[展示](../contracts/learning-presentation.md) | PRA/TBK/PRES/COL-005/006 | P1教材/普通题五类输入与评分反馈；P2生成题复用；E1/E2考试分支，规则/模型不混口径 |
| AI习题与删题 | [AI习题](../modules/ai-exercises.md)、[API](../contracts/api.md)、[待决](../decisions/pending.md) | AIX-01～10/PRA | P2词本/收藏/教材来源、预览/冻结/明确生成及删错误题；P3/P4补错题/诊断来源；OPEN-10在首次公共题版本兼容冻结前锁定 |
| 错题与自动掌握 | [学习证据](../architecture/vocabulary-learning.md)、[AI习题](../modules/ai-exercises.md) | AIX/VL-01～10/VNB-06～08/10 | P3可靠错误/部分正确历史、独立收藏、当前投影/辅助/重评/只读掌握；E2接考试事实，CSV不恢复证据 |
| 学习诊断 | [收藏学习](../modules/vocabulary-practice.md)、[运行层](../architecture/agent-runtime.md) | DIAG/AI | P4真实事实/薄弱亮点/依据/回原文/出题，补齐查询朗读和NLP；E2补考试事实 |
| 试卷 | [考试](../modules/exams.md)、[结构](../contracts/material-structures.md)、[展示](../contracts/learning-presentation.md) | 考试清单/MSTR/PRES/DAT | M4格式/校对/文字稿候选；L5私有音频/ready；E1场次/次数/锁卷，E2评分/重评/复盘/交卷门槛 |
| 站内消息与任务进度 | [消息](../contracts/notifications.md)、[进度](../contracts/job-progress.md) | NTF-01～05/WSP-01～05 | B2c任务基础；M1持久消息/未读/已读/跳转及材料进度，后续任务类型随功能接入 |
| 日志与业务埋点 | [观测](../operations/observability.md)、[MyHome](../operations/myhome-integration.md) | LOG及原观测清单 | B1/B2基础；各阶段覆盖正常/失败、脱敏/关联/补传/隔离，R2全部来源、正式制品与采集故障 |
| 前端统一缓存与更新 | [机制](../architecture/frontend-cache.md)、[校验协议](../contracts/client-cache.md) | FCACHE-01～14，关联CACHE/LC/SET/FLT | B2a本人资料/设置作用域、写后更新、本机清理与空校验注册框架的当期分支已重新验收通过；B2b/c授权/任务，M材料/消息，L收藏/解释/音频，P/E证据与可见性仍未交付；R1/R2汇总全部分支，不先关闭FCACHE全族 |

### 跨入口验收

| 能力 | 权威正文与验收 | 分支归属 |
| --- | --- | --- |
| 源提取/ruby | [提取](../contracts/source-extraction.md)，SRC-01～04/TYPE-06 | M1～M4按获准格式与日英材料；原书ruby不混canonical_text、不猜造读法 |
| 全应用基础NLP | [文本分析](../architecture/text-analysis.md)，NLP-01～08/LC-13 | M材料/全书；L2全部查询卡片/解释、L1手动收藏注册来源；P题目/反馈/诊断；E题面/评分/复盘，逐字段签收 |
| 手动上下文 | [上下文](../contracts/query-context.md)，QCTX-01～05 | B2a预算设置；M2有权源计划；L2材料/独立图文/已发布解释全部；P/E新增来源/交卷限制 |
| 统一学习文字动作 | [AI朗读](../modules/ai-speech.md)，SEL/QRY-10/COL-005～006 | M2定位/手动扩选；L2查询收藏/L4朗读；P题面/反馈/诊断；E2交卷有权文字，不开放隐藏内容 |
| 逐模型TTS | [适配](../architecture/tts-adapters.md)，TTSA-01～05 | L4每个注册模型的协议、真实音频/三端兼容，L5/P/E新增来源；不能以单模型夹具覆盖全部 |
| 持久结果与缓存 | [缓存](../architecture/learning-cache.md)，LC-01～13 | L2文本，L4私有/公共音频，L5章节/听力准备，P/E所有新成品；Fake计数证明复用，实际音频兼容另验 |

每个跨阶段验收族须记录已关闭的来源/字段/模型/平台及剩余分支。模块条目是行为要求，实施时展开为真实case/runner/参数和必需矩阵；不因参考链路、HTML或文档通过而关闭整族。原来无编号的CSV/考试/观测清单继续保留，不虚构已存在测试。

## 2. 公共工程与运行验收

| 范围 | 唯一方法/规则 | 实施验收 |
| --- | --- | --- |
| 产品视觉、组件、动效与文案 | [产品设计语言：晴空频率](../product/design-language.md)、[已确认Flutter主界面](reviews/2026-09-27-frontend-visual-refinement.md#1-用户确认与分工)、[Flutter适配](../engineering/flutter.md) | DESIGN-01～DESIGN-06为正式页面检查项，随各页面切片验证；[HTML原型](../../prototype/README.md)保留早期流程参考，DESIGN11/12的历史局部证据见[体验优化](reviews/2026-09-25-prototype-experience.md)与[任务流优化](reviews/2026-09-25-task-flow-refinement.md)，不能反向覆盖已确认Flutter界面。B2a旧平行正式页面的视觉通过结论已撤回；以同一Flutter mock为唯一主界面完成迁移、正式Web/Android复测后，当期适用视觉与交互重新验收通过，历史与修订见[验收记录](reviews/2026-09-28-profile-settings-acceptance.md)；其他业务页面仍按所属切片交付，不替代FLT/UIE或业务验收 |
| 目录、依赖与公共服务 | [项目结构](../architecture/project-structure.md)、[架构](../architecture/overview.md) | STR/API/DAT，依赖方向与真实事务/隔离 |
| 后端模块、统一返回/异常和多语言边界 | [后端手册](../engineering/backend.md)、[返回契约](../contracts/api-responses.md) | STR/SCF与API-07～API-10；真实路由/生成模型一致、框架异常/流式例外、语言和安全参数 |
| 建表、时间字段与无外键隔离 | [数据库规范](../engineering/database.md)、[数据库设计书](../architecture/database-design.md)、[Redis字段](../architecture/redis-design.md) | DB-01～DB-12；结构/字典、时间写入、双账号与逻辑关联竞争、迁移证据，按已交付范围执行；DBDESIGN1/2/3及[DBDESIGN4修订](reviews/2026-09-26-database-audit-fixes.md)仅交付设计、[158→142全表收敛](../architecture/database-convergence.md)、[142表命名与关系](../architecture/database-relations.md)及文档审查，不计业务实现；本轮对应根级Lesson/听力kind、COL-005/006及LC-10的待实施验收 |
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
