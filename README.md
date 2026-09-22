# Haruka（ハルカ）

把用户自己的小说、文章、教材和试卷，变成可阅读、可朗读、可练习和可模拟考试的语言学习资料库。

采用 Flutter（Windows、Web、Android）与 Python 前后端分离架构，学习 Agent 使用 Pydantic AI。支持多用户、管理后台与完整 RBAC；使用各用户自己的 API Key，朗读采用 Gemini/OpenRouter TTS，用户备份恢复仅为单词 CSV。

## 当前状态

需求与技术方案已文档化，Flutter/Python工程、依赖、运行测试及B0/B1/B2尚未实现。已有独立 [HTML交互原型](prototype/README.md)，采用中性底色、Primary主色与杂志式排版，不设“继续阅读”；它使用内存示例，不代表真实业务已交付。具体视觉取值及原型边界以其说明为准。

## 从这里开始

| 你要做的事 | 入口 |
| --- | --- |
| 了解产品目标、首版与后续范围 | [产品总览](docs/product/overview.md) |
| 按功能或职责查阅文档 | [文档导航](docs/README.md) |
| 查看实施阶段和验收要求 | [路线图](docs/delivery/roadmap.md) |
| 查看已选方案与待决事项 | [决策索引](docs/decisions/README.md) |
| 让Agent开始工作 | [AGENTS.md](AGENTS.md) |

MyHome提供可复用基础设施，Haruka保持独立业务、账号、数据与凭据。技术细节、检查规则和阶段证据分别由文档导航指向唯一正文；本页不重复维护配置或验收清单。
