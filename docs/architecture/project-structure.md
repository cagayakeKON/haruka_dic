# 项目结构与模块职责

状态：设计基线 v0.2，2026-09-22。以下是正式工程创建时的目标结构；当前已有文档，旧 HTML 原型已按用户要求删除，正式工程尚未创建。选型见 [架构总览](overview.md)，代码约束见 [代码规范](../engineering/coding.md)，具体初始化载体见 [脚手架蓝图](../engineering/scaffold.md)。

## 1. 仓库结构

~~~text
haruka_dic/
  README.md / AGENTS.md
  .editorconfig / .gitattributes / .gitignore
  docs/                             产品、契约、规范、验收与审查记录
  contracts/                        后端导出的版本化OpenAPI/权限/错误/事件目录
  tools/                            toolchain.json、锁定Node工具、codegen配置/清单
    e2e/                            Playwright浏览器测试、页面对象及独立Node依赖锁
  testdata/                         assets固定素材/manifest、scenarios声明式场景
  frontend/                         单个 Flutter 应用，含用户端与 Web 管理布局
    pubspec.yaml / pubspec.lock
    analysis_options.yaml
    config/build_targets.json       应用身份、环境与公开构建配置的权威来源
    config/ui_test_ids.json         UI Test ID唯一来源，生成Dart并供浏览器测试读取
    lib/
      main.dart                     初始化、错误钩子、依赖组装
      app/                          App、启动恢复、路由、主题、两端布局
      core/                         auth、access、network、telemetry、storage、platform
      features/
        account/ library/ reader/ collections/ practice/ exams/
        agent/ speech/ settings/ admin/
      shared/                       通用组件与纯展示模型；无业务越权入口
      generated/                    按版本生成的 API DTO/客户端、UI Test ID与本地化输出
    test/                           单元、widget、repository/契约测试
    integration_test/               三平台应用级场景
    test_driver/                    锁定Flutter SDK所需的Web集成测试入口
    patrol_test/                    Android原生系统交互补充
    android/ windows/ web/          平台宿主，工程初始化生成
  backend/
    pyproject.toml / uv.lock / .python-version
    app/
      main.py                       FastAPI factory、lifespan、路由注册
      bootstrap.py                  API/Worker/Outbox依赖组装与资源释放
      cli/                          api、worker、outbox、manage正式入口
      contracts/                    权限/错误/遥测的类型化只读定义，导出至根contracts
      api/                          routes、认证/权限依赖、错误与流式适配
      core/                         settings、security、logging、生命周期
      domain/                       状态机、计分、权限/出处值对象、纯业务规则
      schemas/                      Pydantic 请求、响应、AI/事件协议
      services/                     用例、授权、事务与幂等协调
      repositories/                 带作用域查询，不提交外层事务
      models/                       SQLAlchemy ORM 与数据库约束
      ai/                           Pydantic AI、模型工厂、工具、Prompt registry
      adapters/                     Redis/Kafka/MinIO、TTS、解析器、邮件等适配
      workers/                      Job handlers、Outbox、截止扫描、清理入口
    alembic/                        版本化迁移，独立于 MyHome
    tests/                          unit、contract、integration、fixtures、evals、support
  deploy/                           独立 Compose、Nginx、采集增量配置与运行说明
  scripts/dev.py                    doctor/bootstrap/dev/check/codegen统一开发入口
  scripts/quality/                  必需用例、覆盖率及结构检查工具/清单
  .github/workflows/                若选GitHub托管：文档/Python/Flutter/构建/发布任务
~~~

项目初期不拆微服务或 Dart 多包。API、Worker、Outbox 使用同一 Python 包和版本的不同入口；Web 管理端先复用 Flutter 工程，原生构建禁用管理路由注册和入口，服务端仍严格检查 admin audience。路径省略号代表模块分组，不表示需要立即创建所有空目录。

后端推荐以Hatchling构建haruka-backend发行包，显式包含app导入包；使用haruka-api、haruka-worker、haruka-outbox、haruka-manage入口。CLI不依赖调用者工作目录；迁移作为配套发布资源显式定位。运行/开发lock与隔离构建依赖约束分别固定，入口初始化/关闭、wheel验证、命令退出行为和三端应用身份由脚手架蓝图维护。

## 2. Flutter 内部分层

每个 feature 按复杂度分为 presentation（screen/widget）、application（Riverpod notifier/use case）、domain（纯模型与规则）、data（repository/API adapter）。简单只读页可以合并 application/domain 文件，禁止机械生成四套空壳。

依赖方向：Widget → notifier/use case → repository 接口 → API/本地缓存适配器。Widget 不访问 Dio、数据库、平台安全存储或直接解密 Key；业务模块通过 core/auth 和 core/access 消费账号/受众/权限，不能各自刷新 Token、解析角色继承。平台插件通过 core/platform 适配，Web 编译不能无条件导入 dart:io。

| 横切模块 | 唯一职责 | 禁止事项 |
| --- | --- | --- |
| AuthController | 恢复/登录/刷新/退出、账号代次 | 业务 feature 私有 Token 副本 |
| AccessController | 当前受众与版本权限、导航、路由/操作守卫 | 本地角色名称推断授权 |
| ApiClient | 关联 ID、会话传输、一次刷新协调、错误映射 | 自动重试没有幂等契约的写入 |
| CacheCoordinator | 服务实例/账号/受众/版本、离线租约、清理 | 把缓存当服务端真相或存密码/Key |
| Telemetry | 日志/埋点/性能/异常、脱敏、有界队列 | 记录题目/答卷/私有正文或上传递归 |
| PlatformServices | 文件、音频、安全存储、生命周期 | 平台分支散落每个页面 |

管理 feature 下按 users、roles、menus、policies、operations、audit 划分；数据取管理 DTO，不复用用户材料详情接口来浏览其他用户。共享按钮组件只能复用交互外观，不能决定业务权限。

## 3. Python 内部分层

请求：api 参数/身份校验 → AuthorizationService → service 用例/事务 → repository + domain → response DTO。对外供应商调用只在 adapter/ai 层发生，不在 ORM hook、路由模型 validator 或数据库事务里调用付费模型。

- api 负责 HTTP 状态、Header、SSE、Cookie；domain 不导入 FastAPI/SQLAlchemy/Pydantic AI。
- service 是业务提交边界；repository 必须接收 ScopeContext，禁止默认 scope=None 的全库查询。管理查询用独立 AdminScopeContext 和白名单 DTO。
- ai 工具调用同一 service，不能直接向表插入数据；输出 schema 不等于通过业务校验。
- worker 只取 Job 引用，校验阶段/租约/当前权限后执行 service。system principal 只有截止封存、清理和已返回产物最小落盘等固定动作。
- 数据库会话按请求/独立任务建立，每个并发协程独立 AsyncSession；不在 asyncio.gather 中共享可变 Session。依据：[SQLAlchemy 并发会话约束](https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html#using-asyncsession-with-concurrent-tasks)。
- app/core 只容纳确实横切的配置与基础机制，不能把所有功能塞进 utils.py 或通用 BaseService。

## 4. 模块与功能映射

| 用例 | Flutter feature | 后端服务/仓储 | 异步处理 |
| --- | --- | --- | --- |
| 登录/注册/会话 | account、core/auth | AuthService、User/AuthSession/Challenge | 邮件、安全撤销通知 |
| 两端 RBAC/管理 | core/access、admin | AuthorizationService、AdminUser/PolicyService | 缓存通知、审计投递 |
| 材料/阅读 | library、reader | Material/ReadingService、出处规则 | 文件解析、AI 分析、清理 |
| 收藏/照片/CSV | collections | Collection/PhotoWord/CsvService | 识词、CSV 分批 |
| 普通练习/诊断 | practice | Practice/Grading/LearnerService | 出题、主观评分、诊断 |
| 试卷/考试 | exams | ExamPaper/Session/GradeService | 结构抽取、截止扫描、逐题批改 |
| 对话/解释 | agent | Agent/ExplanationService | 按即时/持久路径处理 |
| 朗读 | speech、core/platform | SpeechService、AudioRepository | 合成、封装、音频存储 |
| 偏好/个人 Key | settings | Settings/CredentialService | 受控连接测试、配置失效 |
| 日志 | core/telemetry | TelemetryIngestService | Outbox 审计日志投递 |

名称是设计职责，不强制每行都拆成多个类。接口依赖必须显式注入，不能运行时导入相邻 MyHome 工作目录。

## 5. 契约、配置与生成文件

后端 Pydantic 请求/响应是 OpenAPI schema 来源，版本化 JSON 契约由 CI 生成并比较。Flutter 客户端生成器在阶段 1 验证后锁定；选定前允许集中维护手写 DTO，但契约测试必须覆盖字段/null/枚举/时间/分页，不允许页面各自解析 JSON。生成文件带来源版本，不手改；再生成产生差异必须可解释。

具体来源文件、稳定operationId、生成器原型、手写过渡期限、--check/--write语义和生成物入库清单见 [生成合同](../engineering/scaffold.md)。权限/错误/遥测目录从后端单向导出，不能把生成JSON或前端常量变成第二个业务事实来源。

UI Test ID属于前端自有元数据，以config/ui_test_ids.json为源生成Dart，Playwright消费同一注册表；定位与三端驱动见 [前端E2E](../engineering/testing/frontend-e2e.md)。固定样本由根testdata复用，backend/tests/fixtures不复制一套资产；support提供工厂/验证器且不进入生产制品，执行数据/秘密不提交，见 [测试数据](../engineering/testing/data.md)。

环境、默认值、敏感配置、模型能力与本地依赖由 [配置与运行说明](../operations/configuration.md) 维护。功能开关是服务端的受控配置，不把供应商 Key、数据库连接或签名秘密放进 Flutter 编译参数。

## 6. 结构验收

- STR-01：依赖检查确认 UI 不直接访问平台凭据/数据库，domain 不依赖框架，Worker/Agent 不绕过 service。
- STR-02：所有入口共用认证/授权/日志组件，新增业务路由/权限/事件有单一注册位置。
- STR-03：在 Web/Windows/Android 编译中验证条件导入、路径与宿主插件；管理路由只出现在 Web 分发面。
- STR-04：从干净检出和锁文件能生成一致契约并执行对应检查；生成物与源版本匹配。

工程初始化另外执行 [SCF脚手架验收](../delivery/milestones/scaffold.md)，不以空目录或模板测试替代参考闭环。

以上均为未来工程验收，当前未创建这些目录或运行构建。
