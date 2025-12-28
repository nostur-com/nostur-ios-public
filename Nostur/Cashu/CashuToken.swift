//
//  CashuToken.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/11/2023.
//

import Foundation
import SwiftCBOR

struct CashuToken {
    let proofs: [CashuProof]
    let mintURL: String
    var unit: String
    let memo: String?
    
    var totalAmount: Int {
        proofs.reduce(0) { $0 + $1.amount }
    }
    
    var primaryMintHost: String? {
        URL(string: mintURL)?.host
    }
}

struct CashuProof {
    let amount: Int
    let keysetID: Data?
    let secret: Data
    let C: Data
    let dleq: DLEQProof?
    let witness: String?
}

struct DLEQProof {
    let e: Data
    let s: Data
    let r: Data
}

enum CashuTokenError: Error {
    case invalidPrefix
    case invalidBase64
    case unsupportedVersion
    case decodingFailed(String)
}

func decodeCashuToken(from tokenString: String) throws -> CashuToken {
    var token = tokenString.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Remove optional "cashu:" URI scheme
    if token.lowercased().hasPrefix("cashu:") {
        token = String(token.dropFirst(6))
    }
    
    guard token.lowercased().hasPrefix("cashua") || token.lowercased().hasPrefix("cashub") else {
        throw CashuTokenError.invalidPrefix
    }
    
    let versionIndex = token.index(token.startIndex, offsetBy: 5)
    let versionChar = token[versionIndex]
    
    let base64Part = String(token.dropFirst(6))
    
    let standardBase64 = base64Part
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    
    guard let data = Data(base64EncodedPadded: standardBase64) else {
        throw CashuTokenError.invalidBase64
    }
    
    if versionChar.uppercased() == "A" {
        return try decodeV3(from: data)
    } else if versionChar.uppercased() == "B" {
        return try decodeV4(from: data)
    } else {
        throw CashuTokenError.unsupportedVersion
    }
}

// MARK: - Helpers

extension Data {
    init?(base64EncodedPadded base64: String) {
        let candidates = [base64, base64 + "=", base64 + "=="]
        for candidate in candidates {
            if let data = Data(base64Encoded: candidate) {
                self = data
                return
            }
        }
        return nil
    }
    
    init?(hex: String) {
        let cleaned = hex.lowercased().filter { "0123456789abcdef".contains($0) }
        guard cleaned.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            let byteString = String(cleaned[index..<nextIndex])
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}

// MARK: - V3 Decoder

private func decodeV3(from data: Data) throws -> CashuToken {
    let decoder = JSONDecoder()
    
    struct V3Token: Decodable {
        let token: [V3Mint]
        let unit: String?    // Now optional!
        let memo: String?
    }
    
    struct V3Mint: Decodable {
        let mint: String
        let proofs: [V3Proof]
    }
    
    struct V3Proof: Decodable {
        let id: String?
        let amount: Int
        let secret: String
        let C: String
        let witness: String?
    }
    
    let v3 = try decoder.decode(V3Token.self, from: data)
    
    guard let firstMint = v3.token.first else {
        throw CashuTokenError.decodingFailed("No mints found in V3 token")
    }
    
    var proofs: [CashuProof] = []
    
    for mint in v3.token {
        for proof in mint.proofs {
            guard let cData = Data(hex: proof.C) else {
                throw CashuTokenError.decodingFailed("Invalid hex string for 'C' in V3 proof")
            }
            
            let keysetID = proof.id.flatMap { Data(hex: $0) }
            let secretData = Data(proof.secret.utf8)
            
            let cashuProof = CashuProof(
                amount: proof.amount,
                keysetID: keysetID,
                secret: secretData,
                C: cData,
                dleq: nil,
                witness: proof.witness
            )
            proofs.append(cashuProof)
        }
    }
    
    // Default to "sat" if unit is missing (safe for 99.9% of tokens)
    let unit = v3.unit ?? "sat"
    
    return CashuToken(
        proofs: proofs,
        mintURL: firstMint.mint,
        unit: unit,
        memo: v3.memo
    )
}

// MARK: - V4 Decoder 

private func decodeV4(from data: Data) throws -> CashuToken {
    guard let rawCBOR = try? CBOR.decode([UInt8](data)),
          case let CBOR.map(topMap) = rawCBOR else {
        throw CashuTokenError.decodingFailed("Invalid top-level CBOR structure")
    }
    
    // Mint URL "m" – required
    guard let mValue = topMap[CBOR.utf8String("m")],
          case let CBOR.utf8String(mintURL) = mValue else {
        throw CashuTokenError.decodingFailed("Missing or invalid 'm' (mint URL)")
    }
    
    // Unit "u" – now optional, default to "sat"
    let unit: String = {
        if let uValue = topMap[CBOR.utf8String("u")],
           case let CBOR.utf8String(uStr) = uValue {
            return uStr
        }
        return "sat"  // Fallback for early/experimental tokens missing unit
    }()
    
    // Optional memo "d"
    let memo: String? = {
        guard let dValue = topMap[CBOR.utf8String("d")],
              case let CBOR.utf8String(memoStr) = dValue else { return nil }
        return memoStr
    }()
    
    // Proof groups "t" → array of groups
    guard let tValue = topMap[CBOR.utf8String("t")],
          case let CBOR.array(groups) = tValue else {
        throw CashuTokenError.decodingFailed("Missing or invalid 't' (proof groups)")
    }
    
    var proofs: [CashuProof] = []
    
    for group in groups {
        guard case let CBOR.map(groupMap) = group else {
            throw CashuTokenError.decodingFailed("Invalid proof group")
        }
        
        // Keyset ID "i" (optional in spec, but usually present)
        let keysetID: Data? = {
            guard let iValue = groupMap[CBOR.utf8String("i")],
                  case let CBOR.byteString(bytes) = iValue else { return nil }
            return Data(bytes)
        }()
        
        // Proofs array "p"
        guard let pValue = groupMap[CBOR.utf8String("p")],
              case let CBOR.array(proofArray) = pValue else {
            throw CashuTokenError.decodingFailed("Missing or invalid 'p' (proofs) in group")
        }
        
        for proofItem in proofArray {
            guard case let CBOR.map(pMap) = proofItem else {
                throw CashuTokenError.decodingFailed("Invalid proof item")
            }
            
            // Amount "a"
            guard let aValue = pMap[CBOR.utf8String("a")],
                  case let CBOR.unsignedInt(amountUInt) = aValue,
                  let amount = Int(exactly: amountUInt) else {
                throw CashuTokenError.decodingFailed("Invalid or missing amount 'a'")
            }
            
            // Secret "s" (UTF-8 string)
            guard let sValue = pMap[CBOR.utf8String("s")],
                  case let CBOR.utf8String(secretStr) = sValue else {
                throw CashuTokenError.decodingFailed("Missing or invalid secret 's'")
            }
            let secretData = Data(secretStr.utf8)
            
            // C "c" (bytes)
            guard let cValue = pMap[CBOR.utf8String("c")],
                  case let CBOR.byteString(cBytes) = cValue else {
                throw CashuTokenError.decodingFailed("Missing or invalid 'c'")
            }
            let cData = Data(cBytes)
            
            // Optional DLEQ "d"
            let dleq: DLEQProof? = {
                guard let dValue = pMap[CBOR.utf8String("d")],
                      case let CBOR.map(dMap) = dValue else { return nil }
                
                guard let eVal = dMap[CBOR.utf8String("e")],
                      case let CBOR.byteString(eBytes) = eVal,
                      let sVal = dMap[CBOR.utf8String("s")],
                      case let CBOR.byteString(sBytes) = sVal,
                      let rVal = dMap[CBOR.utf8String("r")],
                      case let CBOR.byteString(rBytes) = rVal else {
                    return nil
                }
                
                return DLEQProof(e: Data(eBytes), s: Data(sBytes), r: Data(rBytes))
            }()
            
            // Optional witness "w"
            let witness: String? = {
                guard let wValue = pMap[CBOR.utf8String("w")],
                      case let CBOR.utf8String(wStr) = wValue else { return nil }
                return wStr
            }()
            
            proofs.append(CashuProof(
                amount: amount,
                keysetID: keysetID,
                secret: secretData,
                C: cData,
                dleq: dleq,
                witness: witness
            ))
        }
    }
    
    guard !proofs.isEmpty else {
        throw CashuTokenError.decodingFailed("No proofs found in V4 token")
    }
    
    return CashuToken(
        proofs: proofs,
        mintURL: mintURL,
        unit: unit,
        memo: memo
    )
}
