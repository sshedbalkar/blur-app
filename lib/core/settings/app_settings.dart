import 'dart:convert';
import 'dart:io';

/// All global settings live here and are edited on the Settings screen
/// (TECHNICAL_REQUIREMENTS.md TR-6). Defaults are derived from the local
/// environment; a value is only written to disk once the user changes it.
class AppSettings {
  AppSettings({
    required this.logDirectory,
    required this.aiEnabled,
    required this.aiBaseUrl,
    required this.aiModel,
    required this.modelDirectory,
    required this.neuralModel,
  });

  /// Defaults for this machine, following the XDG base directory layout.
  factory AppSettings.defaults([Map<String, String>? env]) {
    env ??= Platform.environment;
    return AppSettings(
      logDirectory: '${_stateHome(env)}/blur-app/logs',
      aiEnabled: true,
      // Ollama's default port; any OpenAI-compatible server works.
      aiBaseUrl: 'http://localhost:11434/v1',
      aiModel: '',
      modelDirectory: '${_dataHome(env)}/blur-app/models',
      neuralModel: '',
    );
  }

  String logDirectory;
  bool aiEnabled;

  /// Base URL of a local OpenAI-compatible server, ending in `/v1`.
  String aiBaseUrl;

  /// Model name as the server knows it. Empty means none chosen yet.
  String aiModel;

  /// Folder holding neural models (`.onnx` files), downloaded or user-added.
  String modelDirectory;

  /// File name, in [modelDirectory], of the neural model to use. Empty means
  /// choose automatically.
  String neuralModel;

  static String _home(Map<String, String> env) => env['HOME'] ?? '.';

  static String _stateHome(Map<String, String> env) =>
      _nonEmpty(env['XDG_STATE_HOME']) ?? '${_home(env)}/.local/state';

  static String _dataHome(Map<String, String> env) =>
      _nonEmpty(env['XDG_DATA_HOME']) ?? '${_home(env)}/.local/share';

  static String defaultFilePath([Map<String, String>? env]) {
    env ??= Platform.environment;
    final config = _nonEmpty(env['XDG_CONFIG_HOME']) ?? '${_home(env)}/.config';
    return '$config/blur-app/settings.json';
  }

  static String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

  Map<String, Object> toJson() => {
    'logDirectory': logDirectory,
    'aiEnabled': aiEnabled,
    'aiBaseUrl': aiBaseUrl,
    'aiModel': aiModel,
    'modelDirectory': modelDirectory,
    'neuralModel': neuralModel,
  };

  /// Loads settings from [path], falling back to defaults for a missing or
  /// unreadable file and for any individual key that is absent or mistyped.
  static AppSettings load(String path, [Map<String, String>? env]) {
    final settings = AppSettings.defaults(env);
    final file = File(path);
    if (!file.existsSync()) return settings;
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map) return settings;
      if (json['logDirectory'] case final String v when v.isNotEmpty) {
        settings.logDirectory = v;
      }
      if (json['aiEnabled'] case final bool v) settings.aiEnabled = v;
      if (json['aiBaseUrl'] case final String v when v.isNotEmpty) {
        settings.aiBaseUrl = v;
      }
      if (json['aiModel'] case final String v) settings.aiModel = v;
      if (json['modelDirectory'] case final String v when v.isNotEmpty) {
        settings.modelDirectory = v;
      }
      if (json['neuralModel'] case final String v) settings.neuralModel = v;
    } on FormatException {
      // Corrupt file: keep defaults; it is rewritten on the next save.
    } on FileSystemException {
      // Unreadable file: keep defaults.
    }
    return settings;
  }

  void save(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n',
    );
  }
}
