//
//  String+matchingStrings.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/01/2023.
//

import Foundation

extension String {
    
    private static var regexCache: [String: NSRegularExpression] = [
        VPostTransformer.videoUrlPattern: try! NSRegularExpression(pattern: VPostTransformer.videoUrlPattern, options: []),
        VPostTransformer.imageUrlPattern: try! NSRegularExpression(pattern: VPostTransformer.imageUrlPattern, options: []),
        VPostTransformer.previewImagePlaceholder: try! NSRegularExpression(pattern: VPostTransformer.previewImagePlaceholder, options: []),
        VPostTransformer.lightningInvoicePattern: try! NSRegularExpression(pattern: VPostTransformer.lightningInvoicePattern, options: []),
        VPostTransformer.notePattern: try! NSRegularExpression(pattern: VPostTransformer.notePattern, options: []),
        VPostTransformer.neventPattern: try! NSRegularExpression(pattern: VPostTransformer.neventPattern, options: []),
        VPostTransformer.nprofilePattern: try! NSRegularExpression(pattern: VPostTransformer.nprofilePattern, options: []),
        VPostTransformer.otherUrlsPattern: try! NSRegularExpression(pattern: VPostTransformer.otherUrlsPattern, options: []),
        "^(npub1)([023456789acdefghjklmnpqrstuvwxyz]{58})$": try! NSRegularExpression(pattern: "^(npub1)([023456789acdefghjklmnpqrstuvwxyz]{58})$", options: []),
        #"@(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})"#: try! NSRegularExpression(pattern: #"@(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})"#, options: []),
        #"(nsec1)([023456789acdefghjklmnpqrstuvwxyz]{58})"#: try! NSRegularExpression(pattern: #"(nsec1)([023456789acdefghjklmnpqrstuvwxyz]{58})"#, options: []),
        "(?<![/\\?]|\\b)(\\#)([^\\s\\[]{2,})\\b": try! NSRegularExpression(pattern: "(?<![/\\?]|\\b)(\\#)([^\\s\\[]{2,})\\b", options: []),
        "^(nostr:)(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})$": try! NSRegularExpression(pattern: "^(nostr:)(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})$", options: []),
        "^(nostur:)(p:|e:)([0-9a-z]{64})$": try! NSRegularExpression(pattern: "^(nostur:)(p:|e:)([0-9a-z]{64})$", options: []),
        "^(nostr:)(p:|e:)([0-9a-z]{64})$": try! NSRegularExpression(pattern: "^(nostr:)(p:|e:)([0-9a-z]{64})$", options: []),
        "^(nostur:t:)(\\S+)$": try! NSRegularExpression(pattern: "^(nostur:t:)(\\S+)$", options: []),
//        VPostTransformer.imageUrlPattern: try! NSRegularExpression(pattern: VPostTransformer.imageUrlPattern, options: []),
//        VPostTransformer.imageUrlPattern: try! NSRegularExpression(pattern: VPostTransformer.imageUrlPattern, options: []),
    ]
    
    
    
    
    
    func matchingStrings(regex: String) -> [[String]] {
        guard let regex = String.regexCache[regex] else { return [] }
        let nsString = self as NSString
        let results  = regex.matches(in: self, options: [], range: NSMakeRange(0, nsString.length))
        return results.map { result in
            (0..<result.numberOfRanges).map {
                result.range(at: $0).location != NSNotFound
                    ? nsString.substring(with: result.range(at: $0))
                    : ""
            }
        }
    }
}
