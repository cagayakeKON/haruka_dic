# 全应用NLP、AI成品与原书ruby存储

日期：2026-09-26，阶段1内文档小阶段DESIGN23，基线1dd0600。用户要求将全部学习文字NLP、AI解析及缓存存储方案写入文档，并明确PDF/图片视觉OCR、EPUB直接解析及ruby保留。只修改文档，原型、Flutter/Python、迁移和现有数据库未修改。

## 设计范围

新增[源提取与ruby](../../contracts/source-extraction.md)：扫描/图像型PDF与图片走本人视觉模型，EPUB正文直接解析，混合文件按页/区域分派；可靠PDF文本层只有正文/注音对应通过检查才直接使用。基础文字与原书注音分别保存、校验出处/对应，模糊候选保留校对信息，不能用NLP猜测充作原书读音。处理路径明确不代表全部格式已经开放。

新增[统一文本分析](../../architecture/text-analysis.md)：覆盖小说全书、教材各角色、题面/可见反馈、AI解释/例句/译文、收藏和已提交查询文字。源身份/字段项、版本/Unicode范围、单元快照、语言适配、跨块句子、发布/失败/任务恢复、缓存与权限/GC串联。AI完整成品先保存，NLP确定性后处理失败不重调AI；长按读取已加载标注，缺失保留手动范围。模型计量token与气泡token分开。

物理设计将原3张材料NLP表替换为text_analysis_versions/units/sentences，词序列收进有界unit JSONB，仍为142张目标表；字段、唯一/索引、关系清单、收敛清单同步。增加Redis R19私有热点标注，OCR完整候选复用FileObject/JobStage；Explanation/Card/音频持久成品沿DESIGN22复用。AGENTS、产品/模块、API/出处/章节准备、导航/决策和阶段计划同步，不勾选正式验收。

## 审查与检查

独立审查由非作者materials_design负责，learning_design在同一轮内核对提取/ruby部分；共2轮，第二轮只复核集中修订及直接影响，未扩大全仓。

| 首轮缺陷/建议 | 集中修订 | 第2轮结论 |
| --- | --- | --- |
| D23-1 / P2：可变源异步处理可能丢失旧文本，最终unit清单初始化时点不闭合 | 锁外准备实际输入快照，源提交事务绑定快照/分析头/JobStage/Job/Outbox；明确input_mode、输入对象引用/GC；最终unit manifest初始NULL、全清单校验及fence后封存，0仅已知空 | 已关闭；受理后编辑仍可恢复旧输入，未封存不发布unit |
| D23-2 / P2：各分析头CAS不能阻止旧pipeline迟到覆盖新版 | 源根锁维护desired和selected两项独立唯一；完成回调只有仍desired才能切selected，失败保留旧可读版；退役/删除先清标记、封存、停任务，再按引用GC | 已关闭；旧完成不能夺取新版意图 |
| D23-3 / P2：试卷草稿version_number不随正文编辑变化 | exam_paper_version分支只接收冻结ready卷；草稿继续源提取/校对，改题/脚本形成新冻结卷后再标注 | 已关闭；专题、数据库分册、考试模块一致 |
| D23-4 / P2：PDF文本层/MD ruby缺合法来源值 | 增pdf_text_layer/md_markup及格式专属证据；确定性提取不伪造OCR run | 已关闭 |
| 非阻塞建议：跨块ruby缺唯一锚点与投影规则 | 首跨度块唯一保存、完整组投影、版本+annotation_id去重；任何跨度失权不返回整组 | 已采纳并定点核对 |

实际检查：36份本次Markdown的本地路径/链接/锚点/代码围栏检查0错误、0未解析；markdownlint通过；git diff --check通过。关系目录142条、表名及序号分别142个唯一值；Redis键目录19条且19个唯一值。旧材料NLP名称仅保留在显式历史映射/替换说明，历史评审的18类Redis记录不重写；当前导航、分册及计划已同步。

EPUB/ruby结构参考源见提取契约中的W3C EPUB 3.3与WHATWG HTML规范。未运行应用/原型测试、DDL、迁移或真实供应商调用，也未修改原型/正式代码。词典选型、识别质量、JSONB粒度性能与原生三端体验仍待对应阶段用样本验证；SRC/NLP/LC正式验收保持未完成。
