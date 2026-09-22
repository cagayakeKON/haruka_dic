// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Haruka';

  @override
  String get home => '主页';

  @override
  String get environment => '环境信息';

  @override
  String get shellTitle => '准备开始学习';

  @override
  String get shellDescription => '应用基础已就绪。账号、材料与学习功能正在建设中。';

  @override
  String get materialsTitle => '你的学习材料';

  @override
  String get materialsDescription => '未来可导入小说、课本和试卷，使用各自的阅读与练习页面。';

  @override
  String get unavailable => '尚未开放';

  @override
  String get novels => '小说';

  @override
  String get textbooks => '课本';

  @override
  String get exams => '试卷';

  @override
  String get environmentDescription => '查看公开构建配置，并检查当前服务是否已就绪。';

  @override
  String get environmentLabel => '运行环境';

  @override
  String get instanceLabel => '服务实例';

  @override
  String get apiLabel => '服务地址';

  @override
  String get applicationLabel => '应用标识';

  @override
  String get devEnvironment => '本地开发';

  @override
  String get productionEnvironment => '正式环境';

  @override
  String get adminTitle => '管理端准备中';

  @override
  String get adminDescription => '管理端需要独立登录及在线权限验证，当前尚未开放。';

  @override
  String get backHome => '返回主页';

  @override
  String get notFoundTitle => '页面不可用';

  @override
  String get notFoundDescription => '此页面不存在，或不适用于当前平台。';

  @override
  String get configurationTitle => '应用配置不可用';

  @override
  String get configurationDescription => '环境、实例或服务地址不符合构建要求，请检查公开构建配置后重新启动。';

  @override
  String get apiAccessExpired => '登录凭据已过期';

  @override
  String get apiAuthLoginFailed => '登录失败';

  @override
  String get apiAuthRequired => '请先登录';

  @override
  String get apiBadRequest => '请求格式有误';

  @override
  String get apiCapabilityUnsupported => '暂不支持所选能力';

  @override
  String get apiCsrfFailed => '请求验证失败';

  @override
  String get apiDependencyError => '依赖服务响应异常';

  @override
  String get apiDependencyTimeout => '依赖服务响应超时';

  @override
  String get apiExternalResultUnknown => '外部操作结果待确认';

  @override
  String get apiIdempotencyConflict => '重复请求内容不一致';

  @override
  String get apiInputInvalid => '输入信息有误';

  @override
  String get apiInternalError => '服务暂时无法完成请求';

  @override
  String get apiKeyRequired => '请配置自己的模型凭据';

  @override
  String get apiMediaTypeUnsupported => '不支持此内容类型';

  @override
  String get apiMethodNotAllowed => '不支持此请求方法';

  @override
  String get apiPayloadTooLarge => '请求内容过大';

  @override
  String get apiPermissionDenied => '没有操作权限';

  @override
  String get apiQuotaExceeded => '已达到使用额度';

  @override
  String get apiRateLimited => '操作过于频繁';

  @override
  String get apiRefreshSuperseded => '登录凭据已由另一请求更新';

  @override
  String get apiResourceExpired => '资源已过期';

  @override
  String get apiResourceNotFound => '未找到资源';

  @override
  String get apiRevisionConflict => '内容已更新，请重新加载';

  @override
  String get apiServiceUnavailable => '服务尚未就绪';

  @override
  String get apiSessionInvalid => '登录已失效';

  @override
  String get apiSessionRevoked => '登录已失效';

  @override
  String get apiStateConflict => '当前状态不支持此操作';

  @override
  String get apiValidationFormat => '信息格式有误';

  @override
  String get apiValidationInvalid => '输入信息有误';

  @override
  String get apiValidationOutOfRange => '数值超出允许范围';

  @override
  String get apiValidationRequired => '请填写必填信息';

  @override
  String get apiValidationTooLong => '内容超过允许长度';

  @override
  String get apiValidationType => '信息类型有误';

  @override
  String get apiValidationUnknownField => '包含不支持的字段';

  @override
  String get checkConnection => '检查服务连接';

  @override
  String get checkingConnection => '正在检查…';

  @override
  String get connectionReady => '服务已就绪';

  @override
  String get apiUnknownError => '暂时无法完成请求，请稍后重试。';
}
