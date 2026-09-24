# Haruka（ハルカ）

把用户自己的小说、课本和试卷，变成可阅读、可朗读、可练习和可模拟考试的语言学习资料库。当前只适配这三类，分别使用专用处理流程与页面。

采用 Flutter（Windows、Web、Android）与 Python 前后端分离架构，学习 Agent 使用 Pydantic AI。支持多用户、管理后台与完整 RBAC；使用各用户自己的 API Key，朗读采用 Gemini/OpenRouter TTS，用户备份恢复仅为单词 CSV。

## 当前状态

阶段1的 **B0 可重复工程基础已验收**：包含 [Flutter三端应用壳](frontend/README.md)、[可安装Python后端](backend/README.md)、[本地基础设施](dev/README.md)、受控数据库初始化、前端契约、开发编排和质量门禁。Windows/Linux干净检出、仓库外正式入口、三端交互及完整B0证据矩阵已通过，详见 [B0验收记录](docs/delivery/reviews/2026-09-22-b0-acceptance.md)。B1登录/收藏/RBAC参考流程和B2持久任务闭环尚未实现，阶段1仍在进行。

产品设计语言已确认为 [「晴空频率」](docs/product/design-language.md)：灵动青春、科技感，以晴空蓝、少量芽黄绿、短声线及统一排版/反馈规则贯穿各场景。[HTML交互原型](prototype/README.md)已按该语言重建手机与电脑两套独立界面，手机端进一步优化了内容排版、底部操作与学习流程；电脑端以相同视觉语言重构了材料列表、阅读分栏、分步表单和键盘操作，两端均清理了非产品说明文案；仍只使用内存中的虚构示例，不代表真实业务已交付。不设“继续阅读”的产品边界保留。开发命令与工具前提见 [开发指南](docs/engineering/development.md)。

## 从这里开始

| 你要做的事 | 入口 |
| --- | --- |
| 了解产品目标、首版与后续范围 | [产品总览](docs/product/overview.md) |
| 设计产品视觉、组件、动效与文案 | [产品设计语言：晴空频率](docs/product/design-language.md) |
| 按功能或职责查阅文档 | [文档导航](docs/README.md) |
| 查看实施阶段和验收要求 | [路线图](docs/delivery/roadmap.md) |
| 查看已选方案与待决事项 | [决策索引](docs/decisions/README.md) |
| 让Agent开始工作 | [AGENTS.md](AGENTS.md) |

MyHome提供可复用基础设施，Haruka保持独立业务、账号、数据与凭据。技术细节、检查规则和阶段证据分别由文档导航指向唯一正文；本页不重复维护配置或验收清单。
