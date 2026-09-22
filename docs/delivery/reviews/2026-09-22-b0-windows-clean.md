# B0 Windows 干净检出记录

状态：Windows PowerShell 干净检出矩阵实际通过。本文只登记本次执行证据，不替代 [B0 完整矩阵](../milestones/scaffold.md) 或远端 CI；既有正式 wheel 安装、数据库、三端与质量检查证据仍保留各自来源身份。

## 输入与执行边界

被测代码固定为已提交 `f3b33c4accf978e87806558cfa1c46641ccc8745`，通过 Git bundle 建立全新 detached clone。没有复制作者已有 `.venv`、`node_modules`、`.dart_tool` 或应用包缓存；uv、npm、pub 使用本轮独立缓存。复用的是按工具清单校验的已安装 SDK，不宣称重新安装了 Windows 系统。所有开发命令均经实际 Windows PowerShell 执行，原始输出含 PowerShell 版本。

一次性工具位于 ignored 的 `artifacts/windows-clean-runner/`，没有成为应用依赖或长期公共框架。它复用已审 Linux runner 的失败诊断与报告辅助，以及已审开发进程所有权实现；启动前检查这些共享文件与选定提交一致。实际身份在 `artifacts/windows/clean-20260922-02/summary.json`：

| 输入 | SHA-256 |
| --- | --- |
| Git bundle | `87025700abbfa09c015104e5c735898e86214243cdc4eac706141ee62899ab50` |
| Windows runner | `5ad97306c00651d890e45d1f7aac6c576acf8fc3e87008005afc35224a295058` |
| PowerShell step | `95895be845a5d7aa9a435c328e3e33ec9b48539f3fd7c2c26fdd13d7b06481ec` |
| 复用 Linux runner | `5d695da799c7e4776ea3a405f698baa3d5d54ccbcd9ace7e3ea29f82f50327e9` |

仅逐一复制 `dev/.local/backend.env`、`test.env`、`test-maintenance.env` 三个既有文件至本轮私有临时目录。runtime 副本只重定向日志位置；维护配置只供只读 schema status。副本在 finally 删除，不把秘密文件放入证据。没有迁移、清库、种子、管理员初始化或供应商付费请求。不可达服务样本只修改私有副本中的 PG 端口，并持有本轮非监听 loopback socket；不停止或重配真实服务。

## 本次矩阵

- backend/docs/web 的 doctor 和 bootstrap 各执行两次，核对锁文件及已有本地配置不变。
- 实际 docs check 与连续两次 codegen check；本次只检查受管生成物，不借作者工作区文件成功。
- 新 editable 环境的 `direct_url.json`、实际发行包列表；`uv build --no-cache --require-hashes --verbose` 的新构建目录和成功结果。原日志的闭包 DEBUG 被宿主 `RUST_LOG=warn` 过滤，六项实际依赖的完整证据见下方独立补录。既有 Windows 正式制品安装验证 `artifacts/package-check/d803e2c88c594f62badce90616a8af61/report.json` 不重复执行。
- 缺 SDK、SDK 版本漂移、运行锁缺失/漂移、必需脚本缺失、构建版本/哈希缺失、无效配置、占用端口、不可达服务必须同时匹配失败状态与精确诊断。
- test runtime 的真实依赖/schema doctor、维护只读 status；core/jobs 各一轮真实 API 与 Flutter Web 生命周期，明确 `business_handlers=false`。结构化结果必须覆盖所需进程，退出 0、未强制清理且无应用残留，端口重新可绑定。
- core 就绪后通过本次唯一 `core-ui.stop` 保持窗口，供主任务执行正式 Web 管理路由的单项真实 UI 检查；该 UI 结果独立归档，停止标记本身不能代替 UI 通过证据。

## 工具 review 与修复

非作者主任务完成第 1 轮工具 review，检查完整 runner、PowerShell step 和 3 项工具回归。工具回归实际覆盖缺失/重复/失败生命周期结果拒绝、PowerShell 空格/中文参数及原生退出码传递、超时自有进程清理；Ruff、strict Pyright 和 PowerShell 语法检查通过。PowerShell step 仅移除外层进程 gate 的内部 `HARUKA_DEV_PROCESS_RUN_ID`，不清除用户 HARUKA 配置；主入口仍拒绝继承 HARUKA 覆盖值。

首次 `clean-20260922-01` 执行完成两轮安装、锁/用户配置不变、docs check、两次 codegen 及 editable 记录，但 fresh build 退出 2。缺陷是工具自设 `UV_NO_CONFIG=true`，同时禁用了已提交 `pyproject.toml` 内的构建约束；该失败不是应用锁不匹配，首轮结果不能计为完整通过。原始 `summary.json` 和 `clean-build-closure.log` 保留。

集中修复删除该变量，构造阶段拒绝继承 `UV_NO_CONFIG`/`UV_CONFIG_FILE`，只检查已知用户/系统 uv 配置文件是否存在，不读取内容；本机两处均不存在。位置依据 [uv 官方配置说明](https://docs.astral.sh/uv/configuration/files/)。没有修改锁文件或降低 hash 要求。新增 1 项环境构造回归、Ruff 与 strict Pyright 通过，独立 fresh hash 构建探针退出 0，证据 `artifacts/windows/build-probe-20260922-01/`。

非作者主任务第 2 轮定点复核上述修复与探针后通过；本次不重开已关闭的开发编排 review，不机械增加第 3 轮。第二次使用相同被测提交、全新 clone 和缓存，证据目录 `artifacts/windows/clean-20260922-02/`。

## 最终实际结果

第二次执行进程退出 0；`summary.json` 的 `passed=true`、`bootstrap_idempotent=true`，共 32 条命令记录，其中 10 条预期失败样本均匹配结构化诊断。这里的 32 是命令数，不是质量测试用例数。工具保持 `reviewed=false`，不自行签署独立 review；`remote_ci_executed=false`。PowerShell 原始版本为 `5.1.26100.9539`。

以下相对证据路径均位于 `artifacts/windows/clean-20260922-02/`，UI 单项除外：

| 验证范围 | 实际结果与原始记录 |
| --- | --- |
| SCF-B0-01 干净初始化 | backend/docs/web 的 doctor、bootstrap 各两次成功；锁文件与既有用户配置摘要不变，见 `summary.json`、`doctor-*.log`、`bootstrap-*.log`。 |
| 失败分类 | 缺运行锁、缺必需脚本、builder 版本漂移、缺构建哈希、运行锁漂移、缺 Flutter、无效配置、占用端口、SDK 版本漂移、依赖不可达全部按预期拒绝；诊断与命令退出值逐项见 `summary.json` 和同名日志。 |
| SCF-B0-02 editable 与构建闭包 | `editable-install.log` 记录实际 `direct_url.json` 的 editable 标记和安装发行包；`clean-build-closure.log` 保留启用哈希校验的全新 wheel/sdist 构建成功输出。六项依赖详情由下方独立补录提供，原日志不作为完整闭包证据。 |
| SCF-B0-05 生成物 | `codegen-check-1.log`、`codegen-check-2.log` 连续通过；`final-tracked-tree.log` 退出 0，受管生成物和源码未漂移。 |
| 真实依赖/schema | `runtime-doctor.log` 检查 test 的 jobs 资源；`maintenance-status.log` 经维护入口只读检查 schema，均退出 0。 |
| core/Web 生命周期 | `application-artifacts/dev/dev-1078c40da2ff4d4a821211e2ab48e903.json` 记录显式 stop marker 请求；frontend/API 均退出 0、`forced=false`、`remaining_app_processes=0`。 |
| jobs/Web 生命周期 | `application-artifacts/dev/dev-f426d23beba04d58b7182b4d1531fc88.json` 记录 frontend/outbox/worker/API 均退出 0、`forced=false`、`remaining_app_processes=0`；Worker/Outbox 仅验证生命周期，`business_handlers=false`。 |

主任务在同一个干净检出的 core/Web 进程上执行正式 `lib/main.dart` 的 `/admin` 路由进入和返回主页。`artifacts/e2e/live-c81d1d70-17c4-4fc0-900b-9174f62e3503/results.json` 记录 1 项通过，unexpected/skipped/flaky 均为 0，`errors=[]`；总耗时 17.3 秒。主任务随后创建本轮 `core-ui.stop`，上述 core 结构化记录确认正常停止。此项不重复先前已通过的真实 health UI 检查。

新构建产物位于 `audit-dist/`，SHA-256 如下：

| 产物 | SHA-256 |
| --- | --- |
| `haruka_backend-0.1.0-py3-none-any.whl` | `43a06279344c81cd4525a8da95276bb45ea16d596d991ff7c991021a655ebfe7` |
| `haruka_backend-0.1.0.tar.gz` | `6294dd0c17ccf6d240417cb080e1f962eeafcb4b638e05d1dc600db957e8674c` |

每种 profile 停止后，runner 实际确认 API `18080` 与 Web `5173` 可以重新绑定；最终源码差异检查和锁/用户配置摘要校验通过。退出后核对本轮 3 个私密配置副本及无效配置样本均已删除。首次失败证据、定点构建探针和本次完整结果分开保留；本记录不宣称已执行远端 CI、重新验收原生端或实现 B2 业务 handler。

## 构建闭包独立补录

最终独立 review 指出原构建日志只有 PowerShell 版本、Building 和 Successfully built，未保存实际安装的六项 PEP 517 依赖版本。检查确认宿主继承的 `RUST_LOG=warn` 过滤了 uv 的 DEBUG；不存在可追补的原始 stderr。原始执行与报告保持原样，不把成功退出视为完整闭包记录。

仅补执行一次候选 `f3b33c4` 的 Windows 隔离构建，继续使用 clean02 的干净 checkout，证据位于 `artifacts/windows/build-closure-20260922-01/`。命令为 `uv --verbose --color never build --no-cache --require-hashes --force-pep517 --python <固定 Python 3.13.6> --out-dir <新目录>`，完整参数见 `summary.json`。子进程移除日志过滤和环境覆盖，保留项目构建约束；新 TEMP 目录、无用户 site-packages，独立保存 `stdout.log` 与 `stderr.log`。没有重跑 clean、应用、UI 或其他测试。

`stderr.log` 第 86、128 行分别记录 sdist 与 wheel 的实际依赖安装；观察器同时从这两个临时构建环境读取 `pyvenv.cfg` 与已安装 `METADATA`，记录版本和元数据 SHA-256。两处均为 `include-system-site-packages = false`，实装依赖均精确为下列六项；每项发布文件的 SHA-256 约束从候选 `pyproject.toml` 读取并完整写入 `summary.json`，构建启用 `--require-hashes`。

| 已安装构建依赖 | 实际版本 |
| --- | --- |
| hatchling | 1.32.4 |
| packaging | 26.3 |
| pathspec | 1.1.1 |
| pluggy | 1.6.0 |
| tomlkit | 0.15.1 |
| trove-classifiers | 2026.9.21.13 |

构建退出 0；源码工作区和项目文件哈希未变。`ownership.json` 记录退出 0、`forced=false`、`remaining_app_processes=0`。新 wheel/sdist 的哈希与上表 clean02 产物完全相同。非作者主任务已读取补录脚本、实际 stderr、隔离环境快照与产物哈希，窄范围核查无阻断；最终独立验收结论由 B0 汇总记录维护。

| 补录证据 | SHA-256 |
| --- | --- |
| `capture.py` | `9f62aa4bd61ab77536ce7780063ebbc5954cde3c1257d47927b854312521d236` |
| `summary.json` | `8838ceac50acc8bc390a67fd65439d20148799f0f8787731f8850826c65a2c38` |
| `stderr.log` | `b979994c1edabb94afa2b65de4ebcdfece84de8aef0f34a5756652c675d24f3a` |
| `stdout.log`（原始空输出） | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
