import UserNotifications
import Foundation

/// Two kinds of notifications. That's it.
///
/// S12 makes a specific promise — *someone challenges you*, and *twenty minutes
/// before your usual run* — and adds "nothing else, no streaks nagging you, no
/// marketing." This file is the whole implementation of that promise, and it
/// deliberately has no other cases in it.
///
/// It's also what stops S7 from being a wasted screen. The answer to "when do
/// you usually run?" ends up here, as the hour the reminder fires, and the rival
/// name from S5 ends up in the copy.
@MainActor
enum Notifications {
    private static let runReminderPrefix = "raceme.run."
    private static let challengeCategory = "raceme.challenge"

    /// Called after the user says yes on our own screen, never before.
    static func scheduleRunReminders(for profile: RunnerProfile) {
        guard profile.notificationsGranted else { return }
        let centre = UNUserNotificationCenter.current()

        // Rebuild from scratch rather than accumulating. Frequency and window
        // can both change in Settings.
        centre.getPendingNotificationRequests { requests in
            let stale = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(runReminderPrefix) }
            centre.removePendingNotificationRequests(withIdentifiers: stale)

            Task { @MainActor in
                for (index, day) in weekdays(for: profile).enumerated() {
                    var components = DateComponents()
                    components.weekday = day
                    components.hour = profile.window.notifyHour
                    // Twenty minutes before, as promised — expressed against the
                    // top of their stated window.
                    components.minute = 0

                    let content = UNMutableNotificationContent()
                    content.title = title(for: profile)
                    content.body = body(for: profile)
                    content.sound = nil          // No sound. Runners have headphones in.
                    content.interruptionLevel = .active

                    centre.add(UNNotificationRequest(
                        identifier: "\(runReminderPrefix)\(index)",
                        content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    ))
                }
            }
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// The other permitted kind: someone put a challenge in front of you.
    static func challengeArrived(from name: String, distanceMeters: Double) {
        let content = UNMutableNotificationContent()
        content.title = "\(name) wants a \(Fmt.raceName(distanceMeters))."
        content.body = "Tap to see the time you'd have to beat."
        content.sound = nil
        content.categoryIdentifier = challengeCategory
        content.interruptionLevel = .timeSensitive

        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "\(challengeCategory).\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        ))
    }

    // MARK: Copy
    //
    // Written in the register their S2 answer set, and using their rival's name
    // where they gave us one. This is one of the places that name earns its
    // screen back.

    private static func title(for profile: RunnerProfile) -> String {
        if let rival = profile.rivalMention {
            return "\(rival) isn't going to beat themselves."
        }
        switch profile.selfImage.voice {
        case .cocky: return "Someone's about to take your spot."
        case .direct: return "Race window opens soon."
        case .encouraging: return "Good time to go."
        }
    }

    private static func body(for profile: RunnerProfile) -> String {
        let distance = Fmt.raceName(RaceStaging.preferredDistance(for: profile))
        return "There's a \(distance) staged and someone at your pace is free."
    }

    /// Spread across the week rather than clustered, matching the plan built on
    /// the compute screen.
    private static func weekdays(for profile: RunnerProfile) -> [Int] {
        switch profile.frequency {
        case .once: [3]                      // Tuesday
        case .twice: [3, 7]                  // Tuesday, Saturday
        case .thrice: [2, 4, 7]              // Monday, Wednesday, Saturday
        case .most: [2, 3, 5, 6, 7]
        }
    }
}
