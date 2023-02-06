//
//  ReversedScrollView.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/02/2023.
//

import SwiftUI

struct ReversedScrollView<Content: View>: View {
    var axis: Axis.Set
    var leadingSpace: CGFloat
    var content: Content
    
    init(_ axis: Axis.Set = .horizontal, leadingSpace: CGFloat = 10, @ViewBuilder builder: ()->Content) {
        self.axis = axis
        self.leadingSpace = leadingSpace
        self.content = builder()
    }
    
    var body: some View {
        GeometryReader { proxy in
            ScrollView(axis) {
                Stack(axis) {
                    Spacer(minLength: leadingSpace)
                    content
                }
                .frame(
                    minWidth: minWidth(in: proxy, for: axis),
                    minHeight: minHeight(in: proxy, for: axis)
                )
            }
        }
    }
    
    func minWidth(in proxy: GeometryProxy, for axis: Axis.Set) -> CGFloat? {
       axis.contains(.horizontal) ? proxy.size.width : nil
    }
        
    func minHeight(in proxy: GeometryProxy, for axis: Axis.Set) -> CGFloat? {
       axis.contains(.vertical) ? proxy.size.height : nil
    }
}

struct Stack<Content: View>: View {
    var axis: Axis.Set
    var content: Content
    
    init(_ axis: Axis.Set = .vertical, @ViewBuilder builder: ()->Content) {
        self.axis = axis
        self.content = builder()
    }
    
    var body: some View {
        switch axis {
        case .horizontal:
            HStack {
                content
            }
        case .vertical:
            VStack {
                content
            }
        default:
            VStack {
                content
            }
        }
    }
}

struct ReversedScrollViewExample: View {
    
    @Namespace var SCROLL_ANCHOR
     
    @State var items = Array(0..<15)
    
    @State var scrollOffset = CGFloat.zero
    @State var anchorOffset = CGFloat.zero
    @State var contentHeight = CGFloat.zero
    
    @State var oldScrollOffset = CGFloat.zero
    @State var oldContentHeight = CGFloat.zero
    
    var body: some View {
        
        VStack {
            Text("Items: \(items.count)\nScroll offset: \(scrollOffset)\nAnchor offset: \(anchorOffset)\nContent height: \(contentHeight)\nScroll-Anchor diff:\(anchorOffset - scrollOffset)")
            Button { scrollOffset = scrollOffset + 50 } label: { Text("Set scroll offset +50") }
            Button { anchorOffset = anchorOffset + 150 } label: { Text("Increase anchor offset by +150") }
            Button {
                // STEPS
                // 1. ✅ GET HEIGHT OF TOTAL ITEMS AND SCROLL OFFSET
//                oldAnchorOffset = anchorOffset
                oldContentHeight = contentHeight
                oldScrollOffset = scrollOffset
                // 2. ✅ ADD NEW ITEMS
                items.append(items.count)
                items.append(items.count)
                items.append(items.count)
                // 3. ✅ GET NEW TOTAL HEIGHT
//                let newHeight = contentHeight
                // 4. SET SCROLL OFFSET TO: NEW_HEIGHT-OLD_HEIGHT + OLD OFFSET
//                anchorOffset = (contentHeight - oldContentHeight) + oldAnchorOffset
//                scrollCounter += 1
                
            } label: {
                Text("Add item")
            }
            NavigationView {
                
                ObservableScrollView(scrollOffset: $scrollOffset, contentHeight: $contentHeight) { proxy in
                    ZStack {
                        VStack {
                            ForEach(items.reversed(), id:\.self) { item in
                                Text("\(item)")
                                    .padding()
                                    .background(Color.gray.opacity(0.5))
                                    .cornerRadius(6)
                            }
                        }
                        VStack(spacing: 0) {
                            Rectangle().frame(width:370, height: anchorOffset).foregroundColor(.red)
                            Rectangle().frame(width: 370, height: 0)
                                .id(SCROLL_ANCHOR)
                            Spacer()
                        }
                    }
                    // This will work with items last I think????
                    .onChange(of: items) { newItems in
                        anchorOffset = contentHeight - oldContentHeight + oldScrollOffset
                        proxy.scrollTo(SCROLL_ANCHOR, anchor: .top)
                    }
                    .onChange(of: scrollOffset) { newScrollOfset in
                        anchorOffset = newScrollOfset // KEEP SCROLL ANCHOR IN SYNC WITH SCROLL OFFSET
                    }
                }
            }
        }
    }
}






// Simple preference that observes a CGFloat.
struct ScrollViewContentHeightPreferenceKey: PreferenceKey {
  static var defaultValue = CGFloat.zero

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value += nextValue()
  }
}

// Simple preference that observes a CGFloat.
struct XXX: PreferenceKey {
    static var defaultValue = 0.0

  static func reduce(value: inout Double, nextValue: () -> Double) {
    value += nextValue()
  }
}

// Simple preference that observes a CGFloat.
struct ScrollViewOffsetPreferenceKey: PreferenceKey {
  static var defaultValue = CGFloat.zero

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value += nextValue()
  }
}

// A ScrollView wrapper that tracks scroll offset changes.
struct ObservableScrollView<Content>: View where Content : View {
  @Namespace var scrollSpace

  @Binding var scrollOffset: CGFloat
  @Binding var contentHeight: CGFloat
  let content: (ScrollViewProxy) -> Content

    init(scrollOffset: Binding<CGFloat>, contentHeight: Binding<CGFloat>,
       @ViewBuilder content: @escaping (ScrollViewProxy) -> Content) {
    _scrollOffset = scrollOffset
        _contentHeight = contentHeight
    self.content = content
  }

  var body: some View {
    ScrollView {
      ScrollViewReader { proxy in
        content(proxy)
          .background(GeometryReader { geo in
              let offset = -geo.frame(in: .named(scrollSpace)).minY
              let height = geo.size.height
//              Color.clear.onAppear {
//                  scrollOffset = offset
//                  contentHeight = height
//              }
              
              Color.clear
                .preference(key: ScrollViewOffsetPreferenceKey.self,
                            value: offset)
              Color.clear
                .preference(key: ScrollViewContentHeightPreferenceKey.self,
                            value: height)
          })
      }
    }
    .coordinateSpace(name: scrollSpace)
    .onPreferenceChange(ScrollViewOffsetPreferenceKey.self) { value in
      scrollOffset = value
    }
    .onPreferenceChange(ScrollViewContentHeightPreferenceKey.self) { value in
      contentHeight = value
    }
  }
}

struct ReversedScrollView_Previews: PreviewProvider {
    static var previews: some View {
        ReversedScrollViewExample()
    }
}
