import 'dart:async';

import 'package:flutter/material.dart';

import 'gateway/gateway_factory.dart';
import 'music_controller.dart';
import 'ui/music_app.dart';
import 'updates/update_controller.dart';
import 'updates/update_factory.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = MusicController(gateway: createMusicGateway());
  final updates = UpdateController(createUpdateBackend());
  runApp(MusicApp(controller: controller, updates: updates));
  unawaited(updates.initialize());
  unawaited(controller.initialize());
}
