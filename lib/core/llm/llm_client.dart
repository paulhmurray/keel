abstract class LLMClient {
  Future<String> complete({
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 1000,
  });

  Stream<String> stream({
    required String systemPrompt,
    required String userMessage,
  });
}
