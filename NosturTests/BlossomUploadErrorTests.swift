import Foundation
import Testing
@testable import Nostur

struct BlossomUploadErrorTests {
    private let url = URL(string: "https://media.example/upload")!

    @Test func forbiddenResponseKeepsHTTPStatusAndHeaderReason() throws {
        let response = try #require(HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil,
                                                  headerFields: ["X-Reason": "Uploads blocked for this IP"]))
        do {
            _ = try blossomUploadURL(data: Data("<html>Forbidden</html>".utf8), response: response)
            Issue.record("A forbidden upload must fail")
        }
        catch {
            #expect(error.localizedDescription.contains("HTTP 403"))
            #expect(error.localizedDescription.contains("Uploads blocked for this IP"))
            #expect(!error.localizedDescription.contains("NSURLErrorDomain"))
        }
    }

    @Test func apacheForbiddenPageUsesHTTPReasonWithoutShowingHTML() throws {
        let response = try #require(HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil))
        do {
            _ = try blossomUploadURL(data: Data("<html>Forbidden</html>".utf8), response: response)
            Issue.record("A forbidden upload must fail")
        }
        catch {
            #expect(error.localizedDescription.contains("HTTP 403"))
            #expect(error.localizedDescription.contains(HTTPURLResponse.localizedString(forStatusCode: 403)))
            #expect(!error.localizedDescription.contains("<html>"))
        }
    }

    @Test func serverJSONErrorSurvives() throws {
        let response = try #require(HTTPURLResponse(url: url, statusCode: 413, httpVersion: nil, headerFields: nil))
        do {
            _ = try blossomUploadURL(data: Data(#"{"message":"File exceeds the upload limit"}"#.utf8), response: response)
            Issue.record("An oversized upload must fail")
        }
        catch {
            #expect(error.localizedDescription.contains("HTTP 413"))
            #expect(error.localizedDescription.contains("File exceeds the upload limit"))
        }
    }

    @Test func successfulUploadStillReturnsDownloadURL() throws {
        let response = try #require(HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: nil))
        let data = Data(#"{"sha256":"abcd","size":4,"uploaded":1,"url":"https://media.example/abcd"}"#.utf8)
        #expect(try blossomUploadURL(data: data, response: response) == "https://media.example/abcd")
    }
}
