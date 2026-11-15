import 'dart:convert';

import '../feature/feature.dart';
import '../feature/feature_registry.dart';
import '../logging/app_logger.dart';
import 'ai_client.dart';

/// Signature of the model call, so the planner can be tested without a server.
typedef ChatFn = Future<String> Function({
  required String system,
  required String user,
});

class Plan {
  const Plan(this.commands, this.notes);

  final List<FeatureCommand> commands;

  /// Things the user should know: steps the model asked for that were
  /// dropped, and values that were pulled back into range.
  final List<String> notes;
}

/// Turns a plain-language request into feature commands with suggested
/// parameter values (UX-1, UX-3). The model only proposes; every value is
/// coerced into the feature's declared range before the user sees it.
class CommandPlanner {
  CommandPlanner(this._registry, this._chat, this._log);

  final FeatureRegistry _registry;
  final ChatFn _chat;
  final AppLogger _log;

  String buildSystemPrompt() {
    final features = [
      for (final f in _registry.all)
        {
          'id': f.id,
          'description': f.description,
          'params': [for (final p in f.params) p.describe()],
        },
    ];
    return 'You convert a user request about a media file into an ordered '
        'list of feature commands.\n'
        'Available features (JSON):\n${jsonEncode(features)}\n'
        'Choose parameter values best suited to the request, within each '
        'parameter\'s min/max or options.\n'
        'Reply with JSON only, in this shape:\n'
        '{"commands":[{"feature":"<id>","params":{"<param id>":<value>}}]}\n'
        'Use only the listed feature ids. If nothing fits, reply '
        '{"commands":[]}.';
  }

  Future<Plan> plan(String request) async {
    if (_registry.all.isEmpty) {
      throw AiException(
        'No features are installed, so there is nothing to plan.',
      );
    }
    final reply = await _chat(system: buildSystemPrompt(), user: request);
    final plan = parse(reply);
    _log.decision('plan', {
      'request': request,
      'modelReply': reply,
      'commands': [for (final c in plan.commands) c.toJson()],
      'notes': plan.notes,
    });
    return plan;
  }

  /// Parses a model reply. Tolerates text or code fences around the JSON.
  Plan parse(String reply) {
    final start = reply.indexOf('{');
    final end = reply.lastIndexOf('}');
    Object? json;
    if (start >= 0 && end > start) {
      try {
        json = jsonDecode(reply.substring(start, end + 1));
      } on FormatException {
        json = null;
      }
    }
    final rawCommands = json is Map ? json['commands'] : null;
    if (rawCommands is! List) {
      throw AiException('The AI reply could not be understood: $reply');
    }

    final commands = <FeatureCommand>[];
    final notes = <String>[];
    for (final raw in rawCommands) {
      if (raw is! Map) continue;
      final id = raw['feature'];
      final feature = id is String ? _registry.byId(id) : null;
      if (feature == null) {
        notes.add('Skipped unknown feature "$id".');
        continue;
      }
      final rawParams = raw['params'];
      final supplied = rawParams is Map
          ? rawParams.map((k, v) => MapEntry('$k', v as Object?))
          : const <String, Object?>{};
      final command = FeatureCommand(feature, supplied);
      for (final entry in supplied.entries) {
        final used = command.params[entry.key];
        if (used == null) {
          notes.add('${feature.name}: ignored unknown setting "${entry.key}".');
        } else if (entry.value != null && !_sameValue(used, entry.value!)) {
          notes.add(
            '${feature.name}: "${entry.key}" suggested as ${entry.value}, '
            'adjusted to $used to stay in the supported range.',
          );
        }
      }
      commands.add(command);
    }
    return Plan(commands, notes);
  }

  static bool _sameValue(Object used, Object suggested) =>
      used is num && suggested is num ? used == suggested : used == suggested;
}
