import 'dart:io';

import 'package:blur_app/core/feature/feature_registry.dart';
import 'package:blur_app/core/logging/app_logger.dart';
import 'package:blur_app/core/settings/app_settings.dart';
import 'package:blur_app/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'core_test.dart' show FakeFeature;

void main() {
  late Directory tmp;
  late AppServices services;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('blur_app_widget');
    services = AppServices(
      settings: AppSettings.defaults({'HOME': tmp.path}),
      settingsPath: '${tmp.path}/settings.json',
      logger: AppLogger('${tmp.path}/logs', echo: false),
      registry: FeatureRegistry(),
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Makes a whole screen fit, so nothing needs scrolling to.
  void useTallWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('empty registry shows the no-features message', (tester) async {
    await tester.pumpWidget(BlurApp(services: services));
    expect(find.text('No features are installed yet.'), findsOneWidget);
  });

  testWidgets('a feature registered at runtime can be added as a step', (
    tester,
  ) async {
    await tester.pumpWidget(BlurApp(services: services));
    services.registry.register(FakeFeature());
    await tester.pump();
    expect(find.text('No features are installed yet.'), findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fake').last);
    await tester.pumpAndSettle();

    expect(find.text('1. Fake'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('a note from a step is shown after the run', (tester) async {
    useTallWindow(tester);
    services.registry.register(FakeFeature(note: 'Ran slowly.'));
    final input = '${tmp.path}/in.png';
    File(input).writeAsStringSync('x');
    await tester.pumpWidget(BlurApp(services: services));

    await tester.enterText(find.widgetWithText(TextField, 'Input file'), input);
    await tester.enterText(
      find.widgetWithText(TextField, 'Save result as'),
      '${tmp.path}/out.png',
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fake').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();

    expect(
      find.text('Done. Saved to ${tmp.path}/out.png\nRan slowly.'),
      findsOneWidget,
    );
  });

  testWidgets('settings screen lists, picks and saves a neural model', (
    tester,
  ) async {
    useTallWindow(tester);
    final models = Directory('${tmp.path}/models')..createSync();
    File('${models.path}/mine.onnx').writeAsStringSync('x');
    await tester.pumpWidget(BlurApp(services: services));
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.textContaining('Recommended for removing blur'), findsOne);

    await tester.enterText(
      find.widgetWithText(TextField, 'Model folder'),
      models.path,
    );
    await tester.tap(find.text('List models'));
    await tester.pump();
    expect(
      find.text('Found 1 model(s) in the folder. Pick one below.'),
      findsOneWidget,
    );
    await tester.tap(find.text('mine.onnx'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Saved.'), findsOneWidget);
    final saved = AppSettings.load(services.settingsPath, {'HOME': tmp.path});
    expect(saved.modelDirectory, models.path);
    expect(saved.neuralModel, 'mine.onnx');
    expect(services.settings.neuralModel, 'mine.onnx');
  });

  testWidgets('settings screen saves changes to disk', (tester) async {
    useTallWindow(tester);
    await tester.pumpWidget(BlurApp(services: services));
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Log folder'),
      '${tmp.path}/newlogs',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Saved.'), findsOneWidget);
    final saved = AppSettings.load(services.settingsPath, {'HOME': tmp.path});
    expect(saved.logDirectory, '${tmp.path}/newlogs');
    expect(services.logger.directory, '${tmp.path}/newlogs');
  });
}
