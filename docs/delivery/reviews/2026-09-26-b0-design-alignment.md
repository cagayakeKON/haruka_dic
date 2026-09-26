# B0 与最新设计对齐

日期：2026-09-26。阶段1内的 B0 增量小阶段，必要验证与两轮定点Review已完成。由 GPT-6 Sol 分别实现前后端，主 Agent 负责范围、代码Review和交付核对；本记录不替换 [2026-09-22 B0 验收](2026-09-22-b0-acceptance.md)的历史候选和完整矩阵。

## 本次范围

- 已有12张基础表对齐现行命名、账号安全版本、角色显示字段和授权数据范围；新增 Alembic revision，保留0001历史，不预建其余目标业务表。
- 发布权限目录补齐错题读取、错题收藏和头像更新；种子升级只创建缺失目录/角色，不覆盖已有人工授权。
- Flutter B0应用壳采用「晴空频率」主题、卡片和响应式排版，补充首版日英材料说明；保留真实健康检查和环境身份。
- 模型、受控结构基线、迁移清单、生成字典、相关测试与文档同步。

前端负责 `frontend/`，后端负责 `backend/` 及后端导出的 `contracts/`；主 Agent 维护文档并审查两端提交内容。用户指定的目标模式仅组织本次工作，不扩大 B0 范围。

## 验证与 Review

检查只覆盖本次修改的模型、迁移、受控初始化、权限注册、生成契约和 Flutter 壳。新增迁移涉及真实 PG 数据兼容，因此需要隔离测试库中的空库、旧版本升级、非法历史数据拒绝与事务回滚证据；视觉调整需要现有页面及布局/文字缩放的 widget 回归。静态分析和文档检查按受影响范围执行。

| 范围 | 实际结果 |
| --- | --- |
| 后端受影响模块 | `tests/integration/test_migrations.py`、`test_initialization.py`，`tests/unit/test_database_models.py`、`test_migrations.py`、`test_registry_references.py`，`tests/contract/test_models_export.py`：66项通过，59.09秒 |
| 最后迁移错误类型修订 | 旧0001升级/拒绝参数化用例及manifest漂移拒绝：7项补测通过，6.49秒；不是新增7项独立覆盖 |
| PostgreSQL兼容与保护 | 空库与旧0001升级；旧ID、密码哈希、创建时间、人工deny保留；安全版本中性回填、邮箱验证保持空；错误范围/受众、孤儿角色/权限/账号拒绝并留在旧revision；首管理员范围错误或混入错误scope时无账号/资料库写入 |
| 受控迁移与种子 | 同物理连接争锁/断连恢复，seed并发幂等、人工授权保留、首管理员原子初始化、UTC时间与约束检查均在上述定点集通过 |
| 后端静态与生成 | 受影响Python的Ruff/Pyright通过；注册检查通过；六份后端导出文件与根contracts逐字节一致；migration manifest验证通过 |
| Flutter壳 | `shell_test.dart`、`health_widget_test.dart`、`controls_test.dart`共14项通过；包含390×844与1280×400的200%文字、导航Key/语义与键盘、尺寸变化保留路由及健康请求无重复 |
| Flutter静态与生成 | Dart格式化、`flutter analyze --fatal-infos --fatal-warnings`无问题；`frontend/tool/generate.py --check`通过 |
| 文档 | 本次18份Markdown的本地链接、围栏及路径检查通过；Markdownlint零问题，`git diff --check`通过 |

测试在现有锁定工具环境执行：后端为Python3.13虚拟环境，PG配置显式选择`dev/.local/test-maintenance.env`，每用例只创建/清理本人随机`haruka_migration_test_*` schema。结果来自本轮工具终端记录，没有另存持久测试报告，因此不提供不存在的报告路径，也不将其包装成原44节点矩阵的签收产物。

第一轮主Agent代码Review发现新CHECK名称会被命名约定重复加前缀，以及非法历史数据的RuntimeError绕过统一维护错误处理；Sol改用`op.f(...)`与`MigrationError`，补齐旧数据保留和范围拒绝回归。第二轮定点复核确认修复与补测，无未关闭代码缺陷。前端壳Review未发现阻断问题。

主Agent维护的文档由前端Sol独立审阅，发现两处将已完成改名/增量仍称为未来设计的残留；集中修正后，第二轮复核通过。没有开启第三轮全仓审查。

当前迁移头为`0002_b0_identity_alignment`，种子/权限目录为`b0-identity-v3`，共94个权限代码；字典仍为12张业务表。0001文件SHA256保持`32a61198fdaf75fb357173f0b70a4c9230e8b61f516f26c06ee04b4c8fdc6467`。已有角色不会因目录增加而自动获得新权限，需后续受控授权。

## 保留边界

B1登录/收藏/实际RBAC、B2持久任务与Outbox投递仍未实现。NLP、视觉OCR、查询上下文、AI成品缓存、TTS适配器/音频缓存和142张目标表中的后续业务结构继续按所属切片实施；本次不会以可点击的假业务入口代替这些能力。

本次仅升级测试库的随机schema，未升级开发库或生产库，未操作MyHome业务。开发实例使用新代码前须停止旧应用，通过现有受控`db upgrade`及`seed apply`入口升级；普通启动仍不自动迁移，不提供新旧表名并行兼容层。未重跑Windows/Linux干净构建、三端完整E2E和原44节点矩阵，不宣称当前HEAD重新完成完整B0验收。

本小阶段按仓库规则本地提交，不push；提交身份以Git实际历史为准，不在文档中循环写入自身commit哈希。
