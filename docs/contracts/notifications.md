# 本人站内消息契约

状态：M1持久消息已实现，必要局部验证、正式Web/Android实操及独立复核通过。覆盖站内消息列表、未读数、打开已读、全部已读和资源跳转。它与[任务进度](job-progress.md)不同，也不是注册邮件、后台系统推送或学习提醒订阅。

## 1. 来源、归属与内容

仅以已提交的本人任务事件创建完成/失败/待校对等白名单消息；沿用[数据设计](../architecture/database-learning.md#77-user_notifications--本人站内任务提示)的user_notifications及Inbox幂等事务，Redis丢失不丢消息/已读。job/资源归属与版本在事务内验证，Worker迟到、重复事件不能创建重复消息或复活来源。

当期白名单为 `material.import.completed`、`material.import.failed`、`material.import.needs_review`。通知消费者使用独立固定Inbox，校验持久Outbox及其规范化负载，消息、库提交序列和Inbox同事务提交后才确认投递；既有模型消费者的ACK不代表消息已入库。恢复按受控批次补消费pending或published事件，暂时退出或停用账号不抹掉已提交任务的安全回执；已删除或旧代次事件只封存消费，不创建新消息。后续业务事件随其切片扩展白名单。

消息仅包含类型、message_code、安全参数、任务/资源引用及时间/已读状态；不保存或返回原文、答案、听力稿、Key、Prompt或任意HTML。资源标题只有当前来源可读时才能补充；失权、已删除或不可见状态只显示通用“资源不可用”，不可借通知读取旧内容。

## 2. API与权限

路径均在/api/v1下，JSON使用[统一返回](api-responses.md)，接口与权限在[API](api.md)及[权限目录](permissions.md)中央登记。

| 操作 | 行为 |
| --- | --- |
| GET notifications | 本人范围、按created_at/id稳定游标分页，可筛未读；返回条目与当前本人未读数、列表快照上界。resource_available及跳转提示不是授权凭据 |
| POST notifications/{id}/read | 提交空JSON对象 `{}`，幂等标记本人单条已读；read_at首次成功后保持，updated_at仅实际改变时更新；外来/不存在ID一致拒绝 |
| POST notifications/read-all | 提交服务端签发并绑定当前账号/受众的列表快照上界，仅将快照时已经提交可见的消息集合标已读；事务期间新消息仍未读，不能提交任意user_id或全实例范围 |

读取需client.notification.read，标记需read+client.notification.update；不隐含授予job.read或来源read。消息摘要允许在来源已失权后显示通用提示，但跳转必须重新校验真实资源动作、归属、版本及业务状态；任务详情另需job.read。管理员无本人消息内容的全局读取旁路。

快照成员须按当时已提交可见集合或受控提交序列冻结，不能仅使用(created_at,id)时间上界；长事务可能先取得旧created_at、在查询后才提交，新到消息不得被该旧快照标读。

当前列表参数为 `limit`（1～100，默认50）、`cursor`和 `unread_only`。具体metadata返回 `next_cursor`、`has_more`、当前总 `unread_count`、`snapshot_token`及 `snapshot_expires_at`。HMAC令牌绑定实例、本人、库、client受众、用途及已提交序列上界，生命周期15分钟；游标另绑定筛选及created_at/id锚点，翻页保留首个快照及期限。全部已读请求只含 `snapshot_token`，响应为 `changed_count`及当前 `unread_count`；不确定结果重试同一令牌，不自动换新快照扩大标读范围。令牌篡改、跨账号/实例/用途/筛选返回INPUT_INVALID，过期返回RESOURCE_EXPIRED。

安全条目仅返回已登记的message_code、空safe_parameters及受控引用。`resource_version`对应源版本号，独立于材料标题等元数据的CAS `revision`；材料metadata以可空 `source_revision_number`提供对应号，旧材料未知时不伪造。跳转时重读确切材料metadata并验证该源版本，不重拉整个材料库；当期源文件已受理也允许进入同一材料详情，但不能因此进入空白阅读器或把试卷标ready。仅有notification.read的用户可在另有来源权限时跳转，不调用标读接口；打开即已读行为仅向同时有update权限的用户提供。

“打开即已读”先提交标记再展示其状态，失败明确可重试，不提前把服务端事实改成成功。全部已读提交期间按快照执行；重试/多端重复幂等，刷新以持久事实重算未读数。通知新到信号只使客户端按权重取，不推送未经裁剪的私有参数。退出/换账号关闭旧订阅，迟到响应按AccountScope代次丢弃。

## 3. 验收

| ID | 必须证明 |
| --- | --- |
| NTF-01 | API/Worker只从已提交白名单事件生成，重复事件/进程重启只有一条；Redis丢失后列表及已读仍在 |
| NTF-02 | A/B交换消息ID、伪造user_id/快照、client/admin受众混用、read/update独立撤权均拒绝，不泄漏存在性 |
| NTF-03 | 分页/未读筛选稳定、单条和全部已读幂等、多端持久一致；并发新消息及旧时间戳晚提交消息不被旧快照误标，失败可恢复 |
| NTF-04 | 有权资源跳转；撤权/已删/旧版本/考试隐藏状态安全降级，原文/答案/稿/秘密不出现在通知或日志 |
| NTF-05 | Android系统通知栏通用摘要及“我的→消息”兜底、窄屏Web的“我的→消息”、电脑header入口；未读数、打开/全部已读、空态/失败/返回焦点、换账号/迟到响应；正常与失败事件进入统一观测 |

Android本地摘要通过当前账号首次缺数据及已确认通知变化从已授权通知仓储同步未读数；不因周期、普通页面返回或切回应用额外刷新业务数据，不含资源标题或正文。点击进入站内消息列表后再重验资源，账号切换/退出清除旧摘要，系统权限拒绝仍可经“我的→消息”访问。它不启动后台服务或接收远程推送；正式运行证据以当期实际联调为准。
