# 文件提取、视觉OCR与原书ruby

状态：2026-09-26，DESIGN23设计，尚未实现。用户确认PDF/图片文字走视觉大语言模型识别并保留ruby，EPUB直接解析。本文明确按实际内容分派和注音保存；格式开放阶段仍由[三类材料](material-types.md)及OPEN-01管理，不把处理方案当成所有格式已经可导入。后续标注见[统一文本分析](../architecture/text-analysis.md)，供应商调用/授权唯一沿用[视觉OCR](../architecture/vision-recognition.md)。

## 1. 格式分派

| 输入 | 提取路径 | 必须保留 |
| --- | --- | --- |
| EPUB中的XHTML文字 | 受限解包，解析容器/包清单、spine及内容文档；按内容节点提取，不整书截图OCR | 文档顺序、块/对话/列表/脚注关系、原文字体语义所需属性、ruby基础文字与注音对应及原件位置 |
| 扫描/图像型PDF、图片 | PDF先确定性渲染页图；图片规范方向；由本人配置的视觉模型做OCR | 原页图、页序/方向/裁切变换，正文、原有注音和版面角色的分别转写 |
| 有文本层的PDF | 只有正文完整性、阅读顺序、注音对应可验证时直接提取；缺失/乱码/对应不可靠的范围使用视觉OCR | 不因存在文字层就丢弃小字注音，也不将文本层与OCR重复拼接 |
| EPUB内嵌扫描图/文字图片 | 正文仍直接解析；需要识别的图独立列入OCR清单，在已有授权范围内调用 | 图的位置及其角色；alt文字不能当成已识别完整正文 |
| 获准的MD/TXT | 确定性读取及注册语法解析；MD内受支持的ruby标记转换为相同结构 | 原段落和标点，原书已有与程序补充的注音来源分开 |

以上说明扫描/图片类PDF的OCR要求，也保留可靠文本层的直接提取路径。确定性提取不调用模型；OCR需要已确认的页/区域和调用上限。混合文件逐区域记录选用方法，不为一张嵌图重识别整本。格式适配器只生成来源结构；小说/课本/试卷继续各自校验和发布。

EPUB的包清单/spine与内容文档结构依据[W3C EPUB 3.3](https://www.w3.org/TR/epub-33/)。实现按接受的EPUB版本/样本锁定适配，不从ZIP文件名排序猜阅读顺序。限制解压总量/比率/层数和路径，禁实体外部访问、脚本执行及自动抓取远程资源；保留原件，不把原HTML直接当应用可执行页面。

## 2. 原书注音结构

`canonical_text`只保存基础文字。源块的`presentation_payload.source_ruby`保存版本化数组；HTML的`rt`为注音，`rp`为兼容展示，不能把它们混入基础文字偏移。[HTML ruby规范](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-ruby-element)区分基础文字与注音；下面的范围/校验字段是Haruka自己的协议。

| 字段 | 规则 |
| --- | --- |
| annotation_id / schema_version | 应用生成的稳定ID和载荷版本，不由模型发明业务ID |
| base_spans | 所属版本内基础文字的有序块范围，使用Unicode scalar左闭右开偏移 |
| annotation_text / annotation_language | 原书注音文本和可确定的语言；不能用词典读音覆盖作者写法 |
| annotation_kind | reading/gloss/unknown；ruby可能表达释义，非reading不自动作为TTS发音提示 |
| grouping / alignment | mono/group/complex；可选组内对应。整词注音不能按字符长度机械分配给每个汉字 |
| origin / verification | epub_markup/pdf_text_layer/md_markup/vision_transcription；validated/uncertain/user_confirmed，模型自报分数不等于验证通过 |
| evidence_ref | epub_markup为包内路径/节点范围；md_markup为原文件摘要/标记范围/语法协议；pdf_text_layer为原文件摘要/页及文字对象范围/阅读顺序和注音对应校验依据；vision_transcription为原页/裁切范围及识别run；各项含提取协议版本，确定性来源不伪造run，精确字框仅在验证可靠时可用 |

跨块注音唯一保存在base_spans首块的source_ruby中，annotation_id在所属MaterialRevision内唯一。读取涉及任一跨度时，服务按受控源关系补取锚定块注音并投影完整组；客户端按版本+annotation_id去重，分页不能将半组冒充完整读音。任一跨度无权时不返回整组，字段或语义边界不允许的跨块组进入质量问题；不为每个块复制一份权威注音。

示例`<ruby>手紙<rt>てがみ</rt></ruby>`存基础文字“手紙”和覆盖这两个scalar的group注音“てがみ”；分词、复制、查询及朗读正文不能变成“手紙てがみ”。嵌套/多层注音保存组层次及原件引用；当前渲染器不能完整呈现时明确降级，不能静默删除注音。

视觉输出使用临时块键及所给页/区域引用，分别返回base_text和ruby_candidates。程序先验证块文字/对应范围，再分配正式块/annotation ID。看不清、无法确定对应基础文字或重叠矛盾的候选保存在私有质量产物中并登记MaterialImportIssue，不发布为有效ruby；基础文字可靠时允许明确“注音待校对”的降级阅读。不能调用NLP猜一个读音后冒充原图识别到的注音。

阅读模式呈现有效原书ruby，解析模式在此基础上补充NLP读音；同一基础范围有效原书读法优先，冲突作为质量信息，不在两层重复显示。校正已发布的基础文字或原书ruby都创建新MaterialRevision；仅重算程序补充读音创建新分析版本。下游缓存依据实际依赖区分，见[文本分析版本规则](../architecture/text-analysis.md#5-版本缓存与复用)。

## 3. 提取结果与恢复

原件/受控页图使用既有FileObject和私有MinIO；完整且通过结构校验的OCR候选保存为版本化私有JSON对象（注册purpose=`vision_recognition_result`），经`job_stages.result_refs`引用其FileObject、实际输入/模型/Prompt/输出协议摘要及来源页/区域。按既有上传/对象发布流程验证后原子提交阶段，不把大段文本放进Outbox或日志，不新增每页OCR结果表。

候选中未确认ruby、阅读顺序和质量问题不会因保存而自动可用。类型服务从该成品发布SourceUnit/ContentBlock及source_ruby，source_asset/原件关系继续负责证据保留；阶段成品只通过本人准备/校对权限读取，考试正文通用接口不返回隐藏答案或脚本。stage和成品引用纳入GC；业务发布仍在恢复中或质量校对仍需候选时不能TTL删除。

已提交OCR命中先恢复业务发布；完整响应已保存时不再次调用模型。严格身份包含owner/源文件字节摘要/页区域/渲染及提取版本/实际模型与协议，Redis丢失不代表未识别。已发布版本普通阅读只读取来源产物，改模型不自动重识别；用户显式重识别才创建新内容版本。供应商结果未知遵循unknown恢复规则，不能承诺供应商恰好执行一次。

首版OCR恢复按本次导入/重解析Job的阶段清单查找已提交成品，不新增跨任务全库OCR哈希检索库。同阶段结果引用须匹配上述输入身份，且所依赖FileObject仍完整有权；重复导入的跨任务OCR去重不在本轮承诺。已发布正文的普通跨端读取直接复用其持久内容，不经过识别任务。

## 4. 必需验收

| ID | 正式验收要求 |
| --- | --- |
| SRC-01 | EPUB按spine和受支持结构提取，rt/rp不混入基础字串；整词/逐字/多层注音及脚注可追溯，异常包和外部资源不执行 |
| SRC-02 | 扫描PDF/图片使用本人视觉模型；混合页只识别授权缺失区域；文本层存在但ruby丢失时不能判完整 |
| SRC-03 | 原书读音与NLP读音分开；模糊小字/错位/重叠候选不伪装有效ruby，修正文和源ruby均新版本 |
| SRC-04 | 完整OCR落盘后发布失败可恢复且供应商计数不增；重启/Redis清空/重复投递、unknown、跨账号及试卷隐藏字段分别验证 |

源格式能力、NLP质量、视觉模型样本和持久恢复都在相应实施阶段验证；本轮只有文档设计。
