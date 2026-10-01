/// The local models Keel suggests for Ollama, and the rule that picks a
/// default for the machine. One catalogue for the setup wizard and the
/// settings page so they never drift apart.
///
/// Sizes are Ollama's default quantisations. Keel's work is drafting and
/// rewriting prose over a long project context, which rewards a 12–14B
/// model on a 12 GB card over a 3B one; the small entries are for laptops.
library;

class OllamaModelInfo {
  final String id; // the `ollama pull` tag
  final String label;
  final String description;
  final String size;
  /// Approximate VRAM to run comfortably, in MiB.
  final int vramMiB;
  const OllamaModelInfo({
    required this.id,
    required this.label,
    required this.description,
    required this.size,
    required this.vramMiB,
  });
}

const List<OllamaModelInfo> kOllamaModels = [
  OllamaModelInfo(
    id: 'qwen3:14b',
    label: 'Qwen3 14B',
    description: 'Best all-rounder for a 12 GB card · strong prose and reasoning',
    size: '9 GB',
    vramMiB: 10500,
  ),
  OllamaModelInfo(
    id: 'qwen3:8b',
    label: 'Qwen3 8B',
    description: 'Fast · fits 8 GB cards · good drafts',
    size: '5 GB',
    vramMiB: 6500,
  ),
  OllamaModelInfo(
    id: 'gemma3:12b',
    label: 'Gemma 3 12B',
    description: 'Google · very natural writing · 128k context',
    size: '8 GB',
    vramMiB: 9500,
  ),
  OllamaModelInfo(
    id: 'phi4',
    label: 'Phi-4 14B',
    description: 'Microsoft · careful, structured output',
    size: '9 GB',
    vramMiB: 10500,
  ),
  OllamaModelInfo(
    id: 'qwen3:30b-a3b',
    label: 'Qwen3 30B (MoE)',
    description: 'Near-frontier quality · needs 32 GB RAM, spills off a 12 GB card',
    size: '19 GB',
    vramMiB: 20000,
  ),
  OllamaModelInfo(
    id: 'gemma3:4b',
    label: 'Gemma 3 4B',
    description: 'Laptops and CPUs · quick, lighter drafts',
    size: '3 GB',
    vramMiB: 4000,
  ),
];

/// The default to offer for a machine with [vramMiB] of GPU memory (null
/// when unknown, e.g. Apple silicon's unified memory or no GPU): the
/// largest catalogue model that fits, preferring Qwen3 at each size.
String recommendedOllamaModel({int? vramMiB, int? systemRamMiB}) {
  if (vramMiB == null) {
    // Unified memory or unknown: 16 GB+ of RAM runs the 14B, else the 8B.
    if (systemRamMiB != null && systemRamMiB >= 24000) return 'qwen3:14b';
    return 'qwen3:8b';
  }
  if (vramMiB >= 10500) return 'qwen3:14b';
  if (vramMiB >= 6500) return 'qwen3:8b';
  return 'gemma3:4b';
}

/// Qwen3 and DeepSeek-R1 families "think" before answering unless told
/// not to; for one-shot drafts that only burns time and tokens.
/// "qwen3:14b" → "qwen3 14b"; ":latest" is dropped as noise. Used wherever
/// the UI names the model that will answer (chat panel header, hints).
String ollamaModelLabel(String model) {
  final t = model.trim();
  if (t.isEmpty) return 'Ollama';
  final parts = t.split(':');
  if (parts.length == 1 || parts[1] == 'latest') return parts.first;
  return '${parts.first} ${parts.sublist(1).join(':')}';
}

bool ollamaModelThinks(String model) {
  final m = model.toLowerCase();
  return m.startsWith('qwen3') || m.contains('deepseek-r1') || m.contains('r1:');
}

/// Removes a `<think>…</think>` preamble a reasoning model may still emit.
String stripThinking(String text) {
  final re = RegExp(r'<think>[\s\S]*?</think>\s*', caseSensitive: false);
  return text.replaceAll(re, '').trimLeft();
}
