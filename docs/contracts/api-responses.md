# 统一 API 返回、异常与语言契约

状态：2026-09-22，B0-foundation已实现公共模型、健康路由和统一错误的最小HTTP边界；业务JSON接口与Dart API生成仍待交付，证据见 [工程记录](../delivery/reviews/2026-09-22-scaffold-foundation.md)。所有用户端和管理端JSON API共用本文模型；接口分组、认证、幂等和流事件见 [API总则](api.md)。本文是返回结构的唯一人工规范，OpenAPI由后端Pydantic单向导出。

## 1. 适用范围与返回责任

| 场景 | 必须采用的返回 |
| --- | --- |
| 单资源、操作结果、已受理任务 | `SuccessResponse[明确的业务 Read/Result DTO]`；202 的 data 含已持久化的 job_id/run_id 和状态 |
| 游标列表 | `PageResponse[明确的条目 DTO]`；data 直接是数组，不增加 data.items 或 data.data |
| API 失败 | 非 2xx HTTP 状态及 `ErrorResponse`；不能 HTTP 200 再用 code 表示失败 |
| 真正无内容成功 | 204 且零响应体；不返回 JSON null，也不创建 SuccessResponse[None] 代替 204 |
| 文件、音频、CSV、SSE、HEAD、304 | 使用原生传输语义；不包 JSON 成功信封。开始传输前的应用错误仍按 ErrorResponse，开始后按流协议处理 |

成功外层只由路由/其纯响应构造函数建立一次；service 返回类型化业务结果或抛出业务异常，不返回 HTTP Response、成功信封或 `(data, code, message)` 元组。错误外层只由 API 异常处理器建立。禁止响应中间件读取并重新包装所有响应体，避免破坏流、Cookie、Header、204 和 OpenAPI。

不增加重复的顶层 success、status、timestamp 或成功 code。HTTP 状态表达传输结果，业务 DTO 的 state 表达业务状态，meta.request_id 负责关联；三者不能互相替代。JSON 使用 application/json。

## 2. 统一模型基线

以下为 `backend/app/schemas/responses.py` 的模型基线，枚举来自 `app/contracts/errors.py` 的只读注册表；基础实现已建立，后续按业务扩展安全字段路径与参数目录。Pydantic泛型和字段模型依据 [官方模型文档](https://pydantic.dev/docs/validation/latest/concepts/models/#generic-models)，实际版本由backend/uv.lock锁定。

```python
from typing import Generic, Literal, Self, TypeVar
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.contracts.errors import ErrorCode, FieldErrorCode

T = TypeVar("T")


class ApiModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ResponseMeta(ApiModel):
    request_id: UUID


class PageMeta(ResponseMeta):
    next_cursor: str | None
    has_more: bool

    @model_validator(mode="after")
    def validate_cursor(self) -> Self:
        if (self.has_more and not self.next_cursor) or (
            not self.has_more and self.next_cursor is not None
        ):
            raise ValueError("has_more and next_cursor must agree")
        return self


class SuccessResponse(ApiModel, Generic[T]):
    data: T
    meta: ResponseMeta


class PageResponse(ApiModel, Generic[T]):
    data: list[T]
    meta: PageMeta


class FieldError(ApiModel):
    source: Literal["body", "query", "path", "header", "cookie"]
    path: list[str | int]
    code: FieldErrorCode
    message: str
    message_args: dict[str, str | int] = Field(default_factory=dict)


class RevisionConflictDetails(ApiModel):
    kind: Literal["revision_conflict"] = "revision_conflict"
    current_revision: int = Field(ge=0)


class ApiError(ApiModel):
    code: ErrorCode
    message: str
    retryable: bool = False
    message_args: dict[str, str | int] = Field(default_factory=dict)
    field_errors: list[FieldError] = Field(default_factory=list)
    details: RevisionConflictDetails | None = None


class ErrorResponse(ApiModel):
    error: ApiError
    meta: ResponseMeta
```

- T 必须具体化，例如 `SuccessResponse[MaterialRead]`、`PageResponse[CollectionRead]`；禁止裸泛型、Any、object 或任意 dict 作为业务载荷。DTO 只包含当前动作允许披露的字段，不能靠序列化时临时 exclude 隐藏密码、Key、答案。
- PageResponse 与 SuccessResponse 是两个并列信封，不能再套一层。空列表为 data=[]、has_more=false、next_cursor=null。next_cursor 只在有后页时非空，末页明确为 null；不全局启用 exclude_none，否则会改变该契约。
- request_id 是服务端为每个 HTTP 请求生成的 UUID，响应 X-Request-ID 与 meta 完全相同；幂等重放仍使用本次 request_id，不缓存旧信封。业务操作关联仍用 API 总则规定的 operation/job/run ID。
- error 的 message_args、field_errors、details 在输出中始终分别有对象、数组、对象或 null；无值时为 `{}`、`[]`、`null`，客户端兼容旧响应缺少可选字段时使用这些默认值。
- details 当前只定义授权后可见的 revision 冲突。增加其他细节时先定义带 kind 的具体 DTO、错误码到 DTO 的对应关系及测试，多种时使用有 discriminator 的联合；不得开放 `dict[str, Any]`。不属于该 code 的 details 必须在错误构造器中拒绝。
- message_args 也必须经过每个错误码的参数名/类型/长度白名单校验；上面的字典类型只是传输类型，不意味着能放任意字符串。仅允许安全数量、约束阈值、预定义枚举，禁止原始输入、账号标识、私有资源内容和凭据。
- 输入/输出 DTO 分离；输入字段缺省与显式 null 的更新语义由业务请求模型定义，不能用响应模型反向作为 PATCH 请求模型。

示例：GET 收藏列表成功，HTTP 200。

```json
{
  "data": [],
  "meta": {
    "request_id": "b5a47558-924b-4c6f-b7f5-f1b7d46345b5",
    "next_cursor": null,
    "has_more": false
  }
}
```

示例：请求字段超出允许长度，HTTP 422。该值仅展示协议，不新增任何业务字段的长度要求。

```json
{
  "error": {
    "code": "INPUT_INVALID",
    "message": "输入信息有误",
    "retryable": false,
    "message_args": {},
    "field_errors": [
      {
        "source": "body",
        "path": ["title"],
        "code": "VALIDATION_TOO_LONG",
        "message": "内容超过允许长度",
        "message_args": {"max_length": 200}
      }
    ],
    "details": null
  },
  "meta": {"request_id": "b5a47558-924b-4c6f-b7f5-f1b7d46345b5"}
}
```

## 3. HTTP、错误码与重试

| HTTP 状态 | 错误码/结果与约定 |
| --- | --- |
| 200/201/204 | 查询或操作完成/创建完成/无内容成功；201 返回资源或 Location，204 不带信封 |
| 202 | 接受且已持久化；返回 Job/Run DTO，不宣称解析、AI 或评分已经完成 |
| 400 | BAD_REQUEST：JSON 语法损坏、协议无法解析；修正请求，不自动重试 |
| 422 | INPUT_INVALID：JSON 可解析但字段类型、必填、格式、允许值或业务输入不合规；不能把身份/归属失败归入这里 |
| 401 | AUTH_REQUIRED、AUTH_LOGIN_FAILED、ACCESS_EXPIRED、SESSION_REVOKED、SESSION_INVALID；仅 native 的 ACCESS_EXPIRED 允许一次刷新协调，其他按认证合同处理 |
| 403 | PERMISSION_DENIED、CSRF_FAILED；刷新 Token 不能修复权限不足 |
| 404 | RESOURCE_NOT_FOUND：不存在、其他用户私有 ID、未知 API 路径；均不泄露他人资源存在性 |
| 405 | METHOD_NOT_ALLOWED；保留由路由系统计算的 Allow Header |
| 409 | REVISION_CONFLICT、IDEMPOTENCY_CONFLICT、STATE_CONFLICT、KEY_REQUIRED；修复冲突/配置后才是新操作。REFRESH_SUPERSEDED 沿用认证专题的同次刷新协调，不套用普通业务重试 |
| 410 | RESOURCE_EXPIRED：本人已过期预览/挑战/游标；他人资源仍为 404 |
| 413/415 | PAYLOAD_TOO_LARGE / MEDIA_TYPE_UNSUPPORTED；服务端仍校验实际内容 |
| 422 | CAPABILITY_UNSUPPORTED：所选模型/声音/格式组合不受支持，不自动更换供应商 |
| 429 | RATE_LIMITED、QUOTA_EXCEEDED；有可靠重试时间才给 Retry-After，无明确恢复条件不得标可立即重试 |
| 500 | INTERNAL_ERROR：未预期代码/响应校验/内部数据错误；安全兜底，不暴露异常文本 |
| 502/503/504 | DEPENDENCY_ERROR / SERVICE_UNAVAILABLE / DEPENDENCY_TIMEOUT；已知外部结果不确定时优先 EXTERNAL_RESULT_UNKNOWN（504），不能把未知收费当未调用 |

错误码在 `app/contracts/errors.py` 注册为稳定字符串枚举，并记录 HTTP 状态、兜底文案、允许参数、details 类型和重试分类；领域层可引用这个不依赖框架的目录。导出到 contracts/errors.json，Flutter 消费其枚举与参数契约。未知客户端错误码按失败处理；不能按 message 文本分支或把未知值映射为成功。

表中为基础分类；各模块已有或后续定义的专用代码也必须进入同一注册表，按模块合同明确状态和恢复方式，不因未列在本表就改名或删除。原生刷新使用专门的 refresh_request_id/代次回执，它与每次 HTTP 的 request_id 不同。

retryable 表示在当前动作协议下允许自动重试，不是“HTTP 5xx 都重试”。默认 false；只有明确暂态原因、重试预算、可重放读取或相同幂等键安全写入全部成立才为 true。EXTERNAL_RESULT_UNKNOWN、内部错误、输入/权限/状态错误均为 false，先查询提交/任务状态；权限重查和幂等语义仍以 API 总则为准。

分页继续采用 opaque cursor + limit：默认 20，最大 100；排序有稳定唯一尾键，cursor 绑定筛选/排序/账号/受众和版本，允许的过滤/排序字段显式声明。失效游标由服务分类，不返回他人的游标内容；普通列表不强制全库精确 total。

## 4. 统一异常处理

| 来源 | 映射责任与约束 |
| --- | --- |
| 领域/应用异常 | `AppError` 携带注册 code 和类型化安全参数；API 统一处理器决定 HTTP/文案/信封，服务不 import FastAPI 或自行创建 JSONResponse |
| RequestValidationError | JSON 解析错误映射 400 BAD_REQUEST，其余已识别的客户端参数错误 422 INPUT_INVALID；字段错误经过下面的清洗器 |
| Starlette HTTPException（含 FastAPI 子类） | 统一处理 404/405 等框架错误；只使用注册映射，不照抄 detail。仅保留服务端生成且允许的 Allow、WWW-Authenticate、Retry-After 等 Header |
| ResponseValidationError / 内部 Pydantic ValidationError | 属于服务端缺陷，500 INTERNAL_ERROR；不一律当客户端 422；供应商解析失败由 adapter 转成相应依赖/模型契约错误 |
| 数据库/供应商异常 | 只把已识别的唯一约束/版本冲突或依赖失败映射为指定业务错误；未知异常为 500。先 rollback，不能所有 IntegrityError 都转重复记录 |
| 未预期 Exception | 最外层错误边界生成最小 ErrorResponse 并集中记录一次脱敏异常；不能返回 str(exc)、SQL、请求体或 Key |
| 取消、断连、流开始后的错误 | 不捕获 BaseException 吞取消；已发响应头不能再改 HTTP 状态或追加 JSON 信封。SSE 用既定 failed/断开与快照恢复，文件/CSV 标记中断，后台任务写持久失败状态 |

字段错误结构由 FieldError 唯一规定。source 是输入位置，path 是相对该位置的公开字段路径，数组下标为整数，例如 `["items", 0, "term"]`；容器级错误用空路径。首批字段码为 VALIDATION_REQUIRED、VALIDATION_TYPE、VALIDATION_FORMAT、VALIDATION_TOO_LONG、VALIDATION_OUT_OF_RANGE、VALIDATION_UNKNOWN_FIELD、VALIDATION_INVALID。

清洗器将 Pydantic 类型映射到上述字段码；只接受请求 schema 中的字段路径及合法数组下标，未知字段或任意字典键退到安全的父路径。禁止透传 errors() 的 input、ctx、url、原始 msg 或未知 loc 字符串；错误数量有上限，初始最多 50 项，剩余由通用输入错误表达。登录等敏感流程另遵循账号防枚举规则，不回显账号是否存在。

请求 ID、CORS、统一错误及日志边界的排列在 B0 实测：未匹配路由、解析错误、鉴权拒绝和未预期 500 都有一致信封与 X-Request-ID；需要跨域的允许来源在错误路径仍有 CORS Header。处理器不再查数据库/调用模型生成错误文案；兜底路径使用启动时验证的静态消息。响应头安全策略与 Cookie 清除必须保留。

统一范围是 Haruka 应用可控制的 API 响应。反向代理可能产生 413/502/504 或非 JSON 响应，客户端按 HTTP/媒体类型安全降级并保留可用关联 ID；部署可提供同形安全错误页，但不声称能统一网络断连或第三方对象存储响应。

实现参考 [FastAPI 错误处理](https://fastapi.tiangolo.com/tutorial/handling-errors/)；实现时仍需证明默认校验响应和路由 404/405 被覆盖，不能只注册业务异常处理器就称为统一。

## 5. 路由声明、序列化和客户端

1. 每条 JSON 路由显式声明具体 `response_model`、成功 HTTP 状态、稳定 operation_id，以及可能发生的 ErrorResponse 状态集合；公共 helper 合并通用 401/403/422/500，公共路由按实际情况裁剪，资源路由补 404/409 等。
2. 同时替换 OpenAPI 中框架默认 HTTPValidationError/422 定义，确保运行响应与生成文档都是统一错误；路由清单检查禁止返回未具体化的泛型或默认裸字典。
3. 普通成功路由返回 Pydantic 信封模型，让声明的响应模型参与校验；不直接 JSONResponse 绕开验证。统一错误处理器先构造 ErrorResponse，再用 `model_dump(mode="json")` 交给 JSONResponse，不能二次 JSON 编码。
4. UUID、UTC 时间和 Decimal 按 API 总则序列化；Decimal 字段使用公共 `CanonicalDecimal`，输入只接受精确 Decimal 或十进制字符串（可含指数），拒绝 JSON number、NaN 和 Infinity，输出固定十进制字符串、不使用指数形式、不经浮点转换。输入与输出 schema 分别描述接受格式和规范格式，Dart 按字符串保留精度。DTO 显式映射允许字段，不能以 from_attributes 暴露整份 ORM 模型。模型正确不代表权限正确，仍需服务的 scope/动作校验。
5. 二进制、CSV、SSE、204、HEAD/304 显式声明 response class、媒体类型和空体行为；Cookie/Header 由路由的 Response 参数或统一安全适配层设置，不放进 data。
6. Flutter 在统一 ApiClient 解码一次，业务页面只接收类型化 data 或失败对象；非 JSON 网关错误、空体和未知错误码走安全兜底。新增可选响应字段允许旧客户端忽略，不把服务端 extra=forbid 当成旧客户端必须拒绝新字段。

响应声明与校验行为依据 [FastAPI response_model](https://fastapi.tiangolo.com/tutorial/response-model/)。声明 ErrorResponse 的 OpenAPI metadata 本身不会安装异常处理器，两者都必须实施。

## 6. 多语言与文案归属

P0 界面只支持 zh-Hans，母语/目标学习语言仍遵循 [设置模块](../modules/settings.md)；本节规定扩展机制，不新增英文或日文 UI 的交付范围。

| 内容 | 归属与规则 |
| --- | --- |
| UI、成功提示、错误/字段错误文案 | Flutter 本地化资源；错误按 code + 白名单 message_args 查资源，不使用服务端文本作判断 |
| error.message 和字段 message | 后端注册目录中的安全兜底模板；P0 为 zh-Hans。未知客户端 code 可显示该安全文本或通用失败提示，不展示原始异常 |
| 将来启用的验证/恢复邮件等 | 后端发送适配器的版本化模板，只有对应功能启用时创建；不把 HTML 模板放入 service/domain 或由 AI 即时翻译 |
| 释义、练习、AI 输出和 TTS | 业务内容语言，由目标语/释义语/声音和模型能力决定，与 HTTP 文案 locale 分开，不因 Accept-Language 改写原文或评分依据 |
| CSV、日志、权限/错误码 | 协议字段和机器事件码保持稳定；CSV 不随界面语言翻译列名，日志不以译文作为检索键 |

API 文案 locale 的解析顺序：请求中合法且在支持清单内的 Accept-Language 偏好（按权重）→ 已取得的当前用户界面偏好 → zh-Hans。P0 清单仅 zh-Hans；不为解析语言额外查找未登录账号，不支持值安全回退、不返回 406。不将母语或 active_target_language 当作界面语言；P0 仅规范化 zh/zh-CN 为 zh-Hans，其他语言/地区不自行推断等价。Header 长度与解析成本受限；q=0、非法值被忽略。

locale 解析结果保存在请求上下文，显式传入消息渲染器，不修改进程全局 locale。带翻译消息的错误响应设置 Content-Language 为实际兜底语言；如未来可缓存语言相关响应，合并 Vary: Accept-Language 并保持私有缓存策略。含多语言材料的成功 DTO 不用该 Header 假装整段内容只有一种语言。

异步任务创建时持久化所需的内容语言/模板语言及版本快照；Worker 不依赖原请求 Header 或全局 locale。改偏好只影响新任务；重新生成属于显式新操作。内容语言、模型/声音等语义维度进入既有按用户分区的缓存键，不能用 UI locale 替代这些维度。

错误目录单向导出 code、参数 schema、默认模板标识；Flutter ARB 是前端译文的唯一来源。构建时检查已支持 locale 的模板存在、占位符名/类型与注册表一致；缺译文走确定的 fallback 并留下无敏感内容的诊断，不动态调用付费模型翻译异常。新增 UI 语言必须作为单独范围变更验证。

## 7. 验收

以下在B0/B1及后续受影响功能落实；当前只有基础模型、真实ASGI错误和离线OpenAPI的局部证据，完整API-07～API-10仍未完成。

- API-07：单资源、分页、空列表、202 使用具体统一模型；HTTP/头/meta 相符，幂等回放更新 request_id，无重复包装。
- API-08：真实路由的业务异常、坏 JSON、字段错误、401/403/404/405、500 均符合 ErrorResponse；默认 422 schema 已替换，未知内部异常无正文/秘密泄露。
- API-09：Decimal/UUID/UTC/null 和泛型实例生成到 Dart 后与运行 JSON 一致；204/文件/SSE 不被包装，流开始后失败与非 JSON 代理错误正确处理。
- API-10：字段路径/参数/details 白名单、未知错误码、语言回退与占位符检查通过；目标学习语独立于 UI locale，任务语言快照不被偏好修改覆盖。
