# 数据库设计书：账号、权限与个人设置

状态：DBDESIGN3 命名与关系基线 v0.3，2026-09-25。属于阶段1后续表设计文档切片；第1节记录经2026-09-26增量对齐的B0物理结构，第2节区分已完成与待实施增量，其余为拟实施设计，不代表登录、完整 RBAC 或设置已经实现。总规则、公共列组与分册入口见 [数据库设计书](database-design.md)。

本分册依据 [认证](authentication.md)、[授权](authorization.md)、[账号](../modules/accounts.md)、[设置](../modules/settings.md)、[管理](../modules/admin.md)、[权限目录](../contracts/permissions.md) 和 [API](../contracts/api.md)。原型账号、语言、阅读、声音和显示页用于核对字段用途；原型内的固定年份、模型名、声音名与本机表单值不是数据库默认值。

字段记法：`NN` 为 NOT NULL，`NULL` 为可空，`—` 表示无数据库默认值；`B` = `id uuid NN`（服务端 uuid4、无数据库默认）+ `created_at/updated_at timestamptz NN DEFAULT now()`；`U` = B + `user_id uuid NN`；`R` = `revision bigint NN DEFAULT 1 CHECK(revision >= 1)`。仅拟新增表使用这些列组；现有表下方逐列展开，保留自然主键例外。所有逻辑关联都不创建物理外键，不使用隐式级联。

## 1. 已实现的 B0 基线：12张表

核对来源为 [模型字典](../../contracts/database-schema.json)、[身份模型](../../backend/app/models/identity.py)、[授权模型](../../backend/app/models/authorization.py)、[0001迁移](../../backend/alembic/versions/0001_b0_identity.py)、[0002增量迁移](../../backend/alembic/versions/0002_b0_identity_alignment.py) 和 [受控结构基线](../../backend/app/maintenance/schema_baseline.json)。数据库默认与 ORM 默认区别：下表 id 的数据库默认是“—”，UUID由服务端生成；updated_at 的 ORM onupdate=now() 不是数据库触发器。

所有现有表入口仅为受控维护初始化；B0无公开删除。涉及关联写入时先锁 authorization_revisions 的 global 行，再锁目标父行；global 行尚不存在时使用既有维护 advisory lock。所有者不可变，普通关系有引用则限制删除，注明历史关系的审计/Outbox引用保留。下表索引仅记录当前实际存在者，未补列未来登录/分页索引。

### admin_audit_events

scope_kind='system_operation'；归属：无私有归属列；生命周期：追加写，创建后不修改。受控初始化追加审计，不包含密码、邮箱或私有材料。

| 列 | PostgreSQL类型 | NULL | DB默认 | 语义 |
| --- | --- | --- | --- | --- |
| `action` | varchar(32) | NN | — | 已注册的维护动作 |
| `actor` | varchar(64) | NN | — | 固定受控维护主体 |
| `target_user_id` | uuid | NULL | — | 目标账号引用；目录种子为空 |
| `authorization_revision` | bigint | NN | — | 同事务提交的授权版本 |
| `id` | uuid | NN | — | 服务端生成的稳定标识；主键 |
| `created_at` | timestamptz | NN | now() | 本行创建时间，UTC |
| `updated_at` | timestamptz | NN | now() | 本行最近一次实际更新的时间，UTC |

约束与索引：

- `ck_admin_audit_events_action`：check（action IN ('seed.applied', 'admin.created')）。
- `ck_admin_audit_events_authorization_revision_positive`：check（authorization_revision >= 1）。
- `pk_admin_audit_events`：primary_key（id）。

逻辑关联：`target_user_id → users.id`（历史保留）。

### auth_policies

scope_kind='system_catalog'；归属：无私有归属列；生命周期：可变；B0保留。注册策略；B0默认关闭注册，不决定后续开放方式。

| 列 | PostgreSQL类型 | NULL | DB默认 | 语义 |
| --- | --- | --- | --- | --- |
| `code` | varchar(32) | NN | — | 固定策略代码；主键 |
| `registration_mode` | varchar(16) | NN | — | 注册入口策略 |
| `default_role_id` | uuid | NN | — | 普通注册初始角色，不允许受保护角色 |
| `revision` | bigint | NN | 1 | 策略并发修改版本 |
| `created_at` | timestamptz | NN | now() | 本行创建时间，UTC |
| `updated_at` | timestamptz | NN | now() | 本行最近一次实际更新的时间，UTC |

约束与索引：

- `ck_auth_policies_code`：check（code = 'registration'）。
- `ck_auth_policies_registration_mode`：check（registration_mode IN ('closed', 'approval', 'open')）。
- `ck_auth_policies_revision_positive`：check（revision >= 1）。
- `pk_auth_policies`：primary_key（code）。

逻辑关联：`default_role_id → roles.id`（限制删除）。

### authorization_revisions

scope_kind='system_operation'；归属：无私有归属列；生命周期：可变；B0保留。授权目录全局版本与共同父行锁。

| 列 | PostgreSQL类型 | NULL | DB默认 | 语义 |
| --- | --- | --- | --- | --- |
| `code` | varchar(16) | NN | — | 固定授权锁行标识；主键 |
| `revision` | bigint | NN | 1 | 授权修改单调版本 |
| `created_at` | timestamptz | NN | now() | 本行创建时间，UTC |
| `updated_at` | timestamptz | NN | now() | 本行最近一次实际更新的时间，UTC |

约束与索引：

- `ck_authorization_revisions_code`：check（code = 'global'）。
- `ck_authorization_revisions_revision_positive`：check（revision >= 1）。
- `pk_authorization_revisions`：primary_key（code）。

逻辑关联：无。

### libraries

scope_kind='library_root'；归属：owner_user_id；生命周期：可变；B0保留。每个账号唯一的私有资料库根。

| 列 | PostgreSQL类型 | NULL | DB默认 | 语义 |
| --- | --- | --- | --- | --- |
| `owner_user_id` | uuid | NN | — | 服务根据已验证账号派生的库所有者 |
| `id` | uuid | NN | — | 服务端生成的稳定标识；主键 |
| `created_at` | timestamptz | NN | now() | 本行创建时间，UTC |
| `updated_at` | timestamptz | NN | now() | 本行最近一次实际更新的时间，UTC |

约束与索引：

- `pk_libraries`：primary_key（id）。
- `uq_libraries_owner_user_id`：unique（owner_user_id）。

逻辑关联：`owner_user_id → users.id`（限制删除）。

### menus

scope_kind='system_catalog'；归属：无私有归属列；生命周期：可变；B0保留。绑定发布路由键的菜单目录；B0管理菜单不可用。

| 列 | PostgreSQL类型 | NULL | DB默认 | 语义 |
| --- | --- | --- | --- | --- |
| `code` | varchar(64) | NN | — | 菜单代码 |
| `route_key` | varchar(64) | NN | — | 前端已注册路由键 |
| `audience` | varchar(10) | NN | — | 菜单受众 |
| `permission_code` | varchar(100) | NN | — | 显示所需权限；不代替接口授权 |
| `enabled` | boolean | NN | — | 菜单是否提供可用入口 |
| `revision` | bigint | NN | 1 | 菜单配置版本 |
| `id` | uuid | NN | — | 服务端生成的稳定标识；主键 |
| `created_at` | timestamptz | NN | now() | 本行创建时间，UTC |
| `updated_at` | timestamptz | NN | now() | 本行最近一次实际更新的时间，UTC |

约束与索引：

- `ck_menus_audience`：check（audience IN ('client', 'admin')）。
- `ck_menus_revision_positive`：check（revision >= 1）。
- `pk_menus`：primary_key（id）。
- `uq_menus_code`：unique（code）。

逻辑关联：`permission_code → permission_catalog.code`（限制删除）。

### outbox_events

scope_kind='system_operation'；归属：无私有归属列；生命周期：可变；B0保留。授权变更持久通知；B0只提交，B1按所选账号通知需要先实现投递，B2复用并扩充。

| 列 | PostgreSQL类型 | NULL | DB默认 | 语义 |
| --- | --- | --- | --- | --- |
| `event_type` | varchar(48) | NN | — | 已注册事件类型 |
| `audit_event_id` | uuid | NN | — | 同事务追加的审计标识 |
| `authorization_revision` | bigint | NN | — | 待通知的授权版本 |
| `status` | varchar(16) | NN | — | 投递状态 |
| `id` | uuid | NN | — | 服务端生成的稳定标识；主键 |
| `created_at` | timestamptz | NN | now() | 本行创建时间，UTC |
| `updated_at` | timestamptz | NN | now() | 本行最近一次实际更新的时间，UTC |

约束与索引：

- `ck_outbox_events_authorization_revision_positive`：check（authorization_revision >= 1）。
- `ck_outbox_events_event_type`：check（event_type = 'authorization.changed'）。
- `ck_outbox_events_status`：check（status IN ('pending', 'published')）。
- `pk_outbox_events`：primary_key（id）。
- `uq_outbox_events_audit_event_id`：unique（audit_event_id）。

逻辑关联：`audit_event_id → admin_audit_events.id`（历史保留）。

### permission_catalog

scope_kind='system_catalog'；归属：无私有归属列；生命周期：可变；B0保留。发布注册的权限目录；权限存在不代表接口已实现。

| 列 | PostgreSQL类型 | NULL | DB默认 | 语义 |
| --- | --- | --- | --- | --- |
| `code` | varchar(100) | NN | — | 不可由后台任意创建的权限代码；主键 |
| `audience` | varchar(10) | NN | — | 登录受众 |
| `data_scope` | varchar(24) | NN | — | 允许的数据范围 |
| `enabled` | boolean | NN | — | 权限是否启用 |
| `created_at` | timestamptz | NN | now() | 本行创建时间，UTC |
| `updated_at` | timestamptz | NN | now() | 本行最近一次实际更新的时间，UTC |

约束与索引：

- `ck_permission_catalog_audience`：check（audience IN ('client', 'admin')）。
- `ck_permission_catalog_data_scope`：check（data_scope IN ('self', 'platform_metadata')）。
- `pk_permission_catalog`：primary_key（code）。

逻辑关联：无。

### role_permission_links

scope_kind='system_catalog'；归属：无私有归属列；生命周期：可变；B0保留。角色显式允许或拒绝；匹配的拒绝优先。

| 列 | PostgreSQL类型 | NULL | DB默认 | 语义 |
| --- | --- | --- | --- | --- |
| `role_id` | uuid | NN | — | 锁定并核对的角色标识 |
| `permission_code` | varchar(100) | NN | — | 已注册的权限代码 |
| `effect` | varchar(8) | NN | — | 允许或显式拒绝 |
| `data_scope` | varchar(24) | NN | — | 授权数据范围，须与权限目录匹配 |
| `id` | uuid | NN | — | 服务端生成的稳定标识；主键 |
| `created_at` | timestamptz | NN | now() | 本行创建时间，UTC |
| `updated_at` | timestamptz | NN | now() | 本行最近一次实际更新的时间，UTC |

约束与索引：

- `ck_role_permission_links_data_scope`：check（data_scope IN ('self', 'platform_metadata')）。
- `ck_role_permission_links_effect`：check（effect IN ('allow', 'deny')）。
- `pk_role_permission_links`：primary_key（id）。
- `uq_role_permission_links_role_id_permission_code_e_5e3b7fafe483`：unique（role_id, permission_code, effect, data_scope）。
- `ix_role_permission_links_permission_code_role_id`：(permission_code, role_id)；权限停用时查引用角色。

逻辑关联：`role_id → roles.id`（限制删除）；`permission_code → permission_catalog.code`（限制删除）。

### roles

scope_kind='system_catalog'；归属：无私有归属列；生命周期：可变；B0保留。角色定义；种子只创建缺失角色，不覆盖人工授权。

| 列 | PostgreSQL类型 | NULL | DB默认 | 语义 |
| --- | --- | --- | --- | --- |
| `code` | varchar(64) | NN | — | 稳定角色代码 |
| `name` | varchar(100) | NN | — | 非唯一的角色显示名，旧记录按code回填 |
| `description` | text | NULL | — | 角色说明 |
| `protected` | boolean | NN | — | 受保护角色标记 |
| `enabled` | boolean | NN | — | 角色是否启用 |
| `revision` | bigint | NN | 1 | 角色并发修改版本 |
| `id` | uuid | NN | — | 服务端生成的稳定标识；主键 |
| `created_at` | timestamptz | NN | now() | 本行创建时间，UTC |
| `updated_at` | timestamptz | NN | now() | 本行最近一次实际更新的时间，UTC |

约束与索引：

- `ck_roles_revision_positive`：check（revision >= 1）。
- `pk_roles`：primary_key（id）。
- `uq_roles_code`：unique（code）。

逻辑关联：无。

### seed_versions

scope_kind='system_operation'；归属：无私有归属列；生命周期：可变；B0保留。已应用种子版本与摘要；拒绝同版本内容漂移。

| 列 | PostgreSQL类型 | NULL | DB默认 | 语义 |
| --- | --- | --- | --- | --- |
| `code` | varchar(64) | NN | — | 种子发布代码；主键 |
| `version` | bigint | NN | — | 种子协议版本 |
| `payload_sha256` | varchar(64) | NN | — | 权威种子内容摘要 |
| `created_at` | timestamptz | NN | now() | 本行创建时间，UTC |
| `updated_at` | timestamptz | NN | now() | 本行最近一次实际更新的时间，UTC |

约束与索引：

- `ck_seed_versions_digest`：check（payload_sha256 ~ '^[a-f0-9]{64}$'）。
- `ck_seed_versions_version_positive`：check（version >= 1）。
- `pk_seed_versions`：primary_key（code）。

逻辑关联：无。

### user_role_links

scope_kind='user_owned'；归属：user_id；生命周期：可变；B0保留。账号角色关联；受控事务内校验身份与受保护角色。

| 列 | PostgreSQL类型 | NULL | DB默认 | 语义 |
| --- | --- | --- | --- | --- |
| `user_id` | uuid | NN | — | 已锁定账号标识 |
| `role_id` | uuid | NN | — | 已锁定角色标识 |
| `id` | uuid | NN | — | 服务端生成的稳定标识；主键 |
| `created_at` | timestamptz | NN | now() | 本行创建时间，UTC |
| `updated_at` | timestamptz | NN | now() | 本行最近一次实际更新的时间，UTC |

约束与索引：

- `pk_user_role_links`：primary_key（id）。
- `uq_user_role_links_user_id_role_id`：unique（user_id, role_id）。
- `ix_user_role_links_role_id_user_id`：(role_id, user_id)；检查受保护角色成员与最后管理员。

逻辑关联：`user_id → users.id`（限制删除）；`role_id → roles.id`（限制删除）。

### users

scope_kind='identity'；归属：无私有归属列；生命周期：可变；B0保留。独立账号身份；B0只支持受控首管理员初始化。

| 列 | PostgreSQL类型 | NULL | DB默认 | 语义 |
| --- | --- | --- | --- | --- |
| `email` | varchar(254) | NN | — | 账号显示邮箱 |
| `email_normalized` | varchar(254) | NN | — | 按账号规则规范化的唯一邮箱 |
| `password_hash` | varchar(512) | NN | — | Argon2id密码哈希，不存明文 |
| `status` | varchar(16) | NN | — | 账号状态 |
| `authz_version` | bigint | NN | 1 | 账号授权版本 |
| `password_version` | bigint | NN | 1 | 密码哈希版本，旧哈希按1回填 |
| `security_epoch` | bigint | NN | 0 | 全局持久撤销代次 |
| `revision` | bigint | NN | 1 | 账号并发修改版本 |
| `email_verified_at` | timestamptz | NULL | — | 实际邮箱验证时间，旧记录不推定已验证 |
| `locked_until` | timestamptz | NULL | — | 有期限的安全锁定截止 |
| `client_security_epoch` | bigint | NN | 0 | 用户端持久撤销代次 |
| `admin_security_epoch` | bigint | NN | 0 | 管理端持久撤销代次 |
| `id` | uuid | NN | — | 服务端生成的稳定标识；主键 |
| `created_at` | timestamptz | NN | now() | 本行创建时间，UTC |
| `updated_at` | timestamptz | NN | now() | 本行最近一次实际更新的时间，UTC |

约束与索引：

- `ck_users_authz_version_positive`：check（authz_version >= 1）。
- `ck_users_password_version_positive`：check（password_version >= 1）。
- `ck_users_revision_positive`：check（revision >= 1）。
- `ck_users_security_epoch_nonnegative`：check（security_epoch >= 0）。
- `ck_users_email_length`：check（length(email_normalized) BETWEEN 3 AND 254）。
- `ck_users_security_epochs_nonnegative`：check（client_security_epoch >= 0 AND admin_security_epoch >= 0）。
- `ck_users_status`：check（status IN ('pending', 'active', 'disabled')）。
- `pk_users`：primary_key（id）。
- `uq_users_email_normalized`：unique（email_normalized）。
- `ix_users_status_created_at_id`：(status, created_at, id)；管理列表索引，管理接口尚未实现。

逻辑关联：无。

## 2. 既有表的增量状态

账号安全字段、角色显示字段与授权范围已由0002增量实现，详情以第1节和生成字典为准；其余表仍需后续Alembic迁移。0001历史保持不变，不把未实现列写入生成字典。添加列先回填并验证，再收紧约束；B0自然主键保留，不为了整齐重建授权目录。

DBDESIGN3约定的 `user_roles → user_role_links`、`role_permissions → role_permission_links` 已写入0002受控迁移，仍分别承载用户↔角色、角色↔权限的多对多关系。迁移保留原行ID、allow/deny及账号哈希；孤儿关联或受众/范围不匹配时拒绝整次revision。第1节和生成字典使用当前名称，表数仍为12；运行实例须通过受控入口升级后才具有新结构。验证与实例边界见[B0设计对齐](../delivery/reviews/2026-09-26-b0-design-alignment.md)。

| 表与状态 | 新列/调整 | 约束与索引/迁移依据 |
| --- | --- | --- |
| users（0002已实现） | `password_version bigint NN DEFAULT 1`；`security_epoch bigint NN DEFAULT 0`；`revision bigint NN DEFAULT 1`；`email_verified_at timestamptz NULL`；`locked_until timestamptz NULL` | password_version/revision>=1、security_epoch>=0；B0已有两端epoch继续保留。账号全局epoch与受众epoch分别对比；旧哈希按1回填，不凭创建时间推定邮箱验证。已加 `(status,created_at,id)` 管理列表索引；锁定为有期限安全属性，不扩展status枚举或形成永久锁号 |
| roles（0002已实现） | `name varchar(100) NN`；`description text NULL` | name仅显示非唯一；按既有code回填，更新revision和updated_at。角色依赖/引用仍由授权服务限制删除 |
| role_permission_links（0002已实现） | `data_scope varchar(24) NN` | 从permission_catalog回填并核对；CHECK self/platform_metadata，服务校验权限受众与范围。唯一键改为 `(role_id,permission_code,effect,data_scope)`；不另建可写casbin_rule |
| menus（待实施） | `parent_menu_id uuid NULL`；`component_key varchar(64) NULL`；`title varchar(100) NN`；`icon_key varchar(64) NULL`；`sort_order integer NN DEFAULT 0`；`permission_match varchar(3) NN DEFAULT 'all'` | parent同受众且无环；sort_order>=0，match=all/any。route_key改为可空以表示分组；叶子route/component由发布注册表匹配。将既有permission_code搬入menu_permission_links后删除该列；父子索引 `(audience,parent_menu_id,sort_order,id)`。最低页面权限保持代码定义，表中条件只能追加 |
| auth_policies（待实施） | `require_email_verification boolean NN DEFAULT false`；`recovery_mode varchar(16) NN DEFAULT 'disabled'` | 仅在[账号待决](../decisions/pending.md)交付路径锁定后启用；recovery_mode=disabled/email/manual，部署必须具备所选交付能力；不把默认false当确认无需验证邮箱 |
| admin_audit_events（待实施） | `actor_user_id uuid NULL`；`audience varchar(10) NULL`；`permission_code varchar(100) NULL`；`target_type varchar(64) NULL`；`target_id uuid NULL`；`target_code varchar(100) NULL`；`operation_id uuid NULL`；`request_id uuid NULL`；`result varchar(24) NULL`；`reason_code varchar(64) NULL`；`payload_schema_version integer NN DEFAULT 1`；`change_summary jsonb NULL` | 扩展action长度到100并按发布事件注册，旧两动作CHECK由版本化允许清单替换；旧actor保留用于维护主体。新用户管理事件必须有actor_user_id/受众/安全结果；target_id与target_code按UUID实体/自然键目录择一，不能丢失permission/auth-policy等自然键目标；旧记录允许NULL且不伪造事实。summary只放白名单权限/状态差异，非完整对象。拟加 `(created_at,id)`、`(actor_user_id,created_at,id)`、`(target_type,target_id,created_at,id)`、`(action,created_at,id)`；按管理员授权时间窗口查询 |
| outbox_events（待实施） | B0字段保留；后续通用事件、聚合引用、重试/租约/发布时间由任务分册统一定义 | 不能把B0仅authorization.changed且audit_event_id必填的结构称为通用投递已实现；新旧事件兼容与索引见[总册](database-design.md)的任务分册入口 |

`users.revision` 用于管理表单并发；`authz_version` 用于本人角色变化；`authorization_revisions.revision` 为全局策略版本，API的policy_revision映射此列；`security_epoch/client_security_epoch/admin_security_epoch` 为撤销，`password_version` 为密码校验结果版本。五类职责不可用updated_at或同一个revision替代。

## 3. 个人资料与设置（拟新增）

本节表均为 `scope_kind=user_owned`，权威归属 `user_id → users.id`。注册事务只创建一个 `user_extensions` 空扩展行；资料、单例学习偏好和通用设置按字段组合并，API/权限/DTO仍分别处理。语言、模型、声音等真正的一对多选择保持子表，按实际选择创建，不预置假语言/模型/Key。所有表包含公共U，未单独列出的默认值均为“—”。

### user_extensions

列组：U；唯一 `(user_id)`。身份密码/安全epoch/授权字段只在 users，本表不保存秘密、会话或高频容量计数。这里不叠加一个要求所有表单共同比较的R，分别采用三个字段组版本：

| 列 | PostgreSQL类型/NULL/默认 | 语义 |
| --- | --- | --- |
| profile_revision | bigint NN DEFAULT 1 | 资料及头像指针CAS，>=1 |
| study_revision | bigint NN DEFAULT 1 | 解释语/当前语与学习语言子行CAS，>=1 |
| settings_revision | bigint NN DEFAULT 1 | 通用设置及模型/声音绑定CAS，>=1 |

资料组：

| 列 | PostgreSQL类型/NULL/默认 | 语义 |
| --- | --- | --- |
| display_name | varchar(100) NULL | 本人称呼；非唯一，不从邮箱前缀回填 |
| avatar_asset_id | uuid NULL | 当前本人头像 → file_objects.id，必须purpose=avatar；没有头像为空 |
| avatar_revision | bigint NN DEFAULT 0 | 头像指针代次；替换/删除均递增 |
| birth_year | smallint NULL | 可选出生年份；不是年龄或身份依据 |
| gender_code | varchar(24) NULL | 设置模块受控代码，可清除 |
| gender_self_description | varchar(200) NULL | 仅self_described允许填写；不进入AI |
| use_optional_demographics_for_ai | boolean NN DEFAULT false | 允许明确功能使用最小派生人口资料 |

学习偏好单例组：

| 列 | PostgreSQL类型/NULL/默认 | 语义 |
| --- | --- | --- |
| explanation_language | varchar(35) NULL | 解释语言，逻辑关联language_capabilities.language_tag |
| active_target_language | varchar(35) NULL | 当前目标语，必须存在本人target语言子行 |

通用设置组：

| 列 | PostgreSQL类型/NULL/默认 | 语义 |
| --- | --- | --- |
| ui_locale | varchar(35) NN DEFAULT 'zh-Hans' | P0界面语言，和解释语言分开 |
| timezone | varchar(64) NULL | 用户确认的IANA时区；空表示未选择，使用服务端明确公布的展示回退 |
| theme_mode | varchar(8) NN DEFAULT 'system' | system/light/dark |
| reduce_motion | varchar(8) NN DEFAULT 'system' | system/on |
| high_contrast | varchar(8) NN DEFAULT 'system' | system/on |
| reading_font_family | varchar(16) NULL | serif/sans等已发布字体类别；空为应用默认 |
| reading_font_size | numeric(5,2) NULL | 逻辑字号，实际显示不低于系统无障碍比例 |
| reading_line_height | numeric(4,2) NULL | 行高倍率 |
| reading_theme | varchar(8) NULL | light/dark/sepia |
| playback_speed | numeric(3,2) NN DEFAULT 1.0 | 播放倍速，0.70–1.50，不改变合成键 |
| query_context_budget_tokens | integer NN DEFAULT 10000 | 本人查询补充前后文预算，CHECK 1000～64000；实际服务硬上限与模型窗口另验，规则见[上下文](../contracts/query-context.md)；属于settings_revision组 |
| explanation_detail | varchar(16) NULL | concise/standard/geek的展示策略，使用发布允许值 |
| exercise_defaults_schema_version | integer NN DEFAULT 1 | 有限默认偏好的schema版本 |
| exercise_defaults | jsonb NULL | 仅题型、方向、建议题数；无词本ID、掌握阈值、答案/AI输出 |
| default_notebook_id | uuid NULL | 本人词本 → vocabulary_notebooks.id；只是下次选择预填 |

CHECK包括：三个组版本>=1、avatar_revision>=0、birth_year为空或>=1900、gender枚举及非self_described时说明为空；设置枚举、正数字号/行高、0.70–1.50倍速、exercise_defaults对象与正schema版本。年份上界/IANA时区/语言能力/数组上限由服务校验。母语、解释语、学习语和ui_locale保持不同含义；资料完整度/年龄段按许可字段派生，不额外存列。字段组仍是明确类型列，不把整份扩展行改为任意JSON。

`avatar_asset_id` 直接逻辑引用本人 `file_objects.id`，只能指向purpose=avatar且完成受控重编码的对象；API的AvatarAsset是该对象的专用投影。替换/删除/头像GC共锁本扩展行，推进profile_revision及avatar_revision，失败保留旧指针。按user_id唯一查根已经支持本人引用核查，不重复创建(user_id,avatar_asset_id)索引。尺寸/校验版本由文件分册唯一维护。文件下载仍逐次鉴权private/no-store。

学习语言以子行表达。语言删除锁本扩展行后修改子行、active_target_language并只推进study_revision；不删除学习事实。模型/声音绑定修改只推进settings_revision。default_notebook_id引用本人词本，删除词本与解除默认必须共用“扩展行→词本”顺序，且推进settings_revision；服务地址、Token、设备缓存和account_generation不进本表。

每个PATCH把expected_revision映射到相应组列，UPDATE只写该组白名单列并推进该组版本及updated_at，禁止整行ORM覆盖。资料和主题并发更新会短暂争用同一PG行锁，但不同组不发生无意义的版本冲突；同组旧版本仍409。涉及多个组的单次操作必须显式声明并在同一事务比较全部相关组版本；普通独立页面不能互相回滚。读取一个组只选择该组允许列，物理合表不扩大DTO或管理权限。子行与组版本、Outbox同事务提交。

### user_languages

列组：U；以 user_id 逻辑关联 user_extensions.user_id；修改由父行 study_revision 保护。

| 列 | PostgreSQL类型/NULL/默认 | 语义 |
| --- | --- | --- |
| language_kind | varchar(8) NN | native/target，分别表示母语与目标语 |
| language_tag | varchar(35) NN | 规范BCP-47 → language_capabilities.language_tag |
| sort_order | integer NN | 有序多选的位置 |
| self_assessed_level | varchar(16) NULL | target时设置模块允许的水平；未填用unknown，native为空 |
| learning_goals | varchar(24)[] NN DEFAULT '{}' | 有限受控目标代码数组；空数组是明确无选择 |

唯一 `(user_id,language_kind,language_tag)` 与 `(user_id,language_kind,sort_order)`；CHECK种类、sort_order>=0、native时level为空且goals空、level允许值、goals为模块允许集合子集。服务校验数组去重/上限、目标语能力、母语/目标语各自支持状态。父锁内显式删除偏好行；不是学习事实清理入口。

### user_model_bindings

列组：U；以user_id关联user_extensions.user_id，随父settings_revision原子更新。

| 列 | PostgreSQL类型/NULL/默认 | 语义 |
| --- | --- | --- |
| capability | varchar(12) NN | text/vision/tts |
| credential_id | uuid NN | 本人ProviderCredential，不复制密文 |
| model_catalog_entry_id | uuid NN | 允许目录中的模型 |
| parameters_schema_version | integer NN DEFAULT 1 | 模型参数白名单版本 |
| parameters | jsonb NN DEFAULT '{}' | 有界采样/合成参数；空对象表示使用目录默认 |

唯一 `(user_id,capability)`；反向索引 `(user_id,credential_id)` 支持删除Key影响预览/解绑。服务验证凭据和模型provider匹配、能力启用；模型停用不删历史run，仅阻止新调用。选择/解绑以及会影响绑定的凭据撤销都按user_extensions→user_provider_credentials稳定ID顺序取锁；不能撤销先锁凭据再补锁扩展行。仅轮换/重加密且不改绑定的路径可只锁凭据，不能随后反向取得扩展行锁。活动run冻结model/settings版本，不追着表内指针变化。

### user_voice_bindings

列组：U；以user_id关联user_extensions.user_id，随父settings_revision原子更新。

| 列 | PostgreSQL类型/NULL/默认 | 语义 |
| --- | --- | --- |
| language_tag | varchar(35) NN | 所选语言 |
| speech_purpose | varchar(16) NN | general/word，普通朗读与收藏词发音各自默认 |
| voice_catalog_entry_id | uuid NULL | 个性声音 → voice_catalog_entries.id |
| global_voice_profile_id | uuid NULL | 标准词音 → global_voice_profiles.id，仅word用途可设 |

唯一 `(user_id,language_tag,speech_purpose)`；CHECK两种声音引用恰有一个非空，global profile仅word允许。服务验证个性声音对应tts绑定的模型、语种一致；标准词音引用[学习分册](database-learning.md)global_voice_profiles的当前已发布修订，新请求冻结其不可变版本，用户不能修改公共profile。标准profile与本人Key/provider不兼容时明确报配置问题。合成键包含实际profile/参数指纹，不能把voice ID单独当完整合成键；旧声音不再可用时保留已生成资产并提示重新选择，不静默换供应商/声音。

AvatarAsset不再单独建表；专用投影及不可变文件字段见[文件对象](database-materials.md#22-file_objects--服务端发布的不可变对象)。不同历史头像仍是一对多的file_objects，合并不只保留当前图，也不开放任意文件作为头像。

## 4. 凭据与认证安全（拟新增）

### user_provider_credentials

列组：U + R；scope_kind=user_owned；本人凭据服务/受控按用户运行的模型工厂可读必要密文，API只读安全掩码。

| 列 | PostgreSQL类型/NULL/默认 | 语义 |
| --- | --- | --- |
| provider | varchar(24) NN | 允许的gemini/openrouter代码 |
| display_label | varchar(100) NULL | 用户区分本人多把Key的标签 |
| encrypted_secret | bytea NULL | 版本化认证加密信封（含nonce/tag），撤销删除后为空 |
| encryption_key_version | varchar(64) NULL | 部署Keyring版本，和密文同时有/同时空 |
| credential_version | bigint NN DEFAULT 1 | 用户轮换/撤销代次 |
| state | varchar(16) NN | active/revoked；不把网络失败写成永久无效 |
| masked_hint | varchar(32) NULL | 严格裁剪的显示掩码，不足以恢复秘密 |
| revoked_at | timestamptz NULL | 撤销提交时间 |

CHECK版本正值、provider/state枚举、密文与主密钥版本成对、active有密文且无revoked_at、revoked有revoked_at。索引 `(user_id,state,created_at,id)` 本人列表；不对密文/掩码建唯一键，不假设每供应商仅一把Key。轮换/重加密共锁本行且比较R及credential_version；运维重加密只改密文/keyring版本与R，不能推进用户credential_version。撤销保留引用壳和审计，清密文/解绑选择，历史结果/调用事实保留。

显式Key能力测试复用[ai_runs](database-learning.md#72-ai_runs)的credential_test运行及安全结果字段，不再复制一张一对一测试摘要表。一次测试只选text/vision/tts中的一种；查询按本人credential_id/credential_version/精确provider与model_id/model_revision/capability取最近已结束的测试run，无记录为untested。迟到旧版本结论只作历史，不能认证新Key；用量仍以真实attempt为准，失败不将其他能力一并标无效。

### user_auth_sessions

列组：U；scope_kind=user_owned；允许本人安全、认证与有权管理会话服务；不是一般资料读取。

| 列 | PostgreSQL类型/NULL/默认 | 语义 |
| --- | --- | --- |
| audience | varchar(10) NN | client/admin，由路由决定 |
| transport | varchar(8) NN | web/native，由受控入口验证 |
| absolute_expires_at | timestamptz NN | 持久绝对期限，不随idle续期延长 |
| revoked_at | timestamptz NULL | 持久撤销提交时间 |
| revoke_reason_code | varchar(64) NULL | 安全原因类别 |
| security_epoch | bigint NN | 创建时users全局epoch |
| audience_security_epoch | bigint NN | 创建时对应client/admin epoch |
| reauthenticated_at | timestamptz NULL | 最近身份重验；Web重验换新session ID |
| device_summary | varchar(200) NULL | 安全裁剪设备摘要，非可信身份 |
| platform | varchar(16) NN | web/windows/android；服务校验允许组合 |
| last_seen_at | timestamptz NULL | 有节制持久化的安全页活动时间，不等于idle存续依据 |

id映射API session_id/session_ref；不另存重复UUID列。CHECK受众/传输/平台枚举、epochs>=0、absolute_expires_at>created_at；admin仅web组合。索引 `(user_id,audience,created_at,id)` 本人列表；`(user_id,audience,id) WHERE revoked_at IS NULL` 撤销某端；`(absolute_expires_at,id)` 留存清理。认证按id取PG会话/用户并比较两层epoch、状态、期限，同时验证Redis存续；不存在Redis材料即重新登录。本人/管理员撤销共锁User→Session，持久撤销+安全审计+Outbox提交后清Redis。到期/撤销后按安全留存清理，不清用户学习事实。

### user_auth_challenges

列组：U；scope_kind=identity，user_id绑定挑战目标身份；仅受限认证流程访问，无匿名查账号接口。

| 列 | PostgreSQL类型/NULL/默认 | 语义 |
| --- | --- | --- |
| purpose | varchar(24) NN | email_verify/password_recovery/activation/reauth；只启用已交付用途 |
| audience | varchar(10) NN | client/admin，不能跨受众消费 |
| token_digest | bytea NN | 高熵挑战的服务端HMAC摘要，不存原Token |
| digest_key_version | varchar(64) NN | 摘要密钥版本，支持受控轮换 |
| security_epoch | bigint NN | 签发时全局安全epoch |
| password_version | bigint NN | 签发时密码版本，防旧重置挑战覆盖新密码 |
| target_email_digest | bytea NULL | 邮箱验证/恢复绑定的规范邮箱摘要，不作日志字段 |
| expires_at | timestamptz NN | 一次性挑战期限 |
| consumed_at | timestamptz NULL | 单次成功消费 |
| revoked_at | timestamptz NULL | 主动废弃/签发策略替代 |
| failed_attempts | integer NN DEFAULT 0 | 已验证挑战上的受限失败计数 |

唯一 `(digest_key_version,token_digest)`；CHECK摘要octet_length=32、版本/计数合法、期限晚于created_at、消费与撤销不可同时非空；索引 `(user_id,purpose,created_at,id)` 和 `(expires_at,id)`。未知账号请求仍通用受理，不为未知邮箱制造假用户/挑战。消费锁User→Challenge并核对目的/受众/期限/版本，密码替换推进password_version与epoch、撤销两端会话并写安全事件；邮件发送/受理不是消费成功。未选恢复交付方式不开放其端点，期限后受控清理摘要。

安全事件使用扩展后的admin_audit_events承载受控身份事件（actor_user_id允许匿名为空，actor为注册安全主体），而非建立有私有内容的通用日志表；登录拒绝等无业务事务事件使用独立受控追加入口。R、摘要和epoch均不返回普通资料DTO。

### user_auth_challenge_deliveries

条件表：仅在邮件模式获选并交付时建立。列组U+R；scope_kind=identity，限定通知Worker读取短期密文；管理/用户接口只返回安全受理状态。

`challenge_id uuid NN → user_auth_challenges.id`；`encrypted_payload bytea NULL`；`encryption_key_version varchar(64) NULL`；`payload_schema_version integer NN DEFAULT 1`；`expires_at timestamptz NN`；`status varchar(16) NN`（pending/sent/failed/expired）；`attempt_count integer NN DEFAULT 0`；`next_attempt_at timestamptz NULL`；`last_error_code varchar(64) NULL`。

唯一 `(user_id,challenge_id)`；CHECK密文/keyring版本成对、正schema版本、非负次数、状态允许值；pending必须有密文。服务校验不晚于挑战期限，sent仅表示交付适配器已受理，不保证收件人收到。索引 `(status,next_attempt_at,id) WHERE status='pending'` 扫待发；`(expires_at,id)` 清密文。密文只包含发送所必需的地址/链接，Kafka/Outbox仅放本记录引用；只限本用途的Worker解密，不能进入日志。锁User→Challenge→Delivery，消费或失效后不再发送；已发/过期按短期保留策略清密文，不能为了重试永久保留原Token。此表存在不代表恢复邮件能力已选定或可用。

## 5. 完整授权与导航关系（拟新增）

本节均为 `scope_kind=system_catalog`，无owner/user伪通配列；只允许发布注册、限定管理授权服务读写。所有关系新增/移除先锁authorization_revisions.global，再按稳定ID顺序锁相关User/Role/Menu等父行；同事务推进全局/用户版本、审计及Outbox。删除为限制删除或显式解除/迁移，不能配置ORM级联。

### role_inheritance_links

列组：B；`child_role_id uuid NN → roles.id`，`parent_role_id uuid NN → roles.id`。唯一 `(child_role_id,parent_role_id)`；CHECK两者不同；反向索引 `(parent_role_id,child_role_id)` 支持上游改变的影响集合。子角色继承父角色；无环、深度和受保护边界在同一授权事务校验，单行CHECK不能证明无环。移除deny路径、停用父角色也做有效权限差异/授予边界复核。

### role_grant_boundaries

列组：B + R。将授权上限表示为有限关系行，不接受任意SQL/任意目标用户条件。

| 列 | PostgreSQL类型/NULL/默认 | 语义 |
| --- | --- | --- |
| grantor_role_id | uuid NN | 操作者当前有效角色 → roles.id |
| boundary_kind | varchar(32) NN | assign_role/assign_permission/manage_account_role/manage_unassigned_accounts |
| target_role_id | uuid NULL | assign_role可授角色；manage_account_role可管理该角色的成员账号 |
| permission_code | varchar(100) NULL | assign_permission可配置的权限 → permission_catalog.code |
| data_scope | varchar(24) NULL | assign_permission时允许的self/platform_metadata |

CHECK分支完整：role类必须target_role_id有值且权限两列空；permission类必须权限两列有值且target_role_id空；unassigned类三列全空。部分唯一分别为 `(grantor_role_id,boundary_kind,target_role_id)` WHERE target_role_id IS NOT NULL、`(grantor_role_id,boundary_kind,permission_code,data_scope)` WHERE permission_code IS NOT NULL、`(grantor_role_id,boundary_kind)` WHERE boundary_kind='manage_unassigned_accounts'；反向 `(target_role_id,grantor_role_id)` 支持删除/影响预览。

这是上限数据的推荐物理表达，不产生新动作权限：仍需相应assign/update权限，受保护目标另需protected_role.manage。账号目标若带多个角色，必须覆盖其完整有效角色集合；有未知/未覆盖角色拒绝，不能因其中一个普通角色匹配就管理高权账号。unassigned仅无角色pending账号的限定管理。操作者自身/已持有角色/继承/默认注册角色引发的升权仍由[授权协议](authorization.md)统一拒绝；表中没有allow_self_escalation开关。

### permission_dependency_links

列组：B；`permission_code varchar(100) NN → permission_catalog.code`；`required_permission_code varchar(100) NN → permission_catalog.code`。唯一 `(permission_code,required_permission_code)`；CHECK不同；反向 `(required_permission_code,permission_code)` 支持权限停用影响预览。仅发布可更新的静态必要依赖；运行时来源、题目状态或复合请求权限不能缩减成这张表的静态闭包。引用端点/能力尚未实现不自动取得授权。

### menu_permission_links

列组：B；`menu_id uuid NN → menus.id`；`permission_code varchar(100) NN → permission_catalog.code`。唯一 `(menu_id,permission_code)`；反向 `(permission_code,menu_id)`。父menus.permission_match定义all/any，仅附加显示限制；迁移将B0menus.permission_code逐条搬入本表并校验条数，再移除旧列。菜单修改按父revision及全局policy_revision提交；不降低代码注册的路由最低权限。空分组可无附加权限，页面仍强制最低要求。

## 6. 发布能力、技术上限与功能配置（拟新增）

目录只保存已允许的能力事实/验证摘要，不引入供应商代理URL、公共Key、套餐、余额或金额。目录版本变化必须审计；影响权限的变更推进全局policy_revision；个人模型测试结论不等于全实例能力保证。所有目录表为 `scope_kind=system_catalog`、列组B+R；可见DTO由已登录client安全能力接口裁剪，写入由发布/有权管理服务完成。

### model_catalog_entries

| 列 | PostgreSQL类型/NULL/默认 | 语义 |
| --- | --- | --- |
| provider | varchar(24) NN | gemini/openrouter |
| model_code | varchar(200) NN | 供应商准确模型标识，不把别名解析成永久能力 |
| display_name | varchar(100) NN | 安全显示名 |
| enabled | boolean NN DEFAULT false | 是否可用于新运行 |
| supports_text / supports_vision | boolean NN DEFAULT false / boolean NN DEFAULT false | 已登记文本/图片能力 |
| supports_tools / supports_structured_output | boolean NN DEFAULT false / boolean NN DEFAULT false | 工具/结构化输出能力 |
| supports_tts | boolean NN DEFAULT false | TTS独立能力，不由text推断 |
| tts_adapter_id / tts_adapter_version | varchar(128) NULL / varchar(64) NULL | TTS时必须齐全，指向受发布注册的精确模型/API契约；未知适配不能启用新合成 |
| tts_contract_schema_version / tts_contract | integer NULL / jsonb NULL | TTS时正版本+有限能力对象，含API家族/声音与输入输出限制；定义见[适配器](tts-adapters.md)，不可含凭据、代码或任意HTTP模板 |
| verified_at | timestamptz NULL | 受控能力验证时间 |
| verification_code | varchar(64) NULL | 验证证据的安全引用代码 |
| parameters_schema_version | integer NN DEFAULT 1 | 允许参数结构版本 |
| parameter_constraints | jsonb NN DEFAULT '{}' | 有界参数名/类型/范围、支持输出格式；无Prompt/秘密 |

唯一 `(provider,model_code)`；CHECKprovider允许值、正schema版本、JSON对象；supports_tts为true时四个tts契约列齐全且版本正，false时均空。适配登记只保留当前发布引用，历史run/音频冻结自身展开规格，不另建适配器历史表。目录规模有界，按唯一键/PK取模型；先不为各布尔能力单列建索引。启停锁本模型与全局策略根，已引用条目保留；不硬删导致历史run丢模型含义。

### voice_catalog_entries

| 列 | PostgreSQL类型/NULL/默认 | 语义 |
| --- | --- | --- |
| model_catalog_entry_id | uuid NN | 支持tts的模型目录根 |
| voice_code | varchar(128) NN | 供应商声音标识 |
| language_tag | varchar(35) NN | 本行适用语言 |
| display_name | varchar(100) NN | 显示名，不把原型示例当真实声音 |
| enabled | boolean NN DEFAULT false | 新合成是否可选 |
| verified_at | timestamptz NULL | 当前组合验证时间 |
| verification_code | varchar(64) NULL | 安全验证证据引用 |

唯一 `(model_catalog_entry_id,voice_code,language_tag)`；服务验证模型provider/TTS/语种一致；按模型唯一前缀读取可选声音。模型/声音调整锁模型目录根，保留被旧音频引用的条目；可读已有音频不要求当前仍能新合成。

### language_capabilities

| 列 | PostgreSQL类型/NULL/默认 | 语义 |
| --- | --- | --- |
| language_tag | varchar(35) NN | 规范BCP-47标签 |
| display_name | varchar(100) NN | 发布显示名 |
| ui_supported | boolean NN DEFAULT false | 是否可选UI语言，P0仅zh-Hans |
| learning_supported | boolean NN DEFAULT false | 是否可选学习语言，P0英语/日语 |
| explanation_supported | boolean NN DEFAULT false | 可选解释语言 |
| native_supported | boolean NN DEFAULT false | 可选母语标签；不代表可学习/解释 |
| enabled | boolean NN DEFAULT false | 新设置选择是否开放 |

唯一 `(language_tag)`；服务按发布目录校验规范化/能力，不能任填标签。已记录的语言历史不随目录停用删除，读取旧事实继续保留原标签；保存新偏好只允许已发布能力。目录有界，通过唯一键/小全集读取，不添加无需求GIN索引。

### feature_flags

`code varchar(100) NN`（发布注册唯一）；`enabled boolean NN DEFAULT false`；`description varchar(200) NULL`。唯一 `(code)`。仅已有功能安全开关，不让管理界面创造任意可执行代码。更新共锁全局策略根、推进policy_revision，后端执行和UI快照同时取其当前状态；不能用此开关绕过permission检查。停止功能保留业务数据。

### runtime_limit_policies

`scope_kind=system_catalog`，列组B+R。

| 列 | PostgreSQL类型/NULL/默认 | 语义 |
| --- | --- | --- |
| limit_code | varchar(64) NN | 发布注册技术维度，如并发、调用次数、字节容量 |
| subject_kind | varchar(24) NN | user_default/instance/global_word |
| value_limit | bigint NN | 限值；0表示该新增动作不允许，NULL不表示无限 |
| window_seconds | integer NULL | 次数窗口；容量/并发为空 |
| enabled | boolean NN DEFAULT true | 该已注册配置是否启用；关闭仍受部署硬限制 |

唯一 `(subject_kind,limit_code)`；CHECK subject允许值、value_limit>=0、window为NULL或>0。维度单位/是否窗口由发布注册表决定，必须与limit_code匹配；有效值不得高于部署硬上限。降低上限只影响后续新增，不删已有数据/已提交attempt。全局词音容量在global_word维度单列，不计成贡献者永久个人用量。

### user_runtime_limits

`scope_kind=user_owned`，列组U+R；允许入口为有权技术上限管理服务，本人仅获得裁剪后的有效限制摘要。

`limit_code varchar(64) NN`；`value_limit bigint NN`；`window_seconds integer NULL`。唯一 `(user_id,limit_code)`；CHECK非负/窗口正值，服务验证同一发布维度和部署硬上限。覆盖缺失则使用user_default，取个人/实例/部署共同允许结果；无交易、购买、金额或reset_balance字段。更新共锁User与配置根并审计，删除覆盖仅恢复默认，不重置事实计数。

### user_storage_states

`scope_kind=user_owned`，列组U+R；只允许容量服务按本人授权动作预留/结算，管理仅看聚合。`used_bytes bigint NN DEFAULT 0`；`reserved_bytes bigint NN DEFAULT 0`。唯一 `(user_id)`，两列CHECK非负。注册时可延迟幂等创建，首次创建先锁User避免双根。

已发布且仍保留的本人file_objects实际字节及纳入容量的结构化结果规范编码字节计入used，同一对象/结果只计一次；staging上传、重编码或生成结果落盘前的承诺容量计入reserved。上传意图/新任务受理必须在同一PG事务锁本行检查 used+reserved+本次需求与当前有效技术上限，写预留事实后增加reserved；不能把两个普通查询或Redis INCR当容量授权。实际字节发布时以不可变对象摘要/大小结算，余量释放；失败/取消必须证明无在途写入再释放。统计校正由受控维护按对象与预留账本复核，不能日常直接覆盖计数。

### global_storage_states

`scope_kind=system_operation`，列组B+R；`catalog_code varchar(32) NN`（CHECK='global_word'，唯一）；`used_bytes bigint NN DEFAULT 0`；`reserved_bytes bigint NN DEFAULT 0`，非负。只由全局词音目录生成/GC服务维护，不受普通用户元数据查询读取。global_word成品计实例共享容量，私有生产Job/个人Key/供应商用量仍属原用户；不得用owner=NULL把本表作为所有私人缓存的总入口。预留与结算锁本行，与个人容量根使用固定顺序；GC删除字节成功并提交资产清理状态后才能扣减used。

### user_storage_reservations

`scope_kind=user_owned`，列组U+R；私有上传/生成/受控清理容量服务可读写，普通API只返回安全可用/不足结果。

| 列 | PostgreSQL类型/NULL/默认 | 语义 |
| --- | --- | --- |
| request_kind | varchar(16) NN | upload_intent/job；登记的容量消费方类型 |
| request_id | uuid NN | 同用户upload_intents.id或jobs.id |
| purpose | varchar(32) NN | 已注册容量用途，见下方允许清单 |
| job_id | uuid NULL | 受理后关联本人jobs.id；上传前可空，不是预留必填前提 |
| operation_id | uuid NN | 受理动作关联，不携带秘密 |
| reserved_bytes | bigint NN | 本次承诺的计量字节上限 |
| settled_bytes | bigint NN DEFAULT 0 | 已发布文件/规范结果的结算字节数 |
| status | varchar(16) NN | reserved/committed/released/unknown |
| expires_at | timestamptz NULL | 应核对在途状态的期限，不代表可以直接释放 |
| settled_at | timestamptz NULL | 结算或已证实无写入的释放时间 |

唯一 `(user_id,request_kind,request_id,purpose)`；CHECK request/status枚举、reserved_bytes>0、0<=settled_bytes<=reserved_bytes、终态要求settled_at、released时settled_bytes=0；索引 `(user_id,status,id)` 本人占用核对、`(status,expires_at,id) WHERE status IN ('reserved','unknown')` 受控恢复扫描。purpose允许material_upload/avatar_image/query_image/vocabulary_csv/photo_words/listening_script/ai_output/private_tts，由入口固定；CSV/照片来源复用同一upload_intent预留，不另为同一原始字节建第二份占用。request_kind=job时request_id与job_id须相同；其他用途可在受理后绑定Job且不新增预留。关联父可与预留在同一受理事务内共同创建，ID由服务端分配；事务提交后必须双向可查且归属匹配，不能提交孤立预留。

在身份锁后先锁user_storage_states根，再按[总册锁序](database-design.md)锁预留行、业务父，计数与预留状态同事务提交。upload_intents.storage_reservation_id指向本表，Job生成输出按阶段引用相应预留；合法重试查同一唯一键，不重复增加reserved。最终多个文件实际字节按此预留汇总结算一次，若输出上界不足须在写入/调用前扩容并再次校验限额。committed的结算不再释放used；后来删除对象/结构化产物只由file/asset/artifact GC的幂等删除事务按实际字节扣减used。unknown和过期预留必须先核对供应商attempt、对象/上传状态及有效租约，无结果证明不能退占用。

### global_storage_reservations

`scope_kind=system_operation`，列组B+R；仅global_word生成/确定性转码/结算服务，客户端/等候者不可读取生产者关联。合成与转码在本表内以受控分支区分，不增加容量表。

| 列 | PostgreSQL类型/NULL/默认 | 语义 |
| --- | --- | --- |
| catalog_code | varchar(32) NN | 固定global_word，关联global_storage_states.catalog_code |
| reservation_kind | varchar(16) NN DEFAULT 'synthesis' | synthesis/transcode；服务固定，不接受客户端任意指定 |
| producer_user_id | uuid NULL | synthesis必有的实际生产者users.id；transcode必须空 |
| producer_job_id | uuid NULL | synthesis必有的实际私有jobs.id；transcode必须空，不借用贡献者Job |
| source_audio_id | uuid NULL | transcode必有的global_word_audios合成根，synthesis为空 |
| derivation_key_digest | bytea NULL | transcode必有的32字节派生身份，synthesis为空 |
| transcode_spec | jsonb NULL | transcode必有的冻结源摘要、transcode_version、output_spec及schema；synthesis为空 |
| transcode_fence | bigint NULL | transcode必有，初值0，每次领取/接管/撤销递增；synthesis为空 |
| transcode_lease_owner, transcode_lease_expires_at | varchar(128) NULL / timestamptz NULL | 转码执行租约，两列同空同有；非transcode为空 |
| output_bucket, object_layout_version | varchar(63) NULL / varchar(64) NULL | transcode受理时冻结的受控Bucket及对象键规则版本，synthesis为空；不接受客户端对象路径 |
| output_candidate | jsonb NULL | 转码阶段有界版本化候选：fence、对象键/版本、摘要、长度、格式/采样/时长及校验版本；仅完整校验后保存，不含音频字节 |
| reservation_stage | varchar(64) NN | 受控输出阶段 |
| operation_id | uuid NN | 实际生产动作 |
| reserved_bytes | bigint NN | 共享成品承诺的字节上限 |
| settled_bytes | bigint NN DEFAULT 0 | 共享成品实际结算字节 |
| status | varchar(16) NN | reserved/committed/released/unknown |
| expires_at | timestamptz NULL | 核对期限，不是自动释放授权 |
| settled_at | timestamptz NULL | 结算/释放时间 |

部分唯一 `(catalog_code,producer_job_id,reservation_stage) WHERE reservation_kind='synthesis'`；转码活动部分唯一 `(catalog_code,source_audio_id,derivation_key_digest) WHERE reservation_kind='transcode' AND status IN ('reserved','unknown')`。CHECK分支字段全有/全空、catalog固定值、派生摘要32字节且spec对象、状态/字节/终态约束与私有预留相同；索引 `(status,expires_at,id) WHERE status IN ('reserved','unknown')`及`(source_audio_id) WHERE source_audio_id IS NOT NULL`。synthesis归属只核对producer_user_id与Job/有效目录生成slot一致，不能借此读取正文/Key。transcode只读取已发布公共根及白名单本地转码spec，不持有个人Key、不创建供应商attempt；请求受理先校验当前本人来源与speech.play，后台恢复仅执行该冻结公共输入的确定性处理。

按身份→global_storage_states→必要的user_storage_states→预留行→实际需要的本人来源/目录父槽/根audio的固定顺序受理、发布和GC；同类多根按稳定ID排序。转码首个请求在容量根锁内查重、复核根ready并建立预留，其余请求复用；转码在锁外执行。派生发布事务要求确切预留仍reserved、spec/源摘要未变、根可用，插入派生唯一行并按实际对象字节结算；同一结果重投不重复计量，已released或旧预留的迟到写入只能清理临时对象。崩溃后的reserved/unknown按已发布派生行、预留及受控对象核对恢复，不依赖私人生产Job；证明无在途发布后才可释放，之后显式重试可建新预留。存在派生对象时先读取或恢复发布，不新建重复成品。synthesis的slot/fence仍须匹配；两分支都不能仅按TTL退占用。公共根及各派生分别计实际字节，不向每个播放者重复收容量。

转码执行领取与恢复也使用上述锁序。CHECK transcode_fence>=0，lease两列同空同有，仅transcode的reserved/unknown可有lease，终态lease清空；synthesis的执行/对象字段全空。工作者领取时锁预留，核对无有效lease并推进fence，保存owner/到期时间；续租、保存候选及最终发布必须匹配确切owner/fence和有效lease，超时本身不授予发布。取消/释放先推进fence使旧执行失效；接管只能由受控确定性媒体服务执行，不获得任何模型调用能力。

object_layout_version注册输出键规则：每次执行使用`global-word/transcode/<reservation_id>/<fence>/output`独占对象键，Bucket由output_bucket确定，输出协议和前缀由服务固定；每次写入使用不可覆盖/条件创建，旧fence不能覆盖新执行对象。已写成但尚未写PG的对象可按持久reservation_id及已分配fence定位，恢复必须检查完整长度/摘要/实际解码及冻结spec，不能仅凭HEAD存在判ready。对象只经目录PG成品引用提供读取，候选键没有公共直读授权。完整校验后在有效lease下保存output_candidate；最终发布从同一候选创建derived行并结算，事务失败保留候选与对象以恢复。

恢复先查派生成品唯一键及已提交预留；未发布时在接管新fence后核对已记录候选或旧fence确定路径，只对完整已封存对象复制到当前fence的不可变键并重新校验，再发布。无法证明完整的残留隔离并仅重做确定性转码，不重调TTS。同一预留全部在途/残留候选字节受reserved_bytes上界约束，接管前清理并确认旧写入结束，或先按容量根扩容，不能按每个fence重复使用一份容量无界落盘。释放必须撤销旧租约写入能力、确认无有效写入/发布并处理候选；无法确认保持unknown。已失效执行者不能发布、续租或释放新占用，只能经受控清理处理自身fence对象；GC依据预留ID/fence检查在途与保留，不按对象年龄直接删除候选。

## 7. 实施顺序与验收落点

1. users的密码/全局安全版本已在0002补齐；随后实施AuthSession及所选身份流程，用A/B、client/admin、Web/native验证持久撤销和Redis材料丢失。既有B0账号回填不能伪造验证邮箱/登录记录。
2. 注册事务增加一个user_extensions空行，后续实现本人资料与头像；三个字段组独立revision，头像用途/文件引用与GC共用扩展行锁。B0旧用户扩展行缺失的回填必须可重复且不覆盖已有资料；不创建旧三单例再迁移合并。
3. 完整RBAC增加继承、授予边界与菜单多权限，消费0002已存在的授权范围列；旧单权限菜单确定性迁移。所有授权变更仍使用同一global父行，审核最后管理员和显式deny导致的间接扩权。
4. 模型目录、个人Key、设置绑定和用量查询按对应功能切片落地；目录启用不代表已验证供应商能力，真实测试遵循已有授权。主密钥重加密与用户轮换并发必须验证。
5. 上传/生成正式接入前，完成容量根与预留结算的PG原子路径。目录共享字节只算一次；各用户attempt用量分别记录。后台技术上限修改不自动删除学习成果。

这些是表依赖次序，不扩大B1/B2已承诺交付范围；所属里程碑与完成标记由[路线图](../delivery/roadmap.md)和[脚手架里程碑](../delivery/milestones/scaffold.md)维护。

实施检查落到[账号ACC](../modules/accounts.md)、[资料PROFILE/设置SET](../modules/settings.md)、[授权/RBAC](authorization.md)与[管理ADM](../modules/admin.md)：注册失败无半成品；当前密码校验与并发改密版本一致；新请求不使用旧授权；个人Key/头像/挑战不可跨用户或用途；角色/菜单/策略变更原子审计；PG/Redis失效关闭；容量并发不超领；日志无秘密/人口资料/私有正文。性能索引在目标PG与合成样本上按实际查询验证；本次文档设计没有运行这些应用测试。

待锁定项：注册/验证/恢复交付方式及挑战期限、头像硬上限/重编码规格、具体模型/声音/标准profile与验证证据、技术限额数值和安全留存时间。对应待决入口仍为[OPEN清单](../decisions/pending.md)；设计表支持这些边界，不提前选择供应商默认值或开放未选能力。
