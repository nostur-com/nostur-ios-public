//
//  DatabaseProblemView.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/03/2025.
//

import SwiftUI

struct DatabaseProblemView: View {
    var body: some View {
        VStack {
            Text("Something went wrong")
                .font(.title2)
            Text("The database could not be loaded.")
                .padding(.bottom, 20)
            Text("Sorry, this was not supposed to happen.")
                .padding(.bottom, 20)
        }
        VStack(alignment: .leading) {
            Text("There are 2 solutions:")
            Text("1) Send screenshot of this error and wait for an update with fix")
            Text("2) Reinstall the app and start fresh")
                .padding(.bottom, 20)
            Text("Error: 00")
            Text(DataProvider.shared().databaseProblemDescription)
        }
        .padding()
    }
}

#Preview {
    DatabaseProblemView()
}
