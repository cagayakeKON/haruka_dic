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
  /// **'当前应用只展示公开构建配置，尚未连接服务或保存个人数据。'**
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
