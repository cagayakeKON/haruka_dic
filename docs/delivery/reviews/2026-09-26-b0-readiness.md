# B0 健康检查调整

日期：2026-09-26。阶段1内的B0后端局部修订，由GPT-6 Sol实现代码与测试，主Agent同步文档并进行代码Review。本记录补充[原B0验收](2026-09-22-b0-acceptance.md)与[B0设计对齐](2026-09-26-b0-design-alignment.md)，不替换历史候选或完整矩阵。

## 范围与行为

原先每次`/health/ready`都会反射全部模型对应的数据库结构，检查字段、约束、索引与注释。本次将高频探针改为检查PG连接/运行身份与权限、精确迁移版本及当前profile必需依赖；完整结构校验继续在进程启动和受控迁移/维护时执行。

- 新增轻量版本检查，验证schema与测试库边界，读取受控版本表且最多取两行；不存在、空表、多行或不匹配的revision均拒绝。
- 启动路径仍完整检查一次；受控迁移、结构基线和迁移文件未改变。
- core继续要求PG/Redis，jobs增加Kafka与私有Bucket；失败返回统一503，下次请求重新检查并可恢复200。`/health/live`仍只表示进程生命周期存活。
- 不增加健康结果缓存、后台定时扫描或自动修复；完整执行边界由[运行与健康契约](../../operations/configuration.md#31-b0健康检查的执行边界)维护。

## 验证与Review

检查范围为后端资源组装、迁移版本探针、HTTP健康契约及直接受影响的core/jobs测试。真实PG验证在`haruka_test`中使用每用例独立的随机`haruka_migration_test_*` schema；不升级开发库或测试库的public schema，不改MyHome数据。

| 检查 | 实际结果 |
| --- | --- |
| HTTP/profile/lifecycle及真实PG定点回归 | 21项通过，0失败/0跳过，8.23秒；本机报告`artifacts/dev/b0-readiness-regression.xml` |
| 原有启动/结构漂移及live/ready区别 | 2项通过，0失败/0跳过，3.71秒；本机报告`artifacts/dev/b0-readiness-startup.xml` |
| 受影响Python文件 | Ruff check与format --check通过；Pyright零错误/警告 |
| 文档 | 7份Markdown本地链接、围栏与路径检查通过；Markdownlint零问题，`git diff --check`通过 |

第一组覆盖`tests/contract/test_readiness.py`、`test_core_never_constructs_jobs_and_cleans_up`、`test_cleanup_in_reverse_order`，以及`test_migrations.py`中的`test_light_revision_probe_rejects_bad_head_and_recovers`、`test_full_schema_check_still_catches_drift_with_valid_head`、`test_schema_check_rejects_an_engine_pointing_at_another_search_path`。第二组执行原有`test_empty_upgrade_repeat_and_read_only_schema_drift`与`test_health_and_readiness_are_distinct`。命令在backend目录使用锁定虚拟环境中的pytest，维护配置显式选择`dev/.local/test-maintenance.env`；以上报告为本机生成产物，不计入历史完整B0矩阵。

重复HTTP探针证明完整检查只在启动执行一次；PG/Redis/版本/Kafka/存储故障均返回503且恢复后200，期间live仍为200。真实PG用例覆盖版本表缺失、空、多行、错版本及恢复，并禁止轻量路径调用inspector/compare_metadata；正确revision下移除一项CHECK，轻量检查通过而完整检查拒绝。错search_path及未登记schema被拒绝，原启动失败资源清理回归仍通过。

主Agent首轮Review检查资源组装、轻量SQL、版本/连接边界和失败恢复，建议版本SELECT沿用SQLAlchemy Core；Sol集中调整后定点复核通过，无未关闭代码缺陷。完整结构校验函数与迁移调用保持原实现。主Agent维护的文档由另一名GPT-6 Sol只读独立审阅，确认检查频率、故障语义和交付边界与代码一致，无文档缺陷；主Agent核对两份测试报告的实际计数后完成记录。

## 保留边界

运行中人为改变结构而保持revision不变，不保证被轻量readiness发现；启动与受控维护的完整检查仍会拒绝结构漂移。运行账号无DDL权限，结构变化必须经过受控迁移。此项调整减少每次探针的结构反射工作，没有进行延迟基准测试，不声明具体提速比例。

数据库表结构、迁移版本、前端、原型和对外响应格式均未调整。B1/B2仍未实现；本次不重跑全仓、跨平台完整E2E或原B0完整验收矩阵，也不据此重新声明完整B0验收。本小阶段完成必要验证与Review后本地提交，不push，提交身份以Git历史为准。
