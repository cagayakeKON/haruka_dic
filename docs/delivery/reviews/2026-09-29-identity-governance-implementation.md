# B2b 身份治理实现与切片复核

## 2026-09-30 正式验收候选（当期验收通过）

本次候选来源为 `106eac8647e08c377be72c5f96b0f0da253f5e78` 加本轮集中修复；正式 Web/Android 必要实操、集中修复和root独立定点复核完成，B2b当期范围验收通过。本轮修复以包含本记录的本地提交为准，实际 commit 哈希见交付消息及 Git 历史。下文 2026-09-29 内容保留为历史证据，历史端口、schema 指纹及未运行状态不代表当前候选。

| 证据 | 当前事实 | 复核及边界 |
| --- | --- | --- |
| 已确认 Flutter mock | 亲自操作 `7488b19` 工作树的管理登录、五个治理栏目、用户摘要 dialog，桌面 1400×900 与手机 390×844；隔离预览 8774 | 已完成桌面/手机正式对照；授权与真实数据允许差异 |
| 正式 Web | 当前 release build 成功，5173 直接提供该构建；早期管理登录、概览、菜单、策略和审计真实读取已操作 | 已完成；最后 Web 退出204 |
| Android | 独立执行者已有 mock 与正式用户端首轮实操 | 最终 APK 与全部必要用户路径已完成 |
| 集中前端回归 | 身份稳定路由、人工恢复撤权清退、会话作用域缓存、菜单配置、审计显式筛选与新旧契约消费定点用例通过 | 定点静态无问题；必要实际路径完成 |
| 共享契约 | Python 单向生成 customization 样本，Dart 消费并断言旧字段缺失兼容；独立 review 后提升 `reviewed_schemas_sha256` 为 `a42c4fc998df0038b81514aa71a22fd5e09c942ae9c9ead0d852e4c73e84f9b4` | 后续 schemas 变化仍需重新 review |

本轮修复包括人工恢复权限 scope 漏项、无关 global revision 导致路由 State 重建、配置标题/图标/排序未投影实际导航、审计筛选缺项及用户会话 dialog 重开重复读取。治理写由同一明确操作的 operation ID 提供 Idempotency-Key；401 不自动重放。最终 Web 实操受到真实管理员登录限流短暂阻塞，保留限制并等待自然到期，没有清除或放宽。

8650f13 当期验收时的 Web 构建与 5173 实际提供的 `main.dart.js` SHA256 同为 `be8547577dcff6001111d73d667b74d27ce5aeb425ec32e8857f3075347c40f1`。实际启动参数直接指向 `frontend/build/web`，不使用旧复制发布目录。

2026-09-30 再次打开 `http://127.0.0.1:5173` 的当前构建：用户登录有「忘记密码？」、没有注册入口；`/recovery` 是邮件申请页；`/admin/login` 是「管理端，独立登录。」。这次没有管理员会话，没有进入治理页面。语义树当时仍留着「正在验证账号与服务…」，画面本身已经是上述表单。

已完成的最终 API 路径：管理 UI 策略预览后 PATCH 200 切为 approval/manual；菜单 dialog 编辑查询标题、顺序与图标后 POST layout 200；已注册待审批账号的摘要首次读取会话 200、关闭重开不增加读取。审计逐字输入 action 跨等待保持焦点且提交前读取不增加，点击筛选后真实读取，再开关已加载行详情额外 GET 0，筛选草稿保持。桌面和手机截图保存在忽略的 `dev/.local/governance-review`；不保存秘密响应或 Token 可见截图。菜单实际用户导航投影、审批及恢复结果均已完成。

本次为 B2b 当期验收，只执行受影响组件、契约及必要 Web/Android 路径；Windows 原生、全仓门禁、B2c 和阶段 1 联合验收没有运行，不据此标为通过。

### 本轮实际失败与集中修复

| 发现方式 | 失败事实 | 修复及复核 |
| --- | --- | --- |
| 独立代码复核 | 人工恢复 scope 漏 `admin.user.update`，有权也无法核验，撤权不收敛 | 补权限 scope，组件验证核验与撤权清内容；真实 Web 已核验签发 200 |
| 路由复核 | 无关 global revision 改 ValueKey，销毁背景页 | 身份 key 排除无关 global 值，router 级断言同 State、搜索草稿与读取次数 |
| 实际导航 | 配置标题、顺序、图标未投影实际菜单 | 新旧兼容 DTO、明确 customization 标记，同壳渲染；真实 Web 保存 200，Android 亲自确认第一项「查询验收」与 book 图标，随后 UI 恢复原值 200 |
| 审计规格与 UI | 仅结果筛选，缺少时间/action/actor/target | 补显式筛选与已有行详情；Web 逐字输入焦点稳定，apply 前无读取，详情开关 GET 0 |
| Android 会话 dialog | 关再开重读第一页 | 身份/会话作用域缓存，成功撤销失效；共享合并 Future 全部执行代次 fence，两个合并 caller 迟到均拒绝 |
| Android 实际激活进度 | `Continuation` header 与服务端 `Bearer` 不匹配，已验证账号仍显示待邮件 | 对齐 opaque Bearer，按服务端 pending/rejected/active 渲染；最终 Android 待审批、批准登录与拒绝状态实测 |
| Android 实际 push 入口 | 首次回归用 `router.go` 没覆盖安全卡 `context.push`；dialog 出现底栏 | 真实入口回归先复现红；沿顶部 ImperativeRouteMatch 取匹配页，真实点击安全/查看会话回归绿。最后 APK 真实入口、关闭/重开/HOME 实操无底栏且业务 GET 0；不用早期合成 dialog 绿替代 |
| 最终手机管理截图 | 创建按钮与固定搜索宽度压挤标题成竖排 | 手机标题/创建与搜索分两排，同 controller/数据源；桌面保留，最后 Web 桌面/手机截图直接复核完成 |
| 人工恢复消费 UI | 签发 raw 码，但 reset 只接受完整信任链接 | 明确 manual/email_or_manual 模式接收严格 43 位码，manual 受理入口标记保留；默认邮件/验证仍检查信任来源与用途。默认拒绝/明确提交组件回归绿，新签发 raw 码经明确 manual 入口真实提交返回 204 |

第一条人工恢复已由 Android 真实申请、Web 核验签发，再从用户 Web 以受信任同用途链接明确提交并返回 204。Android 旧会话 dialog 清退，新密码重新登录成功；PG 同次 `password_recovery` 撤销对应旧 session，Loki 有相同 request 的 204。HOME 窗口没有 `/me/access` 401 证据，不把匿名前端日志的 401 误归到该会话。

Web 登录限流 429 与快速输入遗漏产生的 401 保留为过程失败；采用逐字真实输入、失焦与提交前值匹配确认，等待限流自然结束。近期重验不足的菜单写返回 401，未自动重放，重新密码登录后由用户明确再次保存成功。首次隔离管理员没有 learner 管理上限，摘要读取 403 正确拒绝；只补合成前置管理角色与受控上限，未预置审批/恢复结果。

### 当前实际 UI 矩阵

| 路径 | 最终事实 |
| --- | --- |
| 管理五栏目与 mock/正式直接对照 | 桌面、手机登录、用户、角色、菜单、策略、审计均亲自操作；最终手机两排 header 已直接看图复核 |
| 角色创建、边界预览、删除 | 空合成角色真 UI 创建/预览/二次确认删除 200，无残留；没有宣称每个角色按钮均实操 |
| 菜单配置与实际导航 | 真 UI 保存标题/顺序/icon 200，Android 实见查询验收/book/首项；真 UI 恢复后 Android 原标题顺序恢复 |
| 审批与拒绝 | Android 真注册/邮箱验证，Web 批准/拒绝 200，Android 准确 pending/active/rejected 与正常登录 |
| 人工恢复 | Android 请求202，Web 核验签发200，受限文件安全交付；用户 Web 链接消费204，Android旧内容清退、新密码登录；第二个新挑战 raw 码明确消费204 |
| dialog/搜索连续性 | 管理摘要重开与审计详情开关额外 GET0；Android真实安全卡 push→dialog→返回/重开/HOME业务GET0、背景稳定无底栏，搜索逐字跨防抖仍focused |
| 权限与会话清退 | Web停用200→Android旧dialog/邮箱清退；Web启用200→Android重新登录；单个当前会话撤销先401近期重验，密码重登录后明确提交200→Android清退，PG分别account_disabled/admin_revoked |
| 初始状态恢复 | 策略 UI 恢复 closed/email200，后端只读确认revision3、邮箱验证仍true；菜单原值已恢复 |
| Web管理退出 | 原实现远端未确认；Web Locks Zone修复后最后构建成功，真实管理菜单退出204并回登录，无远端未确认提示；PG同会话user_requested持久撤销 |

最终 APK SHA256：`034320ef13681e4fe0f2c52687e50b2cdfc1458a6b41ef100155d4da07852c18`。Android完整事实与截图索引在本机忽略产物 `artifacts/dev/identity-android-20260930/current-candidate.md`。Web截图在 `dev/.local/governance-review`，实际秘密没有进入截图、报告或输出。Token仅从当前真实UI复制到忽略的受限文件，消费经真实表单，不用HTTP替代。

### 独立 review 关闭依据与后端证据

root 第一轮集中定位、第二轮只复核本轮必要修订；没有全仓第三轮。事务内重新验证当前 actor/user/session与5分钟近期重验；丢失对应登录资格推进 audience epoch，重授不复活旧token；effective grant ceiling、deny解除与继承复核；按实际status动作鉴权；17个治理写接口必需Idempotency-Key；7日用途限定密文回执在当前授权且挑战仍有效时重展，摘要/加密密钥版本不符失败关闭，稳定查询摘要防止旧键重执行；拒绝审计提交与Outbox；0007→0008/0009升级保留已有客户端回执，均有定点回归及root独立源码复核。

证据索引为本机忽略的 `artifacts/identity-governance-backend-evidence.json`，保留每份XML真实结果和早期失败，不以一个合并总数掩盖失败：manual-receipt-attempt2的四个非过期case通过，expired由manual-expired-final同名case1项通过补齐；schema-final的additive case通过，迁移兼容由migration-compat-source-final1项通过补齐；final-security早期regrant失败由final-security-attempt2三种regrant与receipt共4项通过补齐；HTTP status错误由http-status-final启用/停用2项通过补齐；旧菜单seed断言由security-regression8项通过覆盖。policy receipt/stale reauth、拒绝审计HTTP/PG、日志秘密扫描与Loki正常/拒绝事件以该索引各原始报告为准。

当前共享契约 OpenAPI SHA256 `89595b5f703024cca7af2d31b3d72cbf73475584ae4e453b67f8f6ff04681d20`，database-schema SHA256 `c3d7028e4f0f6ee46f0d2104ab6da856be9ba67293eb99b0f781660997b85475`。components兼容扩展与共享样本/旧字段消费经独立复核后提升前述schemas指纹；新增必需header只改operation元数据。

Web管理退出的新增失败是JS Web Locks回调丢失调用Zone，导致退休绑定授权不传递；最小纯Dart编译JS harness在正常localhost/headless中原实现ZONE_LOST、修后ZONE_RETAINED。仅Web条件分支捕获调用Zone再run(action)，没有放宽ApiClient代次、实例、会话或退休请求白名单。新增browser unit尝试停在loading，没有执行结果，明确不记为通过；上述实际harness为最低运行证据。临时源码 `dev/.local/governance-review/zone-harness.dart` 直接导入现有 `frontend/lib/core/auth/auth_sync_web.dart`，调用 runZoned→withIdentityLock→异步等待后比较 marker 对象同一性；命令 `dart compile js --packages=frontend/.dart_tool/package_config.json dev/.local/governance-review/zone-harness.dart -o dev/.local/governance-review/zone-harness.js`，普通 localhost:8780 页面与锁定 Playwright1.63 headless读取DOM结果。原输出ZONE_LOST、仅生产实现修订后同一harness输出ZONE_RETAINED；临时产物不构成正式运行/构建依赖。

最后生成门禁发现拒绝审计 action 被错误用作未注册日志事件，定点改为共享已注册 `authz.denied` 并纳入后端事件清单；PG审计 action 保持不变，日志字段与业务安全行为未扩展。相关 Ruff/Pyright/registry 检查通过，最终 `scripts/dev.py codegen --check` 通过，报告 `artifacts/dev/codegen-635167e931594bc8bc02709a0e321322.json`。

限制：本轮不运行全仓覆盖率、Windows原生、真实供应商或阶段1联合验收；B2c未完成。没有宣称每个管理按钮均真实实操，分页超过20页静默截断仍是规模建议，未据无真实规模证据扩展本轮。当前空材料fixture没有真实滚动资产，不宣称内容长列表滚动实测。

当前管理退出持久证据：专属管理员最终会话于 `2026-09-30T04:51:01.599585Z` 以 `user_requested` 撤销，HTTP logout204于 `04:51:01.632543Z`，前置access200；见忽略产物 `artifacts/identity-governance-admin-logout-evidence.json`。

## 2026-09-30 用户桌面导航漏验与补修（修复复核完成）

用户在本地体验提交 `8650f13c401052b7ce3d39f1447c17a55e36e277` 后报告左侧菜单整块灰色，材料页仍正常。此前管理端与Android实操没有覆盖正式普通用户桌面侧栏悬停，存在验收漏项；先前通过不能证明该路径正常。

GPT-6.1 Sol亲自查看用户截图，并在独立headless Chromium 1400×900上下文正常登录、跳过可选资料、悬停正式导航后复现相同灰块。release脱敏错误处理没有console正文，不据此判定无异常。亲自操作已确认7488b19基线的材料/查询/我的导航与悬停，对照原侧栏布局。

新增 `frontend/test/app/desktop_navigation_overlay_test.dart` 运行真实HarukaApp、MaterialApp.router.builder与正常认证控制器，修前抛出 `RawTooltip: No Overlay widget found`，涉及侧栏Tooltip及通知IconButton；先前独立home:Scaffold手机组件测试未覆盖这种祖先关系。测试中的login-only样本无材料导航，首次查材料的定位断言也失败，随后定位实际允许的「我的」；不把fixture错误当生产根因。

最小修复仅为已登录普通用户持久壳包 `Overlay.wrap`。没有新增Navigator、改权限、删Tooltip或更换导航。锁定SDK `packages/flutter/lib/src/widgets/overlay.dart:930` 实现为Stateful wrapper、late final OverlayEntry，更新只markNeedsBuild，dispose才移除；不因普通build新建entry或销毁路由子页。root独立定点复核该实现与生产diff，并直接查看修后桌面提示截图。

source-only inventory尝试仍被既有大量未分类源拒绝，未记通过；本次唯一生产源haruka_app.dart已分类为core/frontend-foundation，没有新增生产源或清单改动，不扩大范围修旧库存。

真实桌面回归修后1项通过：悬停提示文字增加、移开恢复，通知提示可见；1400→900rail→390phone→1400保留同一背景Element，额外业务读取0。既有手机真实安全入口dialog回归1项及底栏导航2项通过。受影响2文件静态检查无问题。前次Android治理证据按原版本保留；本次只追加Overlay共同祖先窄路径：新APK88.0秒构建/安装成功，SHA256 `9181a7fe2918e95edcda5174a58a6fcade4736f9175a91fe98ce5ead076b374b`，真实My→安全→sessions/BACK再开/HOME返回均无底栏，dialog居中与层级正常。暖sessions200后有效窗口业务GET0，身份access校验仍有正常日志。证据索引为忽略产物 `artifacts/dev/android-overlay-20260930/report.md`，同目录window.json与security/sessions/return/resume/dialog-resume.png。没有重跑审批/恢复/撤销、改密码、权限或策略。

正式Web新版构建104.8秒成功，5173直接提供同一 `frontend/build/web`。磁盘与HTTP实际提供的main.dart.js SHA256均为 `f7ff0284f5d33cb60e9963b8341c57c64b3ead2e732190fba12c43d51c2dfcd2`。真实查询→材料→我的切换成功；材料首次GET1属于实际资源变化必要读。材料与通知hover提示正常出现、移开消失，通知真实点击进入既定未开放页面；900rail→390phone→1400保持/settings及正常导航，窗口只有身份/me/access1次校验，业务GET0。截图在 `dev/.local/governance-review/sidebar-fixed-*.png`。没有操作用户的浏览器tab、系统鼠标或改其账号/策略，真实验证使用独立本地上下文。

## 2026-09-29 历史记录

状态：**代码与切片复核已完成，本记录不签署 B2b 验收。** 当前 Flutter mock 的管理概览和审计已在桌面与手机视口实操；正式 Web/Android 对照和阶段 1 联合验收没有做。当时没有 Git commit；当前候选来源与本轮提交见上文。B2c 的配额、模型目录、任务运维和用量聚合没有实现。

## 已实现范围

管理壳内接入了授权内核、角色与授予边界、用户与会话、两端菜单、审批注册、人工恢复、审计查询和身份计数概览。任务、存储和模型用量仍显示「此功能尚未开放。」诊断查询和任意 LogQL 没有做。

PostgreSQL 仍是唯一授权账本。PyCasbin 只做只读投影。没有可写 `casbin_rule` 表，没有物理外键。显式拒绝优先。停用角色不贡献权限，也不传递继承。继承环和超过 4 层的继承会被拒绝。最后一个可登录的 `super_admin` 受保护。部署默认仍是注册 `closed`、找回 `email`。切换策略不改写已有账号状态、审批快照或进行中的挑战。管理员不能查看或设置永久明文密码，也不能代登录。邀请不在范围内。

审计为 `GET /api/v1/admin/audit-events`，概览为 `GET /api/v1/admin/governance-summary`。没有新权限代码，也没有新表。详情使用已加载行，变更摘要只保留短标量，并去掉键名含 token、password、secret 或 key 的字段。权限标识列表不返回。

成功的授权写入会重新核对当前权限。权限没变时，账号、角色、菜单、概览和审计列表不因全局授权版本变化而整页重拉。权限收回后，这些列表清空，仍打开的治理弹窗改为无权限提示。

## 切片复核

每一段都由独立只读复核完成。发现的缺陷已在同一次复核的定点第二轮关闭。没有做第三轮全量复核。

| 切片 | 复核 | 关闭的缺陷 |
| --- | --- | --- |
| 授权内核 | 授权内核复核 `ea0a9fba-9ec2-409f-9ce7-43c743212838` | 两轮后关闭 |
| 角色与授予边界 | 角色授予复核 `60488110-5af7-45fc-8422-f140205c912a`；上游上限缺陷复核 `1d6b7fe7-ac0d-441f-9853-a9deb96be737` | 启用角色的上限，以及停用祖先组合 |
| 用户与会话 | 用户会话复核 `3ec3980e-2ede-47c1-a130-65be36839496` | 三处缺陷 |
| 菜单与导航 | 菜单导航独立复核与菜单缺陷定点复核 `b13e220c-b3c3-493c-b781-4a7a8edccfa9` | 已有库不补菜单、手机不足两个页签、格式 |
| 审批注册 | 审批注册独立复核与审批绕过定点复核 `d3dcc17c-73c5-4677-8b7f-25fee7f0c34e` | 未审批账号不能借启用绕过审批 |
| 人工恢复 | 人工恢复独立复核与人工恢复缺陷定点复核 `aa8faa2b-e6ef-4514-90dd-7a24269fbf31` | 未绑定请求、过期被写成拒绝、回车通道、本人恢复列表、日志事件 |
| 审计与撤权刷新 | 审计撤权独立复核与审计缺陷定点复核 `f8e81979-b1a2-4f7d-853a-76dc09e26149` | 概览/审计因授权版本重拉、弹窗在撤权后仍留内容、翻页与筛选竞态、文档把权限列表写成会返回 |

## 本记录依赖的测试

审计切片当场运行：`tests/unit/test_audit_governance.py`、`tests/integration/test_audit_governance.py`、`tests/contract/test_models_export.py` 共 9 项通过。Flutter `governance_overview_widget_test.dart` 与既有用户、角色、菜单、策略组件测试在撤权修正前通过；修正后概览/审计、用户、角色、菜单组件测试共 7 项通过。更早切片的测试以各次复核记录为准，本次没有重跑阶段 1 全矩阵。

发布契约只更新了 `contracts/openapi.json` 与 `contracts/version.json`。OpenAPI 路径数为 73，其 sha256 为 `1eccf66d2990cd7a93b338569d50919fa0e5dcfd7a023be8dcf967175732cd2b`。database-schema、errors、permissions、telemetry 的既有哈希未变。`reviewed_schemas_sha256` 没有提升。

## 已对照的 mock

2026-09-29 用当前源码启动的预览 `http://127.0.0.1:8773`（`lib/main_preview.dart`）操作了管理壳。预览登录使用任意含 `@` 的邮箱和至少 6 位密码，不连接正式 API。

- 桌面 1400×900：登录后进入运维概览（账号数 128、待处理任务 4、请求成功率 99.2%，以及任务队列和授权变化两张卡片），再进入审计诊断。审计是四列表格：时间、操作类别、目标范围、结果。样例三行，行本身没有详情弹窗。
- 手机 390×844：同一概览改为上下排列；「打开管理导航」打开抽屉，进入审计诊断。结果列在该宽度下被裁到视口外，语义树里仍有「待提交 / 已提交 / 已读取」。选择导航项后抽屉保持打开，点遮罩后关闭。

更早占着 8772 的预览仍是旧构建，打开 `/mock/admin` 会报无此路由，不能当作这次对照。

## 本机库与进程

本地开发库 `haruka_dev` 已由受控维护从 `0006_avatar_assets` 升到 `0007_authorization_governance`，并补上了缺失的已发布菜单。`18081` 仍是升级前启动的旧进程，新路由在那里返回 404。当前代码的 API 在 `127.0.0.1:18080`：概览和审计未登录时返回 401，人工恢复的空 POST 返回 422。当前前端在 `http://localhost:5173`，已打开管理登录页；没有管理员会话，未进入治理页面。登录成功后的入口改为访问投影里的第一个已发布栏目，不再固定打开注册策略；正在运行的 5173 进程还是改动前的构建。注册策略仍是关闭，邮件找回未启用。

## 未验证

没有登录正式管理端，因此没有把接入真实数据的概览、审计、用户、角色、菜单、审批和人工恢复与上述 mock 并排对照。也没有在 Web 或 Android 上实操审批和人工恢复。Windows 原生没有运行。全仓覆盖门禁没有执行；库存扫描仍因更早未分类文件失败，本次新增文件已列入清单。弹窗闸门在同一授权范围再次变为当前时会重新显示原弹窗，这是复核留下的可选项，没有扩展。
