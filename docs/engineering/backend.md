# 后端开发手册

状态：设计基线 v0.1，2026-09-22。本文是未来 Python/FastAPI 工程的开发方法，当前没有 backend 工程或可运行示例。目录归属由 [项目结构](../architecture/project-structure.md) 定义；语言和静态规则见 [代码规范](coding.md)、[Lint](lint.md)，HTTP 模型和多语言以 [统一返回契约](../contracts/api-responses.md) 为唯一正文。

## 1. 新增功能的顺序

| 步骤 | 具体产出与完成依据 |
| --- | --- |
| 对齐行为 | 阅读对应 modules、API/权限、认证/数据设计，明确入口、动作权限、状态、归属、失败与验收；待决产品选择先保持显式，不自行当成既定范围 |
| 确定契约 | 定义请求 DTO、业务结果/Read DTO、HTTP 状态、统一响应泛型、错误码、幂等与 revision；为前后端提供一致样本，敏感字段不在 Read DTO 中 |
| 确定数据 | 按数据库规范登记表/索引/逻辑关联/锁顺序和迁移；只在实际需要时增加表，不为一个接口复制一套用户/权限表 |
| 编写领域与用例 | 纯规则放 domain；service 承担当前权限、ScopeContext、状态、事务/幂等及 Job/Outbox；先明确提交点和失败恢复，再写路由 |
| 编写仓储/适配 | 查询显式带 scope，跨表引用逐项验证；供应商和存储通过明确 adapter；仓储不 commit，不返回可绕过范围的查询构造器给路由 |
| 接入 HTTP | route 校验输入并调用用例，显式映射返回 DTO，包装一次统一模型；安装共用异常处理器和请求上下文，不逐路由 try/except 拼消息 |
| 接入观测/生成 | 登记必要事件及安全字段，继承 request/operation/job 关联；导出 OpenAPI/错误目录和 Dart 消费契约，不手改生成文件 |
| 局部验证/交付 | 执行目标行为及受影响权限/事务/契约的必要测试，按 AGENTS 完成本阶段独立 review、文档和 commit；不因加一个接口运行全仓全平台 |

开发环境与命令只从 [日常开发](development.md) 和 [脚手架](scaffold.md) 进入。本文不新增第二套 CLI、依赖管理或代码生成入口。

## 2. 模块、类型与公开入口

继续采用“技术层目录内按业务命名”的单体结构，具体目录和允许导入关系见项目结构。以材料查询为例，未来文件分属 `api/routes/materials.py`、`schemas/materials.py`、`services/materials.py`、`repositories/materials.py`、`models/materials.py`；复杂到需要拆分时，将同层的 materials.py 转成 materials/ 包，不同时保留文件和同名包。

| 类型 | 命名/责任 |
| --- | --- |
| 请求 DTO | MaterialUpdateRequest 等，验证协议字段；写入只提取允许修改的字段，不把 model_dump 全量赋给 ORM |
| 应用命令/结果 | MaterialUpdateCommand、MaterialView 等类型化对象；只有需要隔离 HTTP 或承载额外应用语义时才单独建，不为机械一对一映射造重复类 |
| API 输出 DTO | MaterialRead 等，明确允许暴露的字段；与请求、ORM、管理 DTO 分开 |
| 应用 service | MaterialService.get/update/delete 等业务动作；依赖经构造参数注入，方法显式接收作用域/命令；不承载 HTTP status、Cookie 或译文渲染 |
| Repository | MaterialRepository 按聚合/查询能力组织；方法名体现 scoped get/list/update；不创建可供业务绕过 scope 的 BaseRepository.get_all |
| 异常 | AppError 及必要的特定业务异常，承载注册错误码/安全上下文；仅预期不存在的内部查询可以返回 None，权限失败、依赖失败不能伪装空结果 |

纯 domain 对象可用 dataclass/Enum/Protocol；协议校验用 Pydantic，持久化用 SQLAlchemy。不为了统一返回而把整个领域层都改成 API Pydantic 模型。面向外部/需要替换实现的边界可定义小 Protocol，普通内部函数不强制每个类配接口/工厂。

公共 service 方法说明动作权限、scope、提交/副作用、幂等和可能业务错误。模块仅通过明确命名的公共入口互调；`_` 私有函数、ORM实例、仓储 session、可执行 query 均不作为跨模块接口。

## 3. 依赖组装与事务生命周期

| 生命周期 | 对象 | 组装/释放规则 |
| --- | --- | --- |
| 进程 | settings、数据库 engine/session factory、连接池、供应商无状态工厂 | bootstrap 组装，API lifespan/正式 CLI 共用；关闭时统一释放；不能持有可变当前用户、个人 Key、scope 或活动 Session |
| 请求 | 认证/授权上下文、request_id、locale、服务实例 | API dependency 提供，用户来自可信认证上下文；`Depends` 只在 API 接线层出现，不扩散到 service/domain |
| 用例/短事务 | AsyncSession、repository、锁/提交 | service 通过注入的 session factory 显式打开和关闭；每次独立执行拥有自己的 session；一个原子用例共用其事务内仓储 |
| Worker/Agent 阶段 | Job 引用、受限主体、当前授权、阶段会话 | 非 HTTP 的 bootstrap/context factory 组装同一 service；重新验证权限、租约和业务代次，不能伪造 Request 或缓存旧用户 Token |

首次认证/授权的数据库读取必须在自己的短作用域结束；不能将其已自动开启事务的 Session 传给 service 再无条件 begin。选定的 service 事务入口是唯一提交者：路由依赖退出不隐式 commit，repository 和嵌套辅助函数不 commit。出现异常由事务上下文 rollback 后重新抛出/映射，响应不能早于应有的提交确认。

跨模块写入若必须原子完成，由明确的应用编排用例拥有一个短事务，调用参与模块明确开放的事务内能力；这些能力接受同一个受控会话和 scope，不自行开新事务/提交。禁止 A service 调 B service 再调回 A 的隐含提交链，也不能用独立 HTTP 自调用协调本进程业务。

非原子、耗时或外部动作拆为持久 Job/Outbox 阶段；不跨付费调用持锁，不用 FastAPI BackgroundTasks 代替必须可靠完成的任务。具体锁、并发删除/关联与恢复由 [数据库规范](database.md)、[数据与任务](../architecture/data-jobs.md) 维护。

## 4. 路由返回模板

以下是未来材料详情路由的接线示意，不是当前存在的 API。依赖/DTO/service 在功能实施时创建并接受实际契约测试；`require_action` 验证身份、受众与动作，service.get 仍验证当前资源的 scope/状态，路由隐藏不代替授权。

```python
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends

from app.api.dependencies import get_material_service, get_request_id, require_action
from app.api.responses import error_responses
from app.domain.scope import ScopeContext
from app.schemas.materials import MaterialRead
from app.schemas.responses import ResponseMeta, SuccessResponse
from app.services.materials import MaterialService

router = APIRouter(prefix="/materials", tags=["materials"])


@router.get(
    "/{material_id}",
    operation_id="get_material",
    status_code=200,
    response_model=SuccessResponse[MaterialRead],
    responses=error_responses(401, 403, 404, 422, 500, 503),
)
async def get_material(
    material_id: UUID,
    scope: Annotated[ScopeContext, Depends(require_action("material.read"))],
    service: Annotated[MaterialService, Depends(get_material_service)],
    request_id: Annotated[UUID, Depends(get_request_id)],
) -> SuccessResponse[MaterialRead]:
    result = await service.get(scope=scope, material_id=material_id)
    data = MaterialRead(id=result.id, title=result.title, revision=result.revision)
    return SuccessResponse[MaterialRead](
        data=data,
        meta=ResponseMeta(request_id=request_id),
    )
```

全局路由挂载 `/api/v1`，不在每个模块重复拼接版本。示例中的 MaterialRead 只表示详情的最小安全投影，真实字段由材料契约确定；管理端应定义自己的元数据 DTO，不复用该用户内容投影。

error_responses 仅返回 OpenAPI 的错误响应声明；它不捕获异常。异常处理器在 main/app factory 一次注册，序列化、默认 422 覆盖、Header 和流式边界按统一返回契约实施。普通路由不直接 return ORM/dict/JSONResponse，不将异常文本写进 message。

写接口沿用同一返回方式，但 service 必须先完成事务提交：创建资源用 201，持久受理任务用 202，约定无响应体的删除用 204。业务是否成功由持久结果确定，不能先返回成功再尝试后台写入。客户端超时后有幂等/状态恢复路径，不能用 retryable 掩盖提交不确定性。

## 5. 写用例示例：收藏新增

以 B1 已规划的收藏新增为参考，以下是实现步骤而非新的功能或路由定义：

1. 输入模型拒绝 owner/user/library/权限等由认证或系统产生的字段；请求只给获准内容、类型与出处引用。取得 collection.create 及所需来源 read 权限，解析可信 ScopeContext。
2. service 开短事务，按照数据规范的固定顺序锁定相关父/来源保护行，校验同库、不可变版本、tombstone/代次和出处；不先在事务外校验后直接插入。
3. 在同一事务处理 actor/audience/动作范围内的幂等回执、业务唯一约束、收藏写入及规定的审计/Outbox。并发重复由约束和规范化请求摘要判断，不能吞掉所有数据库异常当成功。
4. 从获准字段形成类型化结果，提交成功后由路由映射 CollectionRead 并返回 201 的 SuccessResponse。重放先重查当前权限，仅复用业务结果引用，不复用旧 HTTP 信封/请求 ID。
5. 当前小阶段只验证必要路径：本人成功和持久结果、跨用户/跨库来源拒绝、相关删除竞争、重复提交、输入和统一返回；不为这个切片预先实现全部照片/CSV/练习能力。

具体业务字段/重复策略仍以 [收藏模块](../modules/vocabulary-practice.md) 和 [出处](../contracts/content-locator.md) 为准；如果写用例触发 AI，则先持久化任务，通过 Worker 执行，不延长这里的事务。

## 6. 测试与交付时如何使用

后端测试框架、真实基础设施、工厂边界和示例分别由 [测试策略](testing/strategy.md)、[测试数据](testing/data.md) 维护。按目标选择层次：纯规则用 unit，HTTP/统一返回用 contract，真实事务/隔离与并发用 integration；不能用 mock 仓储证明数据库竞争安全。

新增响应或错误类型时，检查 JSON 样本、具体泛型 OpenAPI、注册错误目录、Flutter DTO/文案参数的同向变更。只写 response_model 声明不代表运行已验证，必须包含相关真实路由错误路径。

本手册的实施检查归入既有 STR/SCF/API/DB 验收族，不另造一套全仓测试门槛。B0 建立公共模型、异常/依赖接线及生成检查，B1 以真实身份/收藏闭环证明使用，后续模块沿用；文档完成不勾选工程里程碑。
