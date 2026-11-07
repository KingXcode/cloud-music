import 'dart:async';

import 'package:flutter/material.dart';

import 'gateway/gateway_factory.dart';
import 'music_controller.dart';
import 'ui/music_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = MusicController(gateway: createMusicGateway());
  runApp(MusicApp(controller: controller));
  unawaited(controller.initialize());
}
