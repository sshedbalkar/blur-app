import 'dart:convert';

import 'package:http/http.dart' as http;

class AiException implements Exception {
  AiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Talks to a local model server that exposes the OpenAI-compatible HTTP API
/// (Ollama, llama.cpp server, LM Studio, ...). Swapping the model means
/// changing the base URL or model name in settings; no code changes.
class AiClient {
  AiClient({required this.baseUrl, required this.model, http.Client? client})
    : _http = client ?? http.Client();

  final String baseUrl;
  final String model;
  final http.Client _http;

  static const _timeout = Duration(seconds: 120);

  Uri _uri(String path) =>
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  /// Names of the models the server offers.
  Future<List<String>> listModels() async {
    final body = await _send(() => _http.get(_uri('/models')));
    final data = body['data'];
    if (data is! List) throw AiException('Unexpected response from /models');
    return [
      for (final m in data)
        if (m is Map && m['id'] is String) m['id'] as String,
    ];
  }

  /// Sends a chat request and returns the assistant's reply text.
  Future<String> chat({required String system, required String user}) async {
    if (model.isEmpty) {
      throw AiException('No AI model selected. Choose one in Settings.');
    }
    final body = await _send(
      () => _http.post(
        _uri('/chat/completions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': model,
          'temperature': 0,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
        }),
      ),
    );
    final choices = body['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map && first['message'] is Map) {
        final content = (first['message'] as Map)['content'];
        if (content is String) return content;
      }
    }
    throw AiException('The AI server returned no reply');
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on Exception catch (e) {
      throw AiException('Cannot reach the AI server at $baseUrl ($e)');
    }
    if (response.statusCode != 200) {
      throw AiException(
        'AI server error ${response.statusCode}: ${response.body}',
      );
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Fall through to the error below.
    }
    throw AiException('The AI server sent a response that is not JSON');
  }

  void close() => _http.close();
}
