import 'package:material_ui/material_ui.dart';

import 'core/feature/feature_registry.dart';
import 'core/logging/app_logger.dart';
import 'core/settings/app_settings.dart';
import 'features/builtin.dart';
import 'ui/home_screen.dart';

/// The long-lived objects every screen shares.
class AppServices {
  AppServices({
    required this.settings,
    required this.settingsPath,
    required this.logger,
    required this.registry,
  });

  final AppSettings settings;
  final String settingsPath;
  final AppLogger logger;
  final FeatureRegistry registry;
}

void main() {
  final settingsPath = AppSettings.defaultFilePath();
  final settings = AppSettings.load(settingsPath);
  final logger = AppLogger(settings.logDirectory);
  final registry = FeatureRegistry();
  registerBuiltinFeatures(registry, settings);
  logger.info('app_start', {
    'features': [for (final f in registry.all) f.id],
    'logFile': logger.currentFilePath,
  });
  runApp(
    BlurApp(
      services: AppServices(
        settings: settings,
        settingsPath: settingsPath,
        logger: logger,
        registry: registry,
      ),
    ),
  );
}

class BlurApp extends StatelessWidget {
  const BlurApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blur App',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.indigo)),
      darkTheme: ThemeData(
        colorScheme: .fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: HomeScreen(services: services),
    );
  }
}
