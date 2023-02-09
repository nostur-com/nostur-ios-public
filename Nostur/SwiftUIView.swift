//
//  SwiftUIView.swift
//  Nostur
//
//  Created by Fabian Lachman on 09/02/2023.
//

import SwiftUI
import Introspect

struct ScrollListOnChangeIos16: View {
    var events:[Event] = []

    // The .introspectX view modifiers will populate scroller
    // they are actually UITableView or UICollectionView which both decend from UIScrollView
    // https://github.com/siteline/SwiftUI-Introspect/releases/tag/0.1.4
    @State private var scroller: UIScrollView?
    
    func scrollToTop() {
        scroller?.setContentOffset(CGPoint(x: 0, y: 0), animated: true)
    }
    
    func scrollToBottom() {
        // Making this async seems to make scroll more consistent to happen after
        // items has been updated. *shrug?*
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            guard let scroller = self.scroller else { return }
            let yOffset = scroller.contentSize.height - scroller.frame.height
            if yOffset < 0 { return }
            scroller.setContentOffset(CGPoint(x: 0, y: yOffset), animated: true)
        }
    }
        
    var body: some View {
        VStack {
            
            HStack {
                Button("Top") {
                    scrollToTop()
                }
                Spacer()
                
                Button("Bottom") {
                    scrollToBottom()
                }
            }.padding()

            // The source of all my pain ...
            List(events.indices, id:\.self) { index in
                NoteRowView(event: events[index])
                    .id(index)
                    .listRowInsets(EdgeInsets())
//                    .scaleEffect(x: 1, y: -1)
            }
            .listStyle(.plain)
            .padding(.bottom, 50)
            
        }
            
        /* in iOS 16 List is backed by UICollectionView, no out of the box .introspectMethod ... nbd. */
        .introspect(selector: TargetViewSelector.ancestorOrSiblingContaining, customize: { (collectionView: UICollectionView) in
            guard #available(iOS 16, *) else { return }
            self.scroller = collectionView
        })

        /* in iOS 15 List is backed by UITableView ... */
        .introspectTableView(customize: { tableView in
            guard #available(iOS 15, *) else { return }
            self.scroller = tableView
        })
    }
}


struct ScrollListOnChangeIos16_Previews: PreviewProvider {
    static var previews: some View {
        
        let notes = PreviewFetcher.fetchEvents("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0")
        
        ScrollListOnChangeIos16(events: notes)
            .withPreviewEnvironment()

    }
}
