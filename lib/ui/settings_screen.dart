import 'package:material_ui/material_ui.dart';

import '../core/ai/ai_client.dart';
import '../core/settings/app_settings.dart';
import '../main.dart';

/// The one place every global setting is shown and changed.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _logDir = TextEditingController(text: _settings.logDirectory);
  late final _baseUrl = TextEditingController(text: _settings.aiBaseUrl);
  late final _model = TextEditingController(text: _settings.aiModel);
  late bool _aiEnabled = _settings.aiEnabled;

  List<String> _models = [];
  String? _message;
  bool _isError = false;
  bool _busy = false;

  AppServices get _s => widget.services;
  AppSettings get _settings => _s.settings;

  @override
  void dispose() {
    _logDir.dispose();
    _baseUrl.dispose();
    _model.dispose();
    super.dispose();
  }

  void _say(String message, {bool error = false}) {
    setState(() {
      _message = message;
      _isError = error;
    });
  }

  Future<void> _findModels() async {
    _s.logger.interaction('find_models_pressed', {'baseUrl': _baseUrl.text});
    final client = AiClient(baseUrl: _baseUrl.text.trim(), model: '');
    setState(() => _busy = true);
    try {
      final models = await client.listModels();
      if (!mounted) return;
      setState(() => _models = models);
      _say(
        models.isEmpty
            ? 'The server is reachable but has no models.'
            : 'Found ${models.length} model(s). Pick one below.',
      );
    } on AiException catch (e) {
      _s.logger.error('find_models_failed', {'error': e.message});
      if (mounted) _say(e.message, error: true);
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save() {
    final logDir = _logDir.text.trim();
    final baseUrl = _baseUrl.text.trim();
    if (logDir.isEmpty || baseUrl.isEmpty) {
      _say('Log folder and AI server address cannot be empty.', error: true);
      return;
    }
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      _say('AI server address is not a valid URL.', error: true);
      return;
    }
    final before = _settings.toJson();
    _settings
      ..logDirectory = logDir
      ..aiEnabled = _aiEnabled
      ..aiBaseUrl = baseUrl
      ..aiModel = _model.text.trim();
    try {
      _settings.save(_s.settingsPath);
    } on Exception catch (e) {
      _s.logger.error('settings_save_failed', {'error': '$e'});
      _say('Could not save settings: $e', error: true);
      return;
    }
    _s.logger.directory = logDir;
    _s.logger.input('settings_saved', {
      'before': before,
      'after': _settings.toJson(),
    });
    _say('Saved.');
  }

  void _reset() {
    _s.logger.interaction('settings_reset_pressed');
    final d = AppSettings.defaults();
    setState(() {
      _logDir.text = d.logDirectory;
      _baseUrl.text = d.aiBaseUrl;
      _model.text = d.aiModel;
      _aiEnabled = d.aiEnabled;
      _models = [];
    });
    _say('Defaults restored. Press Save to keep them.');
  }

  @override
  Widget build(BuildContext context) {
    final titles = Theme.of(context).textTheme.titleMedium;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Logs', style: titles),
          const SizedBox(height: 12),
          TextField(
            controller: _logDir,
            decoration: const InputDecoration(
              labelText: 'Log folder',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Text('AI model', style: titles),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use AI to suggest steps and settings'),
            value: _aiEnabled,
            onChanged: (v) {
              _s.logger.interaction('ai_toggle', {'enabled': v});
              setState(() => _aiEnabled = v);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _baseUrl,
            enabled: _aiEnabled,
            decoration: const InputDecoration(
              labelText: 'Local AI server address',
              helperText:
                  'Any OpenAI-compatible server, e.g. Ollama, llama.cpp, '
                  'LM Studio',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _model,
                  enabled: _aiEnabled,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _busy || !_aiEnabled ? null : _findModels,
                child: const Text('Find models'),
              ),
            ],
          ),
          if (_models.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final m in _models)
                  ChoiceChip(
                    label: Text(m),
                    selected: _model.text == m,
                    onSelected: (_) {
                      _s.logger.interaction('model_picked', {'model': m});
                      setState(() => _model.text = m);
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              FilledButton(onPressed: _save, child: const Text('Save')),
              const SizedBox(width: 12),
              TextButton(
                onPressed: _reset,
                child: const Text('Restore defaults'),
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(
              _message!,
              style: TextStyle(
                color: _isError ? Theme.of(context).colorScheme.error : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
