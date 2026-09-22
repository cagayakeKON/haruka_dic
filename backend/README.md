# Haruka 后端

阶段1已有B0基础壳和基础设施切片。可安装包、四个正式CLI、PG/Redis/Kafka/MinIO客户端、统一资源组装与HTTP返回、离线OpenAPI导出已建立；完整B0尚未完成，实测见 [交付记录](../docs/delivery/reviews/2026-09-22-scaffold-infrastructure.md)。

先用Python3.13.6运行统一bootstrap。该命令按锁安装，不更新依赖。当前仓库内uv为`.tools/uv/uv.exe`，版本必须与工具清单一致；其他环境先安装清单指定版本。本机PATH的Python3.9不适用，以下显式选择锁定版本。

```powershell
.tools/uv/uv.exe run --python 3.13.6 python scripts/dev.py bootstrap --scope backend
.tools/uv/uv.exe run --python 3.13.6 python scripts/dev.py check --stage backend
.tools/uv/uv.exe run --python 3.13.6 python scripts/dev.py infra up
.tools/uv/uv.exe run --project backend --locked haruka-api --config dev/.local/backend.env
```

`--config` 显式指定配置文件；环境变量优先，不自动读取当前目录的 `.env`。配置检查只输出是否通过，不输出输入值。API 默认仅绑定回环地址。此切片仅允许 dev/test，staging/production 在持久依赖及安全接线完成前拒绝启动。

`GET /health/live` 表示应用循环存活；`GET /health/ready` 仍返回503，直到后续具备schema兼容检查及业务安全基础。基础设施配置启用时，启动会真实验证PG/Redis/Kafka/私有Bucket；失败清理此前取得的资源并停止启动。`backend/.env.example` 明确为不连接基础设施的离线壳模式，不能用于通过连接验收。

没有业务API，`/api/v1/*` 返回统一404。Worker/Outbox的 `--check-startup` 共用真实资源生命周期，Worker额外创建并关闭不自动提交offset的Consumer；尚不领取任务或发送Outbox。manage的db/seed/admin仍明确未实现，普通启动不建表、迁移、建Bucket或种子。

```powershell
.tools/uv/uv.exe run --project backend --locked haruka-worker --config dev/.local/backend.env --check-startup
.tools/uv/uv.exe run --project backend --locked haruka-outbox --config dev/.local/backend.env --check-startup
.tools/uv/uv.exe run --project backend --locked haruka-manage --config dev/.local/backend.env check-infrastructure
.tools/uv/uv.exe run --project backend --locked python -m app.contracts.export --output contracts
```

后端导出只读取无副作用的模型/路由，任何目录可调用已安装入口，不要求数据库或模型Key。SQLAlchemy使用asyncpg及每用例独立AsyncSession，Redis使用asyncio池；Kafka/MinIO在进程内专用线程串行执行有网络时限的阻塞SDK。所有连接都由bootstrap拥有和关闭，不在模块顶层实例化客户端，不共享当前用户或个人模型Key。业务授权、稳定幂等和Job/Outbox提交仍由后续服务层承担，基础adapter不构成可直接公开的业务接口。

依赖精确锁在pyproject/uv.lock；PEP517构建闭包另行固定版本/哈希。日志使用logging的安全JSON出口，正常事件和错误都采集，SDK原始消息/SQL参数不输出；输出故障也不会回显原始record。HARUKA_LOG_FILE指定绝对基础路径，实际文件按服务和PID拆分，供 [dev/Alloy](../dev/README.md) 采集，避免多进程竞争同一轮转文件。个人AI/TTS客户端须后续按用户注入，本轮不创建全局模型客户端或进行付费调用。
