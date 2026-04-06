import 'dart:convert';
import 'dart:io';

import 'llm_client.dart';

class ClaudeClient implements LLMClient {
  final String apiKey;
  final String model;

  ClaudeClient({
    required this.apiKey,
    this.model = 'claude-opus-4-5',
  });

  static const String _baseUrl = 'api.anthropic.com';
  static const String _messagesPath = '/v1/messages';
  static const String _anthropicVersion = '2023-06-01';

  @override
  Future<String> complete({
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 1000,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.https(_baseUrl, _messagesPath),
      );

      request.headers.set('x-api-key', apiKey);
      request.headers.set('anthropic-version', _anthropicVersion);
      request.headers.set('content-type', 'application/json');

      final body = jsonEncode({
        'model': model,
        'max_tokens': maxTokens,
        'system': systemPrompt,
        'messages': [
          {'role': 'user', 'content': userMessage},
        ],
      });

      final bodyBytes = utf8.encode(body);
      request.headers.contentLength = bodyBytes.length;
      request.add(bodyBytes);
      final response = await request.close();

      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        throw Exception(
          'Anthropic API error ${response.statusCode}: $responseBody',
        );
      }

      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final content = data['content'] as List<dynamic>;
      if (content.isEmpty) {
        throw Exception('Empty response from Anthropic API');
      }

      final firstBlock = content.first as Map<String, dynamic>;
      return firstBlock['text'] as String? ?? '';
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
    // True SSE streaming can be added in a later phase.
    final result = await complete(
      systemPrompt: systemPrompt,
      userMessage: userMessage,
    );
    yield result;
  }
}
