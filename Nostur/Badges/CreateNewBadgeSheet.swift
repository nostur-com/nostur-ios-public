//
//  CreateNewBadgeSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

import SwiftUI

struct CreateNewBadgeSheet: View {
    
    @EnvironmentObject var ns:NosturState
    let up:Unpublisher = .shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State var badgeCode = ""
    @State var name = ""
    @State var description = ""
    @State var image1024 = ""
    @State var image256 = ""
    
    enum FocusedField {
        case badgeCode
    }
    
    @FocusState private var focusedField: FocusedField?
    
    var accentColor: Color = .orange
    var grayBackground: Color = Color.gray.opacity(0.2)
    
    var body: some View {
        Form {
            TextField("Code (bravery, verified_human, early_adoptor)", text: $badgeCode)
                .lineLimit(1)
                .focused($focusedField, equals: .badgeCode)
            TextField("Name", text: $name)
                .lineLimit(1)
            TextField("Description", text: $description)
                .lineLimit(2)
            TextField("Image URL (1024x1024)", text: $image1024)
                .lineLimit(1)
            TextField("Thumbnail URL (256x256)", text: $image256)
                .lineLimit(1)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: {
                    dismiss()
                }, label: {
                    Text("Cancel")
                })
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    createBadge()
                    dismiss()
                }, label: {
                    Text("Done")
                }).disabled(name == "" || description == "" || badgeCode == "")
            }
        }
        .navigationTitle("Create new badge")
        .onAppear { focusedField = .badgeCode }
    }
    func createBadge() {
        let newBadge = createBadgeDefinition(badgeCode, name: name, description: description, image1024: image1024, thumb256: image256)

        do {    
            guard let newBadgeSigned = try? ns.signEvent(newBadge) else { throw "could not create newBadgeSigned " }
            _ = Event.saveEventFromMain(event: newBadgeSigned)
            DataProvider.shared().bgSave()
//            print(newBadgeSigned.wrappedEventJson())
            up.publishNow(newBadgeSigned)
        }
        catch {
            print("🔴🔴 could not create badge")
            print(error)
        }
    }
}

struct CreateNewBadgeSheet_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CreateNewBadgeSheet()
                .withPreviewEnvironment({ pe in pe.loadBadges() })
        }
    }
}
