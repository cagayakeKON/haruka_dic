# Dart API 生成器原型

2026-09-22 实测 OpenAPI Generator 7.25.0 的 dart-dio；固定下载地址、JAR 摘要与非默认选项见 [evaluation.json](evaluation.json)。正式工程只增加 Dio 5.11.1，不提交生成器创建的第二个 Dart package 或浮动依赖。

当前正式 OpenAPI 已暴露阻断问题：`message_args` 的 `string | integer` 被生成为空 `MessageArgsValue`，其 `==` 和 `hashCode` 表达式不完整，Dart 3.13.3 的 formatter 以解析错误退出。自定义 `sourceFolder` 在 Windows 还生成反斜杠 package URI，Optional 的导入硬编码为 `src/optional.dart`。这不是健康接口本身的协议问题，不通过手改生成物掩盖。

依据 [脚手架蓝图](../../../docs/engineering/scaffold.md) 采用限定 B0/B1 的集中手写 DTO 过渡，位置为 `frontend/lib/core/api`。正式错误目录/ARB 对照仍自动导出；响应模型通过后端导出的跨语言样本验证。进入 B2 前须完成长期生成方案决策，不把当前状态称为 Dart DTO 自动生成已通过。

重现原型：先按 evaluation.json 下载并校验 JAR，执行 `java -jar <jar> generate -g dart-dio -i contracts/openapi.json -o artifacts/dart-dio-prototype` 并传入该文件的 properties，再使用锁定 Dart 对输出的 `model/message_args_value.dart` 运行 `dart format --output=none`。原始试验输出保存在忽略的 artifacts 中；它不是生产输入。

健康 API 消费只通过已校验的实例地址、显式用户操作与依赖注入执行，无自动重试、Token 注入或模型调用。无效 JSON、未知错误码、代理 HTML 均归类为安全失败，远端正文不进入异常字符串或界面。204 与二进制走独立传输路径，成功响应只解包一次。
