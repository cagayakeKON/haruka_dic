# 数据库设计与建表规范

状态：2026-09-22，B0已建立12张账号/授权初始化基础表、UTC公共Mixin、受控迁移与字典检查器，局部证据见 [数据库切片](../delivery/reviews/2026-09-22-b0-identity.md)。不使用数据库外键；后续业务表仍按本文实施，未实现的隔离/删除/任务验收不计为通过。

本文维护物理结构、公共字段、无外键关联、隔离与数据库变更规则。具体表结构与Redis键设计见[数据库设计书](../architecture/database-design.md)，其新增结构尚未实施。业务聚合/事务/任务状态以 [数据与任务](../architecture/data-jobs.md) 为准，身份和授权分别以 [认证](../architecture/authentication.md)、[RBAC](../architecture/authorization.md) 为准；操作流程见 [部署与恢复](../operations/deployment-recovery.md)，测试执行频率以根 [AGENTS.md](../../AGENTS.md) 为准。

## 1. 总体边界

- PostgreSQL为服务端业务事实库。Haruka使用独立数据库、凭据、迁移历史；即使共用MyHome的PG实例也不跨库关联其业务表。
- 首版采用同一数据库、同一业务schema中的共享表，按用户/私有资料库隔离；不为每个用户建库或schema，不引入组织tenant模型。首版业务schema为Haruka数据库中的public，连接search_path固定、运行账号无CREATE/DDL权限。
- **不建立物理外键**：ORM不声明ForeignKey/ForeignKeyConstraint，迁移不创建REFERENCES/FOREIGN KEY，不靠数据库级联删除/更新。逻辑关联字段、关联校验、索引和数据字典仍必须存在。
- 数据库保留PRIMARY KEY、UNIQUE、NOT NULL和单行CHECK；跨表存在性/归属/版本/状态由受控服务事务维护，不能声称普通UUID列能自动防止跨用户引用。
- 首版隔离基线是强制ScopeContext、专用管理/维护入口及受限数据库账号，不启用RLS。若后续增加RLS，须另行设计连接池上下文、策略和绕过控制；不将尚未启用的RLS计作隔离证据。
- Flutter的Drift是缓存，不是第二套服务端事实来源；缓存同样不声明物理外键，字段/缓存版本遵循适配映射，不能用SQLite测试替代PG行为。

## 2. MyHome依据与采用范围

本机参考为 [TimestampMixin](../../../MyHome/backend/app/models/mixins.py)、[DeclarativeBase](../../../MyHome/backend/app/models/base.py) 与 [后端说明](../../../MyHome/backend/README.md)。这几个链接依赖相邻源码，不是Haruka运行时依赖。

MyHome的TimestampMixin定义created_at/updated_at，二者server_default=func.now()，updated_at另有onupdate=func.now()。Haruka沿用该职责划分，并明确DateTime(timezone=True)映射timestamptz，保持本项目已有UTC契约；不复制MyHome默认DateTime/naive UTC的实现差异。MyHome部分Mixin实际声明外键，不能将本次Haruka禁用外键说成MyHome全库的既有事实。

SQLAlchemy的onupdate由其生成DML时应用，并不是数据库触发器；默认值也不能覆盖显式传入的值。Haruka因此另规定原生SQL、批量更新及upsert路径，见第5节。[SQLAlchemy默认值说明](https://docs.sqlalchemy.org/en/20/core/defaults.html)

## 3. 命名、主键与关联列

| 对象 | 统一规则 | 示例 |
| --- | --- | --- |
| 表 | 小写snake_case、复数；不加tbl/t_；不用保留字或依赖双引号的大小写 | users、materials、exam_sessions |
| 关联表 | 按业务方向命名；独立行ID和业务组合唯一约束并存 | collection_tags、user_roles |
| 字段 | 小写snake_case；名称表达含义与单位，不使用含混的type/value/data | owner_user_id、duration_ms、size_bytes |
| 时间/日期 | 时间点后缀_at，纯日期后缀_date；截止时间统一沿已发布业务契约 | created_at、expires_at、deadline |
| 主键 | 业务实体默认id UUID，由后端使用标准uuid4生成；无需另建自增号 | 客户端/模型/CSV的ID不直接决定新对象ID |
| 逻辑关联 | <资源单数>_id，PG原生UUID；与目标列类型一致，无物理外键 | material_id、collection_id |
| 约束 | pk_<table>、uq_<table>_<columns>、ck_<table>_<meaning> | ck_exam_items_score_nonnegative |
| 索引 | ix_<table>_<columns>；部分/表达式索引使用稳定业务后缀 | ix_materials_owner_library_active_order |

业务唯一性由单独UNIQUE/唯一索引表达，UUID不能代替业务去重。既有API中的session_id等语义名称可映射到物理id，但在字典登记，不能暗改接口。固定权限代码、受控幂等键等自然标识是否作主键须逐表说明，不强行给Alembic内部版本表加业务ID。

Base统一使用MetaData.naming_convention。命名模板包含全部组合列，CHECK显式给语义名称；无fk模板。控制标识符为ASCII、最多63字节，长名由统一工具确定性缩短并检查碰撞，不能由各迁移作者随意截断。名称改变也是需要审查的schema差异。[SQLAlchemy命名约定](https://docs.sqlalchemy.org/en/20/core/constraints.html#configuring-constraint-naming-conventions)

## 4. 字段类型、空值与公共字段

| 字段/用途 | 数据库与Python规则 |
| --- | --- |
| id、逻辑关联ID | UUID / uuid.UUID，不存varchar UUID或逗号分隔ID串 |
| created_at、updated_at | TIMESTAMPTZ NOT NULL，server_default=now()；更新规则见第5节 |
| owner_user_id / user_id | UUID；私有记录必需；同一表只有一个权威所有者列，具体名称见第6节 |
| library_id | 库内业务表UUID NOT NULL；Library根表自身id即库ID，不重复存自引用列 |
| revision | 可变且需并发保护的实体用BIGINT NOT NULL DEFAULT 1及CHECK(revision >= 1)；原子递增 |
| generation / epoch | 业务代次用BIGINT、明确初值与非负约束；不可互换或用更新时间替代 |
| 分数/精确数值 | NUMERIC(p,s) / Decimal；每字段显式p/s及上下界，写入前拒绝NaN/Infinity和未经契约允许的超精度值，评分沿现有十进制字符串/舍入协议；不依赖PG存储时舍入替代输入验证 |
| 计数、字节、时长 | INTEGER/BIGINT，明确单位、上界/非负约束；不能用浮点存计数 |
| 布尔 | BOOLEAN；未知状态确有业务意义才允许NULL，不能用0/1/-1混合表达流程 |
| 状态/语言/短代码 | 有长度界限的VARCHAR与允许值/形状校验；首版状态优先文本+命名CHECK，避免无必要的PG原生ENUM升级耦合 |
| 正文/笔记 | TEXT，应用层限制请求/业务长度；不靠任意VARCHAR(255)截断用户材料 |
| JSONB | 仅版本化可变卡片/题型载荷、有限设置；有schema_version、大小和结构校验，不能代替所有者/状态/关联/唯一键列 |
| 密文/摘要 | 类型和长度匹配实际加密/摘要编码；只存密文、摘要或受控引用，禁止数据库注释/样本含真实秘密 |
| deleted_at | 仅需要软删除的表添加，可空timestamptz；禁止给所有表机械加入软删除Mixin |

公共时间字段适用于业务实体、关联表、目录表、任务和审计表；Alembic内部表、纯数据库视图不属于业务表，在检查器清单显式区分。append-only记录仍保留两个时间字段，创建后不修改，updated_at保持初始值；不能据此允许修改审计事件。

新增列必须明确nullable，不用空字符串、零UUID、-1或空JSON表示不存在。NOT NULL不自动获得业务默认值；只有明确中性初值才定义server_default，关键状态/归属不得由默认值猜测。可选复合引用必须全空或全有，可用单行CHECK保证；存在性仍由服务检查。

字符串规范化与显示值分开，例如email_normalized、lemma；禁止为了唯一性改写原文。JSON更新使用完整替换或经过验证的变更跟踪，不依赖普通dict原地修改必然被ORM检测。数据库CHECK不能用查询其他表的函数模拟外键；约束只维护本行确定规则。[PostgreSQL约束](https://www.postgresql.org/docs/current/ddl-constraints.html)

## 5. 创建和更新时间

1. created_at表示本行首次持久化的时间；updated_at表示本行最近一次实际UPDATE的数据库时间。新建时二者都由同一事务的数据库now()初始化，不接受普通客户端赋值。
2. 公共TimestampMixin使用DateTime(timezone=True)、nullable=False、server_default=func.now()；updated_at另设onupdate=func.now()。数据库连接时区统一UTC；API返回带Z的ISO 8601，展示再转用户时区。
3. 常规ORM更新使用Mixin；Core批量UPDATE、原生SQL、Worker阶段写入、数据修复及upsert的DO UPDATE分支必须显式设置updated_at=数据库now()，不能假定所有路径都会应用onupdate。created_at在冲突更新时保留原值。应用不得直接采用客户端时间覆盖这两列。[SQLAlchemy upsert的SET规则](https://docs.sqlalchemy.org/en/20/dialects/postgresql.html#the-set-clause)
4. 无实际业务变化的幂等重放返回原结果，不为表示“访问过”强制UPDATE。确需维护最后访问时间使用独立last_seen_at；有状态/租约写入时updated_at可变化，但不等于用户编辑时间。
5. now()取事务起始时间，不是提交时间或全局单调序号；同事务多次更新可能同值，等待锁也可能影响时序。并发控制用revision/业务代次，游标加稳定id；不设置updated_at严格递增或updated_at >= created_at的通用CHECK。[PostgreSQL当前时间](https://www.postgresql.org/docs/current/functions-datetime.html#FUNCTIONS-DATETIME-CURRENT)
6. 单词CSV历史时间按 [CSV时间映射](../contracts/vocabulary-csv.md#时间字段与数据库映射) 保存为source_created_at/source_updated_at，不覆盖本行公共时间；CSV导出字段与物理列的含义不能混用。受控整库灾备还原可保留原值，规则与用户CSV导入分开；数据迁移回填须记录取值依据，不把不明时间伪装成真实创建时间。
7. 首版不安装通用更新时间触发器，也不把server_onupdate标记当成触发器DDL。任何后续改用触发器的设计必须同步ORM、原生SQL、迁移与测试，不能同时维护互相覆盖的两套规则。

## 6. 数据隔离方案

### 表的作用域分类

| scope_kind | 适用对象 | 必需约束 |
| --- | --- | --- |
| identity | users、身份挑战等 | 仅认证/本人安全/明确授权的管理服务访问；登录前邮箱检索是受限认证动作，不是通用无scope查询 |
| user_owned | 个人Key、设置、设备会话 | 权威所有者列NOT NULL；现有领域称user_id时保留该列，并在字典映射到ScopeContext.user_id，不再复制owner_user_id |
| library_root | libraries | id为library_id，owner_user_id NOT NULL且唯一；首版每用户一个私有库 |
| library_owned | 材料、内容子表、收藏、考试/作答、私有关联表等 | owner_user_id与library_id均NOT NULL，服务检查库属于该用户，双方列不可事后转移 |
| system_catalog | 权限、角色/菜单定义、注册策略、标准词音目录等 | 独立服务和明确入口；global_word仅按[缓存协议](../architecture/learning-cache.md#51-收藏库标准单词发音的全局缓存)供获权用户复用/受控Worker填充，不伪造owner=NULL为用户查询通配符 |
| system_operation | 运维审计、固定职责维护记录 | 固定操作范围与最小DTO，不提供“任意用户”开关；私有Job仍有不可变所有者 |

每个业务表必须登记scope_kind、权威归属列、允许入口和生命周期；漏登记阻断建表。新增库内子表显式带owner/library，不能只沿多跳关联猜归属。库内冗余归属值只能从已认证上下文及已验证父记录派生，后续不可批量“改归属”；需迁移到另一用户的功能当前不在范围。

### 查询和写入边界

- ScopeContext由已验证会话与当前权限创建，至少绑定user_id、audience及适用的library_id；API请求体、URL参数、CSV、模型和消息中的user_id都不能构造可信scope。
- Repository方法必须接收适合该表类别的scope；没有scope=None、is_admin=True或ignore_owner的通用绕过参数。管理查询使用独立AdminScopeContext、操作范围和白名单DTO，不复用用户全文接口。
- 列表、详情、搜索、分页游标、COUNT、JOIN、子查询、UPDATE、DELETE、UPSERT都约束归属。JOIN每一侧的私有数据均核对owner/library；只过滤主表不能自动证明错误关联的另一侧安全。
- 更新采用id + scope + expected_revision/状态条件，检查受影响行数；零行按统一不可访问/版本冲突映射，不另查无scope对象确认属于谁。新增所有者由服务写入，不能批量解包客户端对象覆盖归属。
- 私有缓存key、幂等key、解释/私有TTS请求合并、对象路径和事件订阅包含账号/实例范围。仅global_word目录与全局生成占用按实例/标准词音键唯一；目录仓储接收限定词条/profile/操作的服务端CatalogScope，不允许通用ignore_owner。内部占用可关联私有生产Job，客户端无读取该关联权限；请求/模型用量/等待引用仍有owner。Worker从持久Job恢复身份和归属，逐阶段/模型调用动作重查权限，不信任队列快照；缓存或分区不是授权替代品。
- 文件签名、CSV、SSE、Agent工具、统计导出与管理元数据都受相同隔离；日志按现有脱敏/身份绑定契约，不把私有正文用于数据库巡检日志。

用户端不获得PG连接。API/Worker账号仅具运行所需DML，不能DDL、切换为迁移身份或修改追加审计；迁移与受控维护使用单独凭据，应用管理员不是数据库管理员。连接池Session只属于当前请求/任务，不缓存上个用户scope。此基线保障的是受控应用路径，持有数据库运行凭据的任意SQL不会自动经过ScopeContext；不将其描述为数据库原生行级隔离。

## 7. 无外键的逻辑关联与并发协议

每条逻辑关系在模型元数据登记：来源列、目标表/键、目标scope、是否可空、版本/状态要求、并发保护的父行、删除策略及历史保留例外。无外键不等于允许悬空关系，也不等于依赖后台巡检才发现越权。

关联新增/替换的统一流程：

1. 按已授权scope解析全部目标ID，拒绝他人/缺失/已删除/版本不匹配对象；批量请求对去重后的完整集合核对，不能只验证第一项或悄悄丢弃无权项。
2. 在写入事务内取得关系登记的父/保护行锁，首版使用SELECT FOR UPDATE。按现有授权锁顺序取得外层锁，再按登记的聚合顺序与稳定ID排序锁父行，避免两个服务反向加锁。
3. 取得锁后重新查询全部目标与库归属、tombstone/delete_generation、冻结版本和业务状态，不能沿用事务前的存在性检查。若目标由更上层聚合保护，新增和删除双方必须锁同一行；无法确定保护行的关系不能交付。
4. 派生owner/library，写子记录/关联、必要Outbox及revision；UNIQUE负责并发重复，失败整次业务事务回滚。不在锁内调用AI、对象存储或长耗时网络。
5. 父删除、合并、替换和GC遵守同一保护行协议，先持锁封存/增加代次并拒绝新引用，再检查/处理已有关系。父先删除则新增失败；新增先提交则删除必须看到新引用并按保留/解除/拒绝策略处理。

对现有不可变内容版本的引用仍需核对材料根的删除状态；仅锁版本行而删除只锁材料根会形成竞态，不被接受。READ COMMITTED为首版一般事务基线；额外隔离级别、锁超时和安全重试按具体用例登记，不靠提高隔离级别代替作用域验证。[PostgreSQL行锁](https://www.postgresql.org/docs/current/explicit-locking.html#LOCKING-ROWS)

所有正式写入口（API、Worker、种子、导入、维护）采用同一关联服务/协议。数据修复若必须绕开服务，在停止受影响写入的受控维护窗口执行，先核对所有者/关系并完成事后巡检，不能作为普通业务捷径。

逻辑关系巡检按scope和稳定游标分批，检查缺父、归属/版本不匹配和非法活动引用；已登记的历史快照例外单列。异常先隔离受影响结果并告警，输出数量及受限引用，不自动改owner、不擅自删除考试/审计历史。巡检用于发现历史/维护错误，不能替代同步授权。GC以完整关系清单和在途引用为依据，无法证明安全就保留并报告。

## 8. 唯一性、约束与索引

- 用户库内业务唯一键包含owner/library及业务键；用户级唯一包含其权威owner列；系统代码、规范化邮箱等明确全局唯一的对象另行声明。幂等记录同时绑定scope、动作及请求摘要，不把不同账号的同值key当同一请求。
- 必需字段NOT NULL；分数/用量/revision等由命名CHECK保证本行范围。NULL参与唯一性的语义必须明确：默认唯一约束不能推定“所有NULL只能一条”；业务要求时选择非空字段或可验证的部分唯一策略。
- `ModelCallUsage`以`external_call_attempt_id`唯一，owner/provider/model/capability/状态与时间非空；各Token、字符、图片和时长分项为非负值或NULL，未知不能写0。按本人时间/模型聚合和管理时间桶建立有界索引，字段口径见[模型用量统计](../contracts/model-usage.md)。
- 软删除后可复用名称的对象使用WHERE deleted_at IS NULL的部分唯一索引；恢复也经过同一唯一校验，冲突返回需处理，不覆盖现存记录。全生命周期唯一对象不得套此模式。
- 根据实际过滤与排序设计组合索引：库内常见(owner_user_id, library_id, created_at, id)，状态/软删除条件根据查询模式加入或用部分索引；不能给每列机械加index=True。
- 逻辑关联列按查子项、删除检查和GC查询建立作用域组合索引，不因没有外键省略访问路径。已由PK/UNIQUE覆盖的相同索引不重复建立；额外覆盖/反向索引说明用途。
- JSONB检索、文本搜索、表达式和GIN索引必须有真实查询需求、样本与EXPLAIN依据，不为所有JSON列建GIN。统计和管理概览有界分页/时间窗口，不做无界全表回传。

每个非主键索引记录支撑的查询/清理动作、列顺序、谓词和代价；用目标PG版本及合成样本验证执行计划，不以空表扫描计划证明性能。建/删索引属于迁移，不能由应用启动自行创建。

## 9. 删除、合并与历史

删除策略按逻辑关系逐条指定restrict、受控解除、历史保留或服务分批清理；这些是服务语义，不是数据库ON DELETE动作。ORM不配置隐式delete/delete-orphan级联，删除只能经显式服务完成。

材料使用既定tombstone/delete_generation阻止新工作及迟到结果复活；冻结试卷/成绩、收藏快照和已提交事实按 [数据生命周期](../architecture/data-jobs.md) 保留。用户不可见与物理清除是不同状态，不能把软删字段替代既有封存/GC协议。

合并保留旧ID到主记录的同scope逻辑映射和历史快照，不把旧ID转向另一用户。恢复核对父对象、当前权限、唯一键、内容版本和代次；不能恢复被新策略撤销的凭据或使旧Worker继续提交。账号当前没有公开物理删除需求，不自动新增删账号及全库级联功能。

## 10. ORM公共模板

以下是结构示意；现有实现见backend/app/models。TimestampMixin用于全部业务表；IdentityMixin、库归属Mixin、revision和软删按表类别组合，不能用一个万能基类塞入所有字段。所有模型集中登记，离线schema导出时不连接服务。

~~~python
from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import DateTime, MetaData, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID as PgUUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention={
        "pk": "pk_%(table_name)s",
        "uq": "uq_%(table_name)s_%(column_0_N_name)s",
        "ix": "ix_%(table_name)s_%(column_0_N_name)s",
        "ck": "ck_%(table_name)s_%(constraint_name)s",
    })


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(),
        comment="本行创建时间，UTC",
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(),
        onupdate=func.now(), comment="本行最近一次实际更新的时间，UTC",
    )


class CollectionTag(TimestampMixin, Base):
    __tablename__ = "collection_tags"
    __table_args__ = (
        UniqueConstraint("owner_user_id", "library_id", "collection_id", "tag_id"),
        {"comment": "本人资料库内的收藏标签关联"},
    )

    id: Mapped[UUID] = mapped_column(PgUUID(as_uuid=True), primary_key=True, default=uuid4)
    owner_user_id: Mapped[UUID] = mapped_column(PgUUID(as_uuid=True), nullable=False)
    library_id: Mapped[UUID] = mapped_column(PgUUID(as_uuid=True), nullable=False)
    collection_id: Mapped[UUID] = mapped_column(PgUUID(as_uuid=True), nullable=False)
    tag_id: Mapped[UUID] = mapped_column(PgUUID(as_uuid=True), nullable=False)
~~~

模板只展示时间和无外键列，不是可直接验收的完整表；实施时补齐每列注释、Table.info的scope/关系/生命周期、支撑查询的索引及对应服务。CollectionTag新增必须先按第7节验证库、收藏和标签，唯一约束本身不验证这些目标存在。

默认显式JOIN/Repository装配，不依赖ORM懒加载自动授权。确有只读relationship需求时显式primaryjoin/foreign列提示并限制为viewonly，连接条件包含scope；该提示不创建外键，也不开放自动关系写入。实例不得跨Session/账号共享，所有DTO在作用域内完成加载。

## 11. 查询、事务与SQL

服务掌握commit/rollback；仓储仅查询/写入/flush，每个并发请求/任务独立AsyncSession。参数化所有值，动态排序/字段/表名只能来自受控白名单；禁止拼接客户端SQL片段。ORM对象不能直接作为API响应。

大列表使用稳定排序及有界分页；可变updated_at排序不保证跨页快照，完整导出/批处理须使用冻结边界或既定游标方案，不能在更新过程中用OFFSET漏行。用户全量CSV仍按专用协议完成，不能因分页限额静默截断。

批量更新/删除必须带scope、状态与必要revision；UPDATE（含软删除）显式维护updated_at，物理DELETE按既定审计/清理记录留痕，不尝试更新已删除行。批次分段提交仅适用于已设计的可恢复任务，不能擅自拆开注册、交卷、授权审计等原子事务。安全重试只包可重做的短事务；数据库事务重试不能重放供应商调用。

SQL日志只记录批准的模板/指纹、耗时、行数和关联信息，不含绑定参数、密文/摘要值、正文或连接秘密；慢查询及失败一并进入 [统一观测](../operations/observability.md)。数据库引擎日志也按其脱敏要求配置。

## 12. 迁移、回填与兼容

所有schema变更经Alembic；不在应用启动运行create_all或自动修复表。不改写已应用revision，不从模型自动生成的候选DDL直接发布。每个迁移说明起止revision、目的、受影响表/数据量、锁和时限、数据回填/兼容、验证与回滚或前滚方式。

采用先扩展、回填、验证再收紧/删除的顺序：新增必填列先明确旧数据如何赋值，大数据分批可恢复回填，冲突/无法归属的行单独处理；检查完成后再收紧NOT NULL/UNIQUE/CHECK。不能用随机owner或当前时间填满以伪装原数据完整。

唯一索引建立前检查冲突；需CREATE INDEX CONCURRENTLY时声明非事务阶段、失败残留/无效索引处理和重试检查。不能静默绕开统一迁移锁或换连接。迁移仍由 [维护入口](scaffold.md#6-数据库初始化与种子) 在同一物理PG连接持session锁执行，包括非事务步骤；无法保留同连接则先修正维护实现。

新增表/约束/时间Mixin的验证覆盖空库及上一交付revision升级；首次建库不存在上一发布版本时如实记录。纯数据迁移也校验逻辑关联/归属、幂等和时间行为。不可逆迁移不虚构downgrade；按 [部署与恢复](../operations/deployment-recovery.md) 提供修复性前滚或恢复依据。

ORM模型、迁移和实际反射schema须一致；仅比较Alembic head不够。迁移产物不能含物理外键，所有非数据库内部业务表具备时间字段/注释和scope登记。运行账号与迁移账号分离，测试不得访问MyHome业务数据或生产副本。

## 13. 数据字典与建表审查

工程建立后，以SQLAlchemy MetaData/列注释及Table.info中的受审查扩展元数据为单一模型说明来源；Alembic记录变化，实际PG反射用于验证。按 [生成流程](scaffold.md) 导出contracts/database-schema.json，登记在受管生成清单中。它是内部数据库字典，不直接生成前端DTO或公开管理查表接口。用户要求的[数据库设计书](../architecture/database-design.md)维护未实现结构的可审查方案，并注明B0摘录基线；表实施后将字段与关系转入模型/生成字典，设计书链接实际来源，不并行维护另一套已实现字段真相。

| 字典层级 | 必需内容 |
| --- | --- |
| 表 | 表名/中文说明、领域模块、scope_kind/归属列映射、可变或追加、用途、保留/清理策略 |
| 列 | 类型/长度/精度、NULL/默认、PK/唯一/校验、中文含义/单位、来源/敏感级别、时间或版本语义 |
| 逻辑关系 | 来源列→目标键、scope/版本规则、可空性、保护行/锁顺序、删除/历史保留策略、服务与拒绝测试引用 |
| 索引/约束 | 名称、列/表达式/顺序/谓词、业务理由、支撑查询或幂等动作 |
| 变更 | 迁移revision、源模型/字典摘要、兼容范围、受影响用例和验证证据 |

新增/修改表的review必须逐项回答：为何需要这些列与NULL/default；如何隔离查询和写入；无外键关联如何防并发悬空；删除/恢复影响谁；时间/revision是否各司其职；唯一与索引是否匹配真实访问；迁移和字典是否同步。不能只凭模型能import或建表SQL能执行就通过。

静态检查验证模型登记、命名/注释/时间字段、scope/关系元数据、零外键及生成差异；真实PG集成验证迁移后的catalog和事务行为。Ruff/Pyright不承担这些检查。检查器必须有缺时间列、漏scope、误加外键、重复索引和字典漂移等坏样本，不能遇到空模型清单就报通过；执行范围见 [Lint](lint.md)。

## 14. 数据库验收

以下为未来工程验收，不代表本次执行过。B0验证已建基础表/公共Mixin/迁移和检查器；B1增加身份/收藏涉及的隔离和关联竞争；后续模块只补自身表及受影响路径。小阶段不强制运行后续全部DB项，大阶段对已交付表和入口执行完整矩阵。

| ID | 必须证明 | 必要证据 |
| --- | --- | --- |
| DB-01 | 没有物理外键且结构符合命名/字段/约束规范 | 模型元数据无外键；实际业务schema的pg_constraint无contype=f；漏字段/错误命名坏样本被拒绝 |
| DB-02 | 所有业务表时间字段一致且不可由普通客户端篡改 | ORM创建/更新、Core批量、原生SQL/upsert、无变化幂等、回填、UTC往返；created_at保留，审计不允许更新 |
| DB-03 | 类型、NULL、精度、状态与业务唯一性有效 | 真实PG拒绝空必填、超范围/重复值；区分NULL、空值和软删唯一行为，数据不被静默截断 |
| DB-04 | 全部读取路径隔离 | A/B替换ID、JOIN、搜索/COUNT/分页/导出；无scope调用失败，管理DTO不泄露私有正文 |
| DB-05 | 逻辑关联全部验证 | 正常服务拒绝缺父、他人ID、错库/错版本及混合批量；归属由服务派生，不能靠直接插入伪造通过 |
| DB-06 | 新增引用与父删除/合并/GC的竞争安全 | 真实PG多连接两种先后顺序、锁等待/重试；无新增活动悬空关联、无被删除内容复活 |
| DB-07 | 删除/恢复保留正确历史 | tombstone与代次、冻结考试/收藏快照保留；恢复唯一冲突明确失败，GC清单完整且失败可恢复 |
| DB-08 | 事务、CAS与任务不重复提交 | 注册/交卷/审计原子性、revision竞争、Worker重投/迟到；失败不留下半成品或重复学习贡献 |
| DB-09 | 索引服务于真实有界查询 | 受影响查询/删除检查的合成数据执行计划、游标稳定性、索引重复与无界查询检查 |
| DB-10 | 迁移与维护可验证 | 空库/已有版本升级、同连接迁移锁、回填中断、索引失败残留、前滚/恢复与最小权限 |
| DB-11 | 字典和schema一致 | 模型登记非空、来源摘要、确定性生成及实际反射核对；漏逻辑关系/字典漂移必须失败 |
| DB-12 | 非HTTP入口和资源同样隔离 | Worker/Agent/CSV/维护、缓存/对象/SSE双账号测试；凭据不串用、巡检只输出受控元数据 |

数据工厂遵守同样逻辑关系，不预置目标动作成功；仅在约束/巡检拒绝用例中故意注入非法记录，明确其绕过入口和期望结果。普通集成不能只mock Repository，也不能以数据库没有FK报错当作应用隔离通过。
