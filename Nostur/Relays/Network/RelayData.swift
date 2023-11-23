// For kind-10002
struct AccountRelayData: Codable, Identifiable, Hashable, Equatable {
    public var id: String { url }
    public var url: String // should be lowercased, without trailing slash
    public var read: Bool
    public var write: Bool
    
    init(url: String, read: Bool, write: Bool) {
        self.url = normalizeRelayUrl(url)
        self.read = read
        self.write = write
    }
    
    mutating func setRead(_ newValue:Bool) {
        self.read = newValue
    }
    
    mutating func setWrite(_ newValue:Bool) {
        self.write = newValue
    }
    
    mutating func setUrl(_ newValue:String) {
        self.url = normalizeRelayUrl(newValue)
    }
}
