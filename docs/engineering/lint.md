# 格式、静态分析与文档检查规则

状态：Draft v0.1，2026-09-22。以下配置与命令是未来工程初始化合同，尚未创建配置文件或执行这些工具；不得将此文档当作检查通过记录。

配套：[代码规范](coding.md)、[本地开发](development.md)、[测试](testing/strategy.md)、[交付验收](../delivery/acceptance.md)。

## 1. 门禁与配置归属

| 检查 | 未来权威配置 | 强制结果 |
| --- | --- | --- |
| Python 格式/规则 | backend/pyproject.toml 的 tool.ruff | format 无差异，check 零违规 |
| Python 类型 | 同文件的 tool.pyright | 手写应用、测试、迁移零错误；不忽略整个适配层 |
| Dart 格式/分析 | frontend/analysis_options.yaml、锁定 Flutter SDK | format 无差异，analyze 零 error/warning/info |
| 浏览器测试 TypeScript | tools/e2e 的 package/lock、类型/格式/lint配置 | 页面对象与用例都通过类型、格式及规则检查，不隐式获取latest |
| Markdown | 根目录 .markdownlint-cli2.jsonc 与锁定工具清单 | 选定规则通过，链接/围栏/路径另行验证 |
| 业务结构检查 | 未来 scripts/ 中经测试的检查入口 | 路由权限声明、契约版本、事件目录和生成物一致 |
| 数据库结构与字典 | Base.metadata、受审查Table.info、迁移及受管数据库字典 | 按[数据库规范](database.md)校验零物理外键、时间/命名/注释、scope/逻辑关系和生成一致；真实约束与并发另由PG集成证明 |
| UI定位与测试数据 | UI注册表、素材manifest、场景schema及受管生成清单 | 非法/重复/未知标识、生成漂移、样本摘要/引用错误、非法场景或秘密输出拒绝 |

必须固定工具版本；升级先审规则变化，再更新配置/锁文件与基线。CI 只检查，不自动修改并提交代码。不用所有规则全开后全局 ignore 的做法，也不把 lint 当成运行时授权证明。

工具版本载体、Node工具锁、scripts/dev.py检查入口、生成目录与源码旁生成物的纳管及差异检查按 [脚手架蓝图](scaffold.md)。缺少已承诺阶段的检查器或配置要失败，不能因为目录尚不存在而自动跳过；文档范围仍仅执行文档检查。

## 2. Python：Ruff

下面是计划写入 backend/pyproject.toml 的配置片段：

~~~toml
[tool.ruff]
target-version = "py313"
line-length = 100
indent-width = 4
src = ["app"]
preview = false
extend-exclude = [".venv", "build", "dist"]

[tool.ruff.lint]
select = [
  "E4", "E7", "E9", "F", "I", "UP", "B", "ASYNC", "S",
  "T20", "SIM", "PIE", "RET", "RUF100",
]
ignore = []

[tool.ruff.lint.isort]
known-first-party = ["app"]

[tool.ruff.lint.per-file-ignores]
"tests/**/*.py" = ["S101"]

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
line-ending = "lf"
skip-magic-trailing-comma = false
docstring-code-format = true
~~~

| 选择 | 用途与明确边界 |
| --- | --- |
| E4/E7/E9、F | 导入/语法类问题、未定义/未使用变量；不启用 E501，由 formatter 尽力处理 100 字符宽度 |
| I、UP | 统一导入与 Python 3.13 可用写法 |
| B、ASYNC | 常见陷阱和异步误用；FastAPI 依赖优先 Annotated，避免为了 B008 对全项目放宽 |
| S | 可静态发现的安全问题；测试只豁免 assert 的 S101，假 Token 等误报逐处解释，不能全量忽略 S |
| T20 | 应用日志不直接 print/pprint；CLI 人机输出如确有需要采用窄范围例外 |
| SIM、PIE、RET | 减少可避免的控制流/返回/重复问题，不为“代码更短”牺牲业务可读性 |
| RUF100 | 清除已失效的 noqa，防止历史豁免永久遗留 |

这些前缀仅包含锁定版本中的稳定规则，preview=false；升级时新增规则仍需审查。格式由 Ruff 单独负责，不并行运行 Black/isort，也不额外启用与 formatter 冲突的引号、缩进或强制逗号规则。配置与规则依据：[Ruff 配置](https://docs.astral.sh/ruff/configuration/)、[规则目录](https://docs.astral.sh/ruff/rules/)、[格式化兼容说明](https://docs.astral.sh/ruff/formatter/)。

工程和工具已存在后，在 backend/ 执行：

~~~text
uv run --locked ruff format --check .
uv run --locked ruff check .
~~~

本地显式修复可以运行 ruff check --fix 后再 format，必须审查差异；不默认启用 --unsafe-fixes。迁移和测试照常检查，只有上面的测试 assert 规则例外。

## 3. Python：Pyright

同一 backend/pyproject.toml 计划包含：

~~~toml
[tool.pyright]
include = ["app", "tests", "alembic"]
exclude = [".venv", "build", "dist"]
pythonVersion = "3.13"
typeCheckingMode = "strict"
venvPath = "."
venv = ".venv"
reportUnnecessaryTypeIgnoreComment = "error"
reportMatchNotExhaustive = "error"
reportImportCycles = "error"
enableTypeIgnoreComments = false
~~~

strict 不代表外部供应商 JSON 已可信；DTO 验证与业务约束仍执行。无类型第三方接口加准确 stub/类型边界，不能整体关闭 reportUnknown 系列或缺少类型声明诊断。关闭泛化的 type: ignore；必要时只用注明具体诊断的 pyright: ignore，并附理由与跟踪项。

推荐在 uv 开发工具清单锁定 Python pyright 包装器，使用版本固定的 Node；该包装器不是微软官方发行物，但默认绑定特定 Pyright 引擎版本。CI 禁止 PYRIGHT_PYTHON_FORCE_VERSION=latest 或跟随编辑器版本的覆盖，记录实际引擎与包装器版本，确保使用受控缓存/包来源。依据：[包装器项目说明](https://github.com/RobertCraigie/pyright-python)。

编辑器和 CI 使用相同项目配置，在 backend/ 执行 uv run --locked pyright。配置能力依据 [Pyright 官方配置](https://github.com/microsoft/pyright/blob/main/docs/configuration.md)。

## 4. Flutter / Dart

计划的 frontend/analysis_options.yaml：

~~~yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  exclude:
    - build/**
    - .dart_tool/**
    - lib/generated/**
    - '**/*.g.dart'
    - '**/*.freezed.dart'
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  errors:
    unused_import: error
    dead_code: error
    avoid_print: error

linter:
  rules:
    avoid_print: true
    avoid_dynamic_calls: true
    cancel_subscriptions: true
    close_sinks: true
    discarded_futures: true
    unawaited_futures: true
    use_build_context_synchronously: true

formatter:
  page_width: 100
~~~

flutter_lints 固定在 dev_dependencies/锁文件中；上述明确开启项目关心的异步、类型和资源释放规则，其余使用该锁定版 flutter_lints。初始化锁定的 Dart 必须支持 page_width；若不支持，先调整版本决策与文档，不让 CI 静默忽略配置。依据：[Dart 分析配置](https://dart.dev/tools/analysis)、[flutter_lints](https://pub.dev/packages/flutter_lints)、[格式化选项](https://dart.dev/tools/dart-format)。

analyzer 的生成物排除不允许手写代码藏入 generated；生成器源与调用方仍要分析，生成物必须编译且再生无差异。formatter 不使用 analyzer 的 exclude，检查目标中的生成 Dart 也须由再生流程统一格式化，不靠手工修补。

工程已创建、test 与 integration_test 目录存在后，在 frontend/ 执行：

~~~text
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze --fatal-infos --fatal-warnings
~~~

format 的检查退出码见 [Dart format](https://dart.dev/tools/dart-format)；分析参数以锁定 SDK 的帮助与 [Flutter 官方命令源码](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/commands/analyze.dart) 校对。不存在的目录不得用空测试文件凑命令，应先按项目初始化阶段建立真实入口或按已存在的检查范围运行。

上面的format命令是最小示例。test_driver、patrol_test建立后必须同时加入格式检查；不能只检查三条旧路径而漏掉新增Dart文件。tools/e2e初始化时锁定TypeScript及配套格式/lint配置，统一check执行类型检查（tsc --noEmit）、格式和规则检查；配置未建立不能算该runner交付。页面对象/用例与Python测试support均属手写代码，不套用generated排除。

[前端定位](testing/frontend-e2e.md) 与 [测试数据](testing/data.md) 的静态检查须有坏样本：重复/非法ID、未登记模板参数、缺素材/hash漂移、未知配方/schema、可执行YAML与秘密混入输出。注册检查只能证明声明一致，不能证明控件实际存在、可输入或权限生效，这些由widget和真实平台测试举证。

规则局限必须在审查中补足：avoid_print 不能阻止 debugPrint；cancel_subscriptions 不能证明所有订阅都被释放；mounted 检查不能替代账号代次检查；strict-casts 不能替代接口数据校验。统一 Telemetry 和相应测试仍是必须项。

## 5. Markdown 与契约检查

未来根目录 .markdownlint-cli2.jsonc 的规则合同如下；只列明确启用项，避免新增工具默认规则改变所有中文文档：

~~~json
{
  "config": {
    "default": false,
    "MD001": true,
    "MD003": { "style": "atx" },
    "MD004": { "style": "dash" },
    "MD009": true,
    "MD010": true,
    "MD012": true,
    "MD013": false,
    "MD018": true,
    "MD019": true,
    "MD022": true,
    "MD023": true,
    "MD025": true,
    "MD027": true,
    "MD031": true,
    "MD032": true,
    "MD034": true,
    "MD038": true,
    "MD039": true,
    "MD040": true,
    "MD042": true
  },
  "globs": ["README.md", "AGENTS.md", "docs/**/*.md"]
}
~~~

MD013 行长不设门禁：中文段落、表格与协议代码块按可读性审查。代码围栏标注语言，Markdown 本地链接使用相对路径；配置中的格式样例只是文档，不承诺已存在的文件/脚本。

Markdownlint 不能代替以下检查，未来 scripts/ 检查入口须实现并有自身的坏样本测试：

1. 本地目标/锚点存在，大小写与实际文件一致；外部参考单独联网抽检。MyHome 外链按相邻仓库引用归类，CI 未挂载参考仓库时单独列为未验证，不能伪装成本仓库断链或通过。
2. 围栏正确闭合且嵌套代码示例不误判；无冲突标记、失效相对路径或意外秘密。
3. 未实现状态、P0/P1、产品边界、权限代码/路由映射、事件/协议版本与路线图一致。
4. 工程建立后扫描每个路由的权限/公共例外声明，校验发布目录与两端组件映射；扫描只能验证声明完整，真实拒绝行为由测试证明。
5. 数据库变更对受影响模型/迁移及共同Base执行DB结构检查；新增或修改检查器时验证漏时间字段、漏scope/逻辑关系、误加物理外键、重复索引、字典漂移与空模型清单等坏样本。实际PG catalog、时间写入和隔离/锁竞争属于[DB验收](database.md)，不能用Ruff、文本搜索或ORM导入成功替代。
6. 按 [统一返回契约](../contracts/api-responses.md) 检查实际路由注册及导出OpenAPI：JSON成功泛型具体化、错误模型/状态声明齐全、默认422已替换、流/空体例外明确；错误码/参数/本地化占位符目录一致。静态声明不能替代API-07～API-10的真实错误响应与跨端解码验证。
7. 按 [模块边界](../architecture/project-structure.md) 检查受影响Python导入关系、domain禁依赖和循环依赖；跨模块仓储/模型联合查询例外需登记。规则用AST或实际导入图实现，不只靠搜索类名；首次建立/改变检查器时提供违法依赖样本证明能阻断。
8. Flutter按 [适配规范](flutter.md) 检查feature/UI不直接导入原生库或调用MethodChannel，平台依赖只在声明适配边界出现；布局阈值集中、业务controller不持有界面对象。静态检查/代码review只能证明边界，三端编译、状态切换与原生交互仍需对应FLT证据，不把检测到kIsWeb当兼容通过。

CLI、配置语法与规则以 [markdownlint-cli2](https://github.com/DavidAnson/markdownlint-cli2) 和 [markdownlint 规则](https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md) 为准。初始化时在独立文档工具清单锁定 Node、包版本与 lockfile，CI 调用已安装的 markdownlint-cli2，不临时下载 latest。现在仅能报告实际执行的链接/围栏等文档检查。

## 6. 豁免与验证证据

- 只在最小代码位置豁免具体规则，注释说明误报原因、跟踪项与移除条件；不能使用整文件 ignore all、空的 noqa、关闭整个严格类型系统。
- 目录级例外必须写入本文件并经过独立评审；生成物的排除是唯一预先允许的分析范围例外，生成器源码不豁免。
- 初始接入不建立隐藏的“历史全部忽略”基线；确有第三方诊断误报时登记逐项例外，依赖升级复核。
- CI 保存工具/SDK 版本、实际命令、退出码和精简报告。通过 lint 不等于通过业务、三端运行或安全验收，门禁组合见 [交付验收](../delivery/acceptance.md)。
