# Linux 本地干净环境验收

范围为 [SCF-B0-01/02/03 的 Linux 项](../../docs/delivery/milestones/scaffold.md)。这里运行本地 Docker Desktop Linux shell；没有远端 CI 执行记录，也不代表整个 B0 已验收。

[toolchain.lock.json](toolchain.lock.json) 固定 Python 基础镜像 digest、Debian 包索引快照及 uv/Node/Flutter 官方下载 SHA256。版本必须与 [项目工具链](../../tools/toolchain.json) 一致，镜像内下载锁必须与检出版本完全一致。Flutter 来自 [官方 Linux release 清单](https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json)。SDK 镜像不包含项目代码、应用依赖、用户配置或测试业务结果。

先在仓库根构建，记下真实的 image ID：

```powershell
docker --context desktop-linux build --platform linux/amd64 --tag haruka-ci-linux:20260922 dev/ci
docker --context desktop-linux image inspect haruka-ci-linux:20260922 --format '{{.Id}}'
```

runner 本身须先经 review 并提交。随后从当前已提交 HEAD 构造 Git bundle，传入新的输出目录及上一条命令返回的完整 `sha256:` image ID；下列变量须使用实际值，不以工作区未提交文件代替提交证据：

```powershell
backend/.venv/Scripts/python.exe dev/ci/run.py --commit $commit --image $imageId --test-config dev/.local/test.env --dev-config dev/.local/backend.env --maintenance-config dev/.local/test-maintenance.env --output $newEvidenceDirectory
```

`run.py` 拒绝 Docker 环境覆盖值，要求当前 context 为 `desktop-linux`，endpoint 精确为本机 Linux engine 的 named pipe；后续命令显式选定该 context。容器不挂 Docker socket，不使用 privileged 或 host network，也不向宿主发布端口。仅挂载本次 Git bundle、三个明确配置文件（只读）和新证据目录。完整 `.local`、宿主 checkout、`.venv`、`node_modules` 均不挂载。容器从 bundle 检出指定 commit，验证干净工作区后安装应用依赖。

配置原件不写入证据。runtime 配置副本位于容器私有 `/work/private`，只替换日志路径；dev/test 身份、账号及凭据保持原值。维护配置只用于安装包外只读 schema 状态检查。四个 loopback TCP bridge 仅向 `host.docker.internal` 的 Haruka 端口 15432/16379/19092/19100 转发，以兼容 Kafka 的 loopback advertised listener；没有修改业务目标白名单或共享基础设施。

执行范围固定如下，首次失败立即退出并保留失败报告；新尝试必须使用新目录，不能覆盖前次失败：

- backend/docs/web 的 doctor 与 bootstrap，各 bootstrap 两次；锁、用户配置和最终 Git tracked diff 必须保持不变。实际调用 docs check 和两次 codegen check。
- 固定 [执行矩阵](execution_matrix.json) 的 34 项开发命令/进程测试与 36 项后端生命周期用例。缺节点、额外节点、skip/xfail 或失败不能通过；不重复质量门禁 32 项。
- 缺 SDK、缺运行锁、缺必需脚本、构建版本/哈希不符、运行锁漂移、无效配置、占用端口与不可达服务失败样本。
- 空缓存 hash 锁定构建的详细日志，editable 安装和实际包清单；正式分发验证脚本在 checkout 外安装 wheel、读取 sdist 资源并启动四个正式入口。
- core/jobs 的真实 API 与 Flutter Web 启动各两轮，检查结构化子进程结果、端口释放及 bridge 无遗留连接；API/Worker/Outbox 分别通过真实 SIGTERM 有界退出。Worker/Outbox 只验证生命周期，业务 handler 仍属于 B2。

原始命令/退出码、SDK/系统包摘要、JUnit 与应用报告保留在本次证据目录。`summary.json` 的 `reviewed` 始终为 false；独立 reviewer 应消费原始证据，再按质量门禁的 procedure schema 登记验收，不能把脚本自报结果当独立 review。

工具单元的局部检查：

```powershell
backend/.venv/Scripts/python.exe -m unittest discover -s dev/ci -p test_runner.py -v
.tools/uv/uv.exe run --project backend --locked ruff check --config backend/pyproject.toml dev/ci
.tools/uv/uv.exe run --project backend --locked pyright --project dev/ci/pyrightconfig.json
```
