//
//  Nip97LoginModel.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/03/2024.
//

import SwiftUI
import Combine

class Nip97LoginModel: ObservableObject {
    
    public var askLoginInfo: AskLoginInfo
    
    init(askLoginInfo: AskLoginInfo, account: CloudAccount) {
        self.askLoginInfo = askLoginInfo
        self.account = account
    }
    
    @Published var state: Nip97LoginModel.LoginState = .initializing
    @Published var account: CloudAccount
    @Published var redirectUrl: String? = nil
    
    private var subscriptions = Set<AnyCancellable>()
    
    public func login() {
        loginPublisher().sink(receiveCompletion: { result in
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.state = .error
                }
            case .finished:
                DispatchQueue.main.async {
                    self.state = .success
                }
            }
        }, receiveValue: { message in
            L.og.debug("login: \(message)")
        })
        .store(in: &subscriptions)
    }
    
    public func loginPublisher() -> AnyPublisher<String, Error> {
        let urlString = "https://\(askLoginInfo.domain)/.well-known/nostr/nip97"
        var nEvent = NEvent(content: "")
        nEvent.publicKey = account.publicKey
        nEvent.kind = .custom(27235)
        nEvent.tags.append(NostrTag(["u", urlString]))
        nEvent.tags.append(NostrTag(["method", "POST"]))
//        nEvent.tags.append(NostrTag(["i", askLoginInfo.challenge]))
        if let signedEvent = try? account.signEvent(nEvent), let url = URL(string: urlString + "?i=\(askLoginInfo.challenge)") {
            
            let jsonString = signedEvent.eventJson()
            guard let jsonData = jsonString.data(using: .utf8, allowLossyConversion: true) else { return Fail(error: URLError(.cannotParseResponse)).eraseToAnyPublisher() }
            let base64 = jsonData.base64EncodedString()
            let authorizationHeader = "Nostr \(base64)"
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
            
            let session = URLSession(configuration: .default)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            return Future { promise in
                session.dataTask(with: request) { (data, response, error) in
                    guard let data = data, let httpResponse = response as? HTTPURLResponse else {
                        L.og.debug("NIP-97: bad server response")
                        promise(.failure(URLError(.badServerResponse)))
                        return
                    }
                    switch httpResponse.statusCode {
                        case 200, 201, 202:
                            do {
                                let uploadResponse = try decoder.decode(Nip97LoginResponse.self, from: data)
                                if uploadResponse.status == "success" {
                                    DispatchQueue.main.async {
                                        self.objectWillChange.send()
                                        promise(.success(uploadResponse.message ?? ""))
                                        if let redirectUrl = uploadResponse.redirectUrl {
                                            self.redirectUrl = redirectUrl
                                        }
                                    }
                                }
                                else {
                                    L.og.debug("NIP-97 Login Error: \(uploadResponse.status) \(uploadResponse.message)")
                                    promise(.failure(URLError(.userAuthenticationRequired)))
                                }
                            } catch {
                                L.og.debug("NIP-97: catch")
                                promise(.failure(error))
                            }
                        case 401:
                            L.og.debug("NIP-97: 401")
                            promise(.failure(URLError(.userAuthenticationRequired)))
                        default:
                            L.og.debug("NIP-97: other")
                            promise(.failure(URLError(.badServerResponse)))
                    }
                }.resume()
            }.eraseToAnyPublisher()
        }
        
        L.og.debug("NIP-97: Fail")
        return Fail(error: URLError(.unknown)).eraseToAnyPublisher()
    }
    
    public class LoginError: Error {
        
    }
    
    public func newLoginInfo(_ askLoginInfo: AskLoginInfo) {
        self.askLoginInfo = askLoginInfo
        self.state = .initializing
    }
    
    public enum LoginState {
        case initializing
        case loggingIn
        case timeout
        case success
        case error
    }
    
    public struct Nip97LoginResponse: Decodable {
        public let status: String
        public let message: String?
        public var redirectUrl: String?
    }
}
