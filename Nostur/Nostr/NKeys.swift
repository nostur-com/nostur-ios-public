//
//  NKeys.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/03/2023.
//

import Foundation
import secp256k1
import CommonCrypto

struct NKeys {

    public let privateKey:secp256k1.Signing.PrivateKey
    public let publicKey:secp256k1.Signing.PublicKey

    init(privateKey:secp256k1.Signing.PrivateKey) {
        self.privateKey = privateKey
        self.publicKey = privateKey.publicKey
    }

    init(privateKeyHex:String) throws {
        do {
            let privateKeyBytes = try privateKeyHex.bytes
            privateKey = try secp256k1.Signing.PrivateKey(rawRepresentation: privateKeyBytes)
            publicKey = privateKey.publicKey
        }
        catch {
            L.og.error("Nkeys.init error")
            throw "could not init keys"
        }
    }

    func privateKeyHex() -> String {
        return String(bytes: privateKey.rawRepresentation.bytes)
    }

    func publicKeyHex() -> String {
        return String(bytes: privateKey.publicKey.xonly.bytes)
    }

    func signature<D: Digest>(for digest: D) throws -> secp256k1.Signing.SchnorrSignature {
        return try privateKey.schnorr.signature(for: digest)
    }

    public static func newKeys() -> NKeys {
        return try! self.init(privateKey: secp256k1.Signing.PrivateKey())
    }
}


// NIP-04 Direct Messaging
// From https://github.com/Galaxoid-Labs/NostrKit
// From https://github.com/cnixbtc/NostrKit
//
// MIT License
//
// Copyright (c) 2022 cnixbtc
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

extension NKeys {
    static func decryptDirectMessageContent(withPrivateKey privateKey: String?, pubkey: String, content: String) -> String? {
        guard let privateKey else {
            return nil
        }
        guard let sharedSecret = get_shared_secret(privkey: privateKey, pubkey: pubkey) else {
            return nil
        }
        guard let dat = decode_dm_base64(content) else {
            return nil
        }
        guard let dat = aes_decrypt(data: dat.content, iv: dat.iv, shared_sec: sharedSecret) else {
            return nil
        }
        return String(data: dat, encoding: .utf8)
    }
    
    static func encryptDirectMessageContent(withPrivatekey privateKey: String?, pubkey: String, content: String) -> String? {
        
        guard let privateKey = privateKey else {
            return nil
        }
        
        guard let sharedSecret = get_shared_secret(privkey: privateKey, pubkey: pubkey) else {
            return nil
        }
        
        let utf8Content = Data(content.utf8).bytes
        var random = Data(count: 16)
        random.withUnsafeMutableBytes { (rawMutableBufferPointer) in
            let bufferPointer = rawMutableBufferPointer.bindMemory(to: UInt8.self)
            if let address = bufferPointer.baseAddress {
                _ = SecRandomCopyBytes(kSecRandomDefault, 16, address)
            }
        }
        
        let iv = random.bytes
        
        guard let encryptedContent = aes_encrypt(data: utf8Content, iv: iv, shared_sec: sharedSecret) else {
            return nil
        }
        
        return encode_dm_base64(content: encryptedContent.bytes, iv: iv)
        
    }

    static func get_shared_secret(privkey: String, pubkey: String) -> [UInt8]? {
        guard let privkey_bytes = try? privkey.bytes else {
            return nil
        }
        guard var pk_bytes = try? pubkey.bytes else {
            return nil
        }
        pk_bytes.insert(2, at: 0)
        
        var publicKey = secp256k1_pubkey()
        var shared_secret = [UInt8](repeating: 0, count: 32)

        var ok =
            secp256k1_ec_pubkey_parse(
                try! secp256k1.Context.create(),
                &publicKey,
                pk_bytes,
                pk_bytes.count) != 0

        if !ok {
            return nil
        }

        ok = secp256k1_ecdh(
            try! secp256k1.Context.create(),
            &shared_secret,
            &publicKey,
            privkey_bytes, {(output,x32,_,_) in
                memcpy(output,x32,32)
                return 1
            }, nil) != 0

        if !ok {
            return nil
        }

        return shared_secret
    }

    struct DirectMessageBase64 {
        let content: [UInt8]
        let iv: [UInt8]
    }

    static func encode_dm_base64(content: [UInt8], iv: [UInt8]) -> String {
        let content_b64 = base64_encode(content)
        let iv_b64 = base64_encode(iv)
        return content_b64 + "?iv=" + iv_b64
    }

    static func decode_dm_base64(_ all: String) -> DirectMessageBase64? {
        let splits = Array(all.split(separator: "?"))

        if splits.count != 2 {
            return nil
        }

        guard let content = base64_decode(String(splits[0])) else {
            return nil
        }

        var sec = String(splits[1])
        if !sec.hasPrefix("iv=") {
            return nil
        }

        sec = String(sec.dropFirst(3))
        guard let iv = base64_decode(sec) else {
            return nil
        }

        return DirectMessageBase64(content: content, iv: iv)
    }

    static func base64_encode(_ content: [UInt8]) -> String {
        return Data(content).base64EncodedString()
    }

    static func base64_decode(_ content: String) -> [UInt8]? {
        guard let dat = Data(base64Encoded: content) else {
            return nil
        }
        return dat.bytes
    }

    static func aes_decrypt(data: [UInt8], iv: [UInt8], shared_sec: [UInt8]) -> Data? {
        return aes_operation(operation: CCOperation(kCCDecrypt), data: data, iv: iv, shared_sec: shared_sec)
    }

    static func aes_encrypt(data: [UInt8], iv: [UInt8], shared_sec: [UInt8]) -> Data? {
        return aes_operation(operation: CCOperation(kCCEncrypt), data: data, iv: iv, shared_sec: shared_sec)
    }

    static func aes_operation(operation: CCOperation, data: [UInt8], iv: [UInt8], shared_sec: [UInt8]) -> Data? {
        let data_len = data.count
        let bsize = kCCBlockSizeAES128
        let len = Int(data_len) + bsize
        var decrypted_data = [UInt8](repeating: 0, count: len)

        let key_length = size_t(kCCKeySizeAES256)
        if shared_sec.count != key_length {
            assert(false, "unexpected shared_sec len: \(shared_sec.count) != 32")
            return nil
        }

        let algorithm: CCAlgorithm = UInt32(kCCAlgorithmAES128)
        let options:   CCOptions   = UInt32(kCCOptionPKCS7Padding)

        var num_bytes_decrypted :size_t = 0

        let status = CCCrypt(operation,  /*op:*/
                             algorithm,  /*alg:*/
                             options,    /*options:*/
                             shared_sec, /*key:*/
                             key_length, /*keyLength:*/
                             iv,         /*iv:*/
                             data,       /*dataIn:*/
                             data_len, /*dataInLength:*/
                             &decrypted_data,/*dataOut:*/
                             len,/*dataOutAvailable:*/
                             &num_bytes_decrypted/*dataOutMoved:*/
        )

        if UInt32(status) != UInt32(kCCSuccess) {
            return nil
        }

        return Data(bytes: decrypted_data, count: num_bytes_decrypted)

    }
}
