import 'package:flutter/material.dart';
import '../presentation/audio_engine_test_interface/audio_engine_test_interface.dart';
import '../presentation/ambient_sound/ambient_sound_screen.dart';

class AppRoutes {
  // TODO: Add your routes here
  static const String initial = '/';
  static const String audioEngineTestInterface = '/audio-engine-test-interface';
  static const String ambientSound = '/ambient-sound';

  static Map<String, WidgetBuilder> routes = {
    initial: (context) => const AudioEngineTestInterface(),
    audioEngineTestInterface: (context) => const AudioEngineTestInterface(),
    ambientSound: (context) => const AmbientSoundScreen(),
    // TODO: Add your other routes here
  };
}
