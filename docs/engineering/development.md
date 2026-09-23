# 开发环境与日常操作

状态：2026-09-22，完整B0已验收，包含两系统干净检出与开发编排、三端壳、数据库初始化、前端契约和质量门禁，见 [验收记录](../delivery/reviews/2026-09-22-b0-acceptance.md)。CI参考工作流已建立，未发生远端运行；生产deploy/与B1/B2业务流程尚未建立。下文“当前可运行”区按实际范围执行，其余章节继续维护完整实施合同。

## 当前可运行：基础设施

所有开发Compose和初始化/日志配置统一在 [dev/](../../dev/README.md)。使用本机锁定Python启动独立PG、Redis、Kafka、MinIO和Alloy/Loki/Grafana；只操作haruka-local项目，保留本机其他项目与MyHome环境。

```powershell
.tools/uv/uv.exe run --python 3.13.6 python scripts/dev.py doctor --scope infra
.tools/uv/uv.exe run --python 3.13.6 python scripts/dev.py infra up
.tools/uv/uv.exe run --python 3.13.6 python scripts/dev.py infra status
.tools/uv/uv.exe run --project backend --locked haruka-api --config dev/.local/backend.env --port 18080
```

启动前生成Git忽略的dev/.local/backend.env及test.env；配置中的基础设施开关启用真实连接，不能从其他环境回退。重复up保留已有配置和卷，down也不删卷。端口、凭据位置、镜像摘要与受限账号说明见dev/README。管理连接检查为 `haruka-manage --config dev/.local/backend.env check-infrastructure`，Worker/Outbox使用同一配置的 `--check-startup` 检验生命周期，不领取业务任务。

基础设施范围检查使用 `check --stage infrastructure`：脚本和dev安全回归/静态检查、真实服务smoke及后端隔离集成。后端改动另运行直接受影响的unit/contract、Ruff/Pyright；不重复未受影响的前端三平台测试。带 `--config dev/.local/test.env` 的backend/tools/verify_distribution.py验证仓库外wheel中四个入口真实连接与关闭。基础设施实测见 [切片记录](../delivery/reviews/2026-09-22-scaffold-infrastructure.md)，完整B0结果见本页开头验收记录。

## 当前可运行：B0-foundation

前提以根 [工具清单](../../tools/toolchain.json) 为准：Python3.13.6、uv0.12.17、Flutter3.47.3及锁定revision。此次Windows机器的PATH中python为3.9，不能直接用于开发入口；以下用仓库内固定uv选择已安装的3.13.6。干净检出须先安装清单指定uv（可置于`.tools/uv/uv.exe`；Linux为`.tools/uv/uv`或PATH），不会提交或自动升级全局SDK。

在仓库根执行：

```powershell
.tools/uv/uv.exe run --no-project --python 3.13.6 python scripts/dev.py doctor --scope all
.tools/uv/uv.exe run --no-project --python 3.13.6 python scripts/dev.py bootstrap --scope backend
.tools/uv/uv.exe run --no-project --python 3.13.6 python scripts/dev.py bootstrap --scope web
.tools/uv/uv.exe run --no-project --python 3.13.6 python scripts/dev.py bootstrap --scope docs
.tools/uv/uv.exe run --no-project --python 3.13.6 python scripts/dev.py codegen --check
.tools/uv/uv.exe run --no-project --python 3.13.6 python scripts/dev.py check --stage B0-foundation
.tools/uv/uv.exe run --project backend --locked haruka-api --config backend/.env.example
```

普通scope的doctor核对工具/工程前提；infra scope补Docker daemon和锁定版本，真实服务由infra smoke验证。bootstrap按锁安装、保留已有配置，不迁移或生成账号；后端范围还会写入虚拟环境字节码禁用钩子，避免在源码目录生成 `__pycache__`。`B0-foundation`和backend/frontend等scope是局部检查；`check --stage B0`要求显式`--identity`与全部`--report`，调用既有必需用例检查器核对完整候选矩阵。缺项、失败、身份不符或procedure缺独立签收均拒绝，B1/B2仍拒绝。报告保存在忽略目录artifacts/dev；详见 [报告合同](../../tools/ci/README.md)。

前端独立启动与平台构建参数见 [前端入口](../../frontend/README.md)，后端能力与入口见 [后端入口](../../backend/README.md)。API仅有公开健康路由：live返回200；基础设施配置下ready重新检查数据库schema及依赖，成功200、失败503；离线壳仍返回503。没有公开登录、业务授权或模型接口。Worker/Outbox尚不处理业务；受控迁移、种子和首管理员入口已开放，首次启动API前按后端指南执行迁移。Web默认origin与后端模板统一为localhost:5173，启动前确认该端口没有被其他服务占用。

制品安装检查可用锁定Python运行`backend/tools/verify_distribution.py --uv .tools/uv/uv.exe`，执行干净缓存wheel/sdist构建、运行依赖单独安装、独立工作目录CLI/生命周期与错误构建哈希拒绝。它不执行PG迁移或真实模型调用。实测、review与历史来源适用性统一见 [B0验收记录](../delivery/reviews/2026-09-22-b0-acceptance.md)。

完整B0入口只核对显式候选的已有证据，不重新执行测试，也不自动将当前HEAD视为同一候选。在本机原始artifacts仍保留时，可按已提交的 [证据摘要清单](../delivery/reviews/2026-09-22-b0-evidence-manifest.json) 重放汇总；新检出需重新收集对应证据，不靠目录通配发现报告：

```powershell
$acceptance = Get-Content 'docs/delivery/reviews/2026-09-22-b0-evidence-manifest.json' -Raw | ConvertFrom-Json
$checkArgs = @('scripts/dev.py', 'check', '--stage', 'B0', '--identity', $acceptance.identity_file.path)
foreach ($report in $acceptance.reports) { $checkArgs += @('--report', $report.path) }
& backend/.venv/Scripts/python.exe @checkArgs
```

配套：[项目结构](../architecture/project-structure.md)、[代码规范](coding.md)、[静态检查](lint.md)、[测试规范](testing/strategy.md)、[交付验收](../delivery/acceptance.md)、[MyHome 复用](../operations/myhome-integration.md)。

脚手架具体文件/命令/构建身份/生成物合同见 [实施蓝图](scaffold.md)，阶段1的B0/B1/B2完成条件与参考流程见 [脚手架验收](../delivery/milestones/scaffold.md)。下文日常操作使用这些入口，不另建平行脚本体系。

新增后端接口或模块按 [后端开发手册](backend.md) 的步骤、依赖/事务生命周期及路由模板推进；统一模型、异常与语言约定见 [API 返回契约](../contracts/api-responses.md)。该手册补充编码操作，不替代本文环境和命令。

新增Flutter页面按 [开发与适配规范](flutter.md) 先对齐共享状态/动作，再选择独立layout与平台adapter；紧凑/宽屏、键盘/触控及状态切换证据随功能切片交付，不能只做桌面页面后缩小窗口视为移动端完成。

前端业务测试实施先读 [Test ID与E2E](testing/frontend-e2e.md)，环境准备先读 [测试数据](testing/data.md)。后续完整check按声明执行键协调各runner和受控工厂；业务流程为选择场景→核对隔离资源→准备合法前置→正常UI动作→持久结果断言→脱敏证据→安全清理。当前只有应用壳的局部测试，不能执行尚未实现的业务工厂与持久结果验收。

## 当前可运行：开发进程编排

首次运行先用后端受控入口完成迁移，再从根目录选择一个profile与平台。以下是Windows PowerShell示例：

```powershell
$runtimeConfig = (Resolve-Path 'dev/.local/backend.env').Path
.tools/uv/uv.exe run --python 3.13.6 python scripts/dev.py doctor --scope backend --config $runtimeConfig --profile jobs --target web --api-port 18080
.tools/uv/uv.exe run --python 3.13.6 python scripts/dev.py dev --profile jobs --target web --config $runtimeConfig --api-port 18080
```

打开 `http://localhost:5173`，环境页点击“检查连接”验证实际就绪。`core`只组装PG/Redis并启动API和Flutter；`jobs`增加Kafka/MinIO及独立Worker/Outbox资源生命周期，明确没有B2任务handler。`windows`和`android`使用相应目标；Android必须加`--device <实际设备ID>`，不会自动选用其他任务设备。

默认API端口8000在部分Windows机器处于系统保留段；显式`--api-port 18080`只选择已登记备用地址，不改变系统排除段、不结束端口占用者、不改秘密配置。Web来源固定localhost:5173。所有继承的`HARUKA_*`覆盖都会被编排入口拒绝，避免doctor和子进程指向不同资源。

Ctrl+C只停止本次应用进程，Compose及数据卷保留；自动烟测可用`--run-seconds 2`，或提供父目录存在、尚不存在的绝对`--stop-file`，随后创建该文件发出停止请求。API/Worker/Outbox先释放资源，Flutter接收app.stop，有界等待后仍需强制回收则报告失败。进程所有权实现见 [开发编排记录](../delivery/reviews/2026-09-22-b0-development.md)，两系统完整应用与三端矩阵见 [B0验收记录](../delivery/reviews/2026-09-22-b0-acceptance.md)。

## 1. 工作边界与约束等级

**必须**先确认本次是文档、实现、测试还是部署工作；只执行已授权的范围。文档任务不安装依赖、创建工程、初始化管理员或接入生产。工程建立后必须按仓库实际清单/脚本核对本文，不能把推荐路径当成已经存在。

**推荐**在隔离本地环境完成开发与自动测试；共享 MyHome 实例仅用于经授权的集成环境。**例外**需说明目标、资源归属与清理边界，不得借测试更改 MyHome 用户数据、配置或日志留存。

## 2. 首次建立工程的顺序

以下步骤在用户要求开始实现后执行，完成一项再将真实路径、命令和版本写回文档：

1. 核对仓库实际状态并建立版本控制/忽略规则（若尚未存在），保留现有文档；按项目结构建立 Python、Flutter 和部署目录。
2. 选择兼容的 Python 3.13 补丁、uv、Flutter 稳定版/配套 Dart、Android/Windows 工具链和基础设施版本，形成可重复的版本清单。
3. 创建 backend/pyproject.toml、uv.lock、Python 版本文件，按蓝图声明可安装包、构建器、依赖组和四个正式CLI；建立共用资源工厂、FastAPI生命周期、配置schema、结构化日志和基础测试入口，验证非editable安装与仓库外启动。
4. 建立一个 Flutter 三端工程，共用功能模块，管理后台推荐同项目 Web 的独立布局/路由；提交 pubspec.yaml/pubspec.lock 及 SDK 版本记录。原生包默认不暴露管理 UI。
5. 按静态检查规范建立 Ruff/Pyright、analyzer/formatter、文档检查配置及最小 CI；增加真实有意义的冒烟/隔离测试，不保留模板计数器测试冒充业务测试。
6. 建立本地/测试隔离基础设施与安全占位配置；验证配置缺失时安全失败、退出时资源正确释放。
7. 实现数据库迁移、账号/RBAC 种子与受控首管理员初始化入口，再逐个交付登录、管理与权限、资料与学习功能；不将第一个注册者自动设为管理员。
8. 依次交付B0工程基础、B1身份/收藏参考流程、B2 Fake异步参考流程；记录实测版本、端口、设备、生成结果和门禁证据。doctor/bootstrap/dev/check/codegen语义已在蓝图固定，未实现的脚本不能出现在“已可运行”命令区。

工具安装依据 [Flutter 安装](https://docs.flutter.dev/install) 与 [uv 项目指南](https://docs.astral.sh/uv/guides/projects/)。本文不锁死今天的最新版编号；初始化必须记录经兼容性验证的确切版本，之后通过受审查的升级变更更新。

## 3. 本地环境与依赖

| 项目 | 本地开发要求 | 验证方式 |
| --- | --- | --- |
| Python/uv | Python 3.13，仓库虚拟环境，依赖由 uv 管理 | 记录实际 Python/uv 版本与 uv.lock 摘要 |
| Flutter/Dart | 同一锁定 SDK，Windows/Web/Android 插件兼容 | flutter --version、flutter doctor；核对目标平台诊断 |
| Windows | Windows runner/开发机、匹配 Flutter 要求的 Visual Studio C++ 桌面工具链 | 在该系统实际构建/运行，不能用 Linux 构建结果替代 |
| Android | 匹配 SDK/Gradle/JDK、模拟器与至少一台目标真机 | 记录 API/ABI/JDK/SDK，验证安全存储、生命周期及音频 |
| Web | 受支持 Chrome/Edge，本地同源开发代理或明确测试的 CORS/CSRF 配置 | 登录/刷新/深链/媒体/SSE；正式验收走 HTTPS |
| 数据与队列 | 独立 PostgreSQL、Redis、Kafka、MinIO | 明确版本、健康探针、本次资源命名空间与无生产连接 |
| 日志 | 本地 JSON stdout 与测试采集路径；集成环境接共享 Alloy/Loki/Grafana | 测试正常/info/异常可查询与秘密哨兵脱敏 |

本地Compose固定使用haruka-local，开发与测试使用不同PG数据库/凭据、Redis DB及前缀、私有Bucket；测试对象/key/consumer group含运行随机ID，只清理本次对象。隔离smoke Topic仅保存短期合成记录，当前没有业务Topic。完整业务集成后续按测试规范扩充独立运行资源，不能把本切片当作已具备用户隔离。所有宿主端口仅绑定回环地址。

一次功能开发无需总是启动完整基础设施：纯规则/组件测试使用 fake；数据库/会话/任务/文件功能分别启动它真实依赖的隔离服务。对外供应商默认关闭，测试 Key 只在测试模拟器中使用。

## 4. 配置与秘密管理

配置使用显式 schema，至少分为应用/环境、数据库、会话材料 Redis、Kafka/Job、对象存储、认证/加密、模型能力/限额、日志采集和客户端公开配置。变量的最终名称由实际配置模块定义，此处不重复另一套未经实现的字段表。

账号传输遵循 [账号流程](../modules/accounts.md)：Web 使用稳定的 opaque HttpOnly Cookie，原生使用短期 JWT 与原子轮换的刷新凭据；PostgreSQL AuthSession/安全 epoch 是撤销事实，Redis 保存可失效的会话材料。请求必须同时满足持久撤销状态、Redis 材料与当前 RBAC，不能通过 Redis 旧副本继续已撤销会话。

- .env.example 仅保存安全占位值和说明，真实 .env/证书/签名材料不提交；连接串、认证签名和 Key 加密主密钥不能写进文档或终端输出。
- dev/test/staging/production 使用独立凭据、Cookie/issuer/数据库/命名空间；非生产构建不得意外连接生产地址。启动时验证必需项与环境组合，并输出安全配置版本摘要。
- Web/Android/Windows 包中的 API 地址和特性元数据视为公开数据；服务端秘密、用户 Key 和任何共享模型调用凭据不能通过构建参数打包进客户端。
- MyHome 的认证密钥、用户表、Redis 会话与 API Key 不复用；共享的是实例与可适配机制，Haruka 的权限/资源独立。
- 首管理员/受控恢复使用后续专用命令，经隐藏输入或秘密注入读取，禁止把密码放命令行历史。具体命令实现后须测试幂等、审计、最后管理员保护，不在文档阶段伪造可运行命令。

## 5. 常用工作流

本节所有命令均须在相应工程/工具/配置已存在后使用。每条命令分别执行并检查退出码，不通过 shell 链接掩盖中间失败。

### 拉取变更或切换分支后

先读变更说明，确认锁文件/迁移/配置变化。维护入口已显式绑定本次隔离配置与迁移资源后，在backend/中执行下列未来命令：

~~~text
uv sync --locked --group dev
uv run --locked haruka-manage db status
~~~

uv sync --locked按锁安装且不静默重新解析；未匹配则修复清单/锁差异，不能改用不校验锁的新安装蒙混通过。dev组合lint/test/codegen分组，定义和CI选择按蓝图执行。[uv 锁定与同步](https://docs.astral.sh/uv/concepts/projects/sync/)

确认目标是本人隔离开发数据库且需要迁移后，再执行uv run --locked haruka-manage db upgrade。维护入口在同一持锁连接中调用Alembic并核对实际revision，不能用裸upgrade命令绕过目标、资源和并发检查。未确定数据库目标时不运行迁移。迁移底层语义见 [Alembic 教程](https://alembic.sqlalchemy.org/en/latest/tutorial.html)。

在 frontend/ 中使用 flutter pub get --enforce-lockfile，并核对 SDK 与提交的锁文件。该参数由 Flutter 转发给 pub，要求清单与锁中的解析及内容摘要一致；初始化锁定 SDK 时必须验证这个命令。依据：[pub 锁校验](https://dart.dev/tools/pub/cmd/pub-get)、[Flutter pub 命令实现](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/commands/packages.dart)。

### 启动与开发一个功能

先按 [AGENTS.md](../../AGENTS.md) 划分大小阶段及文件责任；前后端在契约对齐后并行开发、按小阶段联调。小阶段/bug只跑必要测试，review控制在1～2轮，完成即本地commit；大阶段完成再做全量测试和全盘review。没有Git仓库时先在工程初始化建立版本控制，不伪造commit记录。

1. 启动所需隔离依赖，经维护入口完成必要迁移/种子，再启动应用；API、Worker、Outbox分别使用蓝图的正式CLI，普通启动不执行DDL。
2. 根目录入口python scripts/dev.py dev选择core/jobs与web/windows/android目标，按build_targets清单显式传递dev身份、API配置与平台参数。Android使用--device指定flutter devices返回的实际设备ID；不直接复制省略环境/flavor的启动命令。底层设备与命令见 [Flutter CLI](https://docs.flutter.dev/reference/flutter-cli)。
3. 从合成账号登录，先验证权限快照/日志关联，再实现正常、加载/空、失败/冲突、无权和恢复状态。
4. 同次维护 API/字段/权限/事件字典与相关测试。变更数据库时生成候选迁移并人工检查，不能直接修改线上表。
5. 根据风险运行相关 lint/类型/测试；检查产物不含私有内容与秘密，整理实际验证证据后交给独立 reviewer。

HTTP Cookie本地调试如需开发例外，仅限绑定回环地址的dev配置；生产始终保持HTTPS、Secure/HttpOnly与CSRF。release编译模式不等于production环境，正式Cookie/代理验收在隔离HTTPS环境执行，宽松开发例外不能作为通过证据。

### 修改数据库与依赖

先按 [数据库规范](database.md) 设计无外键结构、created_at/updated_at、作用域与逻辑关系/删除协议；同次维护模型元数据、Alembic、数据库字典及必要DB验收，不另外手写不受管的字段清单。

新增 Alembic revision 先审 DDL、数据修复、归属约束、索引和锁影响；在空库与上一发布版本库两条路径升级，验证回滚或前滚方案。业务样本使用合成数据，禁止复制生产数据库用于一般测试。

依赖变更显式更新清单和锁，说明必要性、兼容性/许可证与平台影响；Python 可用 uv lock --upgrade-package 对指定包升级，Flutter 按锁定工具的依赖操作更新。正常同步不做全量 upgrade。升级后重新验证受影响的输出模型、迁移和平台插件。

### 停止与清理

优雅停止应用/Worker，让有界在途操作结束或按任务协议释放租约；停止客户端播放器/订阅并清理本次私有测试数据。数据库/对象清理使用本次显式资源清单，命名空间与绝对路径核对后执行；不要提供一键删除所有 Docker volume 或广泛递归删除作为常规手册。

## 6. 检查入口与排查顺序

格式/分析的完整命令以 [静态检查](lint.md) 为准，测试命令和依赖以 [测试规范](testing/strategy.md) 为准；未来scripts/dev.py按蓝图封装，透明转发退出码并显示实际执行范围。Windows PowerShell和CI shell入口分别验证，不假设Bash脚本在用户机器天然可用。bootstrap只同步已有锁定工程与无秘密模板，迁移、种子和管理员初始化使用显式维护命令。

| 症状 | 先检查 | 禁止的临时绕过 |
| --- | --- | --- |
| 登录后马上失效 | 受众/Cookie/CSRF、PG AuthSession/安全 epoch、Redis 会话材料、当前授权版本、时钟与配置 | 关闭鉴权或给所有用户管理权限 |
| 403/空菜单 | 有效权限依赖、菜单显示限制、功能开关、当前受众 | 前端硬编码显示或后端跳过权限 |
| AI/TTS 失败 | 本人凭据状态、模型能力、上限、Job/AiRun 安全错误分类 | 用共享 Key/他人 Key 兜底或无限重试 |
| Worker 不处理 | Job/Outbox、Kafka namespace/consumer、领取租约、当前权限 | 手工重复提交供应商请求或删业务记录重来 |
| 日志看不到 | 接收响应、队列/丢弃计数、stdout、Alloy 来源、Loki 接收窗口 | 打印全部请求/SQL/Prompt 或暴露 Loki |
| 三端数据不一致 | 账号/服务实例、材料/协议版本、缓存代次、服务端是否提交 | 将本地缓存覆盖服务器最新数据 |

排查统一使用 request_id/operation_id/job_id/ai_run_id 与安全原因分类，避免输出完整配置。异常若影响既有业务或共享服务，停止扩散并按交付规范的恢复/回滚计划处理。

## 7. 工程初始化交付清单

- [ ] 真实项目目录、SDK/工具版本与锁文件存在且本文已与实际一致。
- [ ] 新开发者使用无秘密模板在隔离环境完成启动、迁移、测试与三端最小登录。
- [ ] 初始角色/权限/菜单、首管理员初始化和配置缺失行为均有测试；没有默认公开管理账号。
- [ ] 所有必要命令在 Windows 与 CI 目标 shell 有运行证据，脚本不存在/目录缺失会明确失败。
- [ ] 常规测试不调用真实模型、不连接 MyHome 生产数据；真实供应商调用有独立明确范围并记录实际用量。
- [ ] API/Worker/Outbox、前端三端/管理端、数据库日志与 info 埋点均可关联；实际未覆盖的原生能力明确登记。

以上为完整初始化清单，当前只取得基础切片证据，仍不勾选整项通过。
