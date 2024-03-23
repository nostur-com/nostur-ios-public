//
//  BookmarksAndPrivateNotes+BookmarkFilters.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/03/2024.
//

import SwiftUI

struct BookmarkFilters: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var onlyShow: Set<Color>
    
    var body: some View {
        VStack {
            Text("Show bookmarks")
            HStack {
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.red)
                    .opacity(onlyShow.contains(.red) ? 1.0 : 0.2)
                    .contentShape(Rectangle())
                    .padding(10)
                    .onTapGesture { self.toggle(.red) }
                
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.blue)
                    .opacity(onlyShow.contains(.blue) ? 1.0 : 0.2)
                    .contentShape(Rectangle())
                    .padding(10)
                    .onTapGesture { self.toggle(.blue) }
                
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.purple)
                    .opacity(onlyShow.contains(.purple) ? 1.0 : 0.2)
                    .contentShape(Rectangle())
                    .padding(10)
                    .onTapGesture { self.toggle(.purple) }
                
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.green)
                    .opacity(onlyShow.contains(.green) ? 1.0 : 0.2)
                    .contentShape(Rectangle())
                    .padding(10)
                    .onTapGesture { self.toggle(.green) }
                
                Image(systemName: "bookmark.fill")
                    .foregroundColor(.orange)
                    .opacity(onlyShow.contains(.orange) ? 1.0 : 0.2)
                    .contentShape(Rectangle())
                    .padding(10)
                    .onTapGesture { self.toggle(.orange) }
            }
            Text("Tap to toggle")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
    
    private func toggle(_ color: Color) {
        if onlyShow.contains(color) {
            onlyShow.remove(color)
        }
        else {
            onlyShow.insert(color)
        }
    }
}

#Preview {
    BookmarkFilters(onlyShow: .constant([]))
}
