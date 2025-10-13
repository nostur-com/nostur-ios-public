//
//  ArticlesColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/10/2025.
//

import SwiftUI

struct ArticlesColumn: View {
    
    @StateObject private var vm = ArticlesFeedViewModel()
    
    var body: some View {
        ArticlesFeed()
            .environmentObject(vm)
    }
}

#Preview {
    ArticlesColumn()
}
