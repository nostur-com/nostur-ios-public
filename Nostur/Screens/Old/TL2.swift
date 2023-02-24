//
//  TL2.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/02/2023.
//

import SwiftUI

class FakeNote2: Identifiable, ObservableObject {
    @Published var name:String
    @Published var id = UUID()
    
    init(name: String, id: UUID = UUID()) {
        self.name = name
        self.id = id
    }
}

class FakeData2 {
    var notes:[FakeNote2] = []
    
    init() {
        for index in 0..<200 {
            notes.append(FakeNote2(name: "Name\(index)"))
        }
    }
}

struct TL2: View {
    
    @Namespace var startAnchor
    
    @State private var fakeData = FakeData2()
    @State private var notes:[FakeNote2] = []
    @State private var count = 0
    
    var body: some View {
        let _  = Self._printChanges()
        
        List {
            ForEach(notes) {
                FakeNoteRow2(fakeNote: $0)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    withAnimation {
                        notes.append(fakeData.notes[count])
                    }
                    count = count + 1
                } label: {
                    Text("Add new")
                }
                Button {
                    guard notes.count != 0 else { return }
                    withAnimation {
                        _ = notes.remove(at: 0)
                    }
                    count = count + 1
                } label: {
                    Text("Remove oldest")
                }
            }
        }
    }
}

struct FakeNoteRow2: View {
    @ObservedObject var fakeNote:FakeNote2
    
    var body: some View {
        let _  = Self._printChanges()
        Text(fakeNote.name)
            .frame(height: 200)
            .background(.red)
    }
}







struct Previews_TL2_Previews: PreviewProvider {
    static var previews: some View {
        TL2()
        //            .withPreviewEnvironment()
    }
}
