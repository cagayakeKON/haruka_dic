# 前端缓存完整代码审查与故障复现

日期：2026-09-27。范围：阶段1现有客户端缓存切片；本轮为代码审查和定点诊断，不代表正式离线业务验收。本轮未修改生产代码、未提交；此前修复与150项运行结果见[恢复修复记录](2026-09-27-cache-recovery-fixes.md)。

后续状态：用户确认只修现有缓存缺陷、正式业务另做。下文保留审查时的原始发现，已不代表当前未修列表；修复、独立复核及实际运行结果见[现有缓存缺陷修复](2026-09-27-cache-defect-fixes.md)。

主Agent审查协调器、Drift、许可模型、重试及独立Agent的结论；GPT-6-Sol只读审查认证/API接线、领域仓储和页面生命周期，另一独立Agent审查平台存储、音频、锁及恢复。诊断测试由主Agent串行运行。以下缺陷仍未修复，诊断断言通过表示复现了当前错误行为。

## 1. 本次输入的逐项结论

| 输入判断 | 核对结果 |
| --- | --- |
| 发布失败吞掉已取得的在线正文 | 成立。`clear_state=pending`且用户显式打开时返回`stale_response`；注入SQLite INSERT失败也直接使读取失败。不能将真实账号/存储/依赖冲突一概改成成功，需区分存储不可写和正文已失效。 |
| 正式流程没有离线入口，前台失败无法恢复租约阅读 | 成立，且属于文档已声明的未交付范围。业务无`enterOfflineForUnreachableNetwork`调用；前台恢复清内存许可与可信时间锚，access失败保持遮罩并最终关闭展示。不能把超时、5xx或429作为已证明断网，也不能在睡眠后未经可信时钟证明就延长租期。 |
| 查询卡失效会永久清掉无关离线许可 | 部分成立。未登记标签被编码成未知，接收端广泛撤销内存；但无关磁盘许可仍可在本次运行的可信时间锚下恢复，诊断已成功离线读取。普通查询卡发布也不自动发送该失效广播，现有七类提交标签均在白名单内。 |
| `Future.any`输掉竞争的取消分支产生未处理错误 | 不成立。Dart的`Future.any`给每个分支安装错误处理，完成后忽略其他分支的错误；zone诊断中取消晚于退避完成，未发生未处理异常。 |
| 空依赖行被head接受，与snapshot不一致 | 成立，但影响需收窄。snapshot拒绝正文和许可；publish还复核完整标签集合，后续在线发布能够修复。未复现永久无法发布或离线绕过。 |
| 元数据随会话增长、原生锁文件常驻 | 前者成立：128条限制只回收正文，tags/grants/read-generation等缺乏统一回收。锁文件常驻本身不能定为互斥错误；随意unlink会使持锁者与新打开者使用不同inode，需在无持有者边界安全治理。 |

## 2. 已用运行诊断确认的缺陷

### P1：撤销落盘失败后，离线恢复重新接受已撤销的内容

[CacheCoordinator](../../../frontend/lib/core/cache/cache_coordinator.dart)的`unavailable`分支先撤掉内存许可再删除磁盘正文；`same + revokeGrant`先删内存许可再更新磁盘许可。这些写入失败时没有留下资源级拒绝标记，也未使旧可信时间锚失效。随后转离线，1191行起的恢复逻辑重新接受磁盘旧许可。

两项诊断分别注入`cache_entries`删除失败、`offline_grants`删除失败：先收到权威不可用/撤销结果，下一次离线读取仍返回旧正文。涉及1260–1278、1295–1325及1196–1203行。修复应先封锁该资源的许可恢复，直到明确重新授权或撤销持久化成功；不能只处理已提交mutation的失败。

### P1：A账号的迟到授权失败封锁已经确认的B账号

[CacheCoordinator](../../../frontend/lib/core/cache/cache_coordinator.dart)的`_authorizedAttempt`（1528–1555行）在检查请求所捕获的身份/账号代次之前，直接对当前协调器调用`blockForAuthorizationFailure()`。取消不是迟到响应不会到达的保证。

诊断保留A请求，完成B的attach，再让A返回403；B仍是当前scope，但`accessReady`从true变为false。应只让当前作用域的授权失败改变当前作用域状态；旧响应仍丢弃。

### P1：音频流交给消费者后，撤权不停止后续字节交付

[CacheAudioManager](../../../frontend/lib/core/cache/cache_audio_manager.dart)的`read`（195–217行）仅在交出流前检查授权代次；[AudioBlobStore](../../../frontend/lib/core/cache/audio_blob_store.dart)的`withReadyStream`（208–217行）随后直接交出原始流，没有撤权/清理取消信号。

诊断读取前2字节后撤权并推进授权代次，消费者仍取得剩余2字节并成功返回。需要可取消的读取/播放生命周期，并在后续交付处复核；仅入口鉴权不足以实现“明确撤权立即停止播放”。当前尚无正式音频页面消费者，本结论针对已实现的基础能力，不声称生产播放器已发生泄漏。

### P2：存储拒绝使合法在线读取失败

[CacheDatabase](../../../frontend/lib/core/cache/cache_database.dart)的publish把清理pending与版本/代次冲突都表示为stale（616–617行）；[协调器](../../../frontend/lib/core/cache/cache_coordinator.dart)在1470–1473行删除内存并抛错。诊断在同一pending状态下证实：清理后后台读取成功、显式打开在成功fetch之后失败。

另一项诊断注入INSERT失败，网络已返回正文，读取仍抛SQLite错误。应区分“当前响应合法，但本地保存失败”和“响应本身已过期”；前者返回正文、`localReady=false`并记录降级，后者仍须拒绝。

### P2：音频删除失败后丢掉操作记录，实际字节不再计入配额

[CacheAudioManager](../../../frontend/lib/core/cache/cache_audio_manager.dart)下载finally（161–173行）不论stage清理成功与否，都调用`abandonAudioOperation`。stage中途失败时甚至还没有`StagedAudio`，也会删除预留记录。推广为ready后发布失败的回滚删除同样没有保留删除失败账目。

诊断在下载流中断且平台拒绝删文件时留下2字节，但操作表为空、audioBytes为0；全量清理报告0个pending，字节仍在。recover能发现孤儿，却未恢复其配额/待删记录。应在确认物理删除完成后释放账目，失败时保留可恢复的deleting记录和实际占用。

### P2：原生损坏索引在预检时绕过内存降级

[原生后端](../../../frontend/lib/core/cache/cache_backend_native.dart)21–27行的只读SQLite预检，在损坏库上抛`SqliteException`；[attach](../../../frontend/lib/core/cache/cache_coordinator.dart)431–441行没有捕获此类普通打开错误，后面的内存降级分支尚未进入。

诊断使用真实原生打开函数、临时损坏index与模拟support目录：attach失败且scope为空，原文件保持不变。已有注入executor的损坏库用例没有覆盖这层预检。应保持原文件并针对普通索引损坏降级；writer占用和需要升级应用仍维持独立终态。

### P2：未来schema异常跨Drift remote后被误认为普通损坏

[CacheDatabase](../../../frontend/lib/core/cache/cache_database.dart)抛出的`CacheSchemaTooNew`经过Drift远端执行器后包装为`DriftRemoteException`；[attach](../../../frontend/lib/core/cache/cache_coordinator.dart)461–472行只按本地异常类型判断，遂进入内存降级而不是`cache_update_required`。

诊断通过`NativeDatabase.createInBackground`复现远端包装语义，再模拟没有native预检的远端executor：schema5保持未修改，客户端却变成memoryOnly且可用。Web后端采用的worker执行器存在这条类型边界；本证据验证共享remote机制，不冒充浏览器端到端运行结果。需通过可靠schema探测或可跨进程识别的错误类别阻断旧客户端。

### P2：合法形状的version损坏未与精确entry_key核对

[_entryExact](../../../frontend/lib/core/cache/cache_database.dart)363–402行校验payload长度和hash并解析version，但未校验`cacheEntryKey(logicalKey, version)`等于存储键。

诊断把v1行的version_json改成合法v2，保留v1正文和键；随后validate收到v2并返回same，客户端返回v1正文但标成v2，且未fetch。应在已知logicalKey的快照读取处复核精确键与版本身份。此为损坏一致性问题，测试手工修改库不代表外部攻击入口。

## 3. 静态确认的其余问题与建议

- **P2，Android音频锁缺同进程互斥。** [原生音频后端](../../../frontend/lib/core/cache/audio_blob_backend_native.dart)77、129、143–145行仅依赖文件锁。锁定Dart SDK的`dart:io/file.dart`明确Linux文件锁属于进程，同一进程的另一个句柄不会按独立读者互斥；这不足以保护同进程播放器与删除/恢复。应像文本入口一样增加进程内锁，并保留OS锁处理进程边界。未在Android实际运行，Windows测试不能证明此Linux语义正确。
- **P2，浏览器实际空间耗尽未走有界淘汰。** [Web音频后端](../../../frontend/lib/core/cache/audio_blob_backend_web.dart)283–286行把IndexedDB事务错误/中止统一变成`StateError`，没有保留可识别的quota类别；下载管理器只在本地账面容量预留失败时尝试LRU。浏览器分配空间低于应用配额时，写入失败不会进入一次有界淘汰后重试。此项仅静态核对，未声称已做浏览器满盘运行验证。
- **P2，设置可见页缺周期及再次进入的资源复验。** [SettingsPage](../../../frontend/lib/features/settings/presentation/settings_pages.dart)158–175行和[SettingsSnapshotGate](../../../frontend/lib/features/settings/presentation/settings_snapshot_gate.dart)27–48行仅在仓储/scope变化时尝试初始读取，已有ready快照会跳过。没有30秒资源刷新；access复核无法发现跨设备资料变化。当前属预览接线路径，补充时须保留表单draft。
- **P2，查询隐藏后快速返回可能跳过本次复验。** [revalidateVisible](../../../frontend/lib/features/agent/data/cached_query_result_repository.dart)217–257行的`_checkingVisible`拒绝新调用，但旧任务只检查最终`_visible`，没有可见周期。旧请求未结束时hide→show会复用上次动作结果或等待下一定时器。需在返回时排队新复验/推进可见代次。未做UI交互运行验证。
- **P3，PreviewApp未释放自己创建的查询仓储。** [dispose](../../../frontend/lib/app/preview_app.dart)229–248行未调用查询仓储的dispose；其订阅、定时器和版本pin生命周期缺少对应收口。应与其他自建仓储一样按所有权释放。
- **P3，内存元数据缺回收。** `_remember`仅限制正文，按资源增长的标签、许可锚、读取代次及显式持久化集合未统一裁剪。治理时必须保留在途请求、有效pin与安全失效信息，不能直接清空绕过代次。
- 未知广播扩大失效及head空依赖差异按第1节定性，不能据此声称所有许可永久消失或现有读路径权限绕过。

## 4. 审查覆盖与实际测试

静态覆盖`frontend/lib/core/cache/`全部24个文件：协调器、Drift schema1/2/3→4、模型、重试、会话绑定、Web/native后端、文本及分区锁、失效提示/通道、音频存储/下载/恢复。追踪正式HarukaApp、ApiClient与AuthController接线，以及查询、设置、材料、收藏/词本、通知仓储及可见页刷新；核对遥测两端白名单和缓存设计/契约的已实现边界。未扩展为后端业务、全应用UI或未来阅读/TTS页面验收。

此前用户要求的现有测试：15个缓存/仓储/API会话测试文件，首轮141通过、9失败；修复后150通过。证据：`artifacts/cache-validation-20260927-201207/vm-tests-after-fix-2.log`。不把这次既有用例通过解读为以上故障分支正确。

本轮新增临时诊断共13项，按需运行一次，全部达成诊断断言：

| 文件 | 数量 | 证据日志 |
| --- | --- | --- |
| `artifacts/cache-audit-20260927/core_probe_test.dart` | 7 | `artifacts/cache-audit-20260927/core-probes.log` |
| `artifacts/cache-audit-20260927/revocation_probe_test.dart` | 2 | `artifacts/cache-audit-20260927/revocation-probes.log` |
| `artifacts/cache-audit-20260927/platform_probe_test.dart` | 4 | `artifacts/cache-audit-20260927/platform-probes.log` |

每个文件分别从frontend运行`flutter test --no-pub --reporter expanded ../artifacts/cache-audit-20260927/<文件名>`。诊断文件保存在被忽略的artifacts目录，包含故障注入，不纳入正式测试成功门禁。

Web的3项既有定点测试仍没有执行结果：Flutter 3.47.3 Windows Web runner加载阶段CanvasKit请求404且测试路径异常，已停止挂起任务，详见前次记录。未改SDK、未机械重跑150项、未运行全仓/Android/Windows宿主验收，未做新UI视觉对照。新文档只核对相对链接和代码围栏。本轮结果是已完成审查并确认缺陷，不能标为缺陷已修复。
