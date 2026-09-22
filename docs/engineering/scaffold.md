# 脚手架实施蓝图

状态：设计基线 v0.1，2026-09-22。本文补充工程初始化的具体选择与操作合同；下列目录、命令、配置和生成物均未创建，不能直接执行或视为验收通过。保持一个 Flutter 工程和一个可安装 Python 包，复用既有业务、认证、权限与日志契约。

配套：[项目结构](../architecture/project-structure.md)、[开发指南](development.md)、[脚手架验收](../delivery/milestones/scaffold.md)、[API](../contracts/api.md)、[权限](../contracts/permissions.md)、[配置运维](../operations/configuration.md)。本文维护工程载体与入口，业务规则仍由各专题维护；检查阈值与必需测试仍以 [测试规范](testing/strategy.md) 为准。

## 1. 实施边界与文件归属

脚手架分 B0 工程基础、B1 三端身份与收藏参考流程、B2 Fake 模型异步参考流程，全部是路线图阶段 1 的子里程碑。文件随实际职责建立，不预建所有 feature 空目录。文档修改不会自动初始化 Git、安装工具或连接共享 MyHome。

| 未来载体 | 维护内容与唯一来源 |
| --- | --- |
| tools/toolchain.json | 精确 Python/uv、Flutter SDK revision及配套Dart、Node/npm、Java/Android与Windows构建工具、代码生成器和镜像版本；无 latest/浮动分支 |
| backend/pyproject.toml、uv.lock、.python-version | Python包、构建器、运行与开发依赖；Python版本须与toolchain一致，依赖解析以lock为准 |
| frontend/pubspec.yaml、pubspec.lock | 单一Flutter应用与插件依赖；SDK约束与toolchain兼容 |
| frontend/config/build_targets.json | 平台×环境的应用身份、构建参数、公开配置schema与目标；不存秘密 |
| frontend/config/ui_test_ids.json | 前端UI定位元数据唯一来源；生成Dart，Playwright只读消费，不承载业务权限 |
| scripts/dev.py | 基于Python标准库的开发入口，统一参数、子进程、路径、退出码与报告；不放业务或授权逻辑 |
| tools/node/package.json、package-lock.json | Markdown等Node开发工具的锁定依赖；不增加Node生产服务 |
| tools/e2e/package.json、package-lock.json | 锁定Playwright/TypeScript开发工具，显式安装浏览器与执行静态检查 |
| testdata/assets、testdata/scenarios | 共享固定素材及manifest、声明式场景；运行账号/凭据不入库 |
| tools/codegen/ | 生成器配置、必要模板、版本/摘要与原型记录；只保留一种正式Dart API生成方案 |
| contracts/ | 由后端导出的OpenAPI、权限/错误/事件目录、版本和摘要；不是另一套可独立编辑的业务定义 |
| .editorconfig、.gitattributes、.gitignore | UTF-8、文本换行、平台文件例外、二进制与生成物分类；不依赖个人Git设置 |

toolchain不复制所有第三方依赖版本，工具/SDK在此固定，依赖包由各自lock控制；多处必要声明用检查器验证一致。记录可兼容范围不能替代实际构建所用的精确版本。Python首版仍为3.13系列，补丁与Flutter/插件等版本在B0原型通过后锁定，不在本次文档中虚构验证结果。

初始运行器需要事先安装的受支持Python、uv与对应平台工具；doctor仅检查并给出安装说明，不假设bootstrap可以先运行尚未安装的Python。bootstrap不自动升级系统SDK，不需要现成后端虚拟环境才能解析自身参数。

## 2. Python包、入口与资源生命周期

### 包与依赖

推荐发行包名haruka-backend，沿用目标结构中的app导入包，使用Hatchling构建，显式声明wheel包含app；不依赖发行名推断目录。backend独占虚拟环境。pyproject声明build-system和精确构建器版本，uv.lock锁运行/开发依赖；构建器版本同时接受工具清单校验。入口与构建系统关系见 [uv项目配置](https://docs.astral.sh/uv/concepts/projects/config/#entry-points)，显式包/资源选取见 [Hatch构建配置](https://hatch.pypa.io/latest/config/build/)。

PEP 517隔离构建依赖另在同一pyproject的tool.uv.build-constraint-dependencies固定全部直接/传递依赖的精确版本与允许的分发包hash，不以uv.lock或仅固定Hatchling顶层版本代替。B0必须锁定支持该hash配置的uv版本并用干净缓存验证；清单覆盖本包wheel/sdist、开发editable以及获准第三方源码包构建。未登记构建依赖、版本漂移、缺hash/摘要不符要失败，不能退回无约束解析；新增源码构建需求先更新受审查的构建约束。各命令显式使用该项目配置，CI保存实际构建依赖清单与摘要，验证闭包完整性。[uv构建约束与hash](https://docs.astral.sh/uv/concepts/projects/build/#build-constraints)

运行依赖放project.dependencies；lint、test、codegen分依赖组，dev组合这三组。开发bootstrap显式同步dev，CI按检查任务声明分组，生产只安装运行依赖。常规同步必须校验lock且不能更新它；初次生成或升级lock走单独有意的依赖变更。模型Fake工具归测试/开发用途，生产配置禁止启用，即使相关符号由上游SDK提供也不能靠是否安装来决定可信程度。

### 正式进程入口

以下是将写入project.scripts的命令契约，当前不是可执行工具：

| 命令 | 入口设计 | 职责 |
| --- | --- | --- |
| haruka-api | app.cli.api:main | 加载配置，启动FastAPI factory与HTTP服务 |
| haruka-worker | app.cli.worker:main | 按声明的任务类型消费/领取，执行用例与租约协议 |
| haruka-outbox | app.cli.outbox:main | 投递已提交Outbox，维护投递状态；不替业务创建任务 |
| haruka-manage | app.cli.manage:main | 显式执行db检查/迁移、受控种子、管理员初始化或恢复 |

CLI是同步main适配，内部按需进入事件循环；不会在已有循环内再调用asyncio.run。共用app/bootstrap.py的类型化依赖组装和关闭逻辑；禁止import模块时读秘密、建连接、迁移数据库、启动线程或请求模型。FastAPI通过lifespan获取/释放资源，Worker/Outbox通过等价异步上下文管理器复用资源工厂。启动失败也按逆序清理已取得资源；每个请求/独立任务持有独立数据库Session。[FastAPI lifespan](https://fastapi.tiangolo.com/advanced/events/)

API、Worker、Outbox只检查schema兼容，不自动迁移或种子初始化。收到停止请求后API停止接收新请求，Worker停止领取，按有界等待处理在途任务/unknown结果，最后关闭连接池与客户端；超时/退出状态、未完成任务和租约可查询。Windows开发进程与Linux容器分别验证停止信号和子进程释放，不以一种系统的信号处理推定另一种正确。

### 不依赖工作目录的打包验证

应用导入只依赖已安装包，禁止sys.path插入工作区或依赖PYTHONPATH补救。资源经importlib.resources或明确配置路径读取，不通过当前工作目录寻找Prompt、模板或策略。OpenAPI/目录导出能在schema模式构造路由，不运行lifespan、不读取生产Secret、不连接PG/Redis或模型。

迁移源仍为backend/alembic，发布制品包含与wheel同提交的alembic目录和配置。haruka-manage db命令显式接收迁移目录/配置路径，或由部署配置提供绝对路径；启动检查manifest的revision/摘要。迁移资源不在wheel内时，单独wheel的API/Worker可运行，但db命令缺资源必须明确失败，不能向父目录猜测或使用其他检出的迁移。

B0在干净虚拟环境安装构建出的wheel及锁定运行依赖，从仓库外目录运行各CLI的帮助/配置校验；运行制品验证另提供对应迁移资源及隔离依赖。除开发editable安装外，CI必须保留这条非editable检查，以发现遗漏文件和隐式导入路径。

## 3. 开发命令的行为合同

统一调用形式为python scripts/dev.py <command>；实现后才写入实际可运行区。脚本按自身路径定位根目录，子进程使用参数数组和显式cwd，不能拼接用户参数执行shell。PowerShell、Linux CI共用Python实现，仅平台能力适配分支不同。根目录外可以用脚本绝对路径调用，不依赖调用者cwd。

| 子命令 | 输入/动作 | 成功与失败定义 |
| --- | --- | --- |
| doctor | --scope docs/backend/web/android/windows/all；只读检查工具、配置schema、锁与所选依赖/端口 | 给每项ready/missing/incompatible和修复说明；所选必需项缺失非0；不输出秘密 |
| bootstrap | 显式scope；在工程和lock已建立后安装锁定依赖，初始化缺失的无秘密本地模板 | 可重复执行；不覆盖已有配置、不升级锁、不迁移/清库/建管理员、不偷偷选择生产环境 |
| dev | --profile core/jobs，--target web/windows/android及Android设备ID | 依赖就绪才启动所选进程；失败回收本次已启动进程，不能输出假就绪 |
| check | --stage B0/B1/B2或后续功能范围；文档为独立docs范围 | 调用现有lint/测试/必需用例/覆盖门禁并传播失败；所选阶段不存在的必需实现失败 |
| codegen | --write更新受管生成物；--check只在临时目录生成并比较 | 默认check；工具/契约/生成差异失败，check不修改工作区与lock |

docs检查不要求Flutter/数据库；B0/B1/B2的范围是已交付能力声明，不能从“发现了哪些文件”自动缩小测试范围。未配置Android设备时可以做声明的构建检查，但不能把运行验收记为通过。输出脱敏的机器报告到artifacts/dev，包含scope、版本、实际命令与结果；机器报告也受忽略与留存限制。

dev只面向隔离dev/test配置。core提供PG/Redis与API、所选前端，适合B1；jobs增加Kafka/MinIO、Worker/Outbox，适合B2。数据库/队列等采用单独Compose项目，执行前核对本次资源清单；MyHome共享部署走运维合同。core未启用异步处理时任务能力明确不可用，不能对未运行Worker的参考任务报告完成。观测可附加隔离采集环境；本地stdout可见不等于已通过Grafana链路。

进程记录包括本次run_id、PID/启动时间/可执行文件、资源namespace；停止只针对仍匹配的本次进程。Windows需要后台启动时使用隐藏窗口的对应实现，不能按进程名称批量终止。停止容器不删除数据卷；清理数据属于显式维护动作，核对目标、绝对路径/资源归属后执行，不提供删除全部Docker卷的默认操作。

## 4. 三端应用身份与构建矩阵

应用身份、部署INSTANCE_ID、用户ID和release是不同维度。身份在frontend/config/build_targets.json单一维护，平台宿主中的必须重复值受CI校验；切换环境不能仅换API URL而复用正式版凭据和缓存。以下标识是工程建议值，首次采用时登记，正式发布前核对发行渠道；不表示已有应用注册或签名身份。

| 目标 | 建议身份/路由 | 隔离与验证 |
| --- | --- | --- |
| Android dev / production | applicationId建议app.haruka.dictionary.dev / app.haruka.dictionary；名称Haruka Dev / Haruka | 同设备并存；安全存储、Drift、日志队列各归本包；升级保留当前环境数据 |
| Windows dev / production | 逻辑app_id为haruka.dictionary.dev / haruka.dictionary；独立产品目录/凭据service名称 | B0按选定安装方式映射稳定安装标识；MSIX映射Package Identity，其他安装器映射安装ID；不能靠改exe显示名判断隔离 |
| Web dev / production | 独立Origin；同一环境内用户路由/与管理路由/admin | API统一/api/v1，管理员API/api/v1/admin；Cookie按既有audience合同隔离，本地缓存仍按实例/用户/受众分区 |

Android以flavor与对应applicationId配置表达环境；具体Gradle/JDK/Flutter版本组合在B0验证。[Flutter Android flavors](https://docs.flutter.dev/deployment/flavors)。Windows不假定Android flavor机制跨平台通用，使用构建入口明确生成/检查宿主参数。Windows最终安装格式和发行签名主体是平台原型门禁，待决不允许宣称正式安装/升级已验收。

Flutter保持一个工程：Web注册用户与管理布局，Windows/Android构建不注册管理路由；统一bootstrap组装公开配置、日志、错误钩子与平台适配。平台区分通过编译条件/适配模块处理；构建目标校验必须实际检测深链和路由注册结果，不能只隐藏入口按钮。dev、production是环境轴，debug、release是优化轴，不能把release构建自动等同生产服务；dev环境也要能构建release用于平台验证。

Web Nginx把/api/v1与私有媒体/事件请求优先转发到后端，未知API路径返回API错误，不能回退成HTML。前端/admin和用户深链在其余页面范围内回退到同一SPA入口，静态资源缺失返回404；入口HTML与版本化assets采用不同缓存策略。实际测试硬刷新、资源路径、Cookie/CSRF、SSE和旧壳兼容。[Flutter Web路径策略](https://docs.flutter.dev/ui/navigation/url-strategies)

目标清单只能保存公开API默认地址、环境/构建标识、支持的能力与版本；用户自选服务仍走设置专题的无凭据探测与账号切换规则。凭据、加密主密钥、签名材料不打入清单。dev/test默认只允许已声明隔离实例，地址配置缺失/环境冲突时失败，不回退生产。所有平台验证安全存储、Drift、文件选择保存、音频与日志适配；Web的WASM/worker等资源按锁定插件的实际要求打包并验证，不假定原生插件自动支持Web。

## 5. API、目录与生成物的单一来源

### 来源与导出方向

| 来源（未来文件） | 导出/消费者 | 约束 |
| --- | --- | --- |
| app/schemas与api路由 | contracts/openapi.json → Dart API DTO/客户端 | Pydantic维护请求/响应；operationId显式、唯一且稳定，不因Python函数改名漂移 |
| app/contracts/permissions.py | contracts/permissions.json → 迁移目录校验、Dart常量与路由声明检查 | 代码注册权限语义/依赖；用户角色授权仍在PG事务中维护，导出文件不能回写人工授权 |
| app/contracts/errors.py | contracts/errors.json → Dart错误枚举/文案映射检查 | 已有安全错误码、可重试分类；未知值安全展示，不映射成功 |
| app/contracts/telemetry.py | contracts/telemetry.json → Flutter事件接口/服务端接收校验 | 白名单字段、类型/限长/敏感等级；只生成契约，不记录私有正文 |
| app/schemas/events.py | contracts/events.json → SSE事件解码及样本 | 沿用API专题事件信封/枚举，不建立第二套SDK事件协议 |
| app/models的MetaData/列注释及Table.info | contracts/database-schema.json → 内部数据字典与schema检查 | 记录scope/逻辑关联/时间/索引，无物理外键；只供内部验证，不直接生成前端DTO，见[数据库规范](database.md) |
| frontend/config/ui_test_ids.json | frontend/lib/generated/ui_test_ids.dart；Playwright读取同一来源 | UI元数据由前端维护；schema/模板参数/唯一性与生成漂移检查，见前端E2E专题 |

这些来源文件只声明类型与不可变元数据，schema/目录不能反向导入数据库运行组件或在导入时读取环境；模型字典只加载无副作用的ORM声明，不建立连接。角色模板作为受审查的版本化种子输入，不是每次启动覆盖的静态权限事实。新增权限默认不授予自定义角色；Seed更新遵守 [RBAC](../architecture/authorization.md) 与下节迁移规则。

### Dart生成器原型

首选评估OpenAPI Generator的dart-dio，确切版本、获取方式/摘要、Java运行要求和配置随B0原型锁定；不直接复制默认选项。前端已规划Dio，原型要验证生成代码可以纳入单一Flutter工程的lib/generated/api，不覆盖应用pubspec或形成未经决定的第二Dart包。生成模板/必要适配必须版本化且可重复，不允许手改结果。[生成器选项](https://openapi-generator.tech/docs/generators/dart-dio/)

原型样本至少包含：snake_case映射、UUID字符串、UTC、Decimal字符串、缺省/显式null/值三态、未知枚举、嵌套列表/分页/统一错误、204、二进制/上传、带discriminator的结构化卡片。Cookie/原生认证协调、SSE重连、幂等与重试由现有手写core适配，不交给生成器默认行为决定。

通过后才登记正式生成器与模板摘要。若无法可靠融入现有工程，按决策记录选择另一个经同样样本验证的生成器，或明确登记集中手写DTO过渡；过渡仅限B0/B1、保持同样跨语言契约测试，不把手写DTO放generated目录，不称为自动生成通过。进入B2前必须锁定长期方案；选择长期手写时需明确修改该生成目标与相关门禁，不能反复以临时状态绕过。

### 确定性与文件纳管

codegen顺序固定为：锁工具与输入 → 离线导出schema/目录 → 校验引用/唯一代码 → 生成Dart → 用锁定SDK格式化 → 编译/解码样本 → 与受管文件清单比较。去除不稳定时间戳和机器路径，JSON键/目录排序固定；版本摘要来自规范化内容。--check在临时目录完成，不修改tracked文件；--write仅更新列明的生成目标，保留未列入范围的手写文件。

| 纳管类别 | 内容 |
| --- | --- |
| 提交 | schema/目录来源、工具清单和锁、生成器配置/模板、contracts导出与来源摘要、lib/generated内可再生代码、本地化源/生成配置、迁移、平台宿主配置 |
| 提交并校验 | Drift等位于源码旁的生成文件、生成器必要的Dart辅助文件；采用后加入明确清单，不能只扫描generated目录 |
| 不提交 | .env真实值、证书/签名密钥、.venv、.dart_tool、构建目录、生成临时目录、工具下载缓存、运行/测试报告及本机配置 |

未来tools/codegen/manifest.json列出source/generator/output/ownership，受管生成目标内出现未知文件或来源摘要不符时失败；允许接管/移除必须显式变更manifest并审查，不能执行全目录递归删除解决差异。Git忽略规则不得吞掉锁文件或受管生成物；提交前与CI都检查生成差异，已有lint例外仍只适用于真正生成内容。

## 6. 数据库初始化与种子

所有业务表先满足 [数据库规范](database.md)：统一时间Mixin、无物理外键、明确scope和逻辑关系校验、命名约束与数据库字典。模型注册、生成字典和已迁移实际schema共同验证，不能用空模型清单通过B0。

haruka-manage提供db status、db upgrade、seed apply、admin init等明确子命令。受控密码通过隐藏输入或Secret注入，不进入命令参数历史。显式加载目标配置，显示脱敏环境/实例/数据库指纹；开发runner拒绝生产配置，运维部署另用该维护入口与已批准目标。

执行顺序为：隔离资源就绪 → 检查只有一个Alembic head及制品资源 → 取得Haruka数据库级迁移锁 → 在锁内重查实际revision与预期起点 → 升级 → 核对schema兼容 → 应用版本化系统目录/初始模板 → 单独初始化首管理员 → 启动进程。迁移锁键在同一Haruka数据库内稳定，不含run_id、进程或revision，避免不同发布各自加锁。使用独立于业务连接池、但同时承载迁移DDL的同一物理PG连接持有session advisory lock，并将该Connection通过Alembic Config.attributes传入env.py；不能另开无锁连接执行DDL。锁超时或持锁连接断开即本次失败，禁止透明重连后继续迁移；重试重新取得锁并检查实际revision/部分DDL状态。不能把每个进程自动执行迁移当并发协调。具体DDL/不可逆项按 [部署与恢复](../operations/deployment-recovery.md) 的前滚/恢复流程处理，证据按 [交付验收](../delivery/acceptance.md) 归档。

这项约束依赖session结束会释放锁的语义，见 [PostgreSQL advisory lock](https://www.postgresql.org/docs/current/explicit-locking.html#ADVISORY-LOCKS)；同一Connection交给迁移环境的接口见 [Alembic连接共享](https://alembic.sqlalchemy.org/en/latest/cookbook.html#sharing-a-connection-across-one-or-more-programmatic-migration-commands)。验收包含双维护进程争锁及持锁/DDL连接中断，不能只测正常串行升级。

目录同步与角色授予分开：首次模板初始化可创建默认角色，升级目录不覆盖已存在角色的人工授权、注册策略或用户绑定；新权限默认不扩大自定义角色。每项种子有版本/摘要与唯一执行记录，变更和审计同事务；重复执行无重复角色/管理员，半途失败按提交边界恢复，不用先清表实现幂等。管理员初始化与恢复遵守最后管理员保护和既有授权边界。

合成测试材料、账号/角色、凭据引用和Fake transport由dev/test夹具或受控CLI准备，标记run_id并只写本次资源。线上HTTP路由不新增seed、debug/login或任意执行任务入口；production配置拒绝dev/test fixture加载。

夹具工厂位于backend/tests/support，不进入生产wheel/镜像；场景输入、别名输出、秘密通道、全局策略隔离与清理fence按 [测试数据](testing/data.md) 实施。统一check在受控测试环境调用工厂和各runner，按run/case/variant/shard/attempt登记资源，不给UI注入数据库凭据或Token。Test ID生成、Web语义树和平台驱动原型按 [前端E2E](testing/frontend-e2e.md) 纳入B0/B1，不将Flutter Key当作DOM属性。

## 7. 参考实现和验收归属

B1用合成材料版本/选区作为合法来源，经正式登录、me/access、POST collections与GET collections完成本人收藏新增和列表，贯通DTO、Repository、Riverpod、服务授权、迁移和日志；无需为此先实现全部上传/阅读器，也不增加未经设计的来源类型。

B2复用现有POST practice-generations，从B1收藏生成一个小规模练习；Job、Outbox、Kafka、Worker、SSE和持久化均用正式机制，只在dev/test把模型调用注入Fake。验证成功、拒绝、重复投递、取消/故障和A/B隔离，不能用Fake结果证明真实AI质量或付费语义已通过。

详细SCF验收ID、平台/参数、坏样本与证据由 [脚手架验收](../delivery/milestones/scaffold.md) 维护。B0/B1/B2通过不代表完整注册恢复、后台管理、材料学习或发布验收通过；工程完成后才按实际证据更新路线图。
