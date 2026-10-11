import Foundation

/// Finds the App Group this installation was actually signed with.
///
/// The build names one group (`AzkarAppGroup` in the Info.plist), but re-signing tools used to
/// install the app with a personal certificate often rename it (to follow the bundle identifier
/// they give the app). The group the app and the widget really share is then only in their
/// provisioning profiles (`embedded.mobileprovision`), so those are read too.
public enum AppGroupLocator {
    /// The groups to try, in order: the build's own name first, then those in the profile.
    public static func candidates(infoPlistGroup: String?, profile: Data?) -> [String] {
        var groups: [String] = []
        if let infoPlistGroup, !infoPlistGroup.isEmpty, !infoPlistGroup.hasPrefix("$(") { groups.append(infoPlistGroup) }
        for group in profile.map(profileGroups) ?? [] where !groups.contains(group) && !group.contains("*") {
            groups.append(group)
        }
        return groups
    }

    /// The `com.apple.security.application-groups` entitlement of a provisioning profile: a
    /// signed envelope around an XML property list, which is read as is.
    public static func profileGroups(_ profile: Data) -> [String] {
        guard let start = profile.range(of: Data("<?xml".utf8)),
              let end = profile.range(of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: profile[start.lowerBound..<end.upperBound],
                                                                      format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any] else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }

    /// The first candidate iOS gives a container for in this process, or nil.
    public static func resolve(bundle: Bundle = .main, fileManager: FileManager = .default) -> String? {
        let named = bundle.object(forInfoDictionaryKey: "AzkarAppGroup") as? String
        let profile = try? Data(contentsOf: bundle.bundleURL.appendingPathComponent("embedded.mobileprovision"))
        return candidates(infoPlistGroup: named, profile: profile).first {
            fileManager.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        }
    }
}
