// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/test/providers/ golden fixtures. All displayed values are synthetic.
#if DEBUG
import DSHClient
import Foundation

@MainActor enum DebugProviderSettings {
    static let example = ConfigurableProvider(provider: "openrouter", displayName: "OpenRouter",
                                               settingsNs: "llm-pi-ai", defaultBaseURL: "https://openrouter.ai/api/v1")
    static var providers: [ConfigurableProvider] {
        DebugPageRegistry.argument("-dsh-screen-fixture") == "empty" ? [] : [example]
    }
    static let models: [ModelOption] = [
        ModelOption(provider: "deepseek-api", model: "deepseek-v4-flash", name: "DeepSeek V4 Flash"),
        ModelOption(provider: "openrouter", model: "example/model", name: "Example model"),
    ]
    static let sections: [EngineNamespace] = [
        EngineNamespace(["ns": "llm-pi-ai", "revision": 1, "value": [
            "providers": ["openrouter": ["baseURL": "https://openrouter.ai/api/v1", "api": "openai-completions",
                                         "apiKeyEnv": "OPENROUTER_API_KEY", "models": [
                                            ["id": "example/model", "name": "Example model",
                                             "contextWindow": 131_072, "maxTokens": 8_192]
                                         ]]]
        ]]),
        EngineNamespace(["ns": "agent-default-model", "revision": 1, "value": [
            "provider": "deepseek-api", "model": "deepseek-v4-flash", "rememberLastSelection": true
        ], "schema": ["type": "object", "dict": [
            "provider": ["type": "string"], "model": ["type": "string"],
            "reasoningEffort": ["type": "string"], "rememberLastSelection": ["type": "boolean"]
        ]]]),
    ]
}
#endif
