# B0 Windows 安装身份原型记录

日期：2026-09-22。范围：阶段 1 / B0 的安装身份独立验证；本记录不签收完整 B0，也不代表生产应用已发布。实现位于 [tools/packaging/windows](../../../tools/packaging/windows/README.md)，共享身份由 [build_targets.json](../../../frontend/config/build_targets.json) 提供。独立 review 由本阶段集成负责人统一归档，本文件记录作者运行证据。

## 实现与实际结果

使用官方 WiX 5.0.2（`5.0.2+aa65968c`）生成当前用户范围的三个 MSI。安装载荷为无网络公开身份 JSON 与测试脚本，没有 Flutter/后端/账号数据；production 名称只表示安装身份，未配置或访问生产服务。

2026-09-22 05:56:09 UTC 本机证明完成，运行 ID `6580f889be7f4b50b8afaeafbe6194db`：

| 验证 | 实际结果 |
| --- | --- |
| 预检 | 两产品目录、HKCU 身份键、关联 UpgradeCode / ProductCode 均不存在后才执行 |
| dev 0.1.0 与 production 0.1.0 | 同时安装成功，独立路径/身份，安装文件摘要与构建载荷一致 |
| Windows Credential Manager | 两个 service 各自写入、读取本轮合成 target；不读取用户凭据 |
| dev 升级 0.1.0 → 0.1.1 | 新 ProductCode 已安装，旧 ProductCode 消失；production 注册、文件和测试凭据仍匹配 |
| 卸载 dev 0.1.1 | dev 目录/身份键消失；production 仍安装且文件摘要匹配、测试凭据可读取 |
| 收尾 | 两个合成凭据已删除，production 已卸载，两环境目录/身份键/关联 MSI 均无残留 |

本轮 3 次安装和 2 次卸载均返回 0，另外校验了安装状态、文件摘要、注册表版本与实际凭据读取结果。未提升权限、安装证书、终止应用或卸载现有用户程序。

本地证据目录：`artifacts/windows-installer/proof-20260922-02/`。`proof.json` 的 `passed=true`、`failure=null`、`cleanup_failures=[]`。证据不纳入 Git，以下摘要用于对应本轮真实产物：

| 产物 | SHA256 |
| --- | --- |
| manifest.json | `cdece195eeaca93edf427d5029f16e0b01f54a964a41f2a3b86adc9bd61ea340` |
| proof.json | `0d0656b2ef8a8d08c67a04e10e097fd0ebb2dfaca16b666cddcd1fe01db615d7` |
| dev 0.1.0 MSI | `f6de6314e1eb8d9a7ae8e1df20f3e0a5c6bd6c18b3f503ff82cd7ca998d4863a` |
| production 0.1.0 MSI | `84909cd2e187a7efaf09dfe7adf076ab5ff9041e6ddc20190b821e19e45c3f22` |
| dev 0.1.1 MSI | `7b25d4c63fa365f6e8808ca53e55d9d844ee0f50a2e83dddda0a14062ebc2ff7` |

原型 Ruff check / format、Pyright strict 均通过，6 个边界测试通过，3 个 PowerShell 脚本解析无语法错误。覆盖身份缺失/混用、目录穿越、稳定身份、非法 MSI 版本及禁止自启动/服务/CustomAction；不扩大为全仓或 Flutter 应用矩阵。

## 工具选择与边界

官方 Inno Setup 7.1.0 下载与签名校验已完成，但编译器安装命令被自动审批审查拒绝，仅返回 `blocked by policy`。该安装未重试，也未通过更换 shell、解包或换参数规避。随后采用官方支持的 `dotnet tool --tool-path`，仅在工作区还原 WiX 文件，不写工具安装注册表。

WiX 7.0.0 构建需要接受商业 OSMF EULA，本次没有接受条款或费用。最终原型固定为官方 MS-RL WiX 5.0.2；nupkg SHA256 为 `f30ef0c74e2a986126539c5780be93ac24e8136eaf723b1937b26272703ae173`，官方 NuGet 作者/仓库签名验证成功。构建使用本机已有 .NET SDK 8.0.200 与 .NET 6.0.36，无新增运行时安装。可复现来源及签名指纹见 [工具锁](../../../tools/packaging/windows/toolchain.json)。

本轮只验证稳定身份映射与本机安装行为。原型无签名，未进行真实 Flutter release 安装、真实应用凭据适配、升级中业务数据迁移或生产分发验收。5.0.2 的选用不代表当前生产工具链或安全支持承诺；正式版本与签名仍需单独确定。

## 独立 review 结论

2026-09-22，非作者 reviewer `infrastructure_tooling` 完成第1轮集中复核，范围为本目录的固定三包构建、工具还原、凭据探针、安装证明与相关边界测试。未发现须修缺陷，无需第2轮；不扩展为真实应用安装或生产工具选型审查。

- 身份与已有安装保护：核对共享清单的两组身份、确定性 GUID、单层产品目录约束，以及安装前的目录/HKCU/关联产品检查。卸载只遍历本轮尝试的 ProductCode，执行前还要求已安装载荷摘要和注册版本匹配；没有通用目录删除或按名称卸载其他应用的操作。
- 凭据与报告：探针使用随机 run ID 的合成 target，已有 target 拒绝覆盖，删除前核对本轮合成内容；包和 MSI 日志不包含用户凭据。报告在凭据删除、剩余产品卸载及残留检查后生成，清理异常阻止 `passed=true`。
- 实际产物：只读打开本轮三个 MSI，核对摘要、对应环境的 Upgrade 表，确认没有 CustomAction、ServiceInstall 或 Shortcut 表。manifest 摘要与 proof 引用一致，源清单摘要与当前文件一致；实际 proof 记录五次 MSI 操作、通过状态及零清理失败。

本次复核没有执行安装、卸载、凭据操作或工具还原，也没有重复作者已通过的6项单元及静态检查。保留既有真实运行证据和文档所述局限，不能据此宣称正式签发、真实 Flutter 安装或完整 B0 已通过。
