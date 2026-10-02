# 阶段1收口与材料导入就绪记录

状态：阶段1已完成，当前进入M1实现。范围为截至本人凭据与模型任务已交付的工程、账号、收藏基础、资料设置、身份治理、模型任务及公共缓存；材料、业务OCR/查询/TTS/NLP/离线消费仍未实现。依据[路线图](../roadmap.md)、[交付验收](../acceptance.md)、[测试规范](../../engineering/testing/strategy.md)与根代理规范。

## 用户验收决定

2026-10-01 用户明确要求先收口阶段1，再进入M1材料导入，并确认模型无需继续验证、现有 `KEY_REJECTED` 是正确结果。因此[B2c当期交付](2026-09-30-model-credentials-tasks.md)按此范围验收通过，保留三次真实认证拒绝及null用量的原始证据，不补发供应商请求，不宣称已验证模型成功或业务质量。既有B1用户接受的未实测边界也保留为接受例外，不改写成passed。

## 执行前范围

| 责任 | 当前完整必需集合 | 证据与边界 |
| --- | --- | --- |
| 后端Agent | 所有unit/contract/integration现有节点；账号/收藏、资料头像设置、治理/RBAC、凭据/任务/用量；真实迁移、事务、Kafka/Redis/对象存储及日志安全 | 先全收集；完整JUnit、Python语句与分支coverage；失败及未完成单独保留，无真实供应商外呼 |
| 前端Agent | 全部Flutter测试/组件/DTO、公共缓存和账号切换；Web、Android当期真实账号/资料/治理/任务操作、构建 | Flutter操作串行；用例/coverage原始结果；模型只读已有失败结果；不执行Windows原生UI、不重复Android找回密码 |
| 主Agent | 已实现工具/开发runner/门禁坏样本、契约生成、完整业务族映射、覆盖分母和阈值、源码/制品身份、文档与资源协调 | 不把检查器成功当成业务覆盖；不访问MyHome业务数据/生产；排除既有09-29用户文档两行修改 |
| 独立Agent | 阶段1完整前后端、契约联调、权限隔离、迁移/任务、日志、测试及文档全盘review | 矩阵预审只指出缺口；正式审查在检查和集中修复完成后执行，不是B2c机械第3轮 |

Python整体80%、核心90%；Flutter整体75%、核心85%，均保持现行门槛。四个必需coverage分片为backend-unit-contract、backend-integration、flutter-unit-widget、flutter-web-widget，完整未命中源码不能省略。原required_cases只有B0/B1/B2c，必须补阶段1聚合及B2a/B2b当期PROFILE/SET/FCACHE/ADM/PERM、DB/DAT/API/UIE/TDS/FLT/DESIGN/log分支；未交付后续分支不混入当期通过。

当期补充已登记于 `foundation-stage-close`：125个procedure，310个分项断言；原56个B0/B1/B2c变体完整保留，新声明没有产生passed。声明及各条权威出处/适用范围在 `tools/ci/foundation-business-procedures.json`，用户接受的未实测边界在独立 `acceptance-boundaries.json`。执行前预审已纠正Android误含Web定位、SET原生/主密钥分支和Android前端日志范围，历史SCF变体须逐个核对变更影响，不能用SCF第01项代表完整旧矩阵。后续按每项真实证据与独立判断生成门禁输入。

## 当前预审与失败记录

独立矩阵预审 `artifacts/stage1/independent-matrix-audit.json` 指出缺少阶段1聚合及B2a/b映射，两个收藏账号/撤权控制源误列普通coverage组，远端CI仅运行检查器不能冒充完整业务覆盖。现行测试规范的旧“未来清单”措辞随本次事实更新。

首次全量检查保留原失败：前端旧通知前后台读取断言与现行稳定UI协议冲突，另有弹层/资料/列表失败待逐项定位；后端旧schema/table/routes数量假设与当前契约不一致，静态检查还发现类型和格式问题。先区分测试过期和真实产品缺陷，再集中修复，不通过删除节点、下降阈值或批量豁免凑通过。

历史已应用Alembic源保持原字节及manifest摘要。历史文件的纯导入/格式问题只允许精确路径的窄静态兼容例外，语法/安全和完整manifest hash验证仍执行，新迁移不得继承这些例外；不是为了formatter绿色重写已应用历史。

本机Docker daemon在准备新隔离实例时不可用；首次prepare及中断的integration运行记为基础设施未完成，待健康恢复后执行原完整集合，不将中断或缺依赖记为passed。

Docker恢复保留运行时IPC目录备份，没有重置配置或数据卷；原Haruka Compose经本地归属校验后启动，smoke验证PG、Redis、Kafka、MinIO、Grafana及日志链路通过。新的fake隔离实例 `a8898186cad54665b6ce9e2212307b06` 使用HTTP，正式业务验证不复用此前真实失败历史或本人Key。

工具首次完整原生检查为153 passed、2 failed、1 skipped，另112子断言通过；原报告保留在 `artifacts/stage1/root-tools/first.junit.xml`。两项失败分别为Windows venv supervisor额外进程误计为业务残留，以及Web构建测试fixture缺少现行public_base_url。修复使用直接标准库解释器作为Windows supervisor、一致校验可执行文件后才开启目标进程的stdin gate，目标仍使用原venv；没有泛排Python/helper进程。关停/残留强制清理/无关进程保护及Web构建定点29项通过。缺显式PG维护目标的原skip随后以隔离维护配置真实执行，schema归属标记与重复清理用例1项通过。失败和skip原报告不重写。

`tools.ci.quality` 的foundation-quality和pytest-adapter两个检查器原生运行通过，完整源码inventory已检查；这证明门禁坏样本和登记规则，不代表业务矩阵通过或覆盖百分比达标。前端有限全收集已得713条testDone（660 success、53 error，含超时后连锁错误），原始JSONL保留；正在修正fakeAsync中的真实SQLite准备/清理，浏览器专属测试仍需在浏览器执行。当前锁定Flutter的Chrome路径不接coverage watcher，官方coverage转换器提供真实CDP/source-map路径，但报告完整分母和静默缺map行为仍须验证，不能复制VM报告充作Web分片。

完整契约再生检查发现动态条件日志事件，现已改成显式静态注册事件；另一轮doctor暴露机器JSON与诊断输出混合风险，runner现为机器输出调用单独返回stdout，仍按真实非零exit失败；26项runner回归及42子断言通过。随后完整 `scripts/dev.py codegen --check` 通过，报告 `artifacts/dev/codegen-136b25218c7b42c281b8392790c64225.json`；前两份失败报告保留，未手改生成输出。

集中修复后，原后端完整集合209项unit/contract与104项integration均通过，原失败报告保留；Ruff、192文件格式、Pyright与14个迁移资源摘要及单head检查通过。完整Python分母12596、核心11055均未缩减；首次有效合并整体74.66%、核心73.54%，未达80%/90%。后续仅补有意义的未覆盖权限、凭据、任务、通知及进程边界用例；补测尚未完成，不能签覆盖通过。

Flutter VM完整运行712条原生success、0 error，进程exit0及最终done success=true，证据在 `artifacts/stage1-frontend-20261001/flutter-unit-widget-final-results.json`。VM报告仍缺27个完整清单源码（包含Web专属及未执行入口），已报告源码的比例为整体81.76%、核心84.38%，只是局部事实，不能当完整覆盖门禁。Chrome原6文件集合首次DDC编译失败揭示控件fixture位于测试根外，现将唯一实现移入test/support并同步三个入口；原失败保留，完整6文件重跑中。Web分片缺失、完整分母及正式双端业务矩阵仍未签收。

后续生成输出按锁定流程重生并格式化，涉及源码行号后重新执行完整VM集合：715条原生success、0 error，exit0且done success=true，当前候选证据为 `flutter-unit-widget-frozen-results.json` 与对应LCOV，旧712报告保留为此前候选事实。Chrome六文件经Windows SDK路径兼容实验实际执行，11个可见测试及6个加载节点均成功；这只是浏览器行为证据。官方DDC转换与VM在128个共用文件的映射行集合不同，直接合并被门禁拒绝；DDC含类型/元数据映射，分母语义、源码编译身份及异步采集收尾正在独立核对，不能据此签Web coverage通过。

独立分母抽查确认额外DDC映射也包含真实getter、构造参数读取、字段初始化及return/throw，不能按字段、类或enum的外观删除。映射行的更多执行点须按真实浏览器运行及采集验证处理，不能以降低分母取得通过。后续两文件采集实验在第二套件加载时超过480秒，原超时、已成功的路由节点及未完成节点分别保留，SDK已恢复原始字节；探针尚未完成，不能据此签采集工具通过。

后端补充真实原生分片后，36份DATA保留来源并合并，整体11093/12596（88.07%）、核心9681/11055（87.57%）；整体已达门槛，核心尚未达到90%。分母保持不变，后续补测分别记录JUnit、DATA及生产源摘要；以mock仓储为边界的低层用例不宣称数据库隔离实测。

正式HTTP Web实操中，注册策略预览、保存、重载读取与恢复原策略已通过；账号完整流程注册、邮箱验证、登录、跳过可选资料、退出、Web找回及新密码登录已通过。过期菜单及按钮定位造成的原失败与中断保留，修正仅涉及测试定位和符合现行页面的期望；资料、设置、跨账号及Android矩阵仍待完成。没有追加真实模型调用。阶段1完整矩阵、覆盖门禁与独立全盘review仍未完成。

后端最终候选52份DATA按当前源摘要合并，整体11387/12606（90.33%）、核心9969/11065（90.09%），已达到80%/90%。后两次分母增加来自本轮修复数据库契约迁移版本来源及安装资源查找，未删除未命中点；两文件旧DATA派生副本只清除此两文件后以新69+4+19条真实定点运行替换，原始DATA与313条完整集合报告保留。19条迁移原生节点包含9个参数化函数，不能记为仅9条。最终Ruff、209文件格式、Pyright均通过，来源与合并摘要在 `artifacts/model-settings-ui/stage-close-backend-final-result.json`；这仍不等于310项业务断言签收。

数据库契约现在读取经manifest校验的单一迁移head，当前为 `0013_outbox_delivery_lease`；可安装wheel纳入14份原始迁移资源，历史源字节不变。仓库外clean build、runtime-only安装、五个正式入口及已安装契约导出通过，报告 `artifacts/package-check/d38371df53fa44c0acf1c2521d4dd01a/report.json`；另核对wheel各资源字节与仓库一致。此轮无数据库配置的安装检查不冒充PG运行检查，隔离PG证据由原迁移用例提供。

Chrome采集修复后的11文件完整原生运行为35个可见节点及11个加载节点成功、0失败、exit0、done成功，耗时303.59秒。SDK兼容改动已恢复原始SHA，源码编译前后相同。独立负例验证损坏VLQ与空项目映射均非零退出且不写LCOV，有效对照退出0；实际探针54行均为CRLF。真实VM/DDC映射行并集按分片各自命中、其余补零的归一化方案获工具定点认可，不删构造参数、初始化或getter等合法映射点。当前完整Flutter诊断仍只有24412/41335（59.06%）、核心6610/11408（57.94%），未达到75%/85%，尚不可签覆盖门禁。正在用既有业务断言补真实Chrome运行，不借用VM命中。

同一份后端canonical样本已通过受控导出产生仅供测试的同步Dart fixture，登记在 `tools/codegen/manifest.json`，唯一目标为 `frontend/test/support/generated/api_compatibility_samples.dart`，未加入生产assets。三份认证测试保留全部断言，仅替换文件读取；唯一SampleAdapter移入测试根并同步21份消费者。实际生成write和check均通过，报告分别为 `codegen-9d8aab4ddb3b4d9789cbd0db022a70e2.json`、`codegen-c8aae632da1442ec841d609540d54346.json`，新runner漂移与目标保护回归28条通过。安装同步期间受控停止并重启同一fake实例，账号与收藏数据保留，HTTP健康检查200；没有改成HTTPS或处理浏览器证书例外。

正式Web另完成资料保存/清空/重载、双视口草稿/焦点/缓存dialog连续性、从真实材料选句收藏、收藏详情dialog连续性以及A/B账号隔离六份原生报告。Android已实操缓存取消、资料软键盘草稿切回保留及真实保存重开，仍有头像、设置和治理矩阵缺口；证据清单 `artifacts/stage1-frontend-20261001/formal-ui-current-evidence.json` 标为partial。03:54:11–24 UTC收藏窗口及04:13:42 UTC观察时的隔离PG `ai_runs` 和 `external_call_attempts` 均为0，采用只读事务核对，不能仅凭单个测试接口请求计数泛化供应商用量结论。

2026-10-01后续收口仍未签收：Python两份必需gate分片按37份unit/contract与15份integration真实DATA分别派生，52份原始DATA不变，严格合并与当前最终候选逐文件分母/命中一致。Flutter原生报告另以原始JSON唯一成功done、失败数0、实际exit0及LCOV摘要生成派生绑定，原报告未覆写；当前严格四分片门禁结果为Python11387/12606、核心9969/11065通过，Flutter24452/41335（59.16%）、核心6650/11408（58.29%）未通过，见 `artifacts/stage1/coverage-gate-native-bound/result.json`。门槛、合法编译映射点和源码范围未减少。

浏览器认证补跑保留了原始失败：首次50成功5失败；有界真实/模拟帧推进后52成功3失败，剩余为本人撤销当前会话两种结果及设置退出；同一受影响VM组11成功、0失败、exit0。显式测试初始路由隔离后仍3失败，因此该假设未获证实。当前定位过程中Flutter tools入口在业务测试开始前阻塞，最小Chrome与版本入口超时均不能记成业务失败/通过；SDK原字节恢复及仅本次进程树清理有证据，生产路由和断言未为测试改写。

正式Web另完成私有头像上传/隔离、学习语言保存重载、外观保存重载和menu/dialog双视口连续性；Android完成资料CAS显式重试后保存重开、头像选择器取消、收藏详情返回、外观CAS重试后真实开关并恢复及语言CAS重试后精确读取。旧Android仅凭标签存在推断跨端新值的结论已撤回，错误报告保留，当前图中母语、解释语言和目标语言选中状态分别核对。具体原生结果与摘要见 `artifacts/stage1-frontend-20261001/formal-ui-current-evidence.json`，不能据这些样例泛化完整310断言。

当前正式Web登录的客户端、API、业务事件和ORM四来源，分别以同一operation/request及精确event_id在Loki、Grafana各匹配1条，原生退出0，见 `artifacts/stage1/exact-current-log-chain.json`。宽范围观测报告的Loki HTTP status0表示该查询未完整返回，保留限制；四来源精确证明不冒充全部日志级别或PG连接全链路。另真实PG合成错误由源头确认后，经受限采集匹配backend_pid/application_name/SQLSTATE并确认标记未泄漏，见 `artifacts/dev/postgres-engine-a8898186cad54665b6ce9e2212307b06-stage-close-current.json`，这是单独源头脱敏证明。当前Web业务日志实际有info/warn，debug/error release样本仍未在本轮签收。

本轮UI操作结束后，仅受控停止当前拥有的serve进程，原生退出0，同一实例账号、数据与构建保留；PG池正常关闭产生连接结束记录。此前活跃连接尚未产生同连接源记录的0匹配查询保留为失败；停止后的ORM backend_pid/application_name/database_name与PG源记录在Loki、Grafana各匹配1条，见 `artifacts/stage1/current-pg-connection-after-stop.json`。该证据与四来源精确关联可以联合证明这次实际登录的PG连接链，不扩展到全部动作、日志级别或模型。

文档检查最新为19份本轮归属文件本地链接/围栏/路径0问题，152份Markdown lint退出0；不据此声称应用通过。后端已补真实凭据重加密/用户轮换双连接锁等待的两种顺序，其他数据库计划及引用父行锁并发证据仍在补齐；独立全盘review和本地commit未完成。

随后确认Chrome认证的三个失败来自测试在真实异步业务完成前断言路由：最终等待分别绑定请求启动、状态与路由完成，生产认证/路由未改，原断言保留。最小本人撤销用例原生通过；后续17文件批次中的原三个认证失败也均成功，但后台模型操作两例及材料导航两例仍失败，整批唯一done为false，不能纳入覆盖门禁。对这四例集中修正业务完成等待后，两文件8个可见节点均成功、exit0、done成功；一次必要17文件采集仍在执行，旧失败报告保留。此前短超时的版本/启动诊断实际涉及Flutter tools编译，不能据此认定整个SDK损坏或业务失败。

后端新增数据库边界已完成：凭据双连接重加密/轮换两种顺序、引用创建与维护tombstone共同父行锁两种顺序、1200本人及18000其他账号历史数据上的真实凭据列表查询计划，以及46个当前发布动作的230次持久授权guard检查，共6个原生节点通过。guard矩阵不冒充每个HTTP接口状态证明。另1个真实PG/Redis测试覆盖12条HTTP绑定的成功、匿名401、当前动作撤权403；限额写入/删除还验证过期CAS409和近期认证401，本人学习档案验证A/B隔离。没有新增生产代码或供应商attempt。独立21份integration DATA与原37份unit/contract按当前117个后端源摘要及完整逐文件分母派生，见 `artifacts/stage1/backend-gate-shards-http-regressions/gate-shards.json`；旧15/20份分片和原始DATA未修改。78条HTTP路由目前均有明确状态绑定，这不等于所有业务变体或310项断言已签收。

最终17文件Chrome整批82个可见业务节点及17个加载节点均成功，exit0、唯一done成功且无失败/skip，原四项失败报告保留。受影响四文件VM定点17业务节点通过，五文件Dart analyze无问题，SDK兼容字节恢复原SHA。真实转换及严格绑定见 `artifacts/stage1/web-auth-contract-business-native-bindings/plan.json`；生产前端源码未改。与后端21份integration合并后的严格门禁为Python11434/12606（90.70%）、核心10016/11065（90.52%）通过；Flutter27313/41335（66.08%）、核心7632/11408（66.90%）仍未达到75%/85%，见 `artifacts/stage1/coverage-gate-auth-business/result.json`。后续仅补此前未覆盖的必要真实浏览器路径，不重跑已通过套件凑增量。

阶段1性能方法登记采用构建/设备/窗口/样本/百分位与原始来源记录，功能及发布节点再测量目标真机profile帧耗时、内存和容量。当前正式UI的03:01～05:01 UTC窗口有5个API模板65个服务端monotonic耗时样本，按nearest-rank给出p50/p95/max及错误次数，并绑定同一Web/APK摘要，见 `artifacts/stage1/current-api-baseline-observation.json`。这是本地API观测基线，不是Flutter帧率或用户感知延迟；Android目前只有实际AVD功能实操，目标物理设备profile测量和最终发布性能阈值未验证。

独立日志测试入口经Dart analyze和release Web构建通过，输出到独立目录并挂载同源子路径；183个生产Dart源码摘要及正式main.dart.js均不变。首次测试入口import lint和Windows相对shader输出路径失败均保留，集中调整import与绝对构建目录后通过。实际Playwright1节点通过，五个debug/info/warn/error与performance事件均获HTTP accepted，并分别在Loki、Grafana按精确event_id各匹配1条，见 `artifacts/stage1/telemetry-release-driver/result.json`。从服务端接收至全部精确查询完成的保守观测上界最大12.804589秒，这个样本观察到初始15秒目标，不是SLA、吞吐或7天容量保证。测试包调用未改动的生产Telemetry及真实匿名接收链路；正式主页面info/warn业务链有单独实操证据。此测试不冒充正式主入口debug/error自行产生，也不把受处理的FlutterError报告当作未捕获进程终止；1毫秒performance事件用于协议验证，不作性能基线。

正式Web另补可选性别、时区及AI可选人口资料同意开关：实际UI保存、服务端PATCH200、重载值与控件状态核对，再经同一UI恢复原值；一项原生Playwright场景退出0，24.5秒，无失败/skip，模型测试提交0。报告及源/制品摘要见 `artifacts/stage1/profile-preferences-ui/result.json`。这补齐上述具体资料动作，不据此泛化全部头像竞争或跨端条款。

正式Web手机视口另确认清理本人本机缓存，核对实际成功提示、清理后仍可访问本人资料、返回和重载保留原服务端资料；一项原生Playwright场景退出0，17.3秒。报告 `artifacts/stage1/cache-clear-ui/result.json` 保留此前移动端登录等待和提示定位失败，成功用例没有修改服务器资料或发起模型测试。此层证明实际UI清理动作及资料保留，持久缓存计数、代次和故障仍依赖对应低层证据，不声明尚未接入正式页的缓存配额控件通过。

独立历史适用性定点核对了B2b/B2c动作源和原记录：可复用的具体动作仍按原构建和原始结果边界记录，不将整轮失败改为成功，也不将不同APK身份合并为本轮新实测；报告 `artifacts/stage1/historical-business-applicability-review/historical-applicability.json`。正式收藏reference入口存在cursor追加路径，旧分页与首页刷新/作用域变更的精确交错变体正在补低层验证，不能全部划为未来范围。此定点判断尚非阶段1全盘review。

管理端实际本人停用操作另通过一项原生Web用例（16.0秒）：POST状态动作因本人管理限制返回403/PERMISSION_DENIED，界面显示无操作权限，重载后账号身份、active状态和revision不变，见 `artifacts/stage1/admin-protection-ui/result.json`。此前等待、定位及端点方法假设错误的五次失败均保留。此路径被 `_reject_self` 前置拒绝，不冒充最后管理员事务保护的409；既有PG正式服务用例提供串行最后管理员校验。

随后补充最后管理员并发保护：两个真实PG连接分别通过持久认证ScopeContext执行正式停用服务，第二事务由 `pg_blocking_pids` 确认等待共同授权锁；第一事务提交一次停用后，第二事务以STATE_CONFLICT回滚，最终保留一个可登录超级管理员，授权revision和审计只增加一次。原生pytest一项通过、JUnit无失败/错误/skip，见 `artifacts/stage1/admin-removal-concurrency/execution.json`。新增22份integration DATA与原37份unit/contract按当前117个生产源严格派生，原始输入及逐文件分母不变，见 `artifacts/stage1/backend-gate-shards-admin-concurrency/result.json`；独立复核仍待完成，不把服务事务测试称为Web并发实操。

Android另补带UTC动作时间标记的缓存dialog取消、真实软键盘输入及HOME/切回应用两条原生路径，均退出0。Loki查询按已加载基线到动作结束的精确occurred_at窗口核对，每个窗口只有一次 `/api/v1/me/access` 200，业务接口完成记录均为0，见 `artifacts/stage1/android-cache-lifecycle-fresh/api-window-proof.json`。旧轮转本地日志缺少部分历史窗口，不能将其空结果当作没有请求；上述65个API耗时样本也仅为本地日志中实际观察到的部分样本，不是03:01～05:01全部请求的完整普查。

新增两个分页交错及两个原生平台管理受众低层用例，四个VM节点均退出0且最终done成功；原生平台逻辑不冒充Windows或Android管理端UI运行。26文件Chrome补采集在已成功部分节点之后发生CDP收尾超时，缺最终done和成功退出，不纳入覆盖。工具已集中修正重复序列化累计大文件的问题，并通过两项低层生命周期回归；28文件原矩阵（含四个新增节点）改为四个七文件批次采集。首批仍在排查CDP快照阻塞，阶段1完整门禁、全盘review和本地提交尚未完成。

独立全盘审查第一轮确认凭据正常业务日志缺陷：创建、轮换和删除仅保存PG审计，没有发射约定事件。集中修复后，三个literal日志均在服务事务退出后记录，仅携带统一关联上下文；9项低层用例和1项真实HTTP/PG用例通过，验证service/commit失败不发成功事件，原测试准备及关联头失败报告保留。受控停止原serve（退出0）后同实例、账号、数据、Web/APK原件重启加载当前路由，仅经真实native登录执行模拟凭据创建/轮换/删除和退出；HTTP201/200/200及退出204，前后只读PG的AiRun/attempt均为0。三个精确事件在本地、Loki、Grafana按event/operation/request各匹配1条，见 `artifacts/stage1/credential-commit-log-runtime/exact-log-proof.json`。独立第2轮定点关闭CROSS-LOG-01，见 `artifacts/stage1/cross-review-backend-tools-round2.json`；这不是模型或UI成功证明。

PROFILE-001另补两个真实账号不填写显示名的注册/验证/登录、相同显示名保存/重读，以及A清空后B完整资料保持不变；真实PG归属及零供应商attempt核对通过，原生pytest1项退出0，见 `artifacts/stage1/profile-display-name-isolation/execution.json`。两次测试准备/查询错误报告保留，独立非作者已定点核对新源与成功节点。

采集工具集中修复后，最小SQLite Chrome套件20个可见节点及首批七文件105个可见节点均完整成功、无失败/skip，采集与转换均退出0；SDK恢复及本工具Wasm清理有记录。新的真实分片绑定保留原四份报告，并按各自命中合并，见 `artifacts/stage1/wasm-batch1-native-bindings/plan.json`。当前严格门禁为Python11221/12612通过、后端核心9803/11071（88.55%）未达90%；Flutter28577/41364（69.09%）、核心8826/11408（77.37%）未达75%/85%，见 `artifacts/stage1/coverage-gate-credential-logs-wasm-one/result.json`。后端日志修复使路由源码变化，旧路由命中已从派生副本清除，新增当前源回归后还须补直接受影响的既有路由用例，不能平移旧行命中；前端其余三个原定批次仍待完成。源码、合法映射点和门槛没有为通过而缩减。

## 2026-10-02 继续收口

当前工作区以 `3998c05` 为基础继续阶段1收口，前后端并行，完成的任务由非作者子Agent定点review；不追加真实供应商调用。阶段1仍未签收，M1业务尚未开始。

- 统一开发入口已支持 `check --stage foundation-stage-close --identity <候选身份> --report <报告>`，转交既有必需用例检查器；缺输入、缺矩阵及失败结果仍拒绝。实际29项测试及49个subtest通过，Ruff/check-format通过，独立任务review通过后本地提交 `4643460`。后续严格Pyright发现既有测试fixture字典类型推断问题，已补准确类型；该路径1项定点测试及Pyright通过，非作者定点复核通过。入口通过不代表阶段1业务矩阵通过。
- 新检出发现 `0010`～`0013` 已应用迁移的原CRLF字节被Git转换为LF，与既有manifest不一致。保持manifest及已应用字节，四条精确Git属性使用 `whitespace=cr-at-eol -text`，不扩大到新迁移；真实Git导出正负例、原PG迁移节点和wheel资源分别验证。当前28项单测、19项PG测试及wheel内14份资源逐字节核对通过；首次基础设施未运行的连接失败报告保留，最终属性对应定点复核仍在完成。
- 后端历史覆盖复用先按117个应用源、测试/资源源及原生节点集合核对，保留原报告身份。独立review发现派生integration报告遗漏8个零命中CLI源文件，已要求补完整文件集合并双向核对分母/命中；原始DATA不改，不为修报告重跑已通过业务。修订派生及完整覆盖门禁尚未签收。
- 通知前后台读取次数的Chrome定点1项通过；原第三批7文件重新采集为60个可见业务节点全部通过、唯一done成功、原生退出0，SDK及采集资产恢复。该批真实转换后的Flutter整体为32814/41962（78.20%）、核心8855/11408（77.62%），核心仍低于85%，不签覆盖通过。其余既定批次和必要核心路径继续执行。
- B1已接受的Android屏外列表/重启读回及Web读取Android所建同一收藏ID明确补入 `acceptance-boundaries.json`，仍为accepted-unexecuted，非作者已核对权威原文；不补测，不写成passed。

本轮原生报告及review保存在当前工作区忽略目录 `artifacts/foundation-closure-root/`、`artifacts/foundation-closure-backend/`、`artifacts/foundation-closure-frontend/` 与 `artifacts/foundation-closure-review/`。具体报告保留源码、依赖及制品摘要；旧检出的原始证据仍保留，不把本段摘要作为310项断言签收。

## M1当前任务

M1业务进入实现。M1范围为三步导入、不可变final文件/版本、类型分派、材料列表/搜索/筛选/详情/确认删除、有权任务进度和持久站内消息；三类专用阅读/结构解析留M2～M4。小说/课本沿已确认MD/EPUB基础范围，PDF、TXT和OCR仍属后续。2026-10-01用户明确选择试卷加入文本PDF、扫描PDF和图片，OPEN-01产品选择已关闭，M1纳入这些源文件的上传/验证/不可变发布及类型分派；OCR、题目校对与冻结按M4举证，不将上传成功冒充可读或ready。前后端继续由不同GPT-6.1 Sol Agent实现，共享契约先冻结；前端编码前须亲自操作已确认Flutter mock对应两端画面，完成后正式Web/Android实操及独立review；测试使用模拟供应商，不追加真实模型验证。
