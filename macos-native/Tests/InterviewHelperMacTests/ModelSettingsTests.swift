import Foundation
import Testing
@testable import InterviewHelperCore

/// Each test gets its own throwaway UserDefaults suite (disk boundary), never `.standard`.
private func makeDefaults() -> UserDefaults {
    let suite = "ih-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Suite("ModelSettings")
struct ModelSettingsTests {
    @Test func test_load_whenNothingStored_usesDefaultModel() {
        #expect(ModelSettings.load(from: makeDefaults()).model == OpenAIAnalyzer.defaultModel)
    }

    @Test func test_load_whenNothingStored_hasNoReasoningEffort() {
        #expect(ModelSettings.load(from: makeDefaults()).reasoningEffort == nil)
    }

    @Test func test_load_whenEffortStored_returnsIt() {
        let defaults = makeDefaults()
        defaults.set("high", forKey: ModelSettings.reasoningEffortKey)
        #expect(ModelSettings.load(from: defaults).reasoningEffort == .high)
    }

    @Test func test_load_whenStoredEffortUnknown_treatsAsDefault() {
        let defaults = makeDefaults()
        defaults.set("turbo", forKey: ModelSettings.reasoningEffortKey)
        #expect(ModelSettings.load(from: defaults).reasoningEffort == nil)
    }

    @Test func test_load_whenRetiredDefaultModelStored_usesCurrentDefault() {
        let defaults = makeDefaults()
        defaults.set("gpt-4.1-mini", forKey: ModelSettings.modelKey)
        #expect(ModelSettings.load(from: defaults).model == OpenAIAnalyzer.defaultModel)
    }

    @Test func test_save_whenModelIsDefault_removesStoredModel() {
        let defaults = makeDefaults()
        defaults.set("gpt-6-astra", forKey: ModelSettings.modelKey)
        ModelSettings.save(model: OpenAIAnalyzer.defaultModel, reasoningEffort: nil, to: defaults)
        #expect(defaults.string(forKey: ModelSettings.modelKey) == nil)
    }

    @Test func test_save_whenModelIsBlank_removesStoredModel() {
        let defaults = makeDefaults()
        defaults.set("gpt-6-astra", forKey: ModelSettings.modelKey)
        ModelSettings.save(model: "   ", reasoningEffort: nil, to: defaults)
        #expect(defaults.string(forKey: ModelSettings.modelKey) == nil)
    }

    @Test func test_save_whenEffortIsDefault_removesStoredEffort() {
        let defaults = makeDefaults()
        defaults.set("high", forKey: ModelSettings.reasoningEffortKey)
        ModelSettings.save(model: OpenAIAnalyzer.defaultModel, reasoningEffort: nil, to: defaults)
        #expect(defaults.string(forKey: ModelSettings.reasoningEffortKey) == nil)
    }

    @Test func test_saveThenLoad_withCustomValues_roundTrips() {
        let defaults = makeDefaults()
        ModelSettings.save(model: " gpt-6-astra ", reasoningEffort: .low, to: defaults)
        #expect(ModelSettings.load(from: defaults) == ModelSettings(model: "gpt-6-astra", reasoningEffort: .low))
    }
}
