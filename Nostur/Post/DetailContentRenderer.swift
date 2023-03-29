//
//  ArticleFormatting.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/03/2023.
//

import SwiftUI

// Renders embeds (VIEWS), not links (in TEXT)
struct DetailContentRenderer: View { // VIEW things
    
    let event:Event
    let textBuilder = ContentLinkRenderer()
    
    var body: some View {
        let input = event.noteTextPrepared
        //        let input = "The quick brown fox jumps over the lazy lazy dog."
        let imageUrlPattern = ###"http(s?):\/\/\S+\.(png|jpe?g|gif|webp|bmp|heic)"###
        let videoUrlPattern = ###"http(s?):\/\/\S+\.(mp4|mov)"###
        let hashtagPattarn = ###"\#\S+"###
        let lightningInvoicePattern = ###"lnbc\S+"###
        let notePattern = ###"nostr:note1\S+"###
        let neventPattern = ###"nostr:nevent1\S+"###
        let pattern = "\(imageUrlPattern)|\(lightningInvoicePattern)|\(notePattern)|\(neventPattern)|\(videoUrlPattern)"
        //        let pattern = ###"\\n"###
        
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: input.utf16.count)
        
        var result: [MarkdownElement] = []
        var lastMatchEnd = 0
        
        regex.enumerateMatches(in: input, options: [], range: range) { match, _, _ in
            if let match = match {
                let matchRange = match.range
                let nonMatchRange = NSRange(location: lastMatchEnd, length: matchRange.location - lastMatchEnd)
                let nonMatch = (input as NSString).substring(with: nonMatchRange)
                let matchString = (input as NSString).substring(with: matchRange)
                
                result.append(MarkdownElement.text(textBuilder.renderedText(event, text:nonMatch)))
                
                if matchString.matchingStrings(regex: imageUrlPattern).count > 0 {
                    result.append(MarkdownElement.image(URL(string: matchString)!))
                }
                else if matchString.matchingStrings(regex: videoUrlPattern).count > 0 {
                    result.append(MarkdownElement.video(URL(string: matchString)!))
                }
                else if matchString.matchingStrings(regex: notePattern).count > 0 {
                    let m = matchString.matchingStrings(regex:#"note1[023456789acdefghjklmnpqrstuvwxyz]{58}"#)
                    result.append(MarkdownElement.note1(m[0][0]))
                }
                else if matchString.matchingStrings(regex: neventPattern).count > 0 {
                    let m = matchString.matchingStrings(regex:#"nevent1\S+"#)
                    do {
                        let identifier = try ShareableIdentifier(m[0][0])
                        if let noteId = identifier.eventId {
                            result.append(MarkdownElement.noteId(noteId))
                        }
                    }
                    catch {
                        print("problem decoding nevent")
                        result.append(MarkdownElement.text(textBuilder.renderedText(event, text:matchString)))
                    }
                }
                else if matchString.matchingStrings(regex: lightningInvoicePattern).count > 0 {
                    result.append(MarkdownElement.lnbc(matchString))
                }
                else {
                    result.append(MarkdownElement.text(textBuilder.renderedText(event, text:matchString)))
                }
                
                lastMatchEnd = matchRange.location + matchRange.length
            }
            
        }
        
        let nonMatchRange = NSRange(location: lastMatchEnd, length: input.utf16.count - lastMatchEnd)
        let nonMatch = (input as NSString).substring(with: nonMatchRange)
        
        result.append(MarkdownElement.text(textBuilder.renderedText(event, text:nonMatch)))
        
        return
        VStack {
            ForEach(result.indices, id:\.self) { index in
                switch result[index] {
                    case .plain(let text):
                        Text(text)
                    case .note1(let noteId):
                        QuoteById(id: hex(noteId))
                    case .noteId(let hex):
                        QuoteById(id: hex)
                    case .text(let attributedString):
                        Text(attributedString)
                            .textSelection(.enabled)
                            .multilineTextAlignment(TextAlignment.leading)
                            .foregroundColor(.primary)
                            .lineSpacing(3)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .lnbc(let text):
                        LightningInvoice(invoice: text)
                    case .video(let url):
                        VideoPlayerView(videoURL: url)
                    case .image(let url):
                        SingleMediaViewer(url: url)
                    default:
                        Text("dunno")
                }
            }
        }
//        .border(.green)
    }
}


enum MarkdownElement: Hashable {
    case plain(String)
    case text(AttributedString)
    case note1(String)
    case noteId(String)
    case lnbc(String)
    case link(String, URL)
    case image(URL)
    case video(URL)
}


struct QuoteById: View {
    
    var sp:SocketPool = .shared
    var id:String
    
    @FetchRequest
    var events:FetchedResults<Event>
    
    init(id:String) {
        self.id = id
        
        _events = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "id == %@", id)
        )
    }
    
    var body: some View {
        if (events.first != nil) {
            QuotedNoteFragmentView(vPost: events.first!.toVPost())
        }
        else {
            ProgressView()
                .hCentered()
                .onAppear {
                    print("🟢 Fetching for QuotedNoteFragmentView \(id)")
                    sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEventAndReferences(id: id)))
                }
        }
    }
}



struct DetailContentRenderer_Previews: PreviewProvider {
    
    static var previews: some View {
        let event = PreviewFetcher.fetchEvent("e560475e1ea5166dfc968ef9ffbe79d87e801aa56b4098aeee4ad1aed4ace64b")
//        let event = PreviewFetcher.fetchEvent("9b34fd9a53398fb51493d68ecfd0d64ff922d0cdf5ffd8f0ffab46c9a3cf54e3")
        ScrollView {
            DetailContentRenderer(event: event!)
        }
    }
}
