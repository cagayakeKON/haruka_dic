# 决策与推荐基线

PLAN2补充分期：下文B1账号决定保持。原型全部功能当前交付的新增要求，将审批注册与人工恢复的可配置完整流程安排在B2b；不倒灌B1或自动改变部署策略，邀请仍除外。细节见[账号](../modules/accounts.md)及[OPEN-02分期说明](pending.md)。

状态：2026-09-23 设计记录，未代表工程验证。本页保存已确认边界、DEC 选择/理由与导航；OPEN 项及尚未满足的就绪门禁统一在 [待决清单](pending.md)。需求冲突时用户最新明确要求优先；[产品总览](../product/overview.md) 定义范围，各专题维护详细契约。

DESIGN23（2026-09-26）确认[文件提取与原书ruby](../contracts/source-extraction.md)及[全应用NLP存储/缓存](../architecture/text-analysis.md)：扫描/图片由视觉模型OCR，EPUB文本直接解析；所有已提交学习文字预处理，AI结果内文本同样标注，三张NLP设计表收敛为分析版本/单元/句子。格式开放范围、真实模型/词典与质量仍按各门禁验证。

DESIGN24（2026-09-26）用户确认材料上传暂限日语/英语；日语NLP使用SudachiPy且固定SplitMode.B中粒度，英语使用spaCy。具体准入规则见[材料语言](../contracts/material-types.md#11-首版材料语言)，适配与版本/缓存见[文本分析](../architecture/text-analysis.md#11-已确认的日英nlp适配)；依赖版本、字典及英语模型包仍待工程验证。

## 1. 已确认

2026-09-26用户明确全平台均不做无障碍功能与专项验收。设置不再提供高对比专项，试卷不增加无障碍字幕/朗读策略；普通触控、键鼠、可见错误反馈及现有减少动态显示偏好仍按业务和动效要求实现。自动化所需技术Test ID只承担功能定位。早期审查记录中的无障碍待办是当时范围，不构成当前交付门槛，变更见[平台交互范围记录](../delivery/reviews/2026-09-26-platform-interaction-scope.md)。

Flutter用户端Windows/Web/Android；Python前后端分离；复用MyHome基础设施；多用户注册登录；管理后台与完整RBAC；学习Agent采用Pydantic AI；Gemini/OpenRouter TTS；试卷模式/整卷考试/AI批改；全量来源日志与前端埋点汇入MyHome Alloy/Loki/Grafana；用户侧导出恢复仅单词CSV。本阶段只文档化，并要求子Agent独立审查。

2026-09-22补充确认：数据库不使用物理外键；业务表统一created_at/updated_at，参考MyHome公共Mixin。字段/隔离/关联/迁移实施基线见 [数据库规范](../engineering/database.md)，替代旧方案中以数据库外键保证跨表归属的做法。

同日进一步确认：导入材料只适配小说、课本、试卷，各自独立处理及使用体验。文件格式仍单独按原优先级和OPEN-01管理；类型拆分不等于确认所有PDF/TXT/OCR进入P0。

OCR统一使用视觉模型已由用户确认，拍照识词共用视觉调用基础；PDF文本提取/渲染可本地完成，不引入传统OCR或静默回退。具体模型仍待OPEN-04验证，格式范围仍按OPEN-01及产品优先级。

用户进一步要求查过的单词、AI解析、句子和TTS都缓存。设计采用服务端持久结果与书内来源索引、可淘汰的Redis/本机副本，未收藏也保存；同词不同语境分开，配置更新不自动丢旧结果或重新调用供应商。

用户补充确认收藏库单词发音全局缓存。标准词形/语种/读音/声音profile一致时在同实例跨用户共享成品；个人解释、出处、收藏/使用记录、Job、Key与模型用量保持隔离。

用户确认可创建多个单词本，已掌握/未掌握由习题结果决定。设计采用同一条目多对多归本、共用学习证据；删除本不删词。2026-09-23进一步确认不支持词汇复习，改为独立AI习题功能；因此每日/到期队列、SRS/FSRS、复习计划和新词额度不进入产品。

同日确认所有可靠错题由服务端留档，用户可以收藏任一历史错题，并用于生成针对性AI习题。自动错题事实、当前错误状态和用户收藏关系分开；答对/重评不删除历史，失效答案不继续作为生成真值。

用户进一步要求补全登录注册、改密、头像、年龄、性别、母语/学习语言等基础设置。当前设计保持注册为最小身份流程；显示名/头像、出生年份/性别和学习档案登录后可选填写，资料默认仅本人可见且人口字段默认不进入AI。年龄不存会过期的整数值，P0以可选出生年份派生粗粒度年龄段。

同日确认三类材料采用公共不可变来源层和分别独立的小说、课本、试卷领域结构。试卷首版接收文字版听力稿或从试卷正文/已发布视觉转写提取脚本候选；AI必须标记疑似听力题并提出脚本—题组/小题候选匹配，用户确认后才用本人TTS生成冻结音频。用户上传原始音频、转写/切段及自动绑定列为P1待办，P0不接受该上传用途。

2026-09-23确认当前不做应用内商业化。Haruka不维护套餐、应用余额、购买、金额或结算；用户继续使用本人供应商Key。系统保留运行保护上限，并按供应商/模型/attempt持久记录input、output、cache read、cache write及供应商可得的其他用量指标。

2026-09-24用户认可「晴空频率」整体风格并要求先写入文档：灵动青春、科技感，以晴空蓝、少量芽黄绿、短声线和统一排版/反馈贯穿各场景。唯一正文见[产品设计语言](../product/design-language.md)；概念稿不改正式导航和业务范围，HTML原型随后重建，Flutter B0基础壳已对齐，正式业务页面仍待交付。

## 2. 当前实现建议

| ID | 选择与理由 | 验证/变更条件 |
| --- | --- | --- |
| DEC-01 | 单仓库Flutter应用+模块化FastAPI，API/Worker共用包不同进程 | 先满足三端和独立管理布局，出现明确规模需求再拆包/服务 |
| DEC-02 | 管理端先Flutter Web，PyCasbin封装于AuthorizationService | 阶段1验证策略投影、继承/deny/授予边界与两端快照，用户尚未单独确认库 |
| DEC-03 | PG保存AuthSession撤销/epoch，Redis保存会话材料 | 消除管理审计与异步删缓存之间的失效窗口 |
| DEC-04 | Web稳定opaque HttpOnly会话Cookie，原生短JWT+轮换refresh | Web普通续期不Set-Cookie，消除刷新迟到回退；身份变更和原生代次仍须竞态验证 |
| DEC-05 | Job/Outbox/Kafka+数据库阶段恢复，无新持久执行服务 | 供应商unknown结果不承诺恰好只执行一次，显式受控重试 |
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
| DEC-16 | 用户确认OCR统一视觉模型；Pydantic AI固定类型化调用，原件/页图准备与三类专用结果校验分开 | [视觉OCR](../architecture/vision-recognition.md) OCR-01～OCR-05按功能/获准格式验收；个人Key/上限、转写版本、定位粒度与失败恢复须验证，不走传统OCR后备 |
| DEC-17 | 查词/句子/AI解析/TTS成功结果必须缓存；设计以PG/MinIO持久保存为基础，书内语境索引、查阅/生成键分离，Redis/Flutter只作副本 | [学习结果缓存](../architecture/learning-cache.md) LC验收；TTL/本机清理不丢已保存的模型结果，并发/改配置/权限/GC须验证；缓存业务未实现 |
| DEC-18 | 收藏标准单词独立发音采用global_word实例级目录，跨用户复用同词/读音/profile音频 | [全局词音](../architecture/learning-cache.md#51-收藏库标准单词发音的全局缓存)及LC-09/10；不共享私人输入/Job/Key，词表与声音范围待阶段3实测锁定，未实现 |
| DEC-19 | 已被DEC-20取代：原方案为多单词本+effective掌握+py-fsrs间隔 | 仅供历史追踪；未实现，不得恢复其复习/SRS部分 |
| DEC-20 | 多单词本只负责组织和选源；effective习题结果驱动只读掌握，不做时间调度。独立AI习题经预览确认后使用本人Key生成；所有可靠错题自动留档，收藏与当前错误状态独立 | [AI习题](../modules/ai-exercises.md)AIX、[单词本](../modules/vocabulary-notebooks.md)VNB及[学习证据](../architecture/vocabulary-learning.md)VL验收；OPEN-11只锁定结果阈值，阶段3组织/CSV、阶段4练习闭环、阶段5考试贡献，均未实现 |
| DEC-21 | 账号身份保留users；资料/单例学习偏好/通用设置合入user_extensions，UserProfile/StudyProfile/Settings保持API投影及字段组版本，语言/模型/Key/会话与容量独立：最小注册，可跳过引导；可选birth_year代替整数年龄，人口字段默认不进AI；头像专用安全发布，语言档案与UI语言/权限分离 | [账号](../modules/accounts.md)ACC-11/12与[设置](../modules/settings.md)PROFILE验收；阶段1实现，精确生日/未成年人、公开资料、邮箱变更/销号另立范围，均未实现 |
| DEC-22 | 材料解析采用公共SourceUnit/ContentBlock来源层+NovelManifest/TextbookManifest/ExamPaperVersion三套领域结构；P0考试听力只处理文字稿/正文候选，经AI标记匹配和人工确认后生成私有TTS | [解析数据结构](../contracts/material-structures.md)MSTR、[考试](../modules/exams.md)与PRES验收；原始音频上传/自动绑定按OPEN-12进入P1前置设计，全部未实现 |
| DEC-23 | 当前不建设Haruka商业化系统；个人Key调用只记录按attempt的模型用量，不维护金额。应用缓存命中与供应商Prompt缓存Token分开 | [模型用量统计](../contracts/model-usage.md)USAGE-01～USAGE-09；阶段1建立持久化/聚合基础，实际模型阶段补供应商适配，均未实现 |
| DEC-24 | 产品设计语言采用「晴空频率」；整体风格已获认可，色彩/形状/文字/状态/动效/文案集中维护，场景只调整视觉强度 | [产品设计语言](../product/design-language.md)DESIGN-01～06随正式页面切片验证；深色派生色、字体资源及尺寸/动效为实现初值，HTML原型已重建，Flutter B0壳已增量对齐，业务页面按切片验证，不回写B0历史验收 |

## 3. 决策导航与变更

| 阅读目的 | 权威正文 |
| --- | --- |
| 系统图、组件职责和技术基线 | [系统架构](../architecture/overview.md)、[项目结构](../architecture/project-structure.md) |
| 会话、RBAC、数据与持久任务 | [认证](../architecture/authentication.md)、[授权](../architecture/authorization.md)、[数据与任务](../architecture/data-jobs.md) |
| 接口、权限代码、模型用量、解析结构与出处 | [API](../contracts/api.md)、[权限目录](../contracts/permissions.md)、[模型用量统计](../contracts/model-usage.md)、[解析数据结构](../contracts/material-structures.md)、[出处契约](../contracts/content-locator.md) |
| 工程入口、生成与阶段边界 | [脚手架](../engineering/scaffold.md)、[B0/B1/B2 验收](../delivery/milestones/scaffold.md) |
| 配置、发布与恢复 | [运行配置](../operations/configuration.md)、[部署与恢复](../operations/deployment-recovery.md) |
| 未选方案、缺少的工程契约及最晚锁定点 | [待决清单](pending.md) |

DEC 编号保持稳定，方案变化时更新理由、影响和验证条件，并同步对应权威专题；不另复制接口字段或运行步骤。被选中、文档化与已实现/实测分别记录，推荐组件不能因写入本表就变成用户已确认或工程已验证。

B0/B1 允许的生成器评估/集中手写 DTO 过渡以脚手架的明确期限为准，B2 前必须锁定长期方案；待选库与未实现状态不等于功能已验收。开放选择不阻止无关工作，但依赖项未决不能签署相应就绪或交付门禁。

## 4. 设计假设与状态维护

所有数值初值（会话/日志队列/上传/任务限额/测试门槛）属于本项目建议，不是供应商保证或MyHome生产事实。改动时只在对应权威专题修改数值，其他文件链接，避免多份默认值互相冲突。

审查问题和修复记录放 [文档审查记录](../delivery/reviews/2026-09-22-design.md)。文档完成表示覆盖与一致性达到审查门槛；工程lint、测试、模型质量、平台发布与部署仍按 [交付验收](../delivery/acceptance.md) 提供真实证据。
