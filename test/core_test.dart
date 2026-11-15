import 'dart:convert';
import 'dart:io';

import 'package:blur_app/core/ai/ai_client.dart';
import 'package:blur_app/core/ai/command_planner.dart';
import 'package:blur_app/core/feature/feature.dart';
import 'package:blur_app/core/feature/feature_registry.dart';
import 'package:blur_app/core/logging/app_logger.dart';
import 'package:blur_app/core/settings/app_settings.dart';
import 'package:blur_app/ui/home_screen.dart' show stepTempPath;
import 'package:flutter_test/flutter_test.dart';

class FakeFeature implements Feature {
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
    return FeatureResult.ok(context.outputPath);
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
        AppSettings.defaultFilePath(env),
        '/home/u/.config/blur-app/settings.json',
      );
    });

    test('save then load round-trips', () {
      final path = '${tmp.path}/cfg/settings.json';
      final s = AppSettings.defaults(env)
        ..logDirectory = '/x'
        ..aiEnabled = false
        ..aiModel = 'm';
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
