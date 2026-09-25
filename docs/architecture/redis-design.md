# Redis 缓存与临时状态设计

状态：2026-09-25，DBDESIGN2 收敛稿，业务键尚未实现。属于[数据库设计书](database-design.md)。现有代码仅提供[连接池与命名构造器](../../backend/app/adapters/cache.py)，不能把本册视为已上线配置。会话算法、权限及学习结果规则分别以[认证](authentication.md)、[授权](authorization.md)、[持久缓存](learning-cache.md)为准。

DESIGN20[小说章节准备](../contracts/novel-preparation.md)复用已有任务进度及私有解释/音频查阅缓存。所选components与真实分项就绪由PG任务/成品派生，Redis丢失后回源恢复；本机下载数量不能当服务端任务ready，未选内容不生成缓存任务。不新增永久chapter-cache键族或用Redis锁替代逐句GenerationSlot。

## 1. 用途与命名

Redis 保存可丢失副本、会话材料和短期协调状态。业务唯一性、有效指针、撤销、幂等结果、考试播放计次、任务租约和供应商调用记录保存在 PG。会话材料是例外：丢失后重新登录，不能从 PG 自动补造登录凭据。

统一前缀 `N:v1`，`N` 为实际配置的 `resource_namespace`，B0 要求与 `instance_id` 相同，例如 `haruka-local-example`。不另硬编码一个 `haruka:` 前缀。`v1` 是缓存序列化版本，和 API、数据库迁移版本不同。现有 `Cache.key()` 由分段参数组装，每段非空且不含冒号；本册冒号表示段分隔。

| 占位符 | 值与可信来源 |
| --- | --- |
| `u` / `a` / `l` | 当前可信用户 UUID / 受众 `client` 或 `admin` / 已验证 Library UUID |
| `sid` | PG AuthSession ID，客户端提交的 ID 只用于定位，不能作为认证依据 |
| `rid` / `ver` | 已授权资源 UUID / 对应不可变版本或 revision；禁止从客户端直接拼接任意 Redis 键 |
| `h` | 服务端规范化后摘要；私人输入、邮箱、IP、Cookie、刷新凭据使用有版本的 HMAC，不在键中放原值 |
| `av` / `gv` | 当前 PG 用户授权版本 / 全局策略版本；使用实际物理列映射，见[账号权限分册](database-identity.md) |

私有业务键显式包含 `u:a`，库内副本再含 `l`。仅身份查找键、匿名限流键和受控公共目录键例外，分别由认证服务、入口保护服务和目录服务管理。客户端和模型均不能调用 Redis。Redis DB 编号与前缀不代替 ACL 或应用权限。

### 编码约定

下表 `string` 指 UTF-8 受限文本，UUID 用小写连字符格式，时间用 Unix 毫秒整数字符串，计数/版本用十进制整数字符串。JSON 中 nullable 使用 `null`；Hash 可选字段不存在，不写字符串 `null`、空字符串或 `-1`。Hash 的所有必需字段必须一起创建，部分缺失视为坏缓存。JSON 使用严格的版本化类型校验，未知版本丢弃。

JSON 副本统一信封：`schema_version: integer=1`、`cached_at_ms: int64`、`source_revision: int64`、`payload: typed object`；涉及不可变产物时 `source_revision` 为其产物版本。私有信封增加 `user_id: uuid`、`audience: string`，库内再加 `library_id: uuid`，读时核对键与值的作用域。Hash 的公共字段为 `schema_version=1`、`updated_at_ms`；其他字段见逐项定义。缓存时间不覆盖 PG 的 `created_at/updated_at`。

## 2. 键目录与 TTL

以下 TTL/容量是**推荐实现初值，待对应切片验证后进入配置**。会话绝对/idle 期限沿认证专题，刷新回执不得超过已规定的 10 秒。TTL 加减抖动只用于普通副本，不能延长安全期限。

| ID | Key 模板（省略 `N:v1:`） | Redis 类型 | TTL / 有界容量 | 写入者；miss/失效处理 |
| --- | --- | --- | --- | --- |
| R01 | `auth:web:<a>:<h>` | String JSON | 不超过关联会话的 idle/绝对期限 | 认证服务创建/续期；miss 重新登录 |
| R02 | `u:<u>:<a>:session:<sid>` | Hash | 用户 min(24h idle, 7d absolute 剩余)；管理 min(30min idle, 8h absolute 剩余) | 认证服务 CAS；miss/坏值失败关闭 |
| R03 | `u:<u>:<a>:refresh-receipt:<sid>:<request_h>` | String JSON | min(10s, 会话剩余) | 原生刷新原子发布；末段为稳定 refresh_request_id 的 HMAC；miss 不补造回执 |
| R04 | `u:<u>:<a>:refresh-used:<sid>` | Hash | 与会话 absolute 截止相同 | 原生刷新服务；每个旧凭据摘要有独立消费时间/代次/请求回执引用 |
| R05 | `u:<u>:<a>:access:<av>:<gv>` | String JSON | 5min，单快照建议 ≤256KiB | 授权服务从 PG 计算；先读当前 PG 版本再查键 |
| R06 | `u:<u>:client:settings:<ver>` | String JSON | 5min，≤64KiB | 本人设置服务；miss 按权限回查 PG |
| R07 | `u:<u>:client:l:<l>:lookup:<h>:<ver>` | String JSON | 10min，≤16KiB | 解释服务；当前 PG lookup revision 确认后读，miss 回 PG |
| R08 | `u:<u>:client:l:<l>:explanation:<rid>:<ver>` | String JSON | 30min，≤256KiB | 成功结果读取/发布后填充；大结果跳过 Redis |
| R09 | `u:<u>:client:l:<l>:audio-manifest:<rid>:<ver>` | String JSON | 30min，≤128KiB | 媒体服务；miss 查 PG/MinIO 元数据 |
| R10 | `global-word:ready:<h>:<ver>` | String JSON | 30min，≤32KiB | 目录服务；只含公共产物，不含贡献者信息 |
| R11 | `u:<u>:client:l:<l>:missing:<h>:<ver>` | String JSON | 3s，≤1KiB | resolve 服务；只抑制重复查找，不决定新生成 |
| R12 | `u:<u>:<a>:idem:<action>:<h>` | String JSON | min(5min, PG 幂等记录剩余) | 提交成功后写入；miss 必查 PG 幂等记录 |
| R13 | `u:<u>:client:job:<rid>:<generation>:<sequence>` | String JSON | 5min，≤8KiB | Outbox/快照读取；先取 PG 当前游标，miss 回 PG |
| R14 | `u:<u>:client:job-events:<rid>:<generation>` | Stream | 最后写入后 15min，最多 1000 条/Job | 已提交 Outbox 投影；缺口发 resync_required |
| R15 | `u:<u>:client:coalesce:<h>` | String JSON | 15s | 生成请求服务；仅削峰，PG slot/fence 才允许执行 |
| R16 | `global-word:coalesce:<h>` | String JSON | 15s | 公共目录生成入口；同 R15，不自动接管供应商调用 |
| R17 | `rate:<action>:<dimension>:<h>:<window>` | Hash | 固定窗口末尾 + 1s | 原子计数服务；阈值按入口策略，失败关闭受保护调用 |
| R18 | `u:<u>:<a>:connections:<kind>` | ZSET | 2min；每个成员租期 60s | WS/SSE 网关；心跳建议 20s，原子清理过期成员/限额 |

R01 的过期绝不单独决定会话有效；即使索引仍在也要检查 R02 和 PG。R04 任一存在过的刷新历史缺失时不能仍允许该会话刷新；R02 保存 `used_digest_count`，与 Hash 历史条目数量（不含两个公共字段）及版本核对失败则要求重新登录。历史摘要在会话内不独立提前淘汰；建议限制每会话最多 4096 次刷新，达到上限撤销该会话并要求重新登录，不静默删旧摘要。此上限为运行保护初值，不是用户登录次数产品限制。

不缓存任意书库组合筛选列表、不预建每日单词 Redis 表、不在 Redis 存音频字节或完整材料。书内已查列表按本人scope对source_result_bindings与当前learning_lookup_states的匹配投影有界分页；列表缓存只有未来测量证明必要才增加。

## 3. 认证与访问字段

### R01 Web opaque Cookie 查找

值是独立身份索引，不套私有业务信封：`schema_version: int=1`、`user_id: uuid`、`session_id: uuid`、`audience: client/admin`、`cookie_digest_version: string`、`absolute_expires_at_ms: int64`。Cookie 本身只在客户端 HttpOnly Cookie 和请求瞬时内存中；摘要查找后读取 PG 会话并比对用户、受众、transport、epoch、期限及 R02。

### R02 会话材料 Hash

| 字段 | 类型 / 空值 | 来源与规则 |
| --- | --- | --- |
| `user_id`, `session_id`, `audience` | uuid/uuid/enum，必需 | 与键、PG 会话完全一致 |
| `transport` | enum，必需 | `web` / `native`，与 user_auth_sessions 相同；分别使用 Cookie / Bearer，禁止交叉使用 |
| `absolute_expires_at_ms`, `idle_expires_at_ms` | int64，必需 | 服务器时间；idle 不超过 absolute |
| `security_epoch`, `audience_epoch` | int64，必需 | 创建会话时捕获；每次受保护请求比对 PG |
| `cookie_digest` | HMAC string，仅 Web 必需 | 与 R01 键摘要对应；不保存 Cookie 原值 |
| `csrf_secret_ciphertext`, `csrf_key_version` | string，仅 Web 必需 | 加密会话 CSRF 材料；通过专用 GET 返回当前 CSRF 值，写请求与 Origin 一并校验 |
| `refresh_digest`, `digest_key_version` | HMAC/string，仅 native 必需 | 当前刷新凭据摘要及摘要密钥版本 |
| `session_generation` | int64 ≥1，仅 native 必需 | 刷新 CAS 代次；迟到响应不能覆盖新代次 |
| `used_digest_count` | int64 ≥0，仅 native 必需 | 与 R04 历史条目数/完整性相对照；初次登录允许 0 / R04 不存在 |
| `last_refresh_at_ms` | int64，可选 | 仅成功刷新更新；日志不输出该 Hash |

Web 正常请求用短脚本检查当前值、续 idle 并更新 R01/R02 TTL，不轮换 Cookie。重验/退出/换账号遵守原认证流程；PG 撤销成功即失效，Redis 删除由 Outbox 补偿。

原生刷新先验证 PG，再由原子操作核对摘要/代次、把旧摘要加入 R04、更新当前摘要/代次与计数，并写 R03。操作后签发/回放前再次确认 PG 有效状态；并发撤销仍由每次业务访问的 PG 检查阻止。PG 与 Redis 不宣称分布式原子提交。进程崩溃后无法安全判定轮换结果时重新登录，不能自动还原旧凭据。

### R03/R04 刷新重试与历史凭据

R03 字段：`schema_version`、`session_id`、`user_id`、`audience`、`request_id_digest`、`consumed_digest`、`issued_generation`、`response_ciphertext`、`encryption_key_version`、`expires_at_ms`。只有同 request_id、相同旧摘要、窗口内且 `issued_generation` 仍为 R02 最新代次才可回放。密文内容为完整刷新响应，短期解密后返回，不写 PG/队列/日志。使用专用用途的加密上下文绑定 session/request/generation。

R04 除 `schema_version/updated_at_ms` 两个公共字段外，每个 Hash field 为 `used_<带版本的旧凭据HMAC>`，值为受控 JSON：`consumed_at_ms: int64`、`consumed_generation: int64`、`issued_generation: int64`、`request_id_digest: string`、`receipt_ref: string`。receipt_ref 只保存 R03 的末段 request_h，由服务端按当前会话scope组装完整键。首次轮换原子追加本条目，不覆盖历史消费时间；窗口以该条目的 `consumed_at_ms + 10s` 判定，不能使用最近一次刷新时间。

只在命中**已认证的旧摘要**时判定重放；仅提供 sid 和随机错误凭据不能撤销他人会话。窗口内不同 request_id 返回既定409；同request且issued_generation仍为最新才尝试读取回执。回执已淘汰/损坏、或其代次已被后续轮换替换时失败关闭/返回既定代次冲突，不补造凭据、不错误地认作窗口外重放；确实超过该条目窗口的旧摘要才按契约推进 PG 撤销。Redis 会话或必要历史丢失则要求重新登录，不凭可疑参数推定已验证用户身份。

### R05 权限快照

私有信封的 payload：`user_authz_version: int64`、`global_policy_version: int64`、`evaluator_version: string`、`permission_catalog_version: string`、`effective_permissions: typed list(code,effect,data_scope)`、`menus: typed list(id,parent_id,route,sort_order)`、`capabilities: typed map`。限制条目数，角色继承与 deny 合并在服务端完成；不让前端或 Redis 单独执行最后管理员/可授予边界校验。

每次请求从 PG 核对账号、会话、login 资格和当前 av/gv；键/值/评估器版本全部相符才能使用。缓存命中不替代对象归属及业务状态检查。权限变更事务推进版本并写审计/Outbox，旧键可异步删或自然过期，新请求不能读旧键。

### R06 本人设置投影

payload 只含 `settings_revision`、`timezone`、`ui_locale`、`display_preferences`、`reading_preferences`、`speech_preferences`、`query_context_budget_tokens`、`model_bindings`（provider/model/capability/版本及 credential_id 引用）。这是user_extensions设置字段组及模型/声音子表的白名单读取投影；key的ver和信封source_revision都取settings_revision，资料/学习组变化不复用为设置版本，preferences由对应有限列组装，不额外增加一套PG列。不存密文 Key、可恢复 Key、头像字节、人口字段或能力探测原文。合表不扩大缓存载荷，资料/学习语言不顺带放进R06；三个组的事务分别发出对应失效事件。模型调用必须从 PG 获取当前凭据状态/版本，在当前调用的内存中解密；本缓存不能证明 Key 仍有效。

## 4. 学习结果、媒体与幂等字段

DESIGN22 R07查阅键纳入[ContextPlan实际语境](../contracts/query-context.md)，R08 provenance返回安全的context_summary及本人有权快照引用，R09配置摘要包含展开后的模型适配契约。R06设置投影按settings_revision更新查询预算；不存私有长篇上下文或TTS字节。R07～R11若用于不属于library的本人输入，模板中的`l:<l>`整体替换为固定`personal`分段；仍必须保留u/client，禁止空library或owner通配。持久模型下线不删除既有R08/R09，命中始终另验来源。

| ID | payload 字段与类型 | 读取与失效规则 |
| --- | --- | --- |
| R07 | `lookup_id: uuid`, `lookup_revision/lookup_generation: int64`, `effective_result_id: uuid?`, `active_run_id: uuid?`, `strict_key_digest: string?`, `storage_state: enum` | 查阅键不含默认模型/Key；必须先核对 PG 当前 lookup revision，旧填充只写旧版本键；跨配置指针以 PG 为准 |
| R08 | `explanation_id: uuid`, `artifact_version: int`, `output_schema_version: string`, `task_kind: enum`, `output: typed object`, `provenance: typed object`, `generated_at: UTC string` | 只缓存完整成功产物；原文依赖、来源权限与考试禁用状态仍需实时验证；卡片由其独立业务输出 schema 校验 |
| R09 | `playback_manifest_id: uuid`, `manifest_version: int64`, `segments: list(audio_asset_id,audio_segment_id,ordinal,codec,media_type,content_digest,size_bytes,duration_ms,source_spans)`, `config_digest: string`, `storage_state: enum` | rid为playback_manifests.id；按manifest关系和音频段组装。不含对象凭据、签名 URL、音频字节或试卷隐藏脚本文本；试卷有限次数媒体必须走场次 PlayAttempt，不能直接签发普通下载 |
| R10 | `word_entry_id: uuid`, `pronunciation_variant: string`, `profile_id/profile_version_id: uuid`, `profile_revision: int64`, `global_audio_id: uuid`, `generation: int64`, `media_type/codec/content_digest: string`, `size_bytes/duration_ms: int64`, `availability: enum` | source_revision为global_word_lookup_states.revision，读音随受控word_entry保存，不虚构单独的读音ID表；鉴权本人收藏/版本/读音/profile 后查当前指针；不含生产者、Job、Key、用量、私人错误或首次生成用户时间 |
| R11 | `lookup_revision: int64`, `reason: not_ready`, `checked_at_ms: int64` | 不缓存权限拒绝，不把未知、broken、网络错误混为“未生成”；生成受理必查 PG，不因负缓存省略结果检查 |
| R12 | `idempotency_record_id: uuid`, `request_digest: string`, `action: string`, `status: enum`, `result_kind: enum`, `result_id: uuid`, `result_revision: int64`, `expires_at_ms: int64` | 同 key 不同请求摘要冲突；响应重新授权读取；不得放密码修改响应、凭据、签名地址或跨账号结果 |

结果提交与 PG 绑定在同一业务事务完成，事务后的 Outbox 失效只是加速。可变指针均使用 PG 版本寻址，避免“删缓存后旧查询迟到回填”恢复旧值。不可变结果可长期保持相同版本键，但每次仍检查父对象 tombstone、来源权限和当前场次规则；cached payload 不是授权凭据。

## 5. 任务、通知与协调字段

R13 payload 与[任务进度事件](../contracts/job-progress.md)同源：`job_id`、`generation`、`sequence`、`type`、`occurred_at`、`status`、`stage`、`progress_percent: 0..100|null`、`material_id?`、`published_revision_id?`、`availability?`、`error_code?`。不保存业务正文。先读取 PG 当前 generation/sequence 再按其版本取副本，不能用 Redis 的“最新”推断任务已完成。

R14 每条 Stream 字段为 `schema_version`、`event_id`、`generation`、`sequence`、`envelope_json`。Stream ID 仅作 Redis 传输游标，客户端的事实游标仍为 PG generation/sequence。重复 event_id/sequence 消费幂等；裁剪、淘汰、重连乱序或缺号时重新授权并查 PG 快照。采用精确最大长度或读取侧硬上限，不把近似裁剪误称严格容量。

Pub/Sub 频道使用同样 namespace：`N:v1:notify:u:<u>:<a>`（会话/访问快照失效或站内任务提示唤醒），以及 `N:v1:notify:global-policy`（全局策略版本变化）。消息仅含 `schema_version,event_id,event_type,resource_id?,revision,occurred_at`，禁止私有正文。Job 唤醒由 R14 或同 scope 的受控通知转发。接收服务在每次向 WS/SSE 发送前重新检查权限；订阅频道名不赋予权限。Pub/Sub 丢失不影响撤权、任务事实或重连恢复；本人站内任务提示与已读时间保存于[学习分册](database-learning.md)的 user_notifications，不以 Pub/Sub 代替持久记录，不扩大为邮件/系统推送。

R15/R16 值为 `schema_version,holder_token,slot_id,fence,expires_at_ms`，holder_token 为服务端短随机值。`SET NX PX` 仅合并入口流量，释放/续期须比较 holder_token；获得/失去 Redis 键不决定 PG 占用是否释放。任何执行与发布必须通过持久 slot 的严格键、租约、fence、当前 lookup generation 和选用 run 检查。unknown 的供应商调用不能因 15 秒到期自动重试。

R17 Hash：`count: int64 >=0`、`window_start_ms: int64`、`window_end_ms: int64`、`policy_revision: int64`。action/维度取白名单，邮箱/IP 先规范化 HMAC；用户/匿名入口分别计数，不记录原 IP/邮箱。首建计数与过期设置为一个原子步骤，窗口结束不靠清理事件触发。登录/注册/挑战、供应商调用准入失败关闭；普通遥测接收限流故障可以丢弃该批并记录本地安全诊断，不阻塞已完成业务。Redis 重启可丢失短期限流计数，需网关/进程受限入口保护；调用总预算、容量预留和在途作业仍以 PG 为准，不能用 Redis 计数证明未超过持久技术额度。

R18 member 为随机 `connection_id`，score 为 `lease_expires_at_ms`；网关本地保存订阅列表与最后游标，不把 Token 写入 ZSET。原子清理到期项、检查已配置并发上限、登记成员；单连接 Job 数沿进度契约。连接索引只是运行保护，丢失不授予额外权限，连接心跳和每次事件仍验证 PG/R02。

## 6. 原子性、容量与故障

- Hash 写字段不会自动刷新键 TTL，应在同一短原子操作显式更新到期；覆盖 String 时明确携带新 TTL，禁止偶然变成永久键。[Redis EXPIRE 官方说明](https://redis.io/docs/latest/commands/expire/)
- CAS 刷新、限流和连接登记可采用版本化 Lua；脚本原子执行期间会阻塞其他 Redis 活动，脚本必须有界。先完整验证参数/类型再写入，运行错误不当作事务回滚；`NOSCRIPT` 时从受管脚本重新载入，不把源码按用户数据动态拼接。[Redis 脚本说明](https://redis.io/docs/latest/develop/programmability/eval-intro/)
- 当前按实际单节点 Redis 设计，跨键脚本必须使用同一个实例。未来改 Cluster 需另做同槽命名/原子性迁移，不能宣称现有跨键刷新直接兼容 Cluster。
- 所有键写入均限制字节数/集合基数；过大结果直接回 PG/对象存储。缓存填充失败不改变已提交业务结果；身份材料写入不完整则登录/刷新失败关闭，不能返回一个不可验证的新会话。
- 采用 cache-aside，TTL 防长期占用，PG revision 防旧值生效；不用 keyspace 过期事件作为业务定时器。考试超时、播放消费、Job 重试/租约、GC 均由 PG 时间和持久状态驱动。
- 沿用独立 ACL/namespace，不修改 MyHome 共享实例的全局淘汰、持久化或内存配置。本期不执行 `FLUSHDB/FLUSHALL`；按业务白名单删除具体键。清本机缓存不会清服务器缓存，更不会删持久结果。
- Redis 键名、输入摘要、响应内容、刷新回执、可恢复 CSRF 材料都不进入日志。仅统计 key family、字节桶、命中/失败、延迟与受控错误；按[观测规则](../operations/observability.md)发送正常与异常事件。

## 7. 实施时的定点验证清单

本次为设计验证，以下均**未运行**：

| 切片 | 最低必要验证 |
| --- | --- |
| B1 认证 | Web 多标签续 idle；native 同 request 重试/不同 request 冲突/窗口外旧摘要；Redis 部分键丢失；PG 撤销但 DEL 失败；A/B 与受众隔离；随机 sid/摘要不能撤销他人 |
| B1 权限 | av/gv 改变后旧缓存/丢失通知/旧 JWT 均拒绝；Redis 不可用/PG 不可用失败关闭；授权评估版本变化不读旧 schema |
| B2 任务 | 重复/乱序事件、Stream 截断、缺口/重连回 PG；Redis 协调键过期后仍由 PG fence 阻止重复发布；unknown 不自动重调 |
| 阶段3 解释/TTS | Redis/本机全 miss 仍读持久成功结果且供应商计数不增加；旧填充不覆盖当前 lookup；来源删除/撤权不因缓存放行；global_word 不暴露贡献者 |
| 阶段4 考试 | 缓存命中仍执行题面裁剪；有限播放次数不依赖 Redis、不通过普通下载绕过；跨端接管和 edit_epoch 正确 |

具体 TTL、容量与阈值在对应切片的配置/压力样本验证后锁定，当前不声称性能、服务可用性或故障恢复已验收。
