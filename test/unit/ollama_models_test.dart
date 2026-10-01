import 'package:flutter_test/flutter_test.dart';
import 'package:keel/core/llm/ollama_client.dart';
import 'package:keel/core/llm/ollama_models.dart';

void main() {
  test('private install path follows the wizard: ~/.local/share/keel on '
      'Linux and macOS, %LOCALAPPDATA%\\Keel on Windows', () {
    expect(
      OllamaClient.keelLocalOllamaExe({'HOME': '/home/paulm'},
          isWindows: false),
      '/home/paulm/.local/share/keel/bin/ollama',
    );
    expect(
      OllamaClient.keelLocalOllamaExe(
          {'LOCALAPPDATA': r'C:\Users\p\AppData\Local'}, isWindows: true),
      r'C:\Users\p\AppData\Local\Keel\bin\ollama.exe',
    );
    // No HOME at all still yields a well-formed relative path, never a throw.
    expect(OllamaClient.keelLocalOllamaExe({}, isWindows: false),
        '/.local/share/keel/bin/ollama');
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
