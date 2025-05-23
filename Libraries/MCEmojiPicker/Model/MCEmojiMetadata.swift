import Foundation

/// Model representing the metadata for an emoji from emoji.json
struct MCEmojiMetadata: Codable {
    let emoji: String
    let description: String
    let category: String
    let aliases: [String]
    let tags: [String]
    let unicodeVersion: String
    let iosVersion: String
    
    enum CodingKeys: String, CodingKey {
        case emoji
        case description
        case category
        case aliases
        case tags
        case unicodeVersion = "unicode_version"
        case iosVersion = "ios_version"
    }
}

/// Service to manage emoji metadata
class MCEmojiMetadataService {
    static let shared = MCEmojiMetadataService()
    
    private var metadataCache: [String: MCEmojiMetadata] = [:]
    
    private init() {
        loadMetadata()
    }
    
    private func loadMetadata() {
        guard let url = Bundle(for: MCEmojiMetadataService.self).url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let metadata = try? JSONDecoder().decode([MCEmojiMetadata].self, from: data) else {
            return
        }
        
        // Create a dictionary for quick lookup by emoji
        metadataCache = Dictionary(uniqueKeysWithValues: metadata.map { ($0.emoji, $0) })
    }
    
    /// Get metadata for a specific emoji
    func getMetadata(for emoji: String) -> MCEmojiMetadata? {
        return metadataCache[emoji]
    }
    
    /// Search for emojis matching the given query
    func search(query: String) -> [String] {
        let searchTerms = query.lowercased().split(separator: " ")
        
        return metadataCache.values.filter { metadata in
            let searchableText = [
                metadata.description,
                metadata.category,
                metadata.aliases.joined(separator: " "),
                metadata.tags.joined(separator: " ")
            ].joined(separator: " ").lowercased()
            
            return searchTerms.allSatisfy { term in
                searchableText.contains(term)
            }
        }.map { $0.emoji }
    }
} 