import 'package:flutter/widgets.dart';

import '../domain/model_configuration_controller.dart';

class ModelConfigurationScope extends InheritedWidget {
  const ModelConfigurationScope({required this.controller, required super.child, super.key});
  final ModelConfigurationController controller;
  static ModelConfigurationController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ModelConfigurationScope>()?.controller;
  @override
  bool updateShouldNotify(ModelConfigurationScope oldWidget) => controller != oldWidget.controller;
}
