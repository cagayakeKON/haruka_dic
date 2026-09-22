# B0 基础设施切片记录

日期：2026-09-22。所属阶段：阶段1中的B0-infrastructure小阶段，接续 [B0-foundation](2026-09-22-scaffold-foundation.md)。本轮用户明确要求初始化基础设施客户端、所有开发Compose放入dev/，并启动本机所需服务。完整B0仍未签署，B1/B2未实现。

## 范围与实现

- `dev/compose.yaml`、初始化/操作脚本及观测配置：独立haruka-local项目，PG18、Redis8.8、Kafka4.2.1、MinIO、Alloy、Loki、Grafana和只读Docker socket proxy；版本及镜像digest锁在tools/toolchain.json。已有其他项目容器不在操作范围。
- `app/adapters`及bootstrap：SQLAlchemy异步engine/session factory、Redis asyncio池、Kafka Producer/Consumer及MinIO客户端。无模块级连接、配置读取或线程启动；逐项注册释放，部分初始化失败逆序关闭。同步SDK使用专用单线程执行器，SDK网络时限约束在途调用；关闭时即使等待者取消，也完成SDK清理并传播取消。
- API、Worker、Outbox及manage共用组装。Worker/Outbox仅实现真实 `--check-startup`，尚无业务常驻handler；Consumer禁用自动提交和自动存储offset。普通启动仅查询依赖，不做迁移、种子或Bucket/Topic创建。
- 本地PG dev/test独立库、非超级运行账号和单独维护账号；运行账号仅CONNECT、public USAGE及后续表DML，未授CREATE/TEMP。MinIO分别私有Bucket与受限账号，应用不使用root。Redis分DB/命名空间，Kafka独立合成Topic和随机consumer group；这不是用户RBAC或生产鉴权。
- `scripts/dev.py infra init|up|status|down|smoke`及doctor infra、check infrastructure。首次生成随机秘密，仅存Git忽略的dev/.local；重复启动不覆盖文件或删除卷，down保留卷。固定实际Docker本机端点，拒绝远程或其他工作区的同名项目，清理会覆盖Compose受管配置的父进程变量。
- 安全JSON同时输出stdout与按服务/PID分开的本地轮转文件，防止多进程竞争。文件/流写失败不回显原始record或异常。Alloy采集本项目容器及dev/test各自日志，正常info进入Loki；Grafana预置本地数据源，不等于MyHome正式接入。

连接和配置详情以 [开发指南](../../engineering/development.md)、[后端入口](../../../backend/README.md)、[dev入口](../../../dev/README.md) 为准。`/health/ready`仍为503，因为schema兼容、迁移和业务安全基础尚未交付；不能用依赖连通替代就绪。

## 依赖与导入依据

本轮只增加正在使用的基础设施SDK，精确版本与传递依赖/hash见backend/pyproject.toml、uv.lock；PEP517构建闭包沿用单独锁定。未增加另一套Kafka/ORM/Agent框架，也未初始化全局个人模型客户端。

| 依赖 | 用途与选择依据 |
| --- | --- |
| SQLAlchemy asyncio 2.0.54、asyncpg 0.31.0 | 沿用架构的异步PG方案，engine显式dispose，每次用例独立AsyncSession，连接UTC/public、限制超时、关闭echo/参数回显。MIT/Apache-2.0；本机Python3.13 Windows wheel实际安装通过 |
| redis 8.1.0 | 官方redis-py asyncio连接池，显式aclose，连接/读写超时及无自动写重试。MIT；纯Python客户端，无第二套aioredis |
| confluent-kafka 2.15.1 | 沿用架构推荐的librdkafka绑定，Producer启用幂等和acks=all，delivery callback确认投递，有限flush及明确close；Consumer不自动ack。Python客户端Apache-2.0，bundled librdkafka按其许可证分发；本机3.13二进制wheel通过 |
| minio 7.2.20、urllib3 2.8.0 | 直接使用MinIO维护的S3 SDK并显式拥有HTTP池；不引入第二套boto3/stubs依赖树。Apache-2.0/MIT；同步调用在线程执行，响应关闭并release_conn，池在结束时清理 |

版本、维护与平台信息来自本轮PyPI元数据及实际锁定安装，未批准第三方sdist构建。Confluent的close和Redis的ping在已锁SDK声明中存在窄类型缺口，用准确Protocol边界处理，不全局关闭strict或使用Any强转。

实践依据：[SQLAlchemy异步会话与dispose](https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html)、[redis-py asyncio池释放](https://redis.io/docs/latest/develop/clients/redis-py/async/)、[Confluent flush/close与Consumer](https://docs.confluent.io/platform/current/clients/confluent-kafka-python/html/index.html)、[MinIO Python客户端](https://minio-py.min.io/)。这些链接说明SDK用法，具体行为仍由锁定版本与实际验证决定。

## 必要检查及实际结果

影响仅限后端资源组装、开发基础设施、日志与工具入口。本轮不修改Flutter代码，不重跑三端UI或后续业务验收，不把局部用例数量当成全仓覆盖率。

| 检查 | 实际证据 |
| --- | --- |
| 导入、设置、生命周期、既有HTTP契约 | 初次48项unit/contract通过；日志/导入/契约变更后22项定点通过，整个释放栈及SDK关闭取消修复后20项定点通过。导入所有app模块时禁止socket connect及线程start，schema导出不依赖配置 |
| 后端静态 | Ruff格式/规则、Pyright strict通过；运行与PEP517依赖保持完整锁定 |
| 真实基础设施 | PG独立连接、UTC/public与非超级/无CREATE；Redis短期key读写清理；Kafka真实Producer→Consumer；MinIO写读删除及匿名403；test凭据访问dev数据库SQLSTATE42501、dev Bucket AccessDenied；Redis不可达安全失败，退出无线程残留。3项集成通过 |
| Compose与工具 | scripts单测及dev安全坏样本通过；doctor核对本机Docker29.5.2/Compose5.1.4，重复up不覆盖配置；smoke实际检查PG响应、Redis PONG、Topic、MinIO/Grafana及Loki入库 |
| 安装制品 | 干净缓存构建及运行依赖hash安装，仓库外非editable wheel的4个正式入口真实连接/关闭；离线导出及错误构建hash拒绝。日志/关闭修复后的最终报告artifacts/package-check/35f477560b1c438c9dfd7111625fa013/report.json |
| 日志链路 | dev/test正常info分别带正确environment进入Loki，本项目PG容器日志可查询；service标签包含8个基础设施服务及api/worker/outbox/manage/integration，未出现其他项目服务 |
| 局部检查入口 | check infrastructure报告artifacts/dev/check-de00d24523be406494b1b1db8e5f2095.json：19项当时scripts回归、真实smoke、3项集成非空无skip；之后补dev检查接线及对应坏样本，scripts成为20项，dev为11项 |
| 文档与生成 | 58份Markdown格式、链接、锚点、围栏与冲突标记检查通过；backend生成契约与权威源码一致，telemetry新增基础设施事件由单向导出更新 |

上述artifacts为本地忽略目录中的执行证据，不提交凭据、原始私有日志或模型数据。Windows实际执行，不声称Linux/CI已验收。SDK投递成功不等于已实现Job/Outbox业务幂等或外部恰好收费一次。

## 独立 Review

第1轮由非作者review_infrastructure检查本阶段和直接影响，集中发现并修复：

1. Docker context优先级及运行期间目标固定，防止本机guard后实际操作远程。
2. 父进程变量覆盖Compose镜像/集群ID，绕过受管锁定配置。
3. SDK关闭等待被取消时丢失排队cleanup；以受保护关闭任务完成后再传播取消。
4. Redis CLI错误响应exit0被误判成功；必须核对唯一PONG。
5. test日志被硬编码标成dev；以受控文件路径分别设置环境标签。
6. logging输出失败的默认handleError回显原始record；替换固定安全失败提示并以秘密哨兵验证。

同轮建议已纳入：按服务/PID拆分轮转文件；增加dev/test跨库与跨Bucket拒绝实测。第2轮仅定点复核以上修复和新增检查接线，六项缺陷均闭合，无新增阻断项。reviewer独立执行后端取消/日志故障4项、dev安全及检查门禁坏样本12项，全部通过；真实只读Compose配置确认镜像覆盖被拒，Loki按dev/test分别查到正常事件。整个AsyncExitStack取消保护与Kafka仅Consumer的配置修订也纳入该轮定点复核；未展开第3轮或全仓审查。

## 保留门禁

完整B0仍缺受控Alembic迁移与锁竞争/断连证明、账号/RBAC种子和首管理员、schema就绪、Dart API生成器方案、完整必需矩阵/覆盖门禁及CI证据。dev core/jobs完整应用进程编排仍明确不可用，当前infra命令只负责基础设施。B1登录收藏和B2持久Job/Outbox/Pydantic AI尚未实现；无真实模型付费调用。本轮不部署生产、不修改MyHome、不push。
