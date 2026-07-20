//
//  SearchColumn.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/07/2026.
//

import SwiftUI

struct SearchColumn: View {
    let containerID: String

    var body: some View {
        Search(containerID: containerID, showsNavigationTitle: false)
            .environment(\.horizontalSizeClass, .compact)
    }
}
