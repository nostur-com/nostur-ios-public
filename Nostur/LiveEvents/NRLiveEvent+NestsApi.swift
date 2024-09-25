//
//  NRLiveEvent+NestsApi.swift
//  Nostur
//
//  Created by Fabian Lachman on 15/09/2024.
//

import SwiftUI
import LiveKit

// MARK: NESTS API - https://github.com/nostrnests/nests/blob/main/API.md
extension NRLiveEvent {
    
    private var roomId: String {
        self.dTag
    }

    // MARK: - Join Room

    @MainActor
    public func joinRoom(account: CloudAccount) async throws -> JoinRoomResponse {
        guard let baseURL = liveKitBaseUrl else { throw NSError(domain: "Invalid baseURL", code: 400, userInfo: nil) }
        let urlString = baseURL + "/api/v1/nests/\(roomId)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 400, userInfo: nil)
        }

        let authorizationHeader = try await createAuthorizationHeader(account: account, urlString: urlString, method: "GET")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(authorizationHeader, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                let joinRoomResponse = try decoder.decode(JoinRoomResponse.self, from: data)
                return joinRoomResponse
            default:
                let errorMessage = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                throw NSError(domain: errorMessage, code: httpResponse.statusCode, userInfo: nil)
            }
        } else {
            throw NSError(domain: "Invalid Response", code: 500, userInfo: nil)
        }
    }

    // MARK: - Update Permissions

    @MainActor
    public func updatePermissions(account: CloudAccount, participantPubKey: String, canPublish: Bool? = nil, muteMicrophone: Bool? = nil, isAdmin: Bool? = nil) async throws {
        guard let baseURL = liveKitBaseUrl else { throw NSError(domain: "Invalid baseURL", code: 400, userInfo: nil) }
        let urlString = baseURL + "/api/v1/nests/\(roomId)/permissions"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 400, userInfo: nil)
        }

        let authorizationHeader = try await createAuthorizationHeader(account: account, urlString: urlString, method: "POST")

        var body: [String: Any] = ["participant": participantPubKey]

        if let canPublish = canPublish {
            body["can_publish"] = canPublish
        }

        if let muteMicrophone = muteMicrophone {
            body["mute_microphone"] = muteMicrophone
        }

        if let isAdmin = isAdmin {
            body["is_admin"] = isAdmin
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body, options: [])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 201:
                print("Permissions updated successfully")
            case 204:
                print("No changes were made")
            case 400:
                throw NSError(domain: "Bad Request", code: 400, userInfo: nil)
            case 401:
                throw NSError(domain: "Unauthorized", code: 401, userInfo: nil)
            case 404:
                throw NSError(domain: "Room Not Found", code: 404, userInfo: nil)
            default:
                throw NSError(domain: "Unexpected Error", code: httpResponse.statusCode, userInfo: nil)
            }
        } else {
            throw NSError(domain: "Invalid Response", code: 500, userInfo: nil)
        }
    }

    // MARK: - Get Room Info

    @MainActor
    public func getRoomInfo() async throws -> LiveKitRoomMetaData {
        guard let baseURL = liveKitBaseUrl else { throw NSError(domain: "Invalid baseURL", code: 400, userInfo: nil) }
        let urlString = baseURL + "/api/v1/nests/\(roomId)/info"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 400, userInfo: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                let roomInfoResponse = try decoder.decode(LiveKitRoomMetaData.self, from: data)
                return roomInfoResponse
            default:
                let errorMessage = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                throw NSError(domain: errorMessage, code: httpResponse.statusCode, userInfo: nil)
            }
        } else {
            throw NSError(domain: "Invalid Response", code: 500, userInfo: nil)
        }
    }

    // MARK: - Start Recording

    @MainActor
    public func startRecording(account: CloudAccount) async throws {
        guard let baseURL = liveKitBaseUrl else { throw NSError(domain: "Invalid baseURL", code: 400, userInfo: nil) }
        let urlString = baseURL + "/api/v1/nests/\(roomId)/recording"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 400, userInfo: nil)
        }

        let authorizationHeader = try await createAuthorizationHeader(account: account, urlString: urlString, method: "POST")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(authorizationHeader, forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 201:
                print("Recording started successfully")
            default:
                let errorMessage = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                throw NSError(domain: errorMessage, code: httpResponse.statusCode, userInfo: nil)
            }
        } else {
            throw NSError(domain: "Invalid Response", code: 500, userInfo: nil)
        }
    }

    // MARK: - Stop Recording

    @MainActor
    public func stopRecording(account: CloudAccount, recordingId: String) async throws {
        guard let baseURL = liveKitBaseUrl else { throw NSError(domain: "Invalid baseURL", code: 400, userInfo: nil) }
        let urlString = baseURL + "/api/v1/nests/\(roomId)/recording/\(recordingId)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 400, userInfo: nil)
        }

        let authorizationHeader = try await createAuthorizationHeader(account: account, urlString: urlString, method: "PATCH")

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.addValue(authorizationHeader, forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 201:
                print("Recording stopped successfully")
            default:
                let errorMessage = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                throw NSError(domain: errorMessage, code: httpResponse.statusCode, userInfo: nil)
            }
        } else {
            throw NSError(domain: "Invalid Response", code: 500, userInfo: nil)
        }
    }

    // MARK: - List Recordings

    @MainActor
    public func listRecordings(account: CloudAccount) async throws -> [RecordingInfo] {
        guard let baseURL = liveKitBaseUrl else { throw NSError(domain: "Invalid baseURL", code: 400, userInfo: nil) }
        let urlString = baseURL + "/api/v1/nests/\(roomId)/recording"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 400, userInfo: nil)
        }

        let authorizationHeader = try await createAuthorizationHeader(account: account, urlString: urlString, method: "GET")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(authorizationHeader, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                let recordings = try decoder.decode([RecordingInfo].self, from: data)
                return recordings
            default:
                let errorMessage = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                throw NSError(domain: errorMessage, code: httpResponse.statusCode, userInfo: nil)
            }
        } else {
            throw NSError(domain: "Invalid Response", code: 500, userInfo: nil)
        }
    }

    // MARK: - Download Recording

    @MainActor
    public func downloadRecording(account: CloudAccount, recordingId: String) async throws -> Data {
        guard let baseURL = liveKitBaseUrl else { throw NSError(domain: "Invalid baseURL", code: 400, userInfo: nil) }
        let urlString = baseURL + "/api/v1/nests/\(roomId)/recording/\(recordingId)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 400, userInfo: nil)
        }

        let authorizationHeader = try await createAuthorizationHeader(account: account, urlString: urlString, method: "GET")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(authorizationHeader, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200:
                return data
            default:
                let errorMessage = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                throw NSError(domain: errorMessage, code: httpResponse.statusCode, userInfo: nil)
            }
        } else {
            throw NSError(domain: "Invalid Response", code: 500, userInfo: nil)
        }
    }

    // MARK: - Delete Recording

    @MainActor
    public func deleteRecording(account: CloudAccount, recordingId: String) async throws {
        guard let baseURL = liveKitBaseUrl else { throw NSError(domain: "Invalid baseURL", code: 400, userInfo: nil) }
        let urlString = baseURL + "/api/v1/nests/\(roomId)/recording/\(recordingId)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 400, userInfo: nil)
        }

        let authorizationHeader = try await createAuthorizationHeader(account: account, urlString: urlString, method: "DELETE")

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue(authorizationHeader, forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 201:
                print("Recording deleted successfully")
            default:
                let errorMessage = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                throw NSError(domain: errorMessage, code: httpResponse.statusCode, userInfo: nil)
            }
        } else {
            throw NSError(domain: "Invalid Response", code: 500, userInfo: nil)
        }
    }
}

// MARK: - Response Models

struct CreateRoomResponse: Codable {
    let roomId: String
    let endpoints: [String]
    let token: String
}

struct JoinRoomResponse: Codable {
    let token: String
}

struct RecordingInfo: Codable, Identifiable {
    let id: String
    let started: Int
    let stopped: Int?
    let url: String
}

struct LiveKitRoomMetaData: Decodable {
    var host: String?
    let speakers: [String]
    let admins: [String]
    var link: String?
    let recording: Bool
}


// Helper function to create NIP-98 authorization header
@MainActor
func createAuthorizationHeader(account: CloudAccount, urlString: String, method: String) async throws -> String {
    var nEvent = NEvent(content: "")
    nEvent.publicKey = account.publicKey
    nEvent.kind = .custom(27235)
    nEvent.tags.append(NostrTag(["u", urlString]))
    nEvent.tags.append(NostrTag(["method", method]))

    let signedNip98Event: NEvent

    if account.isNC {
        // Sign remotely
        nEvent = nEvent.withId()
        signedNip98Event = try await withCheckedThrowingContinuation { continuation in
            NSecBunkerManager.shared.requestSignature(forEvent: nEvent, usingAccount: account) { signedEvent in
                continuation.resume(returning: signedEvent)
            }
        }
    } else {
        // Sign locally
        guard let signedEvent = try? account.signEvent(nEvent) else {
            throw NSError(domain: "Signing failed", code: 500, userInfo: nil)
        }
        signedNip98Event = signedEvent
    }

    let jsonString = signedNip98Event.eventJson()
    guard let jsonData = jsonString.data(using: .utf8, allowLossyConversion: true) else {
        throw NSError(domain: "Encoding failed", code: 500, userInfo: nil)
    }
    let base64 = jsonData.base64EncodedString()
    let authorizationHeader = "Nostr \(base64)"
    return authorizationHeader
}

@MainActor
func createRoom(baseURL: String, account: CloudAccount, relays: [String], hlsStream: Bool) async throws -> CreateRoomResponse {
    let urlString = baseURL + "/api/v1/nests"
    guard let url = URL(string: urlString) else {
        throw NSError(domain: "Invalid URL", code: 400, userInfo: nil)
    }

    let authorizationHeader = try await createAuthorizationHeader(account: account, urlString: urlString, method: "PUT")

    let requestBody: [String: Any] = [
        "relays": relays,
        "hls_stream": hlsStream
    ]

    let requestData = try JSONSerialization.data(withJSONObject: requestBody, options: [])

    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.addValue(authorizationHeader, forHTTPHeaderField: "Authorization")
    request.httpBody = requestData

    let (data, response) = try await URLSession.shared.data(for: request)

    if let httpResponse = response as? HTTPURLResponse {
        switch httpResponse.statusCode {
        case 200:
            let decoder = JSONDecoder()
            let createRoomResponse = try decoder.decode(CreateRoomResponse.self, from: data)
            return createRoomResponse
        default:
            let errorMessage = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw NSError(domain: errorMessage, code: httpResponse.statusCode, userInfo: nil)
        }
    } else {
        throw NSError(domain: "Invalid Response", code: 500, userInfo: nil)
    }
}
