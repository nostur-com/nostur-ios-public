//
//  CreateNewBadgeSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

import SwiftUI
import NavigationBackport

struct CreateNewBadgeSheet: View {
    
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var badgeCode = ""
    @State private var name = ""
    @State private var description = ""
    @State private var image1024 = ""
    @State private var image256 = ""
    
    private enum FocusedField {
        case badgeCode
    }
    
    @FocusState private var focusedField: FocusedField?
    
    private var accentColor: Color = .orange
    private var grayBackground: Color = Color.gray.opacity(0.2)
    
    var body: some View {
        Form {
            TextField(String(localized:"Code (bravery, verified_human, early_adoptor)", comment:"Label for input field for badge code on Badge creation screen"), text: $badgeCode)
                .lineLimit(1)
                .focused($focusedField, equals: .badgeCode)
            TextField(String(localized:"Name", comment:"Label for input field for badge name on Badge creation screen"), text: $name)
                .lineLimit(1)
            TextField(String(localized:"Description", comment:"Label for input field for badge description on Badge creation screen"), text: $description)
                .lineLimit(2)
            TextField(String(localized:"Image URL (1024x1024)", comment:"Label for input field for badge image on Badge creation screen"), text: $image1024)
                .lineLimit(1)
            TextField(String(localized:"Thumbnail URL (256x256)", comment:"Label for input field for badge image on Badge creation screen"), text: $image256)
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
        .navigationTitle(String(localized:"Create new badge", comment:"Navigation title for Badge creation screen"))
        .onAppear { focusedField = .badgeCode }
    }
    
    func createBadge() {
        let newBadge = createBadgeDefinition(badgeCode, name: name, description: description, image1024: image1024, thumb256: image256)
        
        do {    
            guard let newBadgeSigned = try? la.account.signEvent(newBadge) else { throw "could not create newBadgeSigned " }
            let bgContext = bg()
            bgContext.perform {
                _ = Event.saveEvent(event: newBadgeSigned, context: bgContext)
                DataProvider.shared().bgSave()
            }
            Unpublisher.shared.publishNow(newBadgeSigned)
        }
        catch {
            L.og.error("🔴🔴 could not create badge \(error)")
        }
    }
}

struct CreateNewBadgeSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadBadges() }) {
            NBNavigationStack {
                CreateNewBadgeSheet()
            }
        }
    }
}
