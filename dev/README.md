# 本地开发基础设施

`dev/` 是开发 Compose、初始化和观测配置的唯一入口，使用独立的 `haruka-local` 项目。它不复用或修改本机其他项目的容器、卷与凭据，不连接 MyHome 或生产服务。镜像的版本和 digest 锁在 [工具链](../tools/toolchain.json) 的 `development_images`。

从仓库根目录使用已锁定的 Python 3.13.6：

```text
python scripts/dev.py infra up
python scripts/dev.py infra status
python scripts/dev.py infra smoke
python scripts/dev.py infra down
```

也可以直接执行 `python dev/infra.py <action>`。`init` 只生成本地配置；`up` 完成生成、Compose 健康检查、数据库/对象存储/Topic 初始化和真实探针。`down` 停止当前仓库的开发容器并保留所有数据卷，不提供删除卷选项。重复启动不会重置密码、删除数据或覆盖手工修改的文件；发现配置冲突会退出并保留原文件。

| 服务 | 宿主机地址 | 用途 |
| --- | --- | --- |
| PostgreSQL 18 | `127.0.0.1:15432` | `haruka_dev` 与 `haruka_test` 两个独立数据库 |
| Redis 8.8 | `127.0.0.1:16379` | dev/test 分别用 DB 0/1，业务仍须加资源/账号前缀 |
| Kafka 4.2.1 | `127.0.0.1:19092` | 单节点 KRaft，容器使用 `kafka:9092` |
| MinIO S3 | `http://127.0.0.1:19100` | 私有 dev/test Bucket；应用凭据限各自 Bucket |
| MinIO Console | `http://127.0.0.1:19101` | 本机开发管理界面 |
| Loki | `http://127.0.0.1:13100` | 隔离的本地日志查询端点 |
| Grafana | `http://127.0.0.1:13000` | 已配置 Haruka Local Loki 数据源 |

所有发布端口只绑定 loopback。Kafka 的本机和容器 listener 分开广播地址，自动创建 Topic 关闭；基础设施初始化只创建两个smoke Topic。单节点 PLAINTEXT Kafka、Redis DB 编号及名称前缀不构成生产鉴权或用户隔离。Compose不建业务表或用户；数据库结构和授权种子另经 [后端受控维护入口](../backend/README.md) 执行，普通API启动不迁移。

## 配置与凭据

首次运行生成随机本机凭据，保存在 Git 忽略的 `.local/` 中，不输出到控制台。保留该目录和对应数据卷的配套关系；有旧卷但缺失凭据时拒绝重新生成，避免新密码与已有数据不一致。

- `.local/backend.env`、`.local/test.env`：应用配置，仅包含各环境运行账号、私有 Bucket 凭据和日志文件路径；由后端显式 `--config` 读取。
- `.local/dev-maintenance.env`、`.local/test-maintenance.env`：单独的数据库维护账号配置，只供受控迁移/种子/管理员入口使用。
- `.local/secrets/grafana_password`：Grafana 用户 `haruka` 的密码。
- `.local/secrets/minio_password`：MinIO Console 用户 `haruka_local_root` 的密码；应用不使用该账号。
- `.local/credentials.json`、`.local/minio/`、`.local/secrets/`：初始化凭据材料，不应复制到应用发布包或日志。

模型任务切片使用 `python -m dev.isolated_app_run prepare --model-mode fake` 创建专属测试schema、账号/密钥材料和Kafka Topic，再经同一 `build-web` 与 `serve --web` 启动正式API/模型Worker/Outbox。默认不带该选项仍是既有core模式。`fake`仅替换供应商边界，PG/Redis/Kafka及任务事实保持真实；运行配置与Topic不进入产品包。

真实供应商样本须先停该run全部进程并结束或取消所有未完成Job，使用 `set-model-mode --run-id <run> --mode live` 显式切换组装后再启动；该命令不接收Key、不创建attempt，不凭切换宣称能力已验证。Key仍经正式本人凭据UI保存。测试调用按当期授权次数执行，不能因为跨端验证或重连重发。Topic创建/清理先检查本机Docker及run ledger，清理只删除当前run登记的 `<instance_id>.jobs`，不操作其他项目或既有环境Topic。

PG 运行账号不是超级用户，无建库、建角色、Schema CREATE 或业务 DDL 权限；维护账号拥有对应数据库，默认授权未来维护账号创建的表/序列给运行账号。初始化只配置角色/数据库/Schema 权限，业务结构必须经受控 Alembic 迁移。此处不实现用户/ScopeContext/RLS 隔离。

脚本拒绝远程 Docker engine 和属于其他工作区的同名 Compose 项目；启动前检查首次所需端口。并发操作通过 `.local/operation.lock` 排他保护。若进程被强制结束留下锁，先确认其中记录的 PID 已退出，再手动移除该单一锁文件。

隔离应用 run 在已确认停止后可选 `python -m dev.isolated_app_run serve --run-id <run_id> --web --fault-proxy --stop-file <该run的新绝对路径>`，此时正式 API 由本机 `18082` 运行，受控故障传输占原 `18081`，现有 Web、Windows、Android 客户端地址不变；不加该选项仍为 `18081` 直连。只有服务处于这一模式时，`python -m dev.local_api_fault_proxy arm --run-id <run_id> --mode <before_503|after_response_drop|delay_response> --method <GET|POST> --path <固定API路径>` 才能发布一次受控规则，返回不含秘密的规则 UUID。`before_503` 仅限现有三种 frontend-logs POST，允许 `--count 1..20`、`--duration-seconds 1..120`；`after_response_drop` 仅限 collections POST 且上游 2xx 完成后断响应；`delay_response` 仅限 materials/collections GET，`--delay-ms` 最多 5000，均按不含查询串的路径匹配。`disarm --run-id <run_id> --rule-id <规则UUID>` 可撤销尚未用尽的规则。私有控制文件只归该 run 所有；客户端和管理端日志 POST 的503回执可额外保存受限批次内最多20个规范事件 UUID，其余仅含 run/规则/请求关联 UUID、固定方法与路径、上游状态和是否注入，不保存正文、属性、Token、Cookie、查询串；运行矩阵仍须通过真实 UI 与业务数据证明结果。

`build-web --replace` 在run停止后先复制完整release到 `web.next`，旧 `web` 移至该run独立的 `web.previous.*` 后发布新包；Windows目录锁会有限重试，失败时尽力恢复旧版且保留staging。若进程在发布中途退出，先确认ledger为stopped及服务进程均已退出，再用 `python -m dev.isolated_app_run recover-web --run-id <run_id> --expected-main-sha <已核对的main.dart.js SHA-256> [--replace]` 受控恢复；入口要求staging与当前Flutter构建的文件集合及主程序一致，并复核包内run身份/API地址。旧证据目录不会自动删除，校验失败不能启动或宣称新包已发布。

## 观测与验证

Alloy 同时采集 `.local/logs/dev*.jsonl`、`test*.jsonl` 和 `infra.jsonl`（统一安全 JSON）及本项目容器日志，再发送到本地 Loki。Docker API 仅通过不发布端口的 socket proxy 读取，禁用写请求；Alloy 的 discovery 和 relabel 都限制 `com.docker.compose.project=haruka-local`。不挂载 Docker socket 到应用或 Alloy。

配置中的 `dev.jsonl` / `test.jsonl` 是路径模板，后端实际派生为 `dev.<service>.<pid>.jsonl` / `test.<service>.<pid>.jsonl`，避免多进程争用同一个轮转文件。Alloy 按文件前缀分别绑定 `environment=dev/test`，不能将测试日志误标为开发事件。高基数关联字段留在 JSON 内容，不创建用户、请求或任务 ID 的 Loki 标签。开发 Loki 未启用认证，仅本机可达；这不是已完成的 MyHome 生产接入。

本地 PostgreSQL 的 Docker 日志先进入独立的 Alloy 安全解析支路，原文不直通 Loki。支路只接受已知 `haruka_dev` / `haruka_test` 数据库和 Haruka 开发、测试、受控维护应用名，提取 `database_name`、`application_name`、`backend_pid`、`sqlstate` 与固定严重程度，重建不含错误正文的 JSON；未匹配的行仅输出固定 `database.engine.parse_error` 事件。这些连接字段保留在正文，不成为高基数索引标签。Compose 为本地 PG 配置含数据库、应用名、PID、SQLSTATE 的 `log_line_prefix`，开启授权连接和断开事件，使用 `terse` 错误格式；`log_statement=none`、绑定参数长度 0 和 `log_min_error_statement=panic` 继续生效。慢查询原始语句日志和引擎锁等待日志未开启，应用层 SQLAlchemy 记录安全的查询计时与失败分类。

受控隔离 run 的合成错误可用 `python -m dev.postgres_log_probe --run-id <32位小写十六进制> --label <新标签>` 验证：只向本地 PG 发送一次无数据写入的非法 UUID，报告原始 Docker 源是否出现合成标记，以及 Loki 是否保留同一 PID/SQLSTATE 而不含该标记；报告不保存标记或原始错误正文。`dev.alloy_recovery_probe` 另用于服务运行时验证 Alloy 暂停期间的正式 API 事件能否按同一 event ID 补采，须与正在使用该隔离 run 的测试方协调窗口。现有合成错误证明仅覆盖 PG 安全采集，不能代替真实 UI 密码、邮件 Token 或跨端观测验收。

邮件 Worker 的独立重试/重启可用 `backend/.venv/Scripts/python.exe -m dev.mail_worker_lifecycle_probe --output artifacts/dev/<新的证明文件>.json` 验证。工具新建并清理自己的随机测试 schema 与资源命名空间，经正式管理/API 路由开放注册并产生持久待投递邮件；先在未监听的本机 SMTP 端口运行一次正式 Worker，核对失败分类和持久重试时间，再启动该 run 私有的 loopback 捕获并在重试时间后运行新的 Worker，最后另启 Worker 核对不重复投递。探针最多等待持久重试时间30秒，超过则明确记为探针不支持，不提前误判为产品失败。报告只含状态、尝试次数、固定事件和进程信息，不保存邮件正文、链接或凭据；它不证明外部 SMTP 送达。

真实合成账号完成可见界面流程并生成私有 actor 文件后，可用 `python -m dev.secret_absence_proof --run-id <run> --actor-file dev/.local/b1/<run>/<actor文件>.secret --output artifacts/dev/<新的证明文件>.json` 检查**该文件当前密码**和本机捕获的邮件操作 Token 是否原样出现在本 run 的全部应用 JSONL及带精确实例 ID 的 Loki 记录。工具从 run 创建时间查询完整 Loki 窗口，要求最早带实例 ID 的本地事件也可在 Loki 找到；窗口不完整、超过100,000行或本地/Loki任一侧128MiB、文件不可用均失败。Loki按五分钟分片查询，单片达到5,000条视为截断，run超过24小时拒绝。极早的启动日志可能尚无实例 ID，仍在本地全文检查中并在报告单独计数，不宣称 Loki 实例过滤覆盖它们。报告只写计数和布尔结果，不保存秘密；它不覆盖该账号以前用过的全部密码，也不代替已执行操作的业务/授权证明。

个人模型实测后，`python -m dev.model_log_proof --run-id <run> --output artifacts/dev/<新的证明文件>.json` 从标准输入接收本人测试Key，仅在内存检查该Key和固定朗读样本文字是否出现在上述完整本地/Loki窗口；不得把Key写入命令参数、临时文件或shell历史。报告只包含缺失布尔值、计数和白名单模型事件，不保存Key、摘要或日志正文。事件计数不等于任务提交或用量证明，仍需核对持久Job/Stage/Run/attempt；其他供应商回复和历史Key另按实际样本验证。

受控接收故障实际发生后，可从私有503回执读取目标事件 UUID，再运行 `python -m dev.telemetry_recovery_proof --run-id <run> --rule-id <规则32位hex> --event-id <目标事件UUID> --expected-user-id <已验证账号UUID> --audience <client|admin> --output artifacts/dev/<新的证明文件>.json`。证明要求目标 UUID 确实在该受众正式日志路径的故障批次中，故障后以同一账号/受众被接收，并在 Loki 出现同一事件 UUID；客户端事件带 operation_id，收藏事件还要求有同操作的服务端提交日志。只显示安全关联字段，不能用另一受众或另一事件的回执替代；它不证明所有队列事件都成功送达。

`smoke` 必须实际读到 PostgreSQL、Redis、两个 Kafka Topic、MinIO/Grafana 健康端点，并将唯一的正常 info 事件从 JSONL 经 Alloy 采入 Loki，同时验证 PostgreSQL 容器日志已到达。后端真实客户端连接、权限隔离、读写与关闭验证由本轮后端集成测试负责。

实现依据：[PostgreSQL 容器数据目录](https://docs.docker.com/guides/postgresql/immediate-setup-and-data-persistence/)、[Kafka 容器与 listener](https://kafka.apache.org/42/getting-started/docker/)、[Alloy Docker 日志](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.docker/)。

本人模型切片的本地 Web 也支持同源 HTTP：停止该 run 后执行 `python -m dev.isolated_app_run set-web-transport --run-id <run> --transport http`，再 `build-web --run-id <run> --replace` 并重新 `serve --web`。入口为 `http://localhost:18443`，端口仍只绑定 loopback；localhost 开发白名单、Origin/CSRF/鉴权保持有效，正式包仍要求 HTTPS，Secure Cookie 属性不放宽。网关只为既有任务事件端点透传 WebSocket Upgrade；所有者与来源授权仍由 API 检查。邮件进程使用同 run 的私有 core 配置，模型进程使用 jobs 配置，停机确认后删除临时邮件配置。
