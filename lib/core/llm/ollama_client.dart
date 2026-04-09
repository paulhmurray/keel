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

      // With stream:false, headers only arrive after full generation.
      // Allow 3 min for model load + inference.
      final response = await request.close()
          .timeout(const Duration(seconds: 180), onTimeout: () {
        throw Exception(
            'Ollama took too long to respond. The model may still be loading — try again in a moment.');
      });

      final responseBody = await response.transform(utf8.decoder).join()
          .timeout(const Duration(seconds: 30), onTimeout: () {
        throw Exception('Timed out reading Ollama response body.');
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
    final uri = Uri.parse('$baseUrl/api/chat');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(uri);
      request.headers.set('content-type', 'application/json');

      final bodyBytes = utf8.encode(jsonEncode({
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userMessage},
        ],
        'stream': true,
      }));
      request.headers.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      // Allow up to 60 s for the model to load before the first token arrives.
      // The TCP connection failure (Ollama not running) is caught earlier by
      // client.connectionTimeout = 10 s, which throws a SocketException.
      final response = await request.close()
          .timeout(const Duration(seconds: 60), onTimeout: () {
        throw Exception(
            'Ollama did not respond in time. The model may be loading — try again in a moment.');
      });

      if (response.statusCode != 200) {
        final body = await response.transform(utf8.decoder).join();
        throw Exception('Ollama API error ${response.statusCode}: $body');
      }

      // Parse NDJSON: each line is a JSON object with message.content
      final remainder = StringBuffer();
      await for (final chunk in response.transform(utf8.decoder)) {
        remainder.write(chunk);
        var text = remainder.toString();
        remainder.clear();
        while (text.contains('\n')) {
          final idx = text.indexOf('\n');
          final line = text.substring(0, idx).trim();
          text = text.substring(idx + 1);
          if (line.isEmpty) continue;
          try {
            final data = jsonDecode(line) as Map<String, dynamic>;
            final content =
                (data['message'] as Map<String, dynamic>?)?['content']
                    as String?;
            if (content != null && content.isNotEmpty) yield content;
            if (data['done'] == true) return;
          } catch (_) {
            // skip malformed line
          }
        }
        remainder.write(text);
      }
    } finally {
      client.close();
    }
  }

  /// Ensures Ollama is running. If not reachable, spawns `ollama serve` as a
  /// detached background process and polls until available or [timeoutSeconds]
  /// elapses. Returns true if Ollama is reachable after the attempt.
  static Future<bool> ensureRunning(
    String baseUrl, {
    int timeoutSeconds = 15,
  }) async {
    if (await isRunning(baseUrl)) return true;

    try {
      await Process.start(
        'ollama',
        ['serve'],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      // ollama binary not in PATH or couldn't start — fall through to poll
      // in case another mechanism (systemd etc.) is bringing it up.
    }

    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (await isRunning(baseUrl)) return true;
    }
    return false;
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
