# Dart API 生成器原型

2026-09-22 实测 OpenAPI Generator 7.25.0 的 dart-dio；固定下载地址、JAR 摘要与非默认选项见 [evaluation.json](evaluation.json)。正式工程只增加 Dio 5.11.1，不提交生成器创建的第二个 Dart package 或浮动依赖。

当前正式 OpenAPI 已暴露阻断问题：`message_args` 的 `string | integer` 被生成为空 `MessageArgsValue`，其 `==` 和 `hashCode` 表达式不完整，Dart 3.13.3 的 formatter 以解析错误退出。自定义 `sourceFolder` 在 Windows 还生成反斜杠 package URI，Optional 的导入硬编码为 `src/optional.dart`。这不是健康接口本身的协议问题，不通过手改生成物掩盖。

2026-09-22 依据 [脚手架蓝图](../../../docs/engineering/scaffold.md) 采用限定 B0/B1 的集中手写 DTO 过渡，位置为 `frontend/lib/core/api`。正式错误目录/ARB 对照仍自动导出；响应模型通过后端导出的跨语言样本验证。当时的期限是进入 B2 前完成长期方案决策。

2026-09-28 的长期决策：正式采用**受审的集中手写 DTO/feature 转换 + 后端生成的 Python/Dart 共享样本 + 全量 OpenAPI schema 指纹审查门禁**。Dart DTO 不在 generated 目录，也不宣称自动生成。`frontend/tool/generate.py` 继续只生成既有错误目录等清单目标；`backend/tests/support/api_compatibility.py` 经 `backend/tools/export_compatibility.py` 单向生成 `fixtures/` 的 OpenAPI、样本和摘要。受影响手写转换必须在 Dart 契约测试中消费对应后端样本；schema 变化须先独立审查旧字段兼容性、手写消费者与样本测试，再更新 [transition.json](transition.json) 的 `reviewed_schemas_sha256`。B2a 的资料、学习档案、服务器设置、语言目录和头像 wire 样本已加入；空 cache validate 尚无前端消费者，仅由后端注册框架和 HTTP 契约测试覆盖。新增实际消费者时再补共享样本与 Dart 转换测试。

B2c 按用户要求先完成两端实现与联调，再做独立 review。生成器提供 `--only ui-identifiers`、`--only client-resources` 与 `--only build-targets`：前者只消费 UI 注册源，后者只消费错误目录、ARB 和既有本地化配置；`build-targets` 仅消费公开开发目标注册表；三者不读取或签署 OpenAPI schema，不生成手写 DTO。它们分别保留标识唯一性和错误/翻译匹配检查，供联调前编译必要资源。完整生成及 `--check` 仍检查全量 schema 指纹；独立 reviewer 核对新凭据/配置/Job/event/结果/用量共享样本与 Dart 消费者后，才更新 `reviewed_schemas_sha256` 并完成全量受管生成验证。

重现原型：先按 evaluation.json 下载并校验 JAR，执行 `java -jar <jar> generate -g dart-dio -i contracts/openapi.json -o artifacts/dart-dio-prototype` 并传入该文件的 properties，再使用锁定 Dart 对输出的 `model/message_args_value.dart` 运行 `dart format --output=none`。原始试验输出保存在忽略的 artifacts 中；它不是生产输入。

健康 API 消费只通过已校验的实例地址、显式用户操作与依赖注入执行，无自动重试、Token 注入或模型调用。无效 JSON、未知错误码、代理 HTML 均归类为安全失败，远端正文不进入异常字符串或界面。204 与二进制走独立传输路径，成功响应只解包一次。
