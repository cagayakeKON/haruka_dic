# 阶段1：B0-foundation 工程基础切片

2026-09-22，用户要求开始按文档创建前后端脚手架。本切片属于路线图阶段1、B0里程碑内部的工程基础工作；完整B0验收范围保持不变，B1/B2仍未实现。起始工程基线为3a5f05a，工作期间另一任务独立提交的OCR文档fa5fbb3已保留，不纳入本切片实现归属。

## 范围与分工

根Agent负责后端包、公共HTTP契约、制品验证、生成manifest与文档；frontend_scaffold负责frontend；dev_tooling负责scripts、工具清单/Node锁和根格式配置。先约定只实现应用壳、无业务数据/登录/任务接口，统一公开环境身份与健康契约，再并行施工。review_foundation执行非作者review。

- 后端：Python3.13.6、Hatchling可安装包、API/Worker/Outbox/manage四个console scripts、显式配置文件/环境优先级、API lifespan、统一错误/分页/成功模型、健康路由、JSON日志白名单及离线OpenAPI/错误/遥测导出。
- 前端：单Flutter工程的Windows/Web/Android宿主、环境身份、公开配置拒绝、中文本地化、紧凑/宽屏壳、键盘/焦点、UI Test ID与生成器；管理路由仅由Web构建注册。
- 工具：固定SDK/依赖锁、doctor/bootstrap/check/codegen入口、Markdown与Python/Dart检查、测试报告非空/失败/跳过拒绝、自身坏样本。完整dev编排明确未实现。

当前只有`GET /health/live`和`GET /health/ready`正式HTTP路由。live表示壳生命周期已开始，ready返回503；`/api/v1/*`没有业务实现，统一返回404。配置只允许隔离dev/test回环来源，staging/production拒绝启动。Worker/Outbox实际执行及manage的db/seed/admin均非零退出；不会生成任务、迁移数据库或创建公开管理员。

## 检查选择与证据

本切片新增配置拒绝、生命周期、HTTP与工具/构建边界，选择后端unit/contract、Flutter壳widget/相关平台冒烟、生成和制品检查；没有执行未来业务矩阵、全仓覆盖率门禁、数据库/模型测试。局部测试数量不代表全仓覆盖率。

后端最终unit/contract共29项通过，Ruff格式/规则与Pyright strict零错误；统一runner报告为`check-48f0a5f039d448c2b485cf8350498eec.json`。包含预检关联及两端默认origin检查。另实际启动API到本机8128端口，HTTP live=200、ready=503、5173来源CORS正确；Ctrl+C后记录process.stopped并退出，不据此宣称未来连接池已关闭。

制品检查已在仓库外系统临时目录的新虚拟环境，仅安装锁定运行依赖与非editable wheel，使用隔离工作目录和Python导入模式核对app来自site-packages。四个入口help/config、API实际lifespan开始/关闭、未实现动作拒绝均验证。干净缓存构建wheel/sdist成功，错误构建哈希负样本确实拒绝；运行依赖安装显式禁止回退源码构建。最终报告为`artifacts/package-check/b4f2abb2f93149cdb19a74e6f7d73424/report.json`。完整真实连接池、迁移/种子生命周期不在这些证据中。

| 前端局部范围 | 实际结果 |
| --- | --- |
| 统一frontend检查 | 14项unit/widget通过，analyze零诊断、Dart格式与生成漂移检查通过；`check-bc275ce82cc64f13a5cbd128a5f5aa96.json` |
| Windows | debug构建、真实宿主壳集成2/2通过；VS17.9.34616.47、Windows SDK10.0.19041.0 |
| Android | dev debug构建、API34模拟器安装与壳集成2/2通过；明确传入flavor和10.0.2.2地址 |
| Web | release构建通过；Chrome/ChromeDriver153.0.8010.50，web-server/headless驱动壳集成2/2通过 |
| 生成器 | UI标识/公开配置/本地化/Windows身份重建一致；5个非法/重复/漂移坏样本通过 |

Android测试结束时Flutter SDK按namespace误尝试卸载无flavor包，已显式卸载本次dev包并确认无残留；测试用例结果与SDK清理限制分开记账。初次`-d chrome`的drive调试连接挂起被中断，不算通过；随后使用SDK支持的`-d web-server --browser-name=chrome --headless`取得真实通过结果。命令和限制已写入前端README。

开发工具Ruff/严格Pyright与14项坏样本通过，报告`check-32122b40fdfd40ba9e83e4c35b23537d.json`。根codegen最终check通过，报告`codegen-e97dbffeeab84295b5c0179f00ddd89f.json`；Markdownlint及链接/锚点/围栏/路径检查通过，报告`check-586e336176224103b22a2908536ea7c0.json`。额外修复三个既有文档的5条多余空行，不改变账号或出处规则。报告存入忽略的artifacts，不含真实用户凭据或材料；外部网页链接未计作本地文档检查通过。

集成收尾发现frontend/tool生成器源码的Python检查尚未接入，已补齐类型与JSON边界、独立strict配置，并将Ruff/Pyright及5个生成器坏样本接入frontend范围。主Agent对非本人编写的该定点类型修订复核；静态检查、5项回归和生成不漂移均通过，未重跑无影响的三平台测试。开发入口接线后的14项工具测试再次通过，报告`check-f49ba683b9da487ab457b1b0eab90ba9.json`。

工具版本由tools/toolchain.json固定，依赖由各lock固定。后端AnyIO约束为4.12.1以匹配Starlette1.6.0仍使用的BlockingPortal接口，HTTP测试使用该Starlette要求的httpx2。新版本uv置于仓库.tools，不替换全局SDK。未调用付费供应商，未修改MyHome、生产服务或用户业务资料。

## 独立review

第1轮发现三个P2：Web默认origin与后端CORS模板不一致；CORS预检绕过请求ID/完成日志；开发报告在JSON序列化后脱敏可能破坏JSON并漏掉Windows路径。已集中修订为一致的5173 origin、外层请求关联/中层CORS/内层错误边界、先递归清洗报告再序列化，并增加定点回归。第2轮核对三项修订及前端终版后关闭缺陷；新增制品脚本的源码构建回退问题补入`--no-build`并在本轮关闭，没有机械开启第3轮。

实际runner还发现Windows CP932控制台无法打印中文，已在入口设置UTF-8并加入真实TextIOWrapper坏样本，修复后精确命令可执行；本机Python3.9也改为早期可读拒绝。所有已发现缺陷以修复和相关验证关闭，不以review轮数豁免。

## 完整B0仍待完成

- PG/Redis/schema真实组装、受控同连接迁移锁、Alembic/表规范、种子与首管理员入口及故障竞争验收。
- Worker/Outbox真实资源生命周期、core/jobs进程编排与安全停止、隔离Compose和容器摘要；Docker服务本次未运行，不连接MyHome或生产。
- Dart API生成器完整兼容样本、权限/事件/数据库目录、固定素材/场景校验、业务与多语言参数消费者；当前机器契约只导出实际公共边界。
- 完整必需用例执行键/分片与覆盖分母/核心组门禁、CI托管及Linux shell实际证据。当前核心代码为配置、bootstrap和API边界，后续门禁必须登记这些文件，不能用空清单验收。
- 三端完整SCF-B0-06及外部语义驱动、正式安装身份/升级签名、持久缓存/平台插件原型；应用壳的局部运行不替代这些门禁。

本切片不改变原有P0、不连接真实供应商、不部署或push。小阶段本地提交包含工程、必要测试和本记录；实际哈希以Git记录及交付回复为准，避免将自身commit哈希写入同一commit形成循环。
