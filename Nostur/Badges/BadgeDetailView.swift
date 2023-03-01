//
//  BadgeDetailView.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/03/2023.
//

import SwiftUI
import Nuke
import NukeUI


struct BadgeDetailView: View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var up:Unpublisher
    @EnvironmentObject var ns:NosturState
    
    @State var awardToPeopleIsShown = false
    
    var badge:Event
    var nBadge:NEvent { badge.toNEvent() }
    
    @FetchRequest
    var badgeAwards:FetchedResults<Event>
//    var nBadgeAwards:[NEvent] { badgeAwards.map { $0.toNEvent() }.filter { $0.badgeDescription != nil && $0.badgeDefinition!.value == nBadge.badgeDefinition!.value } }
    
    init(badge:Event) {
        print("🧨🧨🧨🧨🧨 BadgeDetailView 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
        self.badge = badge
        let r = Event.fetchRequest()
        r.predicate = NSPredicate(format: "kind == 8 AND tagsSerialized CONTAINS %@", "[\"a\",\"\(badge.toNEvent().badgeDefinition!.value)") // OPTIMISATION HACK
        r.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
        _badgeAwards = FetchRequest(fetchRequest: r)
    }
    
    var body: some View {
        ScrollView {
            HStack(alignment: .top) {
                VStack(alignment: .center) {
                    if nBadge.badgeImage?.otherInformation[safe: 0] != nil {
                        LazyImage(url: URL(string: nBadge.badgeImage!.otherInformation[safe: 0]!)) { state in
                            if let image = state.image {
                                image.frame(width: 50, height: 50)
                            }
                            else {
                                ProgressView()
                            }
                        }
                        .processors([ImageProcessors.Resize(width: 50)])
                        .animation(nil)
                        .pipeline(ImageProcessing.shared.pipeline)
                        .padding(10)
                    }
                }
                .frame(width: 60)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(nBadge.badgeName?.value ?? "No name")
                        .font(.subheadline)
                    Text(nBadge.badgeDescription?.value ?? "No description").font(.caption2)
                    Text("Awarded to \(badge.awardedTo.count) people").font(.caption)
                }.padding(10)
            }
            Spacer()
            
            
            Button { awardToPeopleIsShown = true } label: { Text("Award to people") }
                .buttonStyle(.borderedProminent)
            // award to people
            
            // lazy vstack foreach award p
            ForEach(badge.badgeAwards) { award in
                Text("Awarded to \(award.toNEvent().pTags().count) people on \(Date(timeIntervalSince1970: Double(award.created_at)).formatted())")
            }
        }
        .sheet(isPresented: $awardToPeopleIsShown) {
            AwardToPeopleSheet(onFinish: { contacts in
                let newBadgeAwards = createBadgeAward(badgeDefinitionId: nBadge.id,
                                                      pubkeys: contacts.map { $0.pubkey })
                
                do {
                    guard let newBadgeAwardsSigned = try? ns.signEvent(newBadgeAwards) else { throw "could not create newBadgeAwardsSigned " }
                    _ = Event.saveEvent(event: newBadgeAwardsSigned, context: viewContext)
                    try viewContext.save()
//                    print(newBadgeAwardsSigned.wrappedEventJson())
                    up.publishNow(newBadgeAwardsSigned)
                }
                catch {
                    print("🔴🔴 could not create badge")
                    print(error)
                }
            })
        }
    }
}

struct BadgeDetailView_Previews: PreviewProvider {
    static var previews: some View {
        
        let badge = PreviewFetcher.fetchEvent("6215b9fee3834ff25da4962dfb0d72e3dd648a454491dc213da5bdf735d7ddd9")
        
        if (badge != nil) {
            BadgeDetailView(badge: badge!)
                .withPreviewEnvironment()
        }
    }
}
