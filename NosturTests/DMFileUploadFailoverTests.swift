import Foundation
import Testing
@testable import Nostur

@MainActor
struct DMFileUploadFailoverTests {
    private let servers = ["https://primary.example", "https://second.example", "https://third.example"]

    @Test func failedPrimaryUsesNextServerAndStopsOnSuccess() async throws {
        var attempts: [String] = []
        let result = try await uploadDMFile(serverStrings: servers) { server in
            attempts.append(server.host!)
            if server.host == "primary.example" { throw BlossomUploadError.error("HTTP 403 — Forbidden") }
            return "https://second.example/encrypted-file"
        }
        #expect(result == "https://second.example/encrypted-file")
        #expect(attempts == ["primary.example", "second.example"])
    }

    @Test func healthyPrimaryDoesNotUploadToMirrors() async throws {
        var attempts = 0
        _ = try await uploadDMFile(serverStrings: servers) { _ in
            attempts += 1
            return "https://primary.example/encrypted-file"
        }
        #expect(attempts == 1)
    }

    @Test func allFailuresIncludeEachServerAndReason() async {
        var attempts: [String] = []
        do {
            _ = try await uploadDMFile(serverStrings: servers) { server in
                attempts.append(server.host!)
                throw BlossomUploadError.error("HTTP 403 — Forbidden")
            }
            Issue.record("All failed servers must produce an upload error")
        }
        catch {
            #expect(attempts == ["primary.example", "second.example", "third.example"])
            for server in attempts { #expect(error.localizedDescription.contains(server)) }
            #expect(error.localizedDescription.contains("HTTP 403"))
        }
    }

    @Test func invalidAndDuplicateServersAreSkipped() async throws {
        var attempts: [String] = []
        let result = try await uploadDMFile(serverStrings: ["bad URL", "ftp://invalid.example", servers[0], servers[0] + "/", servers[1]]) { server in
            attempts.append(server.host!)
            if server.host == "primary.example" { throw URLError(.timedOut) }
            return "success"
        }
        #expect(result == "success")
        #expect(attempts == ["primary.example", "second.example"])
    }

    @Test func cancellationDoesNotTryAnotherServer() async {
        var attempts = 0
        do {
            _ = try await uploadDMFile(serverStrings: servers) { _ in
                attempts += 1
                throw URLError(.cancelled)
            }
            Issue.record("Cancellation must be propagated")
        }
        catch {
            #expect(error is CancellationError)
            #expect(attempts == 1)
        }
    }
}
