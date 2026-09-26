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
  String get shellDescription => 'Haruka 的学习空间正在搭建。当前可查看应用环境与服务连接。';

  @override
  String get materialsTitle => '你的学习材料';

  @override
  String get materialsDescription => '小说、课本和试卷将分别进入专属的阅读与学习页面。';

  @override
  String get materialLanguages => '首版材料支持日语和英语。';

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

  @override
  String get authEmail => '邮箱';

  @override
  String get authPassword => '密码';

  @override
  String get authConfirmPassword => '确认密码';

  @override
  String get authShowPassword => '显示密码';

  @override
  String get authHidePassword => '隐藏密码';

  @override
  String get authRequired => '请填写此项';

  @override
  String get authInvalidEmail => '请输入有效邮箱';

  @override
  String get authPasswordMismatch => '两次输入的密码不一致';

  @override
  String get authSignIn => '登录';

  @override
  String get authSigningIn => '正在登录…';

  @override
  String get authCreateAccount => '创建账号';

  @override
  String get authCreatingAccount => '正在提交注册…';

  @override
  String get authLoginTitle => '欢迎回来';

  @override
  String get authLoginHint => '使用你的账号继续学习。';

  @override
  String get authRegisterTitle => '创建账号';

  @override
  String get authRegisterHint => '注册只需邮箱和密码。资料稍后再填写。';

  @override
  String get authForgotPassword => '忘记密码？';

  @override
  String get authBackToLogin => '返回登录';

  @override
  String get authRecoveryTitle => '找回密码';

  @override
  String get authRecoveryHint => '输入注册邮箱，我们会受理找回请求。受理不代表邮件已送达。';

  @override
  String get authRequestRecovery => '提交申请';

  @override
  String get authHeroLogin => '欢迎回来。';

  @override
  String get authHeroRegister => '从这里开始。';

  @override
  String get authHeroRecovery => '找回访问方式。';

  @override
  String get authAdminHero => '管理端，独立登录。';

  @override
  String get authAdminEntry => '管理端入口';

  @override
  String get authAdminWorkspace => '管理端';

  @override
  String get authAdminPublishedNotice => '注册策略保存后由服务端生效；仅显示当前有权管理的操作。';

  @override
  String get authEmailVerificationFact => '邮箱验证已启用';

  @override
  String get authMailRecoveryFact => '邮件找回';

  @override
  String get authAvailable => '可用';

  @override
  String get authUnavailableShort => '暂不可用';

  @override
  String get authRequestingRecovery => '正在受理…';

  @override
  String get authVerifyTitle => '验证邮箱';

  @override
  String get authVerifyHint => '打开邮件中的验证链接完成激活。';

  @override
  String get authVerify => '完成验证';

  @override
  String get authVerifying => '正在验证…';

  @override
  String get authNewPassword => '新密码';

  @override
  String get authCompleteRecovery => '重置密码';

  @override
  String get authResettingPassword => '正在重置…';

  @override
  String get authRegisterReceived => '注册请求已受理';

  @override
  String get authRegisterReceivedHint => '请留意验证邮件。邮件可能尚未送达，暂时无法登录时可稍后重发。';

  @override
  String get authRecoveryReceived => '找回请求已受理';

  @override
  String get authRecoveryReceivedHint => '若账号符合条件，我们会发送找回邮件。请检查收件箱，受理不代表已送达。';

  @override
  String get authVerified => '邮箱验证完成';

  @override
  String get authResetComplete => '密码已重置';

  @override
  String get authRegistrationClosed => '当前暂停新账号注册';

  @override
  String get authServiceUnavailable => '账号服务暂不可用，请稍后重试。';

  @override
  String get authRetry => '重试';

  @override
  String get authWorking => '正在处理…';

  @override
  String get authAdminLoginTitle => '管理端登录';

  @override
  String get authAdminLoginHint => '管理操作需要独立的管理会话。';

  @override
  String get authBrandLine => '让每一次学习，都有清晰的方向。';

  @override
  String get authVerificationToken => '粘贴邮件中的验证链接';

  @override
  String get authRecoveryToken => '粘贴邮件中的重置链接';

  @override
  String get authInvalidActionLink => '请使用本服务邮件中的正确链接';

  @override
  String get authResetTitle => '设置新密码';

  @override
  String get authResetHint => '完成后请用新密码重新登录。';

  @override
  String get authAccount => '账号与安全';

  @override
  String get accountHomeTitle => '我的';

  @override
  String get accountLearningTitle => '学习材料';

  @override
  String get authAccountHint => '在这里管理自己的密码与已登录设备。';

  @override
  String get authSignOut => '退出当前账号';

  @override
  String get authChangePassword => '修改密码';

  @override
  String get authCurrentPassword => '当前密码';

  @override
  String get authPasswordChanged => '密码操作已提交，请用新密码重新登录。';

  @override
  String get authPasswordOutcomeUnknown => '无法确认密码操作结果。请勿重复提交；尝试用新密码登录，必要时使用邮件找回。';

  @override
  String get authDeviceSessions => '已登录设备';

  @override
  String get authRevokeSession => '撤销此设备';

  @override
  String get authRevokeAll => '退出所有设备';

  @override
  String get authSessionCurrent => '当前设备';

  @override
  String get authSessionLastSeen => '最近活动';

  @override
  String get authSessionNever => '尚无活动记录';

  @override
  String get authSessionExpires => '到期时间';

  @override
  String get authLoadMoreSessions => '加载更多会话';

  @override
  String get referenceMaterialsTitle => '材料库';

  @override
  String get referenceMaterialsHint => '这里仅展示可读取的短材料，用于验证选区查询与收藏；完整阅读器在后续阶段提供。';

  @override
  String get referenceJapanese => '日语';

  @override
  String get referenceEnglish => '英语';

  @override
  String get referenceLoadMore => '加载更多';

  @override
  String get referenceNoMaterials => '暂无可读取的参考材料。';

  @override
  String get referenceSelectHint => '在文字中选中已准备词后查询已保存的卡片。';

  @override
  String get referenceQuery => '查询选区';

  @override
  String get referenceNoPreparedCard => '该选区暂无已保存的卡片。';

  @override
  String get referenceSave => '加入收藏';

  @override
  String get referenceSaved => '已保存到你的收藏。';

  @override
  String get referenceOpenCollections => '查看我的收藏';

  @override
  String get referenceCollectionsTitle => '我的收藏';

  @override
  String get referenceNoCollections => '暂无收藏。';

  @override
  String get referenceClose => '关闭';

  @override
  String get referenceRetry => '重试加载';

  @override
  String get referencePartOfSpeech => '词性';

  @override
  String get referenceOtherMeanings => '其它释义';

  @override
  String get referenceExamples => '例句';

  @override
  String get referenceSource => '出处';

  @override
  String get authPendingEmail => '邮箱尚待验证';

  @override
  String get authPendingEmailHint => '请使用验证邮件中的链接。邮件可能尚未送达，可申请重发。';

  @override
  String get authResendVerification => '重发验证邮件';

  @override
  String get authResendReceived => '重发请求已受理，受理不代表邮件已送达。';

  @override
  String get authAdminPolicy => '注册策略';

  @override
  String get authAdminPolicyHint => '现有账号仍可登录与邮件找回；新账号注册由上方开关控制。';

  @override
  String get authRegistrationEnabled => '允许新账号注册';

  @override
  String get authSavePolicy => '保存注册策略';

  @override
  String get authNoAdminPermission => '当前管理会话没有此操作权限。';

  @override
  String get authLoading => '正在验证账号与服务…';

  @override
  String get authUnavailable => '账号服务暂不可用。请检查连接后重试。';

  @override
  String get authCheckAgain => '重新检查';

  @override
  String get authBackToAccount => '返回账号';

  @override
  String get authSessionRevoked => '设备会话已撤销。';

  @override
  String get authNoSessions => '没有可显示的会话。';

  @override
  String get authCheckActivation => '检查验证状态';

  @override
  String get authStillPending => '邮箱仍待验证。请先打开邮件中的验证链接。';

  @override
  String get authSignedOutLocally => '本机登录已清除，但无法确认服务端会话已撤销。重新登录后可在设备会话中撤销它。';

  @override
  String authPasswordLength(int min, int max) {
    return '密码需要 $min 至 $max 个字符';
  }
}
