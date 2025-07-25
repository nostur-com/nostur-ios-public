//
//  TopZaps.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/04/2024.
//

import SwiftUI
import SwiftUIFlow

struct TopZaps: View {
    @Environment(\.theme) private var theme
    public let id: String
    
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)], predicate: NSPredicate(value: false))
    private var zaps: FetchedResults<Event>
    private var zapsSorted: [Event] {
        zaps
            .sorted(by: { $0.naiveSats > $1.naiveSats })
            .uniqued(on: { $0.id })
    }
    
    @State private var verifiedZaps: [ZapAndZapFrom] = []
    @State var actualSize: CGSize? = nil
    @Namespace private var animation
    @State private var animateUpdate = UUID()
  
    
    init(id: String) {
        self.id = id
        _zaps = FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: true)], predicate: NSPredicate(format: "zappedEventId == %@ AND kind == 9735", id))
    }
    
    var body: some View {
        Flow(.vertical, alignment: .topLeading) {
            if let actualSize {
                ForEach(verifiedZaps.indices, id: \.self) { index in
                    ZapPill(zap: verifiedZaps[index], index: index, availableWidth: actualSize.width)
                        .id(verifiedZaps[index].id)
                        .matchedGeometryEffect(id: verifiedZaps[index].id, in: animation)
                }
            }
        }
        .animation(.easeIn, value: animateUpdate)
        .frame(maxHeight: 75, alignment: .topLeading) // Max 3 rows
        .clipped()
        .drawingGroup()
        .readSize { size in
            guard actualSize == nil else { return }
            actualSize = size
        }
         .nosturNavBgCompat(theme: theme)
        .onAppear {
            loadZaps(zapsSorted)
        }
        .onChange(of: zapsSorted) { newZapsSorted in
            loadZaps(newZapsSorted)
        }
    }
    
    private func loadZaps(_ zaps: [Event]) {
        verifiedZaps = zaps
            .filter { $0.flags != "zpk_mismatch_event" }
            .prefix(17)
            .compactMap({ zap in
                guard let zapFrom = zap.zapFromRequest else { return nil }
                return ZapAndZapFrom(zap: zap, zapFrom: zapFrom)
            })
        animateUpdate = UUID()
    }
}

struct ZapAndZapFrom: Identifiable {
    var id: String { zap.id }
    let zap: Event
    let zapFrom: Event
}

struct ZapPill: View {
    @Environment(\.theme) private var theme
    public var zap: ZapAndZapFrom
    public var index: Int
    public var availableWidth: CGFloat
    
    @State private var pfpURL: URL?
    
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .foregroundColor(randomColor(seed: zap.zapFrom.pubkey))
                .frame(width: 20.0, height: 20.0)
                .overlay {
                    if let pfpURL {
                        MiniPFP(pictureUrl: pfpURL, size: 20.0)
                            .animation(.easeIn, value: pfpURL)
                    }
                }
            Text(zap.zap.naiveSats.satsFormatted)
                .foregroundColor(theme.accent)
                .padding(.trailing, 5)
            if index < 3, let content = zap.zapFrom.content {
                Text(content)
                    .padding(.trailing, 5)
                    .lineLimit(1)
            }
        }
        .background(theme.listBackground.opacity(0.5))
        .foregroundColor(theme.primary)
        .font(.footnote)
        .clipShape(Capsule())
        .frame(maxWidth: index == 0 ? availableWidth : ((availableWidth-20) / 2))
        .onAppear {
            guard let pfpURL = zap.zapFrom.contact?.pictureUrl, self.pfpURL != pfpURL else { return }
            self.pfpURL = pfpURL
        }
        .onReceive(Kind0Processor.shared.receive.receive(on: RunLoop.main)) { profile in
            guard profile.pubkey == zap.zapFrom.pubkey, pfpURL != profile.pictureUrl else { return }
            withAnimation {
                pfpURL = profile.pictureUrl
            }
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadZaps()
    }) {
        TopZaps(id: "7682031bb0b06d7b9c417dae30141357a74b4f089ebd46226990d418e2def565")
    }
}
