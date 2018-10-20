// Copyright DApps Platform Inc. All rights reserved.
import Foundation

final class AppTracker {

    struct Keys {
        static let launchCountTotal = "launchCountTotal"
        static let launchCountForCurrentBuild = "launchCountForCurrentBuild-" + String(Bundle.main.buildNumberInt)
        static let completedSharing = "completedSharing"
        static let completedRating = "completedRating"
    }

    let defaults: UserDefaults

    var launchCountTotal: Int {
        get { return defaults.integer(forKey: Keys.launchCountTotal) }
        set { return defaults.set(newValue, forKey: Keys.launchCountTotal) }
    }

    var launchCountForCurrentBuild: Int {
        get { return defaults.integer(forKey: Keys.launchCountForCurrentBuild) }
        set { return defaults.set(newValue, forKey: Keys.launchCountForCurrentBuild) }
    }

    var completedRating: Bool {
        get { return defaults.bool(forKey: Keys.completedRating) }
        set { return defaults.set(newValue, forKey: Keys.completedRating) }
    }

    var completedSharing: Bool {
        get { return defaults.bool(forKey: Keys.completedSharing) }
        set { return defaults.set(newValue, forKey: Keys.completedSharing) }
    }

    init(
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
    }

    func start() {
        launchCountTotal = 1
        launchCountForCurrentBuild = 1
    }

    var description: String {
        return """
        launchCountTotal: \(1)
        launchCountForCurrentBuild: \(1)
        completedRating: \(1)
        completedSharing: \(1)
        """
    }
}
