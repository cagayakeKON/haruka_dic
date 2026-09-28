# 文本清理与音频收尾修复

范围：阶段1现有客户端缓存基础的局部缺陷修复，承接[前一轮缺陷修复](2026-09-27-cache-defect-fixes.md)。GPT-6-Sol实现，主Agent独立review及运行相关回归；按用户要求不提交、不推送。正式validate、descriptor、grant、可靠断网判断和音频业务页面仍另行建设。

## 核对与修复范围

1. 清文本保留的ready音频不应被暂停写入的门闩挡住；下载须及时核对持久代次，不能只在整段发布时发现跨标签清理。
2. 清文本换代时须退休旧staging、释放下载槽，并对已无owner的残留字节及预约执行清退；删除失败继续计账。
3. 同asset的staging或deleting操作须阻止第二次预约，不能在传输结束才发现重复。
4. 待删除的A不能仅凭全局pending状态阻止已清净B或新C的显式下载；同键残留、容量和权限仍应拒绝。
5. 恢复校验不得持分区发布锁遍历全文件SHA-256，拆分短锁快照、锁外校验和提交前复核。
6. 已确认但未落盘的正文应支持校验same后再次尝试保存。原代码在磁盘行缺失时会清掉内存候选，因此这一分支实际会重复fetch，并非必然永久停在same；修复需同时防止把另一标签已删除的旧持久副本重新发布。

以上路径已修复。文本补存候选只在原快照仍匹配时参与same复验，发布仍复核全部代次；成功补存可沿用尚有效、同身份同版本的许可，same不带新许可不会续期或丢弃既有有效许可。音频下载的持久代次检查不依赖广播，等待下一块时也可由本地失效事件取消。

清文本的实际入口现在调用音频清退并重算clear状态；旧owner稍后完成finally也会重算最后一条pending。收尾事务核对发起清理的storage_epoch，较早的清理不能结束较新的清理。退休owner取得操作锁后，会核对操作身份并处理stage和尚未提交索引的promoted引用；删除失败按已测得的实际残留收账，不永久占用未下载部分的预约。

## Review与验证

主Agent完成一轮集中review和一轮定点复核，修订了：取消等待者累积、旧清理收尾的代次CAS、已退休音频的大额预约收账、promote后崩溃窗口、恢复时待删引用重复计账，以及same补存时已有有效许可的重新启用。没有重新审查未改动的整个项目。

最终9个文件共107项通过，日志为`artifacts/cache-audio-text-fixes-20260927/final-tests.log`：

- 核心：`cache_database_test.dart`、`cache_coordinator_test.dart`、`cache_recovery_regression_test.dart`。
- 直接消费者：`cached_query_result_repository_test.dart`。
- 音频：`audio_blob_store_test.dart`、`audio_blob_backend_native_test.dart`、`cache_audio_manager_test.dart`、`cache_audio_recovery_regression_test.dart`、`cache_audio_fault_regression_test.dart`。

新增/扩展用例证明：清文本后ready音频仍可读；真实协调器入口清退死亡stage并释放预约；停滞下载收到失效后取消；另一数据库连接清文本且完全丢失广播时，下一块不会写入；同asset并发预约只成功一次；无关键显式下载可在pending期间完成；恢复hash暂停时其他发布仍能完成，稍后发布的ready不被删除；promote后崩溃及100字节预约只有2字节残留时账目准确；INSERT故障和配额恢复后same补存不增加fetch；其他连接删掉已落盘行时必须重新取数；已有有效许可在same省略新许可时仍可随补存恢复；旧clear收尾不能修改新clear状态。

`dart analyze lib/core/cache test/core/cache`通过，结果为`No issues found`，见`analyze-final.log`。首次分析发现异步取消链缺少显式`unawaited`标记，已修复。首批核心76项、音频26项分别通过，之后针对review新增/修改的收尾路径执行上述最终相关矩阵；不将这些重叠批次相加。跨连接用例触发Drift的多实例debug提醒，保留原日志，未屏蔽警告或把它误记为失败。

运行复用此前临时测试目录，源码及测试链接回原仓库，构建输出隔离，依赖不变；没有终止并行前端任务。此次只改缓存基础与相关文档，没有修改页面布局，不重复UI原型或全仓验收。原生文件后端的证据是Flutter低层测试，不是Windows或Android应用实机验收；本轮未重跑浏览器和Web构建，前轮证据不能冒充本轮平台实测。

本轮修改的8个Dart文件通过格式检查，`dart format --output=none --set-exit-if-changed`报告0个文件需要修改。

## 不扩展的边界

当前从后台恢复立即进入待在线验证并隐藏私有内容；连续前台时的20秒检查和30秒失败截止不构成恢复宽限。此次保留该安全行为并澄清架构文档，不自动将超时或5xx转换为离线许可。当前材料、设置、收藏与通知是memoryOnly重新取数；查询学习文字是预览中的可持久化消费者，不代表正式离线业务已经交付。
