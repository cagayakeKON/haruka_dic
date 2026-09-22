# 测试规范与验证矩阵

状态：2026-09-22，B0-foundation已建立后端unit/contract、Flutter unit/widget/integration入口及开发工具坏样本测试；实际结果见 [工程记录](../../delivery/reviews/2026-09-22-scaffold-foundation.md)。完整必需用例/覆盖分母门禁、业务集成与CI仍未交付；本文规定后续必须验证的行为，不以局部通过替代完整矩阵。

配套：[代码规范](../coding.md)、[数据库规范](../database.md)、[静态检查](../lint.md)、[交付验收](../../delivery/acceptance.md)、[实施阶段](../../delivery/roadmap.md)、[RBAC](../../architecture/authorization.md)、[统一日志](../../operations/observability.md)。

## 1. 目标、等级与例外

**必须**证明用户看到的行为和业务不变量，尤其是身份/数据隔离、撤权、事务一致性、出处、考试答案保存、AI 结果约束和恢复。每个缺陷修复在能够稳定复现的最低有效层补回归；不为纯文档、纯样式、getter 或实现细节机械写测试。

**推荐**使用少量端到端主路径配合充分的规则、组件和集成测试；不要所有情况都依赖浏览器点击，也不要只 mock 仓储后声称数据库约束正确。**例外**必须记录缺口、责任人、补测条件、替代证据与期限；涉及越权、秘密泄漏、数据丢失或 P0 主流程的缺口阻断交付。

文档变更只做 [文档检查](../lint.md)，不创建空测试工程。代码建立后，实际测试文件关联稳定用例 ID 与对应功能契约，审查以可验证结果为准。

执行节奏以根 [AGENTS.md](../../../AGENTS.md) 为准：小阶段和bug修复只执行有影响依据的必要测试，所选必需用例必须有真实结果；完整回归矩阵和全仓覆盖分母/阈值门禁只在大阶段或发布大节点完成时执行。局部报告必须注明范围，不能因未跑全仓覆盖而自动触发全量，也不能把局部通过当作全量通过。大节点修复后的复测按实际影响保留有效证据，不无条件重跑整个套件。

工程初始化按 [脚手架验收](../../delivery/milestones/scaffold.md) 的B0/B1/B2登记阶段必需SCF场景，再随功能扩充。阶段选择来自受版本控制的交付范围，不能根据测试缺失自动减小范围；这些小阶段验证各自必要场景及检查器能力，大阶段执行完整覆盖分母/阈值门禁。Fake参考流程不替代真实AI质量或平台发布验收。

## 2. 测试分层

前端框架、Test ID 注册表、Key/Semantics、浏览器/原生边界和 E2E 步骤由 [前端测试专题](frontend-e2e.md) 维护；素材、工厂、时钟、隔离和清理由 [测试数据专题](data.md) 维护。两篇的 UIE/TDS 验收按阶段登记为必需项，不另设覆盖率门槛。

| 层 | 未来位置/工具 | 必须覆盖 | 不负责证明 |
| --- | --- | --- | --- |
| Python 规则单测 | backend/tests/unit，pytest | 状态转换、计分/限额、CSV 转义/重复、Unicode/出处转换、缓存键、类型化模型 | 真实数据库事务、真实供应商语义质量 |
| API/协议契约 | backend/tests/contract | 输入/返回/错误模型、OpenAPI、SSE 次序与恢复、DTO 字段裁剪、客户端样本解码 | 只凭快照批准敏感字段新增 |
| Python 集成 | backend/tests/integration | 真实 PostgreSQL 迁移/行内及唯一约束、服务层无外键逻辑关联/并发、AuthSession 撤销事实、Redis 会话材料/轮换、Outbox/Kafka 重投、MinIO 权限及对象生命周期 | 不使用 SQLite 代替 PostgreSQL 锁/精度/JSON/约束语义；不把任意 SQL 跨用户拒绝当成未启用 RLS 的数据库能力 |
| Flutter 单元 | frontend/test，flutter_test | 控制器、账号代次、访问快照、DTO、缓存、选择偏移与播放器状态 | OS 安全存储和真实播放 |
| Flutter 组件 | frontend/test，flutter_test | 加载/空/错误/只读/无权、导航守卫、表单、题目/成绩、无障碍语义 | 真实平台弹窗或浏览器 Cookie |
| 三端应用内集成 | frontend/integration_test，integration_test | 注册登录、主学习闭环、考试、CSV、退出切账号 | 无法操作原生平台 UI；测试入口包不能代替最终发布包 |
| 浏览器与原生补充 | tools/e2e 的 Playwright；frontend/patrol_test 的 Android Patrol；Windows 专项驱动或明确人工记录 | Web Cookie/多标签/刷新/管理端、系统权限/文件框/后台恢复及实际候选制品冒烟 | 不复制完整公共用例；未验证平台驱动不能声称覆盖 |
| AI/TTS 协议测试 | backend/tests/contract，Fake 模型/HTTP/音频 | 类型、工具权限、无 Key、取消/超时、重试预算、音频字节/格式和用量口径 | 模拟输出不能证明模型讲解/批改质量 |
| AI/TTS 质量评估 | 受控评估样本与独立运行记录 | 英/日解释、抽题/评分、真实声音/音频和模型能力 | 不加入常规 PR 的隐式付费调用 |

Flutter 官方区分 unit/widget/integration；integration_test 不能操作原生平台 UI，须用实际平台操作或经评估的专用驱动补齐，不把自动测试未覆盖的系统界面写成通过。Patrol 的项目分工为 Android 补充，并不表示该工具没有 Web 能力。依据：[Flutter 测试分层](https://docs.flutter.dev/testing/overview)、[集成测试](https://docs.flutter.dev/testing/integration-tests)。

### 后端 route、service 与 repository 的写法

下面沿用既有层级，规定同一功能在不同层的证据责任；不要求每个函数或每个场景在三层重复测试。未来文件按“层级/模块/test_行为.py”组织，通用夹具放适用目录的 conftest.py，跨层准备逻辑复用测试数据工厂。

| 被测入口与样例位置 | 样例责任与主要断言 | 替身边界 |
| --- | --- | --- |
| route：tests/contract/api/test_collections.py | 经真实 ASGI 请求证明收藏请求校验、HTTP 状态、响应序列化/字段裁剪、分页及错误映射；检查 OpenAPI 与运行响应一致 | 可以覆盖 service 依赖以触发明确成功/失败，但不能直接调用 route 函数代替 HTTP 协议测试，也不能据此声明授权或数据库已通过 |
| service 规则：tests/unit/services/test_collections.py | 对纯规则或可独立编排的行为给定有类型的输入/依赖，断言结果、业务错误及禁止发生的副作用 | 可用符合接口的仓储/供应商替身；不把 fake commit、内存去重或调用次数当作真实事务、锁或唯一约束证据 |
| service 事务：tests/integration/services/test_collections.py | 调用实际服务和仓储，在真实 PG 上验证 ScopeContext、归属/父状态、成功提交及失败回滚；涉及任务时同时验证业务记录与 Outbox 原子性 | 保留真实查询、授权和事务路径，只在已声明的外部供应商边界替换；提交后的结果用独立 Session 读取，失败后确认无半成品 |
| repository：tests/integration/repositories/test_collections.py | 调用实际仓储方法，验证作用域过滤、稳定排序/分页、软删可见性、实际使用的写入及公共时间字段语义 | 使用迁移后的真实 PG；不 mock SQLAlchemy 的 execute/scalars 调用链来证明 SQL 正确；跨表业务合法性仍按 service 协议验证 |

普通 JSON 的 SuccessResponse[T]、PageResponse[T]、ErrorResponse 以及下载/SSE 等例外，以 [API 返回契约](../../contracts/api-responses.md) 为唯一字段来源。契约测试同时核验 HTTP 状态、明确预期的结构/业务字段与禁止泄漏字段；仅用同一 Pydantic 模型把自身输出解析成功不构成独立预期，不能用整份快照自动接受错误码或敏感字段变化。动态 request_id、时间和业务 ID 验证其约束及关联，不硬编码本次运行值。

认证、权限或隔离为目标时，不覆盖当前用户/授权依赖为“永远允许”；真实 API/Worker 路径和同库 A/B 数据证据仍按第4节执行。将 service 替换掉的 route 契约用例只登记为 contract，不同时登记为对应真实集成用例。

### 命名、AAA 与参数化

- **命名**使用 test_动作_条件_预期 的 snake_case，例如 test_create_collection_foreign_source_rejected；函数名描述可观察行为，不写 test_01 或内部方法名的机械镜像。稳定 case_id 与需求/参数映射独立维护，重命名或移动测试不自动改变用例身份。
- **Arrange**通过最小合法 fixture 准备前置条件，标明哪些流程未被本次测试；**Act**执行被测公开入口；**Assert**核对结果或类型化错误、已提交状态及必须没有发生的副作用。一个用例聚焦一种行为；并发、恢复或幂等用例可有协议要求的多步 Act，但每步目的和状态断言必须清楚。
- **断言**优先业务结果与不变量，不断言无契约意义的私有 helper 次数/顺序、ORM 对象内存身份或完整 SQL 文本。拒绝用例同时检查无越权数据、无未经许可的业务写入/付费调用，保留契约要求的审计和限流记录；并发用例检查最终有效记录和业务贡献，而不只断言某个异常出现。错误文案仅在它属于明确兼容契约时逐字比较。
- **参数化**用 pytest.mark.parametrize / pytest.param 表达同一规则的成功、边界和失败输入，并给每个参数组稳定、无秘密的业务 ids；避免在一个测试函数内循环多组输入，使第一处失败遮住后续结果。不同执行语义拆成用例，不用大笛卡尔积或许多条件分支堆成万能测试。
- 参数组使用不可变值或准备配方，每次执行重新取得可变对象、账号和 Session；pytest 不复制传入的 list/dict，不能跨参数共享被修改的对象。ids 不含密码、Token 或用户正文；需要登记为必需行为的参数进入第5节的执行键和数据专题 variant，不能只在显示名称中区分。参数语义见 [pytest 参数化](https://docs.pytest.org/en/stable/how-to/parametrize.html)。

## 3. 夹具、环境与可重复性

### 隔离基础设施

- 集成测试只连接独立测试实例/命名空间，启动时验证显式 test 模式、允许的目标地址和本次唯一资源标识；单凭数据库名包含 test 不足以授权清理。
- 测试 PostgreSQL 主版本与目标部署匹配，实际执行 Alembic；事务/并发/迁移测试允许真实 commit，不能被外层 rollback 夹具掩盖。普通集成用例可用独立 schema/事务提速，但跨连接用例需共享本次隔离数据库。
- Redis、Kafka Topic/consumer group、MinIO Bucket/前缀均含本次随机命名空间。清理前核对目标清单，只删除本次创建的资源；不连接或清理 MyHome 数据。
- 容器镜像按版本/摘要固定，健康检查通过后再测试，不能靠固定 sleep 猜依赖已就绪。缺依赖是环境失败，不是 skip 后显示全通过。
- SQLite 仅用于真实客户端 Drift 缓存测试。网络故障、死锁/租约和进程重启在隔离环境注入，绝不通过停止共享生产服务实现。

### 无外键数据与隔离验收

按 [数据库规范](../database.md) 的 DB 验收登记迁移元数据、字段/时间、约束、查询、逻辑关联与隔离用例；沿用 [数据与任务](../../architecture/data-jobs.md) 的 DAT-01/DAT-06 验证引用和删除竞争。Haruka 独立数据库/账号，P0 同库同 schema 共享表、强制 ScopeContext、无物理外键且不启用 RLS；A/B 越权用例必须处于同一被测库/schema，不能用分库夹具代替应用隔离。

分别证明两类保证：PK/UNIQUE/NOT NULL/行内 CHECK 由真实 PG 约束测试验证；跨 owner/library、错误父版本/状态、批量混入他人 ID 由实际业务服务/API/Worker 在真实 PG 上拒绝。对所有者/关联的校验不能只 mock 仓储，也不能直接插一条跨库 SQL 然后期待不存在的 FK 或 RLS 自动拒绝。

并发测试使用真实提交与屏障，覆盖新增/重绑引用、父 tombstone、GC及迟到 Worker 在同一父行锁/代次协议下的不同先后次序，验证无新悬空引用、无跨用户转移且保留必要历史。工厂的合法前置和清理按同一逻辑关联规范；created_at/updated_at 覆盖 ORM、批量/raw SQL、upsert 等实际写路径，不把某一路径通过当成全体自动更新时间正确。

### 共同测试数据

必须提供 A/B 两个独立用户、各自 Library/材料/试卷/Key 引用，client/admin 会话、全部初始角色及 pending/disabled/locked 账号。每个用例声明需要的权限，不让所有夹具默认超级管理员。

应用业务时钟、随机数据、供应商和网络可替换；注入时钟驱动规则中的考试截止、离线租约与退避，不以等待几分钟证明纯规则边界。API/Worker使用同一场景时间，不能修改共享全局now污染并行用例；Redis TTL、数据库自主时间、JWT库内部时钟和浏览器Cookie/OS不自动跟随业务时钟，另做受控真实期限验证。需要真实并发时用屏障/事件控制竞争顺序，并给等待设有限超时。

英/日材料至少包含组合字符、emoji、假名/汉字、注音、换行和跨块选区。CSV 覆盖多行字段、引号/分隔符、标签、公式前缀、重复词和非法来源。试卷包含共享题干、题图、分值冲突、有/无参考答案、未识别题型和部分批改失败；格式样本按最终范围锁定，不能把待明确的 OCR 当已支持。

公开/自建合成样本入仓库并记录来源和许可；真实个人材料不得默认提交到 fixtures 或 CI 产物。截图、测试日志、录制响应及数据库样本先脱敏。

唯一固定样本位于testdata/assets，场景位于testdata/scenarios；backend/tests/support只准备合法前置并返回别名/账本，秘密另传。用run/case/variant/shard/attempt隔离可变资源，全局策略测试独占实例或串行；清理先处理在途任务与迟到写入，再按归属账本回收。详细合同以测试数据专题为准。

### 异步与外部调用

后端统一 pytest + pytest-asyncio，首版采用 strict 模式；异步测试显式 asyncio 标记，异步夹具用 pytest_asyncio.fixture。loop 和资源生命周期一致，默认 function 范围；共享池跨 loop 的优化必须有可靠关闭策略，不能碰到 event loop closed 后靠重试隐藏问题。配置依据：[pytest-asyncio 模式](https://pytest-asyncio.readthedocs.io/en/stable/concepts.html)、[配置](https://pytest-asyncio.readthedocs.io/en/stable/reference/configuration.html)。

API 异步测试可使用 HTTPX ASGITransport，必须显式启动/关闭应用 lifespan；AsyncClient 本身不负责触发 lifespan，见 [FastAPI 异步测试](https://fastapi.tiangolo.com/advanced/async-tests/)。真实网关 Cookie、CORS、CSRF、Range 和 SSE 缓冲另外在部署样式环境测试。

Pydantic AI 使用 TestModel/FunctionModel/依赖覆盖测试，默认禁用真实模型请求；SDK 的禁用开关不覆盖独立 HTTPX TTS 适配器，因此测试还必须限制网络出站到声明的测试基础设施或 mock transport。能力和限制见 [Pydantic AI 测试](https://pydantic.dev/docs/ai/guides/testing/)。

### fixture 生命周期与依赖覆盖

可变的 app、会话、ScopeContext、业务时钟、账号数据及替身调用记录默认 function 范围。只读素材可跨用例共享；基础设施或连接池确需更大 scope 时，必须保证资源/事件循环生命周期一致，并继续为每个用例创建独立 Session、执行身份和资源账本。不能把 session 范围的 AsyncSession 或全局已登录客户端当作提速方式。

夹具显式声明依赖，建立资源后及时登记清理，使用 yield 配合 try/finally 或上下文管理器释放。尽量让一个 fixture 管理一种有状态资源；多步准备使用可逐步登记关闭动作的管理器，保证后一步失败时已取得的资源仍可回收。yield 前抛错时，pytest 不会执行该 fixture 的 yield 后段，因此不能把所有清理都放在准备流程的最后。释放失败要保留原测试失败和清理错误；按测试数据专题先 quiesce/fence 再回收账本资源，恢复未成功的环境不得交给下一个用例。依据：[pytest fixture 与安全清理](https://docs.pytest.org/en/stable/how-to/fixtures.html)。

FastAPI 依赖覆盖用实际被 Depends 引用的 callable 作为键。每个修改 overrides 的用例独占自己的 app，覆盖前保存已有映射，finally 恢复；不能只在成功断言后重置，也不能对共享 app 无条件清空其他用例的覆盖。覆盖包围完整请求和相关 lifespan/后台任务的生命周期，退出覆盖前先停止本次活动。机制依据：[FastAPI 依赖覆盖](https://fastapi.tiangolo.com/advanced/testing-dependencies/)。

以下是未来测试 support 的局部辅助模板，尚未创建或执行；function 范围 fixture 可在此上下文内 yield 本用例的 app。原依赖与替身由实际工程明确传入，不在模板中定义应用端口、认证旁路或额外 HTTP 路由：

~~~python
from collections.abc import Callable, Iterator
from contextlib import contextmanager

from fastapi import FastAPI


@contextmanager
def override_dependency(
    app: FastAPI,
    target: Callable[..., object],
    replacement: Callable[..., object],
) -> Iterator[None]:
    previous = app.dependency_overrides.copy()
    try:
        app.dependency_overrides[target] = replacement
        yield
    finally:
        app.dependency_overrides.clear()
        app.dependency_overrides.update(previous)
~~~

### mock 与 Fake 的边界

优先对应用已有的接口注入小型、有类型的 Fake；临时 mock 用 create_autospec 约束调用签名，并按需用 spec_set 拒绝未知属性。异步依赖保留 await 语义，不能用宽松 MagicMock 掩盖不存在的方法或错参。patch 作用于被测代码实际查找符号的位置，并以 fixture/上下文限定寿命；避免永久改写环境变量、全局客户端或第三方内部实现。能力依据：[Python mock 与 autospec](https://docs.python.org/3/library/unittest.mock.html)。

规则单测允许模拟时钟、随机数、仓储端口和供应商；狭义 route 契约允许覆盖 service。真实集成/E2E 仍按测试数据专题保留 PG、Redis、权限、Job/Outbox/Worker 等被测链路，Fake 只替换约定的外部供应商。生产配置拒绝 Fake，测试不能增加可公开调用的控制入口。Spy 的次数/顺序只用于有意义的契约，例如拒绝后零次付费调用、限定重试预算；“调用了 commit 一次”不能证明提交成功或无重复结果。

## 4. 首版必须覆盖的行为矩阵

用例 ID 是后续实现的追踪标识，当前没有对应可运行测试。每组包含成功、边界、失败恢复和越权路径，详细业务条件由所链接专题维护。

| 用例组 | 核心断言 | 最低证据 |
| --- | --- | --- |
| AUTH | 重复注册竞争/回滚；错误密码/限流；原生刷新轮换/重放、Web 续期/多窗口；改密撤销；启用的验证/恢复挑战按用途/到期/单次消费；两端登录资格 | 真实 DB/Redis + API + 三端/管理 Web |
| AUTHZ | 多角色/继承/环/停用/deny；未知权限默认拒绝；写权限不扩大读/范围；直达路由和直接 API；逐字段裁剪 | 授权规则/真实投影 + UI + API 权限矩阵 |
| REVOKE | 多实例旧缓存、通知丢失、Redis 删除失败而 PG 撤销已提交、旧表单/并发管理提交；撤权后新请求/工具/付费步骤拒绝；最后管理员竞争保护 | 并发集成 + SSE/Worker/管理 Web |
| ISOLATION | 同库同 schema 的 A/B 交换所有资源/父子 ID，批量混入他人 ID；ScopeContext及服务事务拒绝非法关联，私有文件签名/任务/统计/日志无泄漏 | 每个资源族实际 API/仓储/文件/Worker + 真实 PG；不依赖 FK/RLS |
| DB | 无物理外键、PK/UNIQUE/NOT NULL/行内 CHECK、字段/时间语义、逻辑关联、父删除竞争、软删唯一、事务/CAS、索引/迁移/字典与数据库账号隔离 | 数据库规范的 DB 验收 + 真实迁移/元数据/服务事务；DAT-01/DAT-06及工厂 TDS 场景 |
| ACCOUNT_SWITCH | A 退出后 B 登录，旧响应/音频/下载/日志/考试草稿不应用到 B；client/admin 快照和队列不混用 | Flutter 单元/组件 + 三端集成 |
| IMPORT | 三类/格式分别验证、大小/解压限制、危险路径/外部资源、取消/重投；三类独立就绪/质量门槛、AI不改所选类型、显式另一类型重处理不改旧历史 | 格式与各处理器单测 + 文件/Worker/专用API集成，TYPE/MAT |
| VISION_OCR | 文本层免调用、扫描/混合页范围、显式阶段/Key/预算、首次识别与重识别版本、截断/漏页/错误坐标、页面重试与unknown结果、无传统OCR回退 | 页计划/校验单测 + Fake视觉/Job/作用域集成；真实识别质量另行授权样本评估，OCR验收按获准格式分期 |
| NOVEL | 章序/对话/脚注、句词边界与原文范围、标注失败降级、专用阅读器 | 人工标注样本 + controller/widget + 三端相关流程，NOV |
| TEXTBOOK | 单元/角色/词表列与题目答案关联、缺结构降级、位置与Attempt分离、逐题反馈 | 独立课本结构样本 + 专用页面/普通练习集成，TBK |
| READING | 稳定出处/Unicode、重解析与删除后的快照、进度冲突、离线租期和重联撤权 | 跨端相同样本 + 缓存/版本单测 |
| COLLECTION | 新增/编辑/删除及标签，重复提交、出处回跳、删除原文后保留上下文，失权不写入 | API + 控制器/组件 |
| VOCABULARY_NOTEBOOK | [VNB验收](../../modules/vocabulary-notebooks.md)：多本/多对多去重、语种/父锁、删本保留词、批量筛选快照、只读派生字段与CSV v2权限 | 规则/真实PG事务 + API/Flutter组件；三端仅选目标流程 |
| VOCABULARY_LEARNING | [VL验收](../../architecture/vocabulary-learning.md)：成功日/间隔/主动回忆、辅助曝光顺序、机会/日额度跨端原子性、pending/重评重放与版本/删除竞争 | Fake时钟纯规则/锁定调度适配 + 真实PG/Outbox；不等真实7天、不以工厂预填掌握替代练习 |
| AI_AGENT | 工具按权限提供且执行再次校验；伪造 user_id 无效；输出未完成不可保存；并发用户 Key 独立；预算/未知收费/续聊恢复 | Fake 模型/HTTP + 持久化集成 |
| SPEECH | 私有缓存隔离与global_word标准词音共享、多读音/声音差异、倍速不重新合成、合并/取消/过期链接、实际 PCM/封装/Content-Type、无 Key 与不支持声音 | 适配器 + 三端实际播放；实际发音质量不由可解码/Fake替代 |
| LEARNING_CACHE | 未收藏的词/句/卡片/TTS持久保存；同词异境与无材料输入不串；清本机/Redis后恢复；模型/Key变更、并发乱序、存储失败/配额/GC和离线租期；全局词音不泄漏私人关系/Job、取消不换Key、删贡献者不删成品 | [LC-01～LC-10](../../architecture/learning-cache.md)；键/版本单测、Fake调用计数与真实PG/对象/任务集成、三端副本与账号切换；只读命中不得新增模型调用 |
| PRACTICE | 可靠客观题不调用 AI；主观失败不计零分；错题/统计幂等；无依据诊断不虚构事实 | 规则/Fake + API 主路径 |
| PRACTICE_SELECTION | PGEN筛选AND/OR、成员时间/空值/时区、有效记忆投影、固定随机/计数、确认竞态/撤权与无隐式扩词；生成不占学习额度 | 纯条件/时钟规则 + 真实PG快照/事务与Fake生成；控件只验条件保持/失效和明确确认 |
| EXAM | 题面 DTO 无答案/rubric；冻结版本；revision/编辑代次；截止/保存/交卷并发；缺 Key、逐题失败、重评历史/统计去重 | 真并发 DB/Worker + 三端 release |
| CSV | 当前用户全部单词、协议往返/可逆转义、映射预览、重复确认、混入他人 ID、导出与实际保存区分 | 规则/API + 三端文件选择保存 |
| JOB | 业务与 Outbox 原子；消息重复、领取租约过期、提交后进程退出、取消竞争、DLQ 恢复；结果不重复写入 | 真实 DB/Kafka/Worker 进程 |
| ADMIN | 元数据范围、授予上限/间接提权、菜单隐藏与功能撤销区别、注册默认角色、策略影响预览、审计不可由应用改删 | 真实策略事务 + 管理 Web |
| LOG | 正常/info/错误来源齐全，哨兵秘密/正文/SQL 参数不泄漏；队列隔离/补传/去重/满载；采集中断不递归；审计持久性 | 日志捕获 + 隔离平台链路 |
| RELEASE | 新装/升级/缓存版本、旧客户端兼容、迁移和应用回滚、签名/HTTPS/代理、版本堆栈还原 | 候选制品实际运行 |

权限测试必须交叉覆盖身份 × 受众 × 账号状态 × 动作 × 数据归属 × 业务状态的关键组合；无需对无业务意义的全笛卡尔积穷举，但每个拒绝原因、每条权限依赖和每个资源族都有正负例。单测 Casbin 返回 true 不能代替接口/Worker/对象范围验证。

## 5. 测试发现、执行与报告

未来 backend/pyproject.toml 的基础配置合同：

~~~toml
[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "--strict-config --strict-markers -ra"
asyncio_mode = "strict"
asyncio_default_fixture_loop_scope = "function"
asyncio_default_test_loop_scope = "function"
xfail_strict = true
markers = [
  "unit: deterministic tests without infrastructure",
  "contract: API, event, and provider contract tests",
  "integration: isolated real infrastructure tests",
  "case_id(id): stable identifier in the required-case manifest",
  "security: authorization, isolation, and secret protection tests",
  "slow: bounded long-running fault or capacity tests",
  "external: explicitly authorized real provider tests",
]
~~~

每个 Python 测试恰有一个主要层级标记 unit/contract/integration，可再带 security/slow/external；Flutter 测试登记 unit/widget/integration 层级。未登记标记、收集失败、没有收集到所需测试、环境失败都使对应检查失败；不得以 pytest 无测试退出码当成功。--strict-markers 只检查标记名称，不执行层级数量或需求覆盖检查，因此工程必须另外实现下面的收集/报告门禁。标记能力依据 [pytest 官方说明](https://docs.pytest.org/en/stable/how-to/mark.html)。

### 必需用例收集与结果门禁

未来 scripts/quality/required_cases.json 保存版本化的功能/验收 ID → case_id → 所需平台/runner/传输方式/参数场景与执行层级映射，当前未创建。每个场景在进入相应功能交付范围时登记；代码建立后清单不能为空，不能因测试失败将必需场景改成可选。纯文档通道不要求尚不存在的应用清单。

CI 在测试收集和报告汇总两处执行独立检查：

1. **收集输入**为本次提交/阶段的必需清单、完整测试节点列表、标记和计划平台分片；校验主要层级恰一个、case_id 形态与映射、被选场景有实际测试/人工平台验收入口。未知/重复冲突映射、缺层级/多层级、清单无实现、关键模块漏登记均失败。
2. **执行键**为 case_id + 测试层级 + runner + 平台/受众或传输方式 + 被要求的参数场景；variant规范化摘要包含这些维度。runner如pytest、flutter_test、integration_test、playwright、patrol或已登记人工流程必须明确，不能靠报告格式猜测。同一场景的一个参数通过不能替代其他参数，integration_test也不能覆盖同平台必需的浏览器/原生专项或最终制品证据；A/B越权与本人允许分别登记。
3. **结果输入**包含原始收集/选择结果、JUnit 或等价机器报告、skipped/xfail/deselected/失败状态以及提交/制品/配置标识。仅看 pytest/Flutter 进程退出码不足以验收。
4. **通过条件**为本次必需矩阵的每个执行键都有匹配版本的合格 passed 证据，且无未处理失败。缺报告、缺记录、仅 skipped/xfail/deselected、环境中断或无法对应版本均失败；--strict-markers 和 xfail_strict 不得替代此判断。
5. **分片规则**预先声明每个执行键由哪些分片负责；其他不适用平台可记录 not_applicable，但指定平台的跳过不能被另一无关平台通过覆盖。必需 slow 场景由慢测分片执行并纳入同一发布汇总，所有分片都排除的场景必须失败。缺必要分片或一个场景在所有责任分片都跳过，汇总失败。
6. **门禁输出**逐项列出 required/passed/failed/skipped/xfail/deselected/missing/not_applicable、证据引用和非零失败退出码；人工平台步骤也需提供审核过的结构化验收记录，不能用自由文本“测过”充当 passed。

检查器本身必须有坏样本：未知/缺失 case_id、重复冲突 ID、零/多层级、缺失或错误runner、同平台错误驱动的通过报告、关键场景 xfail、slow 全部被排除、所有平台都 skip、只通过部分参数、缺分片/空报告和提交版本不匹配。常规局部开发允许选择子集，但报告明确局部范围；功能/发布的必需集合由门禁决定，不能靠 -m/-k 缩小后宣称全面通过。

工程和隔离依赖存在后，下列命令分别在 backend/、frontend/ 运行；本次未执行：

~~~text
uv run --locked pytest tests/unit
uv run --locked pytest tests/contract tests/integration -m "not external and not slow"
uv run --locked pytest tests -m "not external and not slow" --cov=app --cov-branch --cov-report=xml --cov-report=json --cov-report=term-missing --cov-fail-under=80
flutter test test --coverage
~~~

coverage 命令是常规确定性回归的数据生成入口，不要求紧跟前两个入口重复运行。局部开发按改动选择层；CI 的必要 slow/平台分片由上面的必需清单补齐。Flutter --coverage 生成 LCOV，不执行下面的百分比门禁；Python --cov-fail-under 只判断本次报告的总体值，核心组及完整分母由独立覆盖率检查器补充。覆盖参数依据 [pytest-cov 官方配置](https://pytest-cov.readthedocs.io/en/latest/config.html)。

Web integration_test 使用与锁定 SDK 配套的浏览器驱动；官方路线采用 flutter drive、test_driver 和目标测试文件，不能假设普通 flutter test -d chrome 已覆盖完整集成流程。Windows 运行于 Windows runner，Android 使用模拟器及真实设备；实际文件和设备 ID 建立后把命令登记到 CI，不在此伪造已有入口。

## 6. 覆盖率、稳定性与 AI 质量

初始门禁是 Haruka 的推荐工程基线，不是外部工具保证：

- Python 手写 app 的语句/分支合并覆盖率至少 80%；认证/授权、评分/提交状态机、CSV/出处、Job 幂等相关核心文件组至少 90%。CI 从完整报告按显式文件清单汇总核心组，输出分母与未覆盖分支；不能用文件平均百分比。核心清单在相关模块创建时同步维护。
- Flutter 手写 lib 总行覆盖率至少 75%，身份/授权、账号切换、考试状态与缓存控制逻辑文件组至少 85%。生成代码、第三方代码和纯生成本地化资源可排除，手写页面和适配器不能借生成目录逃避统计。
- 覆盖率不是行为通过率。AUTHZ/ISOLATION/EXAM/JOB 等必需场景必须全部通过，即使总百分比足够；不要求无意义的 100% 行覆盖，也不为达标删掉异常处理。
- 新模块引入后不得静默降低基线；明确的低收益边界可经独立评审登记窄例外及替代验证。任何已确认越权、数据丢失、错误累计成绩或秘密泄漏均不得以覆盖率例外放行。

### 覆盖率检查器合同

工程初始化时实现独立的覆盖率门禁，未来 scripts/quality/coverage_manifest.json 记录手写源根目录、明确的生成物/无可执行语句例外、模块分类、核心组清单与阈值；当前不创建脚本或清单。必须满足：

| 项目 | 必须行为 |
| --- | --- |
| 输入 | 同一提交/SDK/配置的 Python coverage JSON、Flutter LCOV 与所需分片、源码清单、已审核的模块/核心组清单；不是任意上传的历史百分比 |
| 完整分母 | 从实际 backend/app/**/*.py 与 frontend/lib/**/*.dart 枚举手写源，再与报告路径逐项核对。首次默认对报告缺失的可执行文件失败，不能把未被测试导入的库当不存在。确需补零时先由已验证的工具取得完整可执行行/分支清单，所有未命中计零，禁止用文件物理行数猜分母 |
| 例外 | 生成物必须同时符合来源/再生命令与路径白名单；纯声明/导出等无可执行语句的文件单独登记且验证，不能因为报告没有文件就自动豁免。路径大小写、平台分隔符和相对根统一后核对，仓库外路径与重复冲突数据失败 |
| 核心组完整性 | 每个手写模块分类为核心或普通，核心分类与代码所有者/功能映射相符；新增模块未分类、核心清单为空、条目不存在、关键模块漏登记均失败。不同组可引用同一文件，但组内只算一次 |
| 计算 | Flutter 用所有有效可执行行的命中总数 / 总数，Python 用覆盖语句数 + 覆盖分支数除以语句数 + 分支数；分别计算总体与核心组，不平均文件百分比。合并分片按文件/行或分支取命中并集，不将重复行累加为覆盖 |
| 失败 | 报告缺失/为空/损坏、必要分片缺失、分母为零且无合法例外、未分类或漏测文件、清单不完整、总体/任一核心组低于门槛，均非零退出；不能只打印 warning |
| 输出 | 提交/工具/清单版本、逐文件归属、分子/分母、未覆盖行/分支、总体/各组阈值及通过/失败原因，供 reviewer 复核 |

Flutter 收集器处理实际取得的 hit map，不应假定 flutter test --coverage 自动为全部未加载库生成零覆盖记录，依据 [Flutter 官方覆盖收集实现](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/test/coverage_collector.dart)。阶段 1 需用“增加一个从未被测试导入的手写文件”证明上述门禁确实失败。

检查器还必须包含空/缺/损坏报告、无测试导入文件、未分类模块、空核心清单、未知路径、生成物假冒、多个分片重复计数、边界阈值及文件百分比平均会误放行等坏样本。检查器通过与业务覆盖达标分别记录，不宣称现有测试命令本身已经实现这些约束。

失败默认不自动重跑变绿。需要复测时保留第一次失败、环境信息与第二次结果；不稳定测试记录根因/责任人/期限，关键场景不可隔离到不阻塞发布的清单。xfail 必须有已知缺陷和严格预期；xfail_strict=true 只让意外通过 XPASS 失败，预期失败 XFAIL 本身仍可能让 pytest 成功退出，因此必需执行键的 XFAIL 一律由结果门禁拒绝。工具语义见 [pytest skip/xfail](https://docs.pytest.org/en/stable/how-to/skipping.html)。

AI 质量单独使用经人工标注的版本化样本与 rubric；首批样本至少覆盖英/日两种语言、选区解释、出题、无参考答案评分、含标准答案评分及各 TTS 路径。记录模型/声音、提示版本、样本摘要、人工结论、实际用量与限制；阈值由小样本基线确定后写入发布门禁。没有质量基线或真实能力证据时不能声称该供应商路径已可发布。

真实调用仅在任务范围已授权、输入/费用/并发/重试上限明确时执行；常规测试始终 fake。模型不稳定使单次输出不同不等于协议可漂移，schema/归属/得分范围等确定性约束仍然必须 100% 校验。

## 7. 发布平台与证据

必须记录 Windows 版本/架构、浏览器与版本、Android API/设备、Flutter/Dart 与后端依赖版本，不写笼统的“三端测试通过”。首版建议覆盖一个受支持 Windows 目标、Chrome/Edge Web，以及最低支持与当前 Android API，版本范围在初始化设备清单锁定；Web 管理端有独立登录/RBAC/敏感表单用例。

实际制品至少验证原生安全存储、文件选择/保存、Windows 音频后端、浏览器自动播放/Cookie/CSRF、多标签刷新、Android 生命周期/进程重建和音频中断。无障碍验证焦点、键盘导航、文字缩放、语义标签和小屏题组；不能只依赖截图差异。

测试报告保存用例/需求 ID、候选版本、实际命令、环境、退出码、失败/跳过理由、覆盖率与脱敏附件。具体合并与发布门禁、迁移/回滚以及交付证据保存在 [交付验收规范](../../delivery/acceptance.md)。
