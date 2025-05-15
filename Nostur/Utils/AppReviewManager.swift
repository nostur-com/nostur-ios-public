import SwiftUI
import StoreKit

@available(iOS 16.0, *)
class AppReviewManager: ObservableObject {
    static let shared = AppReviewManager()
    
    public var requestReview: RequestReviewAction? = nil
    
    private let userDefaults = UserDefaults.standard
    private let firstLaunchKey = "first_launch_date"
    private let lastReviewRequestKey = "last_review_request_date"
    private let consecutiveDaysKey = "consecutive_days_used"
    private let lastUsedDateKey = "last_used_date"
    private let hasLikedOrReactedKey = "has_liked_or_reacted"
    private let hasZappedKey = "has_zapped"
    private let hasUsedPostPreviewKey = "has_used_post_preview"
    private let hasUsedPostKey = "has_used_post"
    
    @Published var didJustReachEndOfFeed = false {
        didSet {
            if oldValue == false && didJustReachEndOfFeed {
                if shouldRequestReview() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.requestReview?()
                        self.setLastReviewRequest()
                    }
                }
            }
        }
    }
    
    private init() {
        // Set first launch date if not set
        if userDefaults.object(forKey: firstLaunchKey) == nil {
            userDefaults.set(Date(), forKey: firstLaunchKey)
        }
    }
    
    public func trackAppUsage() {
        let calendar = Calendar.current
        let today = Date()
        
        // Get last used date
        if let lastUsedDate = userDefaults.object(forKey: lastUsedDateKey) as? Date {
            // Check if last used was yesterday
            if calendar.isDateInYesterday(lastUsedDate) {
                // Increment consecutive days
                let currentConsecutiveDays = userDefaults.integer(forKey: consecutiveDaysKey)
                userDefaults.set(currentConsecutiveDays + 1, forKey: consecutiveDaysKey)
            } else if !calendar.isDateInToday(lastUsedDate) {
                // Reset consecutive days if not used yesterday
                userDefaults.set(1, forKey: consecutiveDaysKey)
            }
        } else {
            // First time using the app
            userDefaults.set(1, forKey: consecutiveDaysKey)
        }
        
        // Update last used date
        userDefaults.set(today, forKey: lastUsedDateKey)
    }
    
    public func trackLikeOrReaction() {
        userDefaults.set(true, forKey: hasLikedOrReactedKey)
    }
    
    public func trackZap() {
        userDefaults.set(true, forKey: hasZappedKey)
    }
    
    public func trackPostPreviewUsage() {
        userDefaults.set(true, forKey: hasUsedPostPreviewKey)
    }
    
    public func trackPostUsage() {
        userDefaults.set(true, forKey: hasUsedPostKey)
    }
    
    public func shouldRequestReview() -> Bool {
        // Don't interupt user, only ask when feed unread goes from N to 0.
        guard didJustReachEndOfFeed else { return false }
        
        // Check if user has been using the app for at least 2 weeks
        guard let firstLaunchDate = userDefaults.object(forKey: firstLaunchKey) as? Date else {
            return false
        }
        
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        guard firstLaunchDate < twoWeeksAgo else {
            return false
        }
        
        // Check if user has used the app for 3 consecutive days
        let consecutiveDays = userDefaults.integer(forKey: consecutiveDaysKey)
        guard consecutiveDays >= 3 else {
            return false
        }
        
        // Check if user has liked/reacted or zapped
        let hasLikedOrReacted = userDefaults.bool(forKey: hasLikedOrReactedKey)
        let hasZapped = userDefaults.bool(forKey: hasZappedKey)
        guard hasLikedOrReacted || hasZapped else {
            return false
        }
        
        // Check if user has used all required features
        let hasUsedPostPreview = userDefaults.bool(forKey: hasUsedPostPreviewKey)
        let hasUsedPost = userDefaults.bool(forKey: hasUsedPostKey)
        guard hasUsedPostPreview && hasUsedPost else {
            return false
        }
        
        // Check if we haven't requested a review recently (at least 30 days)
        if let lastReviewRequest = userDefaults.object(forKey: lastReviewRequestKey) as? Date {
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            guard lastReviewRequest < thirtyDaysAgo else {
                return false
            }
        }
        
        return true
    }
    
    public func setLastReviewRequest() {
        userDefaults.set(Date(), forKey: lastReviewRequestKey)
    }
}
