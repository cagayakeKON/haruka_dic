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

  /// No description provided for @shellDescription.
  ///
  /// In zh, this message translates to:
  /// **'Haruka 的学习空间正在搭建。当前可查看应用环境与服务连接。'**
  String get shellDescription;

  /// No description provided for @materialsTitle.
  ///
  /// In zh, this message translates to:
  /// **'你的学习材料'**
  String get materialsTitle;

  /// No description provided for @materialsDescription.
  ///
  /// In zh, this message translates to:
  /// **'小说、课本和试卷将分别进入专属的阅读与学习页面。'**
  String get materialsDescription;

  /// No description provided for @materialLanguages.
  ///
  /// In zh, this message translates to:
  /// **'首版材料支持日语和英语。'**
  String get materialLanguages;

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
  /// **'管理端需要独立登录及在线权限验证，当前尚未开放。'**
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

  /// No description provided for @authRequestRecovery.
  ///
  /// In zh, this message translates to:
  /// **'提交申请'**
  String get authRequestRecovery;

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

  /// No description provided for @authAdminPublishedNotice.
  ///
  /// In zh, this message translates to:
  /// **'注册策略保存后由服务端生效；仅显示当前有权管理的操作。'**
  String get authAdminPublishedNotice;

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

  /// No description provided for @referenceMaterialsHint.
  ///
  /// In zh, this message translates to:
  /// **'这里仅展示可读取的短材料，用于验证选区查询与收藏；完整阅读器在后续阶段提供。'**
  String get referenceMaterialsHint;

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
  /// **'现有账号仍可登录与邮件找回；新账号注册由上方开关控制。'**
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
