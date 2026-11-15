import 'package:material_ui/material_ui.dart';

import '../core/ai/ai_client.dart';
import '../core/settings/app_settings.dart';
import '../features/deblur/neural_models.dart';
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
  late final _modelDir = TextEditingController(text: _settings.modelDirectory);
  late final _neuralModel = TextEditingController(text: _settings.neuralModel);
  late bool _aiEnabled = _settings.aiEnabled;

  List<String> _models = [];
  List<String> _neuralModels = [];
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
    _modelDir.dispose();
    _neuralModel.dispose();
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

  void _listNeuralModels() {
    final folder = _modelDir.text.trim();
    _s.logger.interaction('list_neural_models_pressed', {'folder': folder});
    final models = installedModels(folder);
    setState(() => _neuralModels = models);
    _say(
      models.isEmpty
          ? 'No models in that folder yet.'
          : 'Found ${models.length} model(s) in the folder. Pick one below.',
    );
  }

  Future<void> _downloadRecommended() async {
    const model = recommendedDeblurModel;
    final folder = _modelDir.text.trim();
    _s.logger.interaction('download_model_pressed', {
      'model': model.fileName,
      'folder': folder,
    });
    if (folder.isEmpty) {
      _say('Model folder cannot be empty.', error: true);
      return;
    }
    if (installedModels(folder).contains(model.fileName)) {
      setState(() => _neuralModels = installedModels(folder));
      _say('${model.name} is already installed.');
      return;
    }
    setState(() => _busy = true);
    _say('Downloading ${model.name}… 0%');
    var shown = 0;
    try {
      await downloadModel(
        model,
        folder,
        onProgress: (fraction) {
          final percent = (fraction * 100).floor();
          if (percent != shown && mounted) {
            shown = percent;
            _say('Downloading ${model.name}… $percent%');
          }
        },
      );
      _s.logger.info('model_downloaded', {
        'model': model.fileName,
        'folder': folder,
      });
      if (!mounted) return;
      setState(() {
        _neuralModels = installedModels(folder);
        _neuralModel.text = model.fileName;
      });
      _say('Downloaded ${model.name}. Press Save to keep it selected.');
    } on NeuralModelException catch (e) {
      _s.logger.error('model_download_failed', {'error': e.message});
      if (mounted) _say(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save() {
    final logDir = _logDir.text.trim();
    final baseUrl = _baseUrl.text.trim();
    final modelDir = _modelDir.text.trim();
    if (logDir.isEmpty || baseUrl.isEmpty) {
      _say('Log folder and AI server address cannot be empty.', error: true);
      return;
    }
    if (modelDir.isEmpty) {
      _say('Model folder cannot be empty.', error: true);
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
      ..aiModel = _model.text.trim()
      ..modelDirectory = modelDir
      ..neuralModel = _neuralModel.text.trim();
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
      _modelDir.text = d.modelDirectory;
      _neuralModel.text = d.neuralModel;
      _neuralModels = [];
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
          Text('Neural blur removal', style: titles),
          const SizedBox(height: 12),
          TextField(
            controller: _modelDir,
            decoration: const InputDecoration(
              labelText: 'Model folder',
              helperText: 'Put your own .onnx models here to use them',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _neuralModel,
                  decoration: const InputDecoration(
                    labelText: 'Neural model',
                    helperText: 'Leave empty to choose automatically',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _busy ? null : _listNeuralModels,
                child: const Text('List models'),
              ),
            ],
          ),
          if (_neuralModels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final m in _neuralModels)
                  ChoiceChip(
                    label: Text(m),
                    selected: _neuralModel.text == m,
                    onSelected: (_) {
                      _s.logger.interaction('neural_model_picked', {
                        'model': m,
                      });
                      setState(() => _neuralModel.text = m);
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            deblurModelRecommendation,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _downloadRecommended,
              icon: const Icon(Icons.download),
              label: const Text('Download recommended model'),
            ),
          ),
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
