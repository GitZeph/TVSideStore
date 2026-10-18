import Foundation
import SwiftUI

/// Model representing a sideloaded application on Apple TV.
public struct InstalledApp: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var originalBundleID: String
    public var rewrittenBundleID: String
    public var version: String
    public var installedDate: Date
    public var expirationDate: Date
    public var sourceURL: URL?
    public var cachedIPAPath: String?
    public var iconData: Data?
    public var isSelf: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        originalBundleID: String,
        rewrittenBundleID: String,
        version: String = "1.0.0",
        installedDate: Date = Date(),
        expirationDate: Date = Date().addingTimeInterval(7 * 86400),
        sourceURL: URL? = nil,
        cachedIPAPath: String? = nil,
        iconData: Data? = nil,
        isSelf: Bool = false
    ) {
        self.id = id
        self.name = name
        self.originalBundleID = originalBundleID
        self.rewrittenBundleID = rewrittenBundleID
        self.version = version
        self.installedDate = installedDate
        self.expirationDate = expirationDate
        self.sourceURL = sourceURL
        self.cachedIPAPath = cachedIPAPath
        self.iconData = iconData
        self.isSelf = isSelf
    }

    /// Days remaining until the free developer certificate expires (7-day window)
    public var daysRemaining: Int {
        let diff = expirationDate.timeIntervalSince(Date())
        return max(0, Int(diff / 86400))
    }

    /// Total hours remaining
    public var hoursRemaining: Int {
        let diff = expirationDate.timeIntervalSince(Date())
        return max(0, Int(diff / 3600))
    }

    public var isExpired: Bool {
        return Date() >= expirationDate
    }

    /// Trigger threshold for automatic background refresh
    public var needsRefresh: Bool {
        return daysRemaining <= 3
    }

    /// Badge color code based on expiration urgency
    public var statusBadgeColor: Color {
        if isExpired {
            return .gray
        } else if daysRemaining > 4 {
            return .green
        } else if daysRemaining >= 2 {
            return .yellow
        } else {
            return .red
        }
    }

    public var formattedCountdown: String {
        if isExpired {
            return "EXPIRED"
        } else if daysRemaining >= 1 {
            return "\(daysRemaining) DAYS"
        } else {
            return "\(hoursRemaining) HOURS"
        }
    }
}

