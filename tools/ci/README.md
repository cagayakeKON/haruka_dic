# B0 检查器与 CI

当前仓库未配置远端。GitHub Actions 文件是可版本控制的参考实现，尚未发生远端运行，也未设置分支保护。`quality.yml` 分 Windows/Linux 运行本次检查器单元，并通过独立锁定 test 依赖 job 验证真实 pytest 适配器；`platform-checks.yml` 只在显式选择影响范围时运行后端检查或某个平台构建，构建成功不代表平台运行或完整 B0 验收。

Actions 使用在官方仓库核验的完整 commit SHA、只读权限、关闭 checkout 凭据持久化；不配置部署秘密或付费供应商。Python、uv、Node、Flutter 使用项目锁定版本，Flutter 还核对精确 revision。宿主 runner 的 OS 镜像可变，因此实际平台/工具证据仍是验收必需项。依据：[GitHub 工作流安全](https://docs.github.com/en/actions/reference/security/secure-use)。

## 本地质量切片

从根目录用锁定 Python 3.13.6 执行，输出目录每次必须是新目录：

```text
python -m tools.ci.quality --commit <实际40位commit> --output artifacts/quality/<唯一运行目录>
uv run --project backend --locked python -m tools.ci.quality --scope B0-pytest-adapter --commit <实际40位commit> --output artifacts/quality/<另一唯一目录>
```

该入口运行 `required_cases.json` 的 `B0-quality` 精确节点，保存 collection/result 原始结构化记录、identity、检查器结论、素材校验和手写源清单。单独选择测试不能缩减 `B0` 的必需矩阵。B0 的 SCF-01～06 程序与平台记录仍在 [程序索引](b0-procedures.json) 登记；索引是执行计划，不能作为通过证据。

完整B0已取得 [本地验收记录](../../docs/delivery/reviews/2026-09-22-b0-acceptance.md)。统一入口 `scripts/dev.py check --stage B0 --identity <候选身份> --report <报告>` 消费全部collection/result报告，`--report`可重复；它调用下述既有检查器，不自动发现报告、不重新执行测试、不将当前HEAD自动视为已验收。实际26份输入、11份procedure索引和最终矩阵的路径/SHA256见 [证据摘要清单](../../docs/delivery/reviews/2026-09-22-b0-evidence-manifest.json)，原始运行文件仍按规则保存在本机ignored artifacts。

## 报告合同

[必需用例清单](../../scripts/quality/required_cases.json) 单向关联 case_id、验收引用、精确测试节点、主要层级、runner、平台、受众、传输、参数和责任分片。同一 case 的不同参数/平台形成不同执行键。报告必须绑定同一 `commit/build_id/configuration/toolchain_sha256/run_id`，每次 attempt 都需要完整 collection/result 和 `session_status=passed`；suite 清理错误、pytest 收集/会话失败、skip、xfail、xpass、deselect、缺记录或错误驱动不能变成通过。后续重试不覆盖首次失败，不同 attempt 的部分节点不能互相补齐。

```text
python -m scripts.quality.cases --scope B0 --identity artifacts/run/identity.json --report artifacts/run/collection.json --report artifacts/run/result.json --output artifacts/run/acceptance.json
```

报告 schema 由 [检查器](../../scripts/quality/cases.py) 校验；`unittest_runner` 和 `pytest_plugin` 是当前实际收集器。Flutter、Playwright、人工平台报告须由各真实驱动转换相同结构，不能把整个命令退出 0 转成每个节点 passed。pytest 显式加载 `-p scripts.quality.pytest_plugin`，传入 `--quality-manifest/identity/shard/scope/output`；harness 将仓库根放入 PYTHONPATH，不改变生产包。

人工 procedure 的结果节点额外包含 `procedure`：`author/reviewer/reviewed_at/assertions`。作者与reviewer必须不同，审查时间含时区；assertions键与case登记清单完全一致，每项包含 `passed=true/evidence_path/sha256`，证据需位于仓库内、非空且摘要匹配。实际命令、断言、工具/制品在这些证据中由独立reviewer核验；只有自由文本“测过”或缺hash的结果不能通过。

## 覆盖分母

[coverage_manifest.json](../../scripts/quality/coverage_manifest.json) 逐一登记所有 Python/Dart 手写源、核心分组和窄例外。新增源文件或核心路径漏登记立即失败。生成物只有在受管生成清单登记来源/生成器/精确输出时可排除；纯声明必须经 AST 或 Dart 指令检查。小阶段只运行 `--inventory-only` 及检查器坏样本，不为凑百分比触发全仓测试。

```text
python -m scripts.quality.coverage --inventory-only --output artifacts/run/inventory.json
python -m scripts.quality.coverage --identity artifacts/run/identity.json --evidence artifacts/run/coverage-evidence.json --output artifacts/run/coverage.json
```

完整覆盖入口用于大阶段，接收 JSON receipt：`schema_version/identity/shards`。每个 shard 明确 `id/language/format/path/sha256/path_base`，路径相对仓库；Python `format=coverage-json`、`path_base=backend`，Flutter `format=lcov`、`path_base=frontend`。跨平台报告若含绝对源路径，必须显式给该分片的 `checkout_root` 才能规范为仓库路径，不能把仓库外路径自动猜成源码。报告需由同次运行产生，Python 必须启用分支。文件/必要分片缺失失败；同一文件分片的分母必须一致，命中取并集。Python 按语句加分支、Flutter 按可执行行加权统计总体和核心组，不平均文件百分比；逐文件输出未命中位置。当前清单阈值来自[测试规范](../../docs/engineering/testing/strategy.md)，本切片没有宣称全仓覆盖达标。

## 测试素材

[素材索引](../../testdata/assets/manifest.json) 是固定样本唯一入口；B0 只纳入自建英/日 Unicode 文本。严格 JSON 场景只执行 `validate_static_assets` 的只读配方，没有账号、SQL、进程或供应商能力。后续业务场景由正式测试工厂添加有类型配方，不向生产 HTTP 增加测试旁路。

```text
python -m scripts.quality.testdata --output artifacts/run/testdata.json
```
