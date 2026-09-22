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
  String get environmentDescription => '当前应用只展示公开构建配置，尚未连接服务或保存个人数据。';

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
}
