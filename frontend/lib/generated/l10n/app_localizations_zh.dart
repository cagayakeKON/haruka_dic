// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get apiReauthenticationRequired => '为保护个人凭据，请重新登录后再操作。';

  @override
  String get authManualRecoveryCode => '人工恢复码或安全链接';

  @override
  String get appTitle => 'Haruka';

  @override
  String get home => '主页';

  @override
  String get environment => '环境信息';

  @override
  String get shellTitle => '准备开始学习';

  @override
  String get materialsTitle => '你的学习材料';

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
  String get adminDescription => '此页面暂不可用。';

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
  String get apiAuthScopeRequired => '请更新应用后重新登录';

  @override
  String get apiAuthScopeChanged => '登录身份已变化，请重新确认';

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
  String get authRecoveryManualHint => '提交后由管理员核验身份。通过后你会得到一次性恢复码，再用它设置新密码。';

  @override
  String get authRecoveryAwaitReview => '申请已受理。请等待管理员核验，核验通过后使用一次性恢复码设置新密码。受理不代表已经核验。';

  @override
  String get authRequestRecovery => '提交申请';

  @override
  String get authRequestManualRecovery => '申请人工恢复';

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
  String get authRecoveryClosed => '当前未开放找回';

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
  String referencePublishedNovelCount(int count) {
    return '小说 · $count 份已发布材料';
  }

  @override
  String get referenceCoverFallback => '文';

  @override
  String referenceNovelLanguage(String language) {
    return '小说 · $language';
  }

  @override
  String get referenceReadable => '可阅读';

  @override
  String get referenceReading => '阅读';

  @override
  String get referenceNovel => '小说';

  @override
  String get referencePublishedChapters => '已发布章节';

  @override
  String get referenceSelectedSource => '已选原文';

  @override
  String get referenceAllCollections => '全部收藏';

  @override
  String referenceCollectionCount(int count) {
    return '$count 条收藏';
  }

  @override
  String get referenceWord => '单词';

  @override
  String get referenceCollectionDetail => '收藏详情';

  @override
  String get referenceMeaning => '释义';

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
  String get authAdminPolicyHint => '切换注册或找回方式不会改变已有账号状态，也不会取消已经发出的挑战。';

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
  String get authPendingApproval => '邮箱已验证，正在等待管理员审批。';

  @override
  String get authApprovalRejected => '注册申请已被拒绝。';

  @override
  String get authApprovalRequired => '提交后需要管理员审批，通过前不能登录。';

  @override
  String get adminPolicyOpen => '开放注册';

  @override
  String get adminPolicyRecoveryEither => '邮件或人工';

  @override
  String get adminPolicyRecoveryDisabled => '关闭找回';

  @override
  String get adminRecoveryRequests => '人工恢复';

  @override
  String get adminMenuOrder => '排序（越小越靠前）';

  @override
  String get adminMenuIcon => '导航图标';

  @override
  String get adminMenuOrderError => '请输入 0 到 100000 的排序值。';

  @override
  String get adminAuditAction => '操作类别';

  @override
  String get adminAuditActor => '操作者 ID';

  @override
  String get adminAuditTargetType => '目标类型';

  @override
  String get adminAuditTargetId => '目标 ID';

  @override
  String get adminAuditTargetCode => '目标代码';

  @override
  String get adminAuditFrom => '开始时间（含时区）';

  @override
  String get adminAuditTo => '结束时间（含时区）';

  @override
  String get adminAuditFilter => '筛选';

  @override
  String get adminAuditTimeError => '请输入带时区的有效时间，结束时间不能早于开始时间。';

  @override
  String get adminRecoveryIssue => '核验签发';

  @override
  String get adminRecoveryReject => '拒绝恢复';

  @override
  String get adminRecoveryInPerson => '当面核验';

  @override
  String get adminRecoveryKnownChannel => '已知渠道核验';

  @override
  String get adminRecoveryTokenOnce => '一次性恢复码只显示这一次。请交给账号持有人，管理员不能代设密码。';

  @override
  String get adminRecoveryTokenHidden => '恢复码不会再次显示。';

  @override
  String get adminRecoveryRequested => '待核验';

  @override
  String get adminRecoveryIssued => '已签发';

  @override
  String get adminRecoveryRejected => '已拒绝';

  @override
  String get adminRecoveryConsumed => '已使用';

  @override
  String get adminRecoveryExpired => '已过期';

  @override
  String get adminGovernanceActive => '可登录账号';

  @override
  String get adminGovernancePending => '待启用账号';

  @override
  String get adminGovernanceDisabled => '已停用账号';

  @override
  String get adminGovernanceApprovals => '待审批';

  @override
  String get adminGovernanceRoles => '启用角色';

  @override
  String get adminGovernanceRecoveries => '待核验恢复';

  @override
  String get adminGovernanceRevision => '授权版本';

  @override
  String get adminGovernanceLater => '任务、存储和模型用量仍未开放。';

  @override
  String get adminAuditEmpty => '还没有审计记录';

  @override
  String get adminAuditDetail => '审计详情';

  @override
  String get adminAuditReason => '原因';

  @override
  String get adminAuditRequest => '请求';

  @override
  String get adminAuditMore => '加载更多';

  @override
  String get adminAuditResultAll => '全部结果';

  @override
  String get adminAuditCommitted => '已提交';

  @override
  String get adminAuditAccepted => '已受理';

  @override
  String get adminAuditDenied => '已拒绝';

  @override
  String get adminAuditFailed => '失败';

  @override
  String get adminUserApprove => '通过审批';

  @override
  String get adminUserReject => '拒绝申请';

  @override
  String get authSignedOutLocally => '本机登录已清除，但无法确认服务端会话已撤销。重新登录后可在设备会话中撤销它。';

  @override
  String authPasswordLength(int min, int max) {
    return '密码需要 $min 至 $max 个字符';
  }

  @override
  String get mockLibraryAddFileInfo => '添加文件与信息';

  @override
  String get mockLibraryAiStructureDescription => '使用个人模型整理章节或题目';

  @override
  String get mockLibraryAiStructureEnabled => '已开启';

  @override
  String get mockLibraryAiStructureDisabled => '未开启';

  @override
  String get mockLibraryAiStructureSuggestion => 'AI 结构建议';

  @override
  String get mockLibraryAddPrompt => '添加小说、课本或试卷，开始学习。';

  @override
  String get mockLibraryAll => '全部';

  @override
  String get mockLibraryBackToEdit => '返回修改';

  @override
  String get mockLibraryCancel => '取消';

  @override
  String mockLibraryChapterCount(Object count) {
    return ' · $count 章';
  }

  @override
  String get mockLibraryChooseType => '选择类型';

  @override
  String get mockLibraryChooseFile => '选择文件';

  @override
  String get mockLibraryChooseMaterialFile => '选择材料文件';

  @override
  String get mockLibraryCloseSearch => '关闭搜索';

  @override
  String get mockLibraryConfirmImport => '确认导入';

  @override
  String get mockLibraryDelete => '删除';

  @override
  String mockLibraryDeleteConfirmMessage(Object title) {
    return '「$title」将从材料库移除。已有合法收藏与历史仍保留。';
  }

  @override
  String get mockLibraryDeleteConfirmTitle => '删除材料？';

  @override
  String get mockLibraryDeleteMaterial => '删除材料';

  @override
  String get mockLibraryEnglish => '英语';

  @override
  String get mockLibraryExam => '试卷';

  @override
  String get mockLibraryExamDescription => '整卷作答与评分';

  @override
  String get mockLibraryImport => '导入材料';

  @override
  String mockLibraryImportStep(Object step, Object total) {
    return '步骤 $step / $total';
  }

  @override
  String mockLibraryImportStepType(int step, int total, String type) {
    return '$step / $total · $type';
  }

  @override
  String mockLibraryImportSummary(String type, String title, String language) {
    return '$type · $title · $language';
  }

  @override
  String get mockLibraryJapanese => '日语';

  @override
  String get mockLibraryLearnable => '可学习';

  @override
  String get mockLibraryMaterialLanguage => '材料语言';

  @override
  String get mockLibraryMaterialTypeStep => '材料类型';

  @override
  String get mockLibraryMaterialActions => '材料操作';

  @override
  String mockLibraryMaterialMetadata(Object details, Object language, Object type) {
    return '$type · $language$details';
  }

  @override
  String get mockLibraryMaterialTitle => '材料标题';

  @override
  String mockLibraryMaterialsCount(Object count) {
    return '$count 份材料';
  }

  @override
  String mockLibraryMoreActions(Object title) {
    return '$title更多操作';
  }

  @override
  String get mockLibraryNeedsReview => '待校对';

  @override
  String get mockLibraryNext => '下一步';

  @override
  String get mockLibraryNoFileSelected => '尚未选择文件';

  @override
  String get mockLibraryNoMatches => '没有匹配的材料';

  @override
  String get mockLibraryNoMaterials => '还没有材料';

  @override
  String get mockLibraryEmptyHint => '目前没有可阅读的小说。';

  @override
  String get mockLibraryOpenMaterial => '打开材料';

  @override
  String get mockLibraryNovel => '小说';

  @override
  String get mockLibraryNovelDescription => '按章节阅读';

  @override
  String mockLibraryParsingProgress(Object percent) {
    return '解析中 · $percent%';
  }

  @override
  String get mockLibraryPending => '待处理';

  @override
  String get mockLibraryProcessing => '处理中';

  @override
  String mockLibraryQuestionCount(Object count) {
    return ' · $count 题';
  }

  @override
  String get mockLibraryReadable => '可阅读';

  @override
  String get mockLibraryRecentlyUpdated => '最近更新';

  @override
  String mockLibrarySelectedFile(String name) {
    return '已选文件：$name';
  }

  @override
  String get mockLibraryResetFilters => '重置筛选';

  @override
  String get mockLibrarySearchHint => '搜索标题或语言';

  @override
  String get mockLibrarySearchMaterials => '搜索材料';

  @override
  String get mockLibraryTextbook => '课本';

  @override
  String get mockLibraryTextbookDescription => '按单元学习与练习';

  @override
  String get mockLibraryTitle => '材料库';

  @override
  String get mockLibraryTryAnotherSearch => '试试其他关键词，或清空筛选。';

  @override
  String mockLibraryUnitCount(Object count) {
    return ' · $count 单元';
  }

  @override
  String get mockLibraryViewDetails => '查看详情';

  @override
  String mockLibraryViewMaterial(Object title) {
    return '查看$title';
  }

  @override
  String get mockShellAppTitle => 'Haruka';

  @override
  String get mockShellBack => '返回';

  @override
  String get mockShellEnglish => '英语';

  @override
  String get mockShellExercise => '练习';

  @override
  String get mockShellJapanese => '日语';

  @override
  String get mockShellLibrary => '材料库';

  @override
  String get mockShellNotebooks => '单词本';

  @override
  String get mockShellNotifications => '站内消息';

  @override
  String get mockShellQuery => '查询';

  @override
  String get mockShellSettings => '我的';

  @override
  String get mockExerciseCorrectFeedback => '回答正确 ·「そっと」强调动作轻柔、避免打扰。';

  @override
  String get mockExerciseDiagnosis => '学习诊断';

  @override
  String get mockExerciseDiagnosisTopics => '方向助词 · 语境词义';

  @override
  String get mockExerciseExisting => '已有习题';

  @override
  String get mockExerciseGenerate => '生成 AI 习题';

  @override
  String get mockExerciseHistory => '学习记录';

  @override
  String get mockExerciseIncorrectFeedback => '再看一眼 · 正确答案是「そっと」，强调动作轻柔。';

  @override
  String get mockExerciseMistakes => '错题库';

  @override
  String mockExerciseMistakesCount(int count) {
    return '$count 道待纠正';
  }

  @override
  String get mockExerciseOptionA => 'そっと';

  @override
  String get mockExerciseOptionB => 'きっと';

  @override
  String get mockExerciseOptionC => 'ずっと';

  @override
  String get mockExerciseOptionD => 'もっと';

  @override
  String mockExerciseQuestionProgress(Object current, Object total) {
    return '题目 $current / $total · 日语';
  }

  @override
  String get mockExerciseQuestionText => '猫を起こさないように、ドアを（　）閉めた。';

  @override
  String get mockExerciseQuestionTranslation => '为了不把猫吵醒，轻轻关上门。';

  @override
  String get mockExerciseRetry => '重做';

  @override
  String mockExerciseSampleSummary(int count) {
    return '日语 · $count 道题';
  }

  @override
  String get mockExerciseSampleTitle => '语境中的表达';

  @override
  String get mockExerciseSelectSource => '选择来源';

  @override
  String get mockExerciseStart => '开始练习';

  @override
  String get mockExerciseSubmit => '提交答案';

  @override
  String get mockExerciseTitle => '练习';

  @override
  String get mockNotebookAdd => '添加';

  @override
  String get mockNotebookAddCollection => '添加收藏';

  @override
  String get mockNotebookAll => '全部';

  @override
  String get mockNotebookAllCollections => '全部收藏';

  @override
  String get mockNotebookAudioUnavailable => '音频暂不可用';

  @override
  String get mockNotebookCancel => '取消';

  @override
  String get mockNotebookChooserTitle => '切换与管理词本';

  @override
  String get mockNotebookClose => '关闭';

  @override
  String mockNotebookCollectionCount(int count) {
    return '$count 条收藏';
  }

  @override
  String get mockNotebookChinese => '中文';

  @override
  String get mockNotebookCreate => '新建词本';

  @override
  String get mockNotebookCsv => '单词 CSV';

  @override
  String get mockNotebookDailyWords => '每日单词';

  @override
  String get mockNotebookDelete => '删除';

  @override
  String get mockNotebookDeleteConfirmMessage => '只解除归类，收藏条目与学习状态仍保留。';

  @override
  String get mockNotebookDeleteConfirmTitle => '删除词本？';

  @override
  String get mockNotebookDeleteNotebook => '删除词本';

  @override
  String mockNotebookDeleteSummary(String name, int count) {
    return '$name · $count 条收藏';
  }

  @override
  String get mockNotebookDescription => '简介';

  @override
  String get mockNotebookEmptyHint => '试试其他词形、读音或释义。';

  @override
  String get mockNotebookEmptyTitle => '没有匹配的收藏';

  @override
  String get mockNotebookNoCollections => '还没有收藏';

  @override
  String get mockNotebookNoCollectionsHint => '这里暂时没有已收藏的内容。';

  @override
  String get mockNotebookEnglish => '英语';

  @override
  String get mockNotebookGenerateExercise => '生成 AI 习题';

  @override
  String get mockNotebookInvalidName => '名称不能为空或与现有词本重复';

  @override
  String get mockNotebookJapanese => '日语';

  @override
  String get mockNotebookKindExcerpt => '摘录';

  @override
  String get mockNotebookKindExercise => '习题';

  @override
  String get mockNotebookKindGrammar => '语法';

  @override
  String get mockNotebookKindPhrase => '短语';

  @override
  String get mockNotebookKindSentence => '句子';

  @override
  String get mockNotebookKindWord => '单词';

  @override
  String get mockNotebookLanguage => '语言';

  @override
  String mockNotebookLanguageAndCount(Object count, Object language) {
    return '$count 条收藏 · $language';
  }

  @override
  String get mockNotebookManage => '管理词本';

  @override
  String mockNotebookManageNamed(String name) {
    return '管理$name';
  }

  @override
  String get mockNotebookName => '名称';

  @override
  String mockNotebookReadNamed(String text) {
    return '朗读$text';
  }

  @override
  String get mockNotebookSave => '保存';

  @override
  String get mockNotebookSearchHint => '搜索收藏内容';

  @override
  String get mockNotebookTitle => '单词本';

  @override
  String get mockQueryAgain => '再查一个';

  @override
  String get mockQueryAudioUnavailable => '音频暂不可用';

  @override
  String get mockQueryCamera => '拍照';

  @override
  String get mockQueryCameraPermissionDenied => '无法使用相机，请检查相机权限';

  @override
  String get mockQueryCameraUnavailable => '相机不可用，请从相册选择';

  @override
  String get mockQueryCardKindExcerpt => '摘录';

  @override
  String get mockQueryCardKindExercise => '习题';

  @override
  String get mockQueryCardKindGrammar => '语法';

  @override
  String get mockQueryCardKindPhrase => '短语';

  @override
  String get mockQueryCardKindSentence => '句子';

  @override
  String get mockQueryCardKindWord => '单词';

  @override
  String get mockQueryContextHint => '补充与本次查询有关的上下文';

  @override
  String get mockQueryContextToggle => '补充上下文（可选）';

  @override
  String get mockQueryDesktopImageHint => '可粘贴图片';

  @override
  String get mockQueryExampleCorrection => '批改：昨日、図書館に行きます。';

  @override
  String get mockQueryExampleGrammar => 'に 和 へ 有什么区别？';

  @override
  String get mockQueryExampleTranslation => '翻译：夏の風がそっと頬に触れた。';

  @override
  String get mockQueryExampleWord => 'そっと 是什么意思？';

  @override
  String get mockQueryExamplesTitle => '试试这样查询';

  @override
  String get mockQueryGallery => '相册';

  @override
  String get mockQueryImage => '图片';

  @override
  String get mockQueryImageAttached => '已选择图片';

  @override
  String get mockQueryImageExample => '图片查询';

  @override
  String get mockQueryImageInvalid => '无法读取图片，请重新选择';

  @override
  String get mockQueryImagePreview => '查看图片';

  @override
  String get mockQueryImageRemove => '移除图片';

  @override
  String get mockQueryImageTooLarge => '图片超过大小或像素限制';

  @override
  String get mockQueryImageTooMany => '最多添加 4 张图片';

  @override
  String get mockQueryImageUnanalysed => '图片尚未分析，无法生成学习卡片';

  @override
  String get mockQueryImageUnsupported => '请选择 PNG、JPEG 或 WebP 图片';

  @override
  String get mockQueryInputHint => '输入单词、句子、语法问题，或添加图片…';

  @override
  String get mockQueryInputTooLong => '输入超过 2000 字，请删减后再添加';

  @override
  String get mockQueryLearningLabel => '语言学习';

  @override
  String get mockQueryMobileImageHint => '可选择图片';

  @override
  String get mockQueryReadAloud => '朗读';

  @override
  String get mockQueryBookmarkTitle => '收藏卡片';

  @override
  String get mockQueryBookmarked => '已收藏';

  @override
  String get mockQuerySaveCard => '收藏';

  @override
  String get mockQuerySaved => '已加入收藏';

  @override
  String get mockQueryAlreadySaved => '已在收藏中';

  @override
  String get mockQuerySend => '发送';

  @override
  String get mockQueryRequestFailed => '查询暂时未完成，请重试';

  @override
  String get mockQuerySubtitle => '理解一个词，读懂一句话。';

  @override
  String get mockQueryTitle => '查询';

  @override
  String get mockQueryLanguage => '日语';

  @override
  String get mockQueryMeaningLabel => '释义';

  @override
  String get mockQueryWordMeaning => '轻轻地；悄悄地';

  @override
  String get mockQueryWordUsage => '用于动作轻柔，或不希望打扰别人的场景。';

  @override
  String get mockQueryWordRomanization => 'sotto';

  @override
  String get mockQueryWordPartOfSpeech => '副词';

  @override
  String get mockQueryContextExamples => '语境例句';

  @override
  String get mockQueryWordExampleOne => 'ドアをそっと閉めた。';

  @override
  String get mockQueryWordExampleOneTranslation => '轻轻地关上了门。';

  @override
  String get mockQueryWordExampleTwo => 'そっと手を握った。';

  @override
  String get mockQueryWordExampleTwoTranslation => '轻轻握住了手。';

  @override
  String get mockQueryTranslationLabel => '译文';

  @override
  String get mockQuerySentenceTranslation => '夏风轻轻拂过脸颊。';

  @override
  String get mockQuerySentenceUsage => 'そっと 描绘风拂过脸颊时轻柔的动作，让句子更有画面感。';

  @override
  String get mockQueryGrammarPoint => '语法提示';

  @override
  String get mockQuerySentenceGrammar => '名词 + に + 触れる：触碰到某物。';

  @override
  String get mockQueryGrammarCoreLabel => '核心用法';

  @override
  String get mockQueryGrammarCore => '目的地与移动方向';

  @override
  String get mockQueryGrammarUsage => '「に」强调到达的地点；「へ」强调移动的方向。表示移动的句子中常可互换。';

  @override
  String get mockQueryGrammarNiLabel => 'に · 到达点';

  @override
  String get mockQueryGrammarNiTranslation => '去车站，强调目的地。';

  @override
  String get mockQueryGrammarHeLabel => 'へ · 方向';

  @override
  String get mockQueryGrammarHeTranslation => '往车站去，强调方向。';

  @override
  String get mockQueryCorrectionFocusLabel => '订正重点';

  @override
  String get mockQueryCorrectionFocus => '过去时间需要搭配过去式';

  @override
  String get mockQueryCorrectionOriginalLabel => '原作答';

  @override
  String get mockQueryCorrectionOriginal => '行きます';

  @override
  String get mockQueryCorrectionSuggestedLabel => '建议订正';

  @override
  String get mockQueryCorrectionSuggested => '行きました';

  @override
  String get mockQueryCorrectionSentence => '昨日、図書館に行きました。';

  @override
  String get mockQueryCorrectionExplanation => '「昨日」表示昨天。这里叙述已经发生的动作，应将「行きます」改为过去式「行きました」。';

  @override
  String mockMaterialChapterNumber(int number) {
    return '第 $number 章';
  }

  @override
  String mockMaterialChapterTitle(int number, String title) {
    return '第 $number 章 · $title';
  }

  @override
  String mockMaterialNumberedTitle(String number, String title) {
    return '$number  $title';
  }

  @override
  String mockMaterialUnitTitle(String number, String title) {
    return 'Unit $number · $title';
  }

  @override
  String mockSupportAnswerCardNumber(int number, String mark) {
    return '$number$mark';
  }

  @override
  String get mockSupportAnsweredMark => ' ✓';

  @override
  String get mockSupportEnglish => '英语';

  @override
  String get mockSupportJapanese => '日语';

  @override
  String mockSupportKindLanguage(String kind, String language) {
    return '$kind · $language';
  }

  @override
  String mockSupportLanguageSources(String language, int count) {
    return '语言：$language · 来源 $count 类';
  }

  @override
  String mockSupportNotificationSummary(String status, String detail) {
    return '$status  ·  $detail';
  }

  @override
  String mockSupportProgress(int percent) {
    return '解析中 · $percent%';
  }

  @override
  String mockSupportQuestionPosition(int question) {
    return '题目 $question / 3';
  }

  @override
  String get mockSupportRead => '已读';

  @override
  String mockSupportSelectedSources(int count) {
    return '已选 $count 项内容，相同收藏只计一次。';
  }

  @override
  String mockSupportSpeakWord(String word) {
    return '朗读$word';
  }

  @override
  String mockSupportStep(int step) {
    return '步骤 $step / 2';
  }

  @override
  String get mockSupportUnread => '新消息';

  @override
  String get mockSupportUpdatesEyebrow => 'IN-APP UPDATES';

  @override
  String mockSupportVisibleAnswer(String answer) {
    return '可见参考答案：$answer';
  }

  @override
  String get mockLibraryJobProgress => '任务进度';

  @override
  String get mockShellNavMaterials => '材料';

  @override
  String get mockShellNavNotebooks => '词本';

  @override
  String get mockExerciseSourceDescription => '从词本、教材或错题中选源';

  @override
  String mockMaterialCurrentRevision(int revision) {
    return '当前内容版本：$revision';
  }

  @override
  String get mockMaterialEnglish => '英语';

  @override
  String get mockMaterialJapanese => '日语';

  @override
  String mockMaterialLanguageDetail(String language) {
    return '语言：$language';
  }

  @override
  String mockMaterialStatusDetail(String status) {
    return '状态：$status';
  }

  @override
  String mockMaterialTypeDetail(String type) {
    return '类型：$type';
  }

  @override
  String mockSettingCacheCounts(int explanations, int audio) {
    return '$explanations 份解释 · $audio 段音频';
  }

  @override
  String mockSettingMegabytes(String amount) {
    return '$amount MB';
  }

  @override
  String mockSettingPlaybackRate(String rate) {
    return '$rate×';
  }

  @override
  String get mockMaterialExamPreparationTitle => '试卷准备';

  @override
  String get mockSupportAddCollection => '添加收藏';

  @override
  String get mockSupportAssignToNotebook => '归入单词本';

  @override
  String get mockSupportAudioUnavailable => '音频暂不可用';

  @override
  String get mockSupportCancel => '取消';

  @override
  String get mockSupportCollectionContentField => '内容';

  @override
  String get mockSupportCollectionContextExamples => '语境例句';

  @override
  String get mockSupportCollectionDeleted => '收藏已删除';

  @override
  String get mockSupportCollectionDetailTitle => '收藏详情';

  @override
  String get mockSupportCollectionKindField => '类型';

  @override
  String get mockSupportCollectionMasteryEvidenceHint => '掌握：按有效习题证据计算，不能手动修改。';

  @override
  String get mockSupportCollectionMeaningField => '释义';

  @override
  String get mockSupportCsvChooseUtf8 => '选择 UTF-8 CSV';

  @override
  String get mockSupportCsvConfirmImport => '确认导入';

  @override
  String get mockSupportCsvExampleFilename => '单词.csv';

  @override
  String get mockSupportCsvExportEntries => '导出词条';

  @override
  String get mockSupportCsvExportReadyToast => 'CSV 已生成';

  @override
  String get mockSupportCsvExportScopeHint => '导出全部单词，包含词本归属、释义与个人笔记。';

  @override
  String get mockSupportCsvGenerateExample => '下载单词 CSV';

  @override
  String get mockSupportCsvImportConfirmedToast => '导入已确认';

  @override
  String get mockSupportCsvImportExportTitle => '单词导入与导出';

  @override
  String get mockSupportCsvImportPreview => '导入预览';

  @override
  String get mockSupportCsvPreviewHint => '导入前可预览词条与重复项。';

  @override
  String get mockSupportCsvPreviewSummary => '导入预览';

  @override
  String get mockSupportCsvShowPreview => '查看导入预览';

  @override
  String get mockSupportCsvTitle => '单词 CSV';

  @override
  String get mockCsvCreateDuplicates => '创建新词条';

  @override
  String get mockCsvDefaultLanguage => '缺少语言时使用';

  @override
  String get mockCsvDownloadStarted => '已交给浏览器下载';

  @override
  String get mockCsvDuplicateAction => '重复项处理';

  @override
  String get mockCsvEmptyWord => '空词形';

  @override
  String get mockCsvExcludeErrors => '排除错误行后导入';

  @override
  String get mockCsvExistingDuplicate => '词表中已有';

  @override
  String get mockCsvFileDuplicate => '文件内重复';

  @override
  String get mockCsvFileReadFailed => '无法读取 CSV 文件';

  @override
  String get mockCsvMergeDuplicates => '补全空白字段';

  @override
  String get mockCsvProblemEmptyFile => '文件为空';

  @override
  String get mockCsvProblemFieldTooLong => '字段过长';

  @override
  String get mockCsvProblemInvalidDate => '时间格式无效';

  @override
  String get mockCsvProblemInvalidEscape => '转义协议不支持';

  @override
  String get mockCsvProblemInvalidExerciseControl => '习题控制值无效';

  @override
  String get mockCsvProblemInvalidLanguage => '语言仅支持日语或英语';

  @override
  String get mockCsvProblemInvalidLocator => '来源定位需要重新验证';

  @override
  String get mockCsvProblemInvalidQuotes => '引号格式无效';

  @override
  String get mockCsvProblemInvalidStatus => '来源状态无效';

  @override
  String get mockCsvProblemInvalidTags => '标签 JSON 无效';

  @override
  String get mockCsvProblemInvalidUtf8 => '文件不是有效的 UTF-8';

  @override
  String get mockCsvProblemInvalidVersion => 'CSV 版本不支持';

  @override
  String get mockCsvProblemInvalidWordbooks => '词本 JSON 无效';

  @override
  String get mockCsvProblemMissingWord => '缺少词形';

  @override
  String get mockCsvProblemMissingWordColumn => '缺少 word 列';

  @override
  String get mockCsvProblemRepeatedColumn => '表头列重复';

  @override
  String get mockCsvProblemRowWidth => '列数与表头不符';

  @override
  String get mockCsvProblemTooLarge => '文件超过 10 MB';

  @override
  String get mockCsvProblemTooManyRows => '记录超过 10000 行';

  @override
  String get mockCsvReadyRow => '可导入';

  @override
  String get mockCsvSaveFailed => 'CSV 保存失败';

  @override
  String get mockCsvSaved => 'CSV 已保存';

  @override
  String get mockCsvSkipDuplicates => '跳过重复';

  @override
  String get mockCsvSystemFlowOpened => '已打开系统保存选项';

  @override
  String get mockCsvSourceUnbound => '来源回跳未恢复';

  @override
  String mockCsvPreviewCounts(int total, int newCount, int duplicates, int errors) {
    return '共 $total 行 · 新词 $newCount · 重复 $duplicates · 错误 $errors';
  }

  @override
  String mockCsvRowLabel(int number, String word) {
    return '第 $number 行 · $word';
  }

  @override
  String mockCsvImportResult(int added, int merged, int skipped, int excluded) {
    return '新增 $added · 补全 $merged · 跳过 $skipped · 排除 $excluded';
  }

  @override
  String get mockSupportDailyWordsAddedToday => '当日加入';

  @override
  String get mockSupportDailyWordsDate => '日期';

  @override
  String get mockSupportDailyWordsEmptyHint => '选择其他日期查看。';

  @override
  String get mockSupportDailyWordsEmptyTitle => '这天没有加入单词';

  @override
  String mockSupportDailyWordsScopeDescription(String timezone) {
    return '$timezone · 全部单词本，重复归类只计一次';
  }

  @override
  String get mockSupportDailyWordsTitle => '每日单词';

  @override
  String get mockSupportDailyWordsWordCountUnit => '个单词';

  @override
  String get mockSupportDiagnosisChooseSource => '选择习题来源';

  @override
  String get mockSupportDiagnosisDirectionEvidence => '教材 Unit 02 的有效作答显示，「に / へ」仍容易混淆。';

  @override
  String get mockSupportDiagnosisDirectionFocus => '方向助词值得再练';

  @override
  String get mockSupportDiagnosisDirectionShortTitle => '方向助词';

  @override
  String get mockSupportDiagnosisEvidenceDisclaimer => '依据可靠作答和来源形成诊断。';

  @override
  String get mockSupportDiagnosisNextStep => '下一步';

  @override
  String get mockSupportDiagnosisNextStepTitle => '选源练习';

  @override
  String get mockSupportDiagnosisNextStepDescription => '从教材或当前错题明确选源，预览后再生成针对性习题。';

  @override
  String get mockSupportDiagnosisRecentSevenDays => '最近 7 天';

  @override
  String get mockSupportDiagnosisReturnToTextbook => '回到教材 →';

  @override
  String get mockSupportDiagnosisStrengthDescription => '在有语境的词义选择题里，你能留意句子的情绪与动作方式。';

  @override
  String get mockSupportDiagnosisStrengths => '亮点';

  @override
  String get mockSupportDiagnosisStrengthTitle => '语境词义';

  @override
  String get mockSupportDiagnosisTitle => '学习诊断';

  @override
  String get mockSupportDiagnosisWeakness => '薄弱点';

  @override
  String get mockSupportEditNotes => '编辑与笔记';

  @override
  String get mockSupportExamAnswerCard => '答题卡';

  @override
  String get mockSupportExamAnswered => '已答';

  @override
  String mockSupportExamAnsweredCount(int answered, int total) {
    return '已答 $answered / $total';
  }

  @override
  String get mockSupportExamBackToPreparation => '试卷准备';

  @override
  String get mockSupportExamConfirmSubmit => '确认交卷';

  @override
  String get mockSupportExamContinueAnswering => '继续作答';

  @override
  String get mockSupportExamDemoScoringHint => '查看评分与解释。';

  @override
  String get mockSupportExamDuration => '考试时长 60 分钟';

  @override
  String get mockSupportExamInProgressSummary => '整卷作答 · 60 分钟';

  @override
  String get mockSupportExamLanguageKnowledge => '语言知识';

  @override
  String get mockSupportExamLeave => '暂时离开';

  @override
  String get mockSupportExamLeaveBody => '离开前会保存当前答案和标记，稍后可继续作答。';

  @override
  String get mockSupportExamLeaveTitle => '暂时离开考试？';

  @override
  String get mockSupportExamListening => '听力';

  @override
  String get mockSupportExamMarkQuestion => '标记题目';

  @override
  String get mockSupportExamMarkForLater => '标记稍后检查';

  @override
  String get mockSupportExamMarked => '已标记';

  @override
  String get mockSupportExamMobileTitle => '模拟考试';

  @override
  String get mockSupportExamNextQuestion => '下一题';

  @override
  String get mockSupportExamOptionCalm => '平静温和';

  @override
  String get mockSupportExamOptionComplex => '十分复杂';

  @override
  String get mockSupportExamOptionForgotPromise => '忘记了约定';

  @override
  String get mockSupportExamOptionHeardBroadcast => '听到了广播';

  @override
  String get mockSupportExamOptionLibraryEntrance => '图书馆门口';

  @override
  String get mockSupportExamOptionMetTeacher => '遇见了老师';

  @override
  String get mockSupportExamOptionParkEntrance => '公园入口';

  @override
  String get mockSupportExamOptionRapid => '迅速猛烈';

  @override
  String get mockSupportExamOptionRememberedFriend => '想起了旧友';

  @override
  String get mockSupportExamOptionSchoolHall => '学校大厅';

  @override
  String get mockSupportExamOptionStationSouthExit => '车站南口';

  @override
  String get mockSupportExamOptionSurprising => '令人惊讶';

  @override
  String get mockSupportExamPaperTitle => 'N2 模拟试卷';

  @override
  String get mockSupportExamPreviousQuestion => '上一题';

  @override
  String mockSupportExamQuestionNumber(int number) {
    return '第 $number 题';
  }

  @override
  String get mockSupportExamQuestionListening => '听力题组 1：两人最后决定在哪里见面？';

  @override
  String get mockSupportExamQuestionMeaning => '「穏やか」に最接近的意思是？';

  @override
  String get mockSupportExamQuestionReading => '文中主人公为什么停下脚步？';

  @override
  String get mockSupportExamResultTitle => '考试结果';

  @override
  String get mockSupportExamReading => '阅读理解';

  @override
  String get mockSupportExamSave => '保存';

  @override
  String get mockSupportExamSaveAndLeave => '保存并离开';

  @override
  String get mockSupportExamSaved => '已保存';

  @override
  String get mockSupportExamSaveDraft => '保存草稿';

  @override
  String get mockSupportExamSessionTitle => '整卷作答';

  @override
  String get mockSupportExamSubmit => '交卷';

  @override
  String mockSupportExamSubmitAnsweredBody(int answered, int total) {
    return '已答 $answered / $total。交卷后答案锁定，再查看复盘。';
  }

  @override
  String get mockSupportExamSubmitConfirmBody => '交卷后答卷锁定，才可查看参考答案与复盘。';

  @override
  String get mockSupportExamSubmitConfirmTitle => '确认交卷？';

  @override
  String get mockSupportExamSubmittedReview => '已交卷 · 成绩复盘';

  @override
  String get mockSupportExamUnanswered => '未答';

  @override
  String get mockSupportExamUnmarkQuestion => '取消标记';

  @override
  String get mockSupportExamUnsaved => '尚未保存';

  @override
  String get mockSupportExerciseAllowRepeatedSource => '候选不足时允许同一来源多题';

  @override
  String get mockSupportExerciseAllOwnWords => '全部本人单词';

  @override
  String get mockSupportExerciseBackToEdit => '修改来源';

  @override
  String get mockSupportExerciseBuilderChooseContent => '想练习哪些内容？';

  @override
  String get mockSupportExerciseBuilderConfirmSettings => '设置与确认';

  @override
  String get mockSupportExerciseBuilderEnglish => '英语';

  @override
  String get mockSupportExerciseBuilderHeadline => '生成 AI 习题';

  @override
  String get mockSupportExerciseBuilderJapanese => '日语';

  @override
  String get mockSupportExerciseBuilderReviewHint => '请确认来源和题目设置；条件变化需重新预览。';

  @override
  String get mockSupportExerciseBuilderStudyLanguage => '学习语言';

  @override
  String get mockSupportExerciseBuilderTitle => '生成习题';

  @override
  String mockSupportExerciseCandidateCount(int count) {
    return '$count 项内容';
  }

  @override
  String mockSupportExerciseCandidateShortage(int available, int count) {
    return '当前 $available 项来源少于计划的 $count 题。可减少题量，或允许同一来源出多题。';
  }

  @override
  String get mockSupportExerciseChooseCollections => '选择收藏条目';

  @override
  String get mockSupportExerciseChooseDiagnosis => '选择诊断薄弱点';

  @override
  String get mockSupportExerciseChooseMistakeRange => '选择错题范围';

  @override
  String get mockSupportExerciseChooseNotebook => '选择单词本';

  @override
  String get mockSupportExerciseConfirmGeneration => '确认生成习题';

  @override
  String get mockSupportExerciseCountFive => '5 题';

  @override
  String get mockSupportExerciseCountOne => '1 题';

  @override
  String get mockSupportExerciseCountTen => '10 题';

  @override
  String get mockSupportExerciseGenerationAcceptedToast => '习题生成已受理';

  @override
  String get mockSupportExerciseNextToSettings => '下一步 · 设置与确认';

  @override
  String get mockSupportExerciseNoCandidates => '当前范围没有可用内容。';

  @override
  String get mockSupportExerciseNeedConcreteSource => '请先选定具体来源。';

  @override
  String get mockSupportExerciseNeedQuestionType => '至少选择一种题型。';

  @override
  String mockSupportExercisePreviewSummary(String language, String types, int count) {
    return '$language · $types · $count 题';
  }

  @override
  String get mockSupportExercisePreviewTitle => '出题范围';

  @override
  String get mockSupportExerciseQuestionCount => '题量';

  @override
  String get mockSupportExerciseQuestionType => '题型';

  @override
  String get mockSupportExerciseSettingsTitle => '题目设置';

  @override
  String get mockSupportExerciseCurrentMistakes => '当前待纠正';

  @override
  String get mockSupportExerciseBookmarkedMistakes => '已收藏的当前错题';

  @override
  String mockSupportExerciseUnitLabel(String number, String title) {
    return 'Unit $number · $title';
  }

  @override
  String get mockSupportExerciseSourceCollection => '手选收藏';

  @override
  String get mockSupportExerciseSourceCollectionDescription => '逐条选择词句或卡片';

  @override
  String get mockSupportExerciseSourceDiagnosis => '诊断薄弱点';

  @override
  String get mockSupportExerciseSourceDiagnosisDescription => '围绕已有诊断练习';

  @override
  String get mockSupportExerciseSourceMistakes => '错题';

  @override
  String get mockSupportExerciseSourceMistakesDescription => '按当前状态或收藏选题';

  @override
  String get mockSupportExerciseSourceNotebook => '单词本';

  @override
  String get mockSupportExerciseSourceNotebookDescription => '按词本选择单词';

  @override
  String get mockSupportExerciseSourceTextbook => '教材';

  @override
  String get mockSupportExerciseSourceTextbookDescription => '选择一个学习单元';

  @override
  String get mockSupportExerciseTypeContextFill => '语境填空';

  @override
  String get mockSupportExerciseTypeMeaningChoice => '词义选择';

  @override
  String get mockSupportExerciseTypeTranslationJudgement => '翻译判断';

  @override
  String get mockSupportJobsConnected => '进度已连接';

  @override
  String get mockSupportJobsNovelDemo => '小说 · 解析任务';

  @override
  String get mockSupportJobsNovelTitle => '雨上がり';

  @override
  String get mockSupportJobsOpenMaterial => '打开材料 →';

  @override
  String get mockSupportJobsTitle => '任务进度';

  @override
  String get mockSupportMistakeAiExerciseSource => 'AI 习题 · 日常的细节';

  @override
  String get mockSupportMistakeBookmarkAction => '收藏错题';

  @override
  String get mockSupportMistakeBookmarked => '已收藏';

  @override
  String get mockSupportMistakeBookmarkedStatus => '已收藏错题';

  @override
  String get mockSupportMistakeChooseAsSource => '从错题选择习题来源';

  @override
  String get mockSupportMistakeDetailTitle => '错题详情';

  @override
  String get mockSupportMistakeDirectionError => '把「へ」解释为动作对象';

  @override
  String get mockSupportMistakeDirectionTopic => '移动方向与目的地';

  @override
  String get mockSupportMistakeExamSource => 'N2 模拟试卷 · 阅读';

  @override
  String get mockSupportMistakeGenerateTargeted => '针对它出题';

  @override
  String get mockSupportMistakeHistoricalExamples => '历史记录';

  @override
  String get mockSupportMistakeImproved => '已经改进';

  @override
  String get mockSupportMistakeLibraryTitle => '错题库';

  @override
  String get mockSupportMistakeListTitle => '错题列表';

  @override
  String get mockSupportMistakeMeaningError => '误选了「迅速猛烈」';

  @override
  String get mockSupportMistakeMeaningTopic => '语境词义：穏やか';

  @override
  String get mockSupportMistakeNeedsCorrection => '当前待纠正';

  @override
  String get mockSupportMistakePreviousAnswer => '当时的作答';

  @override
  String get mockSupportMistakeReferenceError => '遗漏上一段的指代';

  @override
  String get mockSupportMistakeReferenceTopic => '阅读中的指代关系';

  @override
  String get mockSupportMistakeRemoveBookmark => '取消收藏';

  @override
  String get mockSupportMistakeTextbookSource => '日语的日常表达 · Unit 02';

  @override
  String get mockSupportMistakeTopicColumn => '考察点';

  @override
  String get mockSupportMistakeSourceColumn => '来源';

  @override
  String get mockSupportMistakeStatusColumn => '当前状态';

  @override
  String get mockSupportMistakeBookmarkColumn => '收藏';

  @override
  String get mockSupportMistakeViewColumn => '查看';

  @override
  String get mockSupportNotificationsHeading => '消息';

  @override
  String get mockSupportNotificationsMarkAllRead => '全部标为已读';

  @override
  String get mockSupportNotificationsEmpty => '暂无消息';

  @override
  String get mockSupportNotificationsReadFailed => '标记已读失败，请重试';

  @override
  String get mockSupportNotificationsTitle => '站内消息';

  @override
  String mockSupportNotificationsUnreadCount(int count) {
    return '$count 条未读';
  }

  @override
  String mockSupportNotificationTodayTime(String time) {
    return '今天 $time';
  }

  @override
  String mockSupportNotificationYesterdayTime(String time) {
    return '昨天 $time';
  }

  @override
  String mockSupportNotificationMonthDay(int month, int day) {
    return '$month 月 $day 日';
  }

  @override
  String get mockSupportPersonalNotes => '个人笔记';

  @override
  String get mockSupportReturnToSource => '回到原文 →';

  @override
  String get mockSupportSave => '保存';

  @override
  String get mockSettingAccountUpdatesGroup => '账号与动态';

  @override
  String get mockSettingAvatarGlyph => '遥';

  @override
  String get mockSettingBirthYearOptional => '出生年份（可选）';

  @override
  String get mockSettingClearAccountLocalCache => '清除此账号本机缓存';

  @override
  String get mockSettingCurrentLearningLanguage => '当前学习语言';

  @override
  String get mockSettingDisplayName => '显示名';

  @override
  String get mockSettingExplanationLanguage => '解释语言';

  @override
  String get mockSettingJobs => '任务进度';

  @override
  String get mockSettingJobsSubtitle => '导入与生成结果';

  @override
  String get mockSettingLearningLevelSample => '日语 · 中级';

  @override
  String get mockSettingLearningPreferencesGroup => '学习偏好';

  @override
  String get mockSettingLocalAvailable => '本机可用';

  @override
  String get mockSettingModelDataGroup => '模型与数据';

  @override
  String get mockSettingMyTitle => '我的';

  @override
  String get mockSettingNotifications => '站内消息';

  @override
  String get mockSettingNotificationsSubtitle => '任务和结果提醒';

  @override
  String get mockSettingReduceMotion => '减少动态';

  @override
  String get mockSettingSaveAppearance => '保存外观';

  @override
  String get mockSettingSaveLanguageOptions => '保存语言选项';

  @override
  String get mockSettingSaveProfile => '保存资料';

  @override
  String get profileGuideTitle => '确认学习资料';

  @override
  String get profileGuideBody => '显示名、解释语言、学习语言和时区都可以稍后填写。跳过不会保存，也不会记成已完成。';

  @override
  String get profileGuideSkip => '跳过';

  @override
  String get serviceSwitchWebFixed => 'Web 使用当前部署，不能在应用内更换服务地址。';

  @override
  String get serviceSwitchConfirm => '退出并使用此服务';

  @override
  String get serviceSwitchWarning => '将退出当前服务并清理本机缓存。';

  @override
  String get serviceSwitchFailed => '未能连接新服务，当前已退出。';

  @override
  String get serviceSwitchProbeFailed => '未能连接该服务。';

  @override
  String get serviceSwitchRevokeFailed => '本机已退出。原服务上的会话可能尚未撤销。';

  @override
  String serviceSwitchIdentity(String instance, String version) {
    return '实例 $instance，接口 $version';
  }

  @override
  String get mockSettingSavedResults => '已保存成果';

  @override
  String get mockSettingTheme => '主题';

  @override
  String get mockProfileAiConsent => '允许 AI 使用可选个人资料';

  @override
  String get mockProfileChangeAvatar => '更换头像';

  @override
  String get mockProfileFallbackName => '学习者';

  @override
  String get mockProfileGenderFemale => '女';

  @override
  String get mockProfileGenderMale => '男';

  @override
  String get mockProfileGenderNonBinary => '非二元';

  @override
  String get mockProfileGenderOptional => '性别（可选）';

  @override
  String get mockProfileGenderPreferNot => '不愿说明';

  @override
  String get mockProfileGenderSelfDescribe => '自我描述';

  @override
  String get mockProfileGenderUnset => '未填写';

  @override
  String mockProfileGreeting(String name) {
    return '你好，$name。';
  }

  @override
  String get mockProfileTimezone => '时区';

  @override
  String get mockProfileTimezoneShanghai => '上海 / Asia/Shanghai';

  @override
  String get mockProfileTimezoneTokyo => '东京 / Asia/Tokyo';

  @override
  String get mockProfileTimezoneUtc => 'UTC';

  @override
  String mockSettingLanguageOptionsSubtitle(String learning, String explanation) {
    return '学习：$learning · 解释：$explanation';
  }

  @override
  String get mockSettingLanguageOptions => '语言选项';

  @override
  String get mockSettingMoreGroup => '更多';

  @override
  String get mockSettingSecurityAccount => '安全与账号';

  @override
  String get mockProfileAvatarTitle => '头像';

  @override
  String get mockProfileAvatarUpdated => '头像已更新';

  @override
  String get mockProfileCurrentAvatar => '当前头像';

  @override
  String get mockSettingProfile => '个人资料';

  @override
  String get mockSettingProfileSubtitle => '显示名与头像';

  @override
  String get mockAdminAccountCount => '账号数';

  @override
  String get mockAdminAccountLabel => '管理账号';

  @override
  String get mockAdminAccountName => '小遥';

  @override
  String get mockAdminAccountRecovery => '账号恢复';

  @override
  String get mockAdminActionColumn => '操作';

  @override
  String get mockAdminActionKindColumn => '操作类别';

  @override
  String get mockAdminActualCallsColumn => '调用次数';

  @override
  String get mockAdminAdminNavigation => '管理端导航';

  @override
  String get mockAdminApprovalExample => '需审批';

  @override
  String get mockAdminApplyPolicy => '应用策略';

  @override
  String mockAdminAttempt(int count) {
    return '$count 次';
  }

  @override
  String mockAdminAttempts(int count) {
    return '$count 次';
  }

  @override
  String get mockAdminAudience => '管理端';

  @override
  String get mockAdminAudienceColumn => '受众';

  @override
  String get mockAdminAudioGeneration => '音频生成';

  @override
  String get mockAdminAudit => '审计诊断';

  @override
  String get mockAdminAvatar => '遥';

  @override
  String get mockAdminAwaitingSubmission => '待提交';

  @override
  String get mockAdminBackToClient => '返回用户端登录';

  @override
  String get mockAdminCapabilityColumn => '能力';

  @override
  String get mockAdminChangePassword => '修改密码';

  @override
  String get mockAdminChooseLater => '待选择';

  @override
  String get mockAdminClientAudience => '用户端';

  @override
  String get mockAdminClientLogin => '进入用户端登录';

  @override
  String get mockAdminClientNavigation => '用户端导航';

  @override
  String get mockAdminClose => '关闭';

  @override
  String get mockAdminClosedExample => '关闭新注册';

  @override
  String get mockAdminCompleted => '已完成';

  @override
  String get mockAdminConfirmPassword => '确认新密码';

  @override
  String get mockAdminCurrentPassword => '当前密码';

  @override
  String get mockAdminCurrentPasswordIncorrect => '当前密码不正确';

  @override
  String get mockAdminCurrentPolicy => '当前策略';

  @override
  String get mockAdminCurrentSession => '当前管理端会话';

  @override
  String get mockAdminDefault => '默认';

  @override
  String get mockAdminEmailColumn => '登录邮箱';

  @override
  String get mockAdminEmailRecovery => '邮件恢复';

  @override
  String get mockAdminEmailVerification => '邮箱验证';

  @override
  String get mockAdminInactive => '未启用';

  @override
  String get mockAdminInvalidCredentials => '邮箱或密码不正确';

  @override
  String get mockAdminJobReferenceColumn => '任务引用';

  @override
  String get mockAdminJobSummary => '任务摘要';

  @override
  String get mockAdminJobs => '任务与资源';

  @override
  String get mockAdminKnownUsageColumn => '已知用量';

  @override
  String get mockAdminLearnerA => '学习者 A';

  @override
  String get mockAdminLearnerB => '学习者 B';

  @override
  String get mockAdminLearnerRole => '学习者';

  @override
  String get mockAdminLoginAction => '登录管理端';

  @override
  String get mockAdminLoginEmail => '登录邮箱';

  @override
  String get mockAdminLoginEmailExample => 'example@demo.test';

  @override
  String get mockAdminLoginEmailInvalid => '请输入有效邮箱';

  @override
  String get mockAdminLoginEntry => '管理端登录';

  @override
  String get mockAdminLoginEyebrow => 'ADMIN / HARUKA';

  @override
  String get mockAdminLoginHero => '管理端，独立登录。';

  @override
  String get mockAdminLoginPassword => '密码';

  @override
  String get mockAdminLoginPasswordHint => '输入密码';

  @override
  String get mockAdminLoginPasswordInvalid => '密码至少 6 位';

  @override
  String get mockAdminLoginTitle => '登录管理端';

  @override
  String get mockAdminLogout => '退出管理端';

  @override
  String get mockAdminManagementPermissions => '管理权限';

  @override
  String get mockAdminManualRecovery => '人工恢复';

  @override
  String get mockAdminMaterialParse => '材料解析';

  @override
  String get mockAdminMembersColumn => '成员';

  @override
  String get mockAdminMenuDiagnosis => '学习诊断';

  @override
  String get mockAdminMenuExercises => 'AI 习题';

  @override
  String get mockAdminMenuLibrary => '材料库';

  @override
  String get mockAdminMenuMistakes => '错题库';

  @override
  String get mockAdminMenuNotebooks => '单词本';

  @override
  String get mockAdminMenuQuery => '查询';

  @override
  String get mockAdminMenuSettings => '设置';

  @override
  String get mockAdminMenus => '页面与菜单';

  @override
  String get mockAdminModelCall => '模型调用';

  @override
  String get mockAdminNeedsAction => '需处理';

  @override
  String get mockAdminNeedsAttention => '待关注';

  @override
  String get mockAdminNeedsConfiguration => '待配置';

  @override
  String get mockAdminNewPassword => '新密码';

  @override
  String get mockAdminNoUsers => '没有匹配的账号';

  @override
  String get mockAdminNormal => '正常';

  @override
  String get mockAdminOnlineDemoSession => '运维账号 · 在线会话';

  @override
  String get mockAdminOpenNavigation => '打开管理导航';

  @override
  String get mockAdminOperator => '运维账号';

  @override
  String get mockAdminOverview => '运维概览';

  @override
  String get mockAdminOwnDevice => '本人设备';

  @override
  String get mockAdminPartialAudioSeconds => '部分音频秒数';

  @override
  String get mockAdminPasswordAllDevices => '修改密码后，所有设备需要重新登录。';

  @override
  String get mockAdminPasswordFlow => '修改密码流程';

  @override
  String get mockAdminPasswordMismatch => '两次输入的新密码不一致';

  @override
  String get mockAdminPasswordRelogin => '修改密码后需要重新登录。';

  @override
  String get mockAdminPasswordTooShort => '新密码至少需要 8 个字符';

  @override
  String get mockAdminPasswordUnchanged => '新密码不能与当前密码相同';

  @override
  String get mockAdminPasswordUpdated => '密码已更新，请重新登录';

  @override
  String get mockAdminPendingApproval => '待审批';

  @override
  String get mockAdminPendingJobs => '待处理任务';

  @override
  String get mockAdminPermissionChanges => '授权变化';

  @override
  String get mockAdminPolicy => '注册策略';

  @override
  String get mockAdminPolicyApplied => '策略已更新';

  @override
  String get mockAdminPreview => '预览';

  @override
  String get mockAdminPreviewPolicy => '预览策略变化';

  @override
  String get mockAdminProtected => '受保护';

  @override
  String get mockAdminPrototypeNotice => '管理操作需保持在线。';

  @override
  String get mockAdminProviderAttempts => '供应商调用次数';

  @override
  String get mockAdminPublishAfterValidation => '验证后发布';

  @override
  String get mockAdminQueueAlert => '任务队列有 2 项等待重试';

  @override
  String get mockAdminReadExample => '已读取';

  @override
  String get mockAdminReadRegistrationPolicy => '注册策略读取';

  @override
  String get mockAdminRegistrationEntry => '注册入口';

  @override
  String get mockAdminRegistrationMode => '注册方式';

  @override
  String get mockAdminRequestSuccess => '请求成功率';

  @override
  String get mockAdminRestricted => '受限';

  @override
  String get mockAdminResultColumn => '结果';

  @override
  String get mockAdminRetryCheck => '重试检查';

  @override
  String get mockAdminRibbon => '管理端';

  @override
  String get mockAdminRoleAlert => '角色更新待核对';

  @override
  String get mockAdminRoleColumn => '角色';

  @override
  String get mockAdminRoleGrantPreview => '角色授权预览';

  @override
  String get mockAdminRolePreviewOnly => '保存角色变更前请核对授权范围。';

  @override
  String mockAdminRoleSummary(String role) {
    return '$role角色';
  }

  @override
  String get mockAdminRoles => '角色与权限';

  @override
  String get mockAdminSearchUsers => '搜索账号';

  @override
  String get mockAdminSavePassword => '保存新密码';

  @override
  String get mockAdminSecurityNav => '账号安全';

  @override
  String get mockAdminSessionRevocation => '会话撤销';

  @override
  String get mockAdminStageColumn => '阶段';

  @override
  String get mockAdminStatusColumn => '状态';

  @override
  String get mockAdminSubmittedExample => '已提交';

  @override
  String get mockAdminSummary => '运维摘要';

  @override
  String get mockAdminSummaryStatus => '当前状态：正常。';

  @override
  String get mockAdminSuperRole => '超级管理员';

  @override
  String get mockAdminSupportRole => '支持人员';

  @override
  String get mockAdminSwitchToClient => '切换到用户端';

  @override
  String get mockAdminTargetScopeColumn => '目标范围';

  @override
  String get mockAdminTextModel => '文本模型';

  @override
  String get mockAdminTimeColumn => '时间';

  @override
  String get mockAdminTypeColumn => '类型';

  @override
  String get mockAdminUnknownUsageAttempts => '用量未提供的 attempts';

  @override
  String get mockAdminUnknownUsageColumn => '未知用量';

  @override
  String get mockAdminUsage => '模型用量';

  @override
  String get mockAdminUserColumn => '用户';

  @override
  String get mockAdminUserList => '用户列表';

  @override
  String get mockAdminUsers => '用户与会话';

  @override
  String get mockAdminVerifyWhenEnabled => '启用后校验';

  @override
  String get mockAdminViewJobs => '查看任务';

  @override
  String get mockAdminViewOperationalSummary => '查看运维摘要';

  @override
  String get mockAdminViewRoles => '查看角色';

  @override
  String get mockAdminViewSummary => '查看摘要';

  @override
  String get mockAdminVisibleProviderCategories => '可见供应商类别';

  @override
  String get mockAdminVisibleWhenAuthorized => '授权后显示';

  @override
  String get mockAdminVisionModel => '视觉模型';

  @override
  String get mockAdminWaitingOwnCredential => '等待本人凭据';

  @override
  String get mockAdminYesterday => '昨天';

  @override
  String get mockAdminPolicyPreviewTitle => '策略变更预览';

  @override
  String mockAdminTokenCount(String count) {
    return '$count Token';
  }

  @override
  String get mockAdminTts => '语音合成';

  @override
  String get mockSettingAudioCacheLimit => '音频副本上限';

  @override
  String get mockSettingContextBudget => '前后文预算';

  @override
  String get mockSettingIdentityUnavailableInMock => '当前无法执行此操作';

  @override
  String get mockSettingLocalSpace => '本机空间';

  @override
  String get mockSettingPersonalApiKey => '个人 API Key';

  @override
  String get mockSettingPlaybackSpeed => '播放倍速';

  @override
  String get mockSettingSaveCacheLimits => '保存本机上限';

  @override
  String get mockMaterialCancel => '取消';

  @override
  String get mockMaterialChapterPreparationAccepted => '本章准备已受理';

  @override
  String mockMaterialChapterProgress(int analysis, int audio, int total) {
    return '解析 $analysis/$total · 朗读 $audio/$total';
  }

  @override
  String mockMaterialChapterCountOf(int chapter, int total) {
    return '第 $chapter 章 / $total 章';
  }

  @override
  String mockMaterialChapterFooter(int chapter, int total) {
    return '$chapter / $total';
  }

  @override
  String get mockMaterialStartPreparation => '开始准备';

  @override
  String get mockSettingClearCacheConfirmTitle => '清除此账号本机缓存？';

  @override
  String get mockSettingSaveSettings => '保存设置';

  @override
  String get mockSettingSettingsSaved => '已保存';

  @override
  String get mockProfileSavedTimezoneFailed => '个人资料已保存，时区未保存，请重试';

  @override
  String get mockProfileBirthYearInvalid => '请输入有效的出生年份';

  @override
  String mockSettingLanguageLevelSummary(String language, String level) {
    return '$language · $level';
  }

  @override
  String get mockSettingViewSession => '查看会话';

  @override
  String get mockMaterialBackToEdit => '返回修改';

  @override
  String get mockMaterialListeningCandidateMatchDescription => '候选题组 1：两人最后决定在哪里见面？';

  @override
  String get mockMaterialReviewListeningScript => '校对听力稿';

  @override
  String get mockAuthBackToLoginDemo => '返回登录';

  @override
  String get mockAuthBrand => 'haruka';

  @override
  String get mockAuthClearSignal => 'CLEAR SIGNAL';

  @override
  String get mockAuthConfirmPasswordPlaceholder => '再次输入密码';

  @override
  String get mockAuthConfirmRequired => '请再次输入密码';

  @override
  String get mockAuthDesktopConfirmPlaceholder => '再次输入密码';

  @override
  String get mockAuthDesktopEmail => '登录邮箱';

  @override
  String get mockAuthDesktopEmailPlaceholder => 'example@demo.test';

  @override
  String get mockAuthDesktopLoginTitle => '登录账号';

  @override
  String get mockAuthDesktopPasswordPlaceholder => '输入密码';

  @override
  String get mockAuthDesktopRegisterTitle => '创建账号';

  @override
  String get mockAuthDesktopSubmitRegister => '创建账号';

  @override
  String get mockAuthEmailRequired => '请输入邮箱';

  @override
  String get mockAuthEnterWorkspace => '进入学习空间';

  @override
  String get mockAuthForgotPasswordDesktop => '忘记密码';

  @override
  String get mockAuthHeroDescription => '把自己的小说、课本与试卷，变成可阅读、理解和练习的语言学习空间。';

  @override
  String get mockAuthHideConfirmPassword => '隐藏确认密码';

  @override
  String get mockAuthMobileEmailPlaceholder => 'name@example.com';

  @override
  String get mockAuthMobilePasswordPlaceholder => '输入密码';

  @override
  String get mockAuthNextStep => '下一步';

  @override
  String get mockAuthNoAccount => '还没有账号？';

  @override
  String get mockAuthPasswordLength => '密码须为 15–128 个字符';

  @override
  String get mockAuthPasswordLengthHint => '15–128 个字符，可包含空格';

  @override
  String get mockAuthPasswordRequired => '请输入密码';

  @override
  String get mockAuthPersonalWorkspace => '个人学习空间';

  @override
  String get mockAuthProbe => '检查地址';

  @override
  String get mockAuthProbeComplete => '地址格式有效';

  @override
  String get mockAuthRecoverAccount => '找回账号';

  @override
  String get mockAuthRecoveryIntro => '输入登录邮箱，提交找回申请。';

  @override
  String get mockAuthRecoveryReceived => '找回申请已受理';

  @override
  String get mockAuthRegistrationAcceptedDesktop => '注册请求已受理';

  @override
  String get mockAuthServiceConstraint => '不能包含账号密码、查询参数或片段。';

  @override
  String get mockAuthServiceConnectionTitle => '服务连接';

  @override
  String get mockAuthServiceField => 'Haruka 服务地址';

  @override
  String get mockAuthServiceInvalid => '请输入有效的 HTTPS 服务地址';

  @override
  String get mockAuthServicePlaceholder => 'https://your-haruka.example';

  @override
  String get mockAuthServiceTitle => '服务地址';

  @override
  String get mockAuthSetPassword => '设置密码';

  @override
  String get mockAuthShowConfirmPassword => '显示确认密码';

  @override
  String get mockAuthViewResult => '提交申请';

  @override
  String get mockMaterialAiExplanation => 'AI 解析';

  @override
  String get mockMaterialAiExplanationDescription => '逐句译文、意群与语法释义';

  @override
  String get mockMaterialAnalysisMode => '解析';

  @override
  String get mockMaterialAnalysisModeHint => '点击句子看解析，长按可选词查询。';

  @override
  String get mockMaterialChapterAfterRain => '雨停之后';

  @override
  String get mockMaterialChapterBeyondWindow => '窓の向こう';

  @override
  String get mockMaterialChapterLetterToFuture => '写给未来的你';

  @override
  String get mockMaterialChapterSeasideMailbox => '海边的邮筒';

  @override
  String get mockMaterialDeletedMessage => '材料已删除';

  @override
  String get mockMaterialDetailsTitle => '材料详情';

  @override
  String get mockMaterialNovelFamiliarHandwritingSentence => '見覚えのある文字を見て、私は思わず微笑んだ。';

  @override
  String get mockMaterialNovelLetterOnDeskSentence => '机の上には、一通の手紙が置かれていた。';

  @override
  String get mockMaterialNovelMorningLightSentence => '朝の光が、白いカーテンを通して部屋に広がった。';

  @override
  String get mockMaterialNovelSummerWindSentence => '窓を開けると、夏の風がそっと頬に触れた。';

  @override
  String get mockMaterialNovelUnfamiliarWordsSentence => 'まだ知らない言葉にも、どこか懐かしい響きがある。';

  @override
  String get mockMaterialPreparationCacheOptions => '缓存内容 · 可多选';

  @override
  String mockMaterialPreparationReadyCount(int ready, int total) {
    return '$ready/$total 句本机就绪';
  }

  @override
  String mockMaterialPreparationPreparedCount(int prepared, int total) {
    return '$prepared/$total 句已准备';
  }

  @override
  String get mockMaterialPreparationPaused => '已暂停，已完成内容保留。';

  @override
  String get mockMaterialPausePreparation => '暂停准备';

  @override
  String get mockMaterialContinuePreparation => '继续准备';

  @override
  String get mockMaterialPreparationComplete => '本章准备完成';

  @override
  String get mockMaterialOriginalText => '原文';

  @override
  String get mockMaterialTranslation => '译文';

  @override
  String get mockMaterialPreviousSentence => '上一句';

  @override
  String get mockMaterialNextSentence => '下一句';

  @override
  String mockMaterialSentencePosition(int current, int total) {
    return '第 $current / $total 句';
  }

  @override
  String get mockMaterialNovelMorningLightTranslation => '晨光穿过白色窗帘，洒满房间。';

  @override
  String get mockMaterialNovelMorningLightRubySegments =>
      '朝~あさ|の~|光~ひかり|が、~|白い~しろい|カーテンを~|通して~とおして|部屋~へや|に~|広がった~ひろがった|。~';

  @override
  String get mockMaterialNovelSummerWindTranslation => '打开窗户，夏风轻轻拂过脸颊。';

  @override
  String get mockMaterialNovelSummerWindRubySegments =>
      '窓~まど|を~|開ける~あける|と、~|夏~なつ|の~|風~かぜ|がそっと~|頬~ほほ|に~|触れた~ふれた|。~';

  @override
  String get mockMaterialNovelLetterOnDeskTranslation => '桌上放着一封信。';

  @override
  String get mockMaterialNovelLetterOnDeskRubySegments =>
      '机~つくえ|の~|上~うえ|には、~|一通~いっつう|の~|手紙~てがみ|が~|置かれていた~おかれていた|。~';

  @override
  String get mockMaterialNovelFamiliarHandwritingTranslation => '看见熟悉的字迹，我不由得微笑。';

  @override
  String get mockMaterialNovelFamiliarHandwritingRubySegments =>
      '見覚え~みおぼえ|のある~|文字~もじ|を~|見て~みて|、~|私~わたし|は~|思わず~おもわず|微笑んだ~ほほえんだ|。~';

  @override
  String get mockMaterialNovelUnfamiliarWordsTranslation => '那些还不认识的词语，也有种令人怀念的回响。';

  @override
  String get mockMaterialNovelUnfamiliarWordsRubySegments =>
      'まだ~|知らない~しらない|言葉~ことば|にも、どこか~|懐かしい~なつかしい|響き~ひびき|がある。~';

  @override
  String mockMaterialSentenceSource(String title, int chapter, String chapterTitle) {
    return '$title · 第 $chapter 章 · $chapterTitle';
  }

  @override
  String get mockMaterialListenOriginal => '朗读原句';

  @override
  String get mockMaterialPauseOriginal => '暂停朗读';

  @override
  String get mockMaterialCollectSentence => '收藏';

  @override
  String get mockMaterialCollectedSentence => '已收藏';

  @override
  String get mockMaterialBookmarkLabel => '书签';

  @override
  String get mockMaterialPrepareChapter => '准备本章';

  @override
  String get mockMaterialReadingMode => '阅读';

  @override
  String get mockMaterialReadingModeHint => '长按一句，点选词汇后查询。';

  @override
  String get mockMaterialSelectChapter => '选择章节';

  @override
  String get mockMaterialSentenceAudio => '逐句朗读';

  @override
  String get mockMaterialSentenceAudioDescription => '单句与连续朗读共用';

  @override
  String get mockMaterialStartLearning => '开始学习';

  @override
  String get mockMaterialStartReading => '开始阅读';

  @override
  String get mockMaterialUnavailableMessage => '材料已删除或不可读取';

  @override
  String get mockMaterialUnavailableTitle => '材料不可用';

  @override
  String get mockMaterialViewExamPreparation => '查看试卷准备';

  @override
  String get mockSettingAccountLanguageGroup => '账号与语言';

  @override
  String get mockSettingAppearance => '外观设置';

  @override
  String get mockSettingAppearanceSubtitle => '主题与动态';

  @override
  String get mockSettingCancel => '取消';

  @override
  String get mockSettingClear => '清理';

  @override
  String get mockSettingClearCacheConfirmMessage => '只清理本机副本；已保存成果仍可重新取得。';

  @override
  String get mockSettingCacheCleared => '本机缓存已清理';

  @override
  String get mockSettingCacheOperationFailed => '缓存操作失败，请重试';

  @override
  String get mockSettingCacheUpdateRequired => '本机缓存由较新版本创建，请更新应用后重试';

  @override
  String get mockSettingCacheWriterUnavailable => '本机缓存正由另一窗口使用，请返回已打开的窗口';

  @override
  String get cacheRevalidating => '正在重新确认访问，请稍候';

  @override
  String mockSettingCacheClearPartial(int count) {
    return '$count 段音频仍待清理';
  }

  @override
  String get mockSettingDarkMode => '深色';

  @override
  String get mockSettingEnglish => '英语';

  @override
  String get mockSettingFollowSystem => '跟随系统';

  @override
  String get mockSettingFontSize => '字号';

  @override
  String get mockSettingJapanese => '日语';

  @override
  String get mockSettingLastNinetyDays => '90 天';

  @override
  String get mockSettingLastSevenDays => '7 天';

  @override
  String get mockSettingLastThirtyDays => '30 天';

  @override
  String get mockSettingLightMode => '明亮';

  @override
  String get mockSettingLocalCache => '本机缓存';

  @override
  String get mockSettingLocalCacheSubtitle => '阅读与音频';

  @override
  String get mockSettingModelDeviceGroup => '模型与设备';

  @override
  String get mockSettingModelUsage => '模型用量';

  @override
  String get mockSettingModelUsageSubtitle => '调用次数与 Token';

  @override
  String get mockSettingPersonalModel => '个人模型';

  @override
  String get mockSettingPersonalModelSubtitle => '模型与 API Key';

  @override
  String get mockSettingQueryContext => '查询与上下文';

  @override
  String get mockSettingQueryContextSubtitle => '前后文预算与取文范围';

  @override
  String get mockSettingReadingDisplayGroup => '阅读与显示';

  @override
  String get mockSettingReadingPreferences => '阅读偏好';

  @override
  String get mockSettingReadingPreferencesSubtitle => '字体、字号与阅读主题';

  @override
  String get mockSettingReadingPreviewSentence => '朝の光が、白いカーテンを通して部屋に広がった。';

  @override
  String get mockSettingSecurityAccountSubtitle => '会话与退出';

  @override
  String get mockSettingServiceConnection => '服务连接';

  @override
  String get mockSettingServiceConnectionSubtitle => '当前部署与连接状态';

  @override
  String get mockSettingSimplifiedChinese => '简体中文';

  @override
  String get mockSettingSpeech => '朗读与声音';

  @override
  String get mockSettingSpeechSubtitle => '声音和播放倍速';

  @override
  String get mockSettingTextCacheLimit => '解释副本上限';

  @override
  String get mockLearningPracticeBookmark => '收藏题目';

  @override
  String get mockLearningPracticeBookmarkConfirm => '确认收藏';

  @override
  String get mockLearningPracticeBookmarkHint => '保存完整题目和当前可见内容，可选单词本归类。';

  @override
  String get mockLearningPracticeConfirm => '确认答案';

  @override
  String get mockLearningPracticeCorrect => '回答正确';

  @override
  String get mockLearningPracticeExplanation => '「は」提示句子的话题。';

  @override
  String get mockLearningPracticeOptionDirection => '表示移动方向';

  @override
  String get mockLearningPracticeOptionJoin => '连接并列句';

  @override
  String get mockLearningPracticeOptionPast => '表示过去时间';

  @override
  String get mockLearningPracticeOptionTopic => '提示话题';

  @override
  String get mockLearningPracticeQuestion => '「わたしは学生です」中的「は」有什么作用？';

  @override
  String get mockLearningPracticeRetry => '重新作答';

  @override
  String get mockLearningPracticeSubtitle => 'Unit 01 · 初次见面';

  @override
  String get mockLearningPracticeTitle => '课后题';

  @override
  String get mockLearningPracticeBackToTextbook => '课本学习';

  @override
  String get mockLearningPracticeUnit2Explanation => '「へ」标示移动的方向。';

  @override
  String get mockLearningPracticeUnit2OptionDirection => '移动方向';

  @override
  String get mockLearningPracticeUnit2OptionObject => '动作对象';

  @override
  String get mockLearningPracticeUnit2OptionReason => '动作原因';

  @override
  String get mockLearningPracticeUnit2OptionRelation => '所属关系';

  @override
  String get mockLearningPracticeUnit2Question => '「駅へ行きます」中的「へ」主要表示什么？';

  @override
  String get mockLearningPracticeUnit2Subtitle => 'Unit 02 · 一起去车站';

  @override
  String get mockLearningPracticeUnit3Explanation => '「ください」在这里表达礼貌请求。';

  @override
  String get mockLearningPracticeUnit3OptionFinished => '我已吃完';

  @override
  String get mockLearningPracticeUnit3OptionRequest => '请给我';

  @override
  String get mockLearningPracticeUnit3OptionWait => '请稍等';

  @override
  String get mockLearningPracticeUnit3OptionWelcome => '欢迎回来';

  @override
  String get mockLearningPracticeUnit3Question => '在咖啡馆点餐时，「ください」通常表达什么？';

  @override
  String get mockLearningPracticeUnit3Subtitle => 'Unit 03 · 在咖啡馆';

  @override
  String get mockLearningPracticeWrong => '这题选 A';

  @override
  String get mockLearningResultAnswerStatus => '答卷状态';

  @override
  String get mockLearningResultAlreadySaved => '已收藏此题';

  @override
  String get mockLearningResultBackToPrep => '试卷准备';

  @override
  String get mockLearningResultCorrectCount => '答对题数';

  @override
  String get mockLearningResultHeadline => '已交卷。';

  @override
  String get mockLearningResultLanguageCategory => '语言知识';

  @override
  String get mockLearningResultListeningCategory => '听力';

  @override
  String get mockLearningResultNeedsReview => '需要回看的题目';

  @override
  String get mockLearningResultNotebooksUpdated => '已更新词本归类';

  @override
  String get mockLearningResultObjective => '客观题';

  @override
  String mockLearningResultQuestionLabel(int number, String category) {
    return '第 $number 题 · $category';
  }

  @override
  String get mockLearningResultReadingCategory => '阅读';

  @override
  String mockLearningResultReference(String answer) {
    return '参考答案：$answer';
  }

  @override
  String get mockLearningResultReturnLibrary => '返回书库';

  @override
  String get mockLearningResultReview => '逐题复盘';

  @override
  String get mockLearningResultSaved => '已收藏';

  @override
  String get mockLearningResultSelectionAudioUnavailable => '音频暂不可用';

  @override
  String get mockLearningResultSelectionAdjust => '调整范围';

  @override
  String get mockLearningResultSelectionAdjustHelp => '可在原文拖选，或在这里调整字词边界。';

  @override
  String get mockLearningResultSelectionClose => '收起选区工具';

  @override
  String get mockLearningResultSelectionEnd => '终点';

  @override
  String get mockLearningResultSelectionInvalidRange => '终点需要在起点之后';

  @override
  String get mockLearningResultSelectionQuery => '查询';

  @override
  String get mockLearningResultSelectionRead => '朗读整句';

  @override
  String get mockLearningResultSelectionStart => '起点';

  @override
  String get mockLearningResultSelectionTitle => '选句学习';

  @override
  String get mockLearningResultSelectionTooMany => '每次最多查询 3 组，请减少选择';

  @override
  String get mockLearningResultSelectionWhole => '查询整句';

  @override
  String get mockLearningResultSubmitted => '已交卷';

  @override
  String get mockLearningResultSummary => '3 道题 · 本次作答结果';

  @override
  String get mockLearningResultTitle => '考试结果';

  @override
  String get mockLearningResultUnanswered => '未作答';

  @override
  String get mockLearningResultViewMistakes => '查看错题库';

  @override
  String mockLearningResultYourChoice(String answer) {
    return '你的选择：$answer';
  }

  @override
  String get mockLearningWordBackToSource => '回到原文 →';

  @override
  String get mockLearningWordEditTitle => '编辑收藏';

  @override
  String get mockLearningWordMastery => '学习中';

  @override
  String get mockLearningWordNotebookSave => '保存归类';

  @override
  String mockLearningWordSourceDate(String source, String date) {
    return '$source · $date 加入';
  }

  @override
  String get mockLearningWordTitle => '收藏详情';

  @override
  String get mockMaterialPauseContinuousPlayback => '暂停连续朗读';

  @override
  String get mockMaterialContinuousPlayback => '连续朗读';

  @override
  String get mockMaterialNovelSelectionTitle => '选句学习';

  @override
  String get mockMaterialNovelSelectionWholeSentence => '查询整句';

  @override
  String get mockMaterialNovelReadSentence => '朗读整句';

  @override
  String get mockMaterialNovelAdjustRange => '调整范围';

  @override
  String get mockMaterialNovelRangeStart => '起点';

  @override
  String get mockMaterialNovelRangeEnd => '终点';

  @override
  String mockMaterialNovelBoundaryOption(int position, String token) {
    return '$position · $token';
  }

  @override
  String get mockMaterialNovelQueryResultTitle => '查询结果';

  @override
  String get mockMaterialNovelNoQueryResult => '暂无查询结果';

  @override
  String get mockMaterialNovelWindowWord => '窓';

  @override
  String get mockMaterialNovelWindowReading => 'まど';

  @override
  String get mockMaterialNovelWindowMeaning => '窗户';

  @override
  String get mockMaterialContentsTooltip => '目录';

  @override
  String get mockMaterialTypographyTooltip => '排版';

  @override
  String get mockMaterialReadingFontSize => '阅读字号';

  @override
  String get mockMaterialRemoveBookmark => '取消书签';

  @override
  String get mockMaterialAddBookmark => '添加书签';

  @override
  String get mockMaterialChapterContents => '章节目录';

  @override
  String get mockMaterialSentenceAnalysisTitle => '句子解析';

  @override
  String get mockMaterialSentenceTranslationSummerWind => '夏风轻轻拂过脸颊。';

  @override
  String get mockMaterialQuerySelection => '查询选中内容';

  @override
  String get mockMaterialSelectionQueryHint => '点选词汇后可查询；完整结果可收藏。';

  @override
  String get mockMaterialClose => '关闭';

  @override
  String get mockMaterialQuery => '查询';

  @override
  String get mockMaterialTextbookUnitFirstMeeting => '初次见面';

  @override
  String get mockMaterialTextbookUnitToStation => '一起去车站';

  @override
  String get mockMaterialTextbookUnitAtCafe => '在咖啡馆';

  @override
  String get mockMaterialTextbookTopicConversation => '会话：よろしくお願いします';

  @override
  String get mockMaterialTextbookTopicVocabulary => '词汇：姓名与职业';

  @override
  String get mockMaterialTextbookTopicGrammar => '语法：は 与 です';

  @override
  String get mockMaterialTextbookTopicExercise => '课后练习：3 题';

  @override
  String get mockMaterialTextbookUnitTwoTopicText => '课文：駅までの道';

  @override
  String get mockMaterialTextbookUnitTwoTopicVocabulary => '词汇：方向与交通';

  @override
  String get mockMaterialTextbookUnitTwoTopicGrammar => '语法：に / へ';

  @override
  String get mockMaterialTextbookUnitTwoTopicExercise => '课后练习：4 题';

  @override
  String get mockMaterialTextbookUnitThreeTopicConversation => '会话：注文をお願いします';

  @override
  String get mockMaterialTextbookUnitThreeTopicExamples => '例句与译文';

  @override
  String get mockMaterialTextbookUnitThreeTopicGrammar => '语法：ください';

  @override
  String get mockMaterialTextbookUnitThreeTopicExercise => '课后练习：3 题';

  @override
  String get mockMaterialTextbookConversationSubtitle => '会话与课文';

  @override
  String get mockMaterialTextbookBackToUnit => '回到单元';

  @override
  String mockMaterialTextbookSource(String unit) {
    return '出处：$unit';
  }

  @override
  String get mockMaterialTextbookVocabularySubtitle => '词汇与释义';

  @override
  String get mockMaterialTextbookGrammarSubtitle => '用法与例句';

  @override
  String get mockMaterialTextbookExerciseSubtitle => '逐题练习';

  @override
  String get mockMaterialTextbookConversationExample => 'よろしくお願いします。\n请多关照。';

  @override
  String get mockMaterialTextbookVocabularyExample => '私 · わたし · 我\n先生 · せんせい · 老师';

  @override
  String get mockMaterialTextbookGrammarExample => '「は」标记主题，「です」构成礼貌判断。';

  @override
  String get mockMaterialTextbookExerciseHint => '选择答案并提交后查看反馈。';

  @override
  String get mockMaterialTextbookUnitTwoTextExample => '駅まで一緒に行きましょう。\n我们一起去车站吧。';

  @override
  String get mockMaterialTextbookUnitTwoGrammarExample => '駅へ行きます。\n「へ」表示移动方向。';

  @override
  String get mockMaterialTextbookUnitTwoMobileGrammar => '駅へ行きます。\n「へ」表示移动的方向。';

  @override
  String get mockMaterialTextbookUnitTwoExampleStation => '駅';

  @override
  String get mockMaterialTextbookUnitTwoExampleStationMeaning => '车站';

  @override
  String get mockMaterialTextbookUnitTwoExampleRight => '右';

  @override
  String get mockMaterialTextbookUnitTwoExampleRightMeaning => '右';

  @override
  String get mockMaterialTextbookUnitTwoExampleLeft => '左';

  @override
  String get mockMaterialTextbookUnitTwoExampleLeftMeaning => '左';

  @override
  String get mockMaterialTextbookUnitThreeMobileConversation => 'コーヒーを一つください。\n请给我一杯咖啡。';

  @override
  String get mockMaterialTextbookUnitThreeDesktopConversation => 'コーヒーをください。\n请给我一杯咖啡。';

  @override
  String get mockMaterialTextbookUnitThreeMobileGrammar => 'コーヒーをください。\n「ください」表达礼貌请求。';

  @override
  String get mockMaterialTextbookUnitThreeDesktopGrammar => 'ケーキをください。\n「ください」表达礼貌请求。';

  @override
  String get mockMaterialTextbookUnitThreeExampleOrder => '注文';

  @override
  String get mockMaterialTextbookUnitThreeExampleOrderMeaning => '点单';

  @override
  String get mockMaterialTextbookUnitThreeExampleWater => '水';

  @override
  String get mockMaterialTextbookUnitThreeExampleWaterMeaning => '水';

  @override
  String get mockMaterialTextbookUnitThreeExampleCoffee => 'コーヒー';

  @override
  String get mockMaterialTextbookUnitThreeExampleCoffeeMeaning => '咖啡';

  @override
  String mockMaterialTextbookReadWord(String word) {
    return '朗读$word';
  }

  @override
  String get mockMaterialTextbookPlaybackTitle => '朗读';

  @override
  String get mockMaterialTextbookPlaybackPlaying => '播放中';

  @override
  String get mockMaterialTextbookPlaybackPaused => '已暂停';

  @override
  String get mockMaterialTextbookPlaybackFinished => '播放完成';

  @override
  String get mockMaterialTextbookPlaybackOnce => '单次朗读';

  @override
  String get mockMaterialTextbookPlaybackPause => '暂停';

  @override
  String get mockMaterialTextbookPlaybackResume => '继续';

  @override
  String get mockMaterialTextbookPlaybackReplay => '重新播放';

  @override
  String get mockMaterialTextbookPlaybackSpeed => '语速';

  @override
  String get mockMaterialTextbookPlaybackStop => '停止';

  @override
  String get mockMaterialStartExercise => '开始练习';

  @override
  String get mockMaterialTextbookJapaneseLabel => '课本 · 日语';

  @override
  String get mockMaterialUnitContents => '单元目录';

  @override
  String mockMaterialTextbookAvailableUnitCount(int count) {
    return '$count 个可用单元';
  }

  @override
  String get mockMaterialTextbookUnitSections => '课文 · 词汇 · 语法 · 练习';

  @override
  String get mockMaterialUnitContentTitle => '单元内容';

  @override
  String get mockMaterialOpenContentHint => '点击查看内容';

  @override
  String get mockMaterialDoUnitExercises => '做课后题';

  @override
  String get mockMaterialTextbookTitle => '课本';

  @override
  String get mockMaterialConfirmCandidateMatch => '确认候选匹配';

  @override
  String get mockMaterialQuestionNumbersAndScores => '题号与分值';

  @override
  String get mockMaterialExtractedNeedsReview => '已提取 · 待校对';

  @override
  String get mockMaterialListeningTranscript => '听力文字稿';

  @override
  String get mockMaterialScriptMatched => '已确认脚本与题组';

  @override
  String get mockMaterialScriptMatchPending => '待确认脚本与题组';

  @override
  String get mockMaterialPrivateSpeechAudio => '朗读音频';

  @override
  String get mockMaterialAudioGenerated => '已生成';

  @override
  String get mockMaterialAudioPending => '待生成';

  @override
  String get mockMaterialWaitingForScriptConfirmation => '等待脚本确认';

  @override
  String get mockMaterialPreparationChecklist => '准备清单';

  @override
  String get mockMaterialListeningPreparationRequired => '听力准备完成后即可开考。';

  @override
  String get mockMaterialOriginalQuestionCount => '原卷题量';

  @override
  String get mockMaterialMinutesLabel => '分钟';

  @override
  String get mockMaterialGenerateListeningAudioMock => '生成听力音频';

  @override
  String get mockMaterialConfirmVersionAndStart => '确认版本并开考';

  @override
  String get mockMaterialIncludedSampleQuestions => '题目';

  @override
  String get mockMaterialSampleTimeLimit => '分钟 · 答题时限';

  @override
  String get mockMaterialNeedsReviewStatus => '待校对';

  @override
  String get mockMaterialExamStatus => '试卷状态';

  @override
  String get mockMaterialReviewListeningCandidate => '校对听力候选';

  @override
  String get mockMaterialExamScriptReviewNotice => '请核对脚本内容与题组、小题关系，确认后可生成听力音频。';

  @override
  String get mockMaterialExamScriptCandidateTitle => '候选文字稿 · 题组 1';

  @override
  String get mockMaterialExamScriptCandidateText => '駅の南口で待ち合わせましょう。午後三時に会いましょう。';

  @override
  String get mockMaterialExamScriptCandidateLink => '候选关联：听力题组 1 / 小题 01';

  @override
  String get mockMaterialExamScriptVerified => '我已核对脚本与题目对应关系';

  @override
  String mockMaterialExamScriptCandidateLinkForItem(String number) {
    return '候选关联：听力题组 1 / 小题 $number';
  }

  @override
  String mockMaterialExamDesktopCandidateGroup(String number) {
    return '题组：听力 · 第 $number 题';
  }

  @override
  String get mockMaterialExamDesktopCandidateTitle => '文字稿候选';

  @override
  String get mockMaterialExamDesktopCandidateText => '明日は駅の南口で会いましょう。';

  @override
  String get mockMaterialExamDesktopCandidateSource => '来源：试卷正文 · 听力题组 1。';

  @override
  String get mockMaterialExamDesktopScriptVerified => '我已核对脚本与题组、小题的对应关系';

  @override
  String get mockMaterialExamDesktopConfirmMatch => '确认匹配';

  @override
  String get mockMaterialExamChangeBinding => '调整关联';

  @override
  String get mockMaterialExamRejectCandidate => '拒绝候选';

  @override
  String get mockMaterialExamBoundQuestion => '关联小题';

  @override
  String mockMaterialExamBoundQuestionOption(String number) {
    return '小题 $number';
  }

  @override
  String get mockMaterialExamReviewQuestions => '校对题号与分值';

  @override
  String mockMaterialExamQuestionEntry(int number) {
    return '第 $number 题';
  }

  @override
  String get mockMaterialExamQuestionNumber => '题号';

  @override
  String get mockMaterialExamQuestionGroup => '题组';

  @override
  String get mockMaterialExamQuestionScore => '分值';

  @override
  String get mockMaterialExamGroupLanguage => '语言知识';

  @override
  String get mockMaterialExamGroupReading => '阅读';

  @override
  String get mockMaterialExamGroupListening => '听力';

  @override
  String get mockMaterialExamQuestionNumberInvalid => '请输入大于 0 的题号';

  @override
  String get mockMaterialExamQuestionNumberDuplicate => '题号不能重复';

  @override
  String get mockMaterialExamQuestionScoreInvalid => '请输入大于 0 的分值';

  @override
  String get mockMaterialExamListeningGroupRequired => '至少需要一道听力题';

  @override
  String get mockMaterialExamReviewCancel => '取消';

  @override
  String get mockMaterialExamReviewConfirm => '确认校对';

  @override
  String get mockMaterialExamQuestionsReviewed => '已校对';

  @override
  String get mockMaterialExamCandidateRejected => '候选已拒绝';

  @override
  String get mockMaterialExamDesktopQuestionStep => '题号、题组与分值';

  @override
  String get mockMaterialExamDesktopNeedsQuestionReview => '待人工校对';

  @override
  String get mockMaterialExamDesktopScriptStep => '听力脚本与题组候选';

  @override
  String get mockMaterialExamDesktopConfirmed => '已确认';

  @override
  String get mockMaterialExamDesktopAudioStep => '听力音频';

  @override
  String get mockMaterialExamDesktopAudioMissing => '未生成';

  @override
  String get mockMaterialExamDesktopAudioReady => '已就绪';

  @override
  String get mockMaterialExamContinueSession => '继续作答';

  @override
  String get mockMaterialGenerateAudioMock => '生成音频';

  @override
  String get mockMaterialConfirmAndFreezeVersion => '确认并冻结版本';

  @override
  String get mockMaterialSampleExamAnswerHint => '交卷后查看答案。';

  @override
  String get mockSettingInterfaceLanguage => '界面语言';

  @override
  String get mockSettingNativeLanguages => '母语（可多选）';

  @override
  String get mockSettingTargetLanguages => '学习语言（可多选）';

  @override
  String get mockSettingLearningLevel => '自评水平';

  @override
  String get mockSettingLevelUnset => '未填写';

  @override
  String get mockSettingLevelBeginner => '初学';

  @override
  String get mockSettingLevelBasic => '初级';

  @override
  String get mockSettingLevelIntermediate => '中级';

  @override
  String get mockSettingLevelAdvanced => '进阶';

  @override
  String get mockSettingLearningGoals => '学习目标';

  @override
  String get mockSettingGoalReading => '阅读';

  @override
  String get mockSettingGoalTextbook => '教材';

  @override
  String get mockSettingGoalExam => '考试';

  @override
  String get mockSettingGoalListening => '听力';

  @override
  String get mockSettingGoalSpeaking => '口语';

  @override
  String get mockSettingGoalWriting => '写作';

  @override
  String get mockSettingGoalVocabulary => '词汇';

  @override
  String get mockSettingGoalGrammar => '语法';

  @override
  String get mockSettingSaveGoals => '保存学习目标';

  @override
  String get mockSettingReadingFont => '阅读字体';

  @override
  String get mockSettingSerifFont => '衬线字体';

  @override
  String get mockSettingSansFont => '无衬线字体';

  @override
  String get mockSettingLineHeight => '行高';

  @override
  String get mockSettingReadingTheme => '阅读主题';

  @override
  String get mockSettingSepiaTheme => '暖纸色';

  @override
  String get mockSettingReadingPreview => '阅读预览';

  @override
  String get settingMotionHint => '降低位移与弹跳';

  @override
  String get settingAppearancePreviewTitle => '一页故事，一点新发现。';

  @override
  String get settingAppearancePreviewBody => '阅读、解释和作答会沿用同一套色彩与文字层级。';

  @override
  String get mockSettingSaveReading => '保存阅读偏好';

  @override
  String get mockSettingContextRange => '取文范围';

  @override
  String get settingContextIntro => '查询会携带当前句和前后文，帮助理解词义与指代。';

  @override
  String get settingContextBudgetHint =>
      '支持 1,000–64,000 tokens。Token 是模型计算文字的单位，当前完整句另计；内容不足时不会凑满。';

  @override
  String settingContextBudgetSummary(String budget) {
    return '最多 $budget tokens 前后文';
  }

  @override
  String get settingContextAvailability => '保存的偏好会在查询功能开放后使用，已有结果不会改变。';

  @override
  String get mockSettingSaveQuery => '保存查询偏好';

  @override
  String get mockSettingBudgetInvalid => '请输入 1000 至 64000 之间的数值';

  @override
  String get mockSettingProvider => '供应商';

  @override
  String get mockSettingOpenRouter => 'OpenRouter';

  @override
  String get mockSettingGemini => 'Gemini';

  @override
  String get mockSettingTextCapability => '文本';

  @override
  String get mockSettingVisionCapability => '视觉';

  @override
  String get mockSettingSpeechCapability => '朗读';

  @override
  String get mockSettingDefaultModel => '默认模型';

  @override
  String get mockSettingSaveModel => '保存模型偏好';

  @override
  String get mockSettingConfigureKey => '配置 API Key';

  @override
  String get mockSettingRemoveKey => '移除 API Key';

  @override
  String get mockSettingKeyConfigured => '已配置';

  @override
  String get mockSettingKeyUnconfigured => '未配置';

  @override
  String get mockSettingKeyRequired => '请输入 API Key';

  @override
  String get mockSettingSaveKey => '保存 API Key';

  @override
  String get mockSettingTestTextModel => '测试文本模型';

  @override
  String get mockSettingModelConfigChecked => '模型配置已检查';

  @override
  String get mockSettingSpeechModel => '朗读模型';

  @override
  String get mockSettingGeminiNatural => 'Gemini 自然语音';

  @override
  String get mockSettingOpenRouterDedicated => 'OpenRouter 专用朗读';

  @override
  String get mockSettingOpenRouterAudio => 'OpenRouter 音频模型';

  @override
  String get mockSettingDefaultVoice => '默认声音';

  @override
  String get mockSettingJapaneseClear => '日语清晰';

  @override
  String get mockSettingEnglishNatural => '英语自然';

  @override
  String get mockSettingAudioFormat => '音频格式';

  @override
  String get mockSettingVoiceStyle => '声音风格';

  @override
  String get mockSettingNaturalStyle => '自然';

  @override
  String get mockSettingSoftStyle => '柔和';

  @override
  String get mockSettingSaveSpeech => '保存朗读偏好';

  @override
  String get mockSettingCallCount => '调用次数';

  @override
  String get mockSettingReuseCount => '结果复用';

  @override
  String get mockSettingUnknownUsage => '用量未提供';

  @override
  String get mockSettingInputTokens => '输入 Token';

  @override
  String get mockSettingOutputTokens => '输出 Token';

  @override
  String get mockSettingCacheReadTokens => '缓存读取';

  @override
  String get mockSettingServiceAddress => '服务地址';

  @override
  String get mockSettingProbeConnection => '检查连接';

  @override
  String get mockSettingAddressValid => '地址格式有效';

  @override
  String get mockSettingAddressInvalid => '请输入有效的 HTTPS 地址';

  @override
  String get mockSettingCurrentSession => '当前设备会话';

  @override
  String get mockSettingChangePassword => '修改密码';

  @override
  String get mockSettingCurrentPassword => '当前密码';

  @override
  String get mockSettingNewPassword => '新密码';

  @override
  String get mockSettingConfirmPassword => '确认新密码';

  @override
  String get mockSettingPasswordMismatch => '两次输入的密码不一致';

  @override
  String get mockSettingPasswordRequired => '请填写全部密码字段';

  @override
  String get mockSettingPasswordTooShort => '新密码至少需要 8 个字符';

  @override
  String get mockSettingPasswordUpdated => '密码已更新';

  @override
  String get mockSettingLogout => '退出登录';

  @override
  String get mockSettingAudioWav => 'WAV';

  @override
  String get mockSettingSessionActive => '本机 · 已登录';

  @override
  String get mockSettingClose => '关闭';

  @override
  String get adminRoleCreate => '创建角色';

  @override
  String get adminRoleCode => '代码';

  @override
  String get adminRoleName => '名称';

  @override
  String get adminRoleDescription => '描述';

  @override
  String get adminRoleEnabled => '启用';

  @override
  String get adminRoleDisabled => '已停用';

  @override
  String get adminRoleSaveMetadata => '保存名称';

  @override
  String get adminRoleSaveGrants => '保存授权';

  @override
  String get adminRoleSaveParents => '保存继承';

  @override
  String get adminRoleSaveBoundaries => '保存授予上限';

  @override
  String get adminRoleDelete => '删除角色';

  @override
  String get adminRoleDeleteConfirm => '只删除没有成员、也不是其他角色上级的空角色。';

  @override
  String get adminRoleParents => '继承的上级角色';

  @override
  String get adminRoleParentHint => '停用的上级不会继续提供权限。';

  @override
  String get adminRoleGrants => '直接授权';

  @override
  String get adminRoleUnset => '未配置';

  @override
  String get adminRoleAllow => '允许';

  @override
  String get adminRoleDeny => '拒绝';

  @override
  String get adminRoleBothEffects => '允许并拒绝';

  @override
  String get adminRoleBoundaries => '授予上限';

  @override
  String get adminRoleAffected => '受影响账号';

  @override
  String get adminRoleReload => '重新加载';

  @override
  String get adminRoleEmpty => '还没有角色';

  @override
  String get adminRoleCodeInvalid => '代码需以小写字母开头，并且只含小写字母、数字和下划线';

  @override
  String get adminRoleNameInvalid => '请填写 1 到 100 个字符的名称';

  @override
  String get adminRoleDescriptionInvalid => '描述不能超过 2000 个字符';

  @override
  String get adminRoleNoCatalog => '没有权限目录读取权，不能编辑授权矩阵。';

  @override
  String get adminRoleAssignRole => '可分配角色';

  @override
  String get adminRoleAssignPermission => '可授予权限';

  @override
  String get adminRoleManageRole => '可管理账号角色';

  @override
  String get adminRoleUnassigned => '可管理未分配账号';

  @override
  String get adminRoleAddBoundary => '添加上限';

  @override
  String get adminUserCreate => '创建账号';

  @override
  String get adminUserEmpty => '没有匹配的账号';

  @override
  String get adminUserPendingGrant => '待授权';

  @override
  String get adminUserDisabled => '已停用';

  @override
  String get adminUserLocked => '已锁定';

  @override
  String get adminUserDisplayName => '显示名';

  @override
  String get adminUserNoPassword => '创建后不会生成可复制的密码。';

  @override
  String get adminUserEnable => '启用';

  @override
  String get adminUserDisable => '停用';

  @override
  String get adminUserRoles => '角色';

  @override
  String get adminUserSaveRoles => '保存角色';

  @override
  String get adminUserSessions => '会话';

  @override
  String get adminUserRevoke => '撤销';

  @override
  String get adminUserRevokeAll => '撤销全部会话';

  @override
  String get adminMenuHidden => '已隐藏';

  @override
  String get adminMenuHide => '隐藏菜单';

  @override
  String get adminMenuHideNote => '隐藏菜单不会停用功能访问。';

  @override
  String get adminMenuFeatureNote => '停用功能访问需要在角色权限中撤销页面权限。';

  @override
  String get adminMenuOpenRoles => '前往角色权限';

  @override
  String get adminMenuGroup => '添加分组';

  @override
  String get adminMenuTop => '顶层';

  @override
  String get adminMenuExtra => '附加显示条件';

  @override
  String get adminMenuPreview => '预览导航';

  @override
  String get adminMenuSave => '保存';

  @override
  String get adminMenuCode => '代码';

  @override
  String get authActivationProgressTitle => '账号激活进度';

  @override
  String get authActivationProgressHint => '正在检查邮箱验证和注册审批状态。';

  @override
  String get authActivationApprovalTitle => '注册申请待审批';
}
