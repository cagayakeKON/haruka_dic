# 缓存精确版本、清理并发与休眠租期修复

范围：阶段1现有缓存基础的局部修复，承接[文本清理与音频收尾修复](2026-09-27-cache-audio-text-recovery.md)。GPT-6-Sol负责实现，主Agent负责独立review、相关回归与记录；按用户要求不提交、不推送。正式校验接口、许可签发和离线阅读业务仍另做。

## 已确认的问题

1. 精确版本未命中时错误删除逻辑键当前内存正文；未落盘候选无法参与精确版本补存，补存许可又错误使用逻辑键槽位。
2. 全量清理与下载收尾没有强制核对发起操作的存储代次，较早的操作可能修改新清理状态；同一协调器的清理未与作用域生命周期串行。
3. 存储同步跨异步等待后未核对本机存储修订，可能用清理前的快照回退内存代次。
4. 后台与恢复没有撤销依赖本次单调时钟的离线时间锚；仅后台重验access不能证明休眠期间的剩余租期。

## 修复与验证

修复后的精确读取不影响另一版本的当前内存正文，刷新回调也只接收请求版本。相同版本的未落盘候选可以用原head快照补存；精确许可槽位及同版本撤销一起处理，失败后的普通读取不能借逻辑键旧许可重新落盘。

文本清理、全量清理和作用域挂接/关闭共用串行队列。清理收尾强制提供发起时的storage_epoch；旧下载退出后的残留核账另外比较当前epoch和pending状态，只有仍匹配才重新计算剩余记录，不能提前结束clearing。

存储同步用单条LEFT JOIN SELECT取得控制代次与失效计数，并在应用前核对本机storageRevision。正文读取的Drift短事务快照使用分区发布锁，避免与另一连接的pin清退竞争SQLite写意图锁；网络请求与音频全文件校验不放进这把锁。

前后台变化撤销离线时间锚并推进独立租期代次。在线正文仍按原账号及存储代次判断是否接受；跨前后台迟到的grant不得建立许可，后台请求也不能为恢复后的离线读建立时间锚。access成功不续租，新前台资源校验才可恢复可信锚。

主Agent完成集中review和针对修订的定点复核。回归过程中修正了：新测试的Drift/matcher同名导入冲突、旧下载退出留下空pending、控制/正文快照与pin清退竞争写锁，以及精确读取的刷新回调展示另一版本。原始失败日志保留，不通过加等待或重复执行掩盖。

本轮最终相关8个测试文件共105项通过，证据目录为`artifacts/cache-version-lifecycle-fixes-20260927/`，不沿用上一轮107项作为本轮证据：

- `core-verified.log`：`cache_database_test.dart`、`cache_coordinator_test.dart`、`cache_recovery_regression_test.dart`、`cache_session_binding_test.dart`、`cached_query_result_repository_test.dart`，86项通过。
- `audio-final.log`：`cache_audio_manager_test.dart`、`cache_audio_recovery_regression_test.dart`、`cache_audio_fault_regression_test.dart`，19项通过。后续核心快照调整未改变音频管理器及其数据库行为，不重复这组测试。
- `analyze-verified.log`：`dart analyze lib/core/cache test/core/cache`报告`No issues found`。首次分析的6处多余断言/类型转换已修复。
- 本轮10个改动Dart文件执行`dart format --output=none --set-exit-if-changed`，0个文件需要修改；相关文档另检查本地链接、代码围栏与空白。

重点回归包括：保留v1磁盘head时补存未落盘v2，精确miss不清当前候选且不闪另一版本；精确撤销后普通same不能重新写回许可；清理完成并产生新正文后才返回旧控制快照；清理与新账号attach按序完成；下载等待期间新清理仍保持clearing；空pending最终回到ready；后台及慢access期间无旧离线许可，迟到grant不能重建时间锚，新的资源校验可恢复离线许可。

测试复用隔离构建输出的临时目录，源码及测试链接回原仓库，依赖未变；原始失败日志保留，重叠批次不累计。跨连接用例的Drift多实例debug提醒未屏蔽。此次是Flutter缓存低层与消费者回归，不是Web浏览器、Android或Windows应用实机验收；未重复全仓、UI或平台构建。

## 边界

本轮不修改页面布局、重拉业务页面或增加正式离线入口。离线租期失效与在线界面授权分开处理：后台恢复不延长许可，也不因清除离线时钟而卸载仍有效的在线页面。access成功本身不能重新建立离线时间锚；需新的前台在线资源授权响应。
