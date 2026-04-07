import 'dart:convert';
import 'dart:io';
import 'llm_client.dart';

class OllamaClient implements LLMClient {
  final String baseUrl; // default 'http://localhost:11434'
  final String model;

  const OllamaClient({
    this.baseUrl = 'http://localhost:11434',
    required this.model,
  });

  @override
  Future<String> complete({
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 1000,
  }) async {
    final uri = Uri.parse('$baseUrl/api/chat');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(uri);
      request.headers.set('content-type', 'application/json');

      final bodyMap = {
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userMessage},
        ],
        'stream': false,
      };

      final bodyBytes = utf8.encode(jsonEncode(bodyMap));
      request.headers.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close()
          .timeout(const Duration(seconds: 10), onTimeout: () {
        throw Exception('Ollama connection timed out. Is Ollama running?');
      });

      final responseBody = await response.transform(utf8.decoder).join()
          .timeout(const Duration(seconds: 180), onTimeout: () {
        throw Exception(
            'Ollama took too long to respond. The model may still be loading — try again in a moment.');
      });

      if (response.statusCode != 200) {
        throw Exception(
          'Ollama API error ${response.statusCode}: $responseBody',
        );
      }

      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final message = data['message'] as Map<String, dynamic>;
      return message['content'] as String? ?? '';
    } finally {
      client.close();
    }
  }

  @override
  Stream<String> stream({
    required String systemPrompt,
    required String userMessage,
  }) async* {
    // Non-streaming fallback: call complete() and yield the full result.
    final result = await complete(
      systemPrompt: systemPrompt,
      userMessage: userMessage,
    );
    yield result;
  }

  /// Returns true if Ollama is reachable at [baseUrl].
  static Future<bool> isRunning(String baseUrl) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl/api/tags'));
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Returns list of locally available model names.
  static Future<List<String>> getAvailableModels(String baseUrl) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl/api/tags'));
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) return [];
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final models = data['models'] as List<dynamic>? ?? [];
      return models
          .map((m) => (m as Map<String, dynamic>)['name'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    } finally {
      client.close();
    }
  }
}
