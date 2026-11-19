import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/llm/ollama_client.dart';
import 'package:keel/core/llm/ollama_models.dart';

void main() {
  test('private install lives beside the app install, never inside it: '
      '~/.local/share/keel-ollama on Linux and macOS, %LOCALAPPDATA%\\Keel '
      'on Windows', () {
    expect(
      OllamaClient.keelLocalOllamaExe({'HOME': '/home/paulm'},
          isWindows: false),
      '/home/paulm/.local/share/keel-ollama/bin/ollama',
    );
    expect(
      OllamaClient.keelLocalOllamaExe(
          {'LOCALAPPDATA': r'C:\Users\p\AppData\Local'}, isWindows: true),
      r'C:\Users\p\AppData\Local\Keel\bin\ollama.exe',
    );
    // No HOME at all still yields a well-formed relative path, never a throw.
    expect(OllamaClient.keelLocalOllamaExe({}, isWindows: false),
        '/.local/share/keel-ollama/bin/ollama');
    // The updater swaps ~/.local/share/keel wholesale; the private Ollama
    // must not be under it.
    final env = {'HOME': '/home/paulm'};
    expect(
      OllamaClient.keelOllamaRoot(env, isWindows: false)
          .startsWith('${OllamaClient.legacyKeelOllamaRoot(env)}/'),
      isFalse,
    );
  });

  group('legacy in-app install', () {
    test('servers running from the legacy binary are stale, including one '
        'whose files an update deleted; nothing else is touched', () {
      const legacy = '/home/p/.local/share/keel';
      final pids = OllamaClient.staleOllamaPids({
        10: '/home/p/.local/share/keel/bin/ollama',
        11: '/home/p/.local/share/keel/bin/ollama (deleted)',
        12: '/usr/bin/ollama', // system install
        13: '/home/p/.local/share/keel/keel', // Keel itself
        14: '/home/p/.local/share/keel-ollama/bin/ollama', // new home
        // An update parked the old install; then the sweep deleted it.
        15: '/home/p/.local/share/.keel-old-1763300000000/bin/ollama',
        16: '/home/p/.local/share/.keel-old-1763300000000/bin/ollama '
            '(deleted)',
        17: '/home/p/.local/share/.keel-old-1/bin/ollama-other',
      }, legacy);
      expect(pids, [10, 11, 15, 16]);
    });

    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('ollama_mig'));
    tearDown(() async => tmp.delete(recursive: true));

    Future<void> seedLegacy(String root) async {
      await File('$root/bin/ollama').create(recursive: true);
      await File('$root/lib/ollama/llama-server').create(recursive: true);
      // The app's own libs share lib/ — they must stay put.
      await File('$root/lib/libapp.so').create(recursive: true);
    }

    test('moves bin/ollama and lib/ollama out, leaves the app alone',
        () async {
      final legacy = '${tmp.path}/keel', fresh = '${tmp.path}/keel-ollama';
      await seedLegacy(legacy);
      expect(
        await OllamaClient.migrateLegacyInstall(
            legacyRoot: legacy, newRoot: fresh),
        isTrue,
      );
      expect(File('$fresh/bin/ollama').existsSync(), isTrue);
      expect(File('$fresh/lib/ollama/llama-server').existsSync(), isTrue);
      expect(File('$legacy/bin/ollama').existsSync(), isFalse);
      expect(Directory('$legacy/lib/ollama').existsSync(), isFalse);
      expect(File('$legacy/lib/libapp.so').existsSync(), isTrue);
    });

    test('no legacy copy, or one already in the new home: nothing moves',
        () async {
      final legacy = '${tmp.path}/keel', fresh = '${tmp.path}/keel-ollama';
      expect(
        await OllamaClient.migrateLegacyInstall(
            legacyRoot: legacy, newRoot: fresh),
        isFalse,
      );
      await seedLegacy(legacy);
      await File('$fresh/bin/ollama').create(recursive: true);
      expect(
        await OllamaClient.migrateLegacyInstall(
            legacyRoot: legacy, newRoot: fresh),
        isFalse,
      );
      expect(File('$legacy/bin/ollama').existsSync(), isTrue);
    });

    test('an update from an older Keel parks Ollama with the old app; '
        'it is found there, newest first', () async {
      final legacy = '${tmp.path}/keel', fresh = '${tmp.path}/keel-ollama';
      await Directory(legacy).create();
      await seedLegacy('${tmp.path}/.keel-old-100');
      await seedLegacy('${tmp.path}/.keel-old-200');
      await Directory('${tmp.path}/.keel-staging-300').create();
      final parked = await OllamaClient.parkedInstalls(legacy);
      expect(parked, ['${tmp.path}/.keel-old-200', '${tmp.path}/.keel-old-100']);
      expect(
        await OllamaClient.migrateLegacyInstall(
            legacyRoot: parked.first, newRoot: fresh),
        isTrue,
      );
      expect(File('$fresh/lib/ollama/llama-server').existsSync(), isTrue);
    });
  });

  test('macOS looks for the official app\'s CLI, never a loose copy', () {
    final c = OllamaClient.macOllamaCandidates({'HOME': '/Users/sam'});
    expect(c, [
      '/opt/homebrew/bin/ollama',
      '/usr/local/bin/ollama',
      '/Applications/Ollama.app/Contents/Resources/ollama',
      '/Users/sam/Applications/Ollama.app/Contents/Resources/ollama',
    ]);
  });

  test('recommendation fits the card: 12 GB → 14B, 8 GB → 8B, small → 4B', () {
    expect(recommendedOllamaModel(vramMiB: 12288), 'qwen3:14b');
    expect(recommendedOllamaModel(vramMiB: 8192), 'qwen3:8b');
    expect(recommendedOllamaModel(vramMiB: 4096), 'gemma3:4b');
    // Unknown GPU (Apple silicon / none): go by RAM.
    expect(recommendedOllamaModel(systemRamMiB: 32768), 'qwen3:14b');
    expect(recommendedOllamaModel(systemRamMiB: 16384), 'qwen3:8b');
    expect(recommendedOllamaModel(), 'qwen3:8b');
  });

  test('catalogue entries are unique and every recommendation is in it', () {
    final ids = kOllamaModels.map((m) => m.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final v in [12288, 8192, 4096]) {
      expect(ids, contains(recommendedOllamaModel(vramMiB: v)));
    }
  });

  test('reasoning families are asked not to think; others are left alone', () {
    expect(ollamaModelThinks('qwen3:14b'), isTrue);
    expect(ollamaModelThinks('deepseek-r1:14b'), isTrue);
    expect(ollamaModelThinks('gemma3:12b'), isFalse);
    expect(stripThinking('<think>\nhmm\n</think>\nIf the vendor slips…'),
        'If the vendor slips…');
    expect(stripThinking('plain'), 'plain');
  });

  test('chat body raises the context window and keeps the model warm', () {
    final body = OllamaClient.buildChatBody(
        model: 'qwen3:14b', systemPrompt: 'S', userMessage: 'U', stream: false, maxTokens: 400);
    expect(body['think'], isFalse);
    expect(body['keep_alive'], '30m');
    final opts = body['options'] as Map;
    expect(opts['num_ctx'], 16384);
    expect(opts['num_predict'], 400);
    final gemma = OllamaClient.buildChatBody(
        model: 'gemma3:12b', systemPrompt: 'S', userMessage: 'U', stream: true);
    expect(gemma.containsKey('think'), isFalse);
    expect((gemma['options'] as Map).containsKey('num_predict'), isFalse);
  });
  _resolutionTests();
  _labelTests();
}


// ── Model resolution against what is actually installed ─────────────────
void _resolutionTests() {
  test('a stale configured model resolves to what is installed', () {
    expect(OllamaClient.pickInstalledModel('llama3.2:3b', ['qwen3:14b']), 'qwen3:14b');
    expect(OllamaClient.pickInstalledModel('qwen3:14b', ['qwen3:14b', 'gemma3:12b']), 'qwen3:14b');
    // Same family wins over first-installed.
    expect(OllamaClient.pickInstalledModel('qwen3:8b', ['gemma3:12b', 'qwen3:14b']), 'qwen3:14b');
    // ":latest" spelling differences are the same model.
    expect(OllamaClient.pickInstalledModel('phi4', ['phi4:latest']), 'phi4:latest');
    expect(OllamaClient.pickInstalledModel('anything', const []), isNull);
  });
}


void _labelTests() {
  test('model label names the installed tag the way a person would', () {
    expect(ollamaModelLabel('qwen3:14b'), 'qwen3 14b');
    expect(ollamaModelLabel('phi4:latest'), 'phi4');
    expect(ollamaModelLabel('phi4'), 'phi4');
    expect(ollamaModelLabel(''), 'Ollama');
  });
}
