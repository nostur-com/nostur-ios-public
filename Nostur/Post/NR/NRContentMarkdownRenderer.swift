import SwiftUI
import MarkdownUI

// Same as NRContentTextRenderer, but with Markdown instead of AttributedString
struct NRContentMarkdownRenderer: View {
    
    let markdownContentWithPs:MarkdownContentWithPs
    let fullWidth = false
    @State var text:MarkdownContent? = nil
    
    var body: some View {
        Markdown(text ?? markdownContentWithPs.output)
            .markdownTextStyle() {
//                FontSize(.em(1.85))
                
                
//              FontFamily(.custom("Charter-Black"))
                FontFamily(.custom("Charter"))
//                FontSize(.rem(3.0))
//              FontFamily(.custom("Georgia"))
//              FontWeight(.bold)
                
                
                ForegroundColor(Color.primary)
                BackgroundColor(Color(.secondarySystemBackground))
//                BackgroundColor(Color.systemBackground)
                
                FontSize(22)
            }
            .markdownTextStyle(\.link) {
                ForegroundColor(Color.accentColor)
                UnderlineStyle(.single)
            }
//            .foregroundColor(Color.red)
//            .font(Font.custom("Charter-Black", size: 20))
//            .font(Font.custom("Georgia", size: 20))
//            .font(.custom("Charter", size: 28))
//            .lineSpacing(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, fullWidth ? 10 : 0)
            .onReceive(
                receiveNotification(.contactSaved)
                    .map({ notification in
                        return notification.object as! String
                    })
                    .filter({ pubkey in
                        guard !markdownContentWithPs.input.isEmpty else { return false }
                        guard !markdownContentWithPs.pTags.isEmpty else { return false }
                        return self.markdownContentWithPs.pTags.contains(pubkey)
                    })
                    .debounce(for: .seconds(0.05), scheduler: RunLoop.main)
            ) { pubkey in
                
                DataProvider.shared().bg.perform {
                    let reparsed = NRTextParser.shared.parseMD(markdownContentWithPs.event, text: markdownContentWithPs.input)
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
