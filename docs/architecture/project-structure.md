# 项目结构与模块职责

状态：2026-09-22，完整B0已验收，已建立frontend/backend/scripts/tools/contracts及dev/基础设施；下列树仍包含尚未创建的业务模块，实际范围见 [B0验收记录](../delivery/reviews/2026-09-22-b0-acceptance.md)。独立 [HTML原型](../../prototype/README.md) 保留。选型见 [架构总览](overview.md)，代码约束见 [代码规范](../engineering/coding.md)，初始化合同见 [脚手架蓝图](../engineering/scaffold.md)。

## 1. 仓库结构

~~~text
haruka_dic/
  README.md / AGENTS.md
  .editorconfig / .gitattributes / .gitignore
  docs/                             product/modules/architecture/contracts/engineering/operations/delivery/decisions
  prototype/                        已有独立 HTML/CSS/JS 原型，不作为正式前端工程
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
      core/                         auth、access、network、telemetry、storage、layout、platform
      features/
        account/ library/ novels/ textbooks/ collections/ practice/ exams/
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
      models/                       SQLAlchemy Base/Mixin、无外键模型、scope/逻辑关系元数据
      ai/                           Pydantic AI、模型工厂、工具、Prompt registry
      adapters/                     Redis/Kafka/MinIO、TTS、解析器、邮件等适配
      workers/                      Job handlers、Outbox、截止扫描、清理入口
    alembic/                        版本化迁移，独立于 MyHome
    tests/                          unit、contract、integration、fixtures、evals、support
  dev/                              开发Compose、隔离初始化、Alloy/Loki/Grafana及本地操作入口
  deploy/                           尚未建立；未来生产Nginx、采集增量与部署恢复配置
  scripts/dev.py                    doctor/bootstrap/dev/check/codegen统一开发入口
  scripts/quality/                  必需用例、覆盖率及结构检查工具/清单
  .github/workflows/                若选GitHub托管：文档/Python/Flutter/构建/发布任务
~~~

项目初期不拆微服务或 Dart 多包。API、Worker、Outbox 使用同一 Python 包和版本的不同入口；Web 管理端先复用 Flutter 工程，原生构建禁用管理路由注册和入口，服务端仍严格检查 admin audience。路径省略号代表模块分组，不表示需要立即创建所有空目录。

文档分类和阅读入口由 [文档导航](../README.md) 维护。docs/contracts是人工维护的协议说明；根contracts是工程建立后由后端schema/注册定义导出的机器契约，两者职责不同，不能复制维护两份完整字段表。具体功能开发从modules进入，不按前端/后端再复制两份功能规格。

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

### 独立布局与平台代码

页面拆分、空间/输入/能力决策、状态恢复及移动端优化以 [Flutter开发与适配规范](../engineering/flutter.md) 为准。以下是复杂feature的目标示例，当前未创建；简单页面不机械增加多套layout或空目录：

~~~text
frontend/lib/
  app/                            路由、全局壳与账号/受众作用域
  core/layout/adaptive_policy.dart  可用空间分类和公共适配策略；阈值单一来源
  core/platform/                  类型化能力接口与条件选择/插件适配
  features/novels/
    application/novel_reader_controller.dart  同一小说的共享状态/动作，生命周期在layout分支以上
    domain/                       小说阅读规则与业务类型
    data/                         API/缓存仓储
    presentation/
      novel_reader_page.dart      小说路由页面协调与布局选择
      layouts/novel_compact.dart  紧凑/触控优先结构
      layouts/novel_expanded.dart 宽屏结构
      widgets/                    本功能可复用的小组件
~~~

platform实现按实际能力拆文件，例如files、audio、secure_storage；Web与原生依赖通过条件导入/独立bootstrap隔离，Android/Windows的插件缺口才增加必要宿主代码。compact/expanded表示空间结构，不能与Android/Windows硬绑定；medium默认复用紧凑布局，只有验证后才增加第三种结构。

两个layout消费同一controller的状态/动作，不互相import对方页面，也不复制repository或直接调用平台插件。page级视图协调器可保存跨layout的焦点/滚动恢复信息，domain/controller不持有Widget、BuildContext或界面控制器。账号切换释放整个私有feature作用域；窗口重排不创建新业务会话。

这个共享只限同一业务类型内的布局。`novels`、`textbooks`、`exams` 分别实现 NovelReaderController、TextbookStudyController、ExamSessionController；`library` 只维护公共入口/元数据并按类型分派。共用文本选区、词条、题型等小组件，不互相导入专用页面或复制/合并彼此状态机，类型合同见 [三类材料](../contracts/material-types.md)。

## 3. Python 内部分层

请求：api 参数/身份校验 → AuthorizationService → service 用例/事务 → repository + domain → response DTO。对外供应商调用只在 adapter/ai 层发生，不在 ORM hook、路由模型 validator 或数据库事务里调用付费模型。

- api 负责 HTTP 状态、Header、SSE、Cookie；domain 不导入 FastAPI/SQLAlchemy/Pydantic AI。
- service 是业务提交边界；repository 必须接收 ScopeContext，禁止默认 scope=None 的全库查询。管理查询用独立 AdminScopeContext 和白名单 DTO。
- ai 工具调用同一 service，不能直接向表插入数据；输出 schema 不等于通过业务校验。
- worker 只取 Job 引用，校验阶段/租约/当前权限后执行 service。system principal 只有截止封存、清理和已返回产物最小落盘等固定动作。
- 数据库会话按请求/独立任务建立，每个并发协程独立 AsyncSession；不在 asyncio.gather 中共享可变 Session。依据：[SQLAlchemy 并发会话约束](https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html#using-asyncsession-with-concurrent-tasks)。
- ORM公共Base、TimestampMixin、无外键关联服务与字典生成按 [数据库规范](../engineering/database.md) 组织；逻辑关联存在性和父删除竞争由service/repository承担，不放入隐式ORM级联或数据库外键。
- app/core 只容纳确实横切的配置与基础机制，不能把所有功能塞进 utils.py 或通用 BaseService。

### 按业务组织文件与跨模块边界

层目录内使用相同业务名分组，如 api/routes/materials.py、schemas/materials.py、services/materials.py、repositories/materials.py、models/materials.py；规模扩大后同层转为 materials/ 包，不提前生成空目录。api/dependencies.py 组装请求依赖，api/exception_handlers.py 负责异常映射，api/responses.py 只提供纯响应/文档辅助，schemas/responses.py 唯一定义 [统一响应模型](../contracts/api-responses.md)。具体新增用例和路由模板见 [后端手册](../engineering/backend.md)。

| 调用方 | 可依赖的业务能力 | 禁止的跨界 |
| --- | --- | --- |
| API/Worker/Agent 工具 | 已公开的应用 service、输入/结果类型与自身适配 | 直接访问其他模块 ORM/仓储、用调用者提供的 user_id 构造可信 scope |
| domain | 纯值对象/规则、无框架的错误/权限代码、标准库 | FastAPI、SQLAlchemy、Pydantic AI、网络/文件 I/O、service/仓储反向依赖 |
| service | 自身仓储/领域、显式注入的 adapter、其他模块公开用例或事务内能力 | 直接 import 其他业务模块仓储/ORM、读取其私有函数、循环调用和隐含嵌套提交 |
| repository | 本模块 ORM/纯查询类型和 ScopeContext | import service/api、调用外部模型或隐式 commit |
| schemas/contracts | Pydantic/标准类型、无副作用的协议定义 | 引入数据库连接、路由注册、运行时环境读取或反向导入 service |

跨域关联只在明确归属的 repository/查询服务中使用显式连接查询；按数据库规范校验每一侧 scope。确需同时使用多个模块模型时，必须登记该联合查询的负责模块、字段投影与授权条件，不能把它做成任意跨表查询工具。跨模块原子写由应用编排用例调用公开的事务内能力，共用一位事务所有者；耗时流程改用 Job/Outbox，不绕过服务边界。

小型模块可直接暴露 services/materials.py 中的方法；拆成包后在明确的 public.py 提供入口，__init__.py 不做连接、注册或大范围星号重导出。跨模块只依赖公开业务类型，不透传 ORM、Session 或 HTTP Request（事务内能力的受控会话参数除外）。导入关系由静态结构检查和 review 共同验证，新增允许边必须说明业务理由；不临时延迟 import 掩盖循环依赖。

## 4. 模块与功能映射

| 用例 | Flutter feature | 后端服务/仓储 | 异步处理 |
| --- | --- | --- | --- |
| 登录/注册/会话 | account、core/auth | AuthService、User/AuthSession/Challenge | 邮件、安全撤销通知 |
| 两端 RBAC/管理 | core/access、admin | AuthorizationService、AdminUser/PolicyService | 缓存通知、审计投递 |
| 材料公共能力 | library | MaterialImport/MaterialService、共用出处/阅读位置服务 | 不可变文件、格式提取、类型分派、清理 |
| 视觉OCR基础能力 | 各消费feature的任务/质量页 | VisionRecognitionService、本人ModelFactory、页/区域识别记录 | Pydantic AI视觉调用、页批次恢复；类型输出/就绪仍由各模块负责 |
| 小说 | novels | NovelProcessing/NovelReadingService、小说manifest/章节与标注引用 | 小说结构、分句/分词及语言标注 |
| 课本 | textbooks | TextbookProcessing/TextbookStudyService、单元/角色及Exercise引用 | 单元分析、词表/习题关联；评分复用Practice公开服务 |
| 收藏/照片/CSV | collections | Collection/PhotoWord/CsvService | 识词、CSV 分批 |
| 多单词本/成员 | collections的notebooks子功能 | NotebookService、Notebook/NotebookItem；CollectionService拥有词内容/版本 | 有界批量、已有Job机制；不复制学习进度 |
| 每日学习/自动掌握 | practice与collections只读状态组件 | VocabularyLearningService、机会/日额度/证据/掌握与调度投影 | 有效评分Outbox消费、确定性重算；复用现有Worker |
| 普通练习/诊断 | practice | Practice/Grading/LearnerService | 出题、主观评分、诊断 |
| 试卷/考试 | exams | ExamPaper/Session/GradeService | 结构抽取、截止扫描、逐题批改 |
| 对话/解释 | agent | Agent/ExplanationService | 按即时/持久路径处理 |
| 朗读 | speech、core/platform | SpeechService、AudioRepository | 合成、封装、音频存储 |
| 偏好/个人 Key | settings | Settings/CredentialService | 受控连接测试、配置失效 |
| 日志 | core/telemetry | TelemetryIngestService | Outbox 审计日志投递 |

名称是设计职责，不强制每行都拆成多个类。接口依赖必须显式注入，不能运行时导入相邻 MyHome 工作目录。

词本在collections中组织紧凑/宽屏页面；复习控制器在practice复用PracticeSession/Attempt，掌握规则由后端唯一计算。Python中词本用例归services/vocabulary_notebooks，纯学习规则归domain/vocabulary_learning，py-fsrs隔离于adapters中的调度适配器；评分仅发布有效证据，学习服务通过既有事务/Outbox更新投影。以上为目标模块职责，不在文档阶段生成空目录或新微服务；依据见[学习状态](vocabulary-learning.md)。

小说/课本/试卷在 api/routes、schemas、services、domain、repositories 中按 novels/textbooks/exams 分组；adapters/parsers 按 markdown/epub 及获准后的 pdf/txt 划分。格式适配器返回源结构，类型处理器返回各自领域产物，Worker handler 显式分派；不建立万能 MaterialProcessor 加一套通用阅读 DTO，也不因此拆微服务或提前生成空文件。

[视觉OCR](vision-recognition.md)在services负责页计划/授权/预算/提交编排，ai负责类型化视觉调用与各业务识别配置，adapters只负责图像预处理/PDF渲染；不增加传统OCR引擎目录或独立部署服务。页面识别稿不是领域ready，仍由小说/课本/试卷各自校验后发布。

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

以上是完整产品的结构验收目标。B0工程基础已按SCF范围验收；业务模块尚未建立，不将B0通过等同于整个STR目标或阶段1完成。
