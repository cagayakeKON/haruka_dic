import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('zh')];

  /// No description provided for @apiReauthenticationRequired.
  ///
  /// In zh, this message translates to:
  /// **'为保护个人凭据，请重新登录后再操作。'**
  String get apiReauthenticationRequired;

  /// No description provided for @authManualRecoveryCode.
  ///
  /// In zh, this message translates to:
  /// **'人工恢复码或安全链接'**
  String get authManualRecoveryCode;

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'Haruka'**
  String get appTitle;

  /// No description provided for @home.
  ///
  /// In zh, this message translates to:
  /// **'主页'**
  String get home;

  /// No description provided for @environment.
  ///
  /// In zh, this message translates to:
  /// **'环境信息'**
  String get environment;

  /// No description provided for @shellTitle.
  ///
  /// In zh, this message translates to:
  /// **'准备开始学习'**
  String get shellTitle;

  /// No description provided for @materialsTitle.
  ///
  /// In zh, this message translates to:
  /// **'你的学习材料'**
  String get materialsTitle;

  /// No description provided for @unavailable.
  ///
  /// In zh, this message translates to:
  /// **'尚未开放'**
  String get unavailable;

  /// No description provided for @novels.
  ///
  /// In zh, this message translates to:
  /// **'小说'**
  String get novels;

  /// No description provided for @textbooks.
  ///
  /// In zh, this message translates to:
  /// **'课本'**
  String get textbooks;

  /// No description provided for @exams.
  ///
  /// In zh, this message translates to:
  /// **'试卷'**
  String get exams;

  /// No description provided for @environmentDescription.
  ///
  /// In zh, this message translates to:
  /// **'查看公开构建配置，并检查当前服务是否已就绪。'**
  String get environmentDescription;

  /// No description provided for @environmentLabel.
  ///
  /// In zh, this message translates to:
  /// **'运行环境'**
  String get environmentLabel;

  /// No description provided for @instanceLabel.
  ///
  /// In zh, this message translates to:
  /// **'服务实例'**
  String get instanceLabel;

  /// No description provided for @apiLabel.
  ///
  /// In zh, this message translates to:
  /// **'服务地址'**
  String get apiLabel;

  /// No description provided for @applicationLabel.
  ///
  /// In zh, this message translates to:
  /// **'应用标识'**
  String get applicationLabel;

  /// No description provided for @devEnvironment.
  ///
  /// In zh, this message translates to:
  /// **'本地开发'**
  String get devEnvironment;

  /// No description provided for @productionEnvironment.
  ///
  /// In zh, this message translates to:
  /// **'正式环境'**
  String get productionEnvironment;

  /// No description provided for @adminTitle.
  ///
  /// In zh, this message translates to:
  /// **'管理端准备中'**
  String get adminTitle;

  /// No description provided for @adminDescription.
  ///
  /// In zh, this message translates to:
  /// **'此页面暂不可用。'**
  String get adminDescription;

  /// No description provided for @backHome.
  ///
  /// In zh, this message translates to:
  /// **'返回主页'**
  String get backHome;

  /// No description provided for @notFoundTitle.
  ///
  /// In zh, this message translates to:
  /// **'页面不可用'**
  String get notFoundTitle;

  /// No description provided for @notFoundDescription.
  ///
  /// In zh, this message translates to:
  /// **'此页面不存在，或不适用于当前平台。'**
  String get notFoundDescription;

  /// No description provided for @configurationTitle.
  ///
  /// In zh, this message translates to:
  /// **'应用配置不可用'**
  String get configurationTitle;

  /// No description provided for @configurationDescription.
  ///
  /// In zh, this message translates to:
  /// **'环境、实例或服务地址不符合构建要求，请检查公开构建配置后重新启动。'**
  String get configurationDescription;

  /// No description provided for @apiAccessExpired.
  ///
  /// In zh, this message translates to:
  /// **'登录凭据已过期'**
  String get apiAccessExpired;

  /// No description provided for @apiAuthLoginFailed.
  ///
  /// In zh, this message translates to:
  /// **'登录失败'**
  String get apiAuthLoginFailed;

  /// No description provided for @apiAuthRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先登录'**
  String get apiAuthRequired;

  /// No description provided for @apiBadRequest.
  ///
  /// In zh, this message translates to:
  /// **'请求格式有误'**
  String get apiBadRequest;

  /// No description provided for @apiCapabilityUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'暂不支持所选能力'**
  String get apiCapabilityUnsupported;

  /// No description provided for @apiCsrfFailed.
  ///
  /// In zh, this message translates to:
  /// **'请求验证失败'**
  String get apiCsrfFailed;

  /// No description provided for @apiDependencyError.
  ///
  /// In zh, this message translates to:
  /// **'依赖服务响应异常'**
  String get apiDependencyError;

  /// No description provided for @apiDependencyTimeout.
  ///
  /// In zh, this message translates to:
  /// **'依赖服务响应超时'**
  String get apiDependencyTimeout;

  /// No description provided for @apiExternalResultUnknown.
  ///
  /// In zh, this message translates to:
  /// **'外部操作结果待确认'**
  String get apiExternalResultUnknown;

  /// No description provided for @apiIdempotencyConflict.
  ///
  /// In zh, this message translates to:
  /// **'重复请求内容不一致'**
  String get apiIdempotencyConflict;

  /// No description provided for @apiInputInvalid.
  ///
  /// In zh, this message translates to:
  /// **'输入信息有误'**
  String get apiInputInvalid;

  /// No description provided for @apiInternalError.
  ///
  /// In zh, this message translates to:
  /// **'服务暂时无法完成请求'**
  String get apiInternalError;

  /// No description provided for @apiKeyRequired.
  ///
  /// In zh, this message translates to:
  /// **'请配置自己的模型凭据'**
  String get apiKeyRequired;

  /// No description provided for @apiMediaTypeUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'不支持此内容类型'**
  String get apiMediaTypeUnsupported;

  /// No description provided for @apiMethodNotAllowed.
  ///
  /// In zh, this message translates to:
  /// **'不支持此请求方法'**
  String get apiMethodNotAllowed;

  /// No description provided for @apiPayloadTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'请求内容过大'**
  String get apiPayloadTooLarge;

  /// No description provided for @apiPermissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'没有操作权限'**
  String get apiPermissionDenied;

  /// No description provided for @apiQuotaExceeded.
  ///
  /// In zh, this message translates to:
  /// **'已达到使用额度'**
  String get apiQuotaExceeded;

  /// No description provided for @apiRateLimited.
  ///
  /// In zh, this message translates to:
  /// **'操作过于频繁'**
  String get apiRateLimited;

  /// No description provided for @apiRefreshSuperseded.
  ///
  /// In zh, this message translates to:
  /// **'登录凭据已由另一请求更新'**
  String get apiRefreshSuperseded;

  /// No description provided for @apiResourceExpired.
  ///
  /// In zh, this message translates to:
  /// **'资源已过期'**
  String get apiResourceExpired;

  /// No description provided for @apiResourceNotFound.
  ///
  /// In zh, this message translates to:
  /// **'未找到资源'**
  String get apiResourceNotFound;

  /// No description provided for @apiRevisionConflict.
  ///
  /// In zh, this message translates to:
  /// **'内容已更新，请重新加载'**
  String get apiRevisionConflict;

  /// No description provided for @apiServiceUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'服务尚未就绪'**
  String get apiServiceUnavailable;

  /// No description provided for @apiSessionInvalid.
  ///
  /// In zh, this message translates to:
  /// **'登录已失效'**
  String get apiSessionInvalid;

  /// No description provided for @apiAuthScopeRequired.
  ///
  /// In zh, this message translates to:
  /// **'请更新应用后重新登录'**
  String get apiAuthScopeRequired;

  /// No description provided for @apiAuthScopeChanged.
  ///
  /// In zh, this message translates to:
  /// **'登录身份已变化，请重新确认'**
  String get apiAuthScopeChanged;

  /// No description provided for @apiSessionRevoked.
  ///
  /// In zh, this message translates to:
  /// **'登录已失效'**
  String get apiSessionRevoked;

  /// No description provided for @apiStateConflict.
  ///
  /// In zh, this message translates to:
  /// **'当前状态不支持此操作'**
  String get apiStateConflict;

  /// No description provided for @apiValidationFormat.
  ///
  /// In zh, this message translates to:
  /// **'信息格式有误'**
  String get apiValidationFormat;

  /// No description provided for @apiValidationInvalid.
  ///
  /// In zh, this message translates to:
  /// **'输入信息有误'**
  String get apiValidationInvalid;

  /// No description provided for @apiValidationOutOfRange.
  ///
  /// In zh, this message translates to:
  /// **'数值超出允许范围'**
  String get apiValidationOutOfRange;

  /// No description provided for @apiValidationRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写必填信息'**
  String get apiValidationRequired;

  /// No description provided for @apiValidationTooLong.
  ///
  /// In zh, this message translates to:
  /// **'内容超过允许长度'**
  String get apiValidationTooLong;

  /// No description provided for @apiValidationType.
  ///
  /// In zh, this message translates to:
  /// **'信息类型有误'**
  String get apiValidationType;

  /// No description provided for @apiValidationUnknownField.
  ///
  /// In zh, this message translates to:
  /// **'包含不支持的字段'**
  String get apiValidationUnknownField;

  /// No description provided for @checkConnection.
  ///
  /// In zh, this message translates to:
  /// **'检查服务连接'**
  String get checkConnection;

  /// No description provided for @checkingConnection.
  ///
  /// In zh, this message translates to:
  /// **'正在检查…'**
  String get checkingConnection;

  /// No description provided for @connectionReady.
  ///
  /// In zh, this message translates to:
  /// **'服务已就绪'**
  String get connectionReady;

  /// No description provided for @apiUnknownError.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法完成请求，请稍后重试。'**
  String get apiUnknownError;

  /// No description provided for @authEmail.
  ///
  /// In zh, this message translates to:
  /// **'邮箱'**
  String get authEmail;

  /// No description provided for @authPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get authPassword;

  /// No description provided for @authConfirmPassword.
  ///
  /// In zh, this message translates to:
  /// **'确认密码'**
  String get authConfirmPassword;

  /// No description provided for @authShowPassword.
  ///
  /// In zh, this message translates to:
  /// **'显示密码'**
  String get authShowPassword;

  /// No description provided for @authHidePassword.
  ///
  /// In zh, this message translates to:
  /// **'隐藏密码'**
  String get authHidePassword;

  /// No description provided for @authRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写此项'**
  String get authRequired;

  /// No description provided for @authInvalidEmail.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效邮箱'**
  String get authInvalidEmail;

  /// No description provided for @authPasswordMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入的密码不一致'**
  String get authPasswordMismatch;

  /// No description provided for @authSignIn.
  ///
  /// In zh, this message translates to:
  /// **'登录'**
  String get authSignIn;

  /// No description provided for @authSigningIn.
  ///
  /// In zh, this message translates to:
  /// **'正在登录…'**
  String get authSigningIn;

  /// No description provided for @authCreateAccount.
  ///
  /// In zh, this message translates to:
  /// **'创建账号'**
  String get authCreateAccount;

  /// No description provided for @authCreatingAccount.
  ///
  /// In zh, this message translates to:
  /// **'正在提交注册…'**
  String get authCreatingAccount;

  /// No description provided for @authLoginTitle.
  ///
  /// In zh, this message translates to:
  /// **'欢迎回来'**
  String get authLoginTitle;

  /// No description provided for @authLoginHint.
  ///
  /// In zh, this message translates to:
  /// **'使用你的账号继续学习。'**
  String get authLoginHint;

  /// No description provided for @authRegisterTitle.
  ///
  /// In zh, this message translates to:
  /// **'创建账号'**
  String get authRegisterTitle;

  /// No description provided for @authRegisterHint.
  ///
  /// In zh, this message translates to:
  /// **'注册只需邮箱和密码。资料稍后再填写。'**
  String get authRegisterHint;

  /// No description provided for @authForgotPassword.
  ///
  /// In zh, this message translates to:
  /// **'忘记密码？'**
  String get authForgotPassword;

  /// No description provided for @authBackToLogin.
  ///
  /// In zh, this message translates to:
  /// **'返回登录'**
  String get authBackToLogin;

  /// No description provided for @authRecoveryTitle.
  ///
  /// In zh, this message translates to:
  /// **'找回密码'**
  String get authRecoveryTitle;

  /// No description provided for @authRecoveryHint.
  ///
  /// In zh, this message translates to:
  /// **'输入注册邮箱，我们会受理找回请求。受理不代表邮件已送达。'**
  String get authRecoveryHint;

  /// No description provided for @authRecoveryManualHint.
  ///
  /// In zh, this message translates to:
  /// **'提交后由管理员核验身份。通过后你会得到一次性恢复码，再用它设置新密码。'**
  String get authRecoveryManualHint;

  /// No description provided for @authRecoveryAwaitReview.
  ///
  /// In zh, this message translates to:
  /// **'申请已受理。请等待管理员核验，核验通过后使用一次性恢复码设置新密码。受理不代表已经核验。'**
  String get authRecoveryAwaitReview;

  /// No description provided for @authRequestRecovery.
  ///
  /// In zh, this message translates to:
  /// **'提交申请'**
  String get authRequestRecovery;

  /// No description provided for @authRequestManualRecovery.
  ///
  /// In zh, this message translates to:
  /// **'申请人工恢复'**
  String get authRequestManualRecovery;

  /// No description provided for @authHeroLogin.
  ///
  /// In zh, this message translates to:
  /// **'欢迎回来。'**
  String get authHeroLogin;

  /// No description provided for @authHeroRegister.
  ///
  /// In zh, this message translates to:
  /// **'从这里开始。'**
  String get authHeroRegister;

  /// No description provided for @authHeroRecovery.
  ///
  /// In zh, this message translates to:
  /// **'找回访问方式。'**
  String get authHeroRecovery;

  /// No description provided for @authAdminHero.
  ///
  /// In zh, this message translates to:
  /// **'管理端，独立登录。'**
  String get authAdminHero;

  /// No description provided for @authAdminEntry.
  ///
  /// In zh, this message translates to:
  /// **'管理端入口'**
  String get authAdminEntry;

  /// No description provided for @authAdminWorkspace.
  ///
  /// In zh, this message translates to:
  /// **'管理端'**
  String get authAdminWorkspace;

  /// No description provided for @authEmailVerificationFact.
  ///
  /// In zh, this message translates to:
  /// **'邮箱验证已启用'**
  String get authEmailVerificationFact;

  /// No description provided for @authMailRecoveryFact.
  ///
  /// In zh, this message translates to:
  /// **'邮件找回'**
  String get authMailRecoveryFact;

  /// No description provided for @authAvailable.
  ///
  /// In zh, this message translates to:
  /// **'可用'**
  String get authAvailable;

  /// No description provided for @authUnavailableShort.
  ///
  /// In zh, this message translates to:
  /// **'暂不可用'**
  String get authUnavailableShort;

  /// No description provided for @authRequestingRecovery.
  ///
  /// In zh, this message translates to:
  /// **'正在受理…'**
  String get authRequestingRecovery;

  /// No description provided for @authVerifyTitle.
  ///
  /// In zh, this message translates to:
  /// **'验证邮箱'**
  String get authVerifyTitle;

  /// No description provided for @authVerifyHint.
  ///
  /// In zh, this message translates to:
  /// **'打开邮件中的验证链接完成激活。'**
  String get authVerifyHint;

  /// No description provided for @authVerify.
  ///
  /// In zh, this message translates to:
  /// **'完成验证'**
  String get authVerify;

  /// No description provided for @authVerifying.
  ///
  /// In zh, this message translates to:
  /// **'正在验证…'**
  String get authVerifying;

  /// No description provided for @authNewPassword.
  ///
  /// In zh, this message translates to:
  /// **'新密码'**
  String get authNewPassword;

  /// No description provided for @authCompleteRecovery.
  ///
  /// In zh, this message translates to:
  /// **'重置密码'**
  String get authCompleteRecovery;

  /// No description provided for @authResettingPassword.
  ///
  /// In zh, this message translates to:
  /// **'正在重置…'**
  String get authResettingPassword;

  /// No description provided for @authRegisterReceived.
  ///
  /// In zh, this message translates to:
  /// **'注册请求已受理'**
  String get authRegisterReceived;

  /// No description provided for @authRegisterReceivedHint.
  ///
  /// In zh, this message translates to:
  /// **'请留意验证邮件。邮件可能尚未送达，暂时无法登录时可稍后重发。'**
  String get authRegisterReceivedHint;

  /// No description provided for @authRecoveryReceived.
  ///
  /// In zh, this message translates to:
  /// **'找回请求已受理'**
  String get authRecoveryReceived;

  /// No description provided for @authRecoveryReceivedHint.
  ///
  /// In zh, this message translates to:
  /// **'若账号符合条件，我们会发送找回邮件。请检查收件箱，受理不代表已送达。'**
  String get authRecoveryReceivedHint;

  /// No description provided for @authVerified.
  ///
  /// In zh, this message translates to:
  /// **'邮箱验证完成'**
  String get authVerified;

  /// No description provided for @authResetComplete.
  ///
  /// In zh, this message translates to:
  /// **'密码已重置'**
  String get authResetComplete;

  /// No description provided for @authRegistrationClosed.
  ///
  /// In zh, this message translates to:
  /// **'当前暂停新账号注册'**
  String get authRegistrationClosed;

  /// No description provided for @authRecoveryClosed.
  ///
  /// In zh, this message translates to:
  /// **'当前未开放找回'**
  String get authRecoveryClosed;

  /// No description provided for @authServiceUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'账号服务暂不可用，请稍后重试。'**
  String get authServiceUnavailable;

  /// No description provided for @authRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get authRetry;

  /// No description provided for @authWorking.
  ///
  /// In zh, this message translates to:
  /// **'正在处理…'**
  String get authWorking;

  /// No description provided for @authAdminLoginTitle.
  ///
  /// In zh, this message translates to:
  /// **'管理端登录'**
  String get authAdminLoginTitle;

  /// No description provided for @authAdminLoginHint.
  ///
  /// In zh, this message translates to:
  /// **'管理操作需要独立的管理会话。'**
  String get authAdminLoginHint;

  /// No description provided for @authBrandLine.
  ///
  /// In zh, this message translates to:
  /// **'让每一次学习，都有清晰的方向。'**
  String get authBrandLine;

  /// No description provided for @authVerificationToken.
  ///
  /// In zh, this message translates to:
  /// **'粘贴邮件中的验证链接'**
  String get authVerificationToken;

  /// No description provided for @authRecoveryToken.
  ///
  /// In zh, this message translates to:
  /// **'粘贴邮件中的重置链接'**
  String get authRecoveryToken;

  /// No description provided for @authInvalidActionLink.
  ///
  /// In zh, this message translates to:
  /// **'请使用本服务邮件中的正确链接'**
  String get authInvalidActionLink;

  /// No description provided for @authResetTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置新密码'**
  String get authResetTitle;

  /// No description provided for @authResetHint.
  ///
  /// In zh, this message translates to:
  /// **'完成后请用新密码重新登录。'**
  String get authResetHint;

  /// No description provided for @authAccount.
  ///
  /// In zh, this message translates to:
  /// **'账号与安全'**
  String get authAccount;

  /// No description provided for @accountHomeTitle.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get accountHomeTitle;

  /// No description provided for @accountLearningTitle.
  ///
  /// In zh, this message translates to:
  /// **'学习材料'**
  String get accountLearningTitle;

  /// No description provided for @authAccountHint.
  ///
  /// In zh, this message translates to:
  /// **'在这里管理自己的密码与已登录设备。'**
  String get authAccountHint;

  /// No description provided for @authSignOut.
  ///
  /// In zh, this message translates to:
  /// **'退出当前账号'**
  String get authSignOut;

  /// No description provided for @authChangePassword.
  ///
  /// In zh, this message translates to:
  /// **'修改密码'**
  String get authChangePassword;

  /// No description provided for @authCurrentPassword.
  ///
  /// In zh, this message translates to:
  /// **'当前密码'**
  String get authCurrentPassword;

  /// No description provided for @authPasswordChanged.
  ///
  /// In zh, this message translates to:
  /// **'密码操作已提交，请用新密码重新登录。'**
  String get authPasswordChanged;

  /// No description provided for @authPasswordOutcomeUnknown.
  ///
  /// In zh, this message translates to:
  /// **'无法确认密码操作结果。请勿重复提交；尝试用新密码登录，必要时使用邮件找回。'**
  String get authPasswordOutcomeUnknown;

  /// No description provided for @authDeviceSessions.
  ///
  /// In zh, this message translates to:
  /// **'已登录设备'**
  String get authDeviceSessions;

  /// No description provided for @authRevokeSession.
  ///
  /// In zh, this message translates to:
  /// **'撤销此设备'**
  String get authRevokeSession;

  /// No description provided for @authRevokeAll.
  ///
  /// In zh, this message translates to:
  /// **'退出所有设备'**
  String get authRevokeAll;

  /// No description provided for @authSessionCurrent.
  ///
  /// In zh, this message translates to:
  /// **'当前设备'**
  String get authSessionCurrent;

  /// No description provided for @authSessionLastSeen.
  ///
  /// In zh, this message translates to:
  /// **'最近活动'**
  String get authSessionLastSeen;

  /// No description provided for @authSessionNever.
  ///
  /// In zh, this message translates to:
  /// **'尚无活动记录'**
  String get authSessionNever;

  /// No description provided for @authSessionExpires.
  ///
  /// In zh, this message translates to:
  /// **'到期时间'**
  String get authSessionExpires;

  /// No description provided for @authLoadMoreSessions.
  ///
  /// In zh, this message translates to:
  /// **'加载更多会话'**
  String get authLoadMoreSessions;

  /// No description provided for @referenceMaterialsTitle.
  ///
  /// In zh, this message translates to:
  /// **'材料库'**
  String get referenceMaterialsTitle;

  /// No description provided for @referenceJapanese.
  ///
  /// In zh, this message translates to:
  /// **'日语'**
  String get referenceJapanese;

  /// No description provided for @referenceEnglish.
  ///
  /// In zh, this message translates to:
  /// **'英语'**
  String get referenceEnglish;

  /// No description provided for @referenceLoadMore.
  ///
  /// In zh, this message translates to:
  /// **'加载更多'**
  String get referenceLoadMore;

  /// No description provided for @referenceNoMaterials.
  ///
  /// In zh, this message translates to:
  /// **'暂无可读取的参考材料。'**
  String get referenceNoMaterials;

  /// No description provided for @referenceSelectHint.
  ///
  /// In zh, this message translates to:
  /// **'在文字中选中已准备词后查询已保存的卡片。'**
  String get referenceSelectHint;

  /// No description provided for @referenceQuery.
  ///
  /// In zh, this message translates to:
  /// **'查询选区'**
  String get referenceQuery;

  /// No description provided for @referenceNoPreparedCard.
  ///
  /// In zh, this message translates to:
  /// **'该选区暂无已保存的卡片。'**
  String get referenceNoPreparedCard;

  /// No description provided for @referenceSave.
  ///
  /// In zh, this message translates to:
  /// **'加入收藏'**
  String get referenceSave;

  /// No description provided for @referenceSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存到你的收藏。'**
  String get referenceSaved;

  /// No description provided for @referenceOpenCollections.
  ///
  /// In zh, this message translates to:
  /// **'查看我的收藏'**
  String get referenceOpenCollections;

  /// No description provided for @referenceCollectionsTitle.
  ///
  /// In zh, this message translates to:
  /// **'我的收藏'**
  String get referenceCollectionsTitle;

  /// No description provided for @referenceNoCollections.
  ///
  /// In zh, this message translates to:
  /// **'暂无收藏。'**
  String get referenceNoCollections;

  /// No description provided for @referenceClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get referenceClose;

  /// No description provided for @referenceRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试加载'**
  String get referenceRetry;

  /// No description provided for @referencePartOfSpeech.
  ///
  /// In zh, this message translates to:
  /// **'词性'**
  String get referencePartOfSpeech;

  /// No description provided for @referenceOtherMeanings.
  ///
  /// In zh, this message translates to:
  /// **'其它释义'**
  String get referenceOtherMeanings;

  /// No description provided for @referenceExamples.
  ///
  /// In zh, this message translates to:
  /// **'例句'**
  String get referenceExamples;

  /// No description provided for @referenceSource.
  ///
  /// In zh, this message translates to:
  /// **'出处'**
  String get referenceSource;

  /// No description provided for @referencePublishedNovelCount.
  ///
  /// In zh, this message translates to:
  /// **'小说 · {count} 份已发布材料'**
  String referencePublishedNovelCount(int count);

  /// No description provided for @referenceCoverFallback.
  ///
  /// In zh, this message translates to:
  /// **'文'**
  String get referenceCoverFallback;

  /// No description provided for @referenceNovelLanguage.
  ///
  /// In zh, this message translates to:
  /// **'小说 · {language}'**
  String referenceNovelLanguage(String language);

  /// No description provided for @referenceReadable.
  ///
  /// In zh, this message translates to:
  /// **'可阅读'**
  String get referenceReadable;

  /// No description provided for @referenceReading.
  ///
  /// In zh, this message translates to:
  /// **'阅读'**
  String get referenceReading;

  /// No description provided for @referenceNovel.
  ///
  /// In zh, this message translates to:
  /// **'小说'**
  String get referenceNovel;

  /// No description provided for @referencePublishedChapters.
  ///
  /// In zh, this message translates to:
  /// **'已发布章节'**
  String get referencePublishedChapters;

  /// No description provided for @referenceSelectedSource.
  ///
  /// In zh, this message translates to:
  /// **'已选原文'**
  String get referenceSelectedSource;

  /// No description provided for @referenceAllCollections.
  ///
  /// In zh, this message translates to:
  /// **'全部收藏'**
  String get referenceAllCollections;

  /// No description provided for @referenceCollectionCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条收藏'**
  String referenceCollectionCount(int count);

  /// No description provided for @referenceWord.
  ///
  /// In zh, this message translates to:
  /// **'单词'**
  String get referenceWord;

  /// No description provided for @referenceCollectionDetail.
  ///
  /// In zh, this message translates to:
  /// **'收藏详情'**
  String get referenceCollectionDetail;

  /// No description provided for @referenceMeaning.
  ///
  /// In zh, this message translates to:
  /// **'释义'**
  String get referenceMeaning;

  /// No description provided for @authPendingEmail.
  ///
  /// In zh, this message translates to:
  /// **'邮箱尚待验证'**
  String get authPendingEmail;

  /// No description provided for @authPendingEmailHint.
  ///
  /// In zh, this message translates to:
  /// **'请使用验证邮件中的链接。邮件可能尚未送达，可申请重发。'**
  String get authPendingEmailHint;

  /// No description provided for @authResendVerification.
  ///
  /// In zh, this message translates to:
  /// **'重发验证邮件'**
  String get authResendVerification;

  /// No description provided for @authResendReceived.
  ///
  /// In zh, this message translates to:
  /// **'重发请求已受理，受理不代表邮件已送达。'**
  String get authResendReceived;

  /// No description provided for @authAdminPolicy.
  ///
  /// In zh, this message translates to:
  /// **'注册策略'**
  String get authAdminPolicy;

  /// No description provided for @authAdminPolicyHint.
  ///
  /// In zh, this message translates to:
  /// **'切换注册或找回方式不会改变已有账号状态，也不会取消已经发出的挑战。'**
  String get authAdminPolicyHint;

  /// No description provided for @authRegistrationEnabled.
  ///
  /// In zh, this message translates to:
  /// **'允许新账号注册'**
  String get authRegistrationEnabled;

  /// No description provided for @authSavePolicy.
  ///
  /// In zh, this message translates to:
  /// **'保存注册策略'**
  String get authSavePolicy;

  /// No description provided for @authNoAdminPermission.
  ///
  /// In zh, this message translates to:
  /// **'当前管理会话没有此操作权限。'**
  String get authNoAdminPermission;

  /// No description provided for @authLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在验证账号与服务…'**
  String get authLoading;

  /// No description provided for @authUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'账号服务暂不可用。请检查连接后重试。'**
  String get authUnavailable;

  /// No description provided for @authCheckAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新检查'**
  String get authCheckAgain;

  /// No description provided for @authBackToAccount.
  ///
  /// In zh, this message translates to:
  /// **'返回账号'**
  String get authBackToAccount;

  /// No description provided for @authSessionRevoked.
  ///
  /// In zh, this message translates to:
  /// **'设备会话已撤销。'**
  String get authSessionRevoked;

  /// No description provided for @authNoSessions.
  ///
  /// In zh, this message translates to:
  /// **'没有可显示的会话。'**
  String get authNoSessions;

  /// No description provided for @authCheckActivation.
  ///
  /// In zh, this message translates to:
  /// **'检查验证状态'**
  String get authCheckActivation;

  /// No description provided for @authStillPending.
  ///
  /// In zh, this message translates to:
  /// **'邮箱仍待验证。请先打开邮件中的验证链接。'**
  String get authStillPending;

  /// No description provided for @authPendingApproval.
  ///
  /// In zh, this message translates to:
  /// **'邮箱已验证，正在等待管理员审批。'**
  String get authPendingApproval;

  /// No description provided for @authApprovalRejected.
  ///
  /// In zh, this message translates to:
  /// **'注册申请已被拒绝。'**
  String get authApprovalRejected;

  /// No description provided for @authApprovalRequired.
  ///
  /// In zh, this message translates to:
  /// **'提交后需要管理员审批，通过前不能登录。'**
  String get authApprovalRequired;

  /// No description provided for @adminPolicyOpen.
  ///
  /// In zh, this message translates to:
  /// **'开放注册'**
  String get adminPolicyOpen;

  /// No description provided for @adminPolicyRecoveryEither.
  ///
  /// In zh, this message translates to:
  /// **'邮件或人工'**
  String get adminPolicyRecoveryEither;

  /// No description provided for @adminPolicyRecoveryDisabled.
  ///
  /// In zh, this message translates to:
  /// **'关闭找回'**
  String get adminPolicyRecoveryDisabled;

  /// No description provided for @adminRecoveryRequests.
  ///
  /// In zh, this message translates to:
  /// **'人工恢复'**
  String get adminRecoveryRequests;

  /// No description provided for @adminMenuOrder.
  ///
  /// In zh, this message translates to:
  /// **'排序（越小越靠前）'**
  String get adminMenuOrder;

  /// No description provided for @adminMenuIcon.
  ///
  /// In zh, this message translates to:
  /// **'导航图标'**
  String get adminMenuIcon;

  /// No description provided for @adminMenuOrderError.
  ///
  /// In zh, this message translates to:
  /// **'请输入 0 到 100000 的排序值。'**
  String get adminMenuOrderError;

  /// No description provided for @adminAuditAction.
  ///
  /// In zh, this message translates to:
  /// **'操作类别'**
  String get adminAuditAction;

  /// No description provided for @adminAuditActor.
  ///
  /// In zh, this message translates to:
  /// **'操作者 ID'**
  String get adminAuditActor;

  /// No description provided for @adminAuditTargetType.
  ///
  /// In zh, this message translates to:
  /// **'目标类型'**
  String get adminAuditTargetType;

  /// No description provided for @adminAuditTargetId.
  ///
  /// In zh, this message translates to:
  /// **'目标 ID'**
  String get adminAuditTargetId;

  /// No description provided for @adminAuditTargetCode.
  ///
  /// In zh, this message translates to:
  /// **'目标代码'**
  String get adminAuditTargetCode;

  /// No description provided for @adminAuditFrom.
  ///
  /// In zh, this message translates to:
  /// **'开始时间（含时区）'**
  String get adminAuditFrom;

  /// No description provided for @adminAuditTo.
  ///
  /// In zh, this message translates to:
  /// **'结束时间（含时区）'**
  String get adminAuditTo;

  /// No description provided for @adminAuditFilter.
  ///
  /// In zh, this message translates to:
  /// **'筛选'**
  String get adminAuditFilter;

  /// No description provided for @adminAuditTimeError.
  ///
  /// In zh, this message translates to:
  /// **'请输入带时区的有效时间，结束时间不能早于开始时间。'**
  String get adminAuditTimeError;

  /// No description provided for @adminRecoveryIssue.
  ///
  /// In zh, this message translates to:
  /// **'核验签发'**
  String get adminRecoveryIssue;

  /// No description provided for @adminRecoveryReject.
  ///
  /// In zh, this message translates to:
  /// **'拒绝恢复'**
  String get adminRecoveryReject;

  /// No description provided for @adminRecoveryInPerson.
  ///
  /// In zh, this message translates to:
  /// **'当面核验'**
  String get adminRecoveryInPerson;

  /// No description provided for @adminRecoveryKnownChannel.
  ///
  /// In zh, this message translates to:
  /// **'已知渠道核验'**
  String get adminRecoveryKnownChannel;

  /// No description provided for @adminRecoveryTokenOnce.
  ///
  /// In zh, this message translates to:
  /// **'一次性恢复码只显示这一次。请交给账号持有人，管理员不能代设密码。'**
  String get adminRecoveryTokenOnce;

  /// No description provided for @adminRecoveryTokenHidden.
  ///
  /// In zh, this message translates to:
  /// **'恢复码不会再次显示。'**
  String get adminRecoveryTokenHidden;

  /// No description provided for @adminRecoveryRequested.
  ///
  /// In zh, this message translates to:
  /// **'待核验'**
  String get adminRecoveryRequested;

  /// No description provided for @adminRecoveryIssued.
  ///
  /// In zh, this message translates to:
  /// **'已签发'**
  String get adminRecoveryIssued;

  /// No description provided for @adminRecoveryRejected.
  ///
  /// In zh, this message translates to:
  /// **'已拒绝'**
  String get adminRecoveryRejected;

  /// No description provided for @adminRecoveryConsumed.
  ///
  /// In zh, this message translates to:
  /// **'已使用'**
  String get adminRecoveryConsumed;

  /// No description provided for @adminRecoveryExpired.
  ///
  /// In zh, this message translates to:
  /// **'已过期'**
  String get adminRecoveryExpired;

  /// No description provided for @adminGovernanceActive.
  ///
  /// In zh, this message translates to:
  /// **'可登录账号'**
  String get adminGovernanceActive;

  /// No description provided for @adminGovernancePending.
  ///
  /// In zh, this message translates to:
  /// **'待启用账号'**
  String get adminGovernancePending;

  /// No description provided for @adminGovernanceDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已停用账号'**
  String get adminGovernanceDisabled;

  /// No description provided for @adminGovernanceApprovals.
  ///
  /// In zh, this message translates to:
  /// **'待审批'**
  String get adminGovernanceApprovals;

  /// No description provided for @adminGovernanceRoles.
  ///
  /// In zh, this message translates to:
  /// **'启用角色'**
  String get adminGovernanceRoles;

  /// No description provided for @adminGovernanceRecoveries.
  ///
  /// In zh, this message translates to:
  /// **'待核验恢复'**
  String get adminGovernanceRecoveries;

  /// No description provided for @adminGovernanceRevision.
  ///
  /// In zh, this message translates to:
  /// **'授权版本'**
  String get adminGovernanceRevision;

  /// No description provided for @adminGovernanceLater.
  ///
  /// In zh, this message translates to:
  /// **'任务、存储和模型用量仍未开放。'**
  String get adminGovernanceLater;

  /// No description provided for @adminAuditEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有审计记录'**
  String get adminAuditEmpty;

  /// No description provided for @adminAuditDetail.
  ///
  /// In zh, this message translates to:
  /// **'审计详情'**
  String get adminAuditDetail;

  /// No description provided for @adminAuditReason.
  ///
  /// In zh, this message translates to:
  /// **'原因'**
  String get adminAuditReason;

  /// No description provided for @adminAuditRequest.
  ///
  /// In zh, this message translates to:
  /// **'请求'**
  String get adminAuditRequest;

  /// No description provided for @adminAuditMore.
  ///
  /// In zh, this message translates to:
  /// **'加载更多'**
  String get adminAuditMore;

  /// No description provided for @adminAuditResultAll.
  ///
  /// In zh, this message translates to:
  /// **'全部结果'**
  String get adminAuditResultAll;

  /// No description provided for @adminAuditCommitted.
  ///
  /// In zh, this message translates to:
  /// **'已提交'**
  String get adminAuditCommitted;

  /// No description provided for @adminAuditAccepted.
  ///
  /// In zh, this message translates to:
  /// **'已受理'**
  String get adminAuditAccepted;

  /// No description provided for @adminAuditDenied.
  ///
  /// In zh, this message translates to:
  /// **'已拒绝'**
  String get adminAuditDenied;

  /// No description provided for @adminAuditFailed.
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get adminAuditFailed;

  /// No description provided for @adminUserApprove.
  ///
  /// In zh, this message translates to:
  /// **'通过审批'**
  String get adminUserApprove;

  /// No description provided for @adminUserReject.
  ///
  /// In zh, this message translates to:
  /// **'拒绝申请'**
  String get adminUserReject;

  /// No description provided for @authSignedOutLocally.
  ///
  /// In zh, this message translates to:
  /// **'本机登录已清除，但无法确认服务端会话已撤销。重新登录后可在设备会话中撤销它。'**
  String get authSignedOutLocally;

  /// No description provided for @authPasswordLength.
  ///
  /// In zh, this message translates to:
  /// **'密码需要 {min} 至 {max} 个字符'**
  String authPasswordLength(int min, int max);

  /// No description provided for @mockLibraryAddFileInfo.
  ///
  /// In zh, this message translates to:
  /// **'添加文件与信息'**
  String get mockLibraryAddFileInfo;

  /// No description provided for @mockLibraryAiStructureDescription.
  ///
  /// In zh, this message translates to:
  /// **'使用个人模型整理章节或题目'**
  String get mockLibraryAiStructureDescription;

  /// No description provided for @mockLibraryAiStructureEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已开启'**
  String get mockLibraryAiStructureEnabled;

  /// No description provided for @mockLibraryAiStructureDisabled.
  ///
  /// In zh, this message translates to:
  /// **'未开启'**
  String get mockLibraryAiStructureDisabled;

  /// No description provided for @mockLibraryAiStructureSuggestion.
  ///
  /// In zh, this message translates to:
  /// **'AI 结构建议'**
  String get mockLibraryAiStructureSuggestion;

  /// No description provided for @mockLibraryAddPrompt.
  ///
  /// In zh, this message translates to:
  /// **'添加小说、课本或试卷，开始学习。'**
  String get mockLibraryAddPrompt;

  /// No description provided for @mockLibraryAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get mockLibraryAll;

  /// No description provided for @mockLibraryBackToEdit.
  ///
  /// In zh, this message translates to:
  /// **'返回修改'**
  String get mockLibraryBackToEdit;

  /// No description provided for @mockLibraryCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get mockLibraryCancel;

  /// No description provided for @mockLibraryChapterCount.
  ///
  /// In zh, this message translates to:
  /// **' · {count} 章'**
  String mockLibraryChapterCount(Object count);

  /// No description provided for @mockLibraryChooseType.
  ///
  /// In zh, this message translates to:
  /// **'选择类型'**
  String get mockLibraryChooseType;

  /// No description provided for @mockLibraryChooseFile.
  ///
  /// In zh, this message translates to:
  /// **'选择文件'**
  String get mockLibraryChooseFile;

  /// No description provided for @mockLibraryChooseMaterialFile.
  ///
  /// In zh, this message translates to:
  /// **'选择材料文件'**
  String get mockLibraryChooseMaterialFile;

  /// No description provided for @mockLibraryCloseSearch.
  ///
  /// In zh, this message translates to:
  /// **'关闭搜索'**
  String get mockLibraryCloseSearch;

  /// No description provided for @mockLibraryConfirmImport.
  ///
  /// In zh, this message translates to:
  /// **'确认导入'**
  String get mockLibraryConfirmImport;

  /// No description provided for @mockLibraryDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get mockLibraryDelete;

  /// No description provided for @mockLibraryDeleteConfirmMessage.
  ///
  /// In zh, this message translates to:
  /// **'「{title}」将从材料库移除。已有合法收藏与历史仍保留。'**
  String mockLibraryDeleteConfirmMessage(Object title);

  /// No description provided for @mockLibraryDeleteConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除材料？'**
  String get mockLibraryDeleteConfirmTitle;

  /// No description provided for @mockLibraryDeleteMaterial.
  ///
  /// In zh, this message translates to:
  /// **'删除材料'**
  String get mockLibraryDeleteMaterial;

  /// No description provided for @mockLibraryEnglish.
  ///
  /// In zh, this message translates to:
  /// **'英语'**
  String get mockLibraryEnglish;

  /// No description provided for @mockLibraryExam.
  ///
  /// In zh, this message translates to:
  /// **'试卷'**
  String get mockLibraryExam;

  /// No description provided for @mockLibraryExamDescription.
  ///
  /// In zh, this message translates to:
  /// **'整卷作答与评分'**
  String get mockLibraryExamDescription;

  /// No description provided for @mockLibraryImport.
  ///
  /// In zh, this message translates to:
  /// **'导入材料'**
  String get mockLibraryImport;

  /// No description provided for @mockLibraryImportStep.
  ///
  /// In zh, this message translates to:
  /// **'步骤 {step} / {total}'**
  String mockLibraryImportStep(Object step, Object total);

  /// No description provided for @mockLibraryImportStepType.
  ///
  /// In zh, this message translates to:
  /// **'{step} / {total} · {type}'**
  String mockLibraryImportStepType(int step, int total, String type);

  /// No description provided for @mockLibraryImportSummary.
  ///
  /// In zh, this message translates to:
  /// **'{type} · {title} · {language}'**
  String mockLibraryImportSummary(String type, String title, String language);

  /// No description provided for @mockLibraryJapanese.
  ///
  /// In zh, this message translates to:
  /// **'日语'**
  String get mockLibraryJapanese;

  /// No description provided for @mockLibraryLearnable.
  ///
  /// In zh, this message translates to:
  /// **'可学习'**
  String get mockLibraryLearnable;

  /// No description provided for @mockLibraryMaterialLanguage.
  ///
  /// In zh, this message translates to:
  /// **'材料语言'**
  String get mockLibraryMaterialLanguage;

  /// No description provided for @mockLibraryMaterialTypeStep.
  ///
  /// In zh, this message translates to:
  /// **'材料类型'**
  String get mockLibraryMaterialTypeStep;

  /// No description provided for @mockLibraryMaterialActions.
  ///
  /// In zh, this message translates to:
  /// **'材料操作'**
  String get mockLibraryMaterialActions;

  /// No description provided for @mockLibraryMaterialMetadata.
  ///
  /// In zh, this message translates to:
  /// **'{type} · {language}{details}'**
  String mockLibraryMaterialMetadata(Object details, Object language, Object type);

  /// No description provided for @mockLibraryMaterialTitle.
  ///
  /// In zh, this message translates to:
  /// **'材料标题'**
  String get mockLibraryMaterialTitle;

  /// No description provided for @mockLibraryMaterialsCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 份材料'**
  String mockLibraryMaterialsCount(Object count);

  /// No description provided for @mockLibraryMoreActions.
  ///
  /// In zh, this message translates to:
  /// **'{title}更多操作'**
  String mockLibraryMoreActions(Object title);

  /// No description provided for @mockLibraryNeedsReview.
  ///
  /// In zh, this message translates to:
  /// **'待校对'**
  String get mockLibraryNeedsReview;

  /// No description provided for @mockLibraryNext.
  ///
  /// In zh, this message translates to:
  /// **'下一步'**
  String get mockLibraryNext;

  /// No description provided for @mockLibraryNoFileSelected.
  ///
  /// In zh, this message translates to:
  /// **'尚未选择文件'**
  String get mockLibraryNoFileSelected;

  /// No description provided for @mockLibraryNoMatches.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的材料'**
  String get mockLibraryNoMatches;

  /// No description provided for @mockLibraryNoMaterials.
  ///
  /// In zh, this message translates to:
  /// **'还没有材料'**
  String get mockLibraryNoMaterials;

  /// No description provided for @mockLibraryEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'目前没有可阅读的小说。'**
  String get mockLibraryEmptyHint;

  /// No description provided for @mockLibraryOpenMaterial.
  ///
  /// In zh, this message translates to:
  /// **'打开材料'**
  String get mockLibraryOpenMaterial;

  /// No description provided for @mockLibraryNovel.
  ///
  /// In zh, this message translates to:
  /// **'小说'**
  String get mockLibraryNovel;

  /// No description provided for @mockLibraryNovelDescription.
  ///
  /// In zh, this message translates to:
  /// **'按章节阅读'**
  String get mockLibraryNovelDescription;

  /// No description provided for @mockLibraryParsingProgress.
  ///
  /// In zh, this message translates to:
  /// **'解析中 · {percent}%'**
  String mockLibraryParsingProgress(Object percent);

  /// No description provided for @mockLibraryPending.
  ///
  /// In zh, this message translates to:
  /// **'待处理'**
  String get mockLibraryPending;

  /// No description provided for @mockLibraryProcessing.
  ///
  /// In zh, this message translates to:
  /// **'处理中'**
  String get mockLibraryProcessing;

  /// No description provided for @mockLibraryQuestionCount.
  ///
  /// In zh, this message translates to:
  /// **' · {count} 题'**
  String mockLibraryQuestionCount(Object count);

  /// No description provided for @mockLibraryReadable.
  ///
  /// In zh, this message translates to:
  /// **'可阅读'**
  String get mockLibraryReadable;

  /// No description provided for @mockLibraryRecentlyUpdated.
  ///
  /// In zh, this message translates to:
  /// **'最近更新'**
  String get mockLibraryRecentlyUpdated;

  /// No description provided for @mockLibrarySelectedFile.
  ///
  /// In zh, this message translates to:
  /// **'已选文件：{name}'**
  String mockLibrarySelectedFile(String name);

  /// No description provided for @mockLibraryResetFilters.
  ///
  /// In zh, this message translates to:
  /// **'重置筛选'**
  String get mockLibraryResetFilters;

  /// No description provided for @mockLibrarySearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索标题或语言'**
  String get mockLibrarySearchHint;

  /// No description provided for @mockLibrarySearchMaterials.
  ///
  /// In zh, this message translates to:
  /// **'搜索材料'**
  String get mockLibrarySearchMaterials;

  /// No description provided for @mockLibraryTextbook.
  ///
  /// In zh, this message translates to:
  /// **'课本'**
  String get mockLibraryTextbook;

  /// No description provided for @mockLibraryTextbookDescription.
  ///
  /// In zh, this message translates to:
  /// **'按单元学习与练习'**
  String get mockLibraryTextbookDescription;

  /// No description provided for @mockLibraryTitle.
  ///
  /// In zh, this message translates to:
  /// **'材料库'**
  String get mockLibraryTitle;

  /// No description provided for @mockLibraryTryAnotherSearch.
  ///
  /// In zh, this message translates to:
  /// **'试试其他关键词，或清空筛选。'**
  String get mockLibraryTryAnotherSearch;

  /// No description provided for @mockLibraryUnitCount.
  ///
  /// In zh, this message translates to:
  /// **' · {count} 单元'**
  String mockLibraryUnitCount(Object count);

  /// No description provided for @mockLibraryViewDetails.
  ///
  /// In zh, this message translates to:
  /// **'查看详情'**
  String get mockLibraryViewDetails;

  /// No description provided for @mockLibraryViewMaterial.
  ///
  /// In zh, this message translates to:
  /// **'查看{title}'**
  String mockLibraryViewMaterial(Object title);

  /// No description provided for @mockShellAppTitle.
  ///
  /// In zh, this message translates to:
  /// **'Haruka'**
  String get mockShellAppTitle;

  /// No description provided for @mockShellBack.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get mockShellBack;

  /// No description provided for @mockShellEnglish.
  ///
  /// In zh, this message translates to:
  /// **'英语'**
  String get mockShellEnglish;

  /// No description provided for @mockShellExercise.
  ///
  /// In zh, this message translates to:
  /// **'练习'**
  String get mockShellExercise;

  /// No description provided for @mockShellJapanese.
  ///
  /// In zh, this message translates to:
  /// **'日语'**
  String get mockShellJapanese;

  /// No description provided for @mockShellLibrary.
  ///
  /// In zh, this message translates to:
  /// **'材料库'**
  String get mockShellLibrary;

  /// No description provided for @mockShellNotebooks.
  ///
  /// In zh, this message translates to:
  /// **'单词本'**
  String get mockShellNotebooks;

  /// No description provided for @mockShellNotifications.
  ///
  /// In zh, this message translates to:
  /// **'站内消息'**
  String get mockShellNotifications;

  /// No description provided for @mockShellQuery.
  ///
  /// In zh, this message translates to:
  /// **'查询'**
  String get mockShellQuery;

  /// No description provided for @mockShellSettings.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get mockShellSettings;

  /// No description provided for @mockExerciseCorrectFeedback.
  ///
  /// In zh, this message translates to:
  /// **'回答正确 ·「そっと」强调动作轻柔、避免打扰。'**
  String get mockExerciseCorrectFeedback;

  /// No description provided for @mockExerciseDiagnosis.
  ///
  /// In zh, this message translates to:
  /// **'学习诊断'**
  String get mockExerciseDiagnosis;

  /// No description provided for @mockExerciseDiagnosisTopics.
  ///
  /// In zh, this message translates to:
  /// **'方向助词 · 语境词义'**
  String get mockExerciseDiagnosisTopics;

  /// No description provided for @mockExerciseExisting.
  ///
  /// In zh, this message translates to:
  /// **'已有习题'**
  String get mockExerciseExisting;

  /// No description provided for @mockExerciseGenerate.
  ///
  /// In zh, this message translates to:
  /// **'生成 AI 习题'**
  String get mockExerciseGenerate;

  /// No description provided for @mockExerciseHistory.
  ///
  /// In zh, this message translates to:
  /// **'学习记录'**
  String get mockExerciseHistory;

  /// No description provided for @mockExerciseIncorrectFeedback.
  ///
  /// In zh, this message translates to:
  /// **'再看一眼 · 正确答案是「そっと」，强调动作轻柔。'**
  String get mockExerciseIncorrectFeedback;

  /// No description provided for @mockExerciseMistakes.
  ///
  /// In zh, this message translates to:
  /// **'错题库'**
  String get mockExerciseMistakes;

  /// No description provided for @mockExerciseMistakesCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 道待纠正'**
  String mockExerciseMistakesCount(int count);

  /// No description provided for @mockExerciseOptionA.
  ///
  /// In zh, this message translates to:
  /// **'そっと'**
  String get mockExerciseOptionA;

  /// No description provided for @mockExerciseOptionB.
  ///
  /// In zh, this message translates to:
  /// **'きっと'**
  String get mockExerciseOptionB;

  /// No description provided for @mockExerciseOptionC.
  ///
  /// In zh, this message translates to:
  /// **'ずっと'**
  String get mockExerciseOptionC;

  /// No description provided for @mockExerciseOptionD.
  ///
  /// In zh, this message translates to:
  /// **'もっと'**
  String get mockExerciseOptionD;

  /// No description provided for @mockExerciseQuestionProgress.
  ///
  /// In zh, this message translates to:
  /// **'题目 {current} / {total} · 日语'**
  String mockExerciseQuestionProgress(Object current, Object total);

  /// No description provided for @mockExerciseQuestionText.
  ///
  /// In zh, this message translates to:
  /// **'猫を起こさないように、ドアを（　）閉めた。'**
  String get mockExerciseQuestionText;

  /// No description provided for @mockExerciseQuestionTranslation.
  ///
  /// In zh, this message translates to:
  /// **'为了不把猫吵醒，轻轻关上门。'**
  String get mockExerciseQuestionTranslation;

  /// No description provided for @mockExerciseRetry.
  ///
  /// In zh, this message translates to:
  /// **'重做'**
  String get mockExerciseRetry;

  /// No description provided for @mockExerciseSampleSummary.
  ///
  /// In zh, this message translates to:
  /// **'日语 · {count} 道题'**
  String mockExerciseSampleSummary(int count);

  /// No description provided for @mockExerciseSampleTitle.
  ///
  /// In zh, this message translates to:
  /// **'语境中的表达'**
  String get mockExerciseSampleTitle;

  /// No description provided for @mockExerciseSelectSource.
  ///
  /// In zh, this message translates to:
  /// **'选择来源'**
  String get mockExerciseSelectSource;

  /// No description provided for @mockExerciseStart.
  ///
  /// In zh, this message translates to:
  /// **'开始练习'**
  String get mockExerciseStart;

  /// No description provided for @mockExerciseSubmit.
  ///
  /// In zh, this message translates to:
  /// **'提交答案'**
  String get mockExerciseSubmit;

  /// No description provided for @mockExerciseTitle.
  ///
  /// In zh, this message translates to:
  /// **'练习'**
  String get mockExerciseTitle;

  /// No description provided for @mockNotebookAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get mockNotebookAdd;

  /// No description provided for @mockNotebookAddCollection.
  ///
  /// In zh, this message translates to:
  /// **'添加收藏'**
  String get mockNotebookAddCollection;

  /// No description provided for @mockNotebookAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get mockNotebookAll;

  /// No description provided for @mockNotebookAllCollections.
  ///
  /// In zh, this message translates to:
  /// **'全部收藏'**
  String get mockNotebookAllCollections;

  /// No description provided for @mockNotebookAudioUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'音频暂不可用'**
  String get mockNotebookAudioUnavailable;

  /// No description provided for @mockNotebookCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get mockNotebookCancel;

  /// No description provided for @mockNotebookChooserTitle.
  ///
  /// In zh, this message translates to:
  /// **'切换与管理词本'**
  String get mockNotebookChooserTitle;

  /// No description provided for @mockNotebookClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get mockNotebookClose;

  /// No description provided for @mockNotebookCollectionCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条收藏'**
  String mockNotebookCollectionCount(int count);

  /// No description provided for @mockNotebookChinese.
  ///
  /// In zh, this message translates to:
  /// **'中文'**
  String get mockNotebookChinese;

  /// No description provided for @mockNotebookCreate.
  ///
  /// In zh, this message translates to:
  /// **'新建词本'**
  String get mockNotebookCreate;

  /// No description provided for @mockNotebookCsv.
  ///
  /// In zh, this message translates to:
  /// **'单词 CSV'**
  String get mockNotebookCsv;

  /// No description provided for @mockNotebookDailyWords.
  ///
  /// In zh, this message translates to:
  /// **'每日单词'**
  String get mockNotebookDailyWords;

  /// No description provided for @mockNotebookDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get mockNotebookDelete;

  /// No description provided for @mockNotebookDeleteConfirmMessage.
  ///
  /// In zh, this message translates to:
  /// **'只解除归类，收藏条目与学习状态仍保留。'**
  String get mockNotebookDeleteConfirmMessage;

  /// No description provided for @mockNotebookDeleteConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除词本？'**
  String get mockNotebookDeleteConfirmTitle;

  /// No description provided for @mockNotebookDeleteNotebook.
  ///
  /// In zh, this message translates to:
  /// **'删除词本'**
  String get mockNotebookDeleteNotebook;

  /// No description provided for @mockNotebookDeleteSummary.
  ///
  /// In zh, this message translates to:
  /// **'{name} · {count} 条收藏'**
  String mockNotebookDeleteSummary(String name, int count);

  /// No description provided for @mockNotebookDescription.
  ///
  /// In zh, this message translates to:
  /// **'简介'**
  String get mockNotebookDescription;

  /// No description provided for @mockNotebookEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'试试其他词形、读音或释义。'**
  String get mockNotebookEmptyHint;

  /// No description provided for @mockNotebookEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的收藏'**
  String get mockNotebookEmptyTitle;

  /// No description provided for @mockNotebookNoCollections.
  ///
  /// In zh, this message translates to:
  /// **'还没有收藏'**
  String get mockNotebookNoCollections;

  /// No description provided for @mockNotebookNoCollectionsHint.
  ///
  /// In zh, this message translates to:
  /// **'这里暂时没有已收藏的内容。'**
  String get mockNotebookNoCollectionsHint;

  /// No description provided for @mockNotebookEnglish.
  ///
  /// In zh, this message translates to:
  /// **'英语'**
  String get mockNotebookEnglish;

  /// No description provided for @mockNotebookGenerateExercise.
  ///
  /// In zh, this message translates to:
  /// **'生成 AI 习题'**
  String get mockNotebookGenerateExercise;

  /// No description provided for @mockNotebookInvalidName.
  ///
  /// In zh, this message translates to:
  /// **'名称不能为空或与现有词本重复'**
  String get mockNotebookInvalidName;

  /// No description provided for @mockNotebookJapanese.
  ///
  /// In zh, this message translates to:
  /// **'日语'**
  String get mockNotebookJapanese;

  /// No description provided for @mockNotebookKindExcerpt.
  ///
  /// In zh, this message translates to:
  /// **'摘录'**
  String get mockNotebookKindExcerpt;

  /// No description provided for @mockNotebookKindExercise.
  ///
  /// In zh, this message translates to:
  /// **'习题'**
  String get mockNotebookKindExercise;

  /// No description provided for @mockNotebookKindGrammar.
  ///
  /// In zh, this message translates to:
  /// **'语法'**
  String get mockNotebookKindGrammar;

  /// No description provided for @mockNotebookKindPhrase.
  ///
  /// In zh, this message translates to:
  /// **'短语'**
  String get mockNotebookKindPhrase;

  /// No description provided for @mockNotebookKindSentence.
  ///
  /// In zh, this message translates to:
  /// **'句子'**
  String get mockNotebookKindSentence;

  /// No description provided for @mockNotebookKindWord.
  ///
  /// In zh, this message translates to:
  /// **'单词'**
  String get mockNotebookKindWord;

  /// No description provided for @mockNotebookLanguage.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get mockNotebookLanguage;

  /// No description provided for @mockNotebookLanguageAndCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条收藏 · {language}'**
  String mockNotebookLanguageAndCount(Object count, Object language);

  /// No description provided for @mockNotebookManage.
  ///
  /// In zh, this message translates to:
  /// **'管理词本'**
  String get mockNotebookManage;

  /// No description provided for @mockNotebookManageNamed.
  ///
  /// In zh, this message translates to:
  /// **'管理{name}'**
  String mockNotebookManageNamed(String name);

  /// No description provided for @mockNotebookName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get mockNotebookName;

  /// No description provided for @mockNotebookReadNamed.
  ///
  /// In zh, this message translates to:
  /// **'朗读{text}'**
  String mockNotebookReadNamed(String text);

  /// No description provided for @mockNotebookSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get mockNotebookSave;

  /// No description provided for @mockNotebookSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索收藏内容'**
  String get mockNotebookSearchHint;

  /// No description provided for @mockNotebookTitle.
  ///
  /// In zh, this message translates to:
  /// **'单词本'**
  String get mockNotebookTitle;

  /// No description provided for @mockQueryAgain.
  ///
  /// In zh, this message translates to:
  /// **'再查一个'**
  String get mockQueryAgain;

  /// No description provided for @mockQueryAudioUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'音频暂不可用'**
  String get mockQueryAudioUnavailable;

  /// No description provided for @mockQueryCamera.
  ///
  /// In zh, this message translates to:
  /// **'拍照'**
  String get mockQueryCamera;

  /// No description provided for @mockQueryCameraPermissionDenied.
  ///
  /// In zh, this message translates to:
  /// **'无法使用相机，请检查相机权限'**
  String get mockQueryCameraPermissionDenied;

  /// No description provided for @mockQueryCameraUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'相机不可用，请从相册选择'**
  String get mockQueryCameraUnavailable;

  /// No description provided for @mockQueryCardKindExcerpt.
  ///
  /// In zh, this message translates to:
  /// **'摘录'**
  String get mockQueryCardKindExcerpt;

  /// No description provided for @mockQueryCardKindExercise.
  ///
  /// In zh, this message translates to:
  /// **'习题'**
  String get mockQueryCardKindExercise;

  /// No description provided for @mockQueryCardKindGrammar.
  ///
  /// In zh, this message translates to:
  /// **'语法'**
  String get mockQueryCardKindGrammar;

  /// No description provided for @mockQueryCardKindPhrase.
  ///
  /// In zh, this message translates to:
  /// **'短语'**
  String get mockQueryCardKindPhrase;

  /// No description provided for @mockQueryCardKindSentence.
  ///
  /// In zh, this message translates to:
  /// **'句子'**
  String get mockQueryCardKindSentence;

  /// No description provided for @mockQueryCardKindWord.
  ///
  /// In zh, this message translates to:
  /// **'单词'**
  String get mockQueryCardKindWord;

  /// No description provided for @mockQueryContextHint.
  ///
  /// In zh, this message translates to:
  /// **'补充与本次查询有关的上下文'**
  String get mockQueryContextHint;

  /// No description provided for @mockQueryContextToggle.
  ///
  /// In zh, this message translates to:
  /// **'补充上下文（可选）'**
  String get mockQueryContextToggle;

  /// No description provided for @mockQueryDesktopImageHint.
  ///
  /// In zh, this message translates to:
  /// **'可粘贴图片'**
  String get mockQueryDesktopImageHint;

  /// No description provided for @mockQueryExampleCorrection.
  ///
  /// In zh, this message translates to:
  /// **'批改：昨日、図書館に行きます。'**
  String get mockQueryExampleCorrection;

  /// No description provided for @mockQueryExampleGrammar.
  ///
  /// In zh, this message translates to:
  /// **'に 和 へ 有什么区别？'**
  String get mockQueryExampleGrammar;

  /// No description provided for @mockQueryExampleTranslation.
  ///
  /// In zh, this message translates to:
  /// **'翻译：夏の風がそっと頬に触れた。'**
  String get mockQueryExampleTranslation;

  /// No description provided for @mockQueryExampleWord.
  ///
  /// In zh, this message translates to:
  /// **'そっと 是什么意思？'**
  String get mockQueryExampleWord;

  /// No description provided for @mockQueryExamplesTitle.
  ///
  /// In zh, this message translates to:
  /// **'试试这样查询'**
  String get mockQueryExamplesTitle;

  /// No description provided for @mockQueryGallery.
  ///
  /// In zh, this message translates to:
  /// **'相册'**
  String get mockQueryGallery;

  /// No description provided for @mockQueryImage.
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get mockQueryImage;

  /// No description provided for @mockQueryImageAttached.
  ///
  /// In zh, this message translates to:
  /// **'已选择图片'**
  String get mockQueryImageAttached;

  /// No description provided for @mockQueryImageExample.
  ///
  /// In zh, this message translates to:
  /// **'图片查询'**
  String get mockQueryImageExample;

  /// No description provided for @mockQueryImageInvalid.
  ///
  /// In zh, this message translates to:
  /// **'无法读取图片，请重新选择'**
  String get mockQueryImageInvalid;

  /// No description provided for @mockQueryImagePreview.
  ///
  /// In zh, this message translates to:
  /// **'查看图片'**
  String get mockQueryImagePreview;

  /// No description provided for @mockQueryImageRemove.
  ///
  /// In zh, this message translates to:
  /// **'移除图片'**
  String get mockQueryImageRemove;

  /// No description provided for @mockQueryImageTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'图片超过大小或像素限制'**
  String get mockQueryImageTooLarge;

  /// No description provided for @mockQueryImageTooMany.
  ///
  /// In zh, this message translates to:
  /// **'最多添加 4 张图片'**
  String get mockQueryImageTooMany;

  /// No description provided for @mockQueryImageUnanalysed.
  ///
  /// In zh, this message translates to:
  /// **'图片尚未分析，无法生成学习卡片'**
  String get mockQueryImageUnanalysed;

  /// No description provided for @mockQueryImageUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'请选择 PNG、JPEG 或 WebP 图片'**
  String get mockQueryImageUnsupported;

  /// No description provided for @mockQueryInputHint.
  ///
  /// In zh, this message translates to:
  /// **'输入单词、句子、语法问题，或添加图片…'**
  String get mockQueryInputHint;

  /// No description provided for @mockQueryInputTooLong.
  ///
  /// In zh, this message translates to:
  /// **'输入超过 2000 字，请删减后再添加'**
  String get mockQueryInputTooLong;

  /// No description provided for @mockQueryLearningLabel.
  ///
  /// In zh, this message translates to:
  /// **'语言学习'**
  String get mockQueryLearningLabel;

  /// No description provided for @mockQueryMobileImageHint.
  ///
  /// In zh, this message translates to:
  /// **'可选择图片'**
  String get mockQueryMobileImageHint;

  /// No description provided for @mockQueryReadAloud.
  ///
  /// In zh, this message translates to:
  /// **'朗读'**
  String get mockQueryReadAloud;

  /// No description provided for @mockQueryBookmarkTitle.
  ///
  /// In zh, this message translates to:
  /// **'收藏卡片'**
  String get mockQueryBookmarkTitle;

  /// No description provided for @mockQueryBookmarked.
  ///
  /// In zh, this message translates to:
  /// **'已收藏'**
  String get mockQueryBookmarked;

  /// No description provided for @mockQuerySaveCard.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get mockQuerySaveCard;

  /// No description provided for @mockQuerySaved.
  ///
  /// In zh, this message translates to:
  /// **'已加入收藏'**
  String get mockQuerySaved;

  /// No description provided for @mockQueryAlreadySaved.
  ///
  /// In zh, this message translates to:
  /// **'已在收藏中'**
  String get mockQueryAlreadySaved;

  /// No description provided for @mockQuerySend.
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get mockQuerySend;

  /// No description provided for @mockQueryRequestFailed.
  ///
  /// In zh, this message translates to:
  /// **'查询暂时未完成，请重试'**
  String get mockQueryRequestFailed;

  /// No description provided for @mockQuerySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'理解一个词，读懂一句话。'**
  String get mockQuerySubtitle;

  /// No description provided for @mockQueryTitle.
  ///
  /// In zh, this message translates to:
  /// **'查询'**
  String get mockQueryTitle;

  /// No description provided for @mockQueryLanguage.
  ///
  /// In zh, this message translates to:
  /// **'日语'**
  String get mockQueryLanguage;

  /// No description provided for @mockQueryMeaningLabel.
  ///
  /// In zh, this message translates to:
  /// **'释义'**
  String get mockQueryMeaningLabel;

  /// No description provided for @mockQueryWordMeaning.
  ///
  /// In zh, this message translates to:
  /// **'轻轻地；悄悄地'**
  String get mockQueryWordMeaning;

  /// No description provided for @mockQueryWordUsage.
  ///
  /// In zh, this message translates to:
  /// **'用于动作轻柔，或不希望打扰别人的场景。'**
  String get mockQueryWordUsage;

  /// No description provided for @mockQueryWordRomanization.
  ///
  /// In zh, this message translates to:
  /// **'sotto'**
  String get mockQueryWordRomanization;

  /// No description provided for @mockQueryWordPartOfSpeech.
  ///
  /// In zh, this message translates to:
  /// **'副词'**
  String get mockQueryWordPartOfSpeech;

  /// No description provided for @mockQueryContextExamples.
  ///
  /// In zh, this message translates to:
  /// **'语境例句'**
  String get mockQueryContextExamples;

  /// No description provided for @mockQueryWordExampleOne.
  ///
  /// In zh, this message translates to:
  /// **'ドアをそっと閉めた。'**
  String get mockQueryWordExampleOne;

  /// No description provided for @mockQueryWordExampleOneTranslation.
  ///
  /// In zh, this message translates to:
  /// **'轻轻地关上了门。'**
  String get mockQueryWordExampleOneTranslation;

  /// No description provided for @mockQueryWordExampleTwo.
  ///
  /// In zh, this message translates to:
  /// **'そっと手を握った。'**
  String get mockQueryWordExampleTwo;

  /// No description provided for @mockQueryWordExampleTwoTranslation.
  ///
  /// In zh, this message translates to:
  /// **'轻轻握住了手。'**
  String get mockQueryWordExampleTwoTranslation;

  /// No description provided for @mockQueryTranslationLabel.
  ///
  /// In zh, this message translates to:
  /// **'译文'**
  String get mockQueryTranslationLabel;

  /// No description provided for @mockQuerySentenceTranslation.
  ///
  /// In zh, this message translates to:
  /// **'夏风轻轻拂过脸颊。'**
  String get mockQuerySentenceTranslation;

  /// No description provided for @mockQuerySentenceUsage.
  ///
  /// In zh, this message translates to:
  /// **'そっと 描绘风拂过脸颊时轻柔的动作，让句子更有画面感。'**
  String get mockQuerySentenceUsage;

  /// No description provided for @mockQueryGrammarPoint.
  ///
  /// In zh, this message translates to:
  /// **'语法提示'**
  String get mockQueryGrammarPoint;

  /// No description provided for @mockQuerySentenceGrammar.
  ///
  /// In zh, this message translates to:
  /// **'名词 + に + 触れる：触碰到某物。'**
  String get mockQuerySentenceGrammar;

  /// No description provided for @mockQueryGrammarCoreLabel.
  ///
  /// In zh, this message translates to:
  /// **'核心用法'**
  String get mockQueryGrammarCoreLabel;

  /// No description provided for @mockQueryGrammarCore.
  ///
  /// In zh, this message translates to:
  /// **'目的地与移动方向'**
  String get mockQueryGrammarCore;

  /// No description provided for @mockQueryGrammarUsage.
  ///
  /// In zh, this message translates to:
  /// **'「に」强调到达的地点；「へ」强调移动的方向。表示移动的句子中常可互换。'**
  String get mockQueryGrammarUsage;

  /// No description provided for @mockQueryGrammarNiLabel.
  ///
  /// In zh, this message translates to:
  /// **'に · 到达点'**
  String get mockQueryGrammarNiLabel;

  /// No description provided for @mockQueryGrammarNiTranslation.
  ///
  /// In zh, this message translates to:
  /// **'去车站，强调目的地。'**
  String get mockQueryGrammarNiTranslation;

  /// No description provided for @mockQueryGrammarHeLabel.
  ///
  /// In zh, this message translates to:
  /// **'へ · 方向'**
  String get mockQueryGrammarHeLabel;

  /// No description provided for @mockQueryGrammarHeTranslation.
  ///
  /// In zh, this message translates to:
  /// **'往车站去，强调方向。'**
  String get mockQueryGrammarHeTranslation;

  /// No description provided for @mockQueryCorrectionFocusLabel.
  ///
  /// In zh, this message translates to:
  /// **'订正重点'**
  String get mockQueryCorrectionFocusLabel;

  /// No description provided for @mockQueryCorrectionFocus.
  ///
  /// In zh, this message translates to:
  /// **'过去时间需要搭配过去式'**
  String get mockQueryCorrectionFocus;

  /// No description provided for @mockQueryCorrectionOriginalLabel.
  ///
  /// In zh, this message translates to:
  /// **'原作答'**
  String get mockQueryCorrectionOriginalLabel;

  /// No description provided for @mockQueryCorrectionOriginal.
  ///
  /// In zh, this message translates to:
  /// **'行きます'**
  String get mockQueryCorrectionOriginal;

  /// No description provided for @mockQueryCorrectionSuggestedLabel.
  ///
  /// In zh, this message translates to:
  /// **'建议订正'**
  String get mockQueryCorrectionSuggestedLabel;

  /// No description provided for @mockQueryCorrectionSuggested.
  ///
  /// In zh, this message translates to:
  /// **'行きました'**
  String get mockQueryCorrectionSuggested;

  /// No description provided for @mockQueryCorrectionSentence.
  ///
  /// In zh, this message translates to:
  /// **'昨日、図書館に行きました。'**
  String get mockQueryCorrectionSentence;

  /// No description provided for @mockQueryCorrectionExplanation.
  ///
  /// In zh, this message translates to:
  /// **'「昨日」表示昨天。这里叙述已经发生的动作，应将「行きます」改为过去式「行きました」。'**
  String get mockQueryCorrectionExplanation;

  /// No description provided for @mockMaterialChapterNumber.
  ///
  /// In zh, this message translates to:
  /// **'第 {number} 章'**
  String mockMaterialChapterNumber(int number);

  /// No description provided for @mockMaterialChapterTitle.
  ///
  /// In zh, this message translates to:
  /// **'第 {number} 章 · {title}'**
  String mockMaterialChapterTitle(int number, String title);

  /// No description provided for @mockMaterialNumberedTitle.
  ///
  /// In zh, this message translates to:
  /// **'{number}  {title}'**
  String mockMaterialNumberedTitle(String number, String title);

  /// No description provided for @mockMaterialUnitTitle.
  ///
  /// In zh, this message translates to:
  /// **'Unit {number} · {title}'**
  String mockMaterialUnitTitle(String number, String title);

  /// No description provided for @mockSupportAnswerCardNumber.
  ///
  /// In zh, this message translates to:
  /// **'{number}{mark}'**
  String mockSupportAnswerCardNumber(int number, String mark);

  /// No description provided for @mockSupportAnsweredMark.
  ///
  /// In zh, this message translates to:
  /// **' ✓'**
  String get mockSupportAnsweredMark;

  /// No description provided for @mockSupportEnglish.
  ///
  /// In zh, this message translates to:
  /// **'英语'**
  String get mockSupportEnglish;

  /// No description provided for @mockSupportJapanese.
  ///
  /// In zh, this message translates to:
  /// **'日语'**
  String get mockSupportJapanese;

  /// No description provided for @mockSupportKindLanguage.
  ///
  /// In zh, this message translates to:
  /// **'{kind} · {language}'**
  String mockSupportKindLanguage(String kind, String language);

  /// No description provided for @mockSupportLanguageSources.
  ///
  /// In zh, this message translates to:
  /// **'语言：{language} · 来源 {count} 类'**
  String mockSupportLanguageSources(String language, int count);

  /// No description provided for @mockSupportNotificationSummary.
  ///
  /// In zh, this message translates to:
  /// **'{status}  ·  {detail}'**
  String mockSupportNotificationSummary(String status, String detail);

  /// No description provided for @mockSupportProgress.
  ///
  /// In zh, this message translates to:
  /// **'解析中 · {percent}%'**
  String mockSupportProgress(int percent);

  /// No description provided for @mockSupportQuestionPosition.
  ///
  /// In zh, this message translates to:
  /// **'题目 {question} / 3'**
  String mockSupportQuestionPosition(int question);

  /// No description provided for @mockSupportRead.
  ///
  /// In zh, this message translates to:
  /// **'已读'**
  String get mockSupportRead;

  /// No description provided for @mockSupportSelectedSources.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 项内容，相同收藏只计一次。'**
  String mockSupportSelectedSources(int count);

  /// No description provided for @mockSupportSpeakWord.
  ///
  /// In zh, this message translates to:
  /// **'朗读{word}'**
  String mockSupportSpeakWord(String word);

  /// No description provided for @mockSupportStep.
  ///
  /// In zh, this message translates to:
  /// **'步骤 {step} / 2'**
  String mockSupportStep(int step);

  /// No description provided for @mockSupportUnread.
  ///
  /// In zh, this message translates to:
  /// **'新消息'**
  String get mockSupportUnread;

  /// No description provided for @mockSupportUpdatesEyebrow.
  ///
  /// In zh, this message translates to:
  /// **'IN-APP UPDATES'**
  String get mockSupportUpdatesEyebrow;

  /// No description provided for @mockSupportVisibleAnswer.
  ///
  /// In zh, this message translates to:
  /// **'可见参考答案：{answer}'**
  String mockSupportVisibleAnswer(String answer);

  /// No description provided for @mockLibraryJobProgress.
  ///
  /// In zh, this message translates to:
  /// **'任务进度'**
  String get mockLibraryJobProgress;

  /// No description provided for @mockShellNavMaterials.
  ///
  /// In zh, this message translates to:
  /// **'材料'**
  String get mockShellNavMaterials;

  /// No description provided for @mockShellNavNotebooks.
  ///
  /// In zh, this message translates to:
  /// **'词本'**
  String get mockShellNavNotebooks;

  /// No description provided for @mockExerciseSourceDescription.
  ///
  /// In zh, this message translates to:
  /// **'从词本、教材或错题中选源'**
  String get mockExerciseSourceDescription;

  /// No description provided for @mockMaterialCurrentRevision.
  ///
  /// In zh, this message translates to:
  /// **'当前内容版本：{revision}'**
  String mockMaterialCurrentRevision(int revision);

  /// No description provided for @mockMaterialEnglish.
  ///
  /// In zh, this message translates to:
  /// **'英语'**
  String get mockMaterialEnglish;

  /// No description provided for @mockMaterialJapanese.
  ///
  /// In zh, this message translates to:
  /// **'日语'**
  String get mockMaterialJapanese;

  /// No description provided for @mockMaterialLanguageDetail.
  ///
  /// In zh, this message translates to:
  /// **'语言：{language}'**
  String mockMaterialLanguageDetail(String language);

  /// No description provided for @mockMaterialStatusDetail.
  ///
  /// In zh, this message translates to:
  /// **'状态：{status}'**
  String mockMaterialStatusDetail(String status);

  /// No description provided for @mockMaterialTypeDetail.
  ///
  /// In zh, this message translates to:
  /// **'类型：{type}'**
  String mockMaterialTypeDetail(String type);

  /// No description provided for @mockSettingCacheCounts.
  ///
  /// In zh, this message translates to:
  /// **'{explanations} 份解释 · {audio} 段音频'**
  String mockSettingCacheCounts(int explanations, int audio);

  /// No description provided for @mockSettingMegabytes.
  ///
  /// In zh, this message translates to:
  /// **'{amount} MB'**
  String mockSettingMegabytes(String amount);

  /// No description provided for @mockSettingPlaybackRate.
  ///
  /// In zh, this message translates to:
  /// **'{rate}×'**
  String mockSettingPlaybackRate(String rate);

  /// No description provided for @mockMaterialExamPreparationTitle.
  ///
  /// In zh, this message translates to:
  /// **'试卷准备'**
  String get mockMaterialExamPreparationTitle;

  /// No description provided for @mockSupportAddCollection.
  ///
  /// In zh, this message translates to:
  /// **'添加收藏'**
  String get mockSupportAddCollection;

  /// No description provided for @mockSupportAssignToNotebook.
  ///
  /// In zh, this message translates to:
  /// **'归入单词本'**
  String get mockSupportAssignToNotebook;

  /// No description provided for @mockSupportAudioUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'音频暂不可用'**
  String get mockSupportAudioUnavailable;

  /// No description provided for @mockSupportCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get mockSupportCancel;

  /// No description provided for @mockSupportCollectionContentField.
  ///
  /// In zh, this message translates to:
  /// **'内容'**
  String get mockSupportCollectionContentField;

  /// No description provided for @mockSupportCollectionContextExamples.
  ///
  /// In zh, this message translates to:
  /// **'语境例句'**
  String get mockSupportCollectionContextExamples;

  /// No description provided for @mockSupportCollectionDeleted.
  ///
  /// In zh, this message translates to:
  /// **'收藏已删除'**
  String get mockSupportCollectionDeleted;

  /// No description provided for @mockSupportCollectionDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'收藏详情'**
  String get mockSupportCollectionDetailTitle;

  /// No description provided for @mockSupportCollectionKindField.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get mockSupportCollectionKindField;

  /// No description provided for @mockSupportCollectionMasteryEvidenceHint.
  ///
  /// In zh, this message translates to:
  /// **'掌握：按有效习题证据计算，不能手动修改。'**
  String get mockSupportCollectionMasteryEvidenceHint;

  /// No description provided for @mockSupportCollectionMeaningField.
  ///
  /// In zh, this message translates to:
  /// **'释义'**
  String get mockSupportCollectionMeaningField;

  /// No description provided for @mockSupportCsvChooseUtf8.
  ///
  /// In zh, this message translates to:
  /// **'选择 UTF-8 CSV'**
  String get mockSupportCsvChooseUtf8;

  /// No description provided for @mockSupportCsvConfirmImport.
  ///
  /// In zh, this message translates to:
  /// **'确认导入'**
  String get mockSupportCsvConfirmImport;

  /// No description provided for @mockSupportCsvExampleFilename.
  ///
  /// In zh, this message translates to:
  /// **'单词.csv'**
  String get mockSupportCsvExampleFilename;

  /// No description provided for @mockSupportCsvExportEntries.
  ///
  /// In zh, this message translates to:
  /// **'导出词条'**
  String get mockSupportCsvExportEntries;

  /// No description provided for @mockSupportCsvExportReadyToast.
  ///
  /// In zh, this message translates to:
  /// **'CSV 已生成'**
  String get mockSupportCsvExportReadyToast;

  /// No description provided for @mockSupportCsvExportScopeHint.
  ///
  /// In zh, this message translates to:
  /// **'导出全部单词，包含词本归属、释义与个人笔记。'**
  String get mockSupportCsvExportScopeHint;

  /// No description provided for @mockSupportCsvGenerateExample.
  ///
  /// In zh, this message translates to:
  /// **'下载单词 CSV'**
  String get mockSupportCsvGenerateExample;

  /// No description provided for @mockSupportCsvImportConfirmedToast.
  ///
  /// In zh, this message translates to:
  /// **'导入已确认'**
  String get mockSupportCsvImportConfirmedToast;

  /// No description provided for @mockSupportCsvImportExportTitle.
  ///
  /// In zh, this message translates to:
  /// **'单词导入与导出'**
  String get mockSupportCsvImportExportTitle;

  /// No description provided for @mockSupportCsvImportPreview.
  ///
  /// In zh, this message translates to:
  /// **'导入预览'**
  String get mockSupportCsvImportPreview;

  /// No description provided for @mockSupportCsvPreviewHint.
  ///
  /// In zh, this message translates to:
  /// **'导入前可预览词条与重复项。'**
  String get mockSupportCsvPreviewHint;

  /// No description provided for @mockSupportCsvPreviewSummary.
  ///
  /// In zh, this message translates to:
  /// **'导入预览'**
  String get mockSupportCsvPreviewSummary;

  /// No description provided for @mockSupportCsvShowPreview.
  ///
  /// In zh, this message translates to:
  /// **'查看导入预览'**
  String get mockSupportCsvShowPreview;

  /// No description provided for @mockSupportCsvTitle.
  ///
  /// In zh, this message translates to:
  /// **'单词 CSV'**
  String get mockSupportCsvTitle;

  /// No description provided for @mockCsvCreateDuplicates.
  ///
  /// In zh, this message translates to:
  /// **'创建新词条'**
  String get mockCsvCreateDuplicates;

  /// No description provided for @mockCsvDefaultLanguage.
  ///
  /// In zh, this message translates to:
  /// **'缺少语言时使用'**
  String get mockCsvDefaultLanguage;

  /// No description provided for @mockCsvDownloadStarted.
  ///
  /// In zh, this message translates to:
  /// **'已交给浏览器下载'**
  String get mockCsvDownloadStarted;

  /// No description provided for @mockCsvDuplicateAction.
  ///
  /// In zh, this message translates to:
  /// **'重复项处理'**
  String get mockCsvDuplicateAction;

  /// No description provided for @mockCsvEmptyWord.
  ///
  /// In zh, this message translates to:
  /// **'空词形'**
  String get mockCsvEmptyWord;

  /// No description provided for @mockCsvExcludeErrors.
  ///
  /// In zh, this message translates to:
  /// **'排除错误行后导入'**
  String get mockCsvExcludeErrors;

  /// No description provided for @mockCsvExistingDuplicate.
  ///
  /// In zh, this message translates to:
  /// **'词表中已有'**
  String get mockCsvExistingDuplicate;

  /// No description provided for @mockCsvFileDuplicate.
  ///
  /// In zh, this message translates to:
  /// **'文件内重复'**
  String get mockCsvFileDuplicate;

  /// No description provided for @mockCsvFileReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取 CSV 文件'**
  String get mockCsvFileReadFailed;

  /// No description provided for @mockCsvMergeDuplicates.
  ///
  /// In zh, this message translates to:
  /// **'补全空白字段'**
  String get mockCsvMergeDuplicates;

  /// No description provided for @mockCsvProblemEmptyFile.
  ///
  /// In zh, this message translates to:
  /// **'文件为空'**
  String get mockCsvProblemEmptyFile;

  /// No description provided for @mockCsvProblemFieldTooLong.
  ///
  /// In zh, this message translates to:
  /// **'字段过长'**
  String get mockCsvProblemFieldTooLong;

  /// No description provided for @mockCsvProblemInvalidDate.
  ///
  /// In zh, this message translates to:
  /// **'时间格式无效'**
  String get mockCsvProblemInvalidDate;

  /// No description provided for @mockCsvProblemInvalidEscape.
  ///
  /// In zh, this message translates to:
  /// **'转义协议不支持'**
  String get mockCsvProblemInvalidEscape;

  /// No description provided for @mockCsvProblemInvalidExerciseControl.
  ///
  /// In zh, this message translates to:
  /// **'习题控制值无效'**
  String get mockCsvProblemInvalidExerciseControl;

  /// No description provided for @mockCsvProblemInvalidLanguage.
  ///
  /// In zh, this message translates to:
  /// **'语言仅支持日语或英语'**
  String get mockCsvProblemInvalidLanguage;

  /// No description provided for @mockCsvProblemInvalidLocator.
  ///
  /// In zh, this message translates to:
  /// **'来源定位需要重新验证'**
  String get mockCsvProblemInvalidLocator;

  /// No description provided for @mockCsvProblemInvalidQuotes.
  ///
  /// In zh, this message translates to:
  /// **'引号格式无效'**
  String get mockCsvProblemInvalidQuotes;

  /// No description provided for @mockCsvProblemInvalidStatus.
  ///
  /// In zh, this message translates to:
  /// **'来源状态无效'**
  String get mockCsvProblemInvalidStatus;

  /// No description provided for @mockCsvProblemInvalidTags.
  ///
  /// In zh, this message translates to:
  /// **'标签 JSON 无效'**
  String get mockCsvProblemInvalidTags;

  /// No description provided for @mockCsvProblemInvalidUtf8.
  ///
  /// In zh, this message translates to:
  /// **'文件不是有效的 UTF-8'**
  String get mockCsvProblemInvalidUtf8;

  /// No description provided for @mockCsvProblemInvalidVersion.
  ///
  /// In zh, this message translates to:
  /// **'CSV 版本不支持'**
  String get mockCsvProblemInvalidVersion;

  /// No description provided for @mockCsvProblemInvalidWordbooks.
  ///
  /// In zh, this message translates to:
  /// **'词本 JSON 无效'**
  String get mockCsvProblemInvalidWordbooks;

  /// No description provided for @mockCsvProblemMissingWord.
  ///
  /// In zh, this message translates to:
  /// **'缺少词形'**
  String get mockCsvProblemMissingWord;

  /// No description provided for @mockCsvProblemMissingWordColumn.
  ///
  /// In zh, this message translates to:
  /// **'缺少 word 列'**
  String get mockCsvProblemMissingWordColumn;

  /// No description provided for @mockCsvProblemRepeatedColumn.
  ///
  /// In zh, this message translates to:
  /// **'表头列重复'**
  String get mockCsvProblemRepeatedColumn;

  /// No description provided for @mockCsvProblemRowWidth.
  ///
  /// In zh, this message translates to:
  /// **'列数与表头不符'**
  String get mockCsvProblemRowWidth;

  /// No description provided for @mockCsvProblemTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'文件超过 10 MB'**
  String get mockCsvProblemTooLarge;

  /// No description provided for @mockCsvProblemTooManyRows.
  ///
  /// In zh, this message translates to:
  /// **'记录超过 10000 行'**
  String get mockCsvProblemTooManyRows;

  /// No description provided for @mockCsvReadyRow.
  ///
  /// In zh, this message translates to:
  /// **'可导入'**
  String get mockCsvReadyRow;

  /// No description provided for @mockCsvSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'CSV 保存失败'**
  String get mockCsvSaveFailed;

  /// No description provided for @mockCsvSaved.
  ///
  /// In zh, this message translates to:
  /// **'CSV 已保存'**
  String get mockCsvSaved;

  /// No description provided for @mockCsvSkipDuplicates.
  ///
  /// In zh, this message translates to:
  /// **'跳过重复'**
  String get mockCsvSkipDuplicates;

  /// No description provided for @mockCsvSystemFlowOpened.
  ///
  /// In zh, this message translates to:
  /// **'已打开系统保存选项'**
  String get mockCsvSystemFlowOpened;

  /// No description provided for @mockCsvSourceUnbound.
  ///
  /// In zh, this message translates to:
  /// **'来源回跳未恢复'**
  String get mockCsvSourceUnbound;

  /// No description provided for @mockCsvPreviewCounts.
  ///
  /// In zh, this message translates to:
  /// **'共 {total} 行 · 新词 {newCount} · 重复 {duplicates} · 错误 {errors}'**
  String mockCsvPreviewCounts(int total, int newCount, int duplicates, int errors);

  /// No description provided for @mockCsvRowLabel.
  ///
  /// In zh, this message translates to:
  /// **'第 {number} 行 · {word}'**
  String mockCsvRowLabel(int number, String word);

  /// No description provided for @mockCsvImportResult.
  ///
  /// In zh, this message translates to:
  /// **'新增 {added} · 补全 {merged} · 跳过 {skipped} · 排除 {excluded}'**
  String mockCsvImportResult(int added, int merged, int skipped, int excluded);

  /// No description provided for @mockSupportDailyWordsAddedToday.
  ///
  /// In zh, this message translates to:
  /// **'当日加入'**
  String get mockSupportDailyWordsAddedToday;

  /// No description provided for @mockSupportDailyWordsDate.
  ///
  /// In zh, this message translates to:
  /// **'日期'**
  String get mockSupportDailyWordsDate;

  /// No description provided for @mockSupportDailyWordsEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'选择其他日期查看。'**
  String get mockSupportDailyWordsEmptyHint;

  /// No description provided for @mockSupportDailyWordsEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'这天没有加入单词'**
  String get mockSupportDailyWordsEmptyTitle;

  /// No description provided for @mockSupportDailyWordsScopeDescription.
  ///
  /// In zh, this message translates to:
  /// **'{timezone} · 全部单词本，重复归类只计一次'**
  String mockSupportDailyWordsScopeDescription(String timezone);

  /// No description provided for @mockSupportDailyWordsTitle.
  ///
  /// In zh, this message translates to:
  /// **'每日单词'**
  String get mockSupportDailyWordsTitle;

  /// No description provided for @mockSupportDailyWordsWordCountUnit.
  ///
  /// In zh, this message translates to:
  /// **'个单词'**
  String get mockSupportDailyWordsWordCountUnit;

  /// No description provided for @mockSupportDiagnosisChooseSource.
  ///
  /// In zh, this message translates to:
  /// **'选择习题来源'**
  String get mockSupportDiagnosisChooseSource;

  /// No description provided for @mockSupportDiagnosisDirectionEvidence.
  ///
  /// In zh, this message translates to:
  /// **'教材 Unit 02 的有效作答显示，「に / へ」仍容易混淆。'**
  String get mockSupportDiagnosisDirectionEvidence;

  /// No description provided for @mockSupportDiagnosisDirectionFocus.
  ///
  /// In zh, this message translates to:
  /// **'方向助词值得再练'**
  String get mockSupportDiagnosisDirectionFocus;

  /// No description provided for @mockSupportDiagnosisDirectionShortTitle.
  ///
  /// In zh, this message translates to:
  /// **'方向助词'**
  String get mockSupportDiagnosisDirectionShortTitle;

  /// No description provided for @mockSupportDiagnosisEvidenceDisclaimer.
  ///
  /// In zh, this message translates to:
  /// **'依据可靠作答和来源形成诊断。'**
  String get mockSupportDiagnosisEvidenceDisclaimer;

  /// No description provided for @mockSupportDiagnosisNextStep.
  ///
  /// In zh, this message translates to:
  /// **'下一步'**
  String get mockSupportDiagnosisNextStep;

  /// No description provided for @mockSupportDiagnosisNextStepTitle.
  ///
  /// In zh, this message translates to:
  /// **'选源练习'**
  String get mockSupportDiagnosisNextStepTitle;

  /// No description provided for @mockSupportDiagnosisNextStepDescription.
  ///
  /// In zh, this message translates to:
  /// **'从教材或当前错题明确选源，预览后再生成针对性习题。'**
  String get mockSupportDiagnosisNextStepDescription;

  /// No description provided for @mockSupportDiagnosisRecentSevenDays.
  ///
  /// In zh, this message translates to:
  /// **'最近 7 天'**
  String get mockSupportDiagnosisRecentSevenDays;

  /// No description provided for @mockSupportDiagnosisReturnToTextbook.
  ///
  /// In zh, this message translates to:
  /// **'回到教材 →'**
  String get mockSupportDiagnosisReturnToTextbook;

  /// No description provided for @mockSupportDiagnosisStrengthDescription.
  ///
  /// In zh, this message translates to:
  /// **'在有语境的词义选择题里，你能留意句子的情绪与动作方式。'**
  String get mockSupportDiagnosisStrengthDescription;

  /// No description provided for @mockSupportDiagnosisStrengths.
  ///
  /// In zh, this message translates to:
  /// **'亮点'**
  String get mockSupportDiagnosisStrengths;

  /// No description provided for @mockSupportDiagnosisStrengthTitle.
  ///
  /// In zh, this message translates to:
  /// **'语境词义'**
  String get mockSupportDiagnosisStrengthTitle;

  /// No description provided for @mockSupportDiagnosisTitle.
  ///
  /// In zh, this message translates to:
  /// **'学习诊断'**
  String get mockSupportDiagnosisTitle;

  /// No description provided for @mockSupportDiagnosisWeakness.
  ///
  /// In zh, this message translates to:
  /// **'薄弱点'**
  String get mockSupportDiagnosisWeakness;

  /// No description provided for @mockSupportEditNotes.
  ///
  /// In zh, this message translates to:
  /// **'编辑与笔记'**
  String get mockSupportEditNotes;

  /// No description provided for @mockSupportExamAnswerCard.
  ///
  /// In zh, this message translates to:
  /// **'答题卡'**
  String get mockSupportExamAnswerCard;

  /// No description provided for @mockSupportExamAnswered.
  ///
  /// In zh, this message translates to:
  /// **'已答'**
  String get mockSupportExamAnswered;

  /// No description provided for @mockSupportExamAnsweredCount.
  ///
  /// In zh, this message translates to:
  /// **'已答 {answered} / {total}'**
  String mockSupportExamAnsweredCount(int answered, int total);

  /// No description provided for @mockSupportExamBackToPreparation.
  ///
  /// In zh, this message translates to:
  /// **'试卷准备'**
  String get mockSupportExamBackToPreparation;

  /// No description provided for @mockSupportExamConfirmSubmit.
  ///
  /// In zh, this message translates to:
  /// **'确认交卷'**
  String get mockSupportExamConfirmSubmit;

  /// No description provided for @mockSupportExamContinueAnswering.
  ///
  /// In zh, this message translates to:
  /// **'继续作答'**
  String get mockSupportExamContinueAnswering;

  /// No description provided for @mockSupportExamDemoScoringHint.
  ///
  /// In zh, this message translates to:
  /// **'查看评分与解释。'**
  String get mockSupportExamDemoScoringHint;

  /// No description provided for @mockSupportExamDuration.
  ///
  /// In zh, this message translates to:
  /// **'考试时长 60 分钟'**
  String get mockSupportExamDuration;

  /// No description provided for @mockSupportExamInProgressSummary.
  ///
  /// In zh, this message translates to:
  /// **'整卷作答 · 60 分钟'**
  String get mockSupportExamInProgressSummary;

  /// No description provided for @mockSupportExamLanguageKnowledge.
  ///
  /// In zh, this message translates to:
  /// **'语言知识'**
  String get mockSupportExamLanguageKnowledge;

  /// No description provided for @mockSupportExamLeave.
  ///
  /// In zh, this message translates to:
  /// **'暂时离开'**
  String get mockSupportExamLeave;

  /// No description provided for @mockSupportExamLeaveBody.
  ///
  /// In zh, this message translates to:
  /// **'离开前会保存当前答案和标记，稍后可继续作答。'**
  String get mockSupportExamLeaveBody;

  /// No description provided for @mockSupportExamLeaveTitle.
  ///
  /// In zh, this message translates to:
  /// **'暂时离开考试？'**
  String get mockSupportExamLeaveTitle;

  /// No description provided for @mockSupportExamListening.
  ///
  /// In zh, this message translates to:
  /// **'听力'**
  String get mockSupportExamListening;

  /// No description provided for @mockSupportExamMarkQuestion.
  ///
  /// In zh, this message translates to:
  /// **'标记题目'**
  String get mockSupportExamMarkQuestion;

  /// No description provided for @mockSupportExamMarkForLater.
  ///
  /// In zh, this message translates to:
  /// **'标记稍后检查'**
  String get mockSupportExamMarkForLater;

  /// No description provided for @mockSupportExamMarked.
  ///
  /// In zh, this message translates to:
  /// **'已标记'**
  String get mockSupportExamMarked;

  /// No description provided for @mockSupportExamMobileTitle.
  ///
  /// In zh, this message translates to:
  /// **'模拟考试'**
  String get mockSupportExamMobileTitle;

  /// No description provided for @mockSupportExamNextQuestion.
  ///
  /// In zh, this message translates to:
  /// **'下一题'**
  String get mockSupportExamNextQuestion;

  /// No description provided for @mockSupportExamOptionCalm.
  ///
  /// In zh, this message translates to:
  /// **'平静温和'**
  String get mockSupportExamOptionCalm;

  /// No description provided for @mockSupportExamOptionComplex.
  ///
  /// In zh, this message translates to:
  /// **'十分复杂'**
  String get mockSupportExamOptionComplex;

  /// No description provided for @mockSupportExamOptionForgotPromise.
  ///
  /// In zh, this message translates to:
  /// **'忘记了约定'**
  String get mockSupportExamOptionForgotPromise;

  /// No description provided for @mockSupportExamOptionHeardBroadcast.
  ///
  /// In zh, this message translates to:
  /// **'听到了广播'**
  String get mockSupportExamOptionHeardBroadcast;

  /// No description provided for @mockSupportExamOptionLibraryEntrance.
  ///
  /// In zh, this message translates to:
  /// **'图书馆门口'**
  String get mockSupportExamOptionLibraryEntrance;

  /// No description provided for @mockSupportExamOptionMetTeacher.
  ///
  /// In zh, this message translates to:
  /// **'遇见了老师'**
  String get mockSupportExamOptionMetTeacher;

  /// No description provided for @mockSupportExamOptionParkEntrance.
  ///
  /// In zh, this message translates to:
  /// **'公园入口'**
  String get mockSupportExamOptionParkEntrance;

  /// No description provided for @mockSupportExamOptionRapid.
  ///
  /// In zh, this message translates to:
  /// **'迅速猛烈'**
  String get mockSupportExamOptionRapid;

  /// No description provided for @mockSupportExamOptionRememberedFriend.
  ///
  /// In zh, this message translates to:
  /// **'想起了旧友'**
  String get mockSupportExamOptionRememberedFriend;

  /// No description provided for @mockSupportExamOptionSchoolHall.
  ///
  /// In zh, this message translates to:
  /// **'学校大厅'**
  String get mockSupportExamOptionSchoolHall;

  /// No description provided for @mockSupportExamOptionStationSouthExit.
  ///
  /// In zh, this message translates to:
  /// **'车站南口'**
  String get mockSupportExamOptionStationSouthExit;

  /// No description provided for @mockSupportExamOptionSurprising.
  ///
  /// In zh, this message translates to:
  /// **'令人惊讶'**
  String get mockSupportExamOptionSurprising;

  /// No description provided for @mockSupportExamPaperTitle.
  ///
  /// In zh, this message translates to:
  /// **'N2 模拟试卷'**
  String get mockSupportExamPaperTitle;

  /// No description provided for @mockSupportExamPreviousQuestion.
  ///
  /// In zh, this message translates to:
  /// **'上一题'**
  String get mockSupportExamPreviousQuestion;

  /// No description provided for @mockSupportExamQuestionNumber.
  ///
  /// In zh, this message translates to:
  /// **'第 {number} 题'**
  String mockSupportExamQuestionNumber(int number);

  /// No description provided for @mockSupportExamQuestionListening.
  ///
  /// In zh, this message translates to:
  /// **'听力题组 1：两人最后决定在哪里见面？'**
  String get mockSupportExamQuestionListening;

  /// No description provided for @mockSupportExamQuestionMeaning.
  ///
  /// In zh, this message translates to:
  /// **'「穏やか」に最接近的意思是？'**
  String get mockSupportExamQuestionMeaning;

  /// No description provided for @mockSupportExamQuestionReading.
  ///
  /// In zh, this message translates to:
  /// **'文中主人公为什么停下脚步？'**
  String get mockSupportExamQuestionReading;

  /// No description provided for @mockSupportExamResultTitle.
  ///
  /// In zh, this message translates to:
  /// **'考试结果'**
  String get mockSupportExamResultTitle;

  /// No description provided for @mockSupportExamReading.
  ///
  /// In zh, this message translates to:
  /// **'阅读理解'**
  String get mockSupportExamReading;

  /// No description provided for @mockSupportExamSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get mockSupportExamSave;

  /// No description provided for @mockSupportExamSaveAndLeave.
  ///
  /// In zh, this message translates to:
  /// **'保存并离开'**
  String get mockSupportExamSaveAndLeave;

  /// No description provided for @mockSupportExamSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get mockSupportExamSaved;

  /// No description provided for @mockSupportExamSaveDraft.
  ///
  /// In zh, this message translates to:
  /// **'保存草稿'**
  String get mockSupportExamSaveDraft;

  /// No description provided for @mockSupportExamSessionTitle.
  ///
  /// In zh, this message translates to:
  /// **'整卷作答'**
  String get mockSupportExamSessionTitle;

  /// No description provided for @mockSupportExamSubmit.
  ///
  /// In zh, this message translates to:
  /// **'交卷'**
  String get mockSupportExamSubmit;

  /// No description provided for @mockSupportExamSubmitAnsweredBody.
  ///
  /// In zh, this message translates to:
  /// **'已答 {answered} / {total}。交卷后答案锁定，再查看复盘。'**
  String mockSupportExamSubmitAnsweredBody(int answered, int total);

  /// No description provided for @mockSupportExamSubmitConfirmBody.
  ///
  /// In zh, this message translates to:
  /// **'交卷后答卷锁定，才可查看参考答案与复盘。'**
  String get mockSupportExamSubmitConfirmBody;

  /// No description provided for @mockSupportExamSubmitConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认交卷？'**
  String get mockSupportExamSubmitConfirmTitle;

  /// No description provided for @mockSupportExamSubmittedReview.
  ///
  /// In zh, this message translates to:
  /// **'已交卷 · 成绩复盘'**
  String get mockSupportExamSubmittedReview;

  /// No description provided for @mockSupportExamUnanswered.
  ///
  /// In zh, this message translates to:
  /// **'未答'**
  String get mockSupportExamUnanswered;

  /// No description provided for @mockSupportExamUnmarkQuestion.
  ///
  /// In zh, this message translates to:
  /// **'取消标记'**
  String get mockSupportExamUnmarkQuestion;

  /// No description provided for @mockSupportExamUnsaved.
  ///
  /// In zh, this message translates to:
  /// **'尚未保存'**
  String get mockSupportExamUnsaved;

  /// No description provided for @mockSupportExerciseAllowRepeatedSource.
  ///
  /// In zh, this message translates to:
  /// **'候选不足时允许同一来源多题'**
  String get mockSupportExerciseAllowRepeatedSource;

  /// No description provided for @mockSupportExerciseAllOwnWords.
  ///
  /// In zh, this message translates to:
  /// **'全部本人单词'**
  String get mockSupportExerciseAllOwnWords;

  /// No description provided for @mockSupportExerciseBackToEdit.
  ///
  /// In zh, this message translates to:
  /// **'修改来源'**
  String get mockSupportExerciseBackToEdit;

  /// No description provided for @mockSupportExerciseBuilderChooseContent.
  ///
  /// In zh, this message translates to:
  /// **'想练习哪些内容？'**
  String get mockSupportExerciseBuilderChooseContent;

  /// No description provided for @mockSupportExerciseBuilderConfirmSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置与确认'**
  String get mockSupportExerciseBuilderConfirmSettings;

  /// No description provided for @mockSupportExerciseBuilderEnglish.
  ///
  /// In zh, this message translates to:
  /// **'英语'**
  String get mockSupportExerciseBuilderEnglish;

  /// No description provided for @mockSupportExerciseBuilderHeadline.
  ///
  /// In zh, this message translates to:
  /// **'生成 AI 习题'**
  String get mockSupportExerciseBuilderHeadline;

  /// No description provided for @mockSupportExerciseBuilderJapanese.
  ///
  /// In zh, this message translates to:
  /// **'日语'**
  String get mockSupportExerciseBuilderJapanese;

  /// No description provided for @mockSupportExerciseBuilderReviewHint.
  ///
  /// In zh, this message translates to:
  /// **'请确认来源和题目设置；条件变化需重新预览。'**
  String get mockSupportExerciseBuilderReviewHint;

  /// No description provided for @mockSupportExerciseBuilderStudyLanguage.
  ///
  /// In zh, this message translates to:
  /// **'学习语言'**
  String get mockSupportExerciseBuilderStudyLanguage;

  /// No description provided for @mockSupportExerciseBuilderTitle.
  ///
  /// In zh, this message translates to:
  /// **'生成习题'**
  String get mockSupportExerciseBuilderTitle;

  /// No description provided for @mockSupportExerciseCandidateCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 项内容'**
  String mockSupportExerciseCandidateCount(int count);

  /// No description provided for @mockSupportExerciseCandidateShortage.
  ///
  /// In zh, this message translates to:
  /// **'当前 {available} 项来源少于计划的 {count} 题。可减少题量，或允许同一来源出多题。'**
  String mockSupportExerciseCandidateShortage(int available, int count);

  /// No description provided for @mockSupportExerciseChooseCollections.
  ///
  /// In zh, this message translates to:
  /// **'选择收藏条目'**
  String get mockSupportExerciseChooseCollections;

  /// No description provided for @mockSupportExerciseChooseDiagnosis.
  ///
  /// In zh, this message translates to:
  /// **'选择诊断薄弱点'**
  String get mockSupportExerciseChooseDiagnosis;

  /// No description provided for @mockSupportExerciseChooseMistakeRange.
  ///
  /// In zh, this message translates to:
  /// **'选择错题范围'**
  String get mockSupportExerciseChooseMistakeRange;

  /// No description provided for @mockSupportExerciseChooseNotebook.
  ///
  /// In zh, this message translates to:
  /// **'选择单词本'**
  String get mockSupportExerciseChooseNotebook;

  /// No description provided for @mockSupportExerciseConfirmGeneration.
  ///
  /// In zh, this message translates to:
  /// **'确认生成习题'**
  String get mockSupportExerciseConfirmGeneration;

  /// No description provided for @mockSupportExerciseCountFive.
  ///
  /// In zh, this message translates to:
  /// **'5 题'**
  String get mockSupportExerciseCountFive;

  /// No description provided for @mockSupportExerciseCountOne.
  ///
  /// In zh, this message translates to:
  /// **'1 题'**
  String get mockSupportExerciseCountOne;

  /// No description provided for @mockSupportExerciseCountTen.
  ///
  /// In zh, this message translates to:
  /// **'10 题'**
  String get mockSupportExerciseCountTen;

  /// No description provided for @mockSupportExerciseGenerationAcceptedToast.
  ///
  /// In zh, this message translates to:
  /// **'习题生成已受理'**
  String get mockSupportExerciseGenerationAcceptedToast;

  /// No description provided for @mockSupportExerciseNextToSettings.
  ///
  /// In zh, this message translates to:
  /// **'下一步 · 设置与确认'**
  String get mockSupportExerciseNextToSettings;

  /// No description provided for @mockSupportExerciseNoCandidates.
  ///
  /// In zh, this message translates to:
  /// **'当前范围没有可用内容。'**
  String get mockSupportExerciseNoCandidates;

  /// No description provided for @mockSupportExerciseNeedConcreteSource.
  ///
  /// In zh, this message translates to:
  /// **'请先选定具体来源。'**
  String get mockSupportExerciseNeedConcreteSource;

  /// No description provided for @mockSupportExerciseNeedQuestionType.
  ///
  /// In zh, this message translates to:
  /// **'至少选择一种题型。'**
  String get mockSupportExerciseNeedQuestionType;

  /// No description provided for @mockSupportExercisePreviewSummary.
  ///
  /// In zh, this message translates to:
  /// **'{language} · {types} · {count} 题'**
  String mockSupportExercisePreviewSummary(String language, String types, int count);

  /// No description provided for @mockSupportExercisePreviewTitle.
  ///
  /// In zh, this message translates to:
  /// **'出题范围'**
  String get mockSupportExercisePreviewTitle;

  /// No description provided for @mockSupportExerciseQuestionCount.
  ///
  /// In zh, this message translates to:
  /// **'题量'**
  String get mockSupportExerciseQuestionCount;

  /// No description provided for @mockSupportExerciseQuestionType.
  ///
  /// In zh, this message translates to:
  /// **'题型'**
  String get mockSupportExerciseQuestionType;

  /// No description provided for @mockSupportExerciseSettingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'题目设置'**
  String get mockSupportExerciseSettingsTitle;

  /// No description provided for @mockSupportExerciseCurrentMistakes.
  ///
  /// In zh, this message translates to:
  /// **'当前待纠正'**
  String get mockSupportExerciseCurrentMistakes;

  /// No description provided for @mockSupportExerciseBookmarkedMistakes.
  ///
  /// In zh, this message translates to:
  /// **'已收藏的当前错题'**
  String get mockSupportExerciseBookmarkedMistakes;

  /// No description provided for @mockSupportExerciseUnitLabel.
  ///
  /// In zh, this message translates to:
  /// **'Unit {number} · {title}'**
  String mockSupportExerciseUnitLabel(String number, String title);

  /// No description provided for @mockSupportExerciseSourceCollection.
  ///
  /// In zh, this message translates to:
  /// **'手选收藏'**
  String get mockSupportExerciseSourceCollection;

  /// No description provided for @mockSupportExerciseSourceCollectionDescription.
  ///
  /// In zh, this message translates to:
  /// **'逐条选择词句或卡片'**
  String get mockSupportExerciseSourceCollectionDescription;

  /// No description provided for @mockSupportExerciseSourceDiagnosis.
  ///
  /// In zh, this message translates to:
  /// **'诊断薄弱点'**
  String get mockSupportExerciseSourceDiagnosis;

  /// No description provided for @mockSupportExerciseSourceDiagnosisDescription.
  ///
  /// In zh, this message translates to:
  /// **'围绕已有诊断练习'**
  String get mockSupportExerciseSourceDiagnosisDescription;

  /// No description provided for @mockSupportExerciseSourceMistakes.
  ///
  /// In zh, this message translates to:
  /// **'错题'**
  String get mockSupportExerciseSourceMistakes;

  /// No description provided for @mockSupportExerciseSourceMistakesDescription.
  ///
  /// In zh, this message translates to:
  /// **'按当前状态或收藏选题'**
  String get mockSupportExerciseSourceMistakesDescription;

  /// No description provided for @mockSupportExerciseSourceNotebook.
  ///
  /// In zh, this message translates to:
  /// **'单词本'**
  String get mockSupportExerciseSourceNotebook;

  /// No description provided for @mockSupportExerciseSourceNotebookDescription.
  ///
  /// In zh, this message translates to:
  /// **'按词本选择单词'**
  String get mockSupportExerciseSourceNotebookDescription;

  /// No description provided for @mockSupportExerciseSourceTextbook.
  ///
  /// In zh, this message translates to:
  /// **'教材'**
  String get mockSupportExerciseSourceTextbook;

  /// No description provided for @mockSupportExerciseSourceTextbookDescription.
  ///
  /// In zh, this message translates to:
  /// **'选择一个学习单元'**
  String get mockSupportExerciseSourceTextbookDescription;

  /// No description provided for @mockSupportExerciseTypeContextFill.
  ///
  /// In zh, this message translates to:
  /// **'语境填空'**
  String get mockSupportExerciseTypeContextFill;

  /// No description provided for @mockSupportExerciseTypeMeaningChoice.
  ///
  /// In zh, this message translates to:
  /// **'词义选择'**
  String get mockSupportExerciseTypeMeaningChoice;

  /// No description provided for @mockSupportExerciseTypeTranslationJudgement.
  ///
  /// In zh, this message translates to:
  /// **'翻译判断'**
  String get mockSupportExerciseTypeTranslationJudgement;

  /// No description provided for @mockSupportJobsConnected.
  ///
  /// In zh, this message translates to:
  /// **'进度已连接'**
  String get mockSupportJobsConnected;

  /// No description provided for @mockSupportJobsNovelDemo.
  ///
  /// In zh, this message translates to:
  /// **'小说 · 解析任务'**
  String get mockSupportJobsNovelDemo;

  /// No description provided for @mockSupportJobsNovelTitle.
  ///
  /// In zh, this message translates to:
  /// **'雨上がり'**
  String get mockSupportJobsNovelTitle;

  /// No description provided for @mockSupportJobsOpenMaterial.
  ///
  /// In zh, this message translates to:
  /// **'打开材料 →'**
  String get mockSupportJobsOpenMaterial;

  /// No description provided for @mockSupportJobsTitle.
  ///
  /// In zh, this message translates to:
  /// **'任务进度'**
  String get mockSupportJobsTitle;

  /// No description provided for @mockSupportMistakeAiExerciseSource.
  ///
  /// In zh, this message translates to:
  /// **'AI 习题 · 日常的细节'**
  String get mockSupportMistakeAiExerciseSource;

  /// No description provided for @mockSupportMistakeBookmarkAction.
  ///
  /// In zh, this message translates to:
  /// **'收藏错题'**
  String get mockSupportMistakeBookmarkAction;

  /// No description provided for @mockSupportMistakeBookmarked.
  ///
  /// In zh, this message translates to:
  /// **'已收藏'**
  String get mockSupportMistakeBookmarked;

  /// No description provided for @mockSupportMistakeBookmarkedStatus.
  ///
  /// In zh, this message translates to:
  /// **'已收藏错题'**
  String get mockSupportMistakeBookmarkedStatus;

  /// No description provided for @mockSupportMistakeChooseAsSource.
  ///
  /// In zh, this message translates to:
  /// **'从错题选择习题来源'**
  String get mockSupportMistakeChooseAsSource;

  /// No description provided for @mockSupportMistakeDetailTitle.
  ///
  /// In zh, this message translates to:
  /// **'错题详情'**
  String get mockSupportMistakeDetailTitle;

  /// No description provided for @mockSupportMistakeDirectionError.
  ///
  /// In zh, this message translates to:
  /// **'把「へ」解释为动作对象'**
  String get mockSupportMistakeDirectionError;

  /// No description provided for @mockSupportMistakeDirectionTopic.
  ///
  /// In zh, this message translates to:
  /// **'移动方向与目的地'**
  String get mockSupportMistakeDirectionTopic;

  /// No description provided for @mockSupportMistakeExamSource.
  ///
  /// In zh, this message translates to:
  /// **'N2 模拟试卷 · 阅读'**
  String get mockSupportMistakeExamSource;

  /// No description provided for @mockSupportMistakeGenerateTargeted.
  ///
  /// In zh, this message translates to:
  /// **'针对它出题'**
  String get mockSupportMistakeGenerateTargeted;

  /// No description provided for @mockSupportMistakeHistoricalExamples.
  ///
  /// In zh, this message translates to:
  /// **'历史记录'**
  String get mockSupportMistakeHistoricalExamples;

  /// No description provided for @mockSupportMistakeImproved.
  ///
  /// In zh, this message translates to:
  /// **'已经改进'**
  String get mockSupportMistakeImproved;

  /// No description provided for @mockSupportMistakeLibraryTitle.
  ///
  /// In zh, this message translates to:
  /// **'错题库'**
  String get mockSupportMistakeLibraryTitle;

  /// No description provided for @mockSupportMistakeListTitle.
  ///
  /// In zh, this message translates to:
  /// **'错题列表'**
  String get mockSupportMistakeListTitle;

  /// No description provided for @mockSupportMistakeMeaningError.
  ///
  /// In zh, this message translates to:
  /// **'误选了「迅速猛烈」'**
  String get mockSupportMistakeMeaningError;

  /// No description provided for @mockSupportMistakeMeaningTopic.
  ///
  /// In zh, this message translates to:
  /// **'语境词义：穏やか'**
  String get mockSupportMistakeMeaningTopic;

  /// No description provided for @mockSupportMistakeNeedsCorrection.
  ///
  /// In zh, this message translates to:
  /// **'当前待纠正'**
  String get mockSupportMistakeNeedsCorrection;

  /// No description provided for @mockSupportMistakePreviousAnswer.
  ///
  /// In zh, this message translates to:
  /// **'当时的作答'**
  String get mockSupportMistakePreviousAnswer;

  /// No description provided for @mockSupportMistakeReferenceError.
  ///
  /// In zh, this message translates to:
  /// **'遗漏上一段的指代'**
  String get mockSupportMistakeReferenceError;

  /// No description provided for @mockSupportMistakeReferenceTopic.
  ///
  /// In zh, this message translates to:
  /// **'阅读中的指代关系'**
  String get mockSupportMistakeReferenceTopic;

  /// No description provided for @mockSupportMistakeRemoveBookmark.
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get mockSupportMistakeRemoveBookmark;

  /// No description provided for @mockSupportMistakeTextbookSource.
  ///
  /// In zh, this message translates to:
  /// **'日语的日常表达 · Unit 02'**
  String get mockSupportMistakeTextbookSource;

  /// No description provided for @mockSupportMistakeTopicColumn.
  ///
  /// In zh, this message translates to:
  /// **'考察点'**
  String get mockSupportMistakeTopicColumn;

  /// No description provided for @mockSupportMistakeSourceColumn.
  ///
  /// In zh, this message translates to:
  /// **'来源'**
  String get mockSupportMistakeSourceColumn;

  /// No description provided for @mockSupportMistakeStatusColumn.
  ///
  /// In zh, this message translates to:
  /// **'当前状态'**
  String get mockSupportMistakeStatusColumn;

  /// No description provided for @mockSupportMistakeBookmarkColumn.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get mockSupportMistakeBookmarkColumn;

  /// No description provided for @mockSupportMistakeViewColumn.
  ///
  /// In zh, this message translates to:
  /// **'查看'**
  String get mockSupportMistakeViewColumn;

  /// No description provided for @mockSupportNotificationsHeading.
  ///
  /// In zh, this message translates to:
  /// **'消息'**
  String get mockSupportNotificationsHeading;

  /// No description provided for @mockSupportNotificationsMarkAllRead.
  ///
  /// In zh, this message translates to:
  /// **'全部标为已读'**
  String get mockSupportNotificationsMarkAllRead;

  /// No description provided for @mockSupportNotificationsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无消息'**
  String get mockSupportNotificationsEmpty;

  /// No description provided for @mockSupportNotificationsReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'标记已读失败，请重试'**
  String get mockSupportNotificationsReadFailed;

  /// No description provided for @mockSupportNotificationsTitle.
  ///
  /// In zh, this message translates to:
  /// **'站内消息'**
  String get mockSupportNotificationsTitle;

  /// No description provided for @mockSupportNotificationsUnreadCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条未读'**
  String mockSupportNotificationsUnreadCount(int count);

  /// No description provided for @mockSupportNotificationTodayTime.
  ///
  /// In zh, this message translates to:
  /// **'今天 {time}'**
  String mockSupportNotificationTodayTime(String time);

  /// No description provided for @mockSupportNotificationYesterdayTime.
  ///
  /// In zh, this message translates to:
  /// **'昨天 {time}'**
  String mockSupportNotificationYesterdayTime(String time);

  /// No description provided for @mockSupportNotificationMonthDay.
  ///
  /// In zh, this message translates to:
  /// **'{month} 月 {day} 日'**
  String mockSupportNotificationMonthDay(int month, int day);

  /// No description provided for @mockSupportPersonalNotes.
  ///
  /// In zh, this message translates to:
  /// **'个人笔记'**
  String get mockSupportPersonalNotes;

  /// No description provided for @mockSupportReturnToSource.
  ///
  /// In zh, this message translates to:
  /// **'回到原文 →'**
  String get mockSupportReturnToSource;

  /// No description provided for @mockSupportSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get mockSupportSave;

  /// No description provided for @mockSettingAccountUpdatesGroup.
  ///
  /// In zh, this message translates to:
  /// **'账号与动态'**
  String get mockSettingAccountUpdatesGroup;

  /// No description provided for @mockSettingAvatarGlyph.
  ///
  /// In zh, this message translates to:
  /// **'遥'**
  String get mockSettingAvatarGlyph;

  /// No description provided for @mockSettingBirthYearOptional.
  ///
  /// In zh, this message translates to:
  /// **'出生年份（可选）'**
  String get mockSettingBirthYearOptional;

  /// No description provided for @mockSettingClearAccountLocalCache.
  ///
  /// In zh, this message translates to:
  /// **'清除此账号本机缓存'**
  String get mockSettingClearAccountLocalCache;

  /// No description provided for @mockSettingCurrentLearningLanguage.
  ///
  /// In zh, this message translates to:
  /// **'当前学习语言'**
  String get mockSettingCurrentLearningLanguage;

  /// No description provided for @mockSettingDisplayName.
  ///
  /// In zh, this message translates to:
  /// **'显示名'**
  String get mockSettingDisplayName;

  /// No description provided for @mockSettingExplanationLanguage.
  ///
  /// In zh, this message translates to:
  /// **'解释语言'**
  String get mockSettingExplanationLanguage;

  /// No description provided for @mockSettingJobs.
  ///
  /// In zh, this message translates to:
  /// **'任务进度'**
  String get mockSettingJobs;

  /// No description provided for @mockSettingJobsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'导入与生成结果'**
  String get mockSettingJobsSubtitle;

  /// No description provided for @mockSettingLearningLevelSample.
  ///
  /// In zh, this message translates to:
  /// **'日语 · 中级'**
  String get mockSettingLearningLevelSample;

  /// No description provided for @mockSettingLearningPreferencesGroup.
  ///
  /// In zh, this message translates to:
  /// **'学习偏好'**
  String get mockSettingLearningPreferencesGroup;

  /// No description provided for @mockSettingLocalAvailable.
  ///
  /// In zh, this message translates to:
  /// **'本机可用'**
  String get mockSettingLocalAvailable;

  /// No description provided for @mockSettingModelDataGroup.
  ///
  /// In zh, this message translates to:
  /// **'模型与数据'**
  String get mockSettingModelDataGroup;

  /// No description provided for @mockSettingMyTitle.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get mockSettingMyTitle;

  /// No description provided for @mockSettingNotifications.
  ///
  /// In zh, this message translates to:
  /// **'站内消息'**
  String get mockSettingNotifications;

  /// No description provided for @mockSettingNotificationsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'任务和结果提醒'**
  String get mockSettingNotificationsSubtitle;

  /// No description provided for @mockSettingReduceMotion.
  ///
  /// In zh, this message translates to:
  /// **'减少动态'**
  String get mockSettingReduceMotion;

  /// No description provided for @mockSettingSaveAppearance.
  ///
  /// In zh, this message translates to:
  /// **'保存外观'**
  String get mockSettingSaveAppearance;

  /// No description provided for @mockSettingSaveLanguageOptions.
  ///
  /// In zh, this message translates to:
  /// **'保存语言选项'**
  String get mockSettingSaveLanguageOptions;

  /// No description provided for @mockSettingSaveProfile.
  ///
  /// In zh, this message translates to:
  /// **'保存资料'**
  String get mockSettingSaveProfile;

  /// No description provided for @profileGuideTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认学习资料'**
  String get profileGuideTitle;

  /// No description provided for @profileGuideBody.
  ///
  /// In zh, this message translates to:
  /// **'显示名、解释语言、学习语言和时区都可以稍后填写。跳过不会保存，也不会记成已完成。'**
  String get profileGuideBody;

  /// No description provided for @profileGuideSkip.
  ///
  /// In zh, this message translates to:
  /// **'跳过'**
  String get profileGuideSkip;

  /// No description provided for @serviceSwitchWebFixed.
  ///
  /// In zh, this message translates to:
  /// **'Web 使用当前部署，不能在应用内更换服务地址。'**
  String get serviceSwitchWebFixed;

  /// No description provided for @serviceSwitchConfirm.
  ///
  /// In zh, this message translates to:
  /// **'退出并使用此服务'**
  String get serviceSwitchConfirm;

  /// No description provided for @serviceSwitchWarning.
  ///
  /// In zh, this message translates to:
  /// **'将退出当前服务并清理本机缓存。'**
  String get serviceSwitchWarning;

  /// No description provided for @serviceSwitchFailed.
  ///
  /// In zh, this message translates to:
  /// **'未能连接新服务，当前已退出。'**
  String get serviceSwitchFailed;

  /// No description provided for @serviceSwitchProbeFailed.
  ///
  /// In zh, this message translates to:
  /// **'未能连接该服务。'**
  String get serviceSwitchProbeFailed;

  /// No description provided for @serviceSwitchRevokeFailed.
  ///
  /// In zh, this message translates to:
  /// **'本机已退出。原服务上的会话可能尚未撤销。'**
  String get serviceSwitchRevokeFailed;

  /// No description provided for @serviceSwitchIdentity.
  ///
  /// In zh, this message translates to:
  /// **'实例 {instance}，接口 {version}'**
  String serviceSwitchIdentity(String instance, String version);

  /// No description provided for @mockSettingSavedResults.
  ///
  /// In zh, this message translates to:
  /// **'已保存成果'**
  String get mockSettingSavedResults;

  /// No description provided for @mockSettingTheme.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get mockSettingTheme;

  /// No description provided for @mockProfileAiConsent.
  ///
  /// In zh, this message translates to:
  /// **'允许 AI 使用可选个人资料'**
  String get mockProfileAiConsent;

  /// No description provided for @mockProfileChangeAvatar.
  ///
  /// In zh, this message translates to:
  /// **'更换头像'**
  String get mockProfileChangeAvatar;

  /// No description provided for @mockProfileFallbackName.
  ///
  /// In zh, this message translates to:
  /// **'学习者'**
  String get mockProfileFallbackName;

  /// No description provided for @mockProfileGenderFemale.
  ///
  /// In zh, this message translates to:
  /// **'女'**
  String get mockProfileGenderFemale;

  /// No description provided for @mockProfileGenderMale.
  ///
  /// In zh, this message translates to:
  /// **'男'**
  String get mockProfileGenderMale;

  /// No description provided for @mockProfileGenderNonBinary.
  ///
  /// In zh, this message translates to:
  /// **'非二元'**
  String get mockProfileGenderNonBinary;

  /// No description provided for @mockProfileGenderOptional.
  ///
  /// In zh, this message translates to:
  /// **'性别（可选）'**
  String get mockProfileGenderOptional;

  /// No description provided for @mockProfileGenderPreferNot.
  ///
  /// In zh, this message translates to:
  /// **'不愿说明'**
  String get mockProfileGenderPreferNot;

  /// No description provided for @mockProfileGenderSelfDescribe.
  ///
  /// In zh, this message translates to:
  /// **'自我描述'**
  String get mockProfileGenderSelfDescribe;

  /// No description provided for @mockProfileGenderUnset.
  ///
  /// In zh, this message translates to:
  /// **'未填写'**
  String get mockProfileGenderUnset;

  /// No description provided for @mockProfileGreeting.
  ///
  /// In zh, this message translates to:
  /// **'你好，{name}。'**
  String mockProfileGreeting(String name);

  /// No description provided for @mockProfileTimezone.
  ///
  /// In zh, this message translates to:
  /// **'时区'**
  String get mockProfileTimezone;

  /// No description provided for @mockProfileTimezoneShanghai.
  ///
  /// In zh, this message translates to:
  /// **'上海 / Asia/Shanghai'**
  String get mockProfileTimezoneShanghai;

  /// No description provided for @mockProfileTimezoneTokyo.
  ///
  /// In zh, this message translates to:
  /// **'东京 / Asia/Tokyo'**
  String get mockProfileTimezoneTokyo;

  /// No description provided for @mockProfileTimezoneUtc.
  ///
  /// In zh, this message translates to:
  /// **'UTC'**
  String get mockProfileTimezoneUtc;

  /// No description provided for @mockSettingLanguageOptionsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'学习：{learning} · 解释：{explanation}'**
  String mockSettingLanguageOptionsSubtitle(String learning, String explanation);

  /// No description provided for @mockSettingLanguageOptions.
  ///
  /// In zh, this message translates to:
  /// **'语言选项'**
  String get mockSettingLanguageOptions;

  /// No description provided for @mockSettingMoreGroup.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get mockSettingMoreGroup;

  /// No description provided for @mockSettingSecurityAccount.
  ///
  /// In zh, this message translates to:
  /// **'安全与账号'**
  String get mockSettingSecurityAccount;

  /// No description provided for @mockProfileAvatarTitle.
  ///
  /// In zh, this message translates to:
  /// **'头像'**
  String get mockProfileAvatarTitle;

  /// No description provided for @mockProfileAvatarUpdated.
  ///
  /// In zh, this message translates to:
  /// **'头像已更新'**
  String get mockProfileAvatarUpdated;

  /// No description provided for @mockProfileCurrentAvatar.
  ///
  /// In zh, this message translates to:
  /// **'当前头像'**
  String get mockProfileCurrentAvatar;

  /// No description provided for @mockSettingProfile.
  ///
  /// In zh, this message translates to:
  /// **'个人资料'**
  String get mockSettingProfile;

  /// No description provided for @mockSettingProfileSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'显示名与头像'**
  String get mockSettingProfileSubtitle;

  /// No description provided for @mockAdminAccountCount.
  ///
  /// In zh, this message translates to:
  /// **'账号数'**
  String get mockAdminAccountCount;

  /// No description provided for @mockAdminAccountLabel.
  ///
  /// In zh, this message translates to:
  /// **'管理账号'**
  String get mockAdminAccountLabel;

  /// No description provided for @mockAdminAccountName.
  ///
  /// In zh, this message translates to:
  /// **'小遥'**
  String get mockAdminAccountName;

  /// No description provided for @mockAdminAccountRecovery.
  ///
  /// In zh, this message translates to:
  /// **'账号恢复'**
  String get mockAdminAccountRecovery;

  /// No description provided for @mockAdminActionColumn.
  ///
  /// In zh, this message translates to:
  /// **'操作'**
  String get mockAdminActionColumn;

  /// No description provided for @mockAdminActionKindColumn.
  ///
  /// In zh, this message translates to:
  /// **'操作类别'**
  String get mockAdminActionKindColumn;

  /// No description provided for @mockAdminActualCallsColumn.
  ///
  /// In zh, this message translates to:
  /// **'调用次数'**
  String get mockAdminActualCallsColumn;

  /// No description provided for @mockAdminAdminNavigation.
  ///
  /// In zh, this message translates to:
  /// **'管理端导航'**
  String get mockAdminAdminNavigation;

  /// No description provided for @mockAdminApprovalExample.
  ///
  /// In zh, this message translates to:
  /// **'需审批'**
  String get mockAdminApprovalExample;

  /// No description provided for @mockAdminApplyPolicy.
  ///
  /// In zh, this message translates to:
  /// **'应用策略'**
  String get mockAdminApplyPolicy;

  /// No description provided for @mockAdminAttempt.
  ///
  /// In zh, this message translates to:
  /// **'{count} 次'**
  String mockAdminAttempt(int count);

  /// No description provided for @mockAdminAttempts.
  ///
  /// In zh, this message translates to:
  /// **'{count} 次'**
  String mockAdminAttempts(int count);

  /// No description provided for @mockAdminAudience.
  ///
  /// In zh, this message translates to:
  /// **'管理端'**
  String get mockAdminAudience;

  /// No description provided for @mockAdminAudienceColumn.
  ///
  /// In zh, this message translates to:
  /// **'受众'**
  String get mockAdminAudienceColumn;

  /// No description provided for @mockAdminAudioGeneration.
  ///
  /// In zh, this message translates to:
  /// **'音频生成'**
  String get mockAdminAudioGeneration;

  /// No description provided for @mockAdminAudit.
  ///
  /// In zh, this message translates to:
  /// **'审计诊断'**
  String get mockAdminAudit;

  /// No description provided for @mockAdminAvatar.
  ///
  /// In zh, this message translates to:
  /// **'遥'**
  String get mockAdminAvatar;

  /// No description provided for @mockAdminAwaitingSubmission.
  ///
  /// In zh, this message translates to:
  /// **'待提交'**
  String get mockAdminAwaitingSubmission;

  /// No description provided for @mockAdminBackToClient.
  ///
  /// In zh, this message translates to:
  /// **'返回用户端登录'**
  String get mockAdminBackToClient;

  /// No description provided for @mockAdminCapabilityColumn.
  ///
  /// In zh, this message translates to:
  /// **'能力'**
  String get mockAdminCapabilityColumn;

  /// No description provided for @mockAdminChangePassword.
  ///
  /// In zh, this message translates to:
  /// **'修改密码'**
  String get mockAdminChangePassword;

  /// No description provided for @mockAdminChooseLater.
  ///
  /// In zh, this message translates to:
  /// **'待选择'**
  String get mockAdminChooseLater;

  /// No description provided for @mockAdminClientAudience.
  ///
  /// In zh, this message translates to:
  /// **'用户端'**
  String get mockAdminClientAudience;

  /// No description provided for @mockAdminClientLogin.
  ///
  /// In zh, this message translates to:
  /// **'进入用户端登录'**
  String get mockAdminClientLogin;

  /// No description provided for @mockAdminClientNavigation.
  ///
  /// In zh, this message translates to:
  /// **'用户端导航'**
  String get mockAdminClientNavigation;

  /// No description provided for @mockAdminClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get mockAdminClose;

  /// No description provided for @mockAdminClosedExample.
  ///
  /// In zh, this message translates to:
  /// **'关闭新注册'**
  String get mockAdminClosedExample;

  /// No description provided for @mockAdminCompleted.
  ///
  /// In zh, this message translates to:
  /// **'已完成'**
  String get mockAdminCompleted;

  /// No description provided for @mockAdminConfirmPassword.
  ///
  /// In zh, this message translates to:
  /// **'确认新密码'**
  String get mockAdminConfirmPassword;

  /// No description provided for @mockAdminCurrentPassword.
  ///
  /// In zh, this message translates to:
  /// **'当前密码'**
  String get mockAdminCurrentPassword;

  /// No description provided for @mockAdminCurrentPasswordIncorrect.
  ///
  /// In zh, this message translates to:
  /// **'当前密码不正确'**
  String get mockAdminCurrentPasswordIncorrect;

  /// No description provided for @mockAdminCurrentPolicy.
  ///
  /// In zh, this message translates to:
  /// **'当前策略'**
  String get mockAdminCurrentPolicy;

  /// No description provided for @mockAdminCurrentSession.
  ///
  /// In zh, this message translates to:
  /// **'当前管理端会话'**
  String get mockAdminCurrentSession;

  /// No description provided for @mockAdminDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get mockAdminDefault;

  /// No description provided for @mockAdminEmailColumn.
  ///
  /// In zh, this message translates to:
  /// **'登录邮箱'**
  String get mockAdminEmailColumn;

  /// No description provided for @mockAdminEmailRecovery.
  ///
  /// In zh, this message translates to:
  /// **'邮件恢复'**
  String get mockAdminEmailRecovery;

  /// No description provided for @mockAdminEmailVerification.
  ///
  /// In zh, this message translates to:
  /// **'邮箱验证'**
  String get mockAdminEmailVerification;

  /// No description provided for @mockAdminInactive.
  ///
  /// In zh, this message translates to:
  /// **'未启用'**
  String get mockAdminInactive;

  /// No description provided for @mockAdminInvalidCredentials.
  ///
  /// In zh, this message translates to:
  /// **'邮箱或密码不正确'**
  String get mockAdminInvalidCredentials;

  /// No description provided for @mockAdminJobReferenceColumn.
  ///
  /// In zh, this message translates to:
  /// **'任务引用'**
  String get mockAdminJobReferenceColumn;

  /// No description provided for @mockAdminJobSummary.
  ///
  /// In zh, this message translates to:
  /// **'任务摘要'**
  String get mockAdminJobSummary;

  /// No description provided for @mockAdminJobs.
  ///
  /// In zh, this message translates to:
  /// **'任务与资源'**
  String get mockAdminJobs;

  /// No description provided for @mockAdminKnownUsageColumn.
  ///
  /// In zh, this message translates to:
  /// **'已知用量'**
  String get mockAdminKnownUsageColumn;

  /// No description provided for @mockAdminLearnerA.
  ///
  /// In zh, this message translates to:
  /// **'学习者 A'**
  String get mockAdminLearnerA;

  /// No description provided for @mockAdminLearnerB.
  ///
  /// In zh, this message translates to:
  /// **'学习者 B'**
  String get mockAdminLearnerB;

  /// No description provided for @mockAdminLearnerRole.
  ///
  /// In zh, this message translates to:
  /// **'学习者'**
  String get mockAdminLearnerRole;

  /// No description provided for @mockAdminLoginAction.
  ///
  /// In zh, this message translates to:
  /// **'登录管理端'**
  String get mockAdminLoginAction;

  /// No description provided for @mockAdminLoginEmail.
  ///
  /// In zh, this message translates to:
  /// **'登录邮箱'**
  String get mockAdminLoginEmail;

  /// No description provided for @mockAdminLoginEmailExample.
  ///
  /// In zh, this message translates to:
  /// **'example@demo.test'**
  String get mockAdminLoginEmailExample;

  /// No description provided for @mockAdminLoginEmailInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效邮箱'**
  String get mockAdminLoginEmailInvalid;

  /// No description provided for @mockAdminLoginEntry.
  ///
  /// In zh, this message translates to:
  /// **'管理端登录'**
  String get mockAdminLoginEntry;

  /// No description provided for @mockAdminLoginEyebrow.
  ///
  /// In zh, this message translates to:
  /// **'ADMIN / HARUKA'**
  String get mockAdminLoginEyebrow;

  /// No description provided for @mockAdminLoginHero.
  ///
  /// In zh, this message translates to:
  /// **'管理端，独立登录。'**
  String get mockAdminLoginHero;

  /// No description provided for @mockAdminLoginPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码'**
  String get mockAdminLoginPassword;

  /// No description provided for @mockAdminLoginPasswordHint.
  ///
  /// In zh, this message translates to:
  /// **'输入密码'**
  String get mockAdminLoginPasswordHint;

  /// No description provided for @mockAdminLoginPasswordInvalid.
  ///
  /// In zh, this message translates to:
  /// **'密码至少 6 位'**
  String get mockAdminLoginPasswordInvalid;

  /// No description provided for @mockAdminLoginTitle.
  ///
  /// In zh, this message translates to:
  /// **'登录管理端'**
  String get mockAdminLoginTitle;

  /// No description provided for @mockAdminLogout.
  ///
  /// In zh, this message translates to:
  /// **'退出管理端'**
  String get mockAdminLogout;

  /// No description provided for @mockAdminManagementPermissions.
  ///
  /// In zh, this message translates to:
  /// **'管理权限'**
  String get mockAdminManagementPermissions;

  /// No description provided for @mockAdminManualRecovery.
  ///
  /// In zh, this message translates to:
  /// **'人工恢复'**
  String get mockAdminManualRecovery;

  /// No description provided for @mockAdminMaterialParse.
  ///
  /// In zh, this message translates to:
  /// **'材料解析'**
  String get mockAdminMaterialParse;

  /// No description provided for @mockAdminMembersColumn.
  ///
  /// In zh, this message translates to:
  /// **'成员'**
  String get mockAdminMembersColumn;

  /// No description provided for @mockAdminMenuDiagnosis.
  ///
  /// In zh, this message translates to:
  /// **'学习诊断'**
  String get mockAdminMenuDiagnosis;

  /// No description provided for @mockAdminMenuExercises.
  ///
  /// In zh, this message translates to:
  /// **'AI 习题'**
  String get mockAdminMenuExercises;

  /// No description provided for @mockAdminMenuLibrary.
  ///
  /// In zh, this message translates to:
  /// **'材料库'**
  String get mockAdminMenuLibrary;

  /// No description provided for @mockAdminMenuMistakes.
  ///
  /// In zh, this message translates to:
  /// **'错题库'**
  String get mockAdminMenuMistakes;

  /// No description provided for @mockAdminMenuNotebooks.
  ///
  /// In zh, this message translates to:
  /// **'单词本'**
  String get mockAdminMenuNotebooks;

  /// No description provided for @mockAdminMenuQuery.
  ///
  /// In zh, this message translates to:
  /// **'查询'**
  String get mockAdminMenuQuery;

  /// No description provided for @mockAdminMenuSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get mockAdminMenuSettings;

  /// No description provided for @mockAdminMenus.
  ///
  /// In zh, this message translates to:
  /// **'页面与菜单'**
  String get mockAdminMenus;

  /// No description provided for @mockAdminModelCall.
  ///
  /// In zh, this message translates to:
  /// **'模型调用'**
  String get mockAdminModelCall;

  /// No description provided for @mockAdminNeedsAction.
  ///
  /// In zh, this message translates to:
  /// **'需处理'**
  String get mockAdminNeedsAction;

  /// No description provided for @mockAdminNeedsAttention.
  ///
  /// In zh, this message translates to:
  /// **'待关注'**
  String get mockAdminNeedsAttention;

  /// No description provided for @mockAdminNeedsConfiguration.
  ///
  /// In zh, this message translates to:
  /// **'待配置'**
  String get mockAdminNeedsConfiguration;

  /// No description provided for @mockAdminNewPassword.
  ///
  /// In zh, this message translates to:
  /// **'新密码'**
  String get mockAdminNewPassword;

  /// No description provided for @mockAdminNoUsers.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的账号'**
  String get mockAdminNoUsers;

  /// No description provided for @mockAdminNormal.
  ///
  /// In zh, this message translates to:
  /// **'正常'**
  String get mockAdminNormal;

  /// No description provided for @mockAdminOnlineDemoSession.
  ///
  /// In zh, this message translates to:
  /// **'运维账号 · 在线会话'**
  String get mockAdminOnlineDemoSession;

  /// No description provided for @mockAdminOpenNavigation.
  ///
  /// In zh, this message translates to:
  /// **'打开管理导航'**
  String get mockAdminOpenNavigation;

  /// No description provided for @mockAdminOperator.
  ///
  /// In zh, this message translates to:
  /// **'运维账号'**
  String get mockAdminOperator;

  /// No description provided for @mockAdminOverview.
  ///
  /// In zh, this message translates to:
  /// **'运维概览'**
  String get mockAdminOverview;

  /// No description provided for @mockAdminOwnDevice.
  ///
  /// In zh, this message translates to:
  /// **'本人设备'**
  String get mockAdminOwnDevice;

  /// No description provided for @mockAdminPartialAudioSeconds.
  ///
  /// In zh, this message translates to:
  /// **'部分音频秒数'**
  String get mockAdminPartialAudioSeconds;

  /// No description provided for @mockAdminPasswordAllDevices.
  ///
  /// In zh, this message translates to:
  /// **'修改密码后，所有设备需要重新登录。'**
  String get mockAdminPasswordAllDevices;

  /// No description provided for @mockAdminPasswordFlow.
  ///
  /// In zh, this message translates to:
  /// **'修改密码流程'**
  String get mockAdminPasswordFlow;

  /// No description provided for @mockAdminPasswordMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入的新密码不一致'**
  String get mockAdminPasswordMismatch;

  /// No description provided for @mockAdminPasswordRelogin.
  ///
  /// In zh, this message translates to:
  /// **'修改密码后需要重新登录。'**
  String get mockAdminPasswordRelogin;

  /// No description provided for @mockAdminPasswordTooShort.
  ///
  /// In zh, this message translates to:
  /// **'新密码至少需要 8 个字符'**
  String get mockAdminPasswordTooShort;

  /// No description provided for @mockAdminPasswordUnchanged.
  ///
  /// In zh, this message translates to:
  /// **'新密码不能与当前密码相同'**
  String get mockAdminPasswordUnchanged;

  /// No description provided for @mockAdminPasswordUpdated.
  ///
  /// In zh, this message translates to:
  /// **'密码已更新，请重新登录'**
  String get mockAdminPasswordUpdated;

  /// No description provided for @mockAdminPendingApproval.
  ///
  /// In zh, this message translates to:
  /// **'待审批'**
  String get mockAdminPendingApproval;

  /// No description provided for @mockAdminPendingJobs.
  ///
  /// In zh, this message translates to:
  /// **'待处理任务'**
  String get mockAdminPendingJobs;

  /// No description provided for @mockAdminPermissionChanges.
  ///
  /// In zh, this message translates to:
  /// **'授权变化'**
  String get mockAdminPermissionChanges;

  /// No description provided for @mockAdminPolicy.
  ///
  /// In zh, this message translates to:
  /// **'注册策略'**
  String get mockAdminPolicy;

  /// No description provided for @mockAdminPolicyApplied.
  ///
  /// In zh, this message translates to:
  /// **'策略已更新'**
  String get mockAdminPolicyApplied;

  /// No description provided for @mockAdminPreview.
  ///
  /// In zh, this message translates to:
  /// **'预览'**
  String get mockAdminPreview;

  /// No description provided for @mockAdminPreviewPolicy.
  ///
  /// In zh, this message translates to:
  /// **'预览策略变化'**
  String get mockAdminPreviewPolicy;

  /// No description provided for @mockAdminProtected.
  ///
  /// In zh, this message translates to:
  /// **'受保护'**
  String get mockAdminProtected;

  /// No description provided for @mockAdminPrototypeNotice.
  ///
  /// In zh, this message translates to:
  /// **'管理操作需保持在线。'**
  String get mockAdminPrototypeNotice;

  /// No description provided for @mockAdminProviderAttempts.
  ///
  /// In zh, this message translates to:
  /// **'供应商调用次数'**
  String get mockAdminProviderAttempts;

  /// No description provided for @mockAdminPublishAfterValidation.
  ///
  /// In zh, this message translates to:
  /// **'验证后发布'**
  String get mockAdminPublishAfterValidation;

  /// No description provided for @mockAdminQueueAlert.
  ///
  /// In zh, this message translates to:
  /// **'任务队列有 2 项等待重试'**
  String get mockAdminQueueAlert;

  /// No description provided for @mockAdminReadExample.
  ///
  /// In zh, this message translates to:
  /// **'已读取'**
  String get mockAdminReadExample;

  /// No description provided for @mockAdminReadRegistrationPolicy.
  ///
  /// In zh, this message translates to:
  /// **'注册策略读取'**
  String get mockAdminReadRegistrationPolicy;

  /// No description provided for @mockAdminRegistrationEntry.
  ///
  /// In zh, this message translates to:
  /// **'注册入口'**
  String get mockAdminRegistrationEntry;

  /// No description provided for @mockAdminRegistrationMode.
  ///
  /// In zh, this message translates to:
  /// **'注册方式'**
  String get mockAdminRegistrationMode;

  /// No description provided for @mockAdminRequestSuccess.
  ///
  /// In zh, this message translates to:
  /// **'请求成功率'**
  String get mockAdminRequestSuccess;

  /// No description provided for @mockAdminRestricted.
  ///
  /// In zh, this message translates to:
  /// **'受限'**
  String get mockAdminRestricted;

  /// No description provided for @mockAdminResultColumn.
  ///
  /// In zh, this message translates to:
  /// **'结果'**
  String get mockAdminResultColumn;

  /// No description provided for @mockAdminRetryCheck.
  ///
  /// In zh, this message translates to:
  /// **'重试检查'**
  String get mockAdminRetryCheck;

  /// No description provided for @mockAdminRibbon.
  ///
  /// In zh, this message translates to:
  /// **'管理端'**
  String get mockAdminRibbon;

  /// No description provided for @mockAdminRoleAlert.
  ///
  /// In zh, this message translates to:
  /// **'角色更新待核对'**
  String get mockAdminRoleAlert;

  /// No description provided for @mockAdminRoleColumn.
  ///
  /// In zh, this message translates to:
  /// **'角色'**
  String get mockAdminRoleColumn;

  /// No description provided for @mockAdminRoleGrantPreview.
  ///
  /// In zh, this message translates to:
  /// **'角色授权预览'**
  String get mockAdminRoleGrantPreview;

  /// No description provided for @mockAdminRolePreviewOnly.
  ///
  /// In zh, this message translates to:
  /// **'保存角色变更前请核对授权范围。'**
  String get mockAdminRolePreviewOnly;

  /// No description provided for @mockAdminRoleSummary.
  ///
  /// In zh, this message translates to:
  /// **'{role}角色'**
  String mockAdminRoleSummary(String role);

  /// No description provided for @mockAdminRoles.
  ///
  /// In zh, this message translates to:
  /// **'角色与权限'**
  String get mockAdminRoles;

  /// No description provided for @mockAdminSearchUsers.
  ///
  /// In zh, this message translates to:
  /// **'搜索账号'**
  String get mockAdminSearchUsers;

  /// No description provided for @mockAdminSavePassword.
  ///
  /// In zh, this message translates to:
  /// **'保存新密码'**
  String get mockAdminSavePassword;

  /// No description provided for @mockAdminSecurityNav.
  ///
  /// In zh, this message translates to:
  /// **'账号安全'**
  String get mockAdminSecurityNav;

  /// No description provided for @mockAdminSessionRevocation.
  ///
  /// In zh, this message translates to:
  /// **'会话撤销'**
  String get mockAdminSessionRevocation;

  /// No description provided for @mockAdminStageColumn.
  ///
  /// In zh, this message translates to:
  /// **'阶段'**
  String get mockAdminStageColumn;

  /// No description provided for @mockAdminStatusColumn.
  ///
  /// In zh, this message translates to:
  /// **'状态'**
  String get mockAdminStatusColumn;

  /// No description provided for @mockAdminSubmittedExample.
  ///
  /// In zh, this message translates to:
  /// **'已提交'**
  String get mockAdminSubmittedExample;

  /// No description provided for @mockAdminSummary.
  ///
  /// In zh, this message translates to:
  /// **'运维摘要'**
  String get mockAdminSummary;

  /// No description provided for @mockAdminSummaryStatus.
  ///
  /// In zh, this message translates to:
  /// **'当前状态：正常。'**
  String get mockAdminSummaryStatus;

  /// No description provided for @mockAdminSuperRole.
  ///
  /// In zh, this message translates to:
  /// **'超级管理员'**
  String get mockAdminSuperRole;

  /// No description provided for @mockAdminSupportRole.
  ///
  /// In zh, this message translates to:
  /// **'支持人员'**
  String get mockAdminSupportRole;

  /// No description provided for @mockAdminSwitchToClient.
  ///
  /// In zh, this message translates to:
  /// **'切换到用户端'**
  String get mockAdminSwitchToClient;

  /// No description provided for @mockAdminTargetScopeColumn.
  ///
  /// In zh, this message translates to:
  /// **'目标范围'**
  String get mockAdminTargetScopeColumn;

  /// No description provided for @mockAdminTextModel.
  ///
  /// In zh, this message translates to:
  /// **'文本模型'**
  String get mockAdminTextModel;

  /// No description provided for @mockAdminTimeColumn.
  ///
  /// In zh, this message translates to:
  /// **'时间'**
  String get mockAdminTimeColumn;

  /// No description provided for @mockAdminTypeColumn.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get mockAdminTypeColumn;

  /// No description provided for @mockAdminUnknownUsageAttempts.
  ///
  /// In zh, this message translates to:
  /// **'用量未提供的 attempts'**
  String get mockAdminUnknownUsageAttempts;

  /// No description provided for @mockAdminUnknownUsageColumn.
  ///
  /// In zh, this message translates to:
  /// **'未知用量'**
  String get mockAdminUnknownUsageColumn;

  /// No description provided for @mockAdminUsage.
  ///
  /// In zh, this message translates to:
  /// **'模型用量'**
  String get mockAdminUsage;

  /// No description provided for @mockAdminUserColumn.
  ///
  /// In zh, this message translates to:
  /// **'用户'**
  String get mockAdminUserColumn;

  /// No description provided for @mockAdminUserList.
  ///
  /// In zh, this message translates to:
  /// **'用户列表'**
  String get mockAdminUserList;

  /// No description provided for @mockAdminUsers.
  ///
  /// In zh, this message translates to:
  /// **'用户与会话'**
  String get mockAdminUsers;

  /// No description provided for @mockAdminVerifyWhenEnabled.
  ///
  /// In zh, this message translates to:
  /// **'启用后校验'**
  String get mockAdminVerifyWhenEnabled;

  /// No description provided for @mockAdminViewJobs.
  ///
  /// In zh, this message translates to:
  /// **'查看任务'**
  String get mockAdminViewJobs;

  /// No description provided for @mockAdminViewOperationalSummary.
  ///
  /// In zh, this message translates to:
  /// **'查看运维摘要'**
  String get mockAdminViewOperationalSummary;

  /// No description provided for @mockAdminViewRoles.
  ///
  /// In zh, this message translates to:
  /// **'查看角色'**
  String get mockAdminViewRoles;

  /// No description provided for @mockAdminViewSummary.
  ///
  /// In zh, this message translates to:
  /// **'查看摘要'**
  String get mockAdminViewSummary;

  /// No description provided for @mockAdminVisibleProviderCategories.
  ///
  /// In zh, this message translates to:
  /// **'可见供应商类别'**
  String get mockAdminVisibleProviderCategories;

  /// No description provided for @mockAdminVisibleWhenAuthorized.
  ///
  /// In zh, this message translates to:
  /// **'授权后显示'**
  String get mockAdminVisibleWhenAuthorized;

  /// No description provided for @mockAdminVisionModel.
  ///
  /// In zh, this message translates to:
  /// **'视觉模型'**
  String get mockAdminVisionModel;

  /// No description provided for @mockAdminWaitingOwnCredential.
  ///
  /// In zh, this message translates to:
  /// **'等待本人凭据'**
  String get mockAdminWaitingOwnCredential;

  /// No description provided for @mockAdminYesterday.
  ///
  /// In zh, this message translates to:
  /// **'昨天'**
  String get mockAdminYesterday;

  /// No description provided for @mockAdminPolicyPreviewTitle.
  ///
  /// In zh, this message translates to:
  /// **'策略变更预览'**
  String get mockAdminPolicyPreviewTitle;

  /// No description provided for @mockAdminTokenCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} Token'**
  String mockAdminTokenCount(String count);

  /// No description provided for @mockAdminTts.
  ///
  /// In zh, this message translates to:
  /// **'语音合成'**
  String get mockAdminTts;

  /// No description provided for @mockSettingAudioCacheLimit.
  ///
  /// In zh, this message translates to:
  /// **'音频副本上限'**
  String get mockSettingAudioCacheLimit;

  /// No description provided for @mockSettingContextBudget.
  ///
  /// In zh, this message translates to:
  /// **'前后文预算'**
  String get mockSettingContextBudget;

  /// No description provided for @mockSettingIdentityUnavailableInMock.
  ///
  /// In zh, this message translates to:
  /// **'当前无法执行此操作'**
  String get mockSettingIdentityUnavailableInMock;

  /// No description provided for @mockSettingLocalSpace.
  ///
  /// In zh, this message translates to:
  /// **'本机空间'**
  String get mockSettingLocalSpace;

  /// No description provided for @mockSettingPersonalApiKey.
  ///
  /// In zh, this message translates to:
  /// **'个人 API Key'**
  String get mockSettingPersonalApiKey;

  /// No description provided for @mockSettingPlaybackSpeed.
  ///
  /// In zh, this message translates to:
  /// **'播放倍速'**
  String get mockSettingPlaybackSpeed;

  /// No description provided for @mockSettingSaveCacheLimits.
  ///
  /// In zh, this message translates to:
  /// **'保存本机上限'**
  String get mockSettingSaveCacheLimits;

  /// No description provided for @mockMaterialCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get mockMaterialCancel;

  /// No description provided for @mockMaterialChapterPreparationAccepted.
  ///
  /// In zh, this message translates to:
  /// **'本章准备已受理'**
  String get mockMaterialChapterPreparationAccepted;

  /// No description provided for @mockMaterialChapterProgress.
  ///
  /// In zh, this message translates to:
  /// **'解析 {analysis}/{total} · 朗读 {audio}/{total}'**
  String mockMaterialChapterProgress(int analysis, int audio, int total);

  /// No description provided for @mockMaterialChapterCountOf.
  ///
  /// In zh, this message translates to:
  /// **'第 {chapter} 章 / {total} 章'**
  String mockMaterialChapterCountOf(int chapter, int total);

  /// No description provided for @mockMaterialChapterFooter.
  ///
  /// In zh, this message translates to:
  /// **'{chapter} / {total}'**
  String mockMaterialChapterFooter(int chapter, int total);

  /// No description provided for @mockMaterialStartPreparation.
  ///
  /// In zh, this message translates to:
  /// **'开始准备'**
  String get mockMaterialStartPreparation;

  /// No description provided for @mockSettingClearCacheConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'清除此账号本机缓存？'**
  String get mockSettingClearCacheConfirmTitle;

  /// No description provided for @mockSettingSaveSettings.
  ///
  /// In zh, this message translates to:
  /// **'保存设置'**
  String get mockSettingSaveSettings;

  /// No description provided for @mockSettingSettingsSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存'**
  String get mockSettingSettingsSaved;

  /// No description provided for @mockProfileSavedTimezoneFailed.
  ///
  /// In zh, this message translates to:
  /// **'个人资料已保存，时区未保存，请重试'**
  String get mockProfileSavedTimezoneFailed;

  /// No description provided for @mockProfileBirthYearInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的出生年份'**
  String get mockProfileBirthYearInvalid;

  /// No description provided for @mockSettingLanguageLevelSummary.
  ///
  /// In zh, this message translates to:
  /// **'{language} · {level}'**
  String mockSettingLanguageLevelSummary(String language, String level);

  /// No description provided for @mockSettingViewSession.
  ///
  /// In zh, this message translates to:
  /// **'查看会话'**
  String get mockSettingViewSession;

  /// No description provided for @mockMaterialBackToEdit.
  ///
  /// In zh, this message translates to:
  /// **'返回修改'**
  String get mockMaterialBackToEdit;

  /// No description provided for @mockMaterialListeningCandidateMatchDescription.
  ///
  /// In zh, this message translates to:
  /// **'候选题组 1：两人最后决定在哪里见面？'**
  String get mockMaterialListeningCandidateMatchDescription;

  /// No description provided for @mockMaterialReviewListeningScript.
  ///
  /// In zh, this message translates to:
  /// **'校对听力稿'**
  String get mockMaterialReviewListeningScript;

  /// No description provided for @mockAuthBackToLoginDemo.
  ///
  /// In zh, this message translates to:
  /// **'返回登录'**
  String get mockAuthBackToLoginDemo;

  /// No description provided for @mockAuthBrand.
  ///
  /// In zh, this message translates to:
  /// **'haruka'**
  String get mockAuthBrand;

  /// No description provided for @mockAuthClearSignal.
  ///
  /// In zh, this message translates to:
  /// **'CLEAR SIGNAL'**
  String get mockAuthClearSignal;

  /// No description provided for @mockAuthConfirmPasswordPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'再次输入密码'**
  String get mockAuthConfirmPasswordPlaceholder;

  /// No description provided for @mockAuthConfirmRequired.
  ///
  /// In zh, this message translates to:
  /// **'请再次输入密码'**
  String get mockAuthConfirmRequired;

  /// No description provided for @mockAuthDesktopConfirmPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'再次输入密码'**
  String get mockAuthDesktopConfirmPlaceholder;

  /// No description provided for @mockAuthDesktopEmail.
  ///
  /// In zh, this message translates to:
  /// **'登录邮箱'**
  String get mockAuthDesktopEmail;

  /// No description provided for @mockAuthDesktopEmailPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'example@demo.test'**
  String get mockAuthDesktopEmailPlaceholder;

  /// No description provided for @mockAuthDesktopLoginTitle.
  ///
  /// In zh, this message translates to:
  /// **'登录账号'**
  String get mockAuthDesktopLoginTitle;

  /// No description provided for @mockAuthDesktopPasswordPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'输入密码'**
  String get mockAuthDesktopPasswordPlaceholder;

  /// No description provided for @mockAuthDesktopRegisterTitle.
  ///
  /// In zh, this message translates to:
  /// **'创建账号'**
  String get mockAuthDesktopRegisterTitle;

  /// No description provided for @mockAuthDesktopSubmitRegister.
  ///
  /// In zh, this message translates to:
  /// **'创建账号'**
  String get mockAuthDesktopSubmitRegister;

  /// No description provided for @mockAuthEmailRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入邮箱'**
  String get mockAuthEmailRequired;

  /// No description provided for @mockAuthEnterWorkspace.
  ///
  /// In zh, this message translates to:
  /// **'进入学习空间'**
  String get mockAuthEnterWorkspace;

  /// No description provided for @mockAuthForgotPasswordDesktop.
  ///
  /// In zh, this message translates to:
  /// **'忘记密码'**
  String get mockAuthForgotPasswordDesktop;

  /// No description provided for @mockAuthHeroDescription.
  ///
  /// In zh, this message translates to:
  /// **'把自己的小说、课本与试卷，变成可阅读、理解和练习的语言学习空间。'**
  String get mockAuthHeroDescription;

  /// No description provided for @mockAuthHideConfirmPassword.
  ///
  /// In zh, this message translates to:
  /// **'隐藏确认密码'**
  String get mockAuthHideConfirmPassword;

  /// No description provided for @mockAuthMobileEmailPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'name@example.com'**
  String get mockAuthMobileEmailPlaceholder;

  /// No description provided for @mockAuthMobilePasswordPlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'输入密码'**
  String get mockAuthMobilePasswordPlaceholder;

  /// No description provided for @mockAuthNextStep.
  ///
  /// In zh, this message translates to:
  /// **'下一步'**
  String get mockAuthNextStep;

  /// No description provided for @mockAuthNoAccount.
  ///
  /// In zh, this message translates to:
  /// **'还没有账号？'**
  String get mockAuthNoAccount;

  /// No description provided for @mockAuthPasswordLength.
  ///
  /// In zh, this message translates to:
  /// **'密码须为 15–128 个字符'**
  String get mockAuthPasswordLength;

  /// No description provided for @mockAuthPasswordLengthHint.
  ///
  /// In zh, this message translates to:
  /// **'15–128 个字符，可包含空格'**
  String get mockAuthPasswordLengthHint;

  /// No description provided for @mockAuthPasswordRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入密码'**
  String get mockAuthPasswordRequired;

  /// No description provided for @mockAuthPersonalWorkspace.
  ///
  /// In zh, this message translates to:
  /// **'个人学习空间'**
  String get mockAuthPersonalWorkspace;

  /// No description provided for @mockAuthProbe.
  ///
  /// In zh, this message translates to:
  /// **'检查地址'**
  String get mockAuthProbe;

  /// No description provided for @mockAuthProbeComplete.
  ///
  /// In zh, this message translates to:
  /// **'地址格式有效'**
  String get mockAuthProbeComplete;

  /// No description provided for @mockAuthRecoverAccount.
  ///
  /// In zh, this message translates to:
  /// **'找回账号'**
  String get mockAuthRecoverAccount;

  /// No description provided for @mockAuthRecoveryIntro.
  ///
  /// In zh, this message translates to:
  /// **'输入登录邮箱，提交找回申请。'**
  String get mockAuthRecoveryIntro;

  /// No description provided for @mockAuthRecoveryReceived.
  ///
  /// In zh, this message translates to:
  /// **'找回申请已受理'**
  String get mockAuthRecoveryReceived;

  /// No description provided for @mockAuthRegistrationAcceptedDesktop.
  ///
  /// In zh, this message translates to:
  /// **'注册请求已受理'**
  String get mockAuthRegistrationAcceptedDesktop;

  /// No description provided for @mockAuthServiceConstraint.
  ///
  /// In zh, this message translates to:
  /// **'不能包含账号密码、查询参数或片段。'**
  String get mockAuthServiceConstraint;

  /// No description provided for @mockAuthServiceConnectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'服务连接'**
  String get mockAuthServiceConnectionTitle;

  /// No description provided for @mockAuthServiceField.
  ///
  /// In zh, this message translates to:
  /// **'Haruka 服务地址'**
  String get mockAuthServiceField;

  /// No description provided for @mockAuthServiceInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的 HTTPS 服务地址'**
  String get mockAuthServiceInvalid;

  /// No description provided for @mockAuthServicePlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'https://your-haruka.example'**
  String get mockAuthServicePlaceholder;

  /// No description provided for @mockAuthServiceTitle.
  ///
  /// In zh, this message translates to:
  /// **'服务地址'**
  String get mockAuthServiceTitle;

  /// No description provided for @mockAuthSetPassword.
  ///
  /// In zh, this message translates to:
  /// **'设置密码'**
  String get mockAuthSetPassword;

  /// No description provided for @mockAuthShowConfirmPassword.
  ///
  /// In zh, this message translates to:
  /// **'显示确认密码'**
  String get mockAuthShowConfirmPassword;

  /// No description provided for @mockAuthViewResult.
  ///
  /// In zh, this message translates to:
  /// **'提交申请'**
  String get mockAuthViewResult;

  /// No description provided for @mockMaterialAiExplanation.
  ///
  /// In zh, this message translates to:
  /// **'AI 解析'**
  String get mockMaterialAiExplanation;

  /// No description provided for @mockMaterialAiExplanationDescription.
  ///
  /// In zh, this message translates to:
  /// **'逐句译文、意群与语法释义'**
  String get mockMaterialAiExplanationDescription;

  /// No description provided for @mockMaterialAnalysisMode.
  ///
  /// In zh, this message translates to:
  /// **'解析'**
  String get mockMaterialAnalysisMode;

  /// No description provided for @mockMaterialAnalysisModeHint.
  ///
  /// In zh, this message translates to:
  /// **'点击句子看解析，长按可选词查询。'**
  String get mockMaterialAnalysisModeHint;

  /// No description provided for @mockMaterialChapterAfterRain.
  ///
  /// In zh, this message translates to:
  /// **'雨停之后'**
  String get mockMaterialChapterAfterRain;

  /// No description provided for @mockMaterialChapterBeyondWindow.
  ///
  /// In zh, this message translates to:
  /// **'窓の向こう'**
  String get mockMaterialChapterBeyondWindow;

  /// No description provided for @mockMaterialChapterLetterToFuture.
  ///
  /// In zh, this message translates to:
  /// **'写给未来的你'**
  String get mockMaterialChapterLetterToFuture;

  /// No description provided for @mockMaterialChapterSeasideMailbox.
  ///
  /// In zh, this message translates to:
  /// **'海边的邮筒'**
  String get mockMaterialChapterSeasideMailbox;

  /// No description provided for @mockMaterialDeletedMessage.
  ///
  /// In zh, this message translates to:
  /// **'材料已删除'**
  String get mockMaterialDeletedMessage;

  /// No description provided for @mockMaterialDetailsTitle.
  ///
  /// In zh, this message translates to:
  /// **'材料详情'**
  String get mockMaterialDetailsTitle;

  /// No description provided for @mockMaterialNovelFamiliarHandwritingSentence.
  ///
  /// In zh, this message translates to:
  /// **'見覚えのある文字を見て、私は思わず微笑んだ。'**
  String get mockMaterialNovelFamiliarHandwritingSentence;

  /// No description provided for @mockMaterialNovelLetterOnDeskSentence.
  ///
  /// In zh, this message translates to:
  /// **'机の上には、一通の手紙が置かれていた。'**
  String get mockMaterialNovelLetterOnDeskSentence;

  /// No description provided for @mockMaterialNovelMorningLightSentence.
  ///
  /// In zh, this message translates to:
  /// **'朝の光が、白いカーテンを通して部屋に広がった。'**
  String get mockMaterialNovelMorningLightSentence;

  /// No description provided for @mockMaterialNovelSummerWindSentence.
  ///
  /// In zh, this message translates to:
  /// **'窓を開けると、夏の風がそっと頬に触れた。'**
  String get mockMaterialNovelSummerWindSentence;

  /// No description provided for @mockMaterialNovelUnfamiliarWordsSentence.
  ///
  /// In zh, this message translates to:
  /// **'まだ知らない言葉にも、どこか懐かしい響きがある。'**
  String get mockMaterialNovelUnfamiliarWordsSentence;

  /// No description provided for @mockMaterialPreparationCacheOptions.
  ///
  /// In zh, this message translates to:
  /// **'缓存内容 · 可多选'**
  String get mockMaterialPreparationCacheOptions;

  /// No description provided for @mockMaterialPreparationReadyCount.
  ///
  /// In zh, this message translates to:
  /// **'{ready}/{total} 句本机就绪'**
  String mockMaterialPreparationReadyCount(int ready, int total);

  /// No description provided for @mockMaterialPreparationPreparedCount.
  ///
  /// In zh, this message translates to:
  /// **'{prepared}/{total} 句已准备'**
  String mockMaterialPreparationPreparedCount(int prepared, int total);

  /// No description provided for @mockMaterialPreparationPaused.
  ///
  /// In zh, this message translates to:
  /// **'已暂停，已完成内容保留。'**
  String get mockMaterialPreparationPaused;

  /// No description provided for @mockMaterialPausePreparation.
  ///
  /// In zh, this message translates to:
  /// **'暂停准备'**
  String get mockMaterialPausePreparation;

  /// No description provided for @mockMaterialContinuePreparation.
  ///
  /// In zh, this message translates to:
  /// **'继续准备'**
  String get mockMaterialContinuePreparation;

  /// No description provided for @mockMaterialPreparationComplete.
  ///
  /// In zh, this message translates to:
  /// **'本章准备完成'**
  String get mockMaterialPreparationComplete;

  /// No description provided for @mockMaterialOriginalText.
  ///
  /// In zh, this message translates to:
  /// **'原文'**
  String get mockMaterialOriginalText;

  /// No description provided for @mockMaterialTranslation.
  ///
  /// In zh, this message translates to:
  /// **'译文'**
  String get mockMaterialTranslation;

  /// No description provided for @mockMaterialPreviousSentence.
  ///
  /// In zh, this message translates to:
  /// **'上一句'**
  String get mockMaterialPreviousSentence;

  /// No description provided for @mockMaterialNextSentence.
  ///
  /// In zh, this message translates to:
  /// **'下一句'**
  String get mockMaterialNextSentence;

  /// No description provided for @mockMaterialSentencePosition.
  ///
  /// In zh, this message translates to:
  /// **'第 {current} / {total} 句'**
  String mockMaterialSentencePosition(int current, int total);

  /// No description provided for @mockMaterialNovelMorningLightTranslation.
  ///
  /// In zh, this message translates to:
  /// **'晨光穿过白色窗帘，洒满房间。'**
  String get mockMaterialNovelMorningLightTranslation;

  /// No description provided for @mockMaterialNovelMorningLightRubySegments.
  ///
  /// In zh, this message translates to:
  /// **'朝~あさ|の~|光~ひかり|が、~|白い~しろい|カーテンを~|通して~とおして|部屋~へや|に~|広がった~ひろがった|。~'**
  String get mockMaterialNovelMorningLightRubySegments;

  /// No description provided for @mockMaterialNovelSummerWindTranslation.
  ///
  /// In zh, this message translates to:
  /// **'打开窗户，夏风轻轻拂过脸颊。'**
  String get mockMaterialNovelSummerWindTranslation;

  /// No description provided for @mockMaterialNovelSummerWindRubySegments.
  ///
  /// In zh, this message translates to:
  /// **'窓~まど|を~|開ける~あける|と、~|夏~なつ|の~|風~かぜ|がそっと~|頬~ほほ|に~|触れた~ふれた|。~'**
  String get mockMaterialNovelSummerWindRubySegments;

  /// No description provided for @mockMaterialNovelLetterOnDeskTranslation.
  ///
  /// In zh, this message translates to:
  /// **'桌上放着一封信。'**
  String get mockMaterialNovelLetterOnDeskTranslation;

  /// No description provided for @mockMaterialNovelLetterOnDeskRubySegments.
  ///
  /// In zh, this message translates to:
  /// **'机~つくえ|の~|上~うえ|には、~|一通~いっつう|の~|手紙~てがみ|が~|置かれていた~おかれていた|。~'**
  String get mockMaterialNovelLetterOnDeskRubySegments;

  /// No description provided for @mockMaterialNovelFamiliarHandwritingTranslation.
  ///
  /// In zh, this message translates to:
  /// **'看见熟悉的字迹，我不由得微笑。'**
  String get mockMaterialNovelFamiliarHandwritingTranslation;

  /// No description provided for @mockMaterialNovelFamiliarHandwritingRubySegments.
  ///
  /// In zh, this message translates to:
  /// **'見覚え~みおぼえ|のある~|文字~もじ|を~|見て~みて|、~|私~わたし|は~|思わず~おもわず|微笑んだ~ほほえんだ|。~'**
  String get mockMaterialNovelFamiliarHandwritingRubySegments;

  /// No description provided for @mockMaterialNovelUnfamiliarWordsTranslation.
  ///
  /// In zh, this message translates to:
  /// **'那些还不认识的词语，也有种令人怀念的回响。'**
  String get mockMaterialNovelUnfamiliarWordsTranslation;

  /// No description provided for @mockMaterialNovelUnfamiliarWordsRubySegments.
  ///
  /// In zh, this message translates to:
  /// **'まだ~|知らない~しらない|言葉~ことば|にも、どこか~|懐かしい~なつかしい|響き~ひびき|がある。~'**
  String get mockMaterialNovelUnfamiliarWordsRubySegments;

  /// No description provided for @mockMaterialSentenceSource.
  ///
  /// In zh, this message translates to:
  /// **'{title} · 第 {chapter} 章 · {chapterTitle}'**
  String mockMaterialSentenceSource(String title, int chapter, String chapterTitle);

  /// No description provided for @mockMaterialListenOriginal.
  ///
  /// In zh, this message translates to:
  /// **'朗读原句'**
  String get mockMaterialListenOriginal;

  /// No description provided for @mockMaterialPauseOriginal.
  ///
  /// In zh, this message translates to:
  /// **'暂停朗读'**
  String get mockMaterialPauseOriginal;

  /// No description provided for @mockMaterialCollectSentence.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get mockMaterialCollectSentence;

  /// No description provided for @mockMaterialCollectedSentence.
  ///
  /// In zh, this message translates to:
  /// **'已收藏'**
  String get mockMaterialCollectedSentence;

  /// No description provided for @mockMaterialBookmarkLabel.
  ///
  /// In zh, this message translates to:
  /// **'书签'**
  String get mockMaterialBookmarkLabel;

  /// No description provided for @mockMaterialPrepareChapter.
  ///
  /// In zh, this message translates to:
  /// **'准备本章'**
  String get mockMaterialPrepareChapter;

  /// No description provided for @mockMaterialReadingMode.
  ///
  /// In zh, this message translates to:
  /// **'阅读'**
  String get mockMaterialReadingMode;

  /// No description provided for @mockMaterialReadingModeHint.
  ///
  /// In zh, this message translates to:
  /// **'长按一句，点选词汇后查询。'**
  String get mockMaterialReadingModeHint;

  /// No description provided for @mockMaterialSelectChapter.
  ///
  /// In zh, this message translates to:
  /// **'选择章节'**
  String get mockMaterialSelectChapter;

  /// No description provided for @mockMaterialSentenceAudio.
  ///
  /// In zh, this message translates to:
  /// **'逐句朗读'**
  String get mockMaterialSentenceAudio;

  /// No description provided for @mockMaterialSentenceAudioDescription.
  ///
  /// In zh, this message translates to:
  /// **'单句与连续朗读共用'**
  String get mockMaterialSentenceAudioDescription;

  /// No description provided for @mockMaterialStartLearning.
  ///
  /// In zh, this message translates to:
  /// **'开始学习'**
  String get mockMaterialStartLearning;

  /// No description provided for @mockMaterialStartReading.
  ///
  /// In zh, this message translates to:
  /// **'开始阅读'**
  String get mockMaterialStartReading;

  /// No description provided for @mockMaterialUnavailableMessage.
  ///
  /// In zh, this message translates to:
  /// **'材料已删除或不可读取'**
  String get mockMaterialUnavailableMessage;

  /// No description provided for @mockMaterialUnavailableTitle.
  ///
  /// In zh, this message translates to:
  /// **'材料不可用'**
  String get mockMaterialUnavailableTitle;

  /// No description provided for @mockMaterialViewExamPreparation.
  ///
  /// In zh, this message translates to:
  /// **'查看试卷准备'**
  String get mockMaterialViewExamPreparation;

  /// No description provided for @mockSettingAccountLanguageGroup.
  ///
  /// In zh, this message translates to:
  /// **'账号与语言'**
  String get mockSettingAccountLanguageGroup;

  /// No description provided for @mockSettingAppearance.
  ///
  /// In zh, this message translates to:
  /// **'外观设置'**
  String get mockSettingAppearance;

  /// No description provided for @mockSettingAppearanceSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'主题与动态'**
  String get mockSettingAppearanceSubtitle;

  /// No description provided for @mockSettingCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get mockSettingCancel;

  /// No description provided for @mockSettingClear.
  ///
  /// In zh, this message translates to:
  /// **'清理'**
  String get mockSettingClear;

  /// No description provided for @mockSettingClearCacheConfirmMessage.
  ///
  /// In zh, this message translates to:
  /// **'只清理本机副本；已保存成果仍可重新取得。'**
  String get mockSettingClearCacheConfirmMessage;

  /// No description provided for @mockSettingCacheCleared.
  ///
  /// In zh, this message translates to:
  /// **'本机缓存已清理'**
  String get mockSettingCacheCleared;

  /// No description provided for @mockSettingCacheOperationFailed.
  ///
  /// In zh, this message translates to:
  /// **'缓存操作失败，请重试'**
  String get mockSettingCacheOperationFailed;

  /// No description provided for @mockSettingCacheUpdateRequired.
  ///
  /// In zh, this message translates to:
  /// **'本机缓存由较新版本创建，请更新应用后重试'**
  String get mockSettingCacheUpdateRequired;

  /// No description provided for @mockSettingCacheWriterUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'本机缓存正由另一窗口使用，请返回已打开的窗口'**
  String get mockSettingCacheWriterUnavailable;

  /// No description provided for @cacheRevalidating.
  ///
  /// In zh, this message translates to:
  /// **'正在重新确认访问，请稍候'**
  String get cacheRevalidating;

  /// No description provided for @mockSettingCacheClearPartial.
  ///
  /// In zh, this message translates to:
  /// **'{count} 段音频仍待清理'**
  String mockSettingCacheClearPartial(int count);

  /// No description provided for @mockSettingDarkMode.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get mockSettingDarkMode;

  /// No description provided for @mockSettingEnglish.
  ///
  /// In zh, this message translates to:
  /// **'英语'**
  String get mockSettingEnglish;

  /// No description provided for @mockSettingFollowSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get mockSettingFollowSystem;

  /// No description provided for @mockSettingFontSize.
  ///
  /// In zh, this message translates to:
  /// **'字号'**
  String get mockSettingFontSize;

  /// No description provided for @mockSettingJapanese.
  ///
  /// In zh, this message translates to:
  /// **'日语'**
  String get mockSettingJapanese;

  /// No description provided for @mockSettingLastNinetyDays.
  ///
  /// In zh, this message translates to:
  /// **'90 天'**
  String get mockSettingLastNinetyDays;

  /// No description provided for @mockSettingLastSevenDays.
  ///
  /// In zh, this message translates to:
  /// **'7 天'**
  String get mockSettingLastSevenDays;

  /// No description provided for @mockSettingLastThirtyDays.
  ///
  /// In zh, this message translates to:
  /// **'30 天'**
  String get mockSettingLastThirtyDays;

  /// No description provided for @mockSettingLightMode.
  ///
  /// In zh, this message translates to:
  /// **'明亮'**
  String get mockSettingLightMode;

  /// No description provided for @mockSettingLocalCache.
  ///
  /// In zh, this message translates to:
  /// **'本机缓存'**
  String get mockSettingLocalCache;

  /// No description provided for @mockSettingLocalCacheSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'阅读与音频'**
  String get mockSettingLocalCacheSubtitle;

  /// No description provided for @mockSettingModelDeviceGroup.
  ///
  /// In zh, this message translates to:
  /// **'模型与设备'**
  String get mockSettingModelDeviceGroup;

  /// No description provided for @mockSettingModelUsage.
  ///
  /// In zh, this message translates to:
  /// **'模型用量'**
  String get mockSettingModelUsage;

  /// No description provided for @mockSettingModelUsageSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'调用次数与 Token'**
  String get mockSettingModelUsageSubtitle;

  /// No description provided for @mockSettingPersonalModel.
  ///
  /// In zh, this message translates to:
  /// **'个人模型'**
  String get mockSettingPersonalModel;

  /// No description provided for @mockSettingPersonalModelSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'模型与 API Key'**
  String get mockSettingPersonalModelSubtitle;

  /// No description provided for @mockSettingQueryContext.
  ///
  /// In zh, this message translates to:
  /// **'查询与上下文'**
  String get mockSettingQueryContext;

  /// No description provided for @mockSettingQueryContextSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'前后文预算与取文范围'**
  String get mockSettingQueryContextSubtitle;

  /// No description provided for @mockSettingReadingDisplayGroup.
  ///
  /// In zh, this message translates to:
  /// **'阅读与显示'**
  String get mockSettingReadingDisplayGroup;

  /// No description provided for @mockSettingReadingPreferences.
  ///
  /// In zh, this message translates to:
  /// **'阅读偏好'**
  String get mockSettingReadingPreferences;

  /// No description provided for @mockSettingReadingPreferencesSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'字体、字号与阅读主题'**
  String get mockSettingReadingPreferencesSubtitle;

  /// No description provided for @mockSettingReadingPreviewSentence.
  ///
  /// In zh, this message translates to:
  /// **'朝の光が、白いカーテンを通して部屋に広がった。'**
  String get mockSettingReadingPreviewSentence;

  /// No description provided for @mockSettingSecurityAccountSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'会话与退出'**
  String get mockSettingSecurityAccountSubtitle;

  /// No description provided for @mockSettingServiceConnection.
  ///
  /// In zh, this message translates to:
  /// **'服务连接'**
  String get mockSettingServiceConnection;

  /// No description provided for @mockSettingServiceConnectionSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'当前部署与连接状态'**
  String get mockSettingServiceConnectionSubtitle;

  /// No description provided for @mockSettingSimplifiedChinese.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get mockSettingSimplifiedChinese;

  /// No description provided for @mockSettingSpeech.
  ///
  /// In zh, this message translates to:
  /// **'朗读与声音'**
  String get mockSettingSpeech;

  /// No description provided for @mockSettingSpeechSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'声音和播放倍速'**
  String get mockSettingSpeechSubtitle;

  /// No description provided for @mockSettingTextCacheLimit.
  ///
  /// In zh, this message translates to:
  /// **'解释副本上限'**
  String get mockSettingTextCacheLimit;

  /// No description provided for @mockLearningPracticeBookmark.
  ///
  /// In zh, this message translates to:
  /// **'收藏题目'**
  String get mockLearningPracticeBookmark;

  /// No description provided for @mockLearningPracticeBookmarkConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认收藏'**
  String get mockLearningPracticeBookmarkConfirm;

  /// No description provided for @mockLearningPracticeBookmarkHint.
  ///
  /// In zh, this message translates to:
  /// **'保存完整题目和当前可见内容，可选单词本归类。'**
  String get mockLearningPracticeBookmarkHint;

  /// No description provided for @mockLearningPracticeConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认答案'**
  String get mockLearningPracticeConfirm;

  /// No description provided for @mockLearningPracticeCorrect.
  ///
  /// In zh, this message translates to:
  /// **'回答正确'**
  String get mockLearningPracticeCorrect;

  /// No description provided for @mockLearningPracticeExplanation.
  ///
  /// In zh, this message translates to:
  /// **'「は」提示句子的话题。'**
  String get mockLearningPracticeExplanation;

  /// No description provided for @mockLearningPracticeOptionDirection.
  ///
  /// In zh, this message translates to:
  /// **'表示移动方向'**
  String get mockLearningPracticeOptionDirection;

  /// No description provided for @mockLearningPracticeOptionJoin.
  ///
  /// In zh, this message translates to:
  /// **'连接并列句'**
  String get mockLearningPracticeOptionJoin;

  /// No description provided for @mockLearningPracticeOptionPast.
  ///
  /// In zh, this message translates to:
  /// **'表示过去时间'**
  String get mockLearningPracticeOptionPast;

  /// No description provided for @mockLearningPracticeOptionTopic.
  ///
  /// In zh, this message translates to:
  /// **'提示话题'**
  String get mockLearningPracticeOptionTopic;

  /// No description provided for @mockLearningPracticeQuestion.
  ///
  /// In zh, this message translates to:
  /// **'「わたしは学生です」中的「は」有什么作用？'**
  String get mockLearningPracticeQuestion;

  /// No description provided for @mockLearningPracticeRetry.
  ///
  /// In zh, this message translates to:
  /// **'重新作答'**
  String get mockLearningPracticeRetry;

  /// No description provided for @mockLearningPracticeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'Unit 01 · 初次见面'**
  String get mockLearningPracticeSubtitle;

  /// No description provided for @mockLearningPracticeTitle.
  ///
  /// In zh, this message translates to:
  /// **'课后题'**
  String get mockLearningPracticeTitle;

  /// No description provided for @mockLearningPracticeBackToTextbook.
  ///
  /// In zh, this message translates to:
  /// **'课本学习'**
  String get mockLearningPracticeBackToTextbook;

  /// No description provided for @mockLearningPracticeUnit2Explanation.
  ///
  /// In zh, this message translates to:
  /// **'「へ」标示移动的方向。'**
  String get mockLearningPracticeUnit2Explanation;

  /// No description provided for @mockLearningPracticeUnit2OptionDirection.
  ///
  /// In zh, this message translates to:
  /// **'移动方向'**
  String get mockLearningPracticeUnit2OptionDirection;

  /// No description provided for @mockLearningPracticeUnit2OptionObject.
  ///
  /// In zh, this message translates to:
  /// **'动作对象'**
  String get mockLearningPracticeUnit2OptionObject;

  /// No description provided for @mockLearningPracticeUnit2OptionReason.
  ///
  /// In zh, this message translates to:
  /// **'动作原因'**
  String get mockLearningPracticeUnit2OptionReason;

  /// No description provided for @mockLearningPracticeUnit2OptionRelation.
  ///
  /// In zh, this message translates to:
  /// **'所属关系'**
  String get mockLearningPracticeUnit2OptionRelation;

  /// No description provided for @mockLearningPracticeUnit2Question.
  ///
  /// In zh, this message translates to:
  /// **'「駅へ行きます」中的「へ」主要表示什么？'**
  String get mockLearningPracticeUnit2Question;

  /// No description provided for @mockLearningPracticeUnit2Subtitle.
  ///
  /// In zh, this message translates to:
  /// **'Unit 02 · 一起去车站'**
  String get mockLearningPracticeUnit2Subtitle;

  /// No description provided for @mockLearningPracticeUnit3Explanation.
  ///
  /// In zh, this message translates to:
  /// **'「ください」在这里表达礼貌请求。'**
  String get mockLearningPracticeUnit3Explanation;

  /// No description provided for @mockLearningPracticeUnit3OptionFinished.
  ///
  /// In zh, this message translates to:
  /// **'我已吃完'**
  String get mockLearningPracticeUnit3OptionFinished;

  /// No description provided for @mockLearningPracticeUnit3OptionRequest.
  ///
  /// In zh, this message translates to:
  /// **'请给我'**
  String get mockLearningPracticeUnit3OptionRequest;

  /// No description provided for @mockLearningPracticeUnit3OptionWait.
  ///
  /// In zh, this message translates to:
  /// **'请稍等'**
  String get mockLearningPracticeUnit3OptionWait;

  /// No description provided for @mockLearningPracticeUnit3OptionWelcome.
  ///
  /// In zh, this message translates to:
  /// **'欢迎回来'**
  String get mockLearningPracticeUnit3OptionWelcome;

  /// No description provided for @mockLearningPracticeUnit3Question.
  ///
  /// In zh, this message translates to:
  /// **'在咖啡馆点餐时，「ください」通常表达什么？'**
  String get mockLearningPracticeUnit3Question;

  /// No description provided for @mockLearningPracticeUnit3Subtitle.
  ///
  /// In zh, this message translates to:
  /// **'Unit 03 · 在咖啡馆'**
  String get mockLearningPracticeUnit3Subtitle;

  /// No description provided for @mockLearningPracticeWrong.
  ///
  /// In zh, this message translates to:
  /// **'这题选 A'**
  String get mockLearningPracticeWrong;

  /// No description provided for @mockLearningResultAnswerStatus.
  ///
  /// In zh, this message translates to:
  /// **'答卷状态'**
  String get mockLearningResultAnswerStatus;

  /// No description provided for @mockLearningResultAlreadySaved.
  ///
  /// In zh, this message translates to:
  /// **'已收藏此题'**
  String get mockLearningResultAlreadySaved;

  /// No description provided for @mockLearningResultBackToPrep.
  ///
  /// In zh, this message translates to:
  /// **'试卷准备'**
  String get mockLearningResultBackToPrep;

  /// No description provided for @mockLearningResultCorrectCount.
  ///
  /// In zh, this message translates to:
  /// **'答对题数'**
  String get mockLearningResultCorrectCount;

  /// No description provided for @mockLearningResultHeadline.
  ///
  /// In zh, this message translates to:
  /// **'已交卷。'**
  String get mockLearningResultHeadline;

  /// No description provided for @mockLearningResultLanguageCategory.
  ///
  /// In zh, this message translates to:
  /// **'语言知识'**
  String get mockLearningResultLanguageCategory;

  /// No description provided for @mockLearningResultListeningCategory.
  ///
  /// In zh, this message translates to:
  /// **'听力'**
  String get mockLearningResultListeningCategory;

  /// No description provided for @mockLearningResultNeedsReview.
  ///
  /// In zh, this message translates to:
  /// **'需要回看的题目'**
  String get mockLearningResultNeedsReview;

  /// No description provided for @mockLearningResultNotebooksUpdated.
  ///
  /// In zh, this message translates to:
  /// **'已更新词本归类'**
  String get mockLearningResultNotebooksUpdated;

  /// No description provided for @mockLearningResultObjective.
  ///
  /// In zh, this message translates to:
  /// **'客观题'**
  String get mockLearningResultObjective;

  /// No description provided for @mockLearningResultQuestionLabel.
  ///
  /// In zh, this message translates to:
  /// **'第 {number} 题 · {category}'**
  String mockLearningResultQuestionLabel(int number, String category);

  /// No description provided for @mockLearningResultReadingCategory.
  ///
  /// In zh, this message translates to:
  /// **'阅读'**
  String get mockLearningResultReadingCategory;

  /// No description provided for @mockLearningResultReference.
  ///
  /// In zh, this message translates to:
  /// **'参考答案：{answer}'**
  String mockLearningResultReference(String answer);

  /// No description provided for @mockLearningResultReturnLibrary.
  ///
  /// In zh, this message translates to:
  /// **'返回书库'**
  String get mockLearningResultReturnLibrary;

  /// No description provided for @mockLearningResultReview.
  ///
  /// In zh, this message translates to:
  /// **'逐题复盘'**
  String get mockLearningResultReview;

  /// No description provided for @mockLearningResultSaved.
  ///
  /// In zh, this message translates to:
  /// **'已收藏'**
  String get mockLearningResultSaved;

  /// No description provided for @mockLearningResultSelectionAudioUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'音频暂不可用'**
  String get mockLearningResultSelectionAudioUnavailable;

  /// No description provided for @mockLearningResultSelectionAdjust.
  ///
  /// In zh, this message translates to:
  /// **'调整范围'**
  String get mockLearningResultSelectionAdjust;

  /// No description provided for @mockLearningResultSelectionAdjustHelp.
  ///
  /// In zh, this message translates to:
  /// **'可在原文拖选，或在这里调整字词边界。'**
  String get mockLearningResultSelectionAdjustHelp;

  /// No description provided for @mockLearningResultSelectionClose.
  ///
  /// In zh, this message translates to:
  /// **'收起选区工具'**
  String get mockLearningResultSelectionClose;

  /// No description provided for @mockLearningResultSelectionEnd.
  ///
  /// In zh, this message translates to:
  /// **'终点'**
  String get mockLearningResultSelectionEnd;

  /// No description provided for @mockLearningResultSelectionInvalidRange.
  ///
  /// In zh, this message translates to:
  /// **'终点需要在起点之后'**
  String get mockLearningResultSelectionInvalidRange;

  /// No description provided for @mockLearningResultSelectionQuery.
  ///
  /// In zh, this message translates to:
  /// **'查询'**
  String get mockLearningResultSelectionQuery;

  /// No description provided for @mockLearningResultSelectionRead.
  ///
  /// In zh, this message translates to:
  /// **'朗读整句'**
  String get mockLearningResultSelectionRead;

  /// No description provided for @mockLearningResultSelectionStart.
  ///
  /// In zh, this message translates to:
  /// **'起点'**
  String get mockLearningResultSelectionStart;

  /// No description provided for @mockLearningResultSelectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'选句学习'**
  String get mockLearningResultSelectionTitle;

  /// No description provided for @mockLearningResultSelectionTooMany.
  ///
  /// In zh, this message translates to:
  /// **'每次最多查询 3 组，请减少选择'**
  String get mockLearningResultSelectionTooMany;

  /// No description provided for @mockLearningResultSelectionWhole.
  ///
  /// In zh, this message translates to:
  /// **'查询整句'**
  String get mockLearningResultSelectionWhole;

  /// No description provided for @mockLearningResultSubmitted.
  ///
  /// In zh, this message translates to:
  /// **'已交卷'**
  String get mockLearningResultSubmitted;

  /// No description provided for @mockLearningResultSummary.
  ///
  /// In zh, this message translates to:
  /// **'3 道题 · 本次作答结果'**
  String get mockLearningResultSummary;

  /// No description provided for @mockLearningResultTitle.
  ///
  /// In zh, this message translates to:
  /// **'考试结果'**
  String get mockLearningResultTitle;

  /// No description provided for @mockLearningResultUnanswered.
  ///
  /// In zh, this message translates to:
  /// **'未作答'**
  String get mockLearningResultUnanswered;

  /// No description provided for @mockLearningResultViewMistakes.
  ///
  /// In zh, this message translates to:
  /// **'查看错题库'**
  String get mockLearningResultViewMistakes;

  /// No description provided for @mockLearningResultYourChoice.
  ///
  /// In zh, this message translates to:
  /// **'你的选择：{answer}'**
  String mockLearningResultYourChoice(String answer);

  /// No description provided for @mockLearningWordBackToSource.
  ///
  /// In zh, this message translates to:
  /// **'回到原文 →'**
  String get mockLearningWordBackToSource;

  /// No description provided for @mockLearningWordEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑收藏'**
  String get mockLearningWordEditTitle;

  /// No description provided for @mockLearningWordMastery.
  ///
  /// In zh, this message translates to:
  /// **'学习中'**
  String get mockLearningWordMastery;

  /// No description provided for @mockLearningWordNotebookSave.
  ///
  /// In zh, this message translates to:
  /// **'保存归类'**
  String get mockLearningWordNotebookSave;

  /// No description provided for @mockLearningWordSourceDate.
  ///
  /// In zh, this message translates to:
  /// **'{source} · {date} 加入'**
  String mockLearningWordSourceDate(String source, String date);

  /// No description provided for @mockLearningWordTitle.
  ///
  /// In zh, this message translates to:
  /// **'收藏详情'**
  String get mockLearningWordTitle;

  /// No description provided for @mockMaterialPauseContinuousPlayback.
  ///
  /// In zh, this message translates to:
  /// **'暂停连续朗读'**
  String get mockMaterialPauseContinuousPlayback;

  /// No description provided for @mockMaterialContinuousPlayback.
  ///
  /// In zh, this message translates to:
  /// **'连续朗读'**
  String get mockMaterialContinuousPlayback;

  /// No description provided for @mockMaterialNovelSelectionTitle.
  ///
  /// In zh, this message translates to:
  /// **'选句学习'**
  String get mockMaterialNovelSelectionTitle;

  /// No description provided for @mockMaterialNovelSelectionWholeSentence.
  ///
  /// In zh, this message translates to:
  /// **'查询整句'**
  String get mockMaterialNovelSelectionWholeSentence;

  /// No description provided for @mockMaterialNovelReadSentence.
  ///
  /// In zh, this message translates to:
  /// **'朗读整句'**
  String get mockMaterialNovelReadSentence;

  /// No description provided for @mockMaterialNovelAdjustRange.
  ///
  /// In zh, this message translates to:
  /// **'调整范围'**
  String get mockMaterialNovelAdjustRange;

  /// No description provided for @mockMaterialNovelRangeStart.
  ///
  /// In zh, this message translates to:
  /// **'起点'**
  String get mockMaterialNovelRangeStart;

  /// No description provided for @mockMaterialNovelRangeEnd.
  ///
  /// In zh, this message translates to:
  /// **'终点'**
  String get mockMaterialNovelRangeEnd;

  /// No description provided for @mockMaterialNovelBoundaryOption.
  ///
  /// In zh, this message translates to:
  /// **'{position} · {token}'**
  String mockMaterialNovelBoundaryOption(int position, String token);

  /// No description provided for @mockMaterialNovelQueryResultTitle.
  ///
  /// In zh, this message translates to:
  /// **'查询结果'**
  String get mockMaterialNovelQueryResultTitle;

  /// No description provided for @mockMaterialNovelNoQueryResult.
  ///
  /// In zh, this message translates to:
  /// **'暂无查询结果'**
  String get mockMaterialNovelNoQueryResult;

  /// No description provided for @mockMaterialNovelWindowWord.
  ///
  /// In zh, this message translates to:
  /// **'窓'**
  String get mockMaterialNovelWindowWord;

  /// No description provided for @mockMaterialNovelWindowReading.
  ///
  /// In zh, this message translates to:
  /// **'まど'**
  String get mockMaterialNovelWindowReading;

  /// No description provided for @mockMaterialNovelWindowMeaning.
  ///
  /// In zh, this message translates to:
  /// **'窗户'**
  String get mockMaterialNovelWindowMeaning;

  /// No description provided for @mockMaterialContentsTooltip.
  ///
  /// In zh, this message translates to:
  /// **'目录'**
  String get mockMaterialContentsTooltip;

  /// No description provided for @mockMaterialTypographyTooltip.
  ///
  /// In zh, this message translates to:
  /// **'排版'**
  String get mockMaterialTypographyTooltip;

  /// No description provided for @mockMaterialReadingFontSize.
  ///
  /// In zh, this message translates to:
  /// **'阅读字号'**
  String get mockMaterialReadingFontSize;

  /// No description provided for @mockMaterialRemoveBookmark.
  ///
  /// In zh, this message translates to:
  /// **'取消书签'**
  String get mockMaterialRemoveBookmark;

  /// No description provided for @mockMaterialAddBookmark.
  ///
  /// In zh, this message translates to:
  /// **'添加书签'**
  String get mockMaterialAddBookmark;

  /// No description provided for @mockMaterialChapterContents.
  ///
  /// In zh, this message translates to:
  /// **'章节目录'**
  String get mockMaterialChapterContents;

  /// No description provided for @mockMaterialSentenceAnalysisTitle.
  ///
  /// In zh, this message translates to:
  /// **'句子解析'**
  String get mockMaterialSentenceAnalysisTitle;

  /// No description provided for @mockMaterialSentenceTranslationSummerWind.
  ///
  /// In zh, this message translates to:
  /// **'夏风轻轻拂过脸颊。'**
  String get mockMaterialSentenceTranslationSummerWind;

  /// No description provided for @mockMaterialQuerySelection.
  ///
  /// In zh, this message translates to:
  /// **'查询选中内容'**
  String get mockMaterialQuerySelection;

  /// No description provided for @mockMaterialSelectionQueryHint.
  ///
  /// In zh, this message translates to:
  /// **'点选词汇后可查询；完整结果可收藏。'**
  String get mockMaterialSelectionQueryHint;

  /// No description provided for @mockMaterialClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get mockMaterialClose;

  /// No description provided for @mockMaterialQuery.
  ///
  /// In zh, this message translates to:
  /// **'查询'**
  String get mockMaterialQuery;

  /// No description provided for @mockMaterialTextbookUnitFirstMeeting.
  ///
  /// In zh, this message translates to:
  /// **'初次见面'**
  String get mockMaterialTextbookUnitFirstMeeting;

  /// No description provided for @mockMaterialTextbookUnitToStation.
  ///
  /// In zh, this message translates to:
  /// **'一起去车站'**
  String get mockMaterialTextbookUnitToStation;

  /// No description provided for @mockMaterialTextbookUnitAtCafe.
  ///
  /// In zh, this message translates to:
  /// **'在咖啡馆'**
  String get mockMaterialTextbookUnitAtCafe;

  /// No description provided for @mockMaterialTextbookTopicConversation.
  ///
  /// In zh, this message translates to:
  /// **'会话：よろしくお願いします'**
  String get mockMaterialTextbookTopicConversation;

  /// No description provided for @mockMaterialTextbookTopicVocabulary.
  ///
  /// In zh, this message translates to:
  /// **'词汇：姓名与职业'**
  String get mockMaterialTextbookTopicVocabulary;

  /// No description provided for @mockMaterialTextbookTopicGrammar.
  ///
  /// In zh, this message translates to:
  /// **'语法：は 与 です'**
  String get mockMaterialTextbookTopicGrammar;

  /// No description provided for @mockMaterialTextbookTopicExercise.
  ///
  /// In zh, this message translates to:
  /// **'课后练习：3 题'**
  String get mockMaterialTextbookTopicExercise;

  /// No description provided for @mockMaterialTextbookUnitTwoTopicText.
  ///
  /// In zh, this message translates to:
  /// **'课文：駅までの道'**
  String get mockMaterialTextbookUnitTwoTopicText;

  /// No description provided for @mockMaterialTextbookUnitTwoTopicVocabulary.
  ///
  /// In zh, this message translates to:
  /// **'词汇：方向与交通'**
  String get mockMaterialTextbookUnitTwoTopicVocabulary;

  /// No description provided for @mockMaterialTextbookUnitTwoTopicGrammar.
  ///
  /// In zh, this message translates to:
  /// **'语法：に / へ'**
  String get mockMaterialTextbookUnitTwoTopicGrammar;

  /// No description provided for @mockMaterialTextbookUnitTwoTopicExercise.
  ///
  /// In zh, this message translates to:
  /// **'课后练习：4 题'**
  String get mockMaterialTextbookUnitTwoTopicExercise;

  /// No description provided for @mockMaterialTextbookUnitThreeTopicConversation.
  ///
  /// In zh, this message translates to:
  /// **'会话：注文をお願いします'**
  String get mockMaterialTextbookUnitThreeTopicConversation;

  /// No description provided for @mockMaterialTextbookUnitThreeTopicExamples.
  ///
  /// In zh, this message translates to:
  /// **'例句与译文'**
  String get mockMaterialTextbookUnitThreeTopicExamples;

  /// No description provided for @mockMaterialTextbookUnitThreeTopicGrammar.
  ///
  /// In zh, this message translates to:
  /// **'语法：ください'**
  String get mockMaterialTextbookUnitThreeTopicGrammar;

  /// No description provided for @mockMaterialTextbookUnitThreeTopicExercise.
  ///
  /// In zh, this message translates to:
  /// **'课后练习：3 题'**
  String get mockMaterialTextbookUnitThreeTopicExercise;

  /// No description provided for @mockMaterialTextbookConversationSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'会话与课文'**
  String get mockMaterialTextbookConversationSubtitle;

  /// No description provided for @mockMaterialTextbookBackToUnit.
  ///
  /// In zh, this message translates to:
  /// **'回到单元'**
  String get mockMaterialTextbookBackToUnit;

  /// No description provided for @mockMaterialTextbookSource.
  ///
  /// In zh, this message translates to:
  /// **'出处：{unit}'**
  String mockMaterialTextbookSource(String unit);

  /// No description provided for @mockMaterialTextbookVocabularySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'词汇与释义'**
  String get mockMaterialTextbookVocabularySubtitle;

  /// No description provided for @mockMaterialTextbookGrammarSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'用法与例句'**
  String get mockMaterialTextbookGrammarSubtitle;

  /// No description provided for @mockMaterialTextbookExerciseSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'逐题练习'**
  String get mockMaterialTextbookExerciseSubtitle;

  /// No description provided for @mockMaterialTextbookConversationExample.
  ///
  /// In zh, this message translates to:
  /// **'よろしくお願いします。\n请多关照。'**
  String get mockMaterialTextbookConversationExample;

  /// No description provided for @mockMaterialTextbookVocabularyExample.
  ///
  /// In zh, this message translates to:
  /// **'私 · わたし · 我\n先生 · せんせい · 老师'**
  String get mockMaterialTextbookVocabularyExample;

  /// No description provided for @mockMaterialTextbookGrammarExample.
  ///
  /// In zh, this message translates to:
  /// **'「は」标记主题，「です」构成礼貌判断。'**
  String get mockMaterialTextbookGrammarExample;

  /// No description provided for @mockMaterialTextbookExerciseHint.
  ///
  /// In zh, this message translates to:
  /// **'选择答案并提交后查看反馈。'**
  String get mockMaterialTextbookExerciseHint;

  /// No description provided for @mockMaterialTextbookUnitTwoTextExample.
  ///
  /// In zh, this message translates to:
  /// **'駅まで一緒に行きましょう。\n我们一起去车站吧。'**
  String get mockMaterialTextbookUnitTwoTextExample;

  /// No description provided for @mockMaterialTextbookUnitTwoGrammarExample.
  ///
  /// In zh, this message translates to:
  /// **'駅へ行きます。\n「へ」表示移动方向。'**
  String get mockMaterialTextbookUnitTwoGrammarExample;

  /// No description provided for @mockMaterialTextbookUnitTwoMobileGrammar.
  ///
  /// In zh, this message translates to:
  /// **'駅へ行きます。\n「へ」表示移动的方向。'**
  String get mockMaterialTextbookUnitTwoMobileGrammar;

  /// No description provided for @mockMaterialTextbookUnitTwoExampleStation.
  ///
  /// In zh, this message translates to:
  /// **'駅'**
  String get mockMaterialTextbookUnitTwoExampleStation;

  /// No description provided for @mockMaterialTextbookUnitTwoExampleStationMeaning.
  ///
  /// In zh, this message translates to:
  /// **'车站'**
  String get mockMaterialTextbookUnitTwoExampleStationMeaning;

  /// No description provided for @mockMaterialTextbookUnitTwoExampleRight.
  ///
  /// In zh, this message translates to:
  /// **'右'**
  String get mockMaterialTextbookUnitTwoExampleRight;

  /// No description provided for @mockMaterialTextbookUnitTwoExampleRightMeaning.
  ///
  /// In zh, this message translates to:
  /// **'右'**
  String get mockMaterialTextbookUnitTwoExampleRightMeaning;

  /// No description provided for @mockMaterialTextbookUnitTwoExampleLeft.
  ///
  /// In zh, this message translates to:
  /// **'左'**
  String get mockMaterialTextbookUnitTwoExampleLeft;

  /// No description provided for @mockMaterialTextbookUnitTwoExampleLeftMeaning.
  ///
  /// In zh, this message translates to:
  /// **'左'**
  String get mockMaterialTextbookUnitTwoExampleLeftMeaning;

  /// No description provided for @mockMaterialTextbookUnitThreeMobileConversation.
  ///
  /// In zh, this message translates to:
  /// **'コーヒーを一つください。\n请给我一杯咖啡。'**
  String get mockMaterialTextbookUnitThreeMobileConversation;

  /// No description provided for @mockMaterialTextbookUnitThreeDesktopConversation.
  ///
  /// In zh, this message translates to:
  /// **'コーヒーをください。\n请给我一杯咖啡。'**
  String get mockMaterialTextbookUnitThreeDesktopConversation;

  /// No description provided for @mockMaterialTextbookUnitThreeMobileGrammar.
  ///
  /// In zh, this message translates to:
  /// **'コーヒーをください。\n「ください」表达礼貌请求。'**
  String get mockMaterialTextbookUnitThreeMobileGrammar;

  /// No description provided for @mockMaterialTextbookUnitThreeDesktopGrammar.
  ///
  /// In zh, this message translates to:
  /// **'ケーキをください。\n「ください」表达礼貌请求。'**
  String get mockMaterialTextbookUnitThreeDesktopGrammar;

  /// No description provided for @mockMaterialTextbookUnitThreeExampleOrder.
  ///
  /// In zh, this message translates to:
  /// **'注文'**
  String get mockMaterialTextbookUnitThreeExampleOrder;

  /// No description provided for @mockMaterialTextbookUnitThreeExampleOrderMeaning.
  ///
  /// In zh, this message translates to:
  /// **'点单'**
  String get mockMaterialTextbookUnitThreeExampleOrderMeaning;

  /// No description provided for @mockMaterialTextbookUnitThreeExampleWater.
  ///
  /// In zh, this message translates to:
  /// **'水'**
  String get mockMaterialTextbookUnitThreeExampleWater;

  /// No description provided for @mockMaterialTextbookUnitThreeExampleWaterMeaning.
  ///
  /// In zh, this message translates to:
  /// **'水'**
  String get mockMaterialTextbookUnitThreeExampleWaterMeaning;

  /// No description provided for @mockMaterialTextbookUnitThreeExampleCoffee.
  ///
  /// In zh, this message translates to:
  /// **'コーヒー'**
  String get mockMaterialTextbookUnitThreeExampleCoffee;

  /// No description provided for @mockMaterialTextbookUnitThreeExampleCoffeeMeaning.
  ///
  /// In zh, this message translates to:
  /// **'咖啡'**
  String get mockMaterialTextbookUnitThreeExampleCoffeeMeaning;

  /// No description provided for @mockMaterialTextbookReadWord.
  ///
  /// In zh, this message translates to:
  /// **'朗读{word}'**
  String mockMaterialTextbookReadWord(String word);

  /// No description provided for @mockMaterialTextbookPlaybackTitle.
  ///
  /// In zh, this message translates to:
  /// **'朗读'**
  String get mockMaterialTextbookPlaybackTitle;

  /// No description provided for @mockMaterialTextbookPlaybackPlaying.
  ///
  /// In zh, this message translates to:
  /// **'播放中'**
  String get mockMaterialTextbookPlaybackPlaying;

  /// No description provided for @mockMaterialTextbookPlaybackPaused.
  ///
  /// In zh, this message translates to:
  /// **'已暂停'**
  String get mockMaterialTextbookPlaybackPaused;

  /// No description provided for @mockMaterialTextbookPlaybackFinished.
  ///
  /// In zh, this message translates to:
  /// **'播放完成'**
  String get mockMaterialTextbookPlaybackFinished;

  /// No description provided for @mockMaterialTextbookPlaybackOnce.
  ///
  /// In zh, this message translates to:
  /// **'单次朗读'**
  String get mockMaterialTextbookPlaybackOnce;

  /// No description provided for @mockMaterialTextbookPlaybackPause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get mockMaterialTextbookPlaybackPause;

  /// No description provided for @mockMaterialTextbookPlaybackResume.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get mockMaterialTextbookPlaybackResume;

  /// No description provided for @mockMaterialTextbookPlaybackReplay.
  ///
  /// In zh, this message translates to:
  /// **'重新播放'**
  String get mockMaterialTextbookPlaybackReplay;

  /// No description provided for @mockMaterialTextbookPlaybackSpeed.
  ///
  /// In zh, this message translates to:
  /// **'语速'**
  String get mockMaterialTextbookPlaybackSpeed;

  /// No description provided for @mockMaterialTextbookPlaybackStop.
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get mockMaterialTextbookPlaybackStop;

  /// No description provided for @mockMaterialStartExercise.
  ///
  /// In zh, this message translates to:
  /// **'开始练习'**
  String get mockMaterialStartExercise;

  /// No description provided for @mockMaterialTextbookJapaneseLabel.
  ///
  /// In zh, this message translates to:
  /// **'课本 · 日语'**
  String get mockMaterialTextbookJapaneseLabel;

  /// No description provided for @mockMaterialUnitContents.
  ///
  /// In zh, this message translates to:
  /// **'单元目录'**
  String get mockMaterialUnitContents;

  /// No description provided for @mockMaterialTextbookAvailableUnitCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个可用单元'**
  String mockMaterialTextbookAvailableUnitCount(int count);

  /// No description provided for @mockMaterialTextbookUnitSections.
  ///
  /// In zh, this message translates to:
  /// **'课文 · 词汇 · 语法 · 练习'**
  String get mockMaterialTextbookUnitSections;

  /// No description provided for @mockMaterialUnitContentTitle.
  ///
  /// In zh, this message translates to:
  /// **'单元内容'**
  String get mockMaterialUnitContentTitle;

  /// No description provided for @mockMaterialOpenContentHint.
  ///
  /// In zh, this message translates to:
  /// **'点击查看内容'**
  String get mockMaterialOpenContentHint;

  /// No description provided for @mockMaterialDoUnitExercises.
  ///
  /// In zh, this message translates to:
  /// **'做课后题'**
  String get mockMaterialDoUnitExercises;

  /// No description provided for @mockMaterialTextbookTitle.
  ///
  /// In zh, this message translates to:
  /// **'课本'**
  String get mockMaterialTextbookTitle;

  /// No description provided for @mockMaterialConfirmCandidateMatch.
  ///
  /// In zh, this message translates to:
  /// **'确认候选匹配'**
  String get mockMaterialConfirmCandidateMatch;

  /// No description provided for @mockMaterialQuestionNumbersAndScores.
  ///
  /// In zh, this message translates to:
  /// **'题号与分值'**
  String get mockMaterialQuestionNumbersAndScores;

  /// No description provided for @mockMaterialExtractedNeedsReview.
  ///
  /// In zh, this message translates to:
  /// **'已提取 · 待校对'**
  String get mockMaterialExtractedNeedsReview;

  /// No description provided for @mockMaterialListeningTranscript.
  ///
  /// In zh, this message translates to:
  /// **'听力文字稿'**
  String get mockMaterialListeningTranscript;

  /// No description provided for @mockMaterialScriptMatched.
  ///
  /// In zh, this message translates to:
  /// **'已确认脚本与题组'**
  String get mockMaterialScriptMatched;

  /// No description provided for @mockMaterialScriptMatchPending.
  ///
  /// In zh, this message translates to:
  /// **'待确认脚本与题组'**
  String get mockMaterialScriptMatchPending;

  /// No description provided for @mockMaterialPrivateSpeechAudio.
  ///
  /// In zh, this message translates to:
  /// **'朗读音频'**
  String get mockMaterialPrivateSpeechAudio;

  /// No description provided for @mockMaterialAudioGenerated.
  ///
  /// In zh, this message translates to:
  /// **'已生成'**
  String get mockMaterialAudioGenerated;

  /// No description provided for @mockMaterialAudioPending.
  ///
  /// In zh, this message translates to:
  /// **'待生成'**
  String get mockMaterialAudioPending;

  /// No description provided for @mockMaterialWaitingForScriptConfirmation.
  ///
  /// In zh, this message translates to:
  /// **'等待脚本确认'**
  String get mockMaterialWaitingForScriptConfirmation;

  /// No description provided for @mockMaterialPreparationChecklist.
  ///
  /// In zh, this message translates to:
  /// **'准备清单'**
  String get mockMaterialPreparationChecklist;

  /// No description provided for @mockMaterialListeningPreparationRequired.
  ///
  /// In zh, this message translates to:
  /// **'听力准备完成后即可开考。'**
  String get mockMaterialListeningPreparationRequired;

  /// No description provided for @mockMaterialOriginalQuestionCount.
  ///
  /// In zh, this message translates to:
  /// **'原卷题量'**
  String get mockMaterialOriginalQuestionCount;

  /// No description provided for @mockMaterialMinutesLabel.
  ///
  /// In zh, this message translates to:
  /// **'分钟'**
  String get mockMaterialMinutesLabel;

  /// No description provided for @mockMaterialGenerateListeningAudioMock.
  ///
  /// In zh, this message translates to:
  /// **'生成听力音频'**
  String get mockMaterialGenerateListeningAudioMock;

  /// No description provided for @mockMaterialConfirmVersionAndStart.
  ///
  /// In zh, this message translates to:
  /// **'确认版本并开考'**
  String get mockMaterialConfirmVersionAndStart;

  /// No description provided for @mockMaterialIncludedSampleQuestions.
  ///
  /// In zh, this message translates to:
  /// **'题目'**
  String get mockMaterialIncludedSampleQuestions;

  /// No description provided for @mockMaterialSampleTimeLimit.
  ///
  /// In zh, this message translates to:
  /// **'分钟 · 答题时限'**
  String get mockMaterialSampleTimeLimit;

  /// No description provided for @mockMaterialNeedsReviewStatus.
  ///
  /// In zh, this message translates to:
  /// **'待校对'**
  String get mockMaterialNeedsReviewStatus;

  /// No description provided for @mockMaterialExamStatus.
  ///
  /// In zh, this message translates to:
  /// **'试卷状态'**
  String get mockMaterialExamStatus;

  /// No description provided for @mockMaterialReviewListeningCandidate.
  ///
  /// In zh, this message translates to:
  /// **'校对听力候选'**
  String get mockMaterialReviewListeningCandidate;

  /// No description provided for @mockMaterialExamScriptReviewNotice.
  ///
  /// In zh, this message translates to:
  /// **'请核对脚本内容与题组、小题关系，确认后可生成听力音频。'**
  String get mockMaterialExamScriptReviewNotice;

  /// No description provided for @mockMaterialExamScriptCandidateTitle.
  ///
  /// In zh, this message translates to:
  /// **'候选文字稿 · 题组 1'**
  String get mockMaterialExamScriptCandidateTitle;

  /// No description provided for @mockMaterialExamScriptCandidateText.
  ///
  /// In zh, this message translates to:
  /// **'駅の南口で待ち合わせましょう。午後三時に会いましょう。'**
  String get mockMaterialExamScriptCandidateText;

  /// No description provided for @mockMaterialExamScriptCandidateLink.
  ///
  /// In zh, this message translates to:
  /// **'候选关联：听力题组 1 / 小题 01'**
  String get mockMaterialExamScriptCandidateLink;

  /// No description provided for @mockMaterialExamScriptVerified.
  ///
  /// In zh, this message translates to:
  /// **'我已核对脚本与题目对应关系'**
  String get mockMaterialExamScriptVerified;

  /// No description provided for @mockMaterialExamScriptCandidateLinkForItem.
  ///
  /// In zh, this message translates to:
  /// **'候选关联：听力题组 1 / 小题 {number}'**
  String mockMaterialExamScriptCandidateLinkForItem(String number);

  /// No description provided for @mockMaterialExamDesktopCandidateGroup.
  ///
  /// In zh, this message translates to:
  /// **'题组：听力 · 第 {number} 题'**
  String mockMaterialExamDesktopCandidateGroup(String number);

  /// No description provided for @mockMaterialExamDesktopCandidateTitle.
  ///
  /// In zh, this message translates to:
  /// **'文字稿候选'**
  String get mockMaterialExamDesktopCandidateTitle;

  /// No description provided for @mockMaterialExamDesktopCandidateText.
  ///
  /// In zh, this message translates to:
  /// **'明日は駅の南口で会いましょう。'**
  String get mockMaterialExamDesktopCandidateText;

  /// No description provided for @mockMaterialExamDesktopCandidateSource.
  ///
  /// In zh, this message translates to:
  /// **'来源：试卷正文 · 听力题组 1。'**
  String get mockMaterialExamDesktopCandidateSource;

  /// No description provided for @mockMaterialExamDesktopScriptVerified.
  ///
  /// In zh, this message translates to:
  /// **'我已核对脚本与题组、小题的对应关系'**
  String get mockMaterialExamDesktopScriptVerified;

  /// No description provided for @mockMaterialExamDesktopConfirmMatch.
  ///
  /// In zh, this message translates to:
  /// **'确认匹配'**
  String get mockMaterialExamDesktopConfirmMatch;

  /// No description provided for @mockMaterialExamChangeBinding.
  ///
  /// In zh, this message translates to:
  /// **'调整关联'**
  String get mockMaterialExamChangeBinding;

  /// No description provided for @mockMaterialExamRejectCandidate.
  ///
  /// In zh, this message translates to:
  /// **'拒绝候选'**
  String get mockMaterialExamRejectCandidate;

  /// No description provided for @mockMaterialExamBoundQuestion.
  ///
  /// In zh, this message translates to:
  /// **'关联小题'**
  String get mockMaterialExamBoundQuestion;

  /// No description provided for @mockMaterialExamBoundQuestionOption.
  ///
  /// In zh, this message translates to:
  /// **'小题 {number}'**
  String mockMaterialExamBoundQuestionOption(String number);

  /// No description provided for @mockMaterialExamReviewQuestions.
  ///
  /// In zh, this message translates to:
  /// **'校对题号与分值'**
  String get mockMaterialExamReviewQuestions;

  /// No description provided for @mockMaterialExamQuestionEntry.
  ///
  /// In zh, this message translates to:
  /// **'第 {number} 题'**
  String mockMaterialExamQuestionEntry(int number);

  /// No description provided for @mockMaterialExamQuestionNumber.
  ///
  /// In zh, this message translates to:
  /// **'题号'**
  String get mockMaterialExamQuestionNumber;

  /// No description provided for @mockMaterialExamQuestionGroup.
  ///
  /// In zh, this message translates to:
  /// **'题组'**
  String get mockMaterialExamQuestionGroup;

  /// No description provided for @mockMaterialExamQuestionScore.
  ///
  /// In zh, this message translates to:
  /// **'分值'**
  String get mockMaterialExamQuestionScore;

  /// No description provided for @mockMaterialExamGroupLanguage.
  ///
  /// In zh, this message translates to:
  /// **'语言知识'**
  String get mockMaterialExamGroupLanguage;

  /// No description provided for @mockMaterialExamGroupReading.
  ///
  /// In zh, this message translates to:
  /// **'阅读'**
  String get mockMaterialExamGroupReading;

  /// No description provided for @mockMaterialExamGroupListening.
  ///
  /// In zh, this message translates to:
  /// **'听力'**
  String get mockMaterialExamGroupListening;

  /// No description provided for @mockMaterialExamQuestionNumberInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入大于 0 的题号'**
  String get mockMaterialExamQuestionNumberInvalid;

  /// No description provided for @mockMaterialExamQuestionNumberDuplicate.
  ///
  /// In zh, this message translates to:
  /// **'题号不能重复'**
  String get mockMaterialExamQuestionNumberDuplicate;

  /// No description provided for @mockMaterialExamQuestionScoreInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入大于 0 的分值'**
  String get mockMaterialExamQuestionScoreInvalid;

  /// No description provided for @mockMaterialExamListeningGroupRequired.
  ///
  /// In zh, this message translates to:
  /// **'至少需要一道听力题'**
  String get mockMaterialExamListeningGroupRequired;

  /// No description provided for @mockMaterialExamReviewCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get mockMaterialExamReviewCancel;

  /// No description provided for @mockMaterialExamReviewConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认校对'**
  String get mockMaterialExamReviewConfirm;

  /// No description provided for @mockMaterialExamQuestionsReviewed.
  ///
  /// In zh, this message translates to:
  /// **'已校对'**
  String get mockMaterialExamQuestionsReviewed;

  /// No description provided for @mockMaterialExamCandidateRejected.
  ///
  /// In zh, this message translates to:
  /// **'候选已拒绝'**
  String get mockMaterialExamCandidateRejected;

  /// No description provided for @mockMaterialExamDesktopQuestionStep.
  ///
  /// In zh, this message translates to:
  /// **'题号、题组与分值'**
  String get mockMaterialExamDesktopQuestionStep;

  /// No description provided for @mockMaterialExamDesktopNeedsQuestionReview.
  ///
  /// In zh, this message translates to:
  /// **'待人工校对'**
  String get mockMaterialExamDesktopNeedsQuestionReview;

  /// No description provided for @mockMaterialExamDesktopScriptStep.
  ///
  /// In zh, this message translates to:
  /// **'听力脚本与题组候选'**
  String get mockMaterialExamDesktopScriptStep;

  /// No description provided for @mockMaterialExamDesktopConfirmed.
  ///
  /// In zh, this message translates to:
  /// **'已确认'**
  String get mockMaterialExamDesktopConfirmed;

  /// No description provided for @mockMaterialExamDesktopAudioStep.
  ///
  /// In zh, this message translates to:
  /// **'听力音频'**
  String get mockMaterialExamDesktopAudioStep;

  /// No description provided for @mockMaterialExamDesktopAudioMissing.
  ///
  /// In zh, this message translates to:
  /// **'未生成'**
  String get mockMaterialExamDesktopAudioMissing;

  /// No description provided for @mockMaterialExamDesktopAudioReady.
  ///
  /// In zh, this message translates to:
  /// **'已就绪'**
  String get mockMaterialExamDesktopAudioReady;

  /// No description provided for @mockMaterialExamContinueSession.
  ///
  /// In zh, this message translates to:
  /// **'继续作答'**
  String get mockMaterialExamContinueSession;

  /// No description provided for @mockMaterialGenerateAudioMock.
  ///
  /// In zh, this message translates to:
  /// **'生成音频'**
  String get mockMaterialGenerateAudioMock;

  /// No description provided for @mockMaterialConfirmAndFreezeVersion.
  ///
  /// In zh, this message translates to:
  /// **'确认并冻结版本'**
  String get mockMaterialConfirmAndFreezeVersion;

  /// No description provided for @mockMaterialSampleExamAnswerHint.
  ///
  /// In zh, this message translates to:
  /// **'交卷后查看答案。'**
  String get mockMaterialSampleExamAnswerHint;

  /// No description provided for @mockSettingInterfaceLanguage.
  ///
  /// In zh, this message translates to:
  /// **'界面语言'**
  String get mockSettingInterfaceLanguage;

  /// No description provided for @mockSettingNativeLanguages.
  ///
  /// In zh, this message translates to:
  /// **'母语（可多选）'**
  String get mockSettingNativeLanguages;

  /// No description provided for @mockSettingTargetLanguages.
  ///
  /// In zh, this message translates to:
  /// **'学习语言（可多选）'**
  String get mockSettingTargetLanguages;

  /// No description provided for @mockSettingLearningLevel.
  ///
  /// In zh, this message translates to:
  /// **'自评水平'**
  String get mockSettingLearningLevel;

  /// No description provided for @mockSettingLevelUnset.
  ///
  /// In zh, this message translates to:
  /// **'未填写'**
  String get mockSettingLevelUnset;

  /// No description provided for @mockSettingLevelBeginner.
  ///
  /// In zh, this message translates to:
  /// **'初学'**
  String get mockSettingLevelBeginner;

  /// No description provided for @mockSettingLevelBasic.
  ///
  /// In zh, this message translates to:
  /// **'初级'**
  String get mockSettingLevelBasic;

  /// No description provided for @mockSettingLevelIntermediate.
  ///
  /// In zh, this message translates to:
  /// **'中级'**
  String get mockSettingLevelIntermediate;

  /// No description provided for @mockSettingLevelAdvanced.
  ///
  /// In zh, this message translates to:
  /// **'进阶'**
  String get mockSettingLevelAdvanced;

  /// No description provided for @mockSettingLearningGoals.
  ///
  /// In zh, this message translates to:
  /// **'学习目标'**
  String get mockSettingLearningGoals;

  /// No description provided for @mockSettingGoalReading.
  ///
  /// In zh, this message translates to:
  /// **'阅读'**
  String get mockSettingGoalReading;

  /// No description provided for @mockSettingGoalTextbook.
  ///
  /// In zh, this message translates to:
  /// **'教材'**
  String get mockSettingGoalTextbook;

  /// No description provided for @mockSettingGoalExam.
  ///
  /// In zh, this message translates to:
  /// **'考试'**
  String get mockSettingGoalExam;

  /// No description provided for @mockSettingGoalListening.
  ///
  /// In zh, this message translates to:
  /// **'听力'**
  String get mockSettingGoalListening;

  /// No description provided for @mockSettingGoalSpeaking.
  ///
  /// In zh, this message translates to:
  /// **'口语'**
  String get mockSettingGoalSpeaking;

  /// No description provided for @mockSettingGoalWriting.
  ///
  /// In zh, this message translates to:
  /// **'写作'**
  String get mockSettingGoalWriting;

  /// No description provided for @mockSettingGoalVocabulary.
  ///
  /// In zh, this message translates to:
  /// **'词汇'**
  String get mockSettingGoalVocabulary;

  /// No description provided for @mockSettingGoalGrammar.
  ///
  /// In zh, this message translates to:
  /// **'语法'**
  String get mockSettingGoalGrammar;

  /// No description provided for @mockSettingSaveGoals.
  ///
  /// In zh, this message translates to:
  /// **'保存学习目标'**
  String get mockSettingSaveGoals;

  /// No description provided for @mockSettingReadingFont.
  ///
  /// In zh, this message translates to:
  /// **'阅读字体'**
  String get mockSettingReadingFont;

  /// No description provided for @mockSettingSerifFont.
  ///
  /// In zh, this message translates to:
  /// **'衬线字体'**
  String get mockSettingSerifFont;

  /// No description provided for @mockSettingSansFont.
  ///
  /// In zh, this message translates to:
  /// **'无衬线字体'**
  String get mockSettingSansFont;

  /// No description provided for @mockSettingLineHeight.
  ///
  /// In zh, this message translates to:
  /// **'行高'**
  String get mockSettingLineHeight;

  /// No description provided for @mockSettingReadingTheme.
  ///
  /// In zh, this message translates to:
  /// **'阅读主题'**
  String get mockSettingReadingTheme;

  /// No description provided for @mockSettingSepiaTheme.
  ///
  /// In zh, this message translates to:
  /// **'暖纸色'**
  String get mockSettingSepiaTheme;

  /// No description provided for @mockSettingReadingPreview.
  ///
  /// In zh, this message translates to:
  /// **'阅读预览'**
  String get mockSettingReadingPreview;

  /// No description provided for @settingMotionHint.
  ///
  /// In zh, this message translates to:
  /// **'降低位移与弹跳'**
  String get settingMotionHint;

  /// No description provided for @settingAppearancePreviewTitle.
  ///
  /// In zh, this message translates to:
  /// **'一页故事，一点新发现。'**
  String get settingAppearancePreviewTitle;

  /// No description provided for @settingAppearancePreviewBody.
  ///
  /// In zh, this message translates to:
  /// **'阅读、解释和作答会沿用同一套色彩与文字层级。'**
  String get settingAppearancePreviewBody;

  /// No description provided for @mockSettingSaveReading.
  ///
  /// In zh, this message translates to:
  /// **'保存阅读偏好'**
  String get mockSettingSaveReading;

  /// No description provided for @mockSettingContextRange.
  ///
  /// In zh, this message translates to:
  /// **'取文范围'**
  String get mockSettingContextRange;

  /// No description provided for @settingContextIntro.
  ///
  /// In zh, this message translates to:
  /// **'查询会携带当前句和前后文，帮助理解词义与指代。'**
  String get settingContextIntro;

  /// No description provided for @settingContextBudgetHint.
  ///
  /// In zh, this message translates to:
  /// **'支持 1,000–64,000 tokens。Token 是模型计算文字的单位，当前完整句另计；内容不足时不会凑满。'**
  String get settingContextBudgetHint;

  /// No description provided for @settingContextBudgetSummary.
  ///
  /// In zh, this message translates to:
  /// **'最多 {budget} tokens 前后文'**
  String settingContextBudgetSummary(String budget);

  /// No description provided for @settingContextAvailability.
  ///
  /// In zh, this message translates to:
  /// **'保存的偏好会在查询功能开放后使用，已有结果不会改变。'**
  String get settingContextAvailability;

  /// No description provided for @mockSettingSaveQuery.
  ///
  /// In zh, this message translates to:
  /// **'保存查询偏好'**
  String get mockSettingSaveQuery;

  /// No description provided for @mockSettingBudgetInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入 1000 至 64000 之间的数值'**
  String get mockSettingBudgetInvalid;

  /// No description provided for @mockSettingProvider.
  ///
  /// In zh, this message translates to:
  /// **'供应商'**
  String get mockSettingProvider;

  /// No description provided for @mockSettingOpenRouter.
  ///
  /// In zh, this message translates to:
  /// **'OpenRouter'**
  String get mockSettingOpenRouter;

  /// No description provided for @mockSettingGemini.
  ///
  /// In zh, this message translates to:
  /// **'Gemini'**
  String get mockSettingGemini;

  /// No description provided for @mockSettingTextCapability.
  ///
  /// In zh, this message translates to:
  /// **'文本'**
  String get mockSettingTextCapability;

  /// No description provided for @mockSettingVisionCapability.
  ///
  /// In zh, this message translates to:
  /// **'视觉'**
  String get mockSettingVisionCapability;

  /// No description provided for @mockSettingSpeechCapability.
  ///
  /// In zh, this message translates to:
  /// **'朗读'**
  String get mockSettingSpeechCapability;

  /// No description provided for @mockSettingDefaultModel.
  ///
  /// In zh, this message translates to:
  /// **'默认模型'**
  String get mockSettingDefaultModel;

  /// No description provided for @mockSettingSaveModel.
  ///
  /// In zh, this message translates to:
  /// **'保存模型偏好'**
  String get mockSettingSaveModel;

  /// No description provided for @mockSettingConfigureKey.
  ///
  /// In zh, this message translates to:
  /// **'配置 API Key'**
  String get mockSettingConfigureKey;

  /// No description provided for @mockSettingRemoveKey.
  ///
  /// In zh, this message translates to:
  /// **'移除 API Key'**
  String get mockSettingRemoveKey;

  /// No description provided for @mockSettingKeyConfigured.
  ///
  /// In zh, this message translates to:
  /// **'已配置'**
  String get mockSettingKeyConfigured;

  /// No description provided for @mockSettingKeyUnconfigured.
  ///
  /// In zh, this message translates to:
  /// **'未配置'**
  String get mockSettingKeyUnconfigured;

  /// No description provided for @mockSettingKeyRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入 API Key'**
  String get mockSettingKeyRequired;

  /// No description provided for @mockSettingSaveKey.
  ///
  /// In zh, this message translates to:
  /// **'保存 API Key'**
  String get mockSettingSaveKey;

  /// No description provided for @mockSettingTestTextModel.
  ///
  /// In zh, this message translates to:
  /// **'测试文本模型'**
  String get mockSettingTestTextModel;

  /// No description provided for @mockSettingModelConfigChecked.
  ///
  /// In zh, this message translates to:
  /// **'模型配置已检查'**
  String get mockSettingModelConfigChecked;

  /// No description provided for @mockSettingSpeechModel.
  ///
  /// In zh, this message translates to:
  /// **'朗读模型'**
  String get mockSettingSpeechModel;

  /// No description provided for @mockSettingGeminiNatural.
  ///
  /// In zh, this message translates to:
  /// **'Gemini 自然语音'**
  String get mockSettingGeminiNatural;

  /// No description provided for @mockSettingOpenRouterDedicated.
  ///
  /// In zh, this message translates to:
  /// **'OpenRouter 专用朗读'**
  String get mockSettingOpenRouterDedicated;

  /// No description provided for @mockSettingOpenRouterAudio.
  ///
  /// In zh, this message translates to:
  /// **'OpenRouter 音频模型'**
  String get mockSettingOpenRouterAudio;

  /// No description provided for @mockSettingDefaultVoice.
  ///
  /// In zh, this message translates to:
  /// **'默认声音'**
  String get mockSettingDefaultVoice;

  /// No description provided for @mockSettingJapaneseClear.
  ///
  /// In zh, this message translates to:
  /// **'日语清晰'**
  String get mockSettingJapaneseClear;

  /// No description provided for @mockSettingEnglishNatural.
  ///
  /// In zh, this message translates to:
  /// **'英语自然'**
  String get mockSettingEnglishNatural;

  /// No description provided for @mockSettingAudioFormat.
  ///
  /// In zh, this message translates to:
  /// **'音频格式'**
  String get mockSettingAudioFormat;

  /// No description provided for @mockSettingVoiceStyle.
  ///
  /// In zh, this message translates to:
  /// **'声音风格'**
  String get mockSettingVoiceStyle;

  /// No description provided for @mockSettingNaturalStyle.
  ///
  /// In zh, this message translates to:
  /// **'自然'**
  String get mockSettingNaturalStyle;

  /// No description provided for @mockSettingSoftStyle.
  ///
  /// In zh, this message translates to:
  /// **'柔和'**
  String get mockSettingSoftStyle;

  /// No description provided for @mockSettingSaveSpeech.
  ///
  /// In zh, this message translates to:
  /// **'保存朗读偏好'**
  String get mockSettingSaveSpeech;

  /// No description provided for @mockSettingCallCount.
  ///
  /// In zh, this message translates to:
  /// **'调用次数'**
  String get mockSettingCallCount;

  /// No description provided for @mockSettingReuseCount.
  ///
  /// In zh, this message translates to:
  /// **'结果复用'**
  String get mockSettingReuseCount;

  /// No description provided for @mockSettingUnknownUsage.
  ///
  /// In zh, this message translates to:
  /// **'用量未提供'**
  String get mockSettingUnknownUsage;

  /// No description provided for @mockSettingInputTokens.
  ///
  /// In zh, this message translates to:
  /// **'输入 Token'**
  String get mockSettingInputTokens;

  /// No description provided for @mockSettingOutputTokens.
  ///
  /// In zh, this message translates to:
  /// **'输出 Token'**
  String get mockSettingOutputTokens;

  /// No description provided for @mockSettingCacheReadTokens.
  ///
  /// In zh, this message translates to:
  /// **'缓存读取'**
  String get mockSettingCacheReadTokens;

  /// No description provided for @mockSettingServiceAddress.
  ///
  /// In zh, this message translates to:
  /// **'服务地址'**
  String get mockSettingServiceAddress;

  /// No description provided for @mockSettingProbeConnection.
  ///
  /// In zh, this message translates to:
  /// **'检查连接'**
  String get mockSettingProbeConnection;

  /// No description provided for @mockSettingAddressValid.
  ///
  /// In zh, this message translates to:
  /// **'地址格式有效'**
  String get mockSettingAddressValid;

  /// No description provided for @mockSettingAddressInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请输入有效的 HTTPS 地址'**
  String get mockSettingAddressInvalid;

  /// No description provided for @mockSettingCurrentSession.
  ///
  /// In zh, this message translates to:
  /// **'当前设备会话'**
  String get mockSettingCurrentSession;

  /// No description provided for @mockSettingChangePassword.
  ///
  /// In zh, this message translates to:
  /// **'修改密码'**
  String get mockSettingChangePassword;

  /// No description provided for @mockSettingCurrentPassword.
  ///
  /// In zh, this message translates to:
  /// **'当前密码'**
  String get mockSettingCurrentPassword;

  /// No description provided for @mockSettingNewPassword.
  ///
  /// In zh, this message translates to:
  /// **'新密码'**
  String get mockSettingNewPassword;

  /// No description provided for @mockSettingConfirmPassword.
  ///
  /// In zh, this message translates to:
  /// **'确认新密码'**
  String get mockSettingConfirmPassword;

  /// No description provided for @mockSettingPasswordMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入的密码不一致'**
  String get mockSettingPasswordMismatch;

  /// No description provided for @mockSettingPasswordRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写全部密码字段'**
  String get mockSettingPasswordRequired;

  /// No description provided for @mockSettingPasswordTooShort.
  ///
  /// In zh, this message translates to:
  /// **'新密码至少需要 8 个字符'**
  String get mockSettingPasswordTooShort;

  /// No description provided for @mockSettingPasswordUpdated.
  ///
  /// In zh, this message translates to:
  /// **'密码已更新'**
  String get mockSettingPasswordUpdated;

  /// No description provided for @mockSettingLogout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get mockSettingLogout;

  /// No description provided for @mockSettingAudioWav.
  ///
  /// In zh, this message translates to:
  /// **'WAV'**
  String get mockSettingAudioWav;

  /// No description provided for @mockSettingSessionActive.
  ///
  /// In zh, this message translates to:
  /// **'本机 · 已登录'**
  String get mockSettingSessionActive;

  /// No description provided for @mockSettingClose.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get mockSettingClose;

  /// No description provided for @adminRoleCreate.
  ///
  /// In zh, this message translates to:
  /// **'创建角色'**
  String get adminRoleCreate;

  /// No description provided for @adminRoleCode.
  ///
  /// In zh, this message translates to:
  /// **'代码'**
  String get adminRoleCode;

  /// No description provided for @adminRoleName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get adminRoleName;

  /// No description provided for @adminRoleDescription.
  ///
  /// In zh, this message translates to:
  /// **'描述'**
  String get adminRoleDescription;

  /// No description provided for @adminRoleEnabled.
  ///
  /// In zh, this message translates to:
  /// **'启用'**
  String get adminRoleEnabled;

  /// No description provided for @adminRoleDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已停用'**
  String get adminRoleDisabled;

  /// No description provided for @adminRoleSaveMetadata.
  ///
  /// In zh, this message translates to:
  /// **'保存名称'**
  String get adminRoleSaveMetadata;

  /// No description provided for @adminRoleSaveGrants.
  ///
  /// In zh, this message translates to:
  /// **'保存授权'**
  String get adminRoleSaveGrants;

  /// No description provided for @adminRoleSaveParents.
  ///
  /// In zh, this message translates to:
  /// **'保存继承'**
  String get adminRoleSaveParents;

  /// No description provided for @adminRoleSaveBoundaries.
  ///
  /// In zh, this message translates to:
  /// **'保存授予上限'**
  String get adminRoleSaveBoundaries;

  /// No description provided for @adminRoleDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除角色'**
  String get adminRoleDelete;

  /// No description provided for @adminRoleDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'只删除没有成员、也不是其他角色上级的空角色。'**
  String get adminRoleDeleteConfirm;

  /// No description provided for @adminRoleParents.
  ///
  /// In zh, this message translates to:
  /// **'继承的上级角色'**
  String get adminRoleParents;

  /// No description provided for @adminRoleParentHint.
  ///
  /// In zh, this message translates to:
  /// **'停用的上级不会继续提供权限。'**
  String get adminRoleParentHint;

  /// No description provided for @adminRoleGrants.
  ///
  /// In zh, this message translates to:
  /// **'直接授权'**
  String get adminRoleGrants;

  /// No description provided for @adminRoleUnset.
  ///
  /// In zh, this message translates to:
  /// **'未配置'**
  String get adminRoleUnset;

  /// No description provided for @adminRoleAllow.
  ///
  /// In zh, this message translates to:
  /// **'允许'**
  String get adminRoleAllow;

  /// No description provided for @adminRoleDeny.
  ///
  /// In zh, this message translates to:
  /// **'拒绝'**
  String get adminRoleDeny;

  /// No description provided for @adminRoleBothEffects.
  ///
  /// In zh, this message translates to:
  /// **'允许并拒绝'**
  String get adminRoleBothEffects;

  /// No description provided for @adminRoleBoundaries.
  ///
  /// In zh, this message translates to:
  /// **'授予上限'**
  String get adminRoleBoundaries;

  /// No description provided for @adminRoleAffected.
  ///
  /// In zh, this message translates to:
  /// **'受影响账号'**
  String get adminRoleAffected;

  /// No description provided for @adminRoleReload.
  ///
  /// In zh, this message translates to:
  /// **'重新加载'**
  String get adminRoleReload;

  /// No description provided for @adminRoleEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有角色'**
  String get adminRoleEmpty;

  /// No description provided for @adminRoleCodeInvalid.
  ///
  /// In zh, this message translates to:
  /// **'代码需以小写字母开头，并且只含小写字母、数字和下划线'**
  String get adminRoleCodeInvalid;

  /// No description provided for @adminRoleNameInvalid.
  ///
  /// In zh, this message translates to:
  /// **'请填写 1 到 100 个字符的名称'**
  String get adminRoleNameInvalid;

  /// No description provided for @adminRoleDescriptionInvalid.
  ///
  /// In zh, this message translates to:
  /// **'描述不能超过 2000 个字符'**
  String get adminRoleDescriptionInvalid;

  /// No description provided for @adminRoleNoCatalog.
  ///
  /// In zh, this message translates to:
  /// **'没有权限目录读取权，不能编辑授权矩阵。'**
  String get adminRoleNoCatalog;

  /// No description provided for @adminRoleAssignRole.
  ///
  /// In zh, this message translates to:
  /// **'可分配角色'**
  String get adminRoleAssignRole;

  /// No description provided for @adminRoleAssignPermission.
  ///
  /// In zh, this message translates to:
  /// **'可授予权限'**
  String get adminRoleAssignPermission;

  /// No description provided for @adminRoleManageRole.
  ///
  /// In zh, this message translates to:
  /// **'可管理账号角色'**
  String get adminRoleManageRole;

  /// No description provided for @adminRoleUnassigned.
  ///
  /// In zh, this message translates to:
  /// **'可管理未分配账号'**
  String get adminRoleUnassigned;

  /// No description provided for @adminRoleAddBoundary.
  ///
  /// In zh, this message translates to:
  /// **'添加上限'**
  String get adminRoleAddBoundary;

  /// No description provided for @adminUserCreate.
  ///
  /// In zh, this message translates to:
  /// **'创建账号'**
  String get adminUserCreate;

  /// No description provided for @adminUserEmpty.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的账号'**
  String get adminUserEmpty;

  /// No description provided for @adminUserPendingGrant.
  ///
  /// In zh, this message translates to:
  /// **'待授权'**
  String get adminUserPendingGrant;

  /// No description provided for @adminUserDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已停用'**
  String get adminUserDisabled;

  /// No description provided for @adminUserLocked.
  ///
  /// In zh, this message translates to:
  /// **'已锁定'**
  String get adminUserLocked;

  /// No description provided for @adminUserDisplayName.
  ///
  /// In zh, this message translates to:
  /// **'显示名'**
  String get adminUserDisplayName;

  /// No description provided for @adminUserNoPassword.
  ///
  /// In zh, this message translates to:
  /// **'创建后不会生成可复制的密码。'**
  String get adminUserNoPassword;

  /// No description provided for @adminUserEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用'**
  String get adminUserEnable;

  /// No description provided for @adminUserDisable.
  ///
  /// In zh, this message translates to:
  /// **'停用'**
  String get adminUserDisable;

  /// No description provided for @adminUserRoles.
  ///
  /// In zh, this message translates to:
  /// **'角色'**
  String get adminUserRoles;

  /// No description provided for @adminUserSaveRoles.
  ///
  /// In zh, this message translates to:
  /// **'保存角色'**
  String get adminUserSaveRoles;

  /// No description provided for @adminUserSessions.
  ///
  /// In zh, this message translates to:
  /// **'会话'**
  String get adminUserSessions;

  /// No description provided for @adminUserRevoke.
  ///
  /// In zh, this message translates to:
  /// **'撤销'**
  String get adminUserRevoke;

  /// No description provided for @adminUserRevokeAll.
  ///
  /// In zh, this message translates to:
  /// **'撤销全部会话'**
  String get adminUserRevokeAll;

  /// No description provided for @adminMenuHidden.
  ///
  /// In zh, this message translates to:
  /// **'已隐藏'**
  String get adminMenuHidden;

  /// No description provided for @adminMenuHide.
  ///
  /// In zh, this message translates to:
  /// **'隐藏菜单'**
  String get adminMenuHide;

  /// No description provided for @adminMenuHideNote.
  ///
  /// In zh, this message translates to:
  /// **'隐藏菜单不会停用功能访问。'**
  String get adminMenuHideNote;

  /// No description provided for @adminMenuFeatureNote.
  ///
  /// In zh, this message translates to:
  /// **'停用功能访问需要在角色权限中撤销页面权限。'**
  String get adminMenuFeatureNote;

  /// No description provided for @adminMenuOpenRoles.
  ///
  /// In zh, this message translates to:
  /// **'前往角色权限'**
  String get adminMenuOpenRoles;

  /// No description provided for @adminMenuGroup.
  ///
  /// In zh, this message translates to:
  /// **'添加分组'**
  String get adminMenuGroup;

  /// No description provided for @adminMenuTop.
  ///
  /// In zh, this message translates to:
  /// **'顶层'**
  String get adminMenuTop;

  /// No description provided for @adminMenuExtra.
  ///
  /// In zh, this message translates to:
  /// **'附加显示条件'**
  String get adminMenuExtra;

  /// No description provided for @adminMenuPreview.
  ///
  /// In zh, this message translates to:
  /// **'预览导航'**
  String get adminMenuPreview;

  /// No description provided for @adminMenuSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get adminMenuSave;

  /// No description provided for @adminMenuCode.
  ///
  /// In zh, this message translates to:
  /// **'代码'**
  String get adminMenuCode;

  /// No description provided for @authActivationProgressTitle.
  ///
  /// In zh, this message translates to:
  /// **'账号激活进度'**
  String get authActivationProgressTitle;

  /// No description provided for @authActivationProgressHint.
  ///
  /// In zh, this message translates to:
  /// **'正在检查邮箱验证和注册审批状态。'**
  String get authActivationProgressHint;

  /// No description provided for @authActivationApprovalTitle.
  ///
  /// In zh, this message translates to:
  /// **'注册申请待审批'**
  String get authActivationApprovalTitle;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
