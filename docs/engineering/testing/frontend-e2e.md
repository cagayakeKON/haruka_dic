# 前端 Test ID 与端到端测试

状态：2026-09-23，B0已验证Flutter三端壳、UI标识单源生成、Key与Web外部Semantics定位、基础控件及Android输入/返回原型；平台原始结果见 [B0验收记录](../../delivery/reviews/2026-09-22-b0-acceptance.md)。业务流程、完整Patrol/平台专项与真机性能随后续功能交付，本文继续维护完整实施基线。

配套：[测试总则与必需用例门禁](strategy.md)、[测试数据](data.md)、[脚手架验收](../../delivery/milestones/scaffold.md)、[交付验收](../../delivery/acceptance.md)。本篇维护工具分工和定位契约，业务断言仍以各功能专题为准。

## 1. 框架选择与平台边界

| 范围 | 采用方案 | 主要责任 |
| --- | --- | --- |
| Flutter 单元/组件 | Flutter SDK 的 flutter_test | 状态、表单、权限显示、导航、错误/加载状态和无障碍语义 |
| Flutter 应用内集成 | Flutter SDK 的 integration_test | Windows/Web/Android 公共业务流程；Web 使用锁定 SDK 支持的 driver 入口 |
| Web 浏览器 E2E | Playwright Test，TypeScript | Cookie/CSRF、刷新、深链、多标签页、多用户上下文、上传下载和管理后台浏览器行为 |
| Android 原生补充 | Patrol | 系统权限、文件选择、应用切换/后台恢复等原生交互；能力逐项做设备原型 |
| Windows 原生补充 | 驱动原型通过后锁定；此前保留结构化人工验收 | 系统文件对话框、安全存储、真实播放、安装/升级等实际平台行为 |
| 后端规则/协议/集成 | pytest + pytest-asyncio | 真实数据库、鉴权、事务、队列及供应商适配；不由前端点击替代 |

integration_test 无法操作原生平台 UI，不能用应用内测试证明系统弹窗通过；Windows 运行需要 Windows runner。[Flutter 集成测试介绍](https://docs.flutter.dev/cookbook/testing/integration/introduction)、[各平台执行方式](https://docs.flutter.dev/testing/integration-tests)

Patrol 已有基于 Playwright 的 Web 支持，仍不支持 Windows；本项目选择它承担 Android 补充测试，避免再维护一套重复 Web 流程。若后续合并工具，先做同等能力/证据原型并更新决策，不把这项分工描述成 Patrol 没有 Web 能力。[Patrol 平台说明](https://patrol.leancode.co/documentation/supported-platforms)、[Patrol Web](https://patrol.leancode.co/documentation/web)

一个业务 case_id 可以有多个必需平台/runner 变体，runner与测试层级是执行键的必填维度，不能用integration_test通过替代同平台所需的Playwright/Patrol或人工证据。用覆盖矩阵明确哪些行为由哪一层证明，不复制三套完整业务 E2E；声明三端支持的关键流程仍需三端运行证据。SDK、浏览器、Patrol、Node 和驱动版本在原型通过后精确锁定，CI 预装所需依赖，不能执行时隐式下载最新版。

## 2. Test ID 契约

### 标识范围与命名

必须给页面根节点、可操作控件、关键业务状态（保存中/已保存、任务失败、成绩待复核等）提供稳定定位。装饰、纯排版容器不强制加标识。使用 surface.feature.screen.element 形式，例如：

```text
client.auth.login.email
client.auth.login.submit
client.account.profile.display_name
client.account.profile.avatar.choose
client.account.study.target_languages
client.account.security.password.current
client.account.security.password.save
client.exam.preparation.listening_script.choose
client.exam.preparation.listening_candidate.{candidate_ref}
client.exam.preparation.listening_binding.{review_ref}.confirm
client.exam.preparation.listening_audio.generate
client.exam.session.listening.play
client.exam.session.save_status
admin.roles.editor.save
```

标识不随文案、本地化、样式或测试执行变化；禁止包含邮箱、单词正文、题干、密码、Key 或 Token。上例花括号表示注册表中的动态模板参数，不是具体控件ID的字面字符；`candidate_ref/review_ref`由前端统一映射为符合命名字符集的稳定不透明引用，不直接拼正文、数组下标或未经规范化的UUID。列表先定位页面/容器，再用稳定的非秘密对象 ID 或局部实例标识定位项，不用索引、当前排序、显示文字或屏幕坐标。数据库对象 ID 仍是可关联元数据，测试证据只保留合成数据所需范围，不因此开放业务数据日志。

共享组件由调用者传入所属作用域；同屏多个实例必须能明确区分。隐藏/卸载的旧页面不能产生歧义。此规则要求测试定位在声明范围内唯一，并不要求所有 Flutter Key 在整棵树全局唯一。

| 标识 | 生命周期 | 用途 |
| --- | --- | --- |
| UI Test ID | 随组件契约长期稳定 | 找到控件/状态；不含 run_id |
| case_id | 随行为规范稳定 | 必需用例与覆盖矩阵 |
| run_id / shard / attempt | 单次执行/分片/尝试 | 数据隔离、运行报告与清理 |
| operation_id / request_id / job_id | 一次业务操作或任务 | 从失败证据关联服务端处理；不能替代 case_id |

### 唯一来源与消费方式

未来在 frontend/config/ui_test_ids.json 维护唯一注册表，包含 schema_version、静态标识和显式允许的列表模板/参数。经受管生成器生成 frontend/lib/generated/ui_test_ids.dart 的常量/构造器；Playwright 读取并校验同一 JSON，不另写一份 TypeScript 字符串目录。动态模板只接受限定格式的非秘密身份参数，不允许任意用户文本拼接。

这是前端自有的 UI 元数据；权限、错误、埋点和业务事件仍由后端契约导出。生成流程纳入 [脚手架蓝图](../scaffold.md) 的 manifest、确定性比较和来源摘要。改名/删除必须一起更新组件、页面对象和用例；静态检查验证非法格式、重复注册、未知引用及生成漂移，运行测试验证标识实际挂载及定位唯一。静态检查不能证明运行中的控件可操作。

### Flutter Key、Semantics 与无障碍

Flutter 内部测试使用 ValueKey 和 find.byKey；需要浏览器/原生外部定位的节点再暴露同源 Semantics.identifier。ValueKey 本身不会自动变成 DOM 的 data-testid。[ValueKey](https://api.flutter.dev/flutter/foundation/ValueKey-class.html)、[find.byKey](https://api.flutter.dev/flutter/flutter_test/CommonFinders/byKey.html)

Semantics.identifier 在 Web 映射为 flt-semantics-identifier，在 Android 映射为 resource-id。它是测试定位元数据，不能替代用户可读的语义 label、role、状态或焦点顺序，也不能通过重复嵌套语义破坏读屏。[Semantics identifier](https://api.flutter.dev/flutter/semantics/SemanticsProperties/identifier.html)

Web 默认不总是启用完整语义树。实施基线是在正常 Web 应用 bootstrap 持有应用生命周期的 SemanticsHandle，显式启用并验证性能与无障碍；不是只在测试包内添加特殊权限入口。若原型表明需使用正常用户可见的无障碍启用方式，必须先更新此基线并让测试验证启用前后行为，不能让 Playwright 静默依赖不存在的 DOM。[Web 无障碍](https://docs.flutter.dev/ui/accessibility/web-accessibility)、[ensureSemantics](https://api.flutter.dev/flutter/semantics/SemanticsBinding/ensureSemantics.html)

Playwright 可把 testIdAttribute 配置为 flt-semantics-identifier；默认 getByTestId 查找的是 data-testid。匹配到语义节点不等于该节点就是可 fill 的 input：页面对象必须按原型结果定位真实可编辑/可点击语义节点，验证焦点、输入、禁用态和错误态，不用坐标兜底掩盖问题。[Playwright Test ID 定位](https://playwright.dev/docs/locators#locate-by-test-id)

B0/B1 原型覆盖 TextField 输入、按钮、对话框、滚动/虚拟列表、路由切换与 Web 刷新；包含客户端和管理布局。Windows 外部驱动的语义映射另验，不能从 Web/Android 推定 Windows 可用。

## 3. 未来测试布局

以下目录是实施约定，本次只创建文档：

```text
frontend/
  config/ui_test_ids.json
  lib/generated/ui_test_ids.dart
  test/                       # flutter_test：unit/widget
  integration_test/           # 公共应用内流程
  test_driver/                # 锁定 SDK 所需的 Web driver 入口
  patrol_test/                # Android 原生补充，不复制全部公共用例
tools/e2e/
  package.json                # Playwright/TypeScript 开发依赖
  package-lock.json
  tests/                      # 浏览器专属用例
  pages/                      # 定位/交互适配，不埋业务通过条件
testdata/
  assets/                     # 固定合成/授权样本及 manifest
  scenarios/                  # 声明式场景，不含凭据
backend/tests/support/        # 测试数据工厂与受控验证支持
```

Playwright 是开发工具，不引入 Node 生产服务。其独立依赖锁、类型/格式/lint 检查必须接入统一 check；Patrol 配置将实际目录明确交给锁定版本的 runner。页面对象复用定位和交互，业务断言留在用例；所有 runner 输出相同 case_id/变体维度。根 scripts/dev.py 根据已声明的阶段与必需用例调用真实工具，不能把未建立的 runner 标为成功。

## 4. E2E 操作流程

1. 创建本次隔离环境，核对 test/dev 实例、应用身份和资源清单；执行正式迁移与版本化基础目录种子。
2. 读取已版本化的场景，由受控工厂准备合法前置状态，输出资源别名和独立秘密通道；见 [测试数据规范](data.md)。
3. 启动真实 API、PG、Redis；异步场景增加真实 Outbox、Kafka、Worker、对象存储及事件链路。只在 dev/test 注入确定性 AI/TTS Fake，不把整个后端替换成响应桩后称作 E2E。
4. 启动所需客户端/浏览器上下文，通过正常 UI 执行被测动作，等待有界、可观测的业务状态。
5. 同时断言 UI 和服务端持久结果；以正常授权 API 为主，内部竞争/一致性断言可用仅测试 runner 持有的受控数据库验证器。UI 不持有数据库凭据或管理员旁路。
6. 记录实际 case/平台/runner/构建/场景摘要及结果；失败保存最小脱敏证据与关联 ID。
7. 无论通过或失败，先停止发起、处置在途任务/迟到结果，再按资源账本清理；清理失败记录为环境失败，不能继续复用污染环境。

测试注册时必须从注册 UI 创建账号并验证后端结果；测试收藏时可预建有效账号和材料，再真实登录并收藏。禁止用工厂直接制造目标成功状态，或把内存中的成功提示当作已保存。首版只允许同一run/case/shard/variant/attempt/actor/audience内复用通过正常UI登录取得的context；不同执行身份重新创建账号/会话并UI登录，不能从通用登录setup复制storageState或注入Token跳过步骤。登录、恢复、退出与撤权专项仍完整验证各自目标路径。

等待保存状态、服务端记录、任务终态或确定的 SSE 事件；每次等待有超时与诊断。不能用固定 sleep 猜执行结束，也不能对持续动画/长连接无条件 pumpAndSettle。时间控制范围见数据专题，浏览器 Cookie、Redis TTL 和 OS 时钟需要单独真实时间验证。

### 首批可执行闭环

| 范围 | UI 目标动作与服务端证据 | 特别约束 |
| --- | --- | --- |
| B1 登录→收藏→列表 | 使用合成账号正式登录，读取 me/access，选择合法材料来源，新增收藏；重读/刷新后存在且归属正确 | A/B 独立数据；无权时入口/请求均拒绝，不能所有账号都给管理员 |
| 账号→资料/头像/语言→改密 | 用最小注册账号跳过/重进引导，保存/清除可选资料，上传并替换受控头像，选择英日目标及当前语言，再修改密码并重新登录 | widget覆盖字段/错误/无障碍；API/真实PG与对象存储证明revision、私有媒体和旧会话撤销。Web同一context执行A→B并确认`/users/me/avatar`不复用A；改密提交后丢响应由API/集成层证明结果未知且不重放。恶意图片主要在后端低层验证，E2E各平台只选一份合法图和一个失败恢复路径 |
| B2 收藏→AI习题 | UI先取得选择预览再确认生成，真实Job/Outbox/Worker，收到状态与结果并查询持久习题 | Fake仅模型边界；预览不调用模型，覆盖重复确认/投递、取消/故障、A/B隔离，不建立复习队列 |
| AUTH Web 会话 | 正常登录、刷新、多标签同步退出/撤权及拒绝旧会话 | 同用户多标签使用同一 context；两个用户使用独立 context |
| AUTHZ 用户/后台 | 菜单/按钮/路由可见性与 API 授权一致；直接深链和伪造资源 ID 被拒绝 | 固定行为矩阵按真实授予权限组合执行，不硬编码“角色名等于允许” |
| 三类材料功能实施后 | 显式选择小说/课本/试卷导入，分别进入章节阅读/单元学习/考试准备；小说扩选回跳，课本词表及逐题反馈，试卷冻结后整卷交卷 | 分别建立页面对象/Test ID命名空间与就绪断言；不把同一阅读页三种标题或一种类型的通过当三类验收；按阶段只执行已交付切片 |
| 教材/试卷展示分期实施后 | 教材按原顺序浏览八类角色→图表/译文/原文对照→回到源位置；试卷校对确认→五类控件输入→打开共享材料再返回→重排后保存与复盘 | 按[PRES契约](../../contracts/learning-presentation.md)分阶段取证；widget覆盖分类与边界，E2E选真实组合路径，核对答案/空位/焦点/服务器状态；未知结构与完整原件越权拒绝，不能用校对时能看到答案证明考试投影安全 |
| 试卷听力分期实施后 | 选择文字稿→查看AI听力题/脚本/题目候选及证据→确认/改绑/拒绝→生成私有TTS→冻结版本→开考预检并按策略播放；另覆盖从试卷正文提取脚本 | 阶段2只验候选/校对，阶段3验Fake TTS任务与持久资产，阶段4验实际场次；目标确认和audio ready必须由UI/正式任务产生。有限次数至少在同场次刷新与显式跨端接管后显示相同剩余值，丢响应用同active attempt恢复，Range/签名刷新不重复扣次；完整播放/续播期限结束后旧attempt不能从头播放，点击重播领取并消耗新attempt。并发超领/首字节与未知交付由更低层真并发验证。题面DOM/Semantics/缓存不出现隐藏稿或答案；原始音频选择在P0没有可用入口，伪音频提交由API负例证明拒绝 |
| 文件与考试功能实施后 | CSV 实际下载/重导入与内容核对；考试答题保存、刷新恢复、交卷后锁定和评分状态 | 系统文件选择另有原生证据；试卷格式采用最终确认范围 |
| 多本/AI习题/错题实施后 | UI创建两本→同词加入两本→选择本/时间/掌握或全部/收藏错题→预览确认→AI生成→真实作答/评分→自动错题留档/收藏→读取掌握原因→删一本后词/历史仍在；CSV v2按阶段往返 | Android独立列表/条件页、Windows/Web分栏/键盘分别取证；Test ID注册单源，不能手改状态、工厂预填目标成功或靠前端动画造错题；预览不调用模型，双端/辅助/重评/收藏竞争优先在更低有效层验证 |

Playwright 默认每用例独立 context；不在不同用户、用例、变体或重试之间复用storageState/可变会话。同一用例内为验证真实会话恢复而保存/恢复本人状态，须明确为目标步骤、遵守秘密文件约束，并使用同一actor/audience；不能借此跳过该用例的首次UI登录。多标签、两个用户、管理员与普通用户的关系由场景明确表达。[Playwright fixtures](https://playwright.dev/docs/test-fixtures)、[浏览器上下文隔离](https://playwright.dev/docs/browser-contexts)

### Flutter布局、输入与平台适配矩阵

适配行为与FLT验收由 [Flutter开发与适配规范](../flutter.md) 定义。每个功能切片登记实际需要的layout/输入/系统能力组合；不将Android等同compact，也不把Web等同expanded。测试按最低有效层分配，避免机械展开所有尺寸×平台×输入的笛卡尔积，已经承诺的必需组合不能因环境缺失省略。

| 变化 | 必要方法/场景 | 关键断言 |
| --- | --- | --- |
| 布局边界 | widget在集中断点的两侧及精确边界设置逻辑尺寸；含窄高、宽矮与正文局部容器 | 导航/列数可预期，无溢出或不可达操作，内容不会因全屏较宽而被过窄子列遮挡 |
| 重排与输入 | widget改变尺寸/文字缩放/键盘insets，目标平台补实际输入法/窗口或方向切换 | 在已输入、选区或任务进行中切换；编辑值、业务ID、内容定位保留，不重复提交/模型调用/订阅 |
| 触控与键鼠 | compact触控路径、expanded键鼠增强；受影响功能补窄桌面键鼠与大窗口触控 | 相同业务结果，非hover可完成，键盘焦点/弹层返回正确，无隐藏旧控件歧义 |
| 无障碍 | widget语义/触控目标检查，实际平台读屏与大字输入/错误状态 | label/role/状态正确，技术ID不被读出，关键文案可达；截图/golden只补外观，不能代替操作 |
| Android系统行为 | Patrol/实际设备证据，按当前功能选择软键盘/返回手势、文字稿文件URI、音频中断、前后台恢复 | 系统取消/拒绝可区分，恢复重验权限与任务；听力播放次数/场次不因进程恢复重置；浏览器设备模拟不替代原生行为 |
| Web/Windows系统行为 | Web用Playwright验证窄/宽窗口、历史/刷新/输入、文字稿文件与自动播放限制；Windows按已有原生分工验证文件选择和真实音频 | 缩放/刷新不重开场次、不误报保存，平台凭据/文件/媒体路径独立有效，听力稿/播放策略不泄漏或重置 |
| 性能与日志 | 真机profile/实际浏览器/Windows样本，按已登记设备和指标测量 | 长文档/列表/图片/流式状态无不可接受退化；重排不重复业务埋点，输出不含正文/秘密 |

同一业务动作在互斥layout中优先沿用同一UI Test ID，专属交互控件可有自己的已注册ID；当前活动页的定位范围内必须唯一。页面对象可适配“打开筛选”等交互步骤，业务断言保持一致；不能通过跳过移动端独有步骤或用坐标点击掩盖定位缺口。

适配参数写入既有场景/执行variant：逻辑视口、DPR、TextScaler设置、输入方式、键盘条件与目标平台；额外观测元数据包含实际设备/浏览器及构建模式。unit/widget允许受控参数模拟，E2E记录实际值。尺寸切换是同一case中的目标动作，例如compact_to_expanded变体预先登记两个状态，不在运行中改run/actor/variant身份或重新生成账号绕过状态保留验证。所有数据仍遵循 [测试数据](data.md) 的隔离/清理规则。

B0验证壳与基础控件，B1验证登录/合法选区收藏的重排与账号状态，B2增加运行中任务切换；小说阅读器、课本单元页、考试页各自的重排/输入/恢复与相关性能测试随功能交付，不能用共享文本控件测试代替三类页面。音频同样按交付范围执行，测试范围和全量测试时机仍以AGENTS为准。

## 5. CI、发布与证据

小阶段/bug修复及对应PR只执行与改动直接相关且必要的规则/组件/契约/E2E；大阶段或发布大节点执行已交付范围内完整必需平台矩阵，节奏以 [AGENTS.md](../../../AGENTS.md) 为准。选择范围受版本控制，不得因runner缺失或设备不可用自动缩小。skip、xfail、未执行、缺分片及环境失败都不算该必需项通过；重试保留首次失败，不用重试转绿掩盖不稳定测试，门禁沿用 [测试规范](strategy.md)。

integration_test/Patrol 的测试入口构建与真实发布制品分别记录。release 优化模式不等于 production 环境；对隔离 dev/test 的 release 构建可以使用受限 Fake，但实际候选制品仍需独立启动与平台冒烟证据。不能从带测试入口的包推定最终安装包、Cookie 配置或正式构建身份通过。

报告包含 case_id、variant、run_id、shard、attempt、平台/设备、runner 和版本、应用/API 构建摘要、数据/场景摘要、耗时、断言结果、首失败/复测关系和清理结果。实际 required_cases 及覆盖分母的校验继续由总则负责，不在此另建宽松门禁。

截图/录屏、浏览器 trace/HAR、storageState 和网络日志可能包含密码、Cookie、Token、Key 或私有正文；控制台脱敏不能清洗这些文件。默认采集最小且已确认安全的证据；敏感步骤关闭相关采集，无法可靠脱敏的产物不上传。原始 storageState 不作为普通 CI 附件或日志上报；临时秘密/认证文件使用受限工作区、短留存和确定删除。业务日志仍通过既有白名单接入统一观测，不把大体积测试录屏和 trace 直接写入 Loki。

## 6. 专项验收项

以下 UIE 是实施验收标识，当前均未执行。由阶段清单显式纳入 required_cases，与 SCF/业务用例建立映射；检查设计、工具原型和运行行为分别记录，不能勾一个文档项代替运行证据。

| ID | 必须证明 |
| --- | --- |
| UIE-01 | 注册表为唯一来源，生成可重现；非法/重复/未知 ID 和手改生成物被拒绝 |
| UIE-02 | 关键控件/状态可由 Key 唯一定位，列表重排和本地化不破坏目标定位 |
| UIE-03 | 正常 Web 应用语义启用；identifier、可访问标签/角色、输入/焦点/对话框均通过真实浏览器原型 |
| UIE-04 | 三端公共流程与平台专属操作按矩阵分别举证；Windows 未验证原生驱动时使用明确人工记录，不能虚报自动覆盖 |
| UIE-05 | 被测动作经正常 UI，真实鉴权与持久层断言成立；Fake 只替换声明的外部供应商边界 |
| UIE-06 | 多用户 context、同用户多标签、原生设备与账号切换隔离正确，并与 TDS 场景对应 |
| UIE-07 | 必需结果/分片齐全，首失败和复测可追溯；测试入口包与最终候选制品证据明确区分 |
| UIE-08 | 日志与附件都按各自渠道脱敏，秘密不进入注册表/普通产物；等待有界，清理失败使环境失败 |

B0先执行注册表/生成静态项及最小定位原型；B1/B2随真实流程补齐关联运行项。尚未到期的业务功能不是本阶段通过项，也不能因此遗漏最终发布所需的专项项。
