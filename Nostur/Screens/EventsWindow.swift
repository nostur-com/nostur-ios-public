//
//  EventsWindow.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/01/2023.
//

import SwiftUI

struct EventsWindow: View {
    
    @State var allItems = Array(1...500) // 0 = old, 500 = new
    @State var loadedItems:[Int] = []
    
    var initialItemsCount:Int = 30
    @State var lastOffset = 0
    
    func fetchMore() {
        for index in 1...5 {
            loadedItems.append(lastOffset+index)
        }
        lastOffset = lastOffset + 5
        unreadCount = updateUnreadCount()
    }

    func removeFirst() {
        loadedItems.remove(at: 0)
    }
    
    @State var lastReadDate = 0
    @State var unreadCount = 0
    
    func updateUnreadCount() -> Int {
        return loadedItems.filter { $0 > lastReadDate }.count
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack {
                    HStack {
                        ControlGroup {
                            Button { proxy.scrollTo("TOP", anchor: .bottom) } label: { Text("toBottom") }
                            Button {
                                removeFirst()
                                proxy.scrollTo(loadedItems.last, anchor: .bottom)
                            } label: { Text("removeFirst") }
                            Button { fetchMore() } label: { Text("fetchMore") }
                            Text("\(unreadCount)")
                        }
                    }
                    ScrollView {
                        LazyVStack {
                            ForEach(loadedItems, id:\.self) { item in
                                VStack {
                                    HStack {
                                        Spacer()
                                        Text("item: \(item)").font(.largeTitle)
                                            .scaleEffect(x: 1, y: -1)
                                        Spacer()
                                    }
                                    .onAppear {
                                        lastReadDate = item >= lastReadDate ? item : lastReadDate
                                        unreadCount = updateUnreadCount()
                                    }
                                    Divider()
                                }
                            }
                            Color.clear
                                .frame(width: 100, height: 1, alignment: .bottom)
                                .id("TOP")
                                .onAppear {
                                    print("ON APPEAAR 😡")
                                    if (loadedItems.count > 10) {
                                        removeFirst()
                                        print("ON APPEAAR 😡😡")
                                        removeFirst()
                                        print("ON APPEAAR 😡😡")
                                        removeFirst()
                                        print("ON APPEAAR 😡😡")
                                        proxy.scrollTo("TOP", anchor: .bottom)
                                    }
                                }
                        }
                    }
                .scaleEffect(x: 1, y: -1)
            }.onAppear {
                fetchMore()
                sleep(2)
                proxy.scrollTo(25)
            }
        }

    }
}

struct EventsWindow_Previews: PreviewProvider {
    static var previews: some View {
        EventsWindow()
    }
}
