//
//  PictureEvent.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/11/2024.
//

import SwiftUI
import NukeUI

struct PictureEventView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var dim: DIMENSIONS
    
    public var imageUrl: URL
    
    public var autoload: Bool = false
    
    public var theme: Theme
    
    public var availableWidth: CGFloat?
    
    static let aspect: CGFloat = 16/9
    
    @State private var didStart = false
    
    var body: some View {
        SingleMediaViewer(url: imageUrl, pubkey: "", imageWidth: availableWidth ?? dim.availableNoteRowImageWidth(), fullWidth: true, autoload: autoload, contentPadding: 0, contentMode: .aspectFit, upscale: true, theme: theme)
    }
}
