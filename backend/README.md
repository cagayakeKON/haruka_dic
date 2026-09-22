# Haruka 后端

阶段1已有B0基础壳、基础设施及数据库初始化切片。可安装包、四个正式CLI、资源组装、统一HTTP返回、受控迁移/种子/首管理员和离线契约导出已建立；完整B0尚未完成，实测见 [数据库交付记录](../docs/delivery/reviews/2026-09-22-b0-identity.md)。

先用Python3.13.6运行统一bootstrap。该命令按锁安装，不更新依赖。当前仓库内uv为`.tools/uv/uv.exe`，版本必须与工具清单一致；其他环境先安装清单指定版本。本机PATH的Python3.9不适用，以下显式选择锁定版本。

```powershell
.tools/uv/uv.exe run --python 3.13.6 python scripts/dev.py bootstrap --scope backend
.tools/uv/uv.exe run --python 3.13.6 python scripts/dev.py check --stage backend
.tools/uv/uv.exe run --python 3.13.6 python scripts/dev.py infra up
.tools/uv/uv.exe run --project backend --locked haruka-manage db upgrade --maintenance-config dev/.local/dev-maintenance.env --migrations-dir "$PWD/backend/alembic"
.tools/uv/uv.exe run --project backend --locked haruka-manage seed apply --maintenance-config dev/.local/dev-maintenance.env
.tools/uv/uv.exe run --project backend --locked haruka-api --config dev/.local/backend.env --port 18080
```

`--config` 显式指定配置文件；环境变量优先，不自动读取当前目录的 `.env`。配置检查只输出是否通过，不输出输入值。API 默认仅绑定回环地址。此切片仅允许 dev/test，staging/production 在持久依赖及安全接线完成前拒绝启动。

`GET /health/live` 表示应用循环存活；`GET /health/ready` 实查数据库结构与当前profile所需依赖，成功200、失败503。`HARUKA_RESOURCE_PROFILE=core`只要求PG/Redis，默认jobs另检查Kafka/私有Bucket。运行账号必须是对应数据库的专用runtime角色，启动时检查实际连接身份、禁止的DDL/审计修改权限和schema；失败清理此前资源并停止启动。`backend/.env.example` 是不连接基础设施的离线壳模式，始终不报告ready。基础设施就绪不代表登录或业务授权已实现。

没有业务API，`/api/v1/*` 返回统一404。Worker/Outbox的 `--check-startup` 共用资源生命周期，Worker额外创建并关闭不自动提交offset的Consumer；尚不领取任务或发送Outbox。普通启动不建表、迁移、建Bucket或种子。

需要保持进程时使用 `--lifecycle-only`，它要求启用jobs资源，并明确报告 `business_handlers=false`；API/Worker/Outbox支持独立绝对未来文件 `--shutdown-file` 供开发编排请求优雅退出。日常前后端联合启动使用[统一开发入口](../docs/engineering/development.md#当前可运行开发进程编排)，优先选择已登记的备用18080，避免本机8000系统保留段。

维护使用独立凭据：`haruka-manage db status/upgrade`还要求`--migrations-dir`为绝对路径；`seed apply`只创建缺失初始目录，不覆盖人工授权。`admin init --maintenance-config <文件> --email <邮箱>`在受控终端隐藏输入密码，拒绝回显回退、已有普通账号提权或第二次首管理员创建。已初始化同一账号的重放不修改密码。迁移通过同一物理PG连接持锁和执行DDL，禁止裸Alembic绕过；同版本sdist包含alembic附件，安装运行不依赖checkout。

```powershell
.tools/uv/uv.exe run --project backend --locked haruka-worker --config dev/.local/backend.env --check-startup
.tools/uv/uv.exe run --project backend --locked haruka-outbox --config dev/.local/backend.env --check-startup
.tools/uv/uv.exe run --project backend --locked haruka-manage --config dev/.local/backend.env check-infrastructure
.tools/uv/uv.exe run --project backend --locked python -m app.contracts.export --output contracts
```

后端导出只读取无副作用的模型/路由，任何目录可调用已安装入口，不要求数据库或模型Key。SQLAlchemy使用asyncpg及每用例独立AsyncSession，Redis使用asyncio池；Kafka/MinIO在进程内专用线程串行执行有网络时限的阻塞SDK。所有连接都由bootstrap拥有和关闭，不在模块顶层实例化客户端，不共享当前用户或个人模型Key。业务授权、稳定幂等和Job/Outbox提交仍由后续服务层承担，基础adapter不构成可直接公开的业务接口。

依赖精确锁在pyproject/uv.lock；PEP517构建闭包另行固定版本/哈希。日志使用logging的安全JSON出口，正常事件和错误都采集，SDK原始消息/SQL参数不输出；输出故障也不会回显原始record。HARUKA_LOG_FILE指定绝对基础路径，实际文件按服务和PID拆分，供 [dev/Alloy](../dev/README.md) 采集，避免多进程竞争同一轮转文件。个人AI/TTS客户端须后续按用户注入，本轮不创建全局模型客户端或进行付费调用。
