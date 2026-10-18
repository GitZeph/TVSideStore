import Foundation

/// Data models for AltStore and SideStore repository compatibility.
public struct AltSourceRepo: Identifiable, Codable, Equatable {
    public var id: String { identifier }
    public var name: String
    public var identifier: String
    public var sourceURL: URL
    public var subtitle: String?
    public var description: String?
    public var iconURL: URL?
    public var apps: [AltSourceApp]

    public init(
        name: String,
        identifier: String,
        sourceURL: URL,
        subtitle: String? = nil,
        description: String? = nil,
        iconURL: URL? = nil,
        apps: [AltSourceApp] = []
    ) {
        self.name = name
        self.identifier = identifier
        self.sourceURL = sourceURL
        self.subtitle = subtitle
        self.description = description
        self.iconURL = iconURL
        self.apps = apps
    }
}

public struct AltSourceApp: Identifiable, Codable, Equatable {
    public var id: String { bundleIdentifier }
    public var name: String
    public var bundleIdentifier: String
    public var developerName: String?
    public var version: String
    public var versionDate: String?
    public var downloadURL: URL
    public var localizedDescription: String?
    public var iconURL: URL?
    public var size: Int64?

    public init(
        name: String,
        bundleIdentifier: String,
        developerName: String? = nil,
        version: String,
        versionDate: String? = nil,
        downloadURL: URL,
        localizedDescription: String? = nil,
        iconURL: URL? = nil,
        size: Int64? = nil
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.developerName = developerName
        self.version = version
        self.versionDate = versionDate
        self.downloadURL = downloadURL
        self.localizedDescription = localizedDescription
        self.iconURL = iconURL
        self.size = size
    }
}

