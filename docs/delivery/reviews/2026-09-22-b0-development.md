# B0 开发入口与进程所有权记录

状态：实施、定点运行及两轮独立 review 已完成，本切片已报缺陷均关闭。本文覆盖 `doctor --config`、`dev core/jobs`、正式入口资源 profile 和本次新增进程控制代码，不替代完整 B0、业务 Worker 或平台发布验收。对应 [SCF-B0-01/03](../milestones/scaffold.md) 与 [开发入口合同](../../engineering/scaffold.md#3-开发命令的行为合同)。

## 本次行为

- 不带 `--config` 的 doctor 检查所选工具；带显式绝对配置文件时，另经正式维护入口校验配置、运行凭据、真实依赖与 schema。带 `--target` 时先诊断启动端口，Android 必须提供明确设备 ID。
- core 通过 `HARUKA_RESOURCE_PROFILE=core` 组装 PG/Redis；jobs 采用完整资源并启动 Worker/Outbox 的 `--lifecycle-only`。两者都不迁移、种子初始化或创建管理员。jobs 的 `business_handlers=false` 明确表示尚未交付 B2 领取、投递及业务执行。
- 后端实际检查连接的数据库和运行角色，拒绝维护账号、超级用户、建库/建角色、schema CREATE 及审计 UPDATE/DELETE/TRUNCATE 权限；只检查配置用户名不足以通过。API 使用 Uvicorn graceful exit，Worker/Outbox 通过同一资源组装释放真实连接；退出标记必须为父目录存在、文件尚不存在的绝对路径。
- API 必须实际返回 readiness 200；Flutter 必须发出 machine `app.started`，Web 还检查服务器可访问，之后才报告启动完成。Web 使用 `web-server`，不打开用户浏览器；Windows/Android 只启动用户所选目标。
- Windows 每个帮助进程以隐藏方式创建，在内核 Job 接管并核对可执行文件/创建时间后才放行实际应用。Job 设置 kill-on-close，因此启动失败和父进程退出不会把本次子孙留给其他任务。POSIX 使用独立 session/process group。
- 停止时先创建本次 API/Worker/Outbox 退出标记，向 Flutter 发送 `app.stop`，有界等待后回收仍存活的自有进程。强制清理或子进程非零退出会使开发命令失败。既有端口占用者、其他设备、Compose 数据卷和相邻项目不在终止范围。
- POSIX 在仍存活的自有 session leader 下回收整个组，包含忽略 SIGTERM 的子孙；父入口异常消失时，监督进程通过 stdin EOF 执行组回收。
- 脱敏报告保存 run ID、namespace、包装进程 PID/创建时间/可执行文件、目标命令、目标 PID、退出码及强制清理标志。长时间运行时也写入启动记录；秘密配置值和原始应用输出不进入这份报告。

## 定点验证

新增 `scripts/tests/test_processes.py` 的 8 项测试在 Windows Python 3.13.6 和 Linux Python 3.13.6 均通过：正常退出标记与重复清理、失败退出码、第二个进程失败后的前序资源释放、忽略 SIGTERM 的自有子孙强制回收且无关进程存活、缺程序拒绝、端口占用不干扰、配置隔离及环境覆盖拒绝。受影响 4 个 Python 文件 Ruff 格式/规则检查与 scripts strict Pyright 通过。未增加空测试或触发其他平台矩阵。

Linux 验证复用本机已存在的镜像 ID `sha256:4b7b8380085c29e0b74450e375ead2f653fb4b5eb1fc012f3f0f7f03649c70d0`，确认 Docker 连接为本地 Desktop Linux named pipe 后，使用禁网、只读根文件系统、临时 `/tmp`、只读 `scripts/` 挂载和自动移除容器执行；没有挂载凭据或发布宿主机端口。原始结果为 `artifacts/dev/b0-processes-linux.txt`，不代表已执行 Linux 全应用或远程 CI。

真实 core 配置、运行账号、依赖与 schema 检查通过，报告 `artifacts/dev/doctor-56b8d1fb426344eda310cfca5db5df57.json`。

后端资源 profile / 退出标记的 37 个定点单元用例通过，结果 `artifacts/dev/profiles-unit.xml`；3 个真实基础设施用例通过，结果 `artifacts/dev/profile-real-infrastructure-configured.xml`。较早未提供 `HARUKA_INTEGRATION_CONFIG` 的 setup 失败报告 `artifacts/dev/profile-real-infrastructure.xml` 保留，不能计作通过。

包含本次 profile/退出标记的候选 wheel/sdist 已完成 Windows 定点验证：清洁隔离构建且校验构建 hash、仓库外 runtime-only 非 editable 安装、4 个正式入口真实基础设施 lifespan、安装后 `db status`/包内 schema baseline、错误构建 hash 拒绝。结果为 `artifacts/package-check/d803e2c88c594f62badce90616a8af61/report.json`，不延伸声明 Linux 包运行结果。

真实 core/Web 运行命令采用 `dev --profile core --target web --api-port 18080 --run-seconds 2`，报告 `artifacts/dev/dev-cfa19d88205e45978cf8b4ea8c0632af.json` 为 passed。API 和 Flutter 都经真实就绪检查，停止后均退出 0、`forced=false`。

真实 jobs/Web 使用同一备用 API 端口和本次唯一 `--stop-file` 保持服务。通过页面点击触发实际 `/health/ready`，确认 HTTP 200、允许 localhost:5173 的 CORS、DTO/UI 就绪及 resize 不重复请求；Playwright 1 项通过，结果 `artifacts/e2e/live-963b7973-f360-4cf0-a9a4-5b786088e8cc/results.json`。创建指定退出标记后，API、Worker、Outbox、Flutter 全部退出 0、`forced=false`；开发报告 `artifacts/dev/dev-d10af4b6445349979dce720732469d82.json` 为 passed。

首次 core/Web 联调暴露 Web `app.started` 后 HTTP 尚未可用、关闭记录字段冲突两项实现问题。已分别修成有界 HTTP 就绪等待和独立 `process_name` 字段，随后上述 core/jobs 正向运行通过。失败原报告 `artifacts/dev/dev-2e70496b1a23484095de2e264ea00fcb.json` 保留，不计作通过。

## 环境限制与 review 范围

本机默认 API 端口 8000 位于 Windows TCP 排除段 7957～8056，实际 bind 返回 WinError 10013。启动前诊断已拒绝，没有修改系统排除段或终止进程；此前报告把该错误概括为占用，现已分开输出系统拒绝/保留与普通占用。备用 18080 已在前端公开目标清单登记，`--api-port 18080` 显式选择该端点，不改写秘密文件。

本次独立 review 覆盖 `scripts/dev.py` 的 doctor/dev 参数及编排、`scripts/development.py`、`scripts/processes.py`、`scripts/tests/test_processes.py`；以及后端 `core/settings.py`、`bootstrap.py`、`adapters/cache.py`、`adapters/database.py`、`cli/api.py`、`cli/worker.py`、`cli/outbox.py`、`cli/lifecycle.py` 和 `test_process_profiles.py`、相关运行用户名 fixture。同时检查兼容 fixture 生成接线、测试入口发现范围和分发验证报告的实际平台元数据；未重新审查已关闭的数据库、前端及质量门禁切片。

本轮没有重新执行 Windows/Android 原生目标，既有平台证据由 B0 总记录汇总；没有运行 Linux 完整应用、远程 CI 或 B2 任务 handler。此处局部结果不代替最终 B0 必需矩阵及全盘 review。

## 独立 review 与集中修复

非作者 reviewer：`infrastructure_tooling`。第 1 轮集中检查实现与直接影响，并只读核对上述单元、真实基础设施、分发安装和 core/jobs/Web 运行证据，发现两项 P2 缺陷：

- `runtime_doctor` 通过 `uv run --locked` 调用维护入口，诊断可能隐式创建或同步依赖环境，违反 doctor 的只读合同。
- 停止记录只根据目标父进程是否退出判断 `forced`，父进程正常退出但孙进程仍存活时，最终强制回收却会记录 `forced=false`。reviewer 的隔离 Windows 复现确认该误报；既有端口占用者与无关进程不应因此被终止。

作者集中修复后，doctor 直接使用 `backend/.venv` 中的已安装 `haruka-manage`，缺少入口时明确要求先执行 `bootstrap --scope backend`，不调用依赖解析器。Windows 改为每个应用独立 Job，查询活动进程数并只扣除已知监督进程；POSIX 检查本次独立进程组内非 zombie 成员。目标退出且残留数为零才算正常停止；残留计数失败也不能当作零。报告增加 `remaining_app_processes`，保留目标真实退出码，存在残留即标记强制清理。

修复期间真实 jobs/Web 运行发现隐藏监督进程创建的 console host 被误计为应用残留。作者将仅使用 pipe 标准流的监督进程改为 `DETACHED_PROCESS`，实际目标继续使用 `CREATE_NO_WINDOW`；Job 接管后的 stdin 放行门及退出回收边界保持有效。失败报告 `artifacts/dev/dev-ac3ded65222341e480e04b342e804e48.json` 保留为 failed，没有改写成通过。

第 2 轮只定点复核这两项修复及 Windows 标志变更的直接影响，结论为两项缺陷均已关闭，无新增阻断项。已阅读真实回归用例：缺环境诊断不运行子命令也不创建 `.venv`；已有环境只调用两次已安装入口；正常父退出而孙进程继续运行时必须记录 `forced=true`，完成回收且保留外部 sentinel。只读核验 Linux 11 项结果 `artifacts/dev/b0-processes-review-linux.txt`，以及最终 Windows 标志修订后的 6 项进程用例结果 `artifacts/dev/b0-processes-review-windows.txt`，均为非空测试、无失败；Windows 最后的改动不影响 Linux 路径，因此保留已有 Linux 证据。

最新真实 jobs/Web 报告 `artifacts/dev/dev-cbd8fa299c19491a818b024c48e36981.json` 为 passed。记录显示诊断直接调用 `haruka-manage`，没有 `uv run`；API、Worker、Outbox、Flutter 四个目标均退出 0、`forced=false`、`remaining_app_processes=0`。本轮未重复未受影响的 API、数据库、前端或分发测试，未增加第 3 轮 review。
