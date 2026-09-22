# B0 可重复工程基础验收

日期：2026-09-22。阶段1的 B0 小阶段已验收通过；候选应用来源为 `f3b33c4accf978e87806558cfa1c46641ccc8745`。Windows/Linux干净检出、三端壳与完整必需矩阵均有实际结果及独立签收，B0范围内没有未关闭缺口。B1/B2未实现，阶段1大节点未完成。

## 实际交付范围

- Flutter Windows/Web/Android 应用壳、环境身份与基础布局/控件；集中 Dio/DTO、错误/精确标量与真实健康接口交互。
- 可安装 Python 包与四个正式入口；PG、Redis、Kafka、MinIO 客户端按实例组装、校验和关闭。core 仅需 PG/Redis，jobs 增加 Kafka/MinIO 与无业务 handler 的 Worker/Outbox 生命周期。
- 12张基础表、UTC公共时间字段、无物理外键的模型/字典；同一物理连接持锁迁移、受控种子v2、原子首管理员初始化、schema检查。没有创建公开默认管理员。
- `dev/` 下独立本地 Compose 与日志采集；锁定工具/构建依赖，doctor/bootstrap/codegen/check/dev 职责明确，进程清理限定为本次所有者。
- 单向契约/定位标识生成、目录拒绝检查、真实结果收集、源码清单及CI参考配置；Windows 安装身份原型验证 dev/prod 共存、升级和卸载隔离。

## 验收证据

最终必需集合由 [required_cases](../../../scripts/quality/required_cases.json) 单一维护：33个自动质量节点与11个按平台拆分的 procedure；procedure 内再逐一核对所有声明断言和底层实际结果。它不是应用全部测试数量，也不代表阶段1全部功能或全仓覆盖率门禁通过。

| 范围 | 实际结果与来源 |
| --- | --- |
| Windows干净检出 | [clean02记录](2026-09-22-b0-windows-clean.md)：32条命令通过，10类准确失败诊断，两轮bootstrap/生成、editable、core/jobs正常关闭；额外单次隔离构建补录真实六项PEP517闭包，产物摘要与clean02一致。首次工具配置错误及原日志过滤缺口保留 |
| Linux干净检出 | `artifacts/linux/clean-20260922-04/`通过；34开发工具、36生命周期节点，9类准确失败诊断，重复bootstrap/生成，wheel/sdist/editable与仓库外四入口；core/jobs各两轮及三入口SIGTERM全部通过 |
| 数据库与初始化 | 复用[迁移](2026-09-22-b0-migrations.md)和[身份](2026-09-22-b0-identity.md)的真实PG争锁/断连/恢复、种子保留人工授权与首管理员事务证据；对应源码至候选版本无差异 |
| 生成与契约 | [登记检查与补录](2026-09-22-b0-generation.md)：6登记节点、7生成器节点、9 Dart API与4配置/布局节点；真实未知UI、错误revision拒绝及两次生成一致性 |
| 平台 | Windows/Android各3个实际原生节点，Web3个外部语义控件节点、1个真实API健康交互和1个正式管理路由节点通过；管理路由只在Web注册 |
| Windows安装身份 | [独立原型](2026-09-22-b0-windows-installer.md)：3个MSI、5次真实安装/升级/卸载操作及独立凭据service验证。载荷为无网络探针，不是正式Flutter发布安装包 |
| 质量 | `artifacts/b0-final-20260922/`统一候选identity下32+1节点通过，源码清单65项、静态资产2份通过；历史质量报告保持原身份 |

[独立证据核查](2026-09-22-b0-evidence.md)记录逐断言来源、原始报告、历史适用性和review。原始报告未记录commit的地方不补造身份；已核验相关迁移/初始化、前端、后端包源码相对其实现提交无差异，保留既有有效证据。旧失败与被拒绝生成器原型不覆盖、不改成通过。

## 完整矩阵与版本绑定

作者root编制11份证据索引，非作者infrastructure_tooling逐断言核验后于 `2026-09-22T07:01:46.712276+00:00` 全部签收。签收文件绑定每份索引SHA256；索引本身保留签收前作者状态，最终结论由独立signoff及22份collection/result receipt表达，不改写历史文件。

实际执行 `scripts/dev.py check --stage B0`，显式输入同候选identity与26份报告：4份自动收集/结果、22份procedure收集/结果。输出 `artifacts/dev/check-5285787c409342699a8798fe232f37c1-matrix.json`：`passed=true`、`failures=0`、44个必需节点的88项collection/result检查均通过，`report_failures=[]`。矩阵SHA256为 `70e790ee96e82eb553e6c5f438458793335e4d96bb05e20b4b4f97578fb005a5`。

[证据摘要清单](2026-09-22-b0-evidence-manifest.json)纳管候选identity、11索引、26报告、源适用性、素材/源码清单及最终gate摘要；底层运行报告保存在本机ignored artifacts。入口汇总只消费已经运行和审过的证据，不重复测试，不自动宣称任意后续HEAD通过。

候选后的 `4b60666` 仅新增正式Web管理路由测试及记录，该真实节点已纳入本次矩阵；`a605c70` 仅增加统一B0汇总入口及对应3项回归，另有2项相邻用例、Ruff/strict Pyright与非作者review通过。它们没有修改被测应用、原必需矩阵或检查器判定；最终提交只归档证据和同步文档。后续代码变化须按影响补充验证。

## 范围边界

B1登录/收藏/实际RBAC授权流程与B2持久任务/Outbox投递/Worker业务/Agent执行尚未实现。正式签名安装包、Android真机与后续插件性能、生产部署/容量、远端CI执行及阶段1大节点全量门禁不属于本次完成声明。Dart DTO按已审过渡方案限B0/B1，B2前锁定长期生成方案。

本机Haruka开发Compose继续运行；core/jobs测试应用均正常停止。Android专属模拟器已关闭、AVD保留，曾尝试卸载测试包但系统返回失败，因此不声称已卸载。Windows安装身份探针及其合成凭据已按原型记录清理。未操作其他项目或生产服务。

## 文档与提交收尾

最终状态同步涉及的23份Markdown已通过本地链接、围栏和路径检查；现有markdownlint-cli2配置实际扫描73份文档，零问题，默认globs之外的tools/ci/README另作定点检查通过。`git diff --check`通过。未因文档收尾重复应用测试，最终文档修订只补对应文件检查。非作者对最终gate、证据摘要和状态边界的核对记在独立证据记录。

只读 `infra status` 报告 `artifacts/dev/infra-38e6e14f38b14ef7a1a46c52589deda8.json` 确认Haruka本地8个服务均running，其中PG/Redis/Kafka/MinIO为healthy。最终本地commit归档本记录、证据摘要及相关状态文档，不push；提交身份以Git实际历史为准，不在文件中循环写入自身commit哈希。
