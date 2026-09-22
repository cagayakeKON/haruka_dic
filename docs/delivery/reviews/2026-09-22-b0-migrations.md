# B0 受控迁移与 schema 检查记录

日期：2026-09-22。所属阶段1 / B0。本记录只证明受控迁移这一工作单元，完整 B0 由最终交付记录汇总；B1/B2 业务能力不在此处验收。

## 实现范围

- [独立维护配置](../../../backend/app/maintenance/settings.py) 显式读取维护配置文件，只接受 loopback 上的 `haruka_dev` / `haruka_test` 及其对应维护角色。运行角色、其他数据库、远程地址和 URL 查询参数均拒绝；声明的 `HARUKA_APP_ENV` 必须与目标一致，production/staging 不能借本地数据库绕过环境拒绝；不从工作目录发现配置。
- [迁移入口](../../../backend/app/maintenance/migrations.py) 使用专用 NullPool engine。同一物理连接持有稳定的数据库级 session advisory lock、检查当前 revision / 实际表清单并执行 Alembic DDL。锁等待有界；断连后本次失败，重试重新连接、取锁、读取已提交状态。
- [Alembic 环境](../../../backend/alembic/env.py) 只接受经 `Config.attributes` 传入且实际持锁的连接，并核对 PG backend PID、search path 和 `pg_locks`。不创建备用 engine；裸命令和离线执行拒绝。
- [首 revision](../../../backend/alembic/versions/0001_b0_identity.py) 明确创建 12 张基础表，无物理外键。迁移事务不负责业务种子；从运行角色撤销审计表的 UPDATE/DELETE 及迁移版本表的 INSERT/UPDATE/DELETE。首次建库没有上一发布 revision；不提供破坏性 downgrade。
- [迁移 manifest](../../../backend/alembic/manifest.json) 固定唯一 head 和全部 Python 迁移资源 SHA-256；缺资源、未知文件、摘要漂移或多 head 均失败。资源目录必须显式传入绝对路径。
- [只读 schema 检查](../../../backend/app/maintenance/schema.py) 核对 revision、表/列/type/NULL/default/索引/唯一约束、注释、主键、零外键和 CHECK。Alembic 不直接比较 CHECK 表达式，因此 [包内基线](../../../backend/app/maintenance/schema_baseline.json) 同时绑定模型源表达式和已审查首迁移的实际 PG canonical 表达式；缺基线、模型漂移、同名 CHECK 内容变化及未验证约束均失败。检查不修复或迁移数据库。

实现依据为 [Alembic 连接共享接口](https://alembic.sqlalchemy.org/en/latest/cookbook.html#sharing-a-connection-across-one-or-more-programmatic-migration-commands) 和 [PostgreSQL advisory lock 语义](https://www.postgresql.org/docs/17/functions-admin.html#FUNCTIONS-ADVISORY-LOCKS)。运行依赖固定 Alembic 1.20.0，沿用仓库锁定的 SQLAlchemy / asyncpg。

## 实际验证

使用已运行的独立开发 PostgreSQL。每个集成用例在 `haruka_test` 创建随机 `haruka_migration_test_<32位hex>` schema，结束仅清理本用例创建的 schema；本子任务未操作 public 或 MyHome 数据。随机 schema 只能由显式测试构造传入，普通维护命令默认 public，环境变量不能偷偷改为测试 schema。

| 范围 | 实际结果 |
| --- | --- |
| 维护配置、迁移资源及基线拒绝样本 | 22 项通过；覆盖运行角色/错误目标、显式配置、秘密 repr、声明环境冲突、测试 schema 边界、缺文件、摘要漂移、未知文件、多 head、缺失和漂移 CHECK 基线 |
| 真实 PG 集成 | 6 项通过，60.62 秒；结果保存在 `artifacts/dev/migrations-first.xml` |
| 空库及幂等升级 | 空库升级到 `0001_b0_identity`，再次升级保持表清单；只读检查发现新增列和同名 CHECK 范围变化 |
| 两个独立维护进程 | 第一个进程持锁执行；第二个在有界等待后失败。实际锁的 PG PID 与成功执行 DDL 的连接 PID 相同 |
| 取锁后断连 | 在首次业务表 DDL 前的合成迁移阶段终止持锁 PG 连接；进程失败，重试使用新 PID，重新取锁与检查 |
| DDL 中断连 | 在 `CREATE TABLE ... pg_sleep(...)` 中终止同一 PG 连接；未提交表被回滚，重试恢复到完整 head |
| 部分步骤已提交后断连 | checkpoint revision 已独立提交，下一 revision 中断；重试先观察 checkpoint revision 与表，再继续余下步骤，未重复执行已提交建表 |
| 裸 Alembic | 未传受控连接不能连接或修改目标 schema |
| 第1轮审查后定点回归 | 正常升级/漂移与错误 search path 2 项通过，17.95 秒，结果为 `artifacts/dev/migrations-review-regression.xml`；原有争锁/断连证据仍适用，未机械重跑 |
| 静态检查 | 本单元 Ruff format/check 与 Pyright strict 通过 |

故障注入只存在于 [测试生成的临时 revision](../../../backend/tests/integration/test_migrations.py)，正式包没有 sleep/故障开关或测试 HTTP 旁路。单测见 [维护拒绝样本](../../../backend/tests/unit/test_migrations.py)。unit JUnit 保存于 `artifacts/dev/migrations-unit.xml`；报告目录不提交。

## 审查与交付边界

本单元由主 Agent 执行第1轮非作者审查，发现维护配置未识别 ambient 声明环境，以及只读检查未核对传入 schema 与连接实际 search path 的两个边界。现已集中修复：拒绝声明环境冲突；反射前同时核对 `current_schema()`、`search_path` 与 dialect 默认 schema。新增环境拒绝单测及真实 PG 错误 search path 用例，并保留无环境声明旧维护文件的兼容性。

修复后的第2轮定点复核已由主 Agent 完成，确认声明环境检查及 `current_schema()` / `search_path` / dialect 默认 schema 一致检查关闭上述两个问题；未发现新增阻断项。最终提交及完整 B0 结论另记 B0 交付记录。本记录不以作者自检代替独立 review。

本单元不声明受控种子、管理员初始化、完整 DB 时间戳矩阵、三端运行、CI 或整个 B0 已验收；这些由对应实现与实际证据汇总。数据库前滚和备份恢复仍按 [部署恢复](../../operations/deployment-recovery.md) 的受控流程执行。
