//
//  ScheduleReminderButton.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/09/2024.
//

import SwiftUI
import UserNotifications

struct ScheduleReminderButton: View {
    // TODO: keep track of already set reminders in LiveEventsModel
    @EnvironmentObject private var themes: Themes
    let at: Date
    var name: String? = nil
    var reminderId: String?
    
    @State private var reminderIsSet: Bool = false
    @State private var errorText: String? = nil
    
    var body: some View {
        if reminderIsSet {
            Text("Reminder set!")
        }
        else if let errorText {
            Text(errorText)
        }
        else {
            Button {
                self.requestNotificationPermission()
            } label: {
                Text("Set reminder")
            }
            .buttonStyle(NosturButton(height: 36, bgColor: themes.theme.accent))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        
    }
    
    // Function to request notification permission
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                self.scheduleNotification()
            } else if error != nil {
                errorText = String(localized: "Nostur does not have permissions to set a reminder", comment: "Error message")
            } else {
                errorText = String(localized: "Nostur does not have permissions to set a reminder", comment: "Error message")
            }
        }
    }

    // Function to schedule a notification
    func scheduleNotification() {
        let content = UNMutableNotificationContent()
        content.title = name ?? "Going live"
        content.body = "\(name ?? "Nests or stream") is starting soon"
        content.sound = .default
        
        // Create a trigger based on the selected date
        let fiveMinutesBefore = at.addingTimeInterval(-300)  // Subtract 5 minutes (60 seconds * 5)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fiveMinutesBefore)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: reminderId ?? UUID().uuidString, content: content, trigger: trigger)

        // Add the notification request to the notification center
        UNUserNotificationCenter.current().add(request) { error in
            if error != nil {
                errorText = String(localized: "Nostur does not have permissions to set a reminder", comment: "Error message")
            } else {
                reminderIsSet = true
            }
        }
    }
}

#Preview {
    ScheduleReminderButton(at: .now.addingTimeInterval(3600), name: "Nust")
        .environmentObject(Themes.default)
}
