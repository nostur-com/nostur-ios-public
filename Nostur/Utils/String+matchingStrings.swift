//
//  String+matchingStrings.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/01/2023.
//

import Foundation

extension String: Error {}

extension String {
    
    var short:String {
        String(self.prefix(min(self.count,11)))
    }
    
    private static var regexCache: [String: NSRegularExpression] = [
        NRContentElementBuilder.videoUrlPattern: try! NSRegularExpression(pattern: NRContentElementBuilder.videoUrlPattern, options: []),
        NRContentElementBuilder.imageUrlPattern: try! NSRegularExpression(pattern: NRContentElementBuilder.imageUrlPattern, options: []),
        NRContentElementBuilder.previewImagePlaceholder: try! NSRegularExpression(pattern: NRContentElementBuilder.previewImagePlaceholder, options: []),
        NRContentElementBuilder.lightningInvoicePattern: try! NSRegularExpression(pattern: NRContentElementBuilder.lightningInvoicePattern, options: []),
        NRContentElementBuilder.notePattern: try! NSRegularExpression(pattern: NRContentElementBuilder.notePattern, options: []),
        NRContentElementBuilder.neventPattern: try! NSRegularExpression(pattern: NRContentElementBuilder.neventPattern, options: []),
        NRContentElementBuilder.nprofilePattern: try! NSRegularExpression(pattern: NRContentElementBuilder.nprofilePattern, options: []),
        NRContentElementBuilder.otherUrlsPattern: try! NSRegularExpression(pattern: NRContentElementBuilder.otherUrlsPattern, options: []),
        "^(npub1)([023456789acdefghjklmnpqrstuvwxyz]{58})$": try! NSRegularExpression(pattern: "^(npub1)([023456789acdefghjklmnpqrstuvwxyz]{58})$", options: []),
        #"@(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})"#: try! NSRegularExpression(pattern: #"@(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})"#, options: []),
        #"(nsec1)([023456789acdefghjklmnpqrstuvwxyz]{58})"#: try! NSRegularExpression(pattern: #"(nsec1)([023456789acdefghjklmnpqrstuvwxyz]{58})"#, options: []),
        "(?<![/\\?]|\\b)(\\#)([^\\s\\[]{2,})\\b": try! NSRegularExpression(pattern: "(?<![/\\?]|\\b)(\\#)([^\\s\\[]{2,})\\b", options: []),
        "^(nostr:)(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})$": try! NSRegularExpression(pattern: "^(nostr:)(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})$", options: []),
        "^(nostur:)(p:|e:)([0-9a-z]{64})$": try! NSRegularExpression(pattern: "^(nostur:)(p:|e:)([0-9a-z]{64})$", options: []),
        "^(nostr:)(p:|e:)([0-9a-z]{64})$": try! NSRegularExpression(pattern: "^(nostr:)(p:|e:)([0-9a-z]{64})$", options: []),
        "^(nostur:t:)(\\S+)$": try! NSRegularExpression(pattern: "^(nostur:t:)(\\S+)$", options: [])
    ]
    
    func matchingStrings(regex: String) -> [[String]] {
        let regex = (String.regexCache[regex]) ?? (try! NSRegularExpression(pattern: regex, options: []))
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
