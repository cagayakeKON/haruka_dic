# 文档审查与验证记录

状态：2026-09-22，首轮功能/工程与脚手架文档已完成独立审查及修订复核；本轮前端E2E/测试数据补充的审查与检查见第6节。Flutter/Python应用工程尚未创建。用户要求以Goal持续细化并交子Agent review，本记录只证明文档层的审查与实际检查，不替代工程验收。

## 1. 分工与独立性

| 参与者 | 编写职责 | 独立审查职责 |
| --- | --- | --- |
| root | 账号/管理流程、接口、权限目录、数据任务、项目结构、运行配置、覆盖与导航整合 | 全局一致性及修订整合 |
| feature_specs | 四份学习功能专题 | root的结构/运行配置/决策/覆盖索引 |
| engineering_specs | 代码、lint、测试、开发、交付规范 | root的账号/API/数据/RBAC操作契约 |
| architecture_review | 不编写初稿 | 既有设计、工程规范、四份学习专题与关键修订复审 |

作者自查不等于独立复核。发现真实缺陷必须修订，并由非作者检查；已知待用户决策或待工程实测单独在决策清单登记，不能把真实缺陷改名为待决项来关闭。

## 2. 首轮与工程规范问题

| ID | 等级 | 问题/修订 | 复核状态 |
| --- | --- | --- | --- |
| R1-01 | P1 | 会话撤销与PG审计/Redis不原子 → PG AuthSession/epoch作为持久撤销事实，Redis失效只收敛 | 已关闭；architecture_review复核ACCOUNT/DATA及ACC-06/DAT-02 |
| R1-02 | P1 | 迟到旧评分覆盖新成绩 → 单活动run、grade_generation/CAS有效指针与贡献替换 | 已关闭；architecture_review复核DATA评分段/DAT-05与考试专题 |
| R1-03 | P2 | 刷新并发/丢响应/旧Cookie → Web稳定opaque Cookie续idle；原生single-flight/代次CAS/有限回执 | 已关闭；architecture_review复核ACCOUNT/ACC-05与AUTH/OVERVIEW |
| R1-04 | P2 | PRD让AI输出原文/ID与架构冲突 → 应用维护原文/ID，模型只给引用/候选 | 已关闭；architecture_review复核PRD 8.1.3与材料流程 |
| R1-05 | P2 | 删除与活跃任务/考试引用竞争 → tombstone/generation、冻结引用与延迟GC | 已关闭；architecture_review复核DATA/DAT-06与MAT-006 |
| R1-06 | P2 | 实际动作和付费阶段权限缺目录 → 中央权限/接口映射、组合依赖与显式用户意图 | 已关闭；architecture_review复核PERMISSION/API与四专题 |
| E-01 | P2 | 覆盖率缺完整分母/阈值执行合同 → 手写源码清单、核心组、缺报告/坏样本检查器 | 已关闭，architecture_review独立复核TESTING/DELIVERY |
| E-02 | P2 | skip/xfail/deselect可漏过必需测试 → 必需case×平台/参数收集与结果门禁 | 已关闭，architecture_review独立复核TESTING/DELIVERY |
| E-03 | P3 | 项目树默认GitHub与托管待定冲突 → .github/workflows标为条件结构 | 已采纳并关闭；engineering_specs独立复核条件目录与CI托管待决一致 |
| C-01 | P1 | 运行配置100MiB与PRD格式限额冲突 → 按格式复用20/50/80MB并固定字节单位 | 已关闭；feature_specs回读CONFIG/PRD |
| C-02 | P1 | 在线旧密文清零后销毁密钥可能破坏备份 → 在线移除与归档密钥销毁分开，保留到依赖备份不再需要 | 已关闭；feature_specs回读CONFIG轮换/恢复流程 |
| C-03 | P2 | 覆盖索引CHAT族不存在 → 使用实际AI验收族 | 已关闭；feature_specs核对覆盖索引与AI专题 |
| F-01 | P2 | 取消误要求原生成权限 → 本人job.cancel独立，重试才复核原业务动作 | 已关闭；architecture_review复核材料/练习/API与验收 |
| F-02 | P2 | 用户凭据和部署加密Key版本混用 → credential_version/encryption_key_version/revision分离 | 已关闭；architecture_review复核SETTINGS/AUTH/DATA/CONFIG |
| F-03 | P1 | 上传校验后可被旧签名覆盖 → staging与后端独享final分离，校验final后发布并用代次保护 | 已关闭；architecture_review复核DATA/API、材料/照片与DAT-08/MAT-008/PHOTO-004 |
| I-01 | P2 | 照片识别/新建/合并权限混用 → 按所选动作分别photo.import/create/read/update，缺权整次拒绝 | 已关闭；engineering_specs复核API/PERMISSION/收藏照片专题 |
| I-02 | P2 | 初始角色/继承/启停deny可绕过assign → 创建空对象与授权分离，影响有效授权的所有路径附加assign | 已关闭；engineering_specs复核ADMIN/PERMISSION及ADM-08/PERM-06 |
| I-03 | P2 | login-only账号被强制profile加载阻断 → access提供最小本人身份，资料/设置按权可选 | 已关闭；engineering_specs复核API/ACCOUNT/ADMIN及ACC-10/SET-007 |
| I-04 | P2 | CSV比较/跳过泄露显式禁止读取的旧词表 → 比较需read、合并另需update；无read仅明确直接新增 | 已关闭；engineering_specs复核CSV/PERMISSION/API及禁止读取、混合动作与批次撤权验收 |

各问题的触发与证据已在子Agent审查消息中提出。18项P1/P2文档问题均已修订并经独立复核关闭；另1项P3说明建议已采纳并复核。三位子Agent在各自审查范围内未再发现需要修订的文档缺陷；当前没有已知未关闭问题。没有用“待实现”替代缺陷关闭，这一结论也不代表未来实现无需测试或不会出现新问题。

## 3. 文档质量门禁

完成条件：P0/P1/P2文档缺陷均关闭、P3明确处理；功能与PRD逐项映射；权限/API/事件/事务只有一套有效契约；本地链接、围栏、冲突标记与规范配置示例检查通过；未实现/未决/待实测边界明确。

首轮全功能细化时实际完成的检查如下，均只针对当时文档；脚手架补强后的全仓结果另记第5节：

| 检查范围 | 实际结果 |
| --- | --- |
| 全仓Markdown文件 | 33份；未创建应用代码、依赖或配置脚手架 |
| 本地Markdown文件链接 | 360处目标存在；不将此项当作外部网站或页内锚点检查 |
| 代码围栏 | 17段均闭合并指定语言 |
| 合并冲突标记 | 未发现 |
| 工程规范示例语法 | 3份TOML（Ruff/Pyright/pytest）、1份Dart YAML和1份Markdownlint JSON，经现有解析器检查通过 |
| 独立审查与复审 | 三位子Agent交叉检查功能、技术契约与工程规范，19项问题/建议均处理并复核关闭 |

未执行Ruff、Pyright、Flutter、Markdownlint或应用测试；示例配置语法检查不等于工具执行通过。功能验收ID和未来CI门禁仍是实施要求，不是通过记录。

## 4. 工程阶段仍须验证

本次不运行不存在的应用测试、不创建配置/脚手架、不连接生产。库版本、原生插件、模型/TTS能力、真实评分质量、平台发布、MyHome实际容量/TLS、恢复目标按 [交付验收](../engineering/DELIVERY_ACCEPTANCE.md) 执行；产品开放选项见 [决策清单](DECISIONS_AND_ASSUMPTIONS.md)。

## 5. 脚手架补强与独立复核

用户同意补强六项脚手架约定后，root编写 [实施蓝图](../engineering/SCAFFOLD_BLUEPRINT.md)，同步结构、开发/测试/lint/交付、运行配置、API、路线图与导航；engineering_specs编写 [阶段验收](../engineering/SCAFFOLD_ACCEPTANCE.md)，architecture_review作为非作者独立审查两份新文档及相关既有契约。

本轮落实后端包/正式CLI、开发命令、三端应用身份、生成物单一来源与纳管、B1收藏/B2 Fake任务参考流程，以及20项SCF验收。B0/B1/B2仍全部未实现，未把注册/恢复的待决策略或真实模型能力标为通过。

| ID | 等级 | 问题与修订 | 独立复核 |
| --- | --- | --- | --- |
| SB-01 | P2 | 迁移锁连接断开后其他DDL连接可能继续 → 同一物理连接持session锁并执行Alembic、锁内核对revision、断连失败重取锁；SCF-B0-04补双进程和断连样本 | 已关闭；architecture_review回读BLUEPRINT迁移段及ACCEPTANCE迁移段/SCF-B0-04 |
| SB-02 | P2 | 顶层构建器锁定不涵盖PEP517间接依赖 → 独立构建约束固定完整闭包版本/hash；SCF-B0-01/02补干净缓存与漏项拒绝 | 已关闭；architecture_review回读BLUEPRINT构建段及ACCEPTANCE构建段/SCF-B0-01/02 |

复核结论：本轮两项问题均修订并独立关闭，未发现其他需要修订的P1/P2文档问题；结构、命令、环境轴和阶段门禁交叉核对一致。验收作者自查20个SCF ID唯一、11个本地链接有效。

本轮最终实际检查：全仓35个文件均为Markdown；406处本地文件链接目标存在，17段代码围栏闭合且注明语言，无合并冲突标记；20个SCF定义唯一，四个CLI在蓝图与验收中一致。旧开发指南中的裸迁移及省略环境的Flutter启动示例已替换。上述检查不包括外部站点/锚点全量验证，也不等于应用构建、lint或测试通过；本轮未创建或执行应用工程。

## 6. 前端E2E与测试数据补充

用户同意把Test ID、测试框架分工、E2E操作和数据规划写入文档。root编写 [前端测试专题](../engineering/FRONTEND_E2E.md)，engineering_specs编写 [测试数据专题](../engineering/TEST_DATA.md)；root同步测试总则、代码/lint/开发/交付、脚手架、项目结构、决策/路线图、导航和代理约定。architecture_review作为非作者独立审查新两篇及跨文档一致性，并核对Flutter/Patrol官方能力说明。

| ID | 等级 | 问题与修订 | 独立复核 |
| --- | --- | --- | --- |
| TE-01 | P2 | E2E允许复用认证上下文而数据规范禁止跨用例会话，边界不一致 → 限定同run/case/shard/variant/attempt/actor/audience内复用真实UI登录context；跨执行身份重新登录；同用例恢复步骤使用受控状态文件 | 已关闭；architecture_review读回两篇登录/context段及原生设备/多设备隔离段 |
| TE-02 | P2 | 必需执行键未含runner，同平台公共集成结果可能覆盖浏览器/原生专项 → TESTING执行键及variant强制runner/层级，补错误驱动报告坏样本 | 已关闭；architecture_review复核TESTING、FRONTEND_E2E、TEST_DATA三处一致 |

本轮新增8项UIE、10项TDS实施验收，保留20项SCF；这些是未来检查合同，均未执行。固定素材、场景、工厂、注册表和测试工程仍待创建。作者自查场景YAML示例语法及素材/配方/别名引用关系通过。

复核结论：两项P2均已独立关闭，新两篇与测试、目录、lint、脚手架、交付和决策约定一致；本轮审查范围内没有已知未关闭问题。未把待验证工具版本、原生驱动或产品选项当作已实测能力。

本轮只修改规范文档；并行工作出现的prototype目录及其状态说明不属于本轮实现或应用测试证据。文档检查范围限定为根README/AGENT/AGENTS及docs下的规范文档，不沿用第5节历史数量。

最终实际检查：上述37份Markdown中，457处本地文件链接目标存在，20段代码围栏闭合且注明语言，无合并冲突标记；20个SCF、8个UIE、10个TDS定义分别数量正确且唯一。此检查不包含外部站点/页内锚点全量验证，也不等于Markdownlint、Flutter、Playwright、Patrol或后端测试通过；本轮没有安装依赖或执行应用测试。

## 7. 代理入口与分阶段工作规则

按用户最新要求，仅保留根AGENTS.md，删除单数兼容入口；同步导航、目标目录和Markdownlint示例的有效引用。AGENTS新增小阶段结束本地commit、前后端契约对齐后并行开发、小阶段/bug仅必要测试、大节点全量测试、小阶段1～2轮review和大阶段全盘review；测试/交付/开发/E2E规范同步执行范围，避免旧全仓覆盖门禁触发小阶段全量测试。

architecture_review完成1轮针对性独立读回，未发现需修订问题，因此没有第2轮或全盘审查。本轮必要检查仅覆盖8份修改的规则/专题：117处本地链接目标存在、13段围栏闭合并注明语言、无冲突标记；Markdownlint JSON示例可解析且globs仅保留标准代理文件；删除目标不存在，全仓检索无单数文件名有效引用。本节另做新增记录的局部检查，不重跑已通过检查。

本次未执行应用测试、全量测试或Git初始化。读取git status返回not a git repository，故没有commit哈希；文档规则已落地，提交步骤未完成。后续工程初始化建立版本控制后，按小阶段提交规则执行，不把本记录当作已提交证据。
