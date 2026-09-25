# 模型用量统计契约

> 状态：2026-09-23 设计基线，尚未实现。本文只定义模型调用事实与统计口径，不定义订阅、余额、购买、价格或结算能力。

## 1. 范围与原则

Haruka P0 使用用户自行配置的供应商 API Key。产品不提供套餐、余额、信用点、充值、订单、发票、价格表、金额估算或结算，也不根据 Token 用量限制功能等级。供应商账号不可用、限流或达到其调用限额作为外部供应商错误处理；Haruka 不替供应商结算，也不把这类错误转换成应用内购买流程。

系统仍可配置请求次数、并发、超时、上下文 Token、输出 Token、文件大小、存储容量和任务重试上限。这些上限用于稳定性、资源保护与防止失控循环，不代表商品套餐或可购买额度。

模型用量统计遵循以下原则：

1. 只记录实际调用事实和供应商返回的用量，不维护金额、币种或单价。
2. 每次真实供应商调用按 attempt 独立记录；重试产生新的 attempt，不覆盖旧记录。
3. 供应商未返回某项用量时保存 `null` 和明确状态，不能用 `0` 冒充已知零消耗。
4. 数据库记录是统计权威来源；结构化日志用于检索和观测，不能代替权威记录。
5. 用量记录不得包含 API Key、原始 Prompt、原始回复、工具正文、试卷内容或用户材料正文。

## 2. 统计对象

每次 `ExternalCallAttempt` 最多对应一份不可变语义的 `ModelCallUsage`。物理上用量字段直接存external_call_attempts行，ModelCallUsage是DTO/值对象，不另建一对一表。允许在供应商响应到达后幂等补全同一行，但不能把多个attempt合并成一条。下表为逻辑字段，物理映射见[调用字典](../architecture/database-learning.md#74-调用用量字段位于-external_call_attempts)：

| 字段 | 含义与约束 |
| --- | --- |
| id | 逻辑用量标识与attempt.id相同，不另分配UUID |
| owner_user_id | 调用及用量所属用户；从认证/任务上下文写入，不接受客户端或模型提供 |
| operation_id / request_id | 端到端关联标识，不作为 Loki 高基数标签 |
| external_call_attempt_id | 逻辑字段映射本行id，PK保证每attempt一份；所有真实调用（包括Key测试与TTS）必须先建立attempt，不复制同值关联列 |
| job_id / ai_run_id | 可空的业务关联；按作用域服务校验，不能代替attempt唯一性 |
| provider / model_id / model_revision | 实际供应商、模型及可得的版本信息 |
| capability | `text`、`vision`、`tts` 或后续登记的明确能力 |
| operation_kind | 解释、OCR、习题生成、评分、TTS 等受控枚举 |
| call_status | 映射attempt.status，调用中started，结束后succeeded/failed或unknown；与业务结果状态分开 |
| usage_status | `complete`、`partial` 或 `unavailable` |
| input_tokens | 供应商报告的输入 Token；未知为 `null` |
| output_tokens | 供应商报告的输出 Token；未知为 `null` |
| total_tokens | 供应商报告值优先；缺失时仅在口径明确时由已知分项计算 |
| cache_read_tokens | 供应商 Prompt/上下文缓存读取 Token；未知为 `null` |
| cache_write_tokens | 供应商 Prompt/上下文缓存写入 Token；未知为 `null` |
| reasoning_tokens | 供应商单独报告的推理 Token；未知为 `null` |
| input_audio_tokens / output_audio_tokens | 供应商单独报告的音频 Token；未知为 `null` |
| input_images | 供应商报告或应用可确定的输入图片数量；未知为 `null` |
| input_characters / output_audio_seconds | TTS 等供应商采用字符或音频时长口径时记录；未知为 `null` |
| provider_usage_schema | 供应商用量响应的适配器版本，便于解释历史字段 |
| safe_usage_details | 仅允许白名单数字、布尔值和枚举；禁止保存任意供应商响应正文 |
| created_at / updated_at | UTC 带时区，使用公共 `TimestampMixin`；补全时显式更新 `updated_at` |

所有计数字段为非负整数或 `null`，时长为非负定点数或 `null`。适配器应校验明显矛盾的负数、溢出和非法类型。供应商的 `total_tokens` 与分项不一致时保留供应商原值并记录规范化告警，不能擅自改写供应商事实。

## 3. 缓存口径

“应用结果缓存”和“供应商 Prompt 缓存”必须分开：

| 情况 | 是否创建供应商 attempt | Token 记录 |
| --- | --- | --- |
| 命中 Haruka 已保存的解释、句子、OCR、习题结果或音频 | 否 | 不创建新的 `ModelCallUsage`；本次读取的模型 Token 为零调用，不伪造一条零 Token 模型记录 |
| 发起模型调用且供应商报告 Prompt 缓存读取 | 是 | 写入 `cache_read_tokens`，同时按供应商口径记录 input/output/total |
| 发起模型调用且供应商报告 Prompt 缓存写入 | 是 | 写入 `cache_write_tokens`，同时保留其他分项 |
| 供应商不提供缓存分项 | 是 | 两个缓存字段为 `null`，`usage_status` 按其他已知字段判定 |

应用缓存命中可单独记录业务事件 `application_cache_hit`，但它不是模型用量，不能混入 Token 聚合。不同供应商对缓存 Token 是否包含在 input/total 中定义不同，适配器按 `provider_usage_schema` 保存其口径，统计层不得再次相加造成重复计算。

## 4. 写入、重试与聚合

1. 发起外部请求前先持久化 `ExternalCallAttempt`；得到供应商响应后，按attempt.id和owner幂等补全本行用量；重复回调写已报告绝对值，不累加，迟到NULL不清已有可信值，变化同事务推进aggregation_revision/updated_at及Outbox。
2. 网络断开、进程崩溃或供应商结果不明时，`call_status=unknown`。没有可信用量就写 `usage_status=unavailable`，不能推算为零。
3. 有界重试产生新的 attempt。作业、运行和用户维度的统计从 attempt 聚合，不能同时累加 attempt 与 AiRun 汇总而重复计算。
4. AiRun/Job 可保存派生汇总和统计版本用于查询加速；源记录变化后按版本重算，源 attempt 始终是权威事实。
5. 迟到响应只能补全它所属的 attempt，不能覆盖后续重试、当前业务结果或其他模型版本的统计。
6. 供应商只返回部分字段时保存现有字段并标记 `partial`；供应商完全不返回用量时标记 `unavailable`。

## 5. 查询与展示

用户可以在设置中的“模型用量”查看本人数据，至少支持按时间范围、供应商、模型、能力和操作类型分组，并展示调用次数、成功/失败/未知次数及各 Token 分项。该投影沿用 `client.credential.read`，只返回当前用户的聚合和其有权读取的运行明细，不返回 Key、Prompt、回复或其他用户标识。

聚合直接从 `ExternalCallAttempt` 的全部匹配行读取同一行用量字段，不需要LEFT JOIN，也不能以usage_status/非空用量筛掉真实调用。started计入调用总数并单列进行中数量；成功/失败/unknown分别计数。每个数值指标返回同一结构：`known_sum`、`known_attempt_count`、`unknown_attempt_count`和`completeness=complete/partial/unavailable`。没有任何已知值时`known_sum=null`；已知值确实为零时才返回0。混合组例如一次`input_tokens=100`、另一次未知，应展示“已知100，另1次未知”，不能只展示100或把未知补零。调用总数、进行中和成功/失败/unknown次数始终从attempt状态统计。

迟到用量补全后，聚合按源attempt更新时间或单调`aggregation_revision`失效并重算；缓存的时间桶不能继续返回旧的unknown计数。分页明细与聚合使用同一截止时间/快照，避免用户翻页时把迟到补全重复计入两个时间桶。

管理后台可在 `admin.dashboard.view` 下查看实例级聚合，用于容量和异常分析；默认只展示供应商、模型、能力、时间桶、状态与计数，不提供用户私有内容或个人 Key。若将来需要按用户排障明细，必须新增独立权限与审计契约，不能借仪表盘权限旁路。

TTS 或视觉供应商可能不使用文本 Token 口径。界面只展示供应商实际返回或应用可确定的指标；字符数、图片数、音频 Token 和音频秒数保持独立列，不能换算成金额，也不能假装成文本 Token。

## 6. 日志与埋点

后端与 Worker 可以发出规范化事件，字段包含 `provider`、`model_id`、`capability`、`operation_kind`、`call_status`、`usage_status` 及已知用量分项。`operation_id`、`job_id`、`ai_run_id` 和用户引用只作为结构化元数据，不作为 Loki 索引标签；接收端绑定身份并执行脱敏。

前端只上报页面展示、筛选和加载结果，不自行计算或回传权威 Token。日志采集失败不能回滚业务用量记录；数据库写入失败则将该 attempt 标记为待补全并告警，不能只靠日志重建事实。

## 7. 验收

- **USAGE-01**：同一次供应商 attempt 重复投递只产生一条用量记录；重试 attempt 分开统计且聚合不重复。
- **USAGE-02**：input、output、cache read、cache write、reasoning 及可选音频/图片/字符指标按供应商返回保存；未知为 `null`，不冒充零。
- **USAGE-03**：Haruka 应用缓存命中不创建模型调用记录；供应商 Prompt 缓存命中仍记录真实 attempt 与缓存 Token。
- **USAGE-04**：迟到、失败和 unknown 响应不会覆盖新运行或误报成功，用量状态与业务结果状态保持独立。
- **USAGE-05**：用户只能读取本人聚合和获准明细；管理仪表盘只返回获准聚合，不泄露 Key、Prompt、回复或私有材料。
- **USAGE-06**：结构化日志可按模型/能力/状态检索，但数据库 attempt 记录是统计权威，日志丢失不改变聚合。
- **USAGE-07**：产品没有订阅、余额、信用点、购买、金额、币种、价格表或结算入口；技术上限不显示为商品套餐。
- **USAGE-08**：供应商账号或调用限额错误进入外部错误映射和重试策略，不进入 Haruka 购买流程，也不借用其他用户的 Key。
- **USAGE-09**：混合已知/未知用量的聚合从全部attempt计数，每个指标返回已知和未知attempt数；迟到补全后按版本重算，不以SUM或INNER JOIN隐藏未知调用。
