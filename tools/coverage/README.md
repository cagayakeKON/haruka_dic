# Flutter Web 测试覆盖采集

锁定 Flutter 3.47.3 的 Chrome 测试平台没有接入普通 coverage watcher。本工具为明确列出的测试采集真实 CDP 执行记录，经官方 `coverage` 与 `source_maps` 转换为 Dart 行数据；不能用 VM 命中替代浏览器执行。

使用仓库锁定的后端 Python。输出目录必须全新，测试位于 `frontend/test`，SDK 必须匹配版本和原始平台源码摘要。采集前冻结源码和工具，独占 SDK 兼容锁，结束时校验并恢复原字节。超时或失败只清理本工具拥有的进程树；出现并发 SDK 修改时拒绝覆盖并保留原字节备份。

```powershell
backend/.venv/Scripts/python.exe -m tools.coverage.runner capture `
  --sdk D:/MyData/software/flutter `
  --output artifacts/web-coverage/capture-example `
  --test test/core/auth/auth_sync_web_test.dart `
  --timeout 900
```

可重复传入 `--test`。`--plain-name` 只用于明确的定点回归，记录为子集，不能凭子集签完整集合。成功必须有原生退出0、唯一成功的最终 done、实际成功节点、无失败节点以及不变的源码/工具摘要；原生输出和失败证据保留。

转换使用采集输出中的实际 `raw/session-*/raw.json` 和 `freeze.json`，输出另选全新目录：

```powershell
backend/.venv/Scripts/python.exe -m tools.coverage.runner convert `
  --sdk D:/MyData/software/flutter `
  --raw artifacts/web-coverage/capture-example/raw/session-actual/raw.json `
  --freeze artifacts/web-coverage/capture-example/freeze.json `
  --output artifacts/web-coverage/convert-example `
  --timeout 900
```

示例中的 `session-actual` 须换成该次实际目录。转换校验每份内容寻址 blob、源映射及冻结源；损坏 VLQ、项目空映射或遗漏项目源拒绝生成结果。纯导出文件必须同时满足注册的 declaration-only 类别和实际只含指令的源码检查；不能按字段、类或枚举的外观删去合法映射点。探针源只保留在完整诊断报告，业务报告是其精确生产源过滤，并各自记录摘要。

诊断只记录静态异常类型、同源源码坐标与计数，省略消息、参数、描述、函数名和查询正文。另允许测试打印有限白名单 `HARUKA_AUTH_TEST_DIAG:` 状态标记；只保存已登记的固定状态名称，任意动态文本、额外参数和未登记标记全部省略。此工具用于测试进程，不采集正式用户页面的控制台正文。

采集及转换成功仅证明该次测试与数据有效。完整覆盖门禁还需 [归一化工具](../../scripts/quality/flutter_lcov_normalization.py) 和 [严格覆盖检查](../../scripts/quality/coverage.py)，绑定真实原生证明、源码与报告摘要，保留 VM/DDC 合法行集合及各分片自身命中，并执行现行完整分母与阈值。不得把本工具进程退出0记成业务验收通过。
