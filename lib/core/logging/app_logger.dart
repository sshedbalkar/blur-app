import 'dart:convert';
import 'dart:io';

/// What kind of event a log line records. `interaction`, `input` and
/// `decision` are the audit trail required by TECHNICAL_REQUIREMENTS.md TR-2;
/// `info` and `error` are ordinary diagnostics.
enum LogKind { interaction, input, decision, info, error }

/// Appends one JSON object per line to `blur-app_YYYY-MM-DD.log` in the
/// configured directory, rolling to a new file when the date changes, and
/// mirrors each line to stdout.
class AppLogger {
  AppLogger(this.directory, {DateTime Function()? clock, this.echo = true})
    : _clock = clock ?? DateTime.now;

  /// Where log files are written. Changing it redirects later lines;
  /// existing files are left where they are.
  String directory;
  final DateTime Function() _clock;
  final bool echo;

  static String fileNameFor(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'blur-app_${t.year}-${two(t.month)}-${two(t.day)}.log';
  }

  String get currentFilePath => '$directory/${fileNameFor(_clock())}';

  void log(LogKind kind, String event, [Map<String, Object?> data = const {}]) {
    final now = _clock();
    final line = jsonEncode({
      'time': now.toIso8601String(),
      'kind': kind.name,
      'event': event,
      if (data.isNotEmpty) 'data': data,
    });
    if (echo) stdout.writeln(line);
    try {
      Directory(directory).createSync(recursive: true);
      File('$directory/${fileNameFor(now)}')
          .writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } on FileSystemException catch (e) {
      // Logging must never take the app down; report and carry on.
      stderr.writeln('blur-app: cannot write log to $directory: ${e.message}');
    }
  }

  void interaction(String event, [Map<String, Object?> data = const {}]) =>
      log(LogKind.interaction, event, data);

  void input(String event, [Map<String, Object?> data = const {}]) =>
      log(LogKind.input, event, data);

  void decision(String event, [Map<String, Object?> data = const {}]) =>
      log(LogKind.decision, event, data);

  void info(String event, [Map<String, Object?> data = const {}]) =>
      log(LogKind.info, event, data);

  void error(String event, [Map<String, Object?> data = const {}]) =>
      log(LogKind.error, event, data);
}
