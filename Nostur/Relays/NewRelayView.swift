//
//  NewRelayView.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/01/2023.
//

import SwiftUI

struct NewRelayView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var cm:ConnectionManager
    
    @State var url = "wss://"
    
    var accentColor: Color = Color.blue
    var grayBackground: Color = Color.gray.opacity(0.2)
    

    fileprivate func addRelay() {
    
        let relay = Relay(context: viewContext)
        relay.id = UUID()
        relay.createdAt = Date()
        relay.url = url

        do {
            try viewContext.save()
            let relaySocket = RelaySocket(relay: relay, delegate: cm.eventReceivingDelegate!)
            print("🟣🟣 connecting to \(relay.url ?? "?")")
            relaySocket.connect()
            cm.relaySockets.append(relaySocket)
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        dismiss()
    }
    
    var body: some View {
        
        VStack{
            Text("Add relay")
                .font(.largeTitle)
                .foregroundColor(.accentColor)
                .fontWeight(.semibold)
                .padding(.bottom, 20)
            TextField("wss://relay...", text: $url)
                .keyboardType(.URL)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                .padding()
                .background(grayBackground)
                .cornerRadius(5.0)
                .padding(.bottom, 20)
            
            Button {
                addRelay()
            } label: {
                Text("Add")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(width: 220, height: 60)
                    .background(accentColor)
                    .cornerRadius(15.0)
            }
            Spacer()
//            Text("creates local account..").foregroundColor(.gray)
            
        }.padding()
    }
}

struct NewRelayView_Previews: PreviewProvider {
    static var previews: some View {
        NewRelayView()
    }
}
