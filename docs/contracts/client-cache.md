# 客户端缓存校验契约

状态：2026-09-27，客户端缓存基础及本轮恢复修复已部分实现；私有请求真实会话绑定及响应头协作已接线，本篇定义的服务端 validate、cache_descriptor、offline_grant 仍待按消费者交付，不能把客户端测试替身视为正式离线协议已上线。服务端始终是业务与权限权威；此契约为[前端缓存机制](../architecture/frontend-cache.md)提供轻量读取协作，不引入离线写同步或新模型调用入口。从B2a开始按实际消费者注册，B0/B1历史验收不变；缺绑定头的旧客户端需按[统一响应契约](api-responses.md#51-b2起的私有请求会话绑定)升级。当前实现与恢复修复见[缓存恢复修复记录](../delivery/reviews/2026-09-27-cache-recovery-fixes.md)，后续缺陷修复及实际验证见[现有缓存缺陷修复](../delivery/reviews/2026-09-27-cache-defect-fixes.md)。

## 1. 传输与权限

新增用户端 `POST /api/v1/me/cache/validate`，语义为只读批量校验，响应为 `SuccessResponse[ClientCacheValidation]`。使用当前client会话、[统一私有请求会话绑定](api-responses.md#51-b2起的私有请求会话绑定)，Web沿统一CSRF校验；不支持admin受众，也不增加可绕过业务权限的cache.read授权。服务端从认证上下文取得本人身份，逐item校验该类型的实际业务read/动作、归属、来源、删除代次与可见投影。

普通业务GET仍沿原端点和返回信封；本契约不批量返回正文，不替代profile.read、ai.explain、speech.play等权限。批次最多50项、请求体最多64KiB；超限返回统一请求校验错误，不截断成功。未知kind/projection/action是协议错误；不存在、其他owner或无权资源统一返回该item的unavailable，不暴露其版本/存在性/失权细节。整个身份失效按统一401/403，不能伪装所有item未命中。

认证API、validate及私有媒体使用 `Cache-Control: private, no-store`；响应不依赖HTTP缓存或304。允许应用持久化的业务DTO由显式白名单处理，头像沿专用规则。首版不新增ETag/If-None-Match协议，避免代理/浏览器返回旧权限下的表示。未来优化须同时定义鉴权先于304、投影与租期刷新，不能仅装缓存插件。

## 2. 请求与结果

| 请求字段 | 语义 |
| --- | --- |
| protocol_version | 初版1；不兼容版本按API统一错误拒绝，不猜测字段 |
| items[].request_ref | 批次内唯一随机关联值，仅回显对齐响应，不作为owner或权限凭证 |
| items[].resource | 白名单kind及稳定id、要读取的领域版本；具体结构复用相应资源契约 |
| items[].source_binding | 来源/版本/受控字段或已有合法绑定引用；必须与该入口一致，无来源独立查询使用本人已提交结果绑定 |
| items[].projection | 白名单投影种类和schema版本；题面/交卷复盘/普通学习分开 |
| items[].action | 该注册资源允许的具体只读动作，不能自造权限代码；服务端映射实际所需动作交集 |
| items[].known_versions | 本机持有的resource/representation/artifact/NLP/绑定版本，不参与授权，不作为当前值可信输入 |

客户端不能提交user_id、任意URL、任意SQL、授权布尔值、正文或模型配置来让validate生成内容。source_binding沿[出处协议](content-locator.md)的类型化引用，后端重新取其真实关系；图片附件、凭据秘密、管理元数据、未提交流片段、场次听力均不注册此入口。请求的语义字段由各领域schema定义，不用无约束JSON兜底。

| 结果字段 | 语义 |
| --- | --- |
| protocol_version、server_time | 当前协议及可信在线时间锚；不替换统一响应meta/request_id |
| scope | 当前instance_id、user_id、audience、session_ref及安全/授权版本；客户端另绑定经确认的规范化服务端点，响应不可覆盖该端点；不含Cookie/Token/Key |
| items[].request_ref、state | state为same、changed、unavailable；不返回请求中未出现的私有资源 |
| items[].validated_versions | 仅有权时返回该投影的当前版本向量；same表示所需各维度都相符 |
| items[].read_ref | changed时返回注册的规范资源/投影引用，客户端使用固定领域端点读取；不返回任意URL/隐藏字段或他人资源 |
| items[].offline_grant | 仅登记为可离线且当前来源/动作/状态允许时返回，其他类型为null；不能根据same自行延长期限 |
| items[].grant_revoked | 明确撤销已有本机许可时为true；缺省/false且offline_grant为null只表示本次未续租，不延长也不删除仍有效的同身份、来源和版本许可 |

同一item的身份、来源权限、当前指针和投影版本必须来自一致读取；使用现有ScopeContext与领域锁/版本复核协议，不能先读授权后混入变更后的隐藏投影。不同item允许分别成功，不宣称整个批次是一份跨业务冻结快照。普通GET/resolve的DTO须提供同等可比较版本和许可元数据：放在注册类型的 `cache_descriptor`，不修改通用SuccessResponse/PageResponse信封，不保存旧request_id。

版本先按领域规范比较：数值revision仅在同一个聚合/源代次内单调；不可变asset ID/摘要只比较相等。已删除来源不可因客户端持有旧版变成可读；独立合法收藏历史通过它自己的入口和来源快照校验。`changed`不保证存在完整新成品；read_ref可能读取当前pending/broken状态，不能因此触发生成。

## 3. 注册投影与许可

| 注册类别 | 校验依据 | 是否可签离线许可 |
| --- | --- | --- |
| material_content | 本人material + 精确版本/章段 + 对应read + 源删除代次 | 仅正式已发布小说/教材阅读投影；试卷准备/隐藏字段不签 |
| learning_text | 已实现客户端查询历史/card使用agent.read及实际来源约束；后续上下文解释与收藏快照须分别注册其来源动作和投影 | 单独判断；仅既定离线学习字段可签，已有词句解释仍额外满足ai.explain与来源许可；缺离线资格不拒绝合法在线读取 |
| speech_asset | 本人合法来源 + speech.play + 精确manifest/asset/实际格式；global_word另验本人词条/读音/profile资格 | 普通许可音频可；任何场次限次听力不可 |

B2a可先交付路由/注册器/边界测试；未实现种类不能假返回same或许可。资料/设置/列表/消息/成绩/用量仍直接网络读取，无需为了validate新增版本表或业务空壳。各领域接入时在自身DTO和正式OpenAPI中登记cache_descriptor与注册schema，按后端单向生成流程更新客户端，不在文档阶段伪造生成物。

offline_grant是服务器经当前鉴权生成的本机许可快照，必含scope/session_ref、security_epoch、authz_version.user、authz_version.policy、精确来源/投影/内容版本、所需动作交集、issued_at/server_time、expires_at和许可schema版本；只经可信在线ApiClient写入。两种授权版本必须同时与最近确认的access一致，任一缺失/变化都拒绝离线读。它不是登录凭证，不回传作为服务端授权依据，也不承诺防设备所有者篡改的DRM。期限取服务器配置上限（推荐24小时）、会话/动作/来源的最短期限。没有明确许可或缺任一依赖时不可离线读；合法在线same/changed可以同时offline_grant=null，不能让离线附加条件变成新的在线权限门槛。server_time由本次校验服务端生成，不回放旧响应时间；客户端按架构中的单调计时/往返上界计算剩余期，迟到响应不重置租期起点。

可信响应适配字段形状为`schema_version: 1`、`scope: {instance_id,user_id,audience,session_ref,security_epoch,authz_version:{user,policy}}`、`resource: {kind,id,source_binding,projection,action,query_key?}`、`required_actions: [权限代码]`、`version: {resource,representation,artifact,nlp,binding}`及`issued_at/server_time/expires_at`。空query_key可省略，非空必须匹配。客户端先核对全部scope、来源、投影、动作及版本，再在本机派生不可由服务端指定的resourceKey摘要；`required_actions`只作响应绑定一致性核对，服务端仍负责动作交集授权。持久本机grant沿用原JSON格式读取，不能把其`resource_key`当作服务端wire字段。`same`且grant为null只保留仍有效的原许可，不续期；`grant_revoked=true`、版本变化、无权或不合法的新grant均立即撤许可。

来源与成品是两层：字节相同可以有多个入口绑定，校验/离线grant按绑定保存；不能因另一个来源仍可读就展示已撤权入口的上下文。NLP/ruby与正文投影绑定、独立版本管理；返回分析状态缺失时仍按既定手动选区降级，不允许客户端补调AI作为缓存修复。

## 4. 变更发现与故障语义

在线首次打开/来源切换/播放下载动作直接读取或validate；正在显示的内容按[客户端周期](../architecture/frontend-cache.md#4-数据策略与默认更新频率)重新校验。可变列表整页重新读取才能发现新增项；不能把逐ID校验当成增量全集同步。Job/SSE终态与本地广播仅为刷新提示，当前状态必须读真实已提交数据。

服务端业务提交无需额外写全局缓存版本表；已有聚合revision、结果指针/代次、内容版本承担真实性。接入缺少版本的可变资源时，在所属领域契约中补真实提交版本；禁止updated_at充当并发控制或全局时间排序。查询/列表没有快照协议时客户端使旧页整体失效并重新分页，CSV/AI选源快照继续沿专门契约。

validate失败只影响本次读取/许可，不触发模型、重评分、重建源或扩大scope。部分item unavailable立即清该绑定/界面；5xx/超时/协议错误不延长旧许可；明确身份/权限拒绝不可离线回退。只读请求的有界重试由统一repository负责，写请求的幂等键不用于validate。服务端限流和正常日志仅记录数量/种类/耗时/结果，不记录引用正文或原始payload。

## 5. 验收与关联

本协议与FCACHE-01/04/05/06/11/12同批验收：A/B引用互换、伪来源/投影、会话切换、已删源、考试未公开字段、批次超限/重复request_ref、部分失权、跨配置/分析版本、校验与业务更新竞争，以及离线期限不因重试延长。通过只能证明相应已注册种类；完整闭环由各模块实现后增量签收，发布必须覆盖全部注册表。
