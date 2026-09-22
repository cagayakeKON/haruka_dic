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

所有发布端口只绑定 loopback。Kafka 的本机和容器 listener 分开广播地址，自动创建 Topic 关闭；初始化只创建 `haruka-local-dev.smoke` 和 `haruka-test-integration.smoke`。单节点 PLAINTEXT Kafka、Redis DB 编号及名称前缀是本机开发设置，不构成生产鉴权或用户数据隔离。当前不预建业务 Topic、Job/Outbox、账号、迁移表或业务表。

## 配置与凭据

首次运行生成随机本机凭据，保存在 Git 忽略的 `.local/` 中，不输出到控制台。保留该目录和对应数据卷的配套关系；有旧卷但缺失凭据时拒绝重新生成，避免新密码与已有数据不一致。

- `.local/backend.env`、`.local/test.env`：应用配置，仅包含各环境运行账号、私有 Bucket 凭据和日志文件路径；由后端显式 `--config` 读取。
- `.local/dev-maintenance.env`、`.local/test-maintenance.env`：单独的数据库维护账号配置，只供后续受控迁移入口使用。
- `.local/secrets/grafana_password`：Grafana 用户 `haruka` 的密码。
- `.local/secrets/minio_password`：MinIO Console 用户 `haruka_local_root` 的密码；应用不使用该账号。
- `.local/credentials.json`、`.local/minio/`、`.local/secrets/`：初始化凭据材料，不应复制到应用发布包或日志。

PG 运行账号不是超级用户，无建库、建角色、Schema CREATE 或业务 DDL 权限；维护账号拥有对应数据库，默认授权未来维护账号创建的表/序列给运行账号。初始化只配置角色/数据库/Schema 权限，业务结构必须经受控 Alembic 迁移。此处不实现用户/ScopeContext/RLS 隔离。

脚本拒绝远程 Docker engine 和属于其他工作区的同名 Compose 项目；启动前检查首次所需端口。并发操作通过 `.local/operation.lock` 排他保护。若进程被强制结束留下锁，先确认其中记录的 PID 已退出，再手动移除该单一锁文件。

## 观测与验证

Alloy 同时采集 `.local/logs/dev*.jsonl`、`test*.jsonl` 和 `infra.jsonl`（统一安全 JSON）及本项目容器日志，再发送到本地 Loki。Docker API 仅通过不发布端口的 socket proxy 读取，禁用写请求；Alloy 的 discovery 和 relabel 都限制 `com.docker.compose.project=haruka-local`。不挂载 Docker socket 到应用或 Alloy。

配置中的 `dev.jsonl` / `test.jsonl` 是路径模板，后端实际派生为 `dev.<service>.<pid>.jsonl` / `test.<service>.<pid>.jsonl`，避免多进程争用同一个轮转文件。Alloy 按文件前缀分别绑定 `environment=dev/test`，不能将测试日志误标为开发事件。高基数关联字段留在 JSON 内容，不创建用户、请求或任务 ID 的 Loki 标签。开发 Loki 未启用认证，仅本机可达；这不是已完成的 MyHome 生产接入。

`smoke` 必须实际读到 PostgreSQL、Redis、两个 Kafka Topic、MinIO/Grafana 健康端点，并将唯一的正常 info 事件从 JSONL 经 Alloy 采入 Loki，同时验证 PostgreSQL 容器日志已到达。后端真实客户端连接、权限隔离、读写与关闭验证由本轮后端集成测试负责。

实现依据：[PostgreSQL 容器数据目录](https://docs.docker.com/guides/postgresql/immediate-setup-and-data-persistence/)、[Kafka 容器与 listener](https://kafka.apache.org/42/getting-started/docker/)、[Alloy Docker 日志](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.docker/)。
