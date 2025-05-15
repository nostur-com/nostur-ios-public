import SwiftUI
import StoreKit

@available(iOS 16.0, *)
struct AppReviewView: View {
    @Environment(\.requestReview) private var requestReview
    @StateObject private var reviewManager = AppReviewManager.shared
    
    var body: some View {
        Color.clear
            .onAppear {
                reviewManager.requestReview = requestReview
                reviewManager.trackAppUsage()
            }
    }
}

@available(iOS 16.0, *)
#Preview {
    AppReviewView()
} 
