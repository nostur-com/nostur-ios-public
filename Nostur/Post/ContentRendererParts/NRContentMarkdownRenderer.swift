//
//  NRContentMarkdownRenderer.swift
//  Nostur
//
//  Created by Fabian Lachman on 22/06/2023.
//

import SwiftUI
import MarkdownUI
import NukeUI

// Same as NRContentTextRenderer, but with Markdown instead of AttributedString
struct NRContentMarkdownRenderer: View {
    public let markdownContentWithPs: MarkdownContentWithPs
    public let fullWidth = false
    public var theme: Theme
    public var maxWidth: CGFloat
    @State var text: MarkdownContent? = nil
    
    var body: some View {
        Markdown(text ?? markdownContentWithPs.output)
            .textSelection(.enabled)
            .markdownBlockStyle(\.table) { configuration in
              configuration.label
                .hScroll(maxWidth: maxWidth)
            }
            .markdownTextStyle() {
                FontFamily(.custom("Charter"))
                ForegroundColor(Color.primary)
                BackgroundColor(Color(.secondarySystemBackground))
                FontSize(22)
            }
            .markdownTextStyle(\.link) {
                ForegroundColor(theme.accent)
            }
            .markdownImageProvider(.nukeImage(maxWidth: maxWidth))
            .markdownInlineImageProvider(.nukeImage(maxWidth: maxWidth))
            .frame(maxWidth: .infinity, alignment: .leading)
//            .padding(.horizontal, 20)
            .onReceive(
                ViewUpdates.shared.contactUpdated
                    .receive(on: RunLoop.main)
                    .filter { (pubkey, _) in
                        guard !markdownContentWithPs.input.isEmpty else { return false }
                        guard !markdownContentWithPs.pTags.isEmpty else { return false }
                        return self.markdownContentWithPs.pTags.contains(pubkey)
                    }
//                    .debounce(for: .seconds(0.05), scheduler: RunLoop.main)
            ) { pubkey in
                bg().perform {
                    guard let event = markdownContentWithPs.event else { return }
                    let reparsed = NRTextParser.shared.parseMD(event, text: markdownContentWithPs.input)
                    DispatchQueue.main.async {
                        L.og.debug("Reparsed: \(reparsed.input) ----> \(reparsed.output.renderPlainText())")
                        if self.text != reparsed.output {
                            self.text = reparsed.output
                        }
                    }
                }
            }
    }
}


struct NukeImageProvider: ImageProvider {
    let maxWidth: CGFloat
    
    init(maxWidth: CGFloat) {
        self.maxWidth = maxWidth
    }
    
    func makeImage(url: URL?) -> some View {
        if let url = url {
            MediaContentView(
                galleryItem: GalleryItem(url: url),
                availableWidth: maxWidth,
                placeholderHeight: maxWidth / 2, // 1:2 guess??
                contentMode: .fill,
                upscale: true,
                autoload: true
            )
            .padding(.horizontal, -20)
        }
        else {
            EmptyView()
        }
    }
}

extension ImageProvider where Self == NukeImageProvider {
    static func nukeImage(maxWidth: CGFloat) -> Self {
        .init(maxWidth: maxWidth)
    }
}

class NukeInlineImageProvider: InlineImageProvider {
    let maxWidth: CGFloat
    
    init(maxWidth: CGFloat) {
        self.maxWidth = maxWidth
    }
    
    func image(with url: URL, label: String) async throws -> Image {
        let imageRequest = makeImageRequest(url, label: "NukeInlineImageProvider")
        
        let task = ImageProcessing.shared.content.imageTask(with: imageRequest)
        
        let response = try await task.response
        
        return Image(uiImage: response.image)
    }
}

extension InlineImageProvider where Self == NukeInlineImageProvider {
    static func nukeImage(maxWidth: CGFloat) -> Self {
        .init(maxWidth: maxWidth)
    }
}


struct NoImageProvider: ImageProvider {
  func makeImage(url: URL?) -> some View {
      EmptyView()
  }
}

extension ImageProvider where Self == NoImageProvider {
  static var noImage: Self {
    .init()
  }
}

class NoInlineImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        return Image(systemName: "photo")
    }
}

extension InlineImageProvider where Self == NoInlineImageProvider {
  static var noImage: Self {
    .init()
  }
}

