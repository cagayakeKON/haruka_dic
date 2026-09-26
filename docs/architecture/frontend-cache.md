# 前端缓存与更新机制

状态：2026-09-26，FCACHE1设计选型。用户要求完整的前端缓存更新机制；本文选定实现方案，尚未引入依赖、创建缓存库或执行平台验收。B0/B1保持既定范围，从B2a建立机制，后续功能随各自切片接入，不能等到发布阶段统一补缓存。

本篇维护客户端分层、存储、更新算法与验收；[客户端缓存校验契约](../contracts/client-cache.md)维护服务端协作协议；[学习结果缓存](learning-cache.md)仍唯一维护AI/TTS持久成果、查阅/生成键及共享词音。产品操作见[设置](../modules/settings.md)，身份与在线授权仍以[认证](authentication.md)、[RBAC](authorization.md)为准。

## 1. 技术选择

| 层 | 本期选型 | 职责及选择理由 |
| --- | --- | --- |
| 页面与内存状态 | 现有Flutter Riverpod 3，AsyncNotifier/Provider按AccountScope与资源键建立 | 订阅仓储状态、刷新状态和销毁；不把Provider存活当成数据新鲜或仍有权限 |
| 请求 | 现有Dio 5，由ApiClient统一认证、错误、取消 | CacheCoordinator在repository层决定是否读取/校验副本；不安装通用HTTP缓存拦截器决定私有业务可见性 |
| 结构化本机副本 | Drift + SQLite，按账号/实例/受众分库 | 事务更新版本、条目、来源依赖、配额和删除状态；支持迁移与查询观察，适合跨条目一致性约束 |
| Windows/Android数据库 | Drift NativeDatabase，后台isolate，应用私有目录 | 同一进程由一个数据库owner串行协调；Windows同安装实例的独立进程用平台互斥量限制单写者，第二进程转交已运行实例 |
| Web数据库 | Drift WasmDatabase，明确检查运行时存储模式 | 仅启用已验证可安全多标签访问的持久模式；不能把不安全降级称为可离线缓存 |
| 音频字节 | 原生私有文件目录；Web独立IndexedDB Blob库，经package:web适配 | 音频与SQLite索引分开，避免大BLOB放大SQL迁移/写入；跨库原子性由发布日志与代次检查完成 |
| 多标签协调 | BroadcastChannel提示 + Web Locks临界区 + 持久代次栅栏 | 消息只加快收敛，锁和提交前版本复核处理清理/写入竞争；不广播正文、令牌或授权结果 |
| 更新 | 主动校验、提交后定向失效、前台周期读取；既有Job/SSE事件辅助 | 不增加通用数据同步服务或客户端变更日志；漏事件靠读取恢复，不需要依赖可靠推送才能正确 |

沿用仓库已有Riverpod/Dio，不改当前锁文件。Drift、sqlite3、drift_dev及构建工具在B2a选取与当时Flutter/Dart兼容的稳定组合，精确锁定；Web worker/wasm同一release并记摘要。选型已定，补丁版本与平台证据属于实现门禁，不留到后续重新选数据库。Riverpod实验性离线持久化和自动mutation重试不作为本期基础；业务写入与模型调用必须由显式用例控制。

Drift官方支持NativeDatabase和WasmDatabase共用API，提供事务与迁移；本项目因此选用它维护关系索引和原子状态。[平台说明](https://drift.simonbinder.eu/platforms/)、[事务](https://drift.simonbinder.eu/dart_api/transactions/)、[迁移](https://drift.simonbinder.eu/migrations/)。Riverpod的生命周期取消与重试可配置；本项目将重试统一收口到repository，避免框架与网络层叠加重试。[取消请求](https://riverpod.dev/docs/how_to/cancel)、[自动重试](https://riverpod.dev/docs/concepts2/retry)。

Web启动检查chosenImplementation：opfsShared、opfsLocks、sharedIndexedDb通过目标浏览器验证后可启用；unsafeIndexedDb一律不用于共享持久库，inMemory只提供本次运行内存。Web音频Blob能力或Web Locks不可用时禁用音频持久下载；若缺少跨标签清理/写入所需的安全协调能力，则整个私有持久缓存降为内存，不冒险开放单标签后让第二标签破坏数据。显示“当前浏览器仅在线使用，本机下载不可用”，在线功能照常。[Drift Web能力说明](https://drift.simonbinder.eu/platforms/web/)

部署优先验证COOP: same-origin和COEP: require-corp；若破坏合法附件/媒体路径，修复同源代理/CORP后再启用，或使用通过验收的sharedIndexedDb。不能为了缓存使登录、媒体或下载失效。SQLite wasm正确MIME、worker CSP与离线静态资源版本一并验收。Web存储容量、持久化请求被拒或浏览器回收都属于可丢副本；不承诺磁盘永久存在。[浏览器存储机制](https://web.dev/articles/storage-for-the-web)、[Web Locks](https://developer.mozilla.org/en-US/docs/Web/API/Web_Locks_API)

## 2. 分层与单一更新入口

~~~mermaid
flowchart TD
    UI[页面和Riverpod状态] --> R[领域Repository]
    R --> C[CacheCoordinator]
    C --> G[账号代次与当前授权检查]
    G --> M[内存视图]
    G --> D[Drift索引与文本副本]
    G --> A[ApiClient 校验及读取]
    D --> B[平台音频BlobStore]
    A --> S[服务端已提交数据]
    S --> C
    C --> UI
~~~

CacheCoordinator只管理通用生命周期、并发和存储；领域repository注册类型化CachePolicy、授权来源、依赖标签、版本比较器和失效规则。它不解析角色名、拼SQL业务条件或推断考试何时能公开答案。未注册资源默认networkOnly；每次增加功能同时登记策略与验收，不提供任意URL缓存接口。

计划职责落在core/cache、core/platform和各feature的data/application；目录仅在对应实现切片创建。统一入口为read、refresh、applyCommittedMutation、invalidate、download、clearScope、closeScope。页面不能直接写Drift、删音频文件或invalidate整个Provider树；布局切换复用同一repository订阅，不增加请求或生成任务。

返回给UI的CacheView至少区分data、source（network/memory/disk）、freshness（validated/refreshing/offline/stale/blocked）、serverSaved、本机ready、lastValidatedAt及error。旧数据刷新失败不伪装成最新；明确拒绝立即移除可见私有内容。模型结果只在服务端确认完整提交后才能标serverSaved，流式半成品只在本次run内存中预览。

## 3. 键、版本与本机记录

### 3.1 作用域与版本维度

| 维度 | 含义及用途 |
| --- | --- |
| scope | 经确认的规范化服务端点endpoint_key + 可信元信息instance_id + access返回的user_id + audience；不能从表单/任意响应正文user_id切换分区 |
| account_generation | 本次运行账号绑定代次；登录身份/session_ref变化、退出、切实例/受众递增，旧请求/Provider/播放器立即失效 |
| storage_epoch | 分区持久控制记录中的随机代次；清理、失权隔离、账号注销和破坏性重建更换，旧进程/标签不能重新发布 |
| resource_version | 领域修订、删除代次、当前有效结果指针；由服务端提交决定，不用updated_at或客户端时间排序 |
| representation | 投影种类/协议版本、来源绑定、可见字段、材料类型与语言；考试题面/复盘与普通题不可共用缓存条目 |
| artifact_version | 不可变文本/解释/音频/NLP各自版本；NLP变化不改原文版本，默认模型/Key变化不让旧成品自动失效或重生成 |
| invalidation_epoch | 当前资源/依赖标签失效计数；内存视图本地维护，涉及持久条目的计数/发布代次也在Drift事务维护，同账号旧GET不得覆盖新结果 |

endpoint_key从用户确认且完成无凭据探测的HTTPS API base URL规范化得到，包含scheme、host、有效port及部署base path，按设置规范拒绝userinfo/query/fragment；固定同源Web同样包含部署路径。不能仅因instance_id相同合并两个地址，恢复/测试副本保留相同UUID也必须重新登录并独立分区。数据库/Blob、锁/广播摘要及本机许可绑定均派生完整scope，服务端grant与接收它的可信endpoint_key一同保存；网络响应不能指挥切换地址。

entry_key是上述scope、注册资源种类、稳定ID、精确版本与投影的规范编码摘要。query_key另含全部筛选、排序、分页cursor/page size、目标/解释语言、时区和API投影版本；不含布局、显示字号和播放倍速。不同过滤条件不能共用页结果。摘要不是脱敏手段，不上传原始键或其可穷举摘要。

会话重验更换session_ref后先关闭旧租期，在线重新验证相同账号的副本，不能把旧会话许可直接移给新会话。同账号普通Token轮换由AuthController处理，不无故清空全部内容；是否可保留副本由当前会话与权限校验决定。分区初始化只依赖me/access最小身份，缺profile.read/settings.read不能阻断登录或已获权的其他功能；未授权配置页不轮询相应端点。

### 3.2 Drift逻辑记录

以下是客户端逻辑模型，不是新增服务端业务表或已生成SQL；本机不使用物理外键/级联。均含created_at/updated_at，作用域隐含于库名且在记录复核，事务维护引用完整性。

| 记录 | 必需信息 | 更新边界 |
| --- | --- | --- |
| cache_control | storage_epoch、schema_version、writer状态、clear状态、两类容量 | 每次发布事务首先检查，控制记录保留在清理后的空库中 |
| cache_entries | entry_key、注册kind/ref、版本/投影、publication_epoch、payload及大小、verified_at、last_access、ready状态 | 只接收允许持久化的完整业务DTO，成功信封/request_id/错误正文不保存 |
| cache_dependencies | entry_key到合法source/binding/action/projection依赖及invalidation_epoch | 同entry事务写入；去重资产可有多个合法绑定，每个入口独立验证 |
| offline_grants | session_ref、安全/权限版本、具体来源/动作/投影/内容版本、服务器时间锚与expires_at | 仅接受当前在线授权响应，最短期限控制；不作为在线请求凭证 |
| local_assets | asset/version/实际格式、hash、expected/actual bytes、staging/ready/deleting/broken、文件/Blob引用 | 完整校验并通过代次复核后才ready，播放仅用ready |
| local_operations | 下载/删除操作ID、创建代次、owner、目标、reserved_bytes、actual_bytes、安全临时引用、重试次数 | 共享事务内预留/释放容量和下载槽，支持崩溃清扫和失败清理；没有业务通用待上传队列 |

可变列表、任务/用量和配置表单只保留当前进程内存，不存进持久cache_entries；本期持久化白名单见下一节。配额设置属于设备本地偏好，清理内容保留它，注销账号清除；遥测补传和考试短时草稿各自有独立边界，不混入可重建学习缓存表。

## 4. 数据策略与默认更新频率

在线的新页面打开、来源切换、下一段播放/下载、从后台恢复和用户显式刷新，都必须有本次动作的服务端授权校验。下表周期用于已打开页面的变化发现，不能用TTL免除新动作授权；离线仅按白名单租期读取。P0不采用对未经本次授权的私有正文先展示再校验的通用SWR。

| 数据 | 本机存储与读取策略 | 更新触发/周期（初值） |
| --- | --- | --- |
| 身份/access、凭据状态、权限菜单 | 内存、networkOnly；秘密由既定认证存储处理 | 启动/身份提示/重连/前台恢复立即重验；活跃前台至多30秒再次检查 |
| 资料、学习档案、服务器偏好、能力目录 | 内存、networkFirst；草稿独立 | 进入页、成功写入、跨标签提示；可见只读数据30秒校验，编辑表单不覆盖draft |
| 材料/收藏/词本/错题/消息等可变列表及统计 | 内存、networkFirst，分页为一个query generation | 进入/筛选/提交/提示立即刷新；可见列表30秒刷新第一页并使旧分页失效 |
| 小说/教材有权正文、ruby和基础NLP | Drift、先在线validate后复用同版本；离线可读已有完整段 | 活跃章/单元30秒校验来源和当前投影；切章/分段另验；NLP增量发布替换匹配分析版本 |
| 已完整提交的词句解释/卡片学习文字 | Drift，同来源/动作/投影validate后复用；有效租期可离线读 | 有效指针、来源/结果/NLP版本变更刷新；重新生成须显式动作 |
| 允许离线的普通音频/manifest | Drift索引 + BlobStore；授权后直接复用已校验版本 | 每次开始/继续及逐段播放检查当前模式许可；签名失效只重签/重传 |
| Job/run/章节准备实时状态 | 内存、有权WebSocket/SSE + REST查询结果 | 终态事件立即重新取已提交结果；断线前台2/5/10/30秒退避查询，不重发创建命令 |
| 学习证据/成绩/诊断/用量 | 内存、networkFirst；已公开诊断/复盘中的许可学习文字可独立按上行入库 | 写入/评分发布提示后刷新；可见时30秒，当前effective/generation以服务端为准 |
| 考试场次、答卷、限次听力、隐藏稿/答案 | 不进通用持久缓存；在线专用repository，短时草稿沿考试契约 | 编辑revision/锁卷/计时/PlayAttempt以服务端实时请求为准；不用30秒周期代替场次协议 |
| 头像、查询附件与上传原件 | 头像按专用private/no-store规则：Web内存、原生受控版本副本；附件不入离线学习缓存 | 每次实际读取鉴权；头像替换/删除清专用副本；不经过通用缓存validate |
| 管理端 | 内存、networkOnly，不签离线租期 | 每次操作/进入页面重验；前台安全轮询，隐藏页停止业务轮询 |

30秒为普通数据最大调度间隔初值，网络延迟另计；前台恢复不能等待下一周期。安全access/当前来源校验正常在最近成功后的20秒启动，随机提前0～2秒以留网络耗时余量；没有成功安全校验连续30秒时将私有UI置为待验证，只有符合第8节网络不可达条件才进入有租期的离线阅读。轮询仅覆盖可见列表、活动阅读窗口与播放器，不扫描全书/全缓存；最多50个引用一批，超出分批并先处理当前可见内容。已展示页面对远端普通变化在健康网络中按此周期收敛，不宣称跨设备瞬时一致。新服务请求始终当前鉴权；明确撤权一收到就停止展示/播放。

查询搜索默认300毫秒防抖；只读singleflight键包含query/entry身份、scope/account_generation/storage_epoch、依赖invalidation_epoch及读取目的，只有同代次同语义请求可合并。提交/删除/手动刷新先提升相应失效代次并摘除旧flight，再创建本代次读取，不能复用注定丢弃的旧GET；旧完成回调只可移除自己的flight标识。消费者离开递减引用，最后消费者释放时先同步摘除自己的flight并禁止新加入，再用CancelToken取消传输；即使取消尚未settle，新消费者也须创建新flight。读重试最多2次、500/1500毫秒抖动退避，429遵守Retry-After且不后台无上限重试；401交认证层至多一次恢复，403/业务校验/取消不重试。Provider自动重试关闭，由此策略统一处理；写入无自动重放，结果未知按领域幂等/对账契约恢复。

## 5. 读取、写入及失效算法

### 5.1 读取

1. 捕获scope、account_generation、storage_epoch、依赖invalidation_epoch及本次read_generation；查注册策略。身份不确定立即blocked，不先恢复私有页面。
2. 在线时，可变视图直接GET；可复用不可变内容调用[批量validate](../contracts/client-cache.md)，必须包含真实来源、投影和动作。same才复用，changed取服务器指定的新投影，unavailable清当前绑定并停止显示。未授权返回不能通过另一个asset_id找回旧内容。
3. 本机miss时先读服务端已有结果/resolve，再下载副本；无成品显示缺失/在途，不由缓存组件发起AI/TTS。离线时只读完整ready、版本相符且租期有效的条目。
4. 应用响应前重查所有代次、当前登录绑定及资源版本；已经失效的请求即使HTTP成功也丢弃。乱序v7不能覆盖v8；无法比较的opaque版本通过read_generation和重新校验处理，不按字符串大小比较。持久发布在锁内比较请求开始时捕获的entry publication_epoch/依赖代次，并事务递增；另一个标签已经发布或失效时CAS失败，丢弃并重验，不凭本标签“最新请求”覆盖共享库。
5. 文本、NLP及依赖在一次Drift事务中发布，文本容量也在同一事务按实际序列化字节准入/更新，多个标签不能各自读旧余量后插入；临时大块写入走同样持久预留。存储失败可在线展示当前合法响应并标“未下载”，不能回滚已提交服务端结果。UI从同一已接受状态更新，Drift watch负责本机变化，不负责网络更新。

### 5.2 写入

写操作保留draft，提交expected_revision/field mask及既有幂等键。成功响应是服务端提交证据：先提升受影响依赖的invalidation_epoch，事务更新服务端返回的完整投影，失效依赖列表/汇总，再通知活跃订阅刷新。不把按钮点击、事件推送或乐观计数当提交成功。

本期仅字体/主题/倍速等既有明确“未保存”预览可先显示；收藏、已读、掌握、交卷、评分、模型任务默认提交后确认。返回204或只返回ID时先标失效再GET，不在客户端猜造完整DTO。409保留draft并显示服务器新版本，用户重应用；超时/断线的写入结果未知先按operation/idempotency查询，不能回滚提示“未保存”后无条件重发。

### 5.3 领域失效表

| 已提交变化 | 必须失效/更新的依赖 |
| --- | --- |
| 材料新增/删除/重解析、阅读位置/书签 | 书库所有相关筛选页、详情、当前版本/目录/书签；删除立即停止该来源阅读/音频、移除相关离线绑定，独立合法收藏快照另验 |
| 收藏编辑/新增/删除、归本/删本、CSV导入 | 条目详情、收藏各筛选页、词本成员/计数、按时区每日加入历史、出题选源预览；删本不删共同条目状态 |
| 资料/学习档案/偏好保存 | 仅对应revision组；时区失效日期列表/统计，目标语失效默认筛选/选源，配置只影响之后生成；旧成品继续标实际配置 |
| 解释/NLP/音频发布或显式重生成 | 当前有效指针、已查索引、绑定投影、章节准备分项；不删除仍有引用的旧成品，不把server ready当local ready |
| 普通作答/评分/重评/纠正/删题 | 当前题/成绩effective、错题当前态、掌握/诊断依据、相关选源计数；旧run迟到不覆盖新代次 |
| 交卷成功/复盘发布 | 场次状态、题面可见性投影、成绩与开放的来源动作；清旧场次辅助状态，只取此时可见字段 |
| 消息单条/全部已读 | 未读计数和全部受影响分页；遵守NTF已提交可见集合，不能本地假设晚到新消息已读 |
| 权限/会话改变、来源不可用 | 立即封锁相关展示/播放/下载，失效许可与依赖；scope未知全封锁，已知来源拒绝仅清相应绑定 |

任何改变列表成员/排序/统计的写入使整个query generation过期；已加载第二页不能接到新第一页后面。取消旧分页请求，重新取得第一页和后续cursor；可恢复稳定item定位，但不能沿用旧cursor。分页追加始终同generation，去重只为渲染防护，不能掩盖遗漏；服务器拒绝过期cursor则重开查询。没有服务端快照分页契约时不宣称翻页是冻结全集，导出与生成选源继续用各自正式快照。

## 6. 跨设备、多标签与事件丢失

跨设备不共享本机缓存；每端通过服务端GET/validate校验当前版本。所有活跃可变查询按第4节刷新，因此新建/删除记录也会发现，不能只验证当前已知ID而漏掉新条目。无须新增服务端全局cache revision表、全量同步游标或每次写入广播所有用户。

本端提交后立即按依赖刷新；Web发布scope摘要、资源类别和“需要重验”提示，不携带内容或权限结论。接收端只把自身相关缓存标脏并重新读取。广播可能丢失/重复/乱序，前台恢复与周期校验兜底；本地事件计数不当服务端版本。身份变化使用既有AuthSync，先暂停私有操作并重新取当前Cookie身份，不相信广播自报user_id。所有私有请求还须遵守[expected session及响应绑定](../contracts/api-responses.md#51-b2起的私有请求会话绑定)，包括不落盘的列表/配置：丢全部广播后旧A页面携带Cookie B也会在业务执行前被服务器拒绝，不能只靠30秒轮询或storage_epoch补救。

每个Web标签保存独立AccountScope内存和epoch快照。共享库写入/清理/迁移使用按分区命名的Web Lock；在锁内、事务提交前读取持久storage_epoch，和请求创建时比较。后台页恢复后先取锁读控制记录、重验身份，不能先显示被浏览器恢复的旧私有Widget。Drift多标签共享仅解决库连接协作，不替代上述业务失效规则。原生多窗口统一走同一个owner。

有权Job/SSE仅提示本人的已提交阶段变化。流结束、重连或序号缺口都GET当前run/结果；传输中的partial内容不写完整缓存。后台/隐藏页暂停业务轮询与普通下载，恢复先校验；不增加后台常驻或移动后台播放承诺。P0每个可见标签各自轮询，批量/抖动降低同步峰值，不引入会成为正确性依赖的选主心跳。

## 7. 下载、配额、清理与崩溃恢复

文本100MB、音频500MB为本机默认初值，可独立调整；MB统一按10^6字节展示并在UI说明。容量包含ready、staging与待删对象实际占用，不能只统计索引中的成功文件；未知容量显示待统计，不填0。下载前在共享Drift事务中按manifest长度预留，整个分区最多2个普通音频下载槽，不能各标签各占2个；整章准备的供应商并发仍由后端独立控制。准入按ready实际量 + 待删实际量 + 各下载max(reserved_bytes, staging实际量)计算，已预留部分不重复累计；释放/发布同事务转移计数。未知长度按块提前追加预留，事务不成功就不继续接收，防止两个标签同时通过剩余容量检查。

下载流程：授权manifest → 受控临时文件/Blob → 流式长度与SHA-256校验 → 获取分区发布锁 → 复核全部代次/许可和配额 → 原子文件替换或Blob写入 → Drift事务登记ready → 释放预留。Web文件库与索引库不假装跨库事务：先记录local_operation，Blob以唯一操作ID存staging；发布索引成功才可被播放器读。崩溃后按日志处理孤儿、缺失Blob和未完成索引；不存在/损坏的ready降broken，回源重下载，不能重新合成。

文件路径/Blob key由应用构造，原始文件名/任意URL不参与目录拼接。DB、文件与账号目录不能越界；Web Blob库与Drift同scope/epoch分区。Range续传只在服务端支持且asset版本/摘要一致时继续，否则删临时副本重下。签名/短效媒体URL仅在内存传输，不放入永久索引或日志。

LRU按本机last_access淘汰可重建副本；正在显示/播放有短期pin，不能被普通淘汰删掉。原生由统一owner持引用，Web消费者持scope/asset共享Web Lock，淘汰只能非阻塞尝试该资源独占锁，失败就跳过；不能只依赖另一标签收不到的内存pin。显式清理先广播停止，取不到独占锁则报告待清理，不能强删仍被占用的对象。分区控制锁仅保护短事务，等待消费者/资源锁前先释放，避免清理和播放释放互相死锁。下载owner持操作锁，崩溃释放后其他窗口可取得该锁、复核epoch并清staging/释放预留，不靠过期心跳抢仍存活的下载。

容量降低到小于在用量时先提示实际不可立即释放量，停止新增下载，待消费者释放后清理；不偷偷越限继续写。配额不足/浏览器QuotaExceededError先有界淘汰一次，再失败则在线使用并明确未下载，禁止无限重试。Web回收导致索引与Blob不同步时分别校验、重建计数，不能显示假ready。

清理账号本机缓存：用户确认范围 → 立即封锁新下载/发布并更换storage_epoch → 通知其他窗口停止消费 → 取消旧下载并等待文件句柄释放 → 标记deleting → 删除索引/文件/Blob → 报告实际成功/失败数量。失败记录保留待清理，重启继续，UI不能全成功；服务器内容不变。清理完成后页面显示未下载，不自动由旧watch、旧轮询或重试重填；新的显式阅读/下载动作才重新允许相应内容持久化。关闭期间到达的旧GET可被丢弃，不用它“恢复”缓存。

退出/切实例/账号/受众先关闭旧AccountScope并清凭据/私有UI，再封锁旧存储代次并清私有文件、草稿、队列、专用头像及订阅。删除失败保留隔离清理记录，新账号也不能打开旧库。Web同一受众的Cookie身份变化影响所有该受众标签，client/admin清理独立；一次退出不宣称撤销另一个受众会话。

## 8. 离线与权限恢复

仅网络实际不可达可切换离线；connectivity类型或navigator.onLine只是提示。超时/5xx/429/证书错误、协议不兼容、身份不确定不自动视为离线授权依据：保留错误并暂停新私有读取；明确401/403及资源unavailable立即禁止降级。已处于离线模式但探测到网络恢复，先进入revalidating，完成当前会话/access和资源检查前不继续在线读旧许可。

离线使用当前账号已保存的正文、词句解释、许可普通音频；每个条目必须匹配来源/动作/投影/版本租期，expires_at取会话、动作、来源期限与部署上限的最小值，推荐最多24小时。租期不授权新查询、新生成、收藏编辑、评分、交卷或管理。已失权源的依赖立即清除；资产被另一合法收藏引用时只经该收藏自己的授权与快照访问，不能恢复原书全文。

时间锚绑定请求开始/响应接受的单调时刻m0/m1：接收时以server_time + (m1-m0)作为保守服务器当前时间上界，之后加同次运行单调增量；不从“响应收到时”重新算完整租期。仅接受当前scope/全部代次校验通过的响应，乱序旧请求不更新锚或许可；新锚不低于旧锚在同一单调时刻的推算值，时钟误差导致提前到期时要求在线重验，不能延长expires_at。租期内持续检查，系统墙钟回拨不能续租。休眠/重启后不能证明单调时钟覆盖停机期间或可信剩余时长则要求在线重验。声音连续播放跨段仍检查有效期，租期失效立即停播。租期是官方客户端显示约束，不宣称阻止设备所有者复制已获得文件。

## 9. 升级、降级与可观测性

Drift schema_version、业务projection_version、应用build和asset版本各自管理。普通迁移在唯一writer锁内事务执行并维护受支持升级路径；不兼容/损坏库先封锁旧代次，只重建可回源的缓存，不能误删认证安全存储、合法待处理考试草稿或遥测队列。新客户端未支持的业务投影拒绝反序列化；老标签发现schema版本不可读则关闭连接并要求更新，不尝试反向迁移。

Web应用壳只缓存无私有内容的静态资源，按build摘要更新；HTML/version入口可重验，hashed静态文件可长期缓存。构建输出无私有数据的版本清单，启动、恢复前台及前台每5分钟用no-cache读取清单，发现build变化通知更新。任何Service Worker/HTTP/CDN缓存均不得缓存认证API、解释、音频、头像或附件。应用自己的Drift/Blob持久化仅依明确业务白名单。新构建可用时提示安全刷新，考试/上传/未保存输入不强制重载；用户完成或明确放弃当前操作后再加载新壳。worker/wasm与build一起部署，不能新旧混用；若启用离线应用壳，Service Worker只按构建清单缓存静态白名单，不注册通用fetch兜底。

统一Telemetry记录cache.read.hit/miss、cache.validation、cache.invalidated、cache.stale_response.discarded、cache.download、cache.evicted/cleared、cache.storage.degraded及schema.migration的结果/原因/平台/字节区间/耗时。正常事件也采集；不记录正文、音频、raw key、签名URL、查询词、授权快照或秘密。监控校验延迟/失败率、请求合并率、磁盘失败、失效后旧响应丢弃和跨端收敛时间；应用命中不创建模型attempt。

## 10. 分期交付与验收

| 阶段 | 本次新增必交付内容 |
| --- | --- |
| B2a | 三端存储能力探测/锁/代次、全私有请求/响应会话栅栏、CacheCoordinator与注册策略、资料/设置提交后刷新、前台与多标签更新、清理/升级基础；validate框架仅注册已有允许资源，离线业务未交付不签虚假许可 |
| B2b/B2c | 权限/会话变化清理及管理onlineOnly；Job终态重新取结果、unknown不重发、模型配置变化不隐式调用 |
| M1～M4 | 材料/消息分页失效、删除代次、正文/ruby/NLP依赖、阅读离线租期；M4题面/隐藏稿投影隔离 |
| L1～L3 | 收藏/词本/CSV批量变化传播、完整解释/卡片文本副本与上下文版本，clear/miss回源不重调AI |
| L4/L5 | 音频BlobStore/两类配额/可见清理统计、下载原子ready、章节分项/逐段播放与准备事件；限次试卷音频排除 |
| P1～P4、E1/E2 | 可靠评分/错题/掌握/诊断依赖和新成品；考试版本/编辑代次/锁卷/可见性转换，不接通用离线写队列 |
| R1/R2 | 汇总所有已接入模块和Windows/Web/Android必需证据、部署静态壳/worker兼容；不能用R阶段代替各切片实现 |

以下FCACHE验收均待执行，原CACHE/LC/SET/FLT仍保留：

| ID | 必须证明的行为 | 首次/增量阶段 |
| --- | --- | --- |
| FCACHE-01 | 含服务地址的scope、请求/响应会话绑定及各代次阻止跨账号/受众/实例；同UUID不同地址隔离；双标签全丢广播后旧A请求不读取或修改B，取消失败也不串写 | B2a，各功能增量 |
| FCACHE-02 | 同代次同key并发只读合并；提交/刷新不复用旧flight；快速离开再重进不加入尚未settle的取消flight；Provider不额外重试；写超时/模型请求不自动重放 | B2a/B2c |
| FCACHE-03 | 本端提交后详情/全部相关列表/计数一致，204重新读取；409保留draft；旧分页不可拼新第一页 | B2a、M1/L1/L3 |
| FCACHE-04 | 双设备改/增/删在前台周期收敛；丢失全部推送/广播仍恢复，后台恢复先校验，身份提示不携秘密 | B2a、M/L |
| FCACHE-05 | 在线命中按入口实际权限校验，agent.read/collection.read合法读取不被额外ai.explain阻断；错误owner/投影/隐藏字段被拒，部分不可用不泄露存在性 | B2a框架、M/L/E |
| FCACHE-06 | 断网已有正文/解释/普通音频在最短租期内可读；拒绝/到期/回拨/不可信休眠失败关闭；高RTT或乱序时间锚不延长许可 | M2/L2/L4 |
| FCACHE-07 | 显式清理与在途GET/下载/另一个标签竞争，旧epoch不能回填；失败数真实，重启续清，服务器成果完整 | B2a框架、M2/L4 |
| FCACHE-08 | 截断/摘要错/磁盘满/QuotaExceeded/发布崩溃/Blob缺失不假ready；双标签预留不超总量/下载槽，跨标签pin不被删，owner崩溃回收预留 | M2文本、L4/L5音频 |
| FCACHE-09 | Web安全持久模式/隐私模式/无Locks/存储回收、原生文件锁/进程重建有实机证据；不安全模式仅内存 | B2a基础、L4媒体 |
| FCACHE-10 | 迁移/回滚旧壳/多标签新旧schema、wasm/worker部署不混版；考试与未提交表单不会被强制刷新丢失 | B2a基础、E1/R2 |
| FCACHE-11 | 原文/NLP/解释/音频/声音/Key独立版本；换配置、清理、签名过期及miss只读已存结果，供应商计数不增 | M/L及P/E新文字 |
| FCACHE-12 | 考试题面/复盘字段分区，限次音频与隐藏稿从未入持久通用缓存；交卷/重评迟到不覆盖新effective | M4/L5/E1/E2 |
| FCACHE-13 | material/collection/notebook/CSV/notifications/grade/settings全部失效表路径逐项覆盖，无收藏mastery手改或离线写入 | 各所属切片，R1汇总 |
| FCACHE-14 | 成功/失败/清理/淘汰正常日志可关联，秘密/正文/签名URL哨兵不泄漏，命中不伪造零Token调用 | B2a/B2c及所有新增消费者 |

验证方法：最低层用可控Future顺序/时钟测试同账号乱序与代次、真实Drift事务测试发布/迁移、真实API检查权限/版本，平台测试验证文件/浏览器边界。E2E经真实UI完成写入、清理、切账号并观察刷新，不能直接修改本机库制造业务成功；网络/磁盘/乱序故障可在测试传输/存储适配边界注入。大节点才运行当时全部已交付缓存矩阵，本次文档设计不声称这些测试通过。
