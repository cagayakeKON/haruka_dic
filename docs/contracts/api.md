# API、事件与客户端契约

状态：设计基线 v0.2，2026-09-22，未实现。本文固定跨模块约定与接口分组，功能载荷由专题定义；后端初始化时将设计展开为OpenAPI/契约测试，不把本表误称已存在接口。

协议归属：认证传输与会话轮换见 [认证设计](../architecture/authentication.md)，权限代码见 [权限目录](permissions.md)，选区/来源字段见 [出处协议](content-locator.md)，CSV文件格式见 [CSV契约](vocabulary-csv.md)。模块只引用这些协议并描述用户行为，不再定义另一套字段；未来根contracts中的生成OpenAPI由后端schema单向导出，不与本文手工双向维护字段表。

## 1. HTTP与数据格式

REST前缀/api/v1；管理业务在/api/v1/admin。请求/响应JSON使用snake_case，Dart DTO做显式映射。UUID使用字符串，日期UTC ISO 8601，分数/金额等固定精度数字用十进制字符串；未知枚举客户端显示安全“不支持”状态，不能自动映射成功。

路由operationId显式声明且稳定唯一；后端schema/注册定义单向生成客户端契约。源码/导出文件归属、生成器原型及差异检查由 [脚手架蓝图](../engineering/scaffold.md) 维护，不改变本文的业务/传输语义。

所有用户端/管理端JSON采用 [统一返回模型](api-responses.md)：SuccessResponse[T]、PageResponse[T]、ErrorResponse。该专题唯一维护模型字段、分页、HTTP/错误码映射、异常清洗、路由声明与多语言；服务返回业务结果，路由包装成功，异常处理器包装失败。二进制、204、SSE等使用自身传输语义。

搜索文本不进入日志；排序/过滤字段允许清单，管理聚合另设上限。业务载荷、权限检查和重试必须同时遵循本文与统一返回专题，不能只统一外层JSON就跳过资源授权。

## 2. 认证、版本、幂等与重试

Web采用 [账号流程](../modules/accounts.md) 的HttpOnly会话Cookie与CSRF/Origin；原生Bearer。用户端/管理端分别校验audience，不接受查询字符串Token。X-Request-ID由服务端生成并返回；客户端发送X-Client-Request-ID、X-Operation-ID仅作已验证格式的关联标识。

可修改聚合在响应中给revision，更新请求携带expected_revision，缺少时拒绝；SQL以id/owner/revision匹配或锁定行检查，成功递增。并发冲突返回409及允许披露的当前revision，不自动last-write-wins。题目答案revision/edit_epoch和管理policy_revision分别在所属聚合处理，不能把每个字段混成全局一个版本。

创建任务、交卷、创建练习/评分、收藏批量/CSV确认、管理写等高影响操作使用Idempotency-Key。PG唯一键为actor+audience+method+route_template+key，保存规范化请求摘要及结果引用；相同键相同摘要返回同一个资源/提交结果，相同键不同摘要409。事务尚未完成返回可查询的in_progress或409，不能同时执行第二份。

首版幂等回执推荐保留至少7天或关联任务终态后24小时两者较长；涉及学习提交/评分的业务唯一约束长期保留，不因回执过期就允许重复Attempt。幂等命中仍检查当前权限/资源可见性，不把旧成功响应当绕过撤权缓存；不在记录中存Token/Key或完整答案，保存HMAC摘要/业务引用。

自动网络重试仅对安全读取、同一幂等键且已定义协议的写入及同次native刷新执行有界退避。超时不能推断写入未提交，先按操作/资源ID查询；流式中断不能自动重新发起模型调用。用户主动新操作必须新key，SDK/Worker重试总预算见 [数据与任务](../architecture/data-jobs.md)。

## 3. 接口分组与功能合同

表中方法/路径为待落地草案；`{id}`均验证归属和用途。明确的action子资源用于提交/重试等状态转移，不用任意`action`字符串做万能执行器。权限代码按 [中央目录](permissions.md) 展开。

| 资源/方法 | 关键输入/返回与业务动作 | 权限/规范 |
| --- | --- | --- |
| GET meta；GET model-capabilities | 公共instance_id/兼容版本/材料类型与格式能力；已登录者模型/声音/输出格式能力 | meta不带凭据探测；模型能力目录是client登录基础只读，不含Key/管理字段；能力支持不代表个人获权 |
| GET auth/policy；POST auth/register/login | 安全公共策略；邮箱/密码；业务会话或受限continuation | 账号流程；注册不接受角色/状态 |
| GET auth/csrf | 当前Web会话绑定的CSRF值 | 同源Cookie身份，不能当业务访问Token |
| POST auth/refresh/logout/password；GET auth/sessions；POST auth/sessions/{id}/revoke | 原生轮换/Web续期；本人退出/改密/会话治理 | 本人身份基础例外；同audience下验证 |
| POST auth/recovery/request/complete、auth/email/verify、auth/reauthenticate | 条件启用的一次性挑战/近期验证 | 目的/到期/单次消费；未选模式不公开能力 |
| GET me/access、admin/me/access | 最小user_id/instance_id/audience/session_ref、account_status、authz_version、权限/范围、nav、flags | 对应login；不要求profile.read，session_ref不是认证凭据，不返回全体用户策略 |
| GET/PATCH users/me、settings | 资料/学习/模型选择；revision | profile.read/update；拒绝身份/权限敏感字段 |
| GET/POST/PATCH/DELETE provider-credentials；POST {id}/test | 掩码/增删轮换；受限能力测试 | credential.read/manage/test；永不GET明文 |
| POST material-imports；POST uploads/{id}/complete | material_type/格式/用途/大小摘要/AI阶段选择；新文件上传意图，或按三类材料契约复用本人源文件重新处理 | material.import、目标试卷组合权限；复用另验源material.read/配额，exam源还需exam.read+exam.edit；目标类型固定，完整校验才受理 |
| GET/DELETE material-imports/{id} | 上传/受理状态；放弃未提交上传意图 | 本人material.import；已受理Job取消用job.cancel，不通过删除意图撤销已提交材料 |
| GET materials、materials/{id}、materials/{id}/revisions；PATCH/DELETE materials/{id} | 三类筛选、共用元数据/状态与版本摘要；改标题/删除，不返回正文/答案、不允许PATCH类型 | material.list/read/update/delete；类型分派以三类材料契约为准 |
| GET novels/{material_id}/revisions/{revision_id}/manifest、chapters/{node_id} | NovelManifest、小说章节原文与语言标注引用 | material.read、type=novel、同库/版本/节点校验 |
| GET textbooks/{material_id}/revisions/{revision_id}/manifest、lessons/{node_id} | TextbookManifest、单元内容/词表和已授权练习引用；不夹带题目答案/评分依据 | material.read、type=textbook；练习详情/作答仍另验practice动作 |
| POST sources/resolve | 授权解析出处，返回三类之一及专用目标引用 | 当前源业务read与同库/版本检查；考试按考试投影规则，不由自报locator获得权限 |
| POST materials/{id}/reparse、materials/{id}/analysis | 新确定性版本；明确AI分析 | reparse/analyze分离；expected_revision/幂等 |
| GET/PUT materials/{id}/progress；GET/POST/DELETE bookmarks | 小说位置/最远位置、课本单元位置、书签；不承载考试进度 | material.read与progress/bookmark动作；只接受novel/textbook |
| GET/POST/PATCH/DELETE collections；GET/POST/PATCH/DELETE tags | kind/词句/笔记/标签/状态/出处快照 | collection对应动作；标签关系本人范围 |
| POST collections/merge | 明确目标/来源条目和合并策略，expected_revision | collection.read/update/delete；只在本人范围合并，不静默删除来源 |
| GET collections/words/export；POST vocabulary-csv/previews；POST {id}/commit | 流式CSV、映射/预览/确认/游标 | CSV组合权限；既有记录比较/跳过需collection.read，合并再需update；无read只明确直接新增、不返回旧词表信息 |
| POST photo-word-imports；GET {id} | 一张图/语言→候选词预览，尚不写收藏 | photo.import；识别可能收费，不能冒充整卷OCR |
| POST photo-word-imports/{id}/confirm | 明确新增/补空合并/排除行后确认 | photo.import；新增再验collection.create；读取/合并既有记录另验collection.read/update，缺任一所选动作权限整次确认拒绝 |
| PATCH/DELETE photo-word-imports/{id} | 修正/丢弃尚未确认的候选预览 | 本人photo.import；已确认的Collection独立编辑，不回滚已提交记录 |
| POST practice-sessions、practice-generations；GET practice-sessions/{id} | 已有题开始与生成新题分离，返回冻结会话/Job | practice.start/generate/read |
| GET practice-generations/{id}；GET mistakes | 已受理生成状态/题目；本人有效错题列表 | practice.read及来源权限，失权结果不因知道Job ID可读 |
| POST practice-sessions/{id}/answers、finish；GET attempts/{id} | 答案版本/提交；结束/成绩读取 | practice.answer/read；服务端判状态 |
| POST attempts/{id}/grading-runs、review-requests | 付费评分/重评、个人异议标记 | grade.request/review.request；不能写任意分数 |
| GET/POST diagnoses；GET diagnoses/{id} | 报告列表/详情/生成，数据范围与统计窗口 | diagnosis.read/generate+来源read |
| POST explanations；GET explanations/{id}；POST {id}/feedback、cards/{id}/feedback | 选区/上下文引用→run/事件；完整结果/卡片反馈 | ai.explain/feedback；Agent卡片需agent.read；生成新结果与读取已有缓存分开 |
| GET/POST agent/threads；GET/DELETE {id}；POST {id}/runs | 分页历史/新轮次/删除；run引用与流 | agent.read/use/delete，每工具独立授权 |
| POST speech/requests；GET speech/assets/{id}/manifest | 来源/模型/声音/格式→Job或已有音频 | speech.generate/play及来源read |
| POST speech/resolve；GET speech/requests/{id}；GET speech/assets/{id}/media | 纯缓存查询、合成状态、音频传输 | resolve/play不收费、不要求Key；新生成只走requests且需generate |
| GET exams；POST exams；GET/PATCH exams/{id}/draft；POST {id}/versions | 试卷列表/从exam材料准备/校对/冻结；不能直接把novel/textbook当试卷 | exam动作+实际AI分析/导入权限；其他类型先显式重新处理 |
| POST exams/{id}/sessions；GET exam-sessions/{id}；POST {id}/takeover | 开考/恢复/显式编辑端接管 | exam_session.start/read/save、edit_epoch |
| PUT exam-sessions/{id}/responses；POST {id}/submit | response_revision/edit_epoch；最后答案与submit_reason | save/submit；服务端时间/锁卷 |
| POST exam-sessions/{id}/grading-runs；GET {id}/results | 初次批改或新generation重评；部分/有效成绩 | exam_grade.request/regrade/read |
| GET jobs/{id}；POST {id}/cancel/retry | 当前阶段、可操作状态、结果引用 | read的结果另验来源read；cancel只需本人范围/可取消状态和job.cancel；仅retry重验原业务权限/付费意图 |
| GET runs/{id}/events | Agent/解释/Job进度的统一应用事件流 | run类型所需read，不能只因有run_id放行 |
| GET runs/{id}；POST runs/{id}/cancel | 持久运行快照/完整结果；取消意图 | 读需对应领域权限；取消需本人job.cancel，失去agent.use不妨碍仍获授权的停止操作 |
| POST frontend-logs、admin/frontend-logs、frontend-logs/anonymous | 受众内批量/受限匿名，逐项接收结果 | 观测规范；不接收任意查询 |
| admin/users、roles、menus、auth-policy、quotas、model-catalog | 分页/详情/预览/显式写操作 | 管理工作流和admin对应动作、revision/审计 |
| admin/sessions、resource-metadata、jobs、audit-events、diagnostics | 限定元数据查询、撤销/安全运维 | 不返回私有内容/Key、不接受任意LogQL |

三类内容接口的语义和字段边界见 [三类材料契约](material-types.md)，各专用路径由对应模块 schema 定义，不用大一统阅读 DTO。`model-capabilities` 只负责模型能力，材料支持组合随公共 `meta` 能力段返回，不携带私有数据或个人授权；UI 不用硬编码扩展名表越过后端检查。管理登录/续期/退出/本人安全流程用admin/auth镜像路径，固定admin受众；业务修改用户状态/角色/权限使用独立子资源，不能把通用PATCH映射任意ORM列。最终具体路由表在工程PR中从此契约展开并接受路由保护枚举检查。

## 4. 文件与流式事件

上传意图只返回临时staging_key的写入能力、格式/大小/摘要规则、期限与传输方式。完成接口领取该意图的提交权后，由后端复制/流式读取到服务端独享的全新final_key，再校验final对象的实际字节/大小/摘要/格式，只有全部通过才在PG事务发布FileObject/Material/Job。客户端永远不获得final_key的PUT权限，Worker只读取这个已验证最终对象；重试不能覆盖已发布final对象。临时对象被重复PUT或复制时改变，最终校验不符就拒绝并清理，不沿用先前HEAD结果。完整状态/竞态合同见数据与任务；头像/照片/试卷等所有上传复用同一不可变发布过程。

私有下载签发前验证业务权限/对象用途，短签名地址到期前的撤权限制必须明确；即时撤权内容采用API鉴权代理。媒体正确设置Content-Type、Range/206、长度与缓存策略，不缓存带会话的私人响应到公共CDN。CSV流失败不显示完整成功，前端收到有效完成后再报告本地保存结果。

SSE采用两步：POST创建run/Job，返回run_id；GET其events读取。事件信封包含schema_version、event_id、run_id、sequence、type、occurred_at、payload，事件类型accepted/progress/text_delta/tool_status/card_ready/completed/failed/cancelled。完整card_ready才允许收藏/后续动作，不能把半JSON交互当最终结果。

Last-Event-ID用于有界事件回放；首版仅保证持久状态、阶段结果和最终卡片可恢复，不保证每token永久存档。窗口外返回需要重新取run快照的明确事件/错误，前端补读最终消息，不重新收费生成。SSE重连重新授权，心跳检查会话/权限；权限丢失关闭，不给旧账号推送新结果。代理禁缓冲/合理超时需部署实测。

## 5. 兼容与验收

新增可选字段向后兼容；删除字段/改枚举语义/必填字段需版本升级或明确迁移期。每次发布记录min_supported_client与契约版本，旧客户端不能理解的写协议显示升级提示而非猜测提交。CSV、AI输出、事件、出处协议有各自schema_version，不能一个app版本代替全部。

API-01：每个路由映射权限/公共例外并测越权；API-02：分页/版本/幂等/超时重试不重复写；API-03：Pydantic/Dart对null/未知枚举/Decimal/Unicode/UTC一致；API-04：SSE断连/窗口外恢复不重复收费；API-05：文件/CSV媒体类型和失败状态在三端有效；API-06：旧客户端兼容、生成契约差异及未经授权字段拒绝可验证。

统一返回、框架异常覆盖和语言/客户端降级的 API-07～API-10 见 [返回契约验收](api-responses.md#7-验收)，按已交付路由和本阶段影响范围执行。
