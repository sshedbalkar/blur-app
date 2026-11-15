/// The plug-and-play feature contract. Every feature implements [Feature]
/// and is added to the [FeatureRegistry]; nothing else in the app needs to
/// know about it. See TECHNICAL_REQUIREMENTS.md TR-1.
library;

/// Declares one user-adjustable parameter and its supported operating range.
/// The UI builds its controls from these, and the AI planner is told about
/// them, so a feature never receives a value outside what it declares.
sealed class ParamSpec {
  const ParamSpec({required this.id, required this.label, this.help = ''});

  final String id;
  final String label;
  final String help;

  Object get defaultValue;

  /// Returns [raw] coerced into the supported range, or [defaultValue] when
  /// it cannot be interpreted at all.
  Object coerce(Object? raw);

  /// Machine-readable description sent to the AI model.
  Map<String, Object> describe();
}

final class NumParam extends ParamSpec {
  const NumParam({
    required super.id,
    required super.label,
    super.help,
    required this.min,
    required this.max,
    required double defaultValue,
    this.step,
  }) : _default = defaultValue,
       assert(min <= max),
       assert(defaultValue >= min && defaultValue <= max);

  final double min;
  final double max;

  /// Slider granularity; null means continuous.
  final double? step;
  final double _default;

  @override
  double get defaultValue => _default;

  @override
  double coerce(Object? raw) {
    final value = switch (raw) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };
    if (value == null || value.isNaN) return _default;
    return value.clamp(min, max).toDouble();
  }

  @override
  Map<String, Object> describe() => {
    'id': id,
    'type': 'number',
    'min': min,
    'max': max,
    'default': _default,
    if (help.isNotEmpty) 'help': help,
  };
}

final class BoolParam extends ParamSpec {
  const BoolParam({
    required super.id,
    required super.label,
    super.help,
    required bool defaultValue,
  }) : _default = defaultValue;

  final bool _default;

  @override
  bool get defaultValue => _default;

  @override
  bool coerce(Object? raw) => switch (raw) {
    bool b => b,
    'true' => true,
    'false' => false,
    _ => _default,
  };

  @override
  Map<String, Object> describe() => {
    'id': id,
    'type': 'boolean',
    'default': _default,
    if (help.isNotEmpty) 'help': help,
  };
}

final class ChoiceParam extends ParamSpec {
  const ChoiceParam({
    required super.id,
    required super.label,
    super.help,
    required this.options,
    required String defaultValue,
  }) : _default = defaultValue;

  final List<String> options;
  final String _default;

  @override
  String get defaultValue => _default;

  @override
  String coerce(Object? raw) =>
      raw is String && options.contains(raw) ? raw : _default;

  @override
  Map<String, Object> describe() => {
    'id': id,
    'type': 'choice',
    'options': options,
    'default': _default,
    if (help.isNotEmpty) 'help': help,
  };
}

/// What a feature is given when it runs.
class FeatureContext {
  const FeatureContext({required this.inputPath, required this.outputPath});

  final String inputPath;
  final String outputPath;
}

class FeatureResult {
  const FeatureResult.ok(String this.outputPath) : error = null;
  const FeatureResult.failed(String this.error) : outputPath = null;

  final String? outputPath;
  final String? error;

  bool get isOk => error == null;
}

abstract interface class Feature {
  /// Stable identifier used in commands, logs and AI output.
  String get id;

  String get name;

  /// Plain-language description of what the feature does. The AI planner
  /// relies on this to match a user's request to the feature.
  String get description;

  List<ParamSpec> get params;

  /// [params] has already been coerced into range by [FeatureCommand].
  Future<FeatureResult> run(FeatureContext context, Map<String, Object> params);
}

/// One planned invocation of a feature with concrete parameter values.
class FeatureCommand {
  /// Builds a command, filling missing parameters with defaults and coercing
  /// supplied ones into their supported range. Unknown keys are dropped.
  FeatureCommand(this.feature, [Map<String, Object?> raw = const {}])
    : params = {for (final p in feature.params) p.id: p.coerce(raw[p.id])};

  final Feature feature;
  final Map<String, Object> params;

  void set(String paramId, Object? value) {
    final spec = feature.params.firstWhere((p) => p.id == paramId);
    params[paramId] = spec.coerce(value);
  }

  Future<FeatureResult> run(FeatureContext context) =>
      feature.run(context, Map.unmodifiable(params));

  Map<String, Object> toJson() => {'feature': feature.id, 'params': params};
}
