# Haruka 后端

阶段 1 的 B0-foundation 工程基础切片。可安装包、四个正式 CLI、配置校验、API 生命周期、统一 HTTP 返回和离线 OpenAPI 导出已建立；完整 B0 尚未完成。

先用Python3.13.6运行统一bootstrap。该命令按锁安装，不更新依赖。当前仓库内uv为`.tools/uv/uv.exe`，版本必须与工具清单一致；其他环境先安装清单指定版本。本机PATH的Python3.9不适用，以下显式选择锁定版本。

```powershell
.tools/uv/uv.exe run --python 3.13.6 python scripts/dev.py bootstrap --scope backend
.tools/uv/uv.exe run --python 3.13.6 python scripts/dev.py check --stage backend
.tools/uv/uv.exe run --project backend --locked haruka-api --config backend/.env.example
```

`--config` 显式指定配置文件；环境变量优先，不自动读取当前目录的 `.env`。配置检查只输出是否通过，不输出输入值。API 默认仅绑定回环地址。此切片仅允许 dev/test，staging/production 在持久依赖及安全接线完成前拒绝启动。

`GET /health/live` 表示应用循环存活；`GET /health/ready` 返回 503，直到后续接入 PG、Redis 与 schema 检查。此时没有任何业务 API；`/api/v1/*` 返回统一 404。Worker/Outbox 可以检查配置，尝试实际运行明确失败；manage 的 db/seed/admin 同样明确未实现，不能用于迁移或初始化管理员。

```powershell
.tools/uv/uv.exe run --project backend --locked haruka-worker --config backend/.env.example --check-config
.tools/uv/uv.exe run --project backend --locked haruka-manage --config backend/.env.example check-config
.tools/uv/uv.exe run --project backend --locked python -m app.contracts.export --output contracts
```

后端导出只读取无副作用的模型/路由，任何目录可调用已安装入口，不要求数据库或模型 Key。依赖实际版本由 `uv.lock` 管理；PEP 517 构建器及其传递依赖在 `pyproject.toml` 单独固定版本/哈希。日志使用标准 logging 的 JSON 白名单出口，记录正常请求和失败分类，不输出请求正文、查询参数或异常原文。日志平台采集将在后续切片接入，当前 stdout 不代表 Grafana 验收。
