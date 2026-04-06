import 'llm_client.dart';
import 'claude_client.dart';
import 'openai_compatible_client.dart';
import 'ollama_client.dart';
import '../../providers/settings_provider.dart';

class LLMClientFactory {
  static LLMClient fromSettings(AppSettings settings) {
    switch (settings.llmProvider) {
      case LLMProvider.claudeApi:
        return ClaudeClient(
          apiKey: settings.claudeApiKey,
          model: settings.claudeModel,
        );
      case LLMProvider.openAi:
        return OpenAiCompatibleClient(
          baseUrl: 'https://api.openai.com/v1',
          apiKey: settings.openAiApiKey,
          model: settings.openAiModel,
        );
      case LLMProvider.grok:
        return OpenAiCompatibleClient(
          baseUrl: 'https://api.x.ai/v1',
          apiKey: settings.grokApiKey,
          model: settings.grokModel,
        );
      case LLMProvider.githubModels:
        return OpenAiCompatibleClient(
          baseUrl: 'https://models.inference.ai.azure.com',
          apiKey: settings.githubToken,
          model: settings.githubModel,
        );
      case LLMProvider.azureOpenAi:
        return OpenAiCompatibleClient(
          baseUrl: settings.azureEndpoint,
          apiKey: settings.azureApiKey,
          model: settings.azureModel,
          isAzure: true,
        );
      case LLMProvider.ollama:
        return OllamaClient(
          baseUrl: settings.ollamaBaseUrl,
          model: settings.ollamaModel,
        );
    }
  }
}
