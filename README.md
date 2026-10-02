# Haruka（ハルカ）

当前版本要求实现手机/电脑原型的全部产品功能；[PLAN2路线图](docs/delivery/roadmap.md)保留B0/B1，重排B2后切片，[35组功能清单](docs/delivery/prototype-scope.md)逐项映射实现与验收。

把用户自己的小说、课本和试卷，变成可阅读、可朗读、可练习和可模拟考试的语言学习资料库。当前只适配这三类，分别使用专用处理流程与页面。材料上传暂限日语和英语；日语NLP固定SudachiPy B中粒度，英语固定spaCy，详见[语言与分析设计](docs/architecture/text-analysis.md#11-已确认的日英nlp适配)。

采用 Flutter（Windows、Web、Android）与 Python 前后端分离架构，学习 Agent 使用 Pydantic AI。支持多用户、管理后台与完整 RBAC；使用各用户自己的 API Key，朗读采用 Gemini/OpenRouter TTS，用户备份恢复仅为单词 CSV。

DESIGN23补齐全应用NLP标注、AI成品存储、EPUB直接提取及扫描/图片视觉OCR保留ruby的[设计方案](docs/architecture/text-analysis.md)与[局部记录](docs/delivery/reviews/2026-09-26-text-analysis-ruby.md)。仅文档，未修改原型或正式应用。

## 当前状态

阶段1的 **B0 可重复工程基础已验收**：包含 [Flutter三端应用壳](frontend/README.md)、[可安装Python后端](backend/README.md)、[本地基础设施](dev/README.md)、受控数据库初始化、前端契约、开发编排和质量门禁。Windows/Linux干净检出、仓库外正式入口、三端交互及完整B0证据矩阵已通过，详见 [B0验收记录](docs/delivery/reviews/2026-09-22-b0-acceptance.md)。[B1账号与收藏闭环](docs/delivery/reviews/2026-09-26-b1-implementation.md)已按用户最终验收决定通过；找回密码闭环只验Web，前端日志只验Web，Windows原生完整矩阵和Android找回完整闭环未完成且不补测，已有局部操作保留。本地隔离SMTP闭环获接受，外部SMTP未实测。未执行步骤不记成实测。[B2a本人资料与设置](docs/delivery/reviews/2026-09-28-profile-settings-acceptance.md)已按当期范围重新验收通过：用户指出旧正式界面偏离已确认Flutter mock，旧视觉通过结论被撤回；真实功能随后迁入同一Flutter主界面、重复页面/壳/导航已删除，正式Web与Android实操和隔离PG定点证据见验收记录。B2b完整治理已有实现与切片复核，2026-09-30 正式 Web/Android 实操、集中修复与独立定点复核已完成，B2b当期范围验收通过，见[实现与验收记录](docs/delivery/reviews/2026-09-29-identity-governance-implementation.md)；[B2c凭据与模型任务](docs/delivery/reviews/2026-09-30-model-credentials-tasks.md)当期工程实现、联调与独立review完成；真实测试均KEY_REJECTED，2026-10-01用户确认该结果并要求不再验证模型，B2c按此范围验收通过，模型可用性未验证，阶段1已完成，M1材料导入、材料库与持久通知已完成；下一开发单元为M2小说专用处理，M3/M4及阶段3～6仍待实施。

2026-09-26 的 [B0设计对齐](docs/delivery/reviews/2026-09-26-b0-design-alignment.md)补充增量迁移、账号安全字段、授权范围和权限目录，并将Flutter基础壳对齐「晴空频率」。仍为12张基础表；业务页面、NLP、AI/TTS和学习缓存继续按后续切片实施。本次局部验证不替换原B0完整验收矩阵。

产品设计语言已确认为 [「晴空频率」](docs/product/design-language.md)：灵动青春、科技感，以晴空蓝、少量芽黄绿、短声线及统一排版/反馈规则贯穿各场景。[HTML交互原型](prototype/README.md)已按该语言重建手机与电脑两套独立界面，手机端进一步优化了内容排版、底部操作与学习流程；电脑端以相同视觉语言重构了材料列表、阅读分栏、分步表单和键盘操作，两端均清理了非产品说明文案。DESIGN6同步了收藏列表/详情弹窗、词本管理弹窗、每日单词、查询与完整卡片收藏、材料直达阅读，以及本地WebSocket进度示例；DESIGN11 修复阅读返回与筛选空态，优化收藏整行操作和手机列表密度；DESIGN12 调整查询输入优先级、来源就地选择与习题设置/范围的一次确认；DESIGN13将查询限定为语言学习任务，移除回答类型，重做学习卡片与紧凑词本列表；DESIGN14移除查询类型选择，按直接输入自动判断语言任务；DESIGN15移除独立Agent聊天，AI仅通过具体功能入口使用；DESIGN16统一选区朗读/查询，DESIGN17补充普通题直接收藏与交卷后试卷的选区/收藏，DESIGN18加入单词喇叭、句子分词浮层和小说连续朗读；DESIGN20加入小说ruby解析模式、点句释义与按章多选准备解析/朗读；这些材料、查询、朗读等演示仍只使用内存中的虚构示例，不代表对应正式业务已交付。不设“继续阅读”的产品边界保留。开发命令与工具前提见 [开发指南](docs/engineering/development.md)。

DESIGN21进一步修复电脑4K阅读布局，将小说点句解析及正文查询改为非模态右侧panel，正文保持可操作，手机保留底部dialog。实际原型检查见[局部记录](docs/delivery/reviews/2026-09-25-desktop-reader-panel.md)，正式应用未修改。

DESIGN22完善查询上下文设置、逐模型TTS适配与统一缓存方案；双端原型加入预算、上下文及缓存状态演示，见[局部记录](docs/delivery/reviews/2026-09-26-context-tts-cache.md)。正式业务未实现。

## 从这里开始

| 你要做的事 | 入口 |
| --- | --- |
| 了解产品目标、首版与后续范围 | [产品总览](docs/product/overview.md) |
| 设计产品视觉、组件、动效与文案 | [产品设计语言：晴空频率](docs/product/design-language.md) |
| 按功能或职责查阅文档 | [文档导航](docs/README.md) |
| 查看实施阶段和验收要求 | [路线图](docs/delivery/roadmap.md) |
| 查阅表结构、逻辑关联与Redis缓存字段 | [数据库设计书](docs/architecture/database-design.md) |
| 查看已选方案与待决事项 | [决策索引](docs/decisions/README.md) |
| 让Agent开始工作 | [AGENTS.md](AGENTS.md) |

MyHome提供可复用基础设施，Haruka保持独立业务、账号、数据与凭据。技术细节、检查规则和阶段证据分别由文档导航指向唯一正文；本页不重复维护配置或验收清单。
