import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'state/app_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  runApp(FlowChatApp(controller: controller));
  unawaited(controller.initialize());
}
