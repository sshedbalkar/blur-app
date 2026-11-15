import 'dart:convert';
import 'dart:io';

import 'package:blur_app/core/ai/ai_client.dart';
import 'package:blur_app/core/ai/command_planner.dart';
import 'package:blur_app/core/feature/feature.dart';
import 'package:blur_app/core/feature/feature_registry.dart';
import 'package:blur_app/core/logging/app_logger.dart';
import 'package:blur_app/core/settings/app_settings.dart';
import 'package:blur_app/features/deblur/neural_models.dart';
import 'package:blur_app/ui/home_screen.dart' show stepTempPath;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeFeature implements Feature {
  FakeFeature({this.note});

  /// Reported with every successful run.
  final String? note;

  @override
  String get id => 'fake';
  @override
  String get name => 'Fake';
  @override
  String get description => 'Test feature';
  @override
  List<ParamSpec> get params => const [
    NumParam(id: 'amount', label: 'Amount', min: 0, max: 10, defaultValue: 5),
    BoolParam(id: 'fast', label: 'Fast', defaultValue: false),
    ChoiceParam(
      id: 'mode',
      label: 'Mode',
      options: ['a', 'b'],
      defaultValue: 'a',
    ),
  ];

  Map<String, Object>? lastParams;

  @override
  Future<FeatureResult> run(
    FeatureContext context,
    Map<String, Object> params,
  ) async {
    lastParams = params;
    return FeatureResult.ok(context.outputPath, note: note);
  }
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('blur_app_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('FeatureCommand', () {
    test('fills defaults, clamps to range, drops unknown keys', () {
      final c = FeatureCommand(FakeFeature(), {
        'amount': 99,
        'mode': 'zzz',
        'bogus': 1,
      });
      expect(c.params, {'amount': 10.0, 'fast': false, 'mode': 'a'});
      c.set('amount', -3);
      expect(c.params['amount'], 0.0);
    });

    test('run passes coerced params to the feature', () async {
      final f = FakeFeature();
      final r = await FeatureCommand(f, {
        'fast': true,
      }).run(const FeatureContext(inputPath: 'in', outputPath: 'out'));
      expect(r.isOk, isTrue);
      expect(f.lastParams, {'amount': 5.0, 'fast': true, 'mode': 'a'});
    });
  });

  test('stepTempPath keeps the output extension', () {
    expect(stepTempPath('/a/b.c/out.png', 1), '/a/b.c/out.step1.tmp.png');
    expect(stepTempPath('/a/b.c/out', 2), '/a/b.c/out.step2.tmp');
    expect(stepTempPath('/a/.hidden', 1), '/a/.hidden.step1.tmp');
  });

  group('FeatureRegistry', () {
    test('register, reject duplicate, unregister, notify', () {
      final r = FeatureRegistry();
      var calls = 0;
      r.addListener(() => calls++);
      r.register(FakeFeature());
      expect(r.byId('fake'), isNotNull);
      expect(() => r.register(FakeFeature()), throwsArgumentError);
      r.unregister('fake');
      expect(r.all, isEmpty);
      expect(calls, 2);
    });
  });

  group('AppLogger', () {
    test('writes dated JSON-lines file and follows directory change', () {
      final log = AppLogger(
        '${tmp.path}/a',
        clock: () => DateTime(2026, 3, 7, 9, 5),
        echo: false,
      );
      log.interaction('clicked', {'what': 'run'});
      log.directory = '${tmp.path}/b';
      log.decision('picked');

      final a = File('${tmp.path}/a/blur-app_2026-03-07.log').readAsLinesSync();
      expect(a, hasLength(1));
      final entry = jsonDecode(a.single) as Map;
      expect(entry['kind'], 'interaction');
      expect(entry['event'], 'clicked');
      expect(entry['data'], {'what': 'run'});
      expect(
        File('${tmp.path}/b/blur-app_2026-03-07.log').readAsLinesSync(),
        hasLength(1),
      );
    });

    test('unwritable directory does not throw', () {
      File('${tmp.path}/file').writeAsStringSync('x');
      final log = AppLogger('${tmp.path}/file/sub', echo: false);
      expect(() => log.info('x'), returnsNormally);
    });
  });

  group('AppSettings', () {
    final env = {'HOME': '/home/u'};

    test('defaults follow XDG', () {
      expect(
        AppSettings.defaults(env).logDirectory,
        '/home/u/.local/state/blur-app/logs',
      );
      expect(
        AppSettings.defaults({...env, 'XDG_STATE_HOME': '/s'}).logDirectory,
        '/s/blur-app/logs',
      );
      expect(
        AppSettings.defaults(env).modelDirectory,
        '/home/u/.local/share/blur-app/models',
      );
      expect(
        AppSettings.defaults({...env, 'XDG_DATA_HOME': '/d'}).modelDirectory,
        '/d/blur-app/models',
      );
      expect(
        AppSettings.defaultFilePath(env),
        '/home/u/.config/blur-app/settings.json',
      );
    });

    test('save then load round-trips', () {
      final path = '${tmp.path}/cfg/settings.json';
      final s = AppSettings.defaults(env)
        ..logDirectory = '/x'
        ..aiEnabled = false
        ..aiModel = 'm'
        ..modelDirectory = '/models'
        ..neuralModel = 'n.onnx';
      s.save(path);
      expect(AppSettings.load(path, env).toJson(), s.toJson());
    });

    test('missing, corrupt or mistyped file falls back to defaults', () {
      final path = '${tmp.path}/settings.json';
      final d = AppSettings.defaults(env).toJson();
      expect(AppSettings.load(path, env).toJson(), d);
      File(path).writeAsStringSync('{not json');
      expect(AppSettings.load(path, env).toJson(), d);
      File(path).writeAsStringSync('{"aiEnabled":"yes","aiModel":"m"}');
      final s = AppSettings.load(path, env);
      expect(s.aiEnabled, isTrue);
      expect(s.aiModel, 'm');
    });
  });

  group('Neural models', () {
    AppSettings settingsFor(String dir, [String chosen = '']) =>
        AppSettings.defaults({'HOME': tmp.path})
          ..modelDirectory = dir
          ..neuralModel = chosen;

    NeuralModel modelWith(List<int> content) => NeuralModel(
      name: 'Tiny',
      fileName: 'tiny.onnx',
      url: 'https://example.invalid/tiny.onnx',
      sha256: sha256.convert(content).toString(),
      bytes: content.length,
      reason: 'test',
    );

    test('lists only .onnx files, sorted; missing folder is empty', () {
      expect(installedModels('${tmp.path}/none'), isEmpty);
      for (final name in ['b.onnx', 'a.onnx', 'notes.txt', 'c.onnx.part']) {
        File('${tmp.path}/$name').writeAsStringSync('x');
      }
      expect(installedModels(tmp.path), ['a.onnx', 'b.onnx']);
    });

    test('resolves chosen, then recommended, then first installed', () {
      expect(
        () => resolveModelPath(settingsFor(tmp.path)),
        throwsA(
          isA<NeuralModelException>().having(
            (e) => e.message,
            'message',
            'No neural model is installed. Download one in Settings.',
          ),
        ),
      );
      File('${tmp.path}/b.onnx').writeAsStringSync('x');
      File('${tmp.path}/a.onnx').writeAsStringSync('x');
      expect(resolveModelPath(settingsFor(tmp.path)), '${tmp.path}/a.onnx');
      final recommended = recommendedDeblurModel.fileName;
      File('${tmp.path}/$recommended').writeAsStringSync('x');
      expect(
        resolveModelPath(settingsFor(tmp.path)),
        '${tmp.path}/$recommended',
      );
      expect(
        resolveModelPath(settingsFor(tmp.path, 'b.onnx')),
        '${tmp.path}/b.onnx',
      );
      expect(
        () => resolveModelPath(settingsFor(tmp.path, 'gone.onnx')),
        throwsA(
          isA<NeuralModelException>().having(
            (e) => e.message,
            'message',
            contains('"gone.onnx" was not found'),
          ),
        ),
      );
    });

    test('download verifies the checksum and reports progress', () async {
      final content = List.generate(1000, (i) => i % 251);
      final dir = '${tmp.path}/models';
      final progress = <double>[];
      await downloadModel(
        modelWith(content),
        dir,
        client: MockClient((_) async => http.Response.bytes(content, 200)),
        onProgress: progress.add,
      );
      expect(File('$dir/tiny.onnx').readAsBytesSync(), content);
      expect(progress.last, 1.0);
      expect(installedModels(dir), ['tiny.onnx']);
    });

    test('damaged or refused download leaves no file behind', () async {
      final content = [1, 2, 3];
      final dir = '${tmp.path}/models';
      await expectLater(
        downloadModel(
          modelWith(content),
          dir,
          client: MockClient((_) async => http.Response.bytes([9, 9], 200)),
        ),
        throwsA(
          isA<NeuralModelException>().having(
            (e) => e.message,
            'message',
            contains('damaged'),
          ),
        ),
      );
      await expectLater(
        downloadModel(
          modelWith(content),
          dir,
          client: MockClient((_) async => http.Response('no', 404)),
        ),
        throwsA(
          isA<NeuralModelException>().having(
            (e) => e.message,
            'message',
            contains('404'),
          ),
        ),
      );
      expect(Directory(dir).listSync(), isEmpty);
    });
  });

  group('CommandPlanner', () {
    CommandPlanner planner(String reply, {FeatureRegistry? registry}) {
      registry ??= FeatureRegistry()..register(FakeFeature());
      return CommandPlanner(
        registry,
        ({required system, required user}) async => reply,
        AppLogger(tmp.path, echo: false),
      );
    }

    test('system prompt describes features and ranges', () {
      final prompt = planner('').buildSystemPrompt();
      expect(prompt, contains('"id":"fake"'));
      expect(prompt, contains('"min":0.0'));
      expect(prompt, contains('"max":10.0'));
    });

    test('parses fenced reply, clamps values, reports adjustments', () async {
      final plan = await planner(
        '```json\n{"commands":['
        '{"feature":"fake","params":{"amount":50,"fast":true,"x":1}},'
        '{"feature":"nope","params":{}}]}\n```',
      ).plan('do it');
      expect(plan.commands, hasLength(1));
      expect(plan.commands.single.params, {
        'amount': 10.0,
        'fast': true,
        'mode': 'a',
      });
      expect(plan.notes, hasLength(3));
      final logged = Directory(tmp.path).listSync().whereType<File>().single;
      expect(logged.readAsStringSync(), contains('"kind":"decision"'));
    });

    test('in-range values produce no notes', () {
      final plan = planner('')
          .parse('{"commands":[{"feature":"fake","params":{"amount":3}}]}');
      expect(plan.commands.single.params['amount'], 3.0);
      expect(plan.notes, isEmpty);
    });

    test('unintelligible reply and empty registry raise AiException', () {
      expect(
        () => planner('sorry, no').parse('sorry, no'),
        throwsA(isA<AiException>()),
      );
      expect(
        planner('{}', registry: FeatureRegistry()).plan('x'),
        throwsA(isA<AiException>()),
      );
    });
  });
}
