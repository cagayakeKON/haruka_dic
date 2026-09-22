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
  /// **'应用基础已就绪。账号、材料与学习功能正在建设中。'**
  String get shellDescription;

  /// No description provided for @materialsTitle.
  ///
  /// In zh, this message translates to:
  /// **'你的学习材料'**
  String get materialsTitle;

  /// No description provided for @materialsDescription.
  ///
  /// In zh, this message translates to:
  /// **'未来可导入小说、课本和试卷，使用各自的阅读与练习页面。'**
  String get materialsDescription;

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
