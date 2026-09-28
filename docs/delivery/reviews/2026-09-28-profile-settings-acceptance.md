# B2a 本人资料与设置切片验收

状态：**前轮基于旧 HTML 原型的视觉通过结论已撤回；按用户确认的 Flutter mock 主界面迁移，在本记录所列 B1/B2a 已交付路径完成定点代码复核、Web 与 Android 真实操作验收**。本记录保留 B2a 当时的后端、权限、缓存与功能操作证据；旧 HTML 原型与旧正式页面的画面对照、80%～90% 视觉判断及旧制品哈希只作为历史过程，不能证明新的唯一主界面。本次不为视觉还原虚构精确百分比，也不把 B2b/B2c、模型、音频或未交付的查询/练习业务标为完成；阶段 1 联合验收仍未执行。

## 主界面基线纠错与新制品实测

用户再次确认，2026-09-27 已接受的 **Flutter mock 渲染页面**才是主界面；其假数据和假动作应替换成真实业务，不能把页面、导航与 dialog 一并丢弃。原记录使用旧 HTML 原型比较新建的正式壳，遗漏了与已确认 Flutter 画面的直接对照，因此原视觉通过判断不成立。基线取自 Git `7488b19` 的独立 Flutter preview release，Chrome `http://127.0.0.1:8772/`；已亲自打开手机 390×844、桌面 1440×900 的登录、注册、我的/设置、外观、预算及管理端概览/策略/安全，并操作导航、开关、保存、表单和安全 dialog。此 Chrome 基线属于预览，不能当正式 API 验收。

本次迁移把 `/login`、`/register` 接到同一 mock 风格认证组件，`/settings` 与 `/account` 共用“我的”导航和卡片，改密/会话继续用 dialog；`/reference/materials`、`/material/:id` 与 `/collections` 使用已有材料/阅读/单词本展示，真实数据由账号作用域控制器注入；`/admin` 使用原管理壳，策略/安全接真实操作；`/environment` 复用 mock 服务连接画面并保留实际健康检查。未交付模块保留原视觉入口但明确不可用，不注入预览 fixture 或假成功。重复展示文件 `frontend/lib/app/{app_shell,home_page,environment_page}.dart`、`frontend/lib/features/account/presentation/preview_auth_pages.dart` 和 `frontend/lib/features/collections/reference_pages.dart` 已实际删除；原认证、参考数据仓储和选区安全业务层继续保留。真实页面仍按权限和账号作用域拒绝越界，不能用预览假回调代替。

### 新主界面运行与边界（当期签署依据）

候选正式 Web 以 `flutter build web --release --no-pub --dart-define=HARUKA_ENV=dev --dart-define=HARUKA_API_BASE_URL=http://127.0.0.1:18080` 构建成功，并在本地 5173 提供；当时 `main.dart.js` SHA256 为 `1763C3F1BDC5B5F47605E40F26FDC67B2EB9605EE01FD547EC4DD49797A63B46`。此包早于后续 reader 返回定位与会话撤销刷新修正，**不是最终制品**。Chrome 实际打开 `http://127.0.0.1:5173/login`，桌面蓝白左右登录布局与独立的 8772 Flutter mock 基线一致；从真实登录页点击“服务地址”到 `/environment`，再点“检查服务连接”，页面由忙态显示“服务已就绪”，实例为 `haruka-local-dev`。这只证明候选登录展示、导航与健康检查，不能证明登录后资料/设置或材料路径。

最初 Chrome 工具对 Flutter 文本框的赋值未进入画布，提交仅得到必填反馈。这是早期操作方法的证据，后来在真实编辑节点上逐键输入/填写并完成合成 A 登录，不再将“登录未通过”当作当前结论。

后续 Web 中间包 `6766B9A30083C3A392D39E3BADA84C6ECA006EBE9CB4A88B9E5D66A6F8448B27` 纳入会话撤销刷新与阅读返回修正；登录蓝区原 mock 文案随后恢复。2026-09-28 约 14:35 UTC，清除临时诊断后的偏好验证 release 候选 `main.dart.js` 的 build/5173 served SHA256 同为 `12801D5E0687EF3D23AB9B5D151A35F1E3E41A46A9BB8923263A1C478F14085D`。独立、无扩展的仓库锁定 Playwright Chromium 在 1280×800 真 UI 执行登录合成 A（`/auth/login` 200）→跳过可选引导→外观页点击“减少动态”，`PATCH /api/v1/users/me/settings` 200 后相关 GET 200，页面“已保存”；再按同一真实 UI 路径保存相反值，整页 reload 后开关仍与已保存值一致。服务端 14:35:24.239 `settings.updated` 与 14:35:24.241 HTTP 200 共享 request `2ceaa49b-b2fe-4be8-bdb6-49a59b95ae4d`/operation `b738b982-8bfe-42fa-92fe-ddb3f7c6c196`，14:35:24.495 再读 200；只读 PG 最终 `reduce_motion=on`、revision 21。截图与无秘密运行脚本位于忽略目录 `dev/.local/mock-ui-migration/web/`，未加入产品/提交。此证据证明无扩展独立 Chromium 的真实 Web 偏好保存与重入；不是对所有 Chrome 工具环境的通过声明。

同一 5173/18080 组合在装有浏览器工具扩展的 Chrome 标签（包括新 Agent Window）仍于约 14:28 UTC 复现：点击外观开关后浏览器报告预检不允许 PATCH，Network 显示 OPTIONS 200、PATCH `net::ERR_FAILED`、服务端没有 PATCH。单次受控 dev 诊断对该次 OPTIONS `Access-Control-Request-Method=PATCH` 的响应记录为 200 且 `Access-Control-Allow-Methods` 明确包含 PATCH，requestId `e62e8899-6932-47c2-934d-19d8ab2726ad`。具体 Chrome 缓存、扩展或中间层原因**未确定**；不能据此修改/放宽后端 CORS、会话或缓存安全条件。临时服务端与前端诊断均已撤销，18080 已恢复普通入口。Codex IAB 本轮返回 unavailable，不能写作它完成了这次迁移后的 Web 操作。

Android 官方 dev release APK SHA256 `4357221C7F197A69002A19DA8FF4150582D2D042CDFB8424AAC61A67DD2793A1`（编译默认 18080，原生已保存同实例 18081）在 emulator-5554 保留数据安装后，真实触控的阅读页仅剩一处长按提示，安全页退出直接返回 mock 登录，B 重新登录后材料与单词本显示正确独立空态且没有 A 收藏；稳定截图为 `dev/.local/mock-ui-migration/android/45-final-reader-single-hint.png`、`47-final-security-before-logout.png`、`48-final-logout-login.png`、`51-final-b-material-empty.png`、`53-final-b-notebook-empty-stable.png`。早一候选 APK `3B20E4AA40578480546250CBC7612B86B8B9EED273D80E7930FB70D70F670D82` 已在 A/18081 实际操作材料→小说长按选词→**读取已存在的解释卡**→点击收藏→单词本 1 条→同一居中详情 dialog；后端核对 resolve 200、收藏提交 201、再读 200，B 收藏仍为 0。该候选的功能证据仅用于后续未改的读取/收藏路径；重复提示与退出导航问题以 435722 包的实拍关闭。没有调用真实模型，不能写作本轮生成了解释。

桌面无扩展 Chromium 在新登录后直接进入单词本，A 已收藏词以原 mock 居中 dialog 呈现，布局与 7488b19 的双栏/弹层层级一致；此路径曾发现“返回出处”按钮依赖材料列表先加载，直接进单词本时未显示。现在按同实例出处 locator 与当前 `material.list`/`material.read` 权限决定显示，不为打开 dialog 读取材料；显式点来源进入 reader 后才按授权列表逐页定位目标并读取章节。最终 Web release（5173，build 与 served `main.dart.js` SHA256 均为 `0E8EAFF0A7F4F0A4FD57ADB802319D2D753383067D326D9EBD8271A9A0E53679`）在 1280×800 的无扩展 Chromium 完成新登录→跳过引导→**不访问材料页**直接进单词本→开“空”详情→“回到原文→”→原小说第一章/原句/右侧章节目录→点 `referenceReaderBack` 回 `/reference/materials`，材料卡仍在。稳定截图为忽略目录 `dev/.local/mock-ui-migration/web/headless-{notebook,word-dialog,source-return,reader-back}.png`。首次脚本用整句精确文本定位因 Flutter 分段语义超时，而页面实际稳定截图已有章节/原句；后续按真实 URL、画面与稳定返回 Test ID 重做整条路径成功，不记为产品加载故障。

Android 最终官方 dev release 增量 APK SHA256 `0200DB2BEAB3AC7E7545262E79D9325F3B4AD3DF79D32FF8B66C6F467D6ED78F` 保留数据安装后，A 重新登录且未访问材料页，单词本 1 条见 `58-source-final-a-cold-notebook.png`；14:55:09 UTC 真点“空”详情，`59-source-final-cold-dialog.png` 显示“回到原文→”；14:55:24 UTC 点击后 `60-source-final-return-reader.png` 显示原小说第一章/原句。以上文件在忽略目录 `dev/.local/mock-ui-migration/android/`。同窗实际 18081 安全日志：14:55:09–11 详情期间材料/小说/收藏业务 GET=0，另有 access 200；显式回源后 14:55:24.502 材料列表 GET200，14:55:25.073 小说章节 GET200。该增量包只修回源冷入口；435722 包退出/单提示/空态及 3B20 包真收藏证据按未受影响路径沿用，不把多个哈希混称同一制品。

新迁移的定点检查与前轮 B2a 结果分开计：auth/account 导航、表单与身份/会话作用域相关用例 17/17；正式 `/settings/security` 旧页在 logout 204 前卸载仍到登录的新增用例 1/1；app 壳/健康入口相关用例 6 项；参考 controller/flow 2/2、共用正式展示 3/3、阅读/dialog 最终 6/6（冷详情材料 GET 0，目标在第二页时材料 GET 2、章节 GET 1；部分运行批次有重叠，不能相加当作独立总数）。受影响 Dart 文件 analyzer 无问题，官方 UI Test ID/l10n 生成及一致性检查、Android 定位脚本 `py_compile`、`git diff --check` 均通过。`scripts/quality/coverage_manifest.json` 已更新此次物理删除/新增的展示文件；全仓 inventory 扫描已执行，但因其他既存未分类文件未通过；全量覆盖门禁未执行，也不宣称通过。旧参考/认证重复展示物理删除后的路由与导入已定点扫描；非作者主 Agent 完成首轮集中审查及缺陷定点复核。这里仅报告本次迁移受影响范围，不与下文历史 B2a 45 项、14 项或 105 项缓存基础检查累加。

弹层/切回业务读取计数须按**实际持久的原生服务地址 18081**解释，而不能按 APK 编译默认 18080 归属：迁移中间 APK 的 A 在 13:52:42–13:52:52 UTC 短 dialog 操作窗，五类设置业务 GET 为 0，access 1 次、sessions 1 次；13:57:28–13:57:41 UTC 短返回/切回窗业务 GET 为 0，access 1 次。此前对 18080 的相同操作计数是查错服务入口，已撤回，不作为静默验收证据。原生必要授权校验仍继续，不为保留界面停用安全租期。

## 前轮范围与方法（历史证据）

正式路径包括可选本人资料与私有头像、学习档案与引导、语言能力目录、显示和阅读偏好、查询预算、本机缓存清理、原生服务地址切换，以及权限、账号、冲突和缓存作用域。服务端以同仓库 dev API、隔离 Haruka PG 与合成 A/B 账号运行；Web 5173 指向正式 dev API 18080，Android 通过原生服务地址界面由 18080 切到同实例 18081。未调用真实模型，未修改 MyHome 或生产。

前端修改前已在 Codex **内置浏览器**分别打开并亲自操作手机、电脑原型的设置导航、资料、语言、外观、弹层和服务连接。正式 Web 亦在内置浏览器真实点击、输入、切标签和重入；工具截图留在本聊天原生图像记录，工具不提供 PNG 导出，未用其他自动化手段替代。Android 由 native Sol 在 emulator-5554 安装官方 dev release APK 后实际操作并保存脱敏截图于 `artifacts/b2a-android-acceptance/`；其未能直接看原型，我负责将实拍与我亲自查看的手机原型对照。最终视觉结论见下文，不把代码检查或单张截图替代真实操作。

## 前轮审查缺陷与关闭情况（功能证据保留）

| 编号 | 发现及本轮处理 | 关闭依据与界限 |
| --- | --- | --- |
| R1 | 正式 `/settings` 曾复用预览模块和假 Key、用量、测试、改密与会话流程；改为只展示 B2a 已交付真实功能，安全操作接真实路径，保留本人本机清理入口。 | 主 Agent 两轮定点源码复核；正式 Web 资料、学习、外观、阅读、预算和清理已操作。后续模型/音频/媒体配额仍未交付。 |
| R2 | 根主题及减少动态曾未消费持久设置；接入设置快照和账号/实例作用域。 | Android B 减少动态开关两次保存且 PG 最终 `system`；无 trace 正式 Web JS `511A405E…` 在 IAB tab 6 真实点 off→on→off，均显示“已保存”，切页返回及整页刷新仍 off，PG 合成 A 最终 `system`、revision 16。旧 Web 标签关后回弹的原因未证实，保留为候选观察，不虚构修复原因。 |
| R3 | 409 Retry 与表单 reset 曾丢草稿；改为保留草稿、显式再应用并仅刷新受影响组。 | 10:20 UTC Android A 先保存 profile，Web A 旧 revision 提交获 409、显示冲突且草稿保留，显式 retry 后再次保存 200。 |
| R4 | 头像删除、自述性别说明、时区显式清除及“我的”头像曾缺失或使用固定“遥”；补本人头像显示、缺失首字、删除及 nullable 字段。 | Web B 上传后资料页与设置入口均显示本人测试头像，删除后回退；后端上传/读取/删除有定点证据。 |
| R5 | 引导多组异步保存/选图与资料跨组保存可能穿越账号代次；预填还可能覆盖已有双语、水平与目标。 | 动作内固定账号、实例、会话、cache scope 并逐 await 核对；只补用户实际改动/缺失字段。局部回归及主 Agent 定点 review 已关，A/B UI 隔离已见。 |
| R6 | 原生服务地址及身份映射可能复用旧实例凭据/权限，旧异步结果越界；表单探测失败、旧 pending 及重入反馈可能错显。 | 凭据按地址/实例/受众分区，切换立即关闭旧动作、加载新 policy；探测 epoch 防旧结果发布。auth/service 定点 26/26，表单 10/10。旧包 18080→18081、重启保留成功；`6C277CF6…` release APK 的失败后重入和旧 5 秒 probe 在途返回重入实操通过，见 `93`/`94`、`99`–`101`。 |
| R7 | 头像请求体/解码资源边界。 | 服务端前置 body 上限、独立解码进程硬截止、尺寸/格式/元数据约束；主 Agent 源码复核及后端定点测试已关。 |
| R8 | 头像提交并发幂等、垃圾回收与跨标签失效。 | 服务端共同父行锁、二次事务以 `populate_existing` 刷新已锁 ORM 行，避免旧 revision/指针；有界 GC；客户端成功 replace/delete 后定向失效 profile，失败/取消不广播，低层 20/20。 |
| R9 | 客户端空注册框架、语言目录与授权范围。 | 版本化 GET language-capabilities 登录基础可读，profile/avatar 仍逐权限；后端隔离 PG login-only 用例证明目录 200、本人资料/头像 403。 |
| R10 | 正常保存与观测事件缺口。 | 服务端提交后事件、Web 客户端白名单、operation/request 关联及日志采集已补；下文区分可观察事实与 PG 原生日志边界。 |
| R11 | revision/Decimal/nullable 与共享 wire 兼容。 | 严格 revision、Decimal、nullable 写入；后端导出 wire 样本与 Dart 消费 4/4，审过的手写 feature DTO + schema hash 审查门禁为长期方案，不宣称 DTO 自动生成。 |
| R12 | 旧库迁移与隔离资源证据。 | 受控 0004→0006 迁移 1 项隔离 PG 用例通过；dev 旧授权库经正式 seed apply 补 v3 目录，仅 A/B 合成账号专属头像角色，原 learner 人工授权不变。 |

本轮 UI 定点还关闭：正式资料/设置页逐控件权限而不整页禁用；资料多组保存前后 scope fence；读取目录失败可显式重试；`SettingsSnapshotGate` 移除设置业务 30 秒强制读取与返回可见强制读取，首次缺数据和真实 scope 变化才读，身份 access 安全周期保留；本机清理使用真实 coordinator。初次登录三组 HTTP 200 却停在“重试加载”的旧问题由 repository scope attach 通知补齐，B 的新会话引导首次进入无需手动 retry。服务探测中不再预先显示失败，改地址作废旧确认；Back 重入清旧反馈且在途旧 probe 不能发布到新表单。新增必要 UI Test ID 由单一注册表官方生成。

## 前轮真实操作与平台证据（旧展示制品）

| 平台及时间（UTC，2026-09-28） | 操作及结果 |
| --- | --- |
| Web A 09:44–09:52 | 首次跨源 HTTP 登录 200 后 CSRF 401，定位为 Web Dio 未带浏览器凭据；启用 `withCredentials` 后 login/csrf/me/access/profile/study/settings 均 200。旧首进引导曾需“重试加载”，后续 scope attach 修正。此失败不作通过证据。 |
| Web A 10:00–10:04 | 资料、时区与设置保存，深色根主题即时显示并重登录恢复；服务短暂受控重启时未提交时区草稿丢失、页面安全关闭，记录为服务中断边界，不能冒充无变化弹层连续性。 |
| Web B 10:11–10:14 | 空资料初次引导无需 retry，跳过到正式设置；学习语言、阅读字体、预算与本机缓存清理真实 UI 保存/确认。上传合成头像后入口和资料均显示；删除后回退。B 与 A 的昵称、头像、主题不串。含未提交草稿时打开菜单/切标签后仍保留；安全日志 10:13:28–10:14:04 五类业务路由 0 次，me/access 2 次及日志 2 次另计。 |
| Android 旧候选包，截图 `01`–`22` | 原生服务地址 18080→18081 经 UI 探测、确认、退出和强停重启后保留，见 `09`、`11`–`17`；这项不归入后续 APK 的构建时间。 |
| Android 10:07:56 UTC 候选包，截图 `30`–`88` | SHA256 `EA8D855F8CB1EEA15BC797A13D8F1DB0A80A7C9DD3AADFBD62CB7F0D97F9E6BF`。A 资料保存与 Web 构成真实 409；B 语言日英多选保存、减少动态 on→off，两次后端提交 200 且最终 PG 为 `system`。无变化短操作窗口 10:22:04–10:22:21 五类业务路由 0、access 3。当前连接 18081 强停重启后仍保留见 `87`。 |
| Android 10:49:16 UTC 服务修复包，截图 `90`–`101` | SHA256 `6C277CF67AE2EA578F6128B10287EF3C2C2D596DA6901A4502A17F6CECBCB777`。无效地址失败后 Back 重入旧错误消失（`93`/`94`）；延迟 5 秒 probe 中 Back 重入，旧成功到达后仍无旧确认、按钮恢复（`99`–`101`）。此包早于手机视觉调整；其功能证据对最终包仍适用。 |
| Android 11:04:27 UTC 最终视觉包，截图 `112`、`114`、`116`–`118`、`120`、`123` | 官方 dev release APK SHA256 `0D485B832BF74B8FCB751B39114A2F7ABC5DB926CF07C4D87D67762A369DB320`。模拟器 UI 的稳定外观单卡主题/减少动态与独立预览见 `112`，三项主题菜单可点且深色根应用/预览即时生效见 `114`；“我的”稳定页 `116`。预算单卡与说明 `117`，逐键输入 5000 后焦点和摘要保持 `118`；同页未导航/保存地直接点 5000→10000 预设、停 2 秒，输入框/高亮 chip/蓝色摘要三处一致见 `123`。左上返回后稳定“我的”见 `120`。`111`/`113`/`119` 是过渡帧，不用于稳定视觉或预设结论；`122` 只证明返回重进时原服务端值。 |
| Web/Android A 10:20:13–10:20:45 | Android profile 保存 200；Web 旧草稿提交 409 无提交后事件、再读 200；Web 明确 retry 后保存 200，草稿未丢。 |
| Web A 10:29–10:31 | A 专属头像角色受控撤销后 authz_version 变化，头像按钮消失，资料仍可读写；恢复后按钮重新出现。B 与通用 learner 未改。 |
| Web A 约 11:04 UTC，最终视觉包 | 正式 `http://127.0.0.1:5173/settings/appearance` 的 Codex IAB tab 7 设 390×844 视口，直接打开页显示“外观设置”单返回，返回到“我的”；同卡主题+减少动态、独立预览卡与手机原型主层级对应。减少动态在新版页 on→off，最终 UI 为 off。预算页从 10000 逐字输入到 5000，每字观察焦点仍在文本框、摘要同步变化；未保存后用快捷值恢复 10000。截图留本聊天原生工具记录。JS SHA256 `BED76B97930E60B0C052C09CF493A63A061EAA32673D4EB1F767624091F1A05A`。 |

Android 第一次图片选择距上次 access 约 50.9 秒，超过 30 秒有效权限租期，被客户端安全中止，未产生 complete；第二次有效租期内上传及删除成功。该首次尝试不是正常取消连续性通过项。模拟器此前发生系统级 ANR，冷启动恢复后才进行有效操作；不计为产品缺陷或成功路径。

手机原型直接操作见本聊天 IAB tab 2（`http://127.0.0.1:8767/phone.html`）；候选 Android 实拍 `50`/`67`（我的）、`51`–`53`（资料与键盘/草稿）、`69`/`70`（语言）、`74`–`76`（外观）、`77`（预算）、`85`（连接）及最终 APK 的 `112`、`114`、`116`–`118`、`120`、`123` 均在 `artifacts/b2a-android-acceptance/`。我的首页卡片分组、本人头像入口、语言复选与保存、预算快捷值与蓝色主操作的空间层级接近原型。真实资料把头像操作放在表单前，增加私有上传/删除，保留了原型未表达的权限与错误状态；语言选项依版本化目录显示比原型更多的母语，这是契约差异。主壳将未交付的查询/练习等导航隐藏，不伪造入口。初次视觉复核发现手机外观三张分离卡、重复“减少动态”标题及缺少原型预览文案，预算缺少解释层级，手机详情又有双返回/品牌标题；这些明显偏离已集中修复。最终 Web 390×844 实操与 Android 稳定实拍均呈现同卡主题+减少动态、独立预览文案卡、预算说明/摘要、详情标题与单返回。桌面正式设置在 1280×720 IAB 与已操作的桌面原型比对，保留原型分栏/卡片层级，真实功能隐藏未交付模块。该次以 HTML 原型为基线的整体还原判断已撤回：用户此前确认的 Flutter mock 才是唯一主界面基线，旧画面对照不能支持 80%～90% 的结论。上述真实权限/资料/语言目录及未交付入口差异仍存在且已说明。

## 前轮自动检查与日志边界（旧展示制品）

局部而非全仓结果：前端缓存/头像 20/20（`cached_settings_repository_test.dart`、`avatar_upload_test.dart`），auth/service 26/26（`auth_controller_test.dart`、`auth_security_test.dart`、`service_endpoint_test.dart` 所在轮次），service 表单最终 10/10（`flutter test --no-pub test/features/settings/service_endpoint_test.dart`），gate 3/3，guide/HTTP adapter 相关轮次 14 项、共享 wire 4/4（`flutter test --no-pub test/settings_contract_samples_test.dart`），受影响文件 Dart analyzer 无错误。资料 widget 文件最终 `flutter test --no-pub test/features/settings/profile_partial_save_widget_test.dart` 5/5，其中原有资料/冲突 3 项与新增 390/1440 尺寸真实 switch tap 2 项；新展示改动后的同文件 5/5 再通过。历史缓存基础证据见 [2026-09-27 的 105 项结果](2026-09-27-cache-version-lifecycle-fixes.md)；本轮变化另按上述缓存、auth、gate 回归验证，不将历史结果写成本轮重跑。

后端从 `backend/` 执行 `.venv/Scripts/pytest.exe tests/unit/test_avatar_image.py tests/unit/test_profile_settings.py tests/unit/test_client_cache_catalogue.py tests/contract/test_models_export.py tests/unit/test_database_models.py -q` 为 45 passed；telemetry/export 两文件选择 14 passed，其中 7 项与 45 项重叠，不能相加为 59 个独立用例。隔离 PG 命令使用 `HARUKA_MAINTENANCE_TEST_CONFIG=dev/.local/test-maintenance.env`，执行 `pytest backend/tests/integration/test_profile_avatar.py backend/tests/integration/test_authentication_flow.py::test_login_only_identity_survives_dependency_faults_without_profile_grant -q` 为 2 passed；`pytest backend/tests/integration/test_migrations.py::test_prior_revision_profile_avatar_upgrade_preserves_existing_account -q` 为 1 passed。后续相同资料头像节点为限时保护及安全关联各定点复跑 1 passed，不累计独立用例。受影响 Ruff check/format 与项目配置 Pyright 0 错误。生成物用 backend venv Python 运行 `frontend/tool/generate.py --write` 与 `--check`，一致性检查为 current；先前无 trace Web JS SHA256 `511A405EC76D9B18C3BF906CAA8EF8591DED7893B792160B627B9D3C71C2F509` 用于开关与重入验收，其后手机展示调整，最终 `flutter build web --release --no-pub --dart-define=HARUKA_ENV=dev --dart-define=HARUKA_API_BASE_URL=http://127.0.0.1:18080` exit 0（187.2 秒），JS SHA256 `BED76B97930E60B0C052C09CF493A63A061EAA32673D4EB1F767624091F1A05A`，已在 390×844 IAB 使用。最终 Android APK SHA256 `0D485B832BF74B8FCB751B39114A2F7ABC5DB926CF07C4D87D67762A369DB320`，官方 dev release 构建 exit 0（184.7 秒），受影响页截图 `112`、`114`、`116`–`118`、`120`、`123`。受影响 Dart 格式、analyzer、生成一致性与 `git diff --check` 通过（已有 CRLF 提示不属空白错误）。

忽略本地 `dev/.local/profile-settings-review/backend-evidence.md` 和 `loki-save-report.json` 保存无秘密明细。Web A 10:00:44 正常 profile/settings 保存，各有 HTTP 200、相同 request/operation 的提交后服务事件、ORM 与 Web advisory Loki 记录；头像 10:12:35 intent/complete、提交后事件和私有 GET 也已关联。PG 原生日志只证明对应 backend PID 的连接/断连生命周期，**不证明每次保存的 SQL**；live 安全日志不带响应头，头像 `private, no-store` 由路由固定设置与隔离 PG 集成断言支撑。18080、18081 为独立本仓 dev 入口，未触及生产。

## 前轮未执行范围与剩余边界（历史结论）

最终 Web 390×844 页面与 Android 官方 release 稳定实拍已由原型查看者对照；同页预算预设操作在截图 `123` 中复核，独立 reviewer 的源码、证据与文档定点复核已完成。早期截图 `119` 是瞬时状态，不作为稳定控件行为证据。未执行 Windows 原生运行、全仓或阶段 1 联合矩阵、真实模型及供应商调用；这些不属于本次 B2a 小阶段运行验收。FCACHE 未签全设备自动同步或未交付媒体配额与音频业务。

本切片未执行 Windows 原生运行、全仓测试或真实供应商调用；Windows 特有代码仅静态与复用低层核对，未把未运行项记作通过。未来模型、音频与媒体配额业务继续按所属小阶段交付。
