# B0 生成与注册目录收口

日期：2026-09-22，阶段1/B0 的 SCF-B0-05 定点工作，不代表整个 B0 通过。

## 新增检查与 review

开发入口在导出前调用 [登记检查](../../../backend/tools/check_registries.py)，使用既有权限模板校验，并检查当前 app 自有 logger 的事件字面量是否在 `EVENTS` 注册。识别目前采用的 logging 模块、getLogger 别名和直接调用；未知或动态事件拒绝，非日志对象的 `error()` 不受影响。这是当前调用模式的静态检查，不声称覆盖 Python 任意动态数据流。外部库在运行时仍经原有安全 formatter 输出 `library.log`，不改变脱敏规则。

新增6项单元通过，原始结果为 `artifacts/dev/registry-references.xml`：未知权限模板、未知事件/别名/直接调用、动态事件拒绝及正常事件和非日志错误调用。实际登记检查通过，受影响 Python 的 Ruff 与 strict Pyright 通过，原 codegen 模拟导出节点定点回归通过。

非作者 `infrastructure_tooling` 第1轮 review 通过，无阻断项。核对生产格式器未修改、检查在写入前执行、安全诊断仅文件及行号、6项原始结果非空且无 skip/error；未重复审查已关闭的协议或 UI 切片。

## 补录的实际证据

历史生成器与 Dart 消费者运行只有任务回执，因此只补录缺少原始文件的7项生成器、9项 Dart API 与4项配置/布局节点。所有选定节点通过，Dart机器报告的最终会话成功、各节点无失败/skip。原始日志及 SHA256 汇总见 `artifacts/b0-contracts-final/summary.json`，没有从退出码重建测试结果。

使用隔离公开文件副本执行两类缺失坏样本，没有修改真实 registry 或工具清单：

- Dart analyzer 先接受已生成的 `UiTestIds.homePage`，再对未知成员返回 `UNDEFINED_GETTER`，不是由缺依赖或语法错误误报。
- 完整 `codegen --check` 入口遇到错误 Flutter revision，在实际 SDK 诊断阶段失败；唯一结构化报告明确指出版本/revision 与工具清单不符，没有执行导出写入。

原始命令、退出码、准确诊断及摘要保存在 `artifacts/b0-contracts-final/negative-summary.json`；两次实际生成一致性与缺失/篡改产物检查由 Linux/Windows 干净检出记录汇总。所有旧失败仍保留，证据未签署前不把独立节点计作整次 B0 通过。
