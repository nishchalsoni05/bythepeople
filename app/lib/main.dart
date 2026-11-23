import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:by_the_people/app/app.dart';
import 'package:by_the_people/core/config/env.dart';
import 'package:by_the_people/core/logging/app_logger.dart';
import 'package:by_the_people/presentation/widgets/shaders.dart';

Future<void> main() async {
  runZonedGuarded(_bootstrap, (error, stack) => appLogger.e('Uncaught error', error: error, stackTrace: stack));
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    appLogger.e('Framework error: ${details.exceptionAsString()}', error: details.exception, stackTrace: details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    appLogger.e('Platform error', error: error, stackTrace: stack);
    return true;
  };

  await Env.load();
  await ShaderLib.load(); // compile shaders on splash
  // Phone UI is portrait-only; this also keeps the motion-sensor axes stable for the cards.
  await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarBrightness: Brightness.light,
    statusBarIconBrightness: Brightness.dark,
  ));
  // Riverpod 3 retries failed providers; we show our own retry button instead.
  runApp(ProviderScope(retry: (_, __) => null, child: const ByThePeopleApp()));
}
