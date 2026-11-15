import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../core/ai/ai_client.dart';
import '../core/ai/command_planner.dart';
import '../core/feature/feature.dart';
import '../main.dart';
import 'param_control.dart';
import 'settings_screen.dart';

/// Main workflow: pick a file, describe the goal, review and adjust the
/// planned commands, run them.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _input = TextEditingController();
  final _output = TextEditingController();
  final _request = TextEditingController();

  final List<FeatureCommand> _commands = [];
  List<String> _notes = [];
  String? _status;
  bool _isError = false;
  bool _busy = false;

  AppServices get _s => widget.services;

  @override
  void initState() {
    super.initState();
    _s.registry.addListener(_onFeaturesChanged);
  }

  @override
  void dispose() {
    _s.registry.removeListener(_onFeaturesChanged);
    _input.dispose();
    _output.dispose();
    _request.dispose();
    super.dispose();
  }

  void _onFeaturesChanged() {
    setState(() {
      _commands.removeWhere((c) => _s.registry.byId(c.feature.id) == null);
    });
  }

  void _setStatus(String? message, {bool error = false}) {
    setState(() {
      _status = message;
      _isError = error;
    });
  }

  Future<void> _plan() async {
    final request = _request.text.trim();
    _s.logger.interaction('plan_pressed');
    _s.logger.input('request', {'text': request});
    if (request.isEmpty) {
      _setStatus('Describe what you want to do first.', error: true);
      return;
    }
    final client = AiClient(
      baseUrl: _s.settings.aiBaseUrl,
      model: _s.settings.aiModel,
    );
    setState(() {
      _busy = true;
      _status = 'Asking the AI model…';
      _isError = false;
    });
    try {
      final plan = await CommandPlanner(
        _s.registry,
        client.chat,
        _s.logger,
      ).plan(request);
      if (!mounted) return;
      setState(() {
        _commands
          ..clear()
          ..addAll(plan.commands);
        _notes = plan.notes;
        _status = plan.commands.isEmpty
            ? 'The AI found no matching feature for that request.'
            : 'Review the suggested steps and settings, then run.';
      });
    } on AiException catch (e) {
      _s.logger.error('plan_failed', {'error': e.message});
      if (mounted) _setStatus(e.message, error: true);
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addManually(Feature feature) {
    _s.logger.interaction('command_added', {'feature': feature.id});
    setState(() => _commands.add(FeatureCommand(feature)));
  }

  void _remove(int index) {
    _s.logger.interaction('command_removed', {
      'feature': _commands[index].feature.id,
    });
    setState(() => _commands.removeAt(index));
  }

  Future<void> _run() async {
    final input = _input.text.trim();
    final output = _output.text.trim();
    _s.logger.interaction('run_pressed');
    _s.logger.input('paths', {'input': input, 'output': output});
    if (input.isEmpty || !File(input).existsSync()) {
      _setStatus('Input file not found: "$input"', error: true);
      return;
    }
    if (output.isEmpty) {
      _setStatus('Enter where to save the result.', error: true);
      return;
    }
    if (output == input) {
      _setStatus(
        'Output must be a different file from the input.',
        error: true,
      );
      return;
    }
    setState(() => _busy = true);
    // Each step reads the previous step's result; only the last one writes
    // the user's output path.
    var current = input;
    final temps = <String>[];
    try {
      for (var i = 0; i < _commands.length; i++) {
        final command = _commands[i];
        final isLast = i == _commands.length - 1;
        final target = isLast ? output : '$output.step${i + 1}.tmp';
        if (!isLast) temps.add(target);
        _setStatus('Running ${command.feature.name}…');
        _s.logger.info('command_start', command.toJson());
        final result = await command.run(
          FeatureContext(inputPath: current, outputPath: target),
        );
        if (!result.isOk) {
          _s.logger.error('command_failed', {
            'feature': command.feature.id,
            'error': result.error,
          });
          if (mounted) {
            _setStatus(
              '${command.feature.name} failed: ${result.error}',
              error: true,
            );
          }
          return;
        }
        _s.logger.info('command_done', {
          'feature': command.feature.id,
          'output': result.outputPath,
        });
        current = result.outputPath!;
      }
      if (mounted) _setStatus('Done. Saved to $current');
    } catch (e) {
      _s.logger.error('run_crashed', {'error': '$e'});
      if (mounted) _setStatus('Run failed: $e', error: true);
    } finally {
      for (final t in temps) {
        final f = File(t);
        if (f.existsSync()) f.deleteSync();
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSettings() async {
    _s.logger.interaction('settings_opened');
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SettingsScreen(services: _s)),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final features = _s.registry.all;
    final aiOn = _s.settings.aiEnabled;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blur App'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _input,
            decoration: const InputDecoration(
              labelText: 'Input file',
              hintText: '/path/to/file',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _output,
            decoration: const InputDecoration(
              labelText: 'Save result as',
              hintText: '/path/to/result',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          if (aiOn) ...[
            TextField(
              controller: _request,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Describe what you want',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _busy || features.isEmpty ? null : _plan,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Suggest steps'),
              ),
            ),
            const SizedBox(height: 24),
          ],
          Row(
            children: [
              Text('Steps', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (features.isNotEmpty)
                PopupMenuButton<Feature>(
                  tooltip: 'Add a step',
                  enabled: !_busy,
                  icon: const Icon(Icons.add),
                  onSelected: _addManually,
                  itemBuilder: (_) => [
                    for (final f in features)
                      PopupMenuItem(value: f, child: Text(f.name)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (features.isEmpty)
            const Text('No features are installed yet.')
          else if (_commands.isEmpty)
            Text(
              aiOn
                  ? 'Describe what you want above, or add a step with +.'
                  : 'Add a step with +.',
            ),
          for (final note in _notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(note, style: Theme.of(context).textTheme.bodySmall),
            ),
          for (var i = 0; i < _commands.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${i + 1}. ${_commands[i].feature.name}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove step',
                          icon: const Icon(Icons.close),
                          onPressed: _busy ? null : () => _remove(i),
                        ),
                      ],
                    ),
                    for (final spec in _commands[i].feature.params)
                      ParamControl(
                        spec: spec,
                        value: _commands[i].params[spec.id]!,
                        enabled: !_busy,
                        onChanged: (v) =>
                            setState(() => _commands[i].set(spec.id, v)),
                        onCommitted: (v) => _s.logger.input('param_changed', {
                          'feature': _commands[i].feature.id,
                          'param': spec.id,
                          'value': v,
                        }),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _busy || _commands.isEmpty ? null : _run,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Run'),
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(
              _status!,
              style: TextStyle(color: _isError ? scheme.error : null),
            ),
          ],
        ],
      ),
    );
  }
}
