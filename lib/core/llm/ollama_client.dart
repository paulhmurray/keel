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
        'AI assistant → Set up Ollama to download one.',
      );
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
      final response = await request.close().timeout(
        const Duration(seconds: 180),
        onTimeout: () {
          throw Exception(
            'Ollama took too long to respond. The model may still be loading — try again in a moment.',
          );
        },
      );

      final responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Timed out reading Ollama response body.');
            },
          );

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

      final bodyBytes = utf8.encode(
        jsonEncode(
          buildChatBody(
            model: await _resolveModel(),
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            stream: true,
          ),
        ),
      );
      request.headers.contentLength = bodyBytes.length;
      request.add(bodyBytes);

      // Allow up to 60 s for the model to load before the first token arrives.
      // The TCP connection failure (Ollama not running) is caught earlier by
      // client.connectionTimeout = 10 s, which throws a SocketException.
      final response = await request.close().timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw Exception(
            'Ollama did not respond in time. The model may be loading — try again in a moment.',
          );
        },
      );

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
  }) => {
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

  /// Root of Keel's private Ollama (the wizard extracts `bin/ollama` +
  /// `lib/ollama/*` here): `~/.local/share/keel-ollama` on Linux/macOS,
  /// `%LOCALAPPDATA%\Keel` on Windows.
  ///
  /// Deliberately a SIBLING of the app install (`~/.local/share/keel`),
  /// never inside it: the self-updater swaps that whole directory out, so
  /// an Ollama living there vanished on every update and the server left
  /// running from the deleted files failed every chat with
  /// "llama-server binary not found".
  static String keelOllamaRoot(
    Map<String, String> env, {
    required bool isWindows,
  }) {
    if (isWindows) return '${env['LOCALAPPDATA'] ?? ''}\\Keel';
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
    return '$home/.local/share/keel-ollama';
  }

  /// Where earlier Keels put the private Ollama on Linux: inside the app
  /// install. Migrated away from by [prepareLocalInstall].
  static String legacyKeelOllamaRoot(Map<String, String> env) {
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
    return '$home/.local/share/keel';
  }

  /// Where the setup wizard puts Keel's private Ollama when there is no
  /// system install. Pure so the path rule is unit-tested;
  /// [resolveOllamaExe] checks the file exists.
  static String keelLocalOllamaExe(
    Map<String, String> env, {
    required bool isWindows,
  }) {
    final root = keelOllamaRoot(env, isWindows: isWindows);
    return isWindows ? '$root\\bin\\ollama.exe' : '$root/bin/ollama';
  }

  /// Pids of Ollama servers running from the legacy in-app location
  /// [legacyRoot] — or from a copy of it an in-app update parked beside it
  /// (`.keel-old-<ms>`, swept on the next launch) — given each process's
  /// `/proc/<pid>/exe` link target. The kernel appends " (deleted)" once
  /// the file is gone, and those are exactly the servers that answer
  /// /api/tags but fail every model load. Pure.
  static List<int> staleOllamaPids(
    Map<int, String> exeByPid,
    String legacyRoot,
  ) {
    final parent = legacyRoot.substring(0, legacyRoot.lastIndexOf('/'));
    final pattern = RegExp(
      '^(?:${RegExp.escape(legacyRoot)}|${RegExp.escape(parent)}/\\.keel-old-[^/]+)'
      r'/bin/ollama(?: \(deleted\))?$',
    );
    return [
      for (final e in exeByPid.entries)
        if (pattern.hasMatch(e.value)) e.key,
    ];
  }

  /// Copies of the app install an in-app update parked beside
  /// [legacyRoot], newest first. An update from a Keel that kept Ollama
  /// inside the install carries Ollama into the parked copy, so this is
  /// where it is rescued from before the launch sweep deletes it.
  static Future<List<String>> parkedInstalls(String legacyRoot) async {
    final parent = Directory(
      legacyRoot.substring(0, legacyRoot.lastIndexOf('/')),
    );
    final found = <(int, String)>[];
    try {
      await for (final e in parent.list(followLinks: false)) {
        final name = e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
        final m = RegExp(r'^\.keel-old-(\d+)$').firstMatch(name);
        if (e is Directory && m != null) {
          found.add((int.parse(m.group(1)!), e.path.replaceAll(RegExp(r'/$'), '')));
        }
      }
    } catch (_) {}
    found.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final f in found) f.$2];
  }

  /// Moves a private Ollama from [legacyRoot] (`bin/ollama` +
  /// `lib/ollama`) to [newRoot], unless [newRoot] already has one.
  /// Returns true when something moved. A failed move (e.g. another
  /// filesystem) leaves the legacy copy where it is — [resolveOllamaExe]
  /// still finds it there — so this never strands the user.
  static Future<bool> migrateLegacyInstall({
    required String legacyRoot,
    required String newRoot,
  }) async {
    final legacyExe = File('$legacyRoot/bin/ollama');
    if (!await legacyExe.exists()) return false;
    if (await File('$newRoot/bin/ollama').exists()) return false;
    try {
      await Directory('$newRoot/bin').create(recursive: true);
      await Directory('$newRoot/lib').create(recursive: true);
      await legacyExe.rename('$newRoot/bin/ollama');
      final legacyLib = Directory('$legacyRoot/lib/ollama');
      if (await legacyLib.exists()) {
        await legacyLib.rename('$newRoot/lib/ollama');
      }
      return true;
    } catch (_) {
      // Half-moved? Put the binary back so the legacy copy stays whole.
      try {
        final moved = File('$newRoot/bin/ollama');
        if (await moved.exists() && !await legacyExe.exists()) {
          await moved.rename(legacyExe.path);
        }
      } catch (_) {}
      return false;
    }
  }

  static bool _prepared = false;

  /// Linux, once per launch: stops any server still running from the
  /// legacy in-app location (or a parked copy of it), then moves the
  /// legacy Ollama — from the install, or from the copy an update just
  /// parked — to [keelOllamaRoot], so [ensureRunning] starts a working
  /// one. Must run BEFORE [sweepOldInstalls]. Best effort.
  static Future<void> prepareLocalInstall() async {
    if (_prepared || !Platform.isLinux) return;
    _prepared = true;
    final env = Platform.environment;
    final legacyRoot = legacyKeelOllamaRoot(env);
    try {
      final exeByPid = <int, String>{};
      await for (final e in Directory('/proc').list(followLinks: false)) {
        final pid = int.tryParse(e.uri.pathSegments.lastWhere(
          (s) => s.isNotEmpty,
          orElse: () => '',
        ));
        if (pid == null) continue;
        try {
          exeByPid[pid] = await Link('/proc/$pid/exe').target();
        } catch (_) {} // other users' processes, or already exited
      }
      final stale = staleOllamaPids(exeByPid, legacyRoot);
      for (final pid in stale) {
        Process.killPid(pid);
      }
      if (stale.isNotEmpty) {
        // Let the port free up before anyone starts a fresh server.
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    } catch (_) {}
    final newRoot = keelOllamaRoot(env, isWindows: false);
    for (final from in [legacyRoot, ...await parkedInstalls(legacyRoot)]) {
      if (await migrateLegacyInstall(legacyRoot: from, newRoot: newRoot)) {
        break;
      }
    }
  }

  /// Where the official macOS Ollama leaves its command-line binary.
  /// Keel never runs a CLI it extracted itself on a Mac: Ollama's own app
  /// is signed and notarized, a loose copy is quarantined and blocked.
  static List<String> macOllamaCandidates(Map<String, String> env) {
    final home = env['HOME'] ?? '';
    return [
      '/opt/homebrew/bin/ollama',
      '/usr/local/bin/ollama',
      '/Applications/Ollama.app/Contents/Resources/ollama',
      '$home/Applications/Ollama.app/Contents/Resources/ollama',
    ];
  }

  /// The executable to launch: a system `ollama` on PATH first, else
  /// Keel's private install, else the bare name (which fails gracefully).
  ///
  /// The wizard, the settings warm-up and the chat panel all go through
  /// this, so a private install started once by the wizard comes back
  /// after a reboot instead of stranding the user at "run setup again".
  static Future<String> resolveOllamaExe() async {
    try {
      final r = await Process.run(Platform.isWindows ? 'where' : 'which', [
        'ollama',
      ]);
      if (r.exitCode == 0) return 'ollama';
    } catch (_) {}
    if (Platform.isMacOS) {
      for (final c in macOllamaCandidates(Platform.environment)) {
        if (await File(c).exists()) return c;
      }
    }
    final local = keelLocalOllamaExe(
      Platform.environment,
      isWindows: Platform.isWindows,
    );
    if (await File(local).exists()) return local;
    if (!Platform.isWindows) {
      // Not yet migrated (or the move failed) — still usable in place.
      final legacy = '${legacyKeelOllamaRoot(Platform.environment)}/bin/ollama';
      if (await File(legacy).exists()) return legacy;
    }
    return 'ollama';
  }

  /// Ensures Ollama is running. If not reachable, spawns `ollama serve` as a
  /// detached background process and polls until available or [timeoutSeconds]
  /// elapses. Returns true if Ollama is reachable after the attempt.
  static Future<bool> ensureRunning(
    String baseUrl, {
    int timeoutSeconds = 15,
  }) async {
    await prepareLocalInstall();
    if (await isRunning(baseUrl)) return true;

    try {
      await Process.start(await resolveOllamaExe(), [
        'serve',
      ], mode: ProcessStartMode.detached);
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
