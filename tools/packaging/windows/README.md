# Windows 安装身份原型

本目录实现阶段 1 / B0 的 Windows 安装身份验证：无签名、当前用户范围 MSI、两个环境共存、开发环境升级、独立卸载和凭据 service 隔离。载荷只有公开身份 JSON 与无网络 PowerShell 探针，不包含 Flutter 程序、后端地址、账号或用户数据；不能用作生产应用安装包。完整 B0、生产签名/分发及真实 Flutter 凭据适配器仍按各自验收推进。

## 身份与维护

身份唯一来源为 [build_targets.json](../../../frontend/config/build_targets.json)。入口要求所有字段存在，拒绝未知环境、路径穿越、目录别名、跨环境复用，以及 installer/service 与 application ID 不一致。

| 环境 | application / installer / credential service | 当前用户产品目录 | MSI UpgradeCode |
| --- | --- | --- | --- |
| dev | `haruka.dictionary.dev` | `%LOCALAPPDATA%\Programs\Haruka Dev` | `D5BEF236-054E-589D-8A3E-79CC8FEE4037` |
| production | `haruka.dictionary` | `%LOCALAPPDATA%\Programs\Haruka` | `B17838EE-499A-503C-B3DC-366BEEFBFF9F` |

UpgradeCode 是 `UUIDv5(NAMESPACE_URL, "urn:haruka:windows-installer:" + installer_id)`，同一环境升级保持不变；ProductCode 在该输入后追加 `:<三段版本>` 得到，因此每版更新。未来真实安装包必须延续环境身份映射，并审查原型到真实组件的迁移。禁止为了换名称重新随机生成 UpgradeCode，或在环境之间复用 Component GUID。当前组件 GUID 仅用于两个探针文件。

MSI 写入 HKCU 的 `Software\Haruka\Installations\<installer_id>`，不请求提升、不启动应用、不注册服务/快捷方式、不安装信任证书，也不关闭应用进程。只有已登记文件和空产品目录由 Windows Installer 管理；没有通用递归删除脚本。

凭据证明使用 Windows Credential Manager 的 Generic 类型，target 为 `<credential_service>/b0-installer-proof/<本轮随机 ID>`，内容仅为环境名和测试标记。写入拒绝已有 target；删除前校验本轮内容。证明脚本负责清理合成凭据，MSI 不调用凭据操作。真实应用的存储、账号/服务端身份分区与卸载后凭据保留策略尚未由本原型实现。

## 工具链

[toolchain.json](toolchain.json) 锁定官方 WiX 5.0.2 NuGet 包 URL、SHA256、作者签名指纹，以及本机使用的 .NET SDK 8.0.200 / .NET 6.0.36。工具包不声明外部 NuGet 依赖；编译器内容封装在已验签 nupkg。bootstrap 使用清空公共源的临时 NuGet.Config，仅从验签后的本地 feed 执行官方 `dotnet tool install --tool-path`，文件位于仓库 `.tools/wix-5.0.2`，不执行 Windows 工具安装器或写卸载注册信息。[官方工具用法](https://docs.firegiant.com/wix/using-wix/)、[dotnet tool-path 文档](https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-tool-install)、[锁定包/依赖/许可证](https://www.nuget.org/packages/wix/5.0.2)。

这是局部原型的工具选择，不声明 5.0.2 为当前生产推荐版本或仍受长期支持。WiX 7.0.0 在构建时要求接受商业 OSMF EULA，本次未接受条款或费用；5.0.2 使用官方 [MS-RL](https://github.com/wixtoolset/wix/blob/v5.0.2/LICENSE.TXT)。生产打包工具链与签名仍需独立决定。

此前官方 Inno Setup 7.1.0 编译器安装尝试被自动审批审查拒绝，返回 `blocked by policy`，未提供细化原因。未重复执行或换壳执行该安装动作；官方没有便携包，第三方解包工具未执行。WiX 的官方工作区本地工具还原只写工具文件，是已实施的替代路径。[Inno 下载](https://jrsoftware.org/isdl.php)、[第三方工具支持边界](https://jrsoftware.org/is3rdparty.php)。

## 命令与验证

从仓库根执行。每轮必须使用尚不存在的输出目录；构建仅允许 `artifacts/windows-installer/` 下输出。bootstrap 需要下载官方包；之后编译和安装证明不调用网络。

```powershell
& tools/packaging/windows/bootstrap.ps1
.tools/uv/uv.exe run --project backend --locked python tools/packaging/windows/build_probe.py --output artifacts/windows-installer/<新证据目录>
& tools/packaging/windows/verify.ps1 -Manifest artifacts/windows-installer/<新证据目录>/manifest.json
```

构建顺序固定为 dev 0.1.0、production 0.1.0、dev 0.1.1。verify 在任何写入前检查包摘要/MSI 属性和当前身份状态；任一预定产品目录、HKCU 身份键、ProductCode 或 UpgradeCode 已存在即停止，保护现有安装。真实运行依次安装两环境、检查文件摘要和独立凭据、升级 dev、检查 production 保持、卸载 dev、再次读取 production 凭据，最后清理两个合成凭据并卸载本轮剩余产品。每次卸载均限定本轮尝试的 ProductCode，且要求载荷和注册信息仍匹配。

输出 `manifest.json`、3 个 MSI、5 个 msiexec 日志与 `proof.json`。只有实际断言通过且清理无残留，`proof.json.passed` 才为 true；不能仅凭安装进程退出 0 签收。自动审批若拒绝实际安装/卸载，应停止被拒动作并保留失败记录，不替换执行方式重试。

```powershell
.tools/uv/uv.exe run --project backend --locked ruff check --config backend/pyproject.toml tools/packaging/windows
.tools/uv/uv.exe run --project backend --locked ruff format --check --config backend/pyproject.toml tools/packaging/windows
.tools/uv/uv.exe run --project backend --locked pyright --project tools/packaging/windows/pyrightconfig.json
.tools/uv/uv.exe run --project backend --locked python -m unittest discover -s tools/packaging/windows -p test_build_probe.py -v
```

当前真实证据见 [本轮记录](../../../docs/delivery/reviews/2026-09-22-b0-windows-installer.md)。这组命令只覆盖打包原型，不重跑 Flutter 三平台应用矩阵。
