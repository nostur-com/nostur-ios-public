//
//  NWCURI.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/06/2023.
//

import Foundation

struct NWCURI {
    var uri:URL
    init(string:String) throws {
        if let uri = URL(string: string) {
            self.uri = uri
        }
        else {
            L.og.error("Invalid NWCURI (A)")
            throw "invalid nwc uri"
        }
        if !isValid {
            L.og.error("Invalid NWCURI (B)")
            throw "invalid nwc uri"
        }
    }
    
    var isValid:Bool {
        guard walletPubkey != nil else { L.og.error("NWCURI: invalid walletPubkey"); return false }
        guard relay != nil else { L.og.error("NWCURI: invalid relay"); return false }
        guard secret != nil else { L.og.error("NWCURI: invalid secret"); return false }
        L.og.info("⚡️ Valid NWCURI")
        return true
    }
    
    var relay:String? {
        guard let queryItems = URLComponents(url: uri, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        return queryItems.first(where: { $0.name == "relay" })?.value
    }
    
    var secret:String? {
        guard let queryItems = URLComponents(url: uri, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        return queryItems.first(where: { $0.name == "secret" })?.value
    }
    
    var walletPubkey:String? {
        guard let host = uri.host else { return nil }
        if #available(iOS 16.0, *) {
            guard host.firstMatch(of: /[0-9a-z]{64}/) != nil else { return nil }
        } else {
            guard let regex = try? NSRegularExpression(pattern: "[0-9a-z]{64}", options: .caseInsensitive) else { return nil }
            let range = NSRange(host.startIndex..<host.endIndex, in: host)
            guard regex.firstMatch(in: host, options: [], range: range) != nil else { return nil }
        }
        
        return host
    }
    
    var lud16:String? {
        guard let queryItems = URLComponents(url: uri, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        return queryItems.first(where: { $0.name == "lud16" })?.value
    }
}
