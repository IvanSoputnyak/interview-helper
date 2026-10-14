import Foundation
import Testing
import InterviewHelperCore

/// Each test gets its own throwaway UserDefaults suite, never `.standard`.
private func makeDefaults() -> UserDefaults {
    let suite = "ih-history-size-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Suite("History size setting")
struct HistorySizeTests {
    @Test func test_maxItems_whenNothingStored_returnsDefault() {
        #expect(QAStore.maxItems(from: makeDefaults()) == QAStore.defaultMaxItems)
    }

    @Test func test_maxItems_whenValueStored_returnsIt() {
        let defaults = makeDefaults()
        defaults.set(100, forKey: QAStore.maxItemsDefaultsKey)
        #expect(QAStore.maxItems(from: defaults) == 100)
    }

    @Test(arguments: [0, -5])
    func test_maxItems_whenStoredValueNotPositive_returnsDefault(stored: Int) {
        let defaults = makeDefaults()
        defaults.set(stored, forKey: QAStore.maxItemsDefaultsKey)
        #expect(QAStore.maxItems(from: defaults) == QAStore.defaultMaxItems)
    }

    @Test func test_maxItems_whenStoredValueAboveLimit_returnsLimit() {
        let defaults = makeDefaults()
        defaults.set(9_999, forKey: QAStore.maxItemsDefaultsKey)
        #expect(QAStore.maxItems(from: defaults) == QAStore.maxItemsLimit)
    }

    @Test func test_saveMaxItems_whenDefault_removesStoredValue() {
        let defaults = makeDefaults()
        defaults.set(100, forKey: QAStore.maxItemsDefaultsKey)
        QAStore.saveMaxItems(QAStore.defaultMaxItems, to: defaults)
        #expect(defaults.object(forKey: QAStore.maxItemsDefaultsKey) == nil)
    }

    @Test func test_saveMaxItems_whenCustom_storesIt() {
        let defaults = makeDefaults()
        QAStore.saveMaxItems(100, to: defaults)
        #expect(defaults.integer(forKey: QAStore.maxItemsDefaultsKey) == 100)
    }

    @Test func test_saveMaxItems_whenZero_storesMinimum() {
        let defaults = makeDefaults()
        QAStore.saveMaxItems(0, to: defaults)
        #expect(defaults.integer(forKey: QAStore.maxItemsDefaultsKey) == QAStore.minItems)
    }

    @Test func test_saveMaxItems_whenAboveLimit_storesLimit() {
        let defaults = makeDefaults()
        QAStore.saveMaxItems(9_999, to: defaults)
        #expect(defaults.integer(forKey: QAStore.maxItemsDefaultsKey) == QAStore.maxItemsLimit)
    }

    @Test(arguments: [1, 26, 500])
    func test_saveThenLoad_withValidSize_roundTrips(size: Int) {
        let defaults = makeDefaults()
        QAStore.saveMaxItems(size, to: defaults)
        #expect(QAStore.maxItems(from: defaults) == size)
    }
}
