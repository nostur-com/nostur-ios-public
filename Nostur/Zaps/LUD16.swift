//
//  LUD16.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/02/2023.
//

import Foundation

// LUD16 response
//{
//    "status": "OK",
//    "tag": "payRequest",
//    "minSendable": 1,
//    "maxSendable": 10000000000,
//    "callback": "https://sendsats.lol/@jb55",
//    "metadata": "[[\"text/plain\",\"jb55's lightning address\"],[\"text/identifier\",\"jb55@sendsats.lol\"]]",
//    "allowsNostr": true,
//    "nostrPubkey": "9630f464cca6a5147aa8a35f0bcdd3ce485324e732fd39e09233b1d848238f31"
//}

struct LUD16response: Codable {
    let status:String?
    let tag:String?
    let minSendable: UInt64?
    let maxSendable: UInt64?
    let callback: String?
    let metadata: String
    let allowsNostr: Bool?
    let nostrPubkey: String?
}

struct LNUrlResponse: Codable {
    let pr:String?
    let routes:[String]?
}

class LUD16 {

    static func getCallbackUrl(lud16:String) async throws -> LUD16response {
        
        let lud16trimmed = lud16.trimmingCharacters(in: .whitespacesAndNewlines)
        let lud16parts = lud16trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: true)
        
        guard lud16parts.count == 2 else { throw "invalid lud16" }
        
        
        guard let lud16url = URL(string: "https://\(lud16parts[1])/.well-known/lnurlp/\(lud16parts[0])") else { throw "invalid lud16url" }
        
        let urlSession = URLSession.shared
        let request = URLRequest(url: lud16url)
        
        let (data, httpResponse) = try await URLSession.shared.data(for: request)
        
        guard (httpResponse as? HTTPURLResponse)?.statusCode == 200 else { throw "Bad response" }
        
        let lud16response = try JSONDecoder().decode(LUD16response.self, from: data)
        
        return lud16response
    }
    
    static func getInvoice(url:String, amount:UInt64, zapRequestNote:NEvent? = nil) async throws -> LNUrlResponse {
        
        guard var callbackUrl = URL(string: url) else { throw "invalid callback url" }
        let amount = URLQueryItem(name: "amount", value: amount.description)
        
        if (zapRequestNote != nil) {
            let zapRequest = URLQueryItem(name: "nostr", value: zapRequestNote?.eventJson())
            callbackUrl.append(queryItems: [amount, zapRequest])
        }
        else {
            callbackUrl.append(queryItems: [amount])
        }
        
        let urlSession = URLSession.shared
        
        do {
            ThreadWarning.which("getInvoice 3")
            let (data, _) = try await urlSession.data(from: callbackUrl)
        
            let response = try JSONDecoder().decode(LNUrlResponse.self, from: data)
        
            return response
        }
        catch {
            throw "Error loading \(url), \(amount.description): \(String(describing: error))"
        }
    }
}
