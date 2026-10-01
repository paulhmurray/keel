import 'dart:convert';
import 'dart:io';
import 'llm_client.dart';
import 'ollama_models.dart';

class OllamaClient implements LLMClient {
  final String baseUrl; // default 'http://localhost:11434'
  final String model;

  const OllamaClient({
    this.baseUrl = 'http://localhost:11434',
    required this.model,
  });

  // Installed-model cache per server, so resolving the model costs one
  // /api/tags call a minute rather than one per draft. Only a hit that
  // contains the configured model is trusted: a miss (the user may have
  // just pulled the model in the wizard) or an empty list re-fetches.
  static final Map<String, (DateTime, List<String>)> _tagsCache = {};

  static Future<List<String>> _installed(String baseUrl, String wanted) async {
    final hit = _tagsCache[baseUrl];
    if (hit != null &&
        hit.$2.contains(wanted) &&
        DateTime.now().difference(hit.$1) < const Duration(seconds: 60)) {
      return hit.$2;
    }
    final models = await getAvailableModels(baseUrl);
    if (models.isNotEmpty) _tagsCache[baseUrl] = (DateTime.now(), models);
    return models;
  }

  /// Which installed model to actually run. The configured name when it
  /// is installed; otherwise the nearest installed relative (same family
  /// before the colon), otherwise whatever is installed — a stale setting
  /// left over from an old default must never fail a draft while a
  /// perfectly good model sits on the machine. Null when nothing is
  /// installed at all.
  static String? pickInstalledModel(String configured, List<String> installed) {
    if (installed.isEmpty) return null;
    if (installed.contains(configured)) return configured;
    // Ollama lists "qwen3:14b" for a pull of "qwen3:14b" and "phi4:latest"
    // for "phi4" — match on the tag with and without ":latest".
    for (final m in installed) {
      if (m == '$configured:latest' || '$m:latest' == configured) return m;
    }
    final family = configured.split(':').first.toLowerCase();
    for (final m in installed) {
      if (m.split(':').first.toLowerCase() == family) return m;
    }
    return installed.first;
  }

  Future<String> _resolveModel() async {
    final installed = await _installed(baseUrl, model);
    final picked = pickInstalledModel(model, installed);
    if (picked == null) {
      throw Exception(
          'No models found on the Ollama server at $baseUrl. Open Settings → '
          'AI assistant → Set up Ollama to download one.');
    }
    return picked;
  }

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

      final bodyMap = buildChatBody(
        model: await _resolveModel(),
        systemPrompt: systemPrompt,
        userMessage: userMessage,
        stream: false,
        maxTokens: maxTokens,
      );

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
      return stripThinking(message['content'] as String? ?? '');
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

      final bodyBytes = utf8.encode(jsonEncode(buildChatBody(
        model: await _resolveModel(),
        systemPrompt: systemPrompt,
        userMessage: userMessage,
        stream: true,
      )));
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

  /// The /api/chat body. Keel's system prompt carries the whole project
  /// context, so the context window is raised well past Ollama's 4k
  /// default; reasoning models are told not to think aloud; the model is
  /// kept warm for half an hour so consecutive drafts don't reload it.
  static Map<String, dynamic> buildChatBody({
    required String model,
    required String systemPrompt,
    required String userMessage,
    required bool stream,
    int? maxTokens,
  }) =>
      {
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userMessage},
        ],
        'stream': stream,
        'keep_alive': '30m',
        if (ollamaModelThinks(model)) 'think': false,
        'options': {
          'num_ctx': 16384,
          'num_predict': ?maxTokens,
          'temperature': 0.4,
        },
      };

  /// Where the setup wizard puts Keel's private Ollama when there is no
  /// system install: `~/.local/share/keel/bin/ollama` on Linux/macOS,
  /// `%LOCALAPPDATA%\Keel\bin\ollama.exe` on Windows. Pure so the path
  /// rule is unit-tested; [resolveOllamaExe] checks the file exists.
  static String keelLocalOllamaExe(Map<String, String> env,
      {required bool isWindows}) {
    if (isWindows) return '${env['LOCALAPPDATA'] ?? ''}\\Keel\\bin\\ollama.exe';
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
    return '$home/.local/share/keel/bin/ollama';
  }

  /// The executable to launch: a system `ollama` on PATH first, else
  /// Keel's private install, else the bare name (which fails gracefully).
  ///
  /// The wizard, the settings warm-up and the chat panel all go through
  /// this, so a private install started once by the wizard comes back
  /// after a reboot instead of stranding the user at "run setup again".
  static Future<String> resolveOllamaExe() async {
    try {
      final r = await Process.run(
          Platform.isWindows ? 'where' : 'which', ['ollama']);
      if (r.exitCode == 0) return 'ollama';
    } catch (_) {}
    final local = keelLocalOllamaExe(Platform.environment,
        isWindows: Platform.isWindows);
    if (await File(local).exists()) return local;
    return 'ollama';
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
        await resolveOllamaExe(),
        ['serve'],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      // No binary on PATH or in Keel's install, or it couldn't start — fall
      // through to poll in case another mechanism (systemd etc.) is bringing
      // it up.
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
