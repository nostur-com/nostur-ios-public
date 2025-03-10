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
            .markdownImageProvider(.nukeImage)
            .markdownInlineImageProvider(.nukeImage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, fullWidth ? 10 : 0)
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
  func makeImage(url: URL?) -> some View {
      if let url = url {
          SingleMediaViewer(url: url, pubkey: "", height: 1200, imageWidth: DIMENSIONS.shared.listWidth, fullWidth: true, autoload: true, contentPadding: 20, upscale: true)
      }
      else {
          EmptyView()
      }
  }
}

extension ImageProvider where Self == NukeImageProvider {
  static var nukeImage: Self {
    .init()
  }
}

class NukeInlineImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        let imageWidth = DIMENSIONS.shared.listWidth
        
        let imageRequest = await ImageRequest(url: url,
                                          processors: [.resize(width: imageWidth, upscale: false)],
                                          options: SettingsStore.shared.lowDataMode ? [.returnCacheDataDontLoad] : [],
                                          userInfo: [.scaleKey: UIScreen.main.scale])
        
        let task = ImageProcessing.shared.content.imageTask(with: imageRequest)
        
        let response = try await task.response
        
        return Image(uiImage: response.image)
    }
}

extension InlineImageProvider where Self == NukeInlineImageProvider {
  static var nukeImage: Self {
    .init()
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

