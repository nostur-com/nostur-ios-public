// The MIT License (MIT)
//
// Copyright © 2022 Ivan Izyumkin
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
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

/// Protocol for the `MCEmojiPickerViewModel`.
protocol MCEmojiPickerViewModelProtocol {
    var searchText: Observable<String> { get set }
    /// Whether the picker shows empty categories. Default false.
    var showEmptyEmojiCategories: Bool { get set }
    /// The emoji categories being used
    var emojiCategories: [MCEmojiCategory] { get }
    /// The observed variable that is responsible for the choice of emoji.
    var selectedEmoji: Observable<MCEmoji?> { get set }
    /// The observed variable that is responsible for the choice of emoji category.
    var selectedEmojiCategoryIndex: Observable<Int> { get set }
    /// Specifies that this will only show the new Emojis from the specified `maxCurrentAvailableOsVersion`
    var onlyShowNewEmojisForVersion: Bool { get set }
    /// Clears the selected emoji, setting to `nil`.
    func clearSelectedEmoji()
    /// Returns the number of categories with emojis.
    func numberOfSections() -> Int
    /// Returns the number of emojis in the target section.
    func numberOfItems(in section: Int) -> Int
    /// Returns the `MCEmoji` for the target `IndexPath`.
    func emoji(at indexPath: IndexPath) -> MCEmoji
    /// Returns the localized section name for the target section.
    func sectionHeaderName(for section: Int) -> String
    /// Updates the emoji skin tone and returns the updated `MCEmoji`.
    func updateEmojiSkinTone(_ skinToneRawValue: Int, in indexPath: IndexPath) -> MCEmoji
}

/// View model which using in `MCEmojiPickerViewController`.
final class MCEmojiPickerViewModel: MCEmojiPickerViewModelProtocol {
    
    // MARK: - Public Properties
    
    public var selectedEmoji = Observable<MCEmoji?>(value: nil)
    public var selectedEmojiCategoryIndex = Observable<Int>(value: 0)
    public var showEmptyEmojiCategories = false
    public var onlyShowNewEmojisForVersion = false
    public var searchText = Observable<String>(value: "")

    public var emojiCategories: [MCEmojiCategory] {
        if searchText.value.isEmpty {
            return allEmojiCategories.filter { showEmptyEmojiCategories || !$0.emojis.isEmpty || onlyShowNewEmojisForVersion }
        } else {
            return filteredCategories
        }
    }
    
    // MARK: - Private Properties
    
    /// All emoji categories.
    private var allEmojiCategories = [MCEmojiCategory]()
    private var filteredCategories = [MCEmojiCategory]()
    
    // MARK: - Initializers
    
    init(unicodeManager: MCUnicodeManagerProtocol = MCUnicodeManager(), onlyShowNewEmojisForVersion: Bool = false) {
        self.onlyShowNewEmojisForVersion = onlyShowNewEmojisForVersion
        allEmojiCategories = unicodeManager.getEmojisForCurrentIOSVersion()
        // Increment usage of each emoji upon selection
        selectedEmoji.bind { emoji in
            emoji?.incrementUsageCount()
        }
        // Bind to searchText changes
        searchText.bind { [weak self] _ in
            self?.updateFilteredCategories()
        }
    }
    
    // MARK: - Private Methods
    
    private func updateFilteredCategories() {
      
        let searchString = searchText.value.lowercased()
        
        if searchString.isEmpty {
            filteredCategories = []
            return
        }
        
        // Get matching emoji strings from metadata service
        let matchingEmojiStrings = MCEmojiMetadataService.shared.search(query: searchString)
        
        // Find the corresponding MCEmoji objects
        let allEmojis = allEmojiCategories.flatMap { $0.emojis }
        let potentialMatches = allEmojis.filter { emoji in
            matchingEmojiStrings.contains(emoji.string)
        }
        
        // If no matches found through metadata, fall back to basic search
        let searchResults = potentialMatches.isEmpty ? allEmojiCategories.flatMap { category in
            category.emojis.filter { emoji in
                let searchKeyMatch = emoji.searchKey.lowercased().contains(searchString)
                let stringMatch = emoji.string.lowercased().contains(searchString)
                return searchKeyMatch || stringMatch
            }
        } : potentialMatches
        
        // Create a search results category
        let searchCategory = MCEmojiCategory(
            type: .search,
            categoryName: "Search Results",
            emojis: searchResults
        )
        
        filteredCategories = [searchCategory]
    }
    
    // MARK: - Public Methods
    
    public func clearSelectedEmoji() {
        selectedEmoji.value = nil
    }
    
    public func numberOfSections() -> Int {
        return emojiCategories.count
    }
    
    public func numberOfItems(in section: Int) -> Int {
        return emojiCategories[section].emojis.count
    }
    
    public func emoji(at indexPath: IndexPath) -> MCEmoji {
        return emojiCategories[indexPath.section].emojis[indexPath.row]
    }
    
    public func sectionHeaderName(for section: Int) -> String {
        return emojiCategories[section].categoryName
    }
    
    public func updateEmojiSkinTone(_ skinToneRawValue: Int, in indexPath: IndexPath) -> MCEmoji {
        let categoryType: MCEmojiCategoryType = emojiCategories[indexPath.section].type
        let allCategoriesIndex: Int = allEmojiCategories.firstIndex { $0.type == categoryType } ?? 0
        allEmojiCategories[allCategoriesIndex].emojis[indexPath.row].set(skinToneRawValue: skinToneRawValue)
        return allEmojiCategories[allCategoriesIndex].emojis[indexPath.row]
    }
}
