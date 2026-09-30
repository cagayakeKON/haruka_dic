"""Stable error identifiers and safe Chinese fallback messages."""

from dataclasses import dataclass
from enum import StrEnum
from types import MappingProxyType


class ErrorCode(StrEnum):
    BAD_REQUEST = "BAD_REQUEST"
    INPUT_INVALID = "INPUT_INVALID"
    AUTH_REQUIRED = "AUTH_REQUIRED"
    AUTH_LOGIN_FAILED = "AUTH_LOGIN_FAILED"
    ACCESS_EXPIRED = "ACCESS_EXPIRED"
    SESSION_REVOKED = "SESSION_REVOKED"
    SESSION_INVALID = "SESSION_INVALID"
    REAUTHENTICATION_REQUIRED = "REAUTHENTICATION_REQUIRED"
    AUTH_SCOPE_REQUIRED = "AUTH_SCOPE_REQUIRED"
    AUTH_SCOPE_CHANGED = "AUTH_SCOPE_CHANGED"
    PERMISSION_DENIED = "PERMISSION_DENIED"
    CSRF_FAILED = "CSRF_FAILED"
    RESOURCE_NOT_FOUND = "RESOURCE_NOT_FOUND"
    METHOD_NOT_ALLOWED = "METHOD_NOT_ALLOWED"
    REVISION_CONFLICT = "REVISION_CONFLICT"
    IDEMPOTENCY_CONFLICT = "IDEMPOTENCY_CONFLICT"
    STATE_CONFLICT = "STATE_CONFLICT"
    KEY_REQUIRED = "KEY_REQUIRED"
    REFRESH_SUPERSEDED = "REFRESH_SUPERSEDED"
    RESOURCE_EXPIRED = "RESOURCE_EXPIRED"
    PAYLOAD_TOO_LARGE = "PAYLOAD_TOO_LARGE"
    MEDIA_TYPE_UNSUPPORTED = "MEDIA_TYPE_UNSUPPORTED"
    CAPABILITY_UNSUPPORTED = "CAPABILITY_UNSUPPORTED"
    RATE_LIMITED = "RATE_LIMITED"
    QUOTA_EXCEEDED = "QUOTA_EXCEEDED"
    INTERNAL_ERROR = "INTERNAL_ERROR"
    DEPENDENCY_ERROR = "DEPENDENCY_ERROR"
    SERVICE_UNAVAILABLE = "SERVICE_UNAVAILABLE"
    DEPENDENCY_TIMEOUT = "DEPENDENCY_TIMEOUT"
    EXTERNAL_RESULT_UNKNOWN = "EXTERNAL_RESULT_UNKNOWN"


@dataclass(frozen=True)
class ErrorDefinition:
    http_status: int
    message: str


ERRORS = MappingProxyType(
    {
        ErrorCode.BAD_REQUEST: ErrorDefinition(400, "请求格式有误"),
        ErrorCode.INPUT_INVALID: ErrorDefinition(422, "输入信息有误"),
        ErrorCode.AUTH_REQUIRED: ErrorDefinition(401, "请先登录"),
        ErrorCode.AUTH_LOGIN_FAILED: ErrorDefinition(401, "登录失败"),
        ErrorCode.ACCESS_EXPIRED: ErrorDefinition(401, "登录凭据已过期"),
        ErrorCode.SESSION_REVOKED: ErrorDefinition(401, "登录已失效"),
        ErrorCode.SESSION_INVALID: ErrorDefinition(401, "登录已失效"),
        ErrorCode.REAUTHENTICATION_REQUIRED: ErrorDefinition(403, "请重新登录以确认敏感操作"),
        ErrorCode.AUTH_SCOPE_REQUIRED: ErrorDefinition(409, "请更新应用后重新登录"),
        ErrorCode.AUTH_SCOPE_CHANGED: ErrorDefinition(409, "登录身份已变化，请重新确认"),
        ErrorCode.PERMISSION_DENIED: ErrorDefinition(403, "没有操作权限"),
        ErrorCode.CSRF_FAILED: ErrorDefinition(403, "请求验证失败"),
        ErrorCode.RESOURCE_NOT_FOUND: ErrorDefinition(404, "未找到资源"),
        ErrorCode.METHOD_NOT_ALLOWED: ErrorDefinition(405, "不支持此请求方法"),
        ErrorCode.REVISION_CONFLICT: ErrorDefinition(409, "内容已更新，请重新加载"),
        ErrorCode.IDEMPOTENCY_CONFLICT: ErrorDefinition(409, "重复请求内容不一致"),
        ErrorCode.STATE_CONFLICT: ErrorDefinition(409, "当前状态不支持此操作"),
        ErrorCode.KEY_REQUIRED: ErrorDefinition(409, "请配置自己的模型凭据"),
        ErrorCode.REFRESH_SUPERSEDED: ErrorDefinition(409, "登录凭据已由另一请求更新"),
        ErrorCode.RESOURCE_EXPIRED: ErrorDefinition(410, "资源已过期"),
        ErrorCode.PAYLOAD_TOO_LARGE: ErrorDefinition(413, "请求内容过大"),
        ErrorCode.MEDIA_TYPE_UNSUPPORTED: ErrorDefinition(415, "不支持此内容类型"),
        ErrorCode.CAPABILITY_UNSUPPORTED: ErrorDefinition(422, "暂不支持所选能力"),
        ErrorCode.RATE_LIMITED: ErrorDefinition(429, "操作过于频繁"),
        ErrorCode.QUOTA_EXCEEDED: ErrorDefinition(429, "已达到使用额度"),
        ErrorCode.INTERNAL_ERROR: ErrorDefinition(500, "服务暂时无法完成请求"),
        ErrorCode.DEPENDENCY_ERROR: ErrorDefinition(502, "依赖服务响应异常"),
        ErrorCode.SERVICE_UNAVAILABLE: ErrorDefinition(503, "服务尚未就绪"),
        ErrorCode.DEPENDENCY_TIMEOUT: ErrorDefinition(504, "依赖服务响应超时"),
        ErrorCode.EXTERNAL_RESULT_UNKNOWN: ErrorDefinition(504, "外部操作结果待确认"),
    }
)


class FieldErrorCode(StrEnum):
    REQUIRED = "VALIDATION_REQUIRED"
    TYPE = "VALIDATION_TYPE"
    FORMAT = "VALIDATION_FORMAT"
    TOO_LONG = "VALIDATION_TOO_LONG"
    OUT_OF_RANGE = "VALIDATION_OUT_OF_RANGE"
    UNKNOWN_FIELD = "VALIDATION_UNKNOWN_FIELD"
    INVALID = "VALIDATION_INVALID"


FIELD_MESSAGES = MappingProxyType(
    {
        FieldErrorCode.REQUIRED: "请填写必填信息",
        FieldErrorCode.TYPE: "信息类型有误",
        FieldErrorCode.FORMAT: "信息格式有误",
        FieldErrorCode.TOO_LONG: "内容超过允许长度",
        FieldErrorCode.OUT_OF_RANGE: "数值超出允许范围",
        FieldErrorCode.UNKNOWN_FIELD: "包含不支持的字段",
        FieldErrorCode.INVALID: "输入信息有误",
    }
)
