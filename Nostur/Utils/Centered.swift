import SwiftUI

struct CenteredProgressView: View {
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            Spacer()
        }
    }
}

struct Centered_Previews: PreviewProvider {
    static var previews: some View {
        CenteredProgressView()
    }
}
