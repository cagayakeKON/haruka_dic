# API、事件与客户端契约

状态：设计基线 v0.3，2026-09-23，未实现。本文固定跨模块约定与接口分组，功能载荷由专题定义；后端初始化时将设计展开为OpenAPI/契约测试，不把本表误称已存在接口。

协议归属：认证传输与会话轮换见 [认证设计](../architecture/authentication.md)，权限代码见 [权限目录](permissions.md)，选区/来源字段见 [出处协议](content-locator.md)，CSV文件格式见 [CSV契约](vocabulary-csv.md)。模块只引用这些协议并描述用户行为，不再定义另一套字段；未来根contracts中的生成OpenAPI由后端schema单向导出，不与本文手工双向维护字段表。

DESIGN16共用选区工具条不新增通用执行接口。朗读仍走speech/resolve与明确的speech/requests；材料/解释查询按实际来源走explanations或agent轮次，收藏仍提交完整card_id/card_revision与归本选择。非材料可见文字按[出处协议](content-locator.md#11-非材料学习文字的选区)传受控资源/版本/字段范围，服务端重取并授权；不可提交隐藏答案、试卷稿件或客户端正文冒充已发布源。

## 1. HTTP与数据格式

REST前缀/api/v1；管理业务在/api/v1/admin。请求/响应JSON使用snake_case，Dart DTO做显式映射。UUID使用字符串，日期UTC ISO 8601，分数等固定精度数字用十进制字符串；未知枚举客户端显示安全“不支持”状态，不能自动映射成功。

路由operationId显式声明且稳定唯一；后端schema/注册定义单向生成客户端契约。源码/导出文件归属、生成器原型及差异检查由 [脚手架蓝图](../engineering/scaffold.md) 维护，不改变本文的业务/传输语义。

所有用户端/管理端JSON采用 [统一返回模型](api-responses.md)：SuccessResponse[T]、PageResponse[T]、ErrorResponse。该专题唯一维护模型字段、分页、HTTP/错误码映射、异常清洗、路由声明与多语言；服务返回业务结果，路由包装成功，异常处理器包装失败。二进制、204、SSE等使用自身传输语义。

搜索文本不进入日志；排序/过滤字段允许清单，管理聚合另设上限。业务载荷、权限检查和重试必须同时遵循本文与统一返回专题，不能只统一外层JSON就跳过资源授权。

## 2. 认证、版本、幂等与重试

Web采用 [账号流程](../modules/accounts.md) 的HttpOnly会话Cookie与CSRF/Origin；原生Bearer。用户端/管理端分别校验audience，不接受查询字符串Token。X-Request-ID由服务端生成并返回；客户端发送X-Client-Request-ID、X-Operation-ID仅作已验证格式的关联标识。

可修改聚合在响应中给revision，更新请求携带expected_revision，缺少时拒绝；SQL以id/owner/revision匹配或锁定行检查，成功递增。并发冲突返回409及允许披露的当前revision，不自动last-write-wins。题目答案revision/edit_epoch和管理policy_revision分别在所属聚合处理，不能把每个字段混成全局一个版本。

创建任务、交卷、创建练习/评分、收藏批量/CSV确认、管理写等高影响操作使用Idempotency-Key。PG唯一键为actor+audience+method+route_template+key，保存规范化请求摘要及结果引用；相同键相同摘要返回同一个资源/提交结果，相同键不同摘要409。事务尚未完成返回可查询的in_progress或409，不能同时执行第二份。

首版幂等回执推荐保留至少7天或关联任务终态后24小时两者较长；涉及学习提交/评分的业务唯一约束长期保留，不因回执过期就允许重复Attempt。幂等命中仍检查当前权限/资源可见性，不把旧成功响应当绕过撤权缓存；不在记录中存Token/Key或完整答案，保存HMAC摘要/业务引用。

自动网络重试仅对安全读取、同一幂等键且已定义协议的写入及同次native刷新执行有界退避。超时不能推断写入未提交，先按操作/资源ID查询；流式中断不能自动重新发起模型调用。用户主动新操作必须新key，SDK/Worker重试总上限见 [数据与任务](../architecture/data-jobs.md)。

个人资料、学习档案和设置仍为三个独立接口；expected_revision分别对应user_extensions的profile_revision/study_revision/settings_revision，只写各自字段组。物理合表不合并权限、DTO或整行暴露，详见[账号表](../architecture/database-identity.md#user_extensions)。

## 3. 接口分组与功能合同

表中方法/路径为待落地草案；`{id}`均验证归属和用途。明确的action子资源用于提交/重试等状态转移，不用任意`action`字符串做万能执行器。权限代码按 [中央目录](permissions.md) 展开。

教材内容与试卷题面的类型化载荷遵循[解析展示契约](learning-presentation.md)：TextbookManifest 的八类角色和考试五类交互/题组分别定义，保留源顺序、关系、版本和消费能力要求，不返回模型生成的页面代码。原文对照复用受控源读取/文件签名，试卷完整原件与题面媒体按各自权限/用途投影；通用材料、出处、缓存及媒体接口不扩大考试内容可见范围。

| 资源/方法 | 关键输入/返回与业务动作 | 权限/规范 |
| --- | --- | --- |
| GET meta；GET model-capabilities；GET language-capabilities | 公共instance_id/兼容版本/材料类型与格式能力；已登录者模型/声音/输出格式能力；版本化UI/学习/解释语言标识 | meta不带凭据探测；两个能力目录是client登录基础只读，不含Key/用户资料/管理字段；能力支持不代表个人获权或模型质量已验证 |
| GET auth/policy；POST auth/register/login | 安全公共策略；邮箱/密码；业务会话或受限continuation | 账号流程；注册不接受角色/状态 |
| GET auth/csrf | 当前Web会话绑定的CSRF值 | 同源Cookie身份，不能当业务访问Token |
| POST auth/refresh；POST auth/logout；POST auth/password/change；GET auth/sessions；POST auth/sessions/{id}/revoke；POST auth/sessions/revoke-all | 原生轮换/Web续期；本人退出、当前密码改密、会话治理 | 本人身份基础例外；同audience下验证。改密成功推进安全epoch并撤销client/admin全部会话，不接受资料字段作为恢复证据 |
| POST auth/recovery/request/complete、auth/email/verify、auth/reauthenticate | 条件启用的一次性挑战/近期验证 | 目的/到期/单次消费；未选模式不公开能力 |
| GET me/access、admin/me/access | 最小user_id/instance_id/audience/session_ref、account_status、authz_version、权限/范围、nav、flags | 对应login；不要求profile.read，session_ref不是认证凭据，不返回全体用户策略 |
| GET users/me/account | 当前登录邮箱、验证/账号状态、创建时间等本人身份摘要 | 本人有效client会话的身份基础读取；不要求profile.read，不返回密码哈希/角色明细/安全epoch，也不提供邮箱PATCH |
| GET/PATCH users/me/profile | 本人显示名、可选出生年份/性别、资料完整度；field mask + expected_revision | profile.read/update；拒绝邮箱/角色/状态/权限及整数年龄写入，可选人口字段默认不进入AI |
| GET/PATCH users/me/study-profile | 母语/解释语言、目标语言/当前语言、各语言水平/目标；field mask + expected_revision | profile.read/update；受版本化语言能力目录约束，移除默认值不删除历史学习数据 |
| GET/PATCH users/me/settings | 模型/声音、时区、AI习题默认、阅读/朗读、theme/无障碍默认；field mask + expected_revision | profile.read/update；本机缓存/服务地址不伪装服务器字段，拒绝修改派生掌握/权限/配额 |
| POST users/me/avatar-upload-intents；POST users/me/avatar-upload-intents/{id}/complete；DELETE users/me/avatar | 本人avatar用途临时上传、验证/重编码后原子替换或删除当前头像 | profile.read+profile.avatar.update；只接受配置允许的静态图片，不接受外链/任意FileObject ID；替换使用profile expected_revision，删除保留受控GC |
| GET users/me/avatar | 当前本人私有头像媒体；无头像返回404/受控空态 | profile.read；每次鉴权，`Cache-Control: private, no-store`，不要求avatar.update，不产生长期公共URL或跨账号ETag，不因知道asset ID/旧revision读取他人对象 |
| GET/POST/PATCH/DELETE provider-credentials；POST {id}/test | 掩码/增删轮换；受限能力测试 | credential.read/manage/test；永不GET明文 |
| GET users/me/model-usage | 本人按时间范围、供应商、模型、能力、操作类型聚合的调用状态及input/output/cache等用量；可按有权run查询明细 | credential.read与self范围；未知分项为null，应用缓存命中不冒充模型调用，不返回Key/Prompt/回复；口径见[模型用量统计](model-usage.md) |
| POST material-imports；POST uploads/{id}/complete | material_type/格式/用途/大小摘要/requested_stages；视觉OCR与进一步AI分析分别明确范围/上限；新上传或本人源文件重新处理 | material.import、目标试卷组合权限；视觉OCR另验analyze；复用验源material.read/配额，exam源还需exam.read+exam.edit；目标类型固定，完整校验才受理 |
| GET/DELETE material-imports/{id} | 上传/受理状态；放弃未提交上传意图 | 本人material.import；已受理Job取消用job.cancel，不通过删除意图撤销已提交材料 |
| GET materials、materials/{id}、materials/{id}/revisions；PATCH/DELETE materials/{id} | 三类筛选、共用元数据/状态与版本摘要；改标题/删除，不返回正文/答案、不允许PATCH类型 | material.list/read/update/delete；类型分派以三类材料契约为准 |
| GET novels/{material_id}/revisions/{revision_id}/manifest、chapters/{node_id} | NovelManifest、小说章节原文与语言标注引用 | material.read、type=novel、同库/版本/节点校验 |
| GET textbooks/{material_id}/revisions/{revision_id}/manifest、lessons/{node_id} | TextbookManifest、单元内容/词表和已授权练习引用；不夹带题目答案/评分依据 | material.read、type=textbook；练习详情/作答仍另验practice动作 |
| POST sources/resolve | 授权解析出处，返回三类之一及专用目标引用 | 当前源业务read与同库/版本检查；考试按考试投影规则，不由自报locator获得权限 |
| POST materials/{id}/reparse、materials/{id}/analysis | reparse发布新内容版本；analysis可首次视觉转写尚无发布版本的源，或仅分析已发布正文 | 按[视觉OCR](../architecture/vision-recognition.md)明确阶段/页计划；首次OCR复核原import/read/analyze，已发布后视觉补识别/重识别需reparse+analyze；expected_revision/幂等/原件资格 |
| GET/PUT materials/{id}/progress；GET/POST/DELETE bookmarks | 小说位置/最远位置、课本单元位置、书签；不承载考试进度 | material.read与progress/bookmark动作；只接受novel/textbook |
| GET collections/daily-words | date与IANA timezone确定本地日，服务换算UTC半开区间；返回日期/时区、同快照total与稳定分页items，按CollectionItem.created_at/id排序，仅kind=word | collection.read、当前本人作用域；跨本去重，不以成员加入或CSV来源时间替代；非法日期/时区拒绝，无模型调用 |
| GET/POST/PATCH/DELETE collections；GET/POST/PATCH/DELETE tags | kind仅创建时选择（word/phrase/grammar/sentence/excerpt/exercise），完整内容/笔记/标签/exercise_control/出处；题目直接收藏提交带类型question_ref（题目ID/版本及必要场次/作答上下文）与notebook_ids，按[题目收藏规则](../modules/vocabulary-practice.md#题目直接收藏)重取当前可见投影；试卷需服务端确认submitted，不要求评分完成；与card_id分支互斥；卡片收藏提交card_id/card_revision/notebook_ids及必要的confirmed_target_language，服务端按[查询收藏规则](../modules/query.md)校验语言确认并重取已发布卡片保存完整快照；响应可带只读mastery/learning_revision | collection对应动作；拒绝写mastery/证据计数，不存在due/调度写入；实质学习内容变更推进版本；有成员时不得改成不匹配语言 |
| GET/POST vocabulary-notebooks；GET/PATCH/DELETE vocabulary-notebooks/{id} | 多本名称/目标语/简介、版本与去重统计；删除本保留各类型收藏和历史 | vocabulary_notebook对应动作，self/同库；读需collection.read，写按目录依赖；非空本不切换语种 |
| GET vocabulary-notebooks/{id}/items；POST vocabulary-notebooks/membership-changes | 稳定分页/筛选；明确add/remove/move、受控条目或冻结选择快照、所涉本expected_revision | notebook.read/update和collection.read；移动同时检查来源/目标本；不授权删除词、改掌握或复制学习进度 |
| GET vocabulary/learning-states | 本人词的只读掌握/原因/证据版本摘要；无队列、due或下次复习 | collection.read；证据/历史明细另需practice.read和实际来源read，按本筛选需notebook.read；缺实践读取权限只给摘要，不含Attempt ID/题答/分数；不发模型请求 |
| POST collections/merge | 明确目标/来源条目和合并策略，expected_revision；涉及词本时确认成员并集 | collection.read/update/delete；成员迁移另需notebook.read/update；只在本人范围合并，学习证据按等价/新学习版本重算，不取最高掌握值 |
| GET collections/words/export；POST vocabulary-csv/previews；POST {id}/commit | 流式CSV v2兼容v1、可选词本列、映射/预览/确认/游标；导入状态仅为来源快照 | CSV组合权限及词本列/筛选依赖；既有记录比较/跳过需collection.read，合并再需update；无read只明确直接新增、不返回旧词表信息 |
| POST photo-word-imports；GET {id} | 一张图/语言→候选词预览，尚不写收藏 | photo.import；识别可能消耗供应商用量，不能冒充整卷OCR |
| POST photo-word-imports/{id}/confirm | 明确新增/补空合并/排除行后确认 | photo.import；新增再验collection.create；读取/合并既有记录另验collection.read/update，缺任一所选动作权限整次确认拒绝 |
| PATCH/DELETE photo-word-imports/{id} | 修正/丢弃尚未确认的候选预览 | 本人photo.import；已确认的Collection独立编辑，不回滚已提交记录 |
| POST ai-exercise-selections；GET ai-exercise-selections/{id} | 按[AI习题](../modules/ai-exercises.md)接收单词本/收藏/教材/错题/诊断及时间/掌握/错误条件，以及题型/方向/题量/同源多题/难度/模型配置等生成设置；返回本人selection/revision/expiry、冻结设置摘要、计数和分页预览 | practice.read+每类实际来源read；按本需notebook.read，错题需mistake.read；不要求Key/generate，不调用模型或写学习事实；无due/复习条件 |
| POST ai-exercise-generations；GET ai-exercise-generations/{id} | 只提交selection_id+expected_revision和幂等键，返回冻结设置及持久引用冻结候选的不可变AiExercisePlan/Job（逻辑plan_id映射exercise_sets.id）；读取生成状态及有权习题集 | practice.generate/read+当前来源权限、本人Key/上限；确认与每个供应商调用阶段重验，拒绝覆盖生成设置或自报候选/mastery/错误状态，摘要冲突要求重新预览 |
| POST practice-sessions；GET practice-sessions/{id} | 用已有教材题/AI习题集开始并恢复冻结会话；不建立review-plan或时间调度 | practice.start/read及当前题目/来源权限；开始已有练习不会隐式生成题目或调用模型评分 |
| GET mistakes；GET mistakes/{id}；POST/DELETE mistakes/{id}/favorite | 本人全部可靠错题历史、当前状态/筛选/详情；收藏/取消收藏独立于错误状态 | mistake.read/favorite及题面/成绩实际权限；列表按投影裁剪，收藏不改评分/掌握，交换他人或无权来源ID拒绝 |
| POST practice-sessions/{id}/answers、finish；GET attempts/{id} | 答案版本/提交；结束/成绩读取；response_kind区分answer/dont_know/skip | practice.answer/read；answer/dont_know按冻结规则形成Attempt，skip仅记录跳过，不以空答案造零分；服务端判状态 |
| POST practice-sessions/{id}/items/{item_id}/assistances | 受控hint/reveal；服务端记录session_item、稳定根题/答案谱系、学习目标/版本和接受顺序后才返回提示 | practice.answer/read与本人活动场次；同根题换会话/设备不能擦除已辅助事实，独立新根题不继承曝光，反馈后订正不成为独立掌握证据；考试不复用此入口 |
| POST attempts/{id}/grading-runs、review-requests | 调用模型评分/重评、个人异议标记 | grade.request/review.request；不能写任意分数 |
| GET/POST diagnoses；GET diagnoses/{id} | 报告列表/详情/生成，数据范围与统计窗口 | diagnosis.read/generate+来源read |
| POST explanations/resolve；GET materials/{id}/explanations | 有界批量的带类型来源/用途只读匹配，含材料、受控资源及手工输入；本人书内已查结果分页索引不混入无材料记录 | ai.explain+实际来源read，考试按阶段限制；不生成、不写学习事实，不返回无权条目/计数 |
| POST explanations；GET explanations/{id}；POST {id}/feedback、cards/{id}/feedback | 明确生成/再解析→已有结果或run；完整持久结果/反馈；记录实际配置与版本 | ai.explain/feedback；Agent卡片需agent.read；按[学习结果缓存](../architecture/learning-cache.md)匹配/合并，新模型调用另验Key/上限；显式再解析使用expected_lookup_revision取得新查阅代次 |
| GET/POST agent/threads；GET/DELETE {id}；POST {id}/runs | 查询/功能运行记录与新轮次/删除，不提供聊天产品接口语义；mode=query/contextual、解释语言/可选目标语、可空材料引用；查询轮次提交文字与有序image_refs，由服务端AI判断语言任务，至少一项有效；run引用与流 | agent.read/use/delete，每工具独立授权；含图轮次检查本人视觉能力及全部附件 |
| POST agent/threads/{id}/image-upload-intents；POST agent/threads/{id}/image-upload-intents/{intent_id}/complete | 仅query_image用途；当前会话的临时上传、真实解码/规范方向/去元数据/重编码后发布不可变图片 | agent.use、本人query会话；复用受控上传发布，不接受任意FileObject或URL |
| GET agent/threads/{id}/images/{image_id}/content；DELETE agent/threads/{id}/images/{image_id} | 获取私有图片；删除未绑定的草稿附件，已绑定消息的附件返回冲突 | 读取需agent.read；草稿移除需agent.use及本人会话；逐次鉴权，private/no-store，正式会话删除与GC另行处理 |
| POST speech/requests；GET speech/assets/{id}/manifest | 来源/模型/声音/格式→本人请求或已有音频；区分private/global_word，后者按标准词条/读音/profile合并 | speech.generate/play及来源read；试卷隐藏听力稿不能作为任意客户端文本提交，须走试卷专用生成入口；ExamListeningAudioBinding不从此通用manifest端点交付，有限场次只走PlayAttempt；global_word生产者Job/Key/模型用量不返回给其他等候者，缺失不自动换用户Key |
| POST speech/resolve；GET speech/requests/{id}；GET speech/assets/{id}/media | 只读匹配/本人等待状态/普通音频传输；global_word响应含asset_kind及实际profile，不含贡献者/他人Job/使用人数 | resolve/play不发起供应商调用、不要求Key；全局媒体也须验证本人收藏来源/版本/读音/profile与资产匹配；试卷听力资产ID在通用resolve/media拒绝，防止绕过场次策略；新生成只走requests且需generate |
| GET exams；POST exams；GET/PATCH exams/{id}/draft；POST {id}/versions | 试卷列表/从exam材料准备/校对/冻结；不能直接把novel/textbook当试卷 | exam动作+实际AI分析/导入权限；其他类型先显式重新处理 |
| POST exams/{id}/listening-script-upload-intents；POST exams/{id}/listening-script-upload-intents/{intent_id}/complete | 为本人试卷草稿上传UTF-8纯文本/Markdown听力稿并发布不可变脚本源版本 | exam.read+exam.edit、expected_revision与本人试卷范围；只接受声明的文字稿用途，P0拒绝音频MIME、外链和任意FileObject ID |
| POST exam-versions/{id}/listening-analysis-runs | 从已发布试卷正文/视觉转写或文字稿生成听力题、脚本片段及题组/小题绑定候选 | exam.read+exam.edit+material.read+material.analyze、本人Key/上限和当前试卷版本；创建Job使用幂等键，模型输出只形成候选，不能发布正式绑定或把模型置信度当确认 |
| GET exam-versions/{id}/listening-review-items | 读取当前候选证据、未决项和人工决定，不触发模型调用 | exam.read+exam.edit、本人试卷/候选代次；失去analyze后仍可处理已产生的候选，不返回答案投影或他人Job |
| PATCH exam-versions/{id}/listening-review-items/{review_id} | 用户确认、编辑、重绑或拒绝听力题/脚本/题目候选，形成正式ExamStimulus与ExamListeningBinding | exam.read+exam.edit、expected_revision和候选代次；不调用模型、不直接生成音频，人工决定优先于同代次迟到结果，冲突要求重新加载 |
| POST exam-versions/{id}/listening-audio-generations | 按已确认脚本/绑定/声音配置创建私有TTS任务；缓存命中返回已有结果 | exam.read+exam.edit+speech.generate；新调用需本人Key/上限，每个供应商调用阶段重验；只允许确认且未泄露答案的脚本版本，资产不得进入global_word，发布需匹配试卷/脚本/生成代次 |
| GET exam-versions/{id}/listening-audio-bindings | 准备页读取已确认题组的音频状态/清单与受控播放信息，不触发合成 | exam.read+exam.edit+speech.play、本人版本/绑定；不要求generate或Key，不返回隐藏稿件/贡献凭据 |
| POST exams/{id}/sessions；GET exam-sessions/{id}；POST {id}/takeover | 开考/恢复/显式编辑端接管；开考冻结题面、听力稿版本、音频资产与播放策略；场次快照返回每个Stimulus的冻结策略、剩余次数和仍在期限内的active attempt摘要 | exam_session.start/read/save、edit_epoch；含必需听力题时另需speech.play且服务端ready预检已通过，不能在开考后隐式重合成或切换声音 |
| POST exam-sessions/{id}/listening-playbacks | `stimulus_id + edit_epoch + Idempotency-Key`领取一次新播放；返回play_attempt_id、冻结Manifest引用、`reserved/active/终态`、续播期限和剩余次数 | exam_session.read+save+speech.play、本人活动场次/当前编辑端/未截止/冻结资产；服务端锁定usage并先占位，同键丢响应重试返回同一attempt，有限次数并发不能超领；显式重播或终态后从头播放须新键/新attempt |
| GET exam-sessions/{id}/listening-playbacks/{play_attempt_id}/manifest；GET .../media | 携带当前edit_epoch读取该attempt的清单/媒体；只有active且未过期限可按持久交付游标/seek策略刷新签名、Range重连或续播；终段交付写completed，期限或回执不确定写closed_unknown | exam_session.read+speech.play、本人场次/当前编辑端/匹配Stimulus和冻结资产/attempt可用；接管后旧端授权失效，新端只恢复同一active attempt；终态拒绝继续签发/从头读取且不退次数，不返回脚本文本；仅可证明零字节的服务端故障可void |
| PUT exam-sessions/{id}/responses；POST {id}/submit | response_revision/edit_epoch；最后答案与submit_reason | save/submit；服务端时间/锁卷 |
| POST exam-sessions/{id}/media-reports | 冻结题面asset引用、edit_epoch与幂等键；服务端受控复核后返回未确认/确认事实及revision，不接受客户端自判故障或任意URL | session.read+save、活动状态/截止/edit_epoch；只读题面不授予报告写入，服务端推导受影响叶子；确认持久化及锁卷/评分门槛见[考试故障处理](../modules/exams.md#必要媒体故障的场次处理) |
| POST exam-sessions/{id}/grading-runs；GET {id}/results | 初次批改或新generation重评；部分/有效成绩 | exam_grade.request/regrade/read |
| WebSocket jobs/events | [版本化进度、订阅、代次/序号与恢复](job-progress.md)；只订阅，不创建或重试任务 | client会话、job.read、本人Job与来源read；Web严格Origin，原生Bearer；每次交付与心跳重验，撤权关闭 |
| GET jobs/{id}；POST {id}/cancel/retry | 当前阶段、可操作状态、结果引用 | read的结果另验来源read；cancel只需本人范围/可取消状态和job.cancel；仅retry重验原业务权限/模型调用意图 |
| GET runs/{id}/events | Agent/解释的SSE文字、卡片及关联run状态；材料/通用任务进度使用jobs/events WebSocket | run类型所需read，不能只因有run_id放行 |
| GET runs/{id}；POST runs/{id}/cancel | 持久运行快照/完整结果；取消意图 | 读需对应领域权限；取消需本人job.cancel，失去agent.use不妨碍仍获授权的停止操作 |
| POST frontend-logs、admin/frontend-logs、frontend-logs/anonymous | 受众内批量/受限匿名，逐项接收结果 | 观测规范；不接收任意查询 |
| admin/users、roles、menus、auth-policy、quotas、model-catalog | 分页/详情/预览/显式写操作；quotas只表示技术运行上限 | 管理工作流和admin对应动作、revision/审计；不提供商业套餐或金额字段 |
| admin/sessions、resource-metadata、jobs、audit-events、diagnostics | 限定元数据查询、撤销/安全运维 | 不返回私有内容/Key、不接受任意LogQL |
| GET admin/dashboard/model-usage | 按时间、供应商、模型、能力和状态的实例级Token/缓存等聚合 | admin.dashboard.view；不返回个人Key、Prompt、回复、私有材料或默认逐用户明细 |

三类内容接口的语义和字段边界见 [三类材料契约](material-types.md)，源层与三类领域对象见 [解析数据结构](material-structures.md)，各专用路径由对应模块 schema 定义，不用大一统阅读 DTO。试卷准备响应必须把正式对象、AI候选、人工校对任务和冻结考试DTO分开；题面接口不返回隐藏听力稿、答案依据、候选内部证据或可推断答案的TTS文本。`model-capabilities` 只负责模型能力，材料支持组合随公共 `meta` 能力段返回，不携带私有数据或个人授权；UI 不用硬编码扩展名表越过后端检查。管理登录/续期/退出/本人安全流程用admin/auth镜像路径，固定admin受众；业务修改用户状态/角色/权限使用独立子资源，不能把通用PATCH映射任意ORM列。最终具体路由表在工程PR中从此契约展开并接受路由保护枚举检查。

## 4. 文件与流式事件

上传意图只返回临时staging_key的写入能力、格式/大小/摘要规则、期限与传输方式。完成接口领取该意图的提交权后，由后端复制/流式读取到服务端独享的全新final_key，再校验final对象的实际字节/大小/摘要/格式，只有全部通过才在PG事务发布FileObject及对应用途的业务引用；材料导入才创建Material/Job，查询图片只发布会话附件，不创建材料或自动调用模型。客户端永远不获得final_key的PUT权限，Worker只读取这个已验证最终对象；重试不能覆盖已发布final对象。临时对象被重复PUT或复制时改变，最终校验不符就拒绝并清理，不沿用先前HEAD结果。完整状态/竞态合同见数据与任务；头像/照片/试卷等所有上传复用同一不可变发布过程。听力文字稿使用试卷专用purpose并发布到ExamListeningScriptSource/Version，不创建第四类Material；P0上传完成端点按真实字节与MIME拒绝原始音频，不能改走通用上传绕过。

私有下载签发前验证业务权限/对象用途，短签名地址到期前的撤权限制必须明确；即时撤权内容采用API鉴权代理。媒体正确设置Content-Type、Range/206、长度与缓存策略，不缓存带会话的私人响应到公共CDN。CSV流失败不显示完整成功，前端收到有效完成后再报告本地保存结果。

SSE负责Agent/解释的文字与卡片，关联Job状态不要求客户端再重复计数；材料和任务栏进度使用[WebSocket](job-progress.md)。SSE采用两步：POST创建run及必要Job，返回run_id；GET其events读取。事件信封包含schema_version、event_id、run_id、sequence、type、occurred_at、payload，事件类型accepted/progress/text_delta/tool_status/card_ready/completed/failed/cancelled。完整card_ready才允许收藏/后续动作，不能把半JSON交互当最终结果。

Last-Event-ID用于有界事件回放；首版仅保证持久状态、阶段结果和最终卡片可恢复，不保证每token永久存档。窗口外返回需要重新取run快照的明确事件/错误，前端补读最终消息，不重新调用供应商生成。SSE重连重新授权，心跳检查会话/权限；权限丢失关闭，不给旧账号推送新结果。代理禁缓冲/合理超时需部署实测。

## 5. 兼容与验收

新增可选字段向后兼容；删除字段/改枚举语义/必填字段需版本升级或明确迁移期。每次发布记录min_supported_client与契约版本，旧客户端不能理解的写协议显示升级提示而非猜测提交。CSV、AI输出、事件、出处协议有各自schema_version，不能一个app版本代替全部。

API-01：每个路由映射权限/公共例外并测越权；API-02：分页/版本/幂等/超时重试不重复写；API-03：Pydantic/Dart对null/未知枚举/Decimal/Unicode/UTC一致；API-04：SSE及任务WebSocket断连/窗口外恢复不重复调用供应商（WebSocket完整矩阵见WSP-01～WSP-05）；API-05：文件/CSV媒体类型和失败状态在三端有效；API-06：旧客户端兼容、生成契约差异及未经授权字段拒绝可验证。

统一返回、框架异常覆盖和语言/客户端降级的 API-07～API-10 见 [返回契约验收](api-responses.md#7-验收)，按已交付路由和本阶段影响范围执行。

## 6. 查询图片请求补充（P0，待实现）

查询上传前读取公开能力配置中的 `query_image_policy`（允许格式、单张字节/像素上限、每轮张数/总字节和临时保留期）；具体数值由部署发布，原型限制不是正式契约默认值。上传意图请求只含受限文件描述与用途上下文，owner来自认证，会话来自路径；complete按临时对象发布协议验证实际字节后返回 `attachment_id/revision/status`，只有ready可发送。

`POST agent/threads/{id}/runs` 的query输入包含可空 `text` 和有序 `image_refs: [{attachment_id, revision}]`，客户端不提交query_task或类型选项；纯图可直接提交，二者皆空拒绝。服务端AI根据实际内容与上下文判断语言任务，并验证输入/结果范围；图片只用于句段翻译、语法解析和语言习题批改。无法判断时请求必要的自然语言补充，不强制类型选择；只发布WordCard/SentenceCard/GrammarCard/ExerciseCard，超范围或未识别不返回可收藏卡片。不得同时接受base64、外链URL或客户端指定的final对象路径；引用必须全部ready、属于当前用户/当前会话/query_image用途，已绑定其他轮次的草稿不能重复绑定。重放同幂等键先返回原轮次结果，同键文字/图片版本/顺序或模型配置不同则冲突；任务推断是轮次的服务端结果，随原结果持久保存，重放不得因重新分类重复调用。新提交在共同会话锁下冻结消息引用，与AiRun/必要Outbox一致提交，删除会话与迟到完成遵守代次保护。

附件不合格、超限或未就绪用具体字段/状态错误拒绝整轮；缺视觉能力或本人Key不丢图转纯文字。成功JSON、分页与错误沿用统一返回契约，图片内容为鉴权的原生二进制响应；消息投影仅返回受控附件引用与必要显示元数据，不回传存储键、EXIF或供应商签名。完整流程和验收由[查询模块](../modules/query.md)维护。
