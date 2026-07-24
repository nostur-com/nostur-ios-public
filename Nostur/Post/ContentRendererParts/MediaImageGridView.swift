//
//  MediaImageGridView.swift
//  Nostur
//
//  2×2 square image grid for Kind1 note rows when a post ends with 4+ images.
//

import SwiftUI

struct MediaImageGridView: View {
    public let items: [GalleryItem]
    public let availableWidth: CGFloat
    public var autoload: Bool = false
    public var isNSFW: Bool = false
    public var zoomableId: String = "Default"
    
    private let spacing: CGFloat = 2
    
    private var cellSize: CGFloat {
        max(1, (availableWidth - spacing) / 2)
    }
    
    private var displayItems: [GalleryItem] {
        Array(items.prefix(4))
    }
    
    /// Images beyond the 3 fully visible cells. The 4th cell is covered by the
    /// overlay, so it counts toward +N together with any images past the grid
    /// (e.g. 7 total → +4, not +3).
    private var extraCount: Int {
        max(0, items.count - 3)
    }
    
    var body: some View {
        let columns = [
            GridItem(.fixed(cellSize), spacing: spacing),
            GridItem(.fixed(cellSize), spacing: spacing)
        ]
        
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                MediaContentView(
                    galleryItem: item,
                    availableWidth: cellSize,
                    placeholderAspect: 1.0,
                    maxHeight: cellSize,
                    contentMode: .fill,
                    galleryItems: items,
                    autoload: autoload,
                    isNSFW: isNSFW,
                    zoomableId: zoomableId
                )
                .frame(width: cellSize, height: cellSize)
                .clipped()
                .contentShape(Rectangle())
                .overlay {
                    // Only when more than 4: 3 clear cells + 4th with +N (includes the covered image)
                    if index == displayItems.count - 1 && items.count > 4 {
                        ZStack {
                            Color.black.opacity(0.45)
                            Text("+\(extraCount)")
                                .font(.system(size: min(cellSize * 0.22, 36), weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(width: availableWidth)
    }
}

#Preview("Media Image Grid 4") {
    let items = (0..<4).map { i in
        GalleryItem(url: URL(string: "https://picsum.photos/seed/\(i)/400")!)
    }
    return MediaImageGridView(items: items, availableWidth: 320, autoload: true)
        .padding()
}

#Preview("Media Image Grid 7 (+4)") {
    let items = (0..<7).map { i in
        GalleryItem(url: URL(string: "https://picsum.photos/seed/\(i)/400")!)
    }
    return MediaImageGridView(items: items, availableWidth: 320, autoload: true)
        .padding()
}
