//
//  TL.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/02/2023.
//

import SwiftUI

class FakeNote: Identifiable, ObservableObject {
    @Published var name:String
    @Published var id = UUID()
    
    init(name: String, id: UUID = UUID()) {
        self.name = name
        self.id = id
    }
}

class FakeData {
    var notes:[FakeNote] = []
    
    init() {
        for index in 0..<200 {
            notes.append(FakeNote(name: "Name\(index)"))
        }
    }
}

struct TL: View {

    
    @State private var fakeData = FakeData()
    @State private var notes:[FakeNote] = []
    @State private var count = 0

    var body: some View {
        let _  = Self._printChanges()
        List(notes) {
            FakeNoteRow(fakeNote: $0)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    withAnimation {
                        notes.insert(fakeData.notes[count], at: 0)
                    }
                    count = count + 1
                } label: {
                    Text("Add at top")
                }
                Button {
                    withAnimation {
                        _ = notes.remove(at: notes.count-1)
                    }
                    count = count + 1
                } label: {
                    Text("Remove last")
                }
            }
        }
    }
}

struct FakeNoteRow: View {
    @ObservedObject var fakeNote:FakeNote
    
    var body: some View {
        let _  = Self._printChanges()
        Text(fakeNote.name)
    }
}







struct Previews_TL_Previews: PreviewProvider {
    static var previews: some View {
        TL()
//            .withPreviewEnvironment()
    }
}
