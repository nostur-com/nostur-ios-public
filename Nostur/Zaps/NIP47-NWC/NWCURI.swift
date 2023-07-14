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
        L.og.info("⚡️ Vaid NWCURI")
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
        guard let host = uri.host() else { print(111); return nil }
        guard host.firstMatch(of: /[0-9a-z]{64}/) != nil else { return nil }
        
        return host
    }
    
    var lud16:String? {
        guard let queryItems = URLComponents(url: uri, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        return queryItems.first(where: { $0.name == "lud16" })?.value
    }
}
