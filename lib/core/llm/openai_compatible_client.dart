import 'dart:convert';
import 'dart:io';
import 'llm_client.dart';

class OpenAiCompatibleClient implements LLMClient {
  final String baseUrl; // e.g. 'https://api.openai.com/v1'
  final String apiKey;
  final String model;
  final bool isAzure; // Azure uses 'api-key' header instead of 'Bearer'

  const OpenAiCompatibleClient({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.isAzure = false,
  });

  @override
  Future<String> complete({
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 1000,
  }) async {
    final uri = isAzure
        ? Uri.parse(
            '$baseUrl/openai/deployments/$model/chat/completions?api-version=2024-05-01-preview')
        : Uri.parse('$baseUrl/chat/completions');

    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);

      if (isAzure) {
        request.headers.set('api-key', apiKey);
      } else {
        request.headers.set('Authorization', 'Bearer $apiKey');
      }
      request.headers.set('content-type', 'application/json');

      final bodyMap = <String, dynamic>{
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userMessage},
        ],
        'max_tokens': maxTokens,
      };
      // Azure: model is in the URL, not the body
      if (!isAzure) {
        bodyMap['model'] = model;
      }

      final bodyBytes = utf8.encode(jsonEncode(bodyMap));
      request.headers.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        throw Exception(
          'OpenAI-compatible API error ${response.statusCode}: $responseBody',
        );
      }

      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>;
      if (choices.isEmpty) {
        throw Exception('Empty choices in API response');
      }
      final message = choices[0]['message'] as Map<String, dynamic>;
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
}
