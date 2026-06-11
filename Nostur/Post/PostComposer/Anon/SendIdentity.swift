//  SendIdentity.swift
import Foundation
import NostrEssentials

enum SendIdentity {
    case account(CloudAccount)
    case anon(Keys)
    var pubkey: String {
        switch self { case .account(let a): return a.publicKey; case .anon(let k): return k.publicKeyHex }
    }
    var isAnon: Bool { if case .anon = self { return true }; return false }
}
