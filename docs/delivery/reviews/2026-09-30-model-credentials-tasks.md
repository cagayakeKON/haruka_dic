# B2c 本人凭据与模型任务实施记录

状态：当期工程实现、正式联调与两轮独立review完成，待用户验收；三项真实测试均 `KEY_REJECTED`，真实模型可用性未验证。所属阶段为阶段1的 B2c 小阶段，不以本记录替代阶段1完整矩阵或全盘 review。权威范围见[路线图](../roadmap.md)、[脚手架验收](../milestones/scaffold.md)、[个人设置](../../modules/settings.md)、[模型用量](../../contracts/model-usage.md)及[任务进度](../../contracts/job-progress.md)。

## 1. 用户确认与实施边界

2026-09-30 用户要求前后端同时由 GPT-6.1 Sol Agent 实现，全部实现和联调完成后由独立 Agent review；随后明确使用 goal 模式开始实现，并提供仅用于测试的个人 OpenRouter Key。秘密不进入本记录、仓库、日志或证据文件。

- 默认供应商为 OpenRouter，保留 Gemini 直连配置入口。
- 本轮仅授权 OpenRouter 文本、视觉、TTS 各一次真实供应商调用，共最多三个 attempt；无自动供应商重试，跨端读取同一已提交结果不增加调用。
- 文本/视觉精确模型为 `google/gemini-2.5-flash`；TTS 为 `google/gemini-3.8-flash-lite-tts`、`Kore`、`mp3`。公开目录及官方协议只证明登记依据，不提前证明个人 Key 或真实调用成功。
- Gemini 未取得真实协议证据，不显示已验证可用。本次不交付材料 OCR、学习查询、业务 TTS、共享词音或完整离线消费。
- 正式 UI 继续使用已确认 Flutter mock 主界面。编码前须亲自实操手机/电脑 mock；接线后须正式 Web/Android 实操及对照，不能用 HTML 或编译结果代替。

## 2. 协作与接口冻结

主 Agent 负责共享契约、生成输出、隔离验收进程、联调与文档；后端 Agent 负责 `backend/`，前端 Agent 负责 `frontend/` 与必要前端测试。独立 reviewer 在两端完成后加入，不参与实现。统一接口源由后端具体 Pydantic schema 定义，根 `contracts/` 与前端生成输出单向导出，不并发手改。

- 凭据安全 DTO、保存/轮换/撤销及影响预览：明确 revision、凭据代次与部署密钥版本；保存不测试，敏感操作检查现有会话五分钟内的密码登录事实。
- `users/me/model-settings` 是本人模型配置的独立投影，与既有设置共用 `settings_revision` 和父锁，不新增平行并发版本。
- 单能力测试只接受注册的最小样本与目录配置，202 返回 Job/Run 引用；结果读取、任务操作与 WebSocket 分别校验本人及来源权限。
- 默认单次测试限一个模型 attempt、零工具；文本/视觉超时60秒、TTS90秒；每人并发1、实例并发4；Job租约120秒、心跳15秒；WebSocket每连接最多100个任务。技术初值仍受部署硬上限约束。
- started/失败/unknown 均保留 attempt；unknown 不自动外发，旧租约和旧凭据结论不能覆盖当前结果。模拟事实与真实事实分开展示和记账。

## 3. 实际验证与证据

前后端已接入正式闭环；三项真实供应商测试已执行，但均返回 `KEY_REJECTED`，不能证明模型可用。独立第1轮 review 已执行并集中修复，最终定点复核另记于第4节。未执行项不记为通过。

必要集合为 SCF-B2-01～08、SET 单能力测试、USAGE-01～09 当期分支，以及直接受影响的身份 Outbox、邮件进程、设置并发、迁移/字典、契约生成和已安装入口。使用真实隔离 PG/Redis/Kafka/Worker；Fake 只用于 dev/test 供应商边界。Web/Android验证当期真实 UI，前端日志只验 Web；Windows只做静态及共享低层逻辑检查。

当前已完成的准备与局部证据：

- 前端 Agent 编码前亲自操作现有 Flutter mock，手机 `390×844`、桌面 `1440×900`；核对本人模型、Key dialog、单项测试、用量筛选、任务及管理任务详情。脱敏基线截图保存在本地 `artifacts/model-settings-ui/baseline-*`，不把 mock 成功当作真实供应商结果。mock 未覆盖的能力选择、取消和 unknown 状态沿用同一组件语言补齐。
- 隔离 runner 新增本人任务 Topic、带服务端所有权 tag 的私有 Bucket/受限对象账号、正式 Outbox/Worker console 进程及受控供应商模式。资源只操作当前本地 Docker 和精确 ledger 所属名称，失败准备仍可回收；模式切换只允许已停止且无未完成任务的专属实例。`dev.test_model_run_harness` 七项边界检查、`dev.test_model_log_proof` 两项脱敏回归和既有发布构建护栏五项，共十四项定点回归通过；对应实际 Ruff 配置、格式和 Pyright 通过。Windows 向容器传脚本的换行问题已修复，两个失败准备 run 的专属资源已清理。
- UI标识、错误目录和本地化采用[独立资源生成](../../../tools/codegen/dart-api/README.md)，四项生成器回归通过；新 OpenAPI 的全量指纹仍未签署，保留全部完成后独立审查的门禁。新增重新登录错误有对应中文反馈。
- [必需用例清单](../../../scripts/quality/required_cases.json) 登记 B2c 的八个 SCF 项和十二个 host/Web/Android 证据变体，声明源为 [任务验证流程](../../../tools/ci/model-task-procedures.json)。清单装载检查通过；此处没有创建通过记录，执行及独立 review 仍待完成。

- 用户明确本地开发使用 HTTP 后，改为同源 `http://localhost:18443`；正式 HTTPS/Cookie 安全约束不放宽。真实 loopback HTTP 转发与注册任务端点的 WebSocket Upgrade/帧转发两项回归通过；原 runner 邮件进程仅接受 core profile，现用同 run 私有 core 配置，任务进程用 jobs profile；Windows 凭据文件 CRLF 去除后对象存储认证通过。runner 当前九项定点测试通过，增加的资源修复及邮件配置回归不冒充业务验收。
- 最终锁定依赖构建非 editable wheel，在隔离虚拟环境安装后，从 checkout 模块之外导入并导出205个 API schema；API、Worker、Outbox 三个已安装 console 的真实资源启动/关闭均成功，记录 `artifacts/model-settings-ui/package-smoke.json`。没有通过 cwd 或 PYTHONPATH 回退 checkout。
- 本次补齐既有源清单中未登记的真实文件与新源，inventory-only 检查通过；未执行全量覆盖率分母/百分比门禁，不把该清单检查当成应用测试通过。全量门禁继续在阶段1大节点执行。
- 后端最终所选十项集成及六项单测全部通过（16 passed，118.89秒），精确节点、断言与源码指纹记录于本地 `artifacts/model-settings-ui/backend-tests.json`。覆盖凭据隔离/CAS/重新登录、幂等、unknown 不重发、已提交阶段恢复、轮换/撤权/取消边界、零限额和并发、过期租约 fence、真实 Kafka 重投递/消费者提交与 ACK 间隙、有权 WebSocket、已知失败用量及显式重试。未模拟成物理进程 SIGKILL，也未执行阶段1完整矩阵。
- unknown 与 invalid 两个故障节点用正式 Worker 日志出口定点复跑（2 passed，29.07秒）；六个实际 attempt/失败事件按 event/job/run 标识在 Alloy→Loki 查询中逐项匹配，Grafana 数据源代理可查询、健康均200，证据 `artifacts/model-settings-ui/fault-log-chain.json`。此项证明真实故障日志采集链，不以数据库状态替代日志证据。
- 首次正式模拟文本任务的 API→Worker 正常完成与 Web 接收日志按同一 request/operation/job/run 关联核实；`formal-normal-log-chain.json`、`formal-web-model-log-chain.json` 分别记录实际 Worker 和 `origin=client` 的 HTTP 事件在 Loki 中的精确匹配。接收端将内部 `frontend.received` 改写为已验证客户端事件名，不能只查该内部事件名称判断是否采集。
- 模拟运行全窗口脱敏证明覆盖本地43340行及Loki43371行、25个日志文件，最早本地事件已在Loki找到，没有截断；测试凭据与日英固定朗读样本未出现。运行仍在记录时两端行数可不同。高密度日志采用不重叠的一分钟查询窗口，保留总大小/条数/完整窗口护栏；四项脱敏与窗口连续性定点测试通过。此时尚未保存用户真实Key，真实Key证明须在授权实测后另行执行。
- 主 Agent 亲自操作正式 Web 的 `1440×900` 桌面与 `390×844` 手机布局，打开并取消 Key dialog；脱敏截图 `root-formal-desktop-key-dialog.png`、`root-formal-mobile-key-dialog.png` 保存于同一本地证据目录。尚未据此声明模型测试/用量/任务闭环已通过。
- 首次 Web 实操的管理入口测试假设已过时，登录本身200，显式入口定位仍在修订；Android 前两轮在服务返回路径定位失败，未注册/提交模型任务，失败文件保留，其中第二次截图是失败后的系统桌面，不作为服务页证据。新正式 UI 闭环尚待验证。

- 随后的正式 Web 文本、视觉、朗读三个模拟测试均形成成功任务；用量逐字输入、菜单开关、前后台及窄宽布局切换检查通过，显式应用筛选才产生一次相关读取。Android 后续运行完成登录、凭据输入取消、保存不调用、一次文本模拟任务以及视觉/朗读选择取消；该运行在用量页定位失败，原始失败报告保留，不将已通过的前七步记为整个流程通过。
- 联调发现统一日志上传使用普通写入路径，成功后自动读取权限，而权限读取又生成日志，造成间接递归。新增专用授权日志上传路径，仅省略成功后的权限刷新，保留普通写入的凭据、CSRF、账号代次、过期处理与错误栅栏；普通业务写入行为保持。三份日志/认证测试共33项通过，新增真实传输观察回归证明46个排队事件由三个批次排空、上传不产生权限读取，普通写入仍校验权限；受影响三文件静态检查无问题。记录 `telemetry-recursion-regression.json`，正式构建与静置验证尚待完成。
- 继续工作时旧服务句柄已不存在，OS核实所有候选Python/Haruka进程及相关监听均不存在，私有台账却遗留 `serving`。按该run精确身份恢复为 `stopped`，未删除资源或向进程发信号；`interrupted-run-recovery.json` 明确这不是正常停机证明，中断原因未知。Docker daemon与旧浏览器标签当时也不可用，正在恢复本机既有开发环境和保留的数据卷，不据此推测主机事件原因。

- 后续核实 Docker Desktop 在清理旧 IPC socket 时启动失败；仅停止本次启动的已核对身份进程，保留运行 socket 目录备份后恢复启动。Haruka 既有容器和数据卷恢复，配置与模板不同时未覆盖本地配置。四个此前成功的模拟 Job/attempt 均仍存在，没有重复执行。
- 最终日志修复后的正式构建再次实操：Web两项只读流程通过（45.2秒），用量逐字输入、菜单、布局和前后台操作仅在显式Apply发生一次业务读取；15秒静置只有一次日志上传，所有日志上传200。管理任务摘要dialog直接使用当前列表数据，无任务重读。Android新包 `44bf3cef199cc043909325447e390cb56d427987d6cb8e74a4ad67237a2810c9` 在恢复的既有 `Haruka_B0_API34` AVD上完成正式登录、读取已有结果及筛选/键盘/前后台草稿检查，四步均通过；不推定先前AVD名，不新增能力调用。证据为 `web-continuity-1790772622961.json`、`admin-model-1790772589452.json`、`android-model-final-read.json` 及相应脱敏截图。
- 断言核对发现目录仍启用但revision已变时，旧任务没有版本屏障。服务端现于内部versioned `generation_config.catalog_revision` 冻结目录整数版本，受理/显式retry分别冻结当时版本，调用及发布前复核；旧pending缺少冻结值时拒绝，须显式retry。供应商 `model_revision` 原语义保持。修复前原生JUnit为2失败/3通过，修复后六项调用/发布边界、非法供应商/任意端点及四项直接恢复回归共11通过（91.32秒），Ruff/Pyright通过；基础设施不可用时的五项fixture error单独保留。见 `backend-fences-result.json`，没有迁移或公开DTO变化。


- 真实 OpenRouter 测试由主 Agent 在正式 Web 单能力确认 dialog 分别提交一次。文本、视觉使用 `google/gemini-2.5-flash`，朗读使用 `google/gemini-3.8-flash-lite-tts`/Kore/ja/mp3；三个 Job 均形成一个真实 attempt，并以 `KEY_REJECTED` 封存失败，未重试。用量 `unavailable`、各 Token 分项为 null，未用零替代；保存本人 Key 和三项绑定前后真实 attempt 仍为零。`formal-before-live-calls.json` 至 `formal-after-live-tts.json` 保存受限事实投影，最终为真实3次、模拟4次；不保存秘密或供应商响应正文，不宣称模型可用。授权的三次额度已用尽，后续只读核对。
- 正式混合历史显示暴露模拟/真实聚合缺少分组字段的问题。`UsageGroup.simulated` 现为必填布尔值，服务端按该字段分组，用量汇总和结果卡分别标明模拟，模拟成功不计为真实成功。新混合账本定点测试通过（1 passed，15.51秒），unknown/invalid两项回归通过；测试中的真实分组行仅是聚合夹具，不冒充供应商证据。Dart状态/展示13项、权威DTO样本4项通过，受影响静态检查通过。失败测试因夹具调用名拼写错误的原始报告仍保留。最终构建后两端只读核对另记。
- 最新非 editable wheel 在独立虚拟环境重新安装，已安装服务源码指纹匹配；API、Worker、Outbox三个入口在checkout模块之外使用正式隔离资源完成启动/关闭，`package-smoke-usage-final.json` 全部通过。


- 模拟分离修复后的最终正式 Web 两项只读流程通过（43.6秒），`web-continuity-1790775188613.json` 为7个terminal Job、真实3/模拟4、15秒静置1次日志上传及仅主动Apply读1次，管理摘要dialog证据 `admin-model-1790775154018.json`。Android `android-model-live-read.json` 在新包 `835f8420354d5d0754a739fe0be49248188d444b14fd560c743e90e434b1172e` 实际登录、读取三条真实失败引用及输入/前后台草稿检查全部通过；Flutter语义树包含屏幕外节点，因此另行逐屏实际滚动截图，并亲自核对TTS/视觉/文本失败及相邻模拟标记，不把XML匹配当成全部卡片可见。真实attempt仍3、模拟4，`formal-after-final-read.json` 证明只读没有新调用。
- 主 Agent 再次亲自打开已确认 Flutter mock 的桌面及手机模型页，操作Key dialog及取消，随后操作最终正式两视口页面、返回和任务列表并实际滚动。同一外壳、导航、三能力卡片、按钮主次和dialog保持；真实凭据选择、声音/语言、版本及失败用量使卡片高度增加，是当期功能差异。无秘密截图 `root-final-model-desktop.png`、`root-final-model-mobile.png`、`root-final-real-tts-mobile.png`、`root-final-real-vision-text-mobile.png`（实际可见为文本及相邻模拟卡）与 `root-final-simulated-marker-mobile.png`；不以配色或编译替代直接对照。


- 停止后的真实Key全窗口脱敏证明通过：本地47份日志105127行、Loki194802行，窗口从run创建前两分钟开始，最早本地事件仍在Loki中，完整查询没有截断；真实Key与日英固定朗读样本在两端均未出现。记录 `artifacts/dev/model-real-key-logs-55bcfa841a76405dbcde2f2949e2389b.json`。先前一分钟查询出现未完成，十秒连续窗口读出原十万行边界；为覆盖长时间跨端运行，将记录上限调整到有限二十万行，独立128MiB/单窗口满页/完整时间边界仍拒绝不完整证据。五项护栏/脱敏定点检查通过。Loki保留的历史采集行与当前本地文件行数不同，日志数量不作为模型调用数，调用权威为PG attempt。

- 三条实际真实失败事件逐一按event/request/operation/job/run在Loki和Grafana代理查询中完全匹配，两项健康检查200，`formal-real-failure-log-chain.json` 通过；不保存供应商原始返回。最终发现部分Token指标中文标签缺失，已补总Token、音频输入/输出Token、输入图片数，Widget实际渲染审图通过；Android打包与临时Flutter测试共享生成配置冲突的失败保留，停止并行Flutter命令后单独构建成功（18.2秒）；最终APK SHA256 `bf46d86c3c3ed4ecf37f9c41349f8868b71b85e2cdc844a3ec53886dc7dc3f94`，Web重新构建成功。仅四个静态标签变动，不重跑未受影响的供应商/跨端流程。

## 4. Review、提交与剩余边界

独立非作者 GPT-6.1 Sol Agent `/root/independent_review` 在两端实现、联调与日志核对完成后执行第1轮集中 review，结论为 changes-requested，当时未提交本阶段 commit。安全记录 `artifacts/model-settings-ui/independent-review-round1.json`：6项确定缺陷，53条断言中51条为有范围限制的组合证据支持，2条因取消恢复缺陷保留未通过；schema消费者尚未批准，不更新受审指纹。完成后记录 reviewer、缺陷与建议、集中修复及必要第二轮定点复核、实际 commit 哈希与未验证边界。不得以本切片局部通过宣称阶段1或全部 AI/TTS 已验收。


第1轮集中修复清单（已完成定点验证，尚待第2轮独立复核）：

- R1-01：`cancel_requested` 遇Worker中断/租约过期未参与恢复，可能永久占用并发槽；修复扫描与取消封存，保留未知attempt，不重发供应商调用。
- R1-02：管理目录PATCH响应是完整能力目录，前端错误解码为单个模型；需正确接收已提交结果。
- R1-03：管理retry请求含后端禁止的 `confirm_new_attempt` 字段导致422；仅保留该接口支持字段，管理恢复仍不产生新供应商attempt。
- R1-04：按run读取历史结果错误继承默认30天用量窗口，造成模拟标识与用量丢失；该run结果完整读取，普通统计时间范围保持。
- R1-05：混合用量未显示未知attempt次数，且未消费/显示进行中次数；分别说明已知、未知和进行中，不将部分合计冒充完整。
- R1-06：凭据列表的旧撤销记录可挤出有效Key；保留本人隔离、有效Key上限与历史结果读取，明确列表历史边界。


后端集中修复已完成，`review-fixes-backend.json` 与原生JUnit保留红绿证据：修复前2项失败，修复后5项通过（45.34秒），追加撤销后历史保留检查1项通过（13.99秒），五文件Ruff/Pyright通过。过期 `cancel_requested` 经实际Kafka Worker扫描推进fence、封存cancelled与unknown attempt，释放槽后新任务202，旧provider迟到不复活；run专属用量没有隐式30天截断，普通聚合仍保留时间筛选。凭据列表明确active优先，随后返回近期revoked，总计最多100项；有效凭据硬上限10，因此均在返回范围，不声称这是完整撤销历史列表，不删除历史数据。真实管理API目录回应和expected_revision-only重试/严格拒额外字段/已知Stage恢复仍仅1 attempt均已验证。尚待前端对应回归及同一独立reviewer第2轮定点复核。

前端集中修复完成：目录PATCH正确消费完整 `ModelDirectory`，保存后直接更新当前投影；管理安全恢复只序列化 `expected_revision`，不产生新的模型测试意图；摘要消费进行中次数，混合指标分别展示已知及未知attempt数。后端单向生成8项新增管理动作/用量边界样本，Dart实际 `ApiClient`、认证和Widget消费者验证真实序列化及返回投影。13项状态、8项DTO/Widget和2项管理动作共23项必要用例完成：组合执行为21通过/2项fixture清理失败，修正fixture后只重跑管理2项并通过，不将原组合失败改记为成功；原日志保留。六文件analyze无问题，`review-fixes-frontend.json` 记录精确边界与源码摘要。

修复后的正式Web和Android顺序构建均成功，APK SHA256 `0bd7833e60580a31ca1e9706cda1814aae0ae3295bfe5b2d1dabf017654a1edd`。最新非editable wheel SHA256 `419df7a7f818bc36b3457fbc6db5561007a55c3087951219275122bf8a14a6c4` 在原独立虚拟环境安装，已安装源码匹配；API、Worker、Outbox三个入口从checkout模块之外完成正式隔离资源启动/关闭，`package-smoke-review-fixed.json` 全部通过，没有提交模型任务。

正式Web管理目录定点操作中，取消为0PATCH/0额外目录GET，停用和恢复各200，完整投影正确回填、CAS版本推进，原enabled值恢复；该脚本随后在用量定位处失败，`review-fixes-catalog-ui.json` 只保留实际通过的目录步骤，不宣称整体通过。修正滚动定位后仅补只读用量流程，1项通过（5.2秒），没有重复目录PATCH；`review-fixes-usage-ui.json` 与两视口PNG经前端和主Agent亲看，进行中0、真实未知用量1次与模拟已知用量分开可见。此前失败定位均保留，没有改Flutter实现来适应测试。客户端关闭并正常停止隔离服务后，`formal-after-review-fixed-read.json` 再次核实真实3/模拟4，不增加供应商调用。真实Key全窗口脱敏证明的截止时间保持原证据，不将后续只读日志冒充已纳入该证明。

最终冻结源码的六份契约导出逐字节一致；300个正式源码inventory-only检查通过，不执行覆盖率；23份本次相关Markdown的本地链接、锚点、围栏均无错误。`final-frozen-source-checks.json` 保存实际命令与证据摘要，排除用户所有的09-29记录改动。第二轮独立复核输入 `acceptance-review-round2-input.json` 绑定32份执行记录及53项断言，仍为待review声明，不是通过记录。


### 最终独立复核与收口

2026-09-30 23:49:10（Asia/Tokyo），同一位独立非作者 GPT-6.1 Sol Agent 完成第2轮定点复核。`independent-review-round2.json` 为 approved-scoped-review，R1-01～06全部关闭，无开放缺陷；12个host/Web/Android变体的53条断言全部有范围限制地支持，每条绑定真实执行记录的路径、SHA与判断。前端/后端作者分别实现、集中修复，独立reviewer未参与业务编写，不机械开启第3轮。最新Android仅重复构建，窄范围共享修复采用此前Android实操及相应Widget/传输回归，不宣称新包再次完整Android实操。

独立批准205个schema的canonical SHA `5cdf3f985c0306672ff1661f655887eede8ec02a616ca3971ad930ebcfe3b15d`，随后更新受审指纹和两个新增Dart消费者登记。全量受管生成write/check均成功，schema变化拒绝护栏1项通过；三份共享兼容导出逐字节一致，300个生产源码hash与实际最终Web/APK构建候选一致，没有因生成修改已测试实现。`generation-final-check.json` 保存结果。

根据独立逐项判断形成12份组合procedure执行证据及host/Web/Android各collection/result共6份门禁输入；每条断言保持源证据hash及review时间。`scripts.dev check --stage B2c` 返回0，报告 `artifacts/dev/check-6cac04118a754ebe8b7cc772024d4d17.json`，对应矩阵failures为0。门禁核对已执行证据，不重跑所有测试，也不把原生失败报告改为passed；procedure通过仅适用本期断言及其明确边界，不代替用户验收、供应商成功协议或阶段1大节点矩阵。

候选父提交 `bab58ff9f92a2e3c9c75d437f9002c342c68e17d` 只作为当时dirty候选的基点，不冒充包含本次实现。公开候选build为 `web-c7cb5bcad5ccb698-android-0bd7833e60580a31`，`candidate-build-provenance.json` 另绑定全部300生产源码。必要检查、review和文档收口后创建本地实现commit，实际hash以Git历史和完成报告为准；不默认push，用户所有的09-29文档两行改动不纳入本阶段提交。

剩余边界：三次真实供应商调用全部失败，没有真实文本/视觉/TTS成功协议证据；Gemini未调用，业务OCR/查询/TTS/离线消费者不属本期；Windows原生UI未实测；阶段1仍未完成。已授权三次额度用尽，没有新增调用或自动重试。本地开发使用HTTP，正式生产HTTPS/Cookie策略保持。正式与mock临时预览均已停止，本期开发容器和隔离数据保留供后续只读验收。
