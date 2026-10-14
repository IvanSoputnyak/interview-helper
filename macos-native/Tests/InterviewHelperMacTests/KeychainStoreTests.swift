import Foundation
import Testing
import InterviewHelperCore

/// Each test uses its own throwaway Keychain service and deletes it afterwards; the user's real key is never touched.
private func withTestService(_ body: (String) throws -> Void) rethrows {
    let service = "com.interviewhelper.tests.\(UUID().uuidString)"
    defer { try? KeychainStore.deleteAPIKey(service: service) }
    try body(service)
}

@Suite("KeychainStore", .serialized)
struct KeychainStoreTests {
    @Test func test_loadAPIKey_whenNothingSaved_returnsNil() {
        withTestService { service in
            #expect(KeychainStore.loadAPIKey(service: service) == nil)
        }
    }

    @Test func test_saveThenLoad_returnsSavedKey() throws {
        try withTestService { service in
            try KeychainStore.saveAPIKey("sk-test-123", service: service)
            #expect(KeychainStore.loadAPIKey(service: service) == "sk-test-123")
        }
    }

    @Test func test_save_whenKeyPadded_storesTrimmedKey() throws {
        try withTestService { service in
            try KeychainStore.saveAPIKey("  sk-test-123 \n", service: service)
            #expect(KeychainStore.loadAPIKey(service: service) == "sk-test-123")
        }
    }

    @Test func test_save_whenKeyAlreadyExists_replacesIt() throws {
        try withTestService { service in
            try KeychainStore.saveAPIKey("sk-old", service: service)
            try KeychainStore.saveAPIKey("sk-new", service: service)
            #expect(KeychainStore.loadAPIKey(service: service) == "sk-new")
        }
    }

    @Test func test_save_whenKeyBlank_deletesExistingKey() throws {
        try withTestService { service in
            try KeychainStore.saveAPIKey("sk-test-123", service: service)
            try KeychainStore.saveAPIKey("   ", service: service)
            #expect(KeychainStore.loadAPIKey(service: service) == nil)
        }
    }

    @Test func test_delete_whenKeyExists_removesIt() throws {
        try withTestService { service in
            try KeychainStore.saveAPIKey("sk-test-123", service: service)
            try KeychainStore.deleteAPIKey(service: service)
            #expect(KeychainStore.loadAPIKey(service: service) == nil)
        }
    }

    @Test func test_delete_whenNothingSaved_doesNotThrow() throws {
        try withTestService { service in
            try KeychainStore.deleteAPIKey(service: service)
            #expect(KeychainStore.loadAPIKey(service: service) == nil)
        }
    }
}
