/// Selects and registers the process-wide video_player backend.
library;

import 'package:flutter/foundation.dart';
import 'package:fvp/fvp.dart' as fvp;

import 'log.dart';

enum VideoBackend { official, fvp }

typedef FvpRegistrar = void Function({dynamic options});

VideoBackend registerVideoBackend({
  TargetPlatform? platform,
  FvpRegistrar? registrar,
}) {
  final target = platform ?? defaultTargetPlatform;
  if (target != TargetPlatform.iOS) {
    Log.i('Video backend registered=official platform=${target.name}');
    return VideoBackend.official;
  }

  try {
    final register = registrar ?? fvp.registerWith;
    register(
      options: <String, dynamic>{
        'platforms': <String>['ios'],
      },
    );
    Log.i('Video backend registered=fvp platform=ios');
    return VideoBackend.fvp;
  } catch (error, stackTrace) {
    Log.e(
      'Video backend registration failed platform=ios fallback=official',
      error: error.runtimeType,
      stackTrace: stackTrace,
    );
    return VideoBackend.official;
  }
}
