import AppKit
import Foundation

@MainActor
enum AppBundleInstaller {
    private static let bundleName = "InplaceAI"
    private static let bundleIdentifier = "com.inplaceai.desktop"

    /// Ensures the app is running from a proper `.app` bundle so macOS can grant Accessibility privileges.
    /// Returns `true` if execution should continue in the current process, or `false` if a relaunch was triggered.
    @discardableResult
    static func ensureRunningFromBundle() -> Bool {
        if Bundle.main.bundlePath.hasSuffix(".app") {
            ensureIconPresent(in: URL(fileURLWithPath: Bundle.main.bundlePath))
            return true
        }

        let executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])

        do {
            let appURL = try installBundle(executableURL: executableURL)
            NSWorkspace.shared.open(appURL)
            NSApp.terminate(nil)
            return false
        } catch {
            NSLog("InplaceAI: failed to install helper bundle: \(error.localizedDescription)")
            return true
        }
    }

    private static func installBundle(executableURL: URL) throws -> URL {
        let manager = FileManager.default
        let applicationsDir = manager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        try manager.createDirectory(at: applicationsDir, withIntermediateDirectories: true)

        let bundleURL = applicationsDir.appendingPathComponent("\(bundleName).app", isDirectory: true)
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        try manager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try manager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let binaryURL = macOSURL.appendingPathComponent(bundleName, isDirectory: false)
        if manager.fileExists(atPath: binaryURL.path) {
            try manager.removeItem(at: binaryURL)
        }
        try manager.copyItem(at: executableURL, to: binaryURL)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)

        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let iconName = "AppIcon"
        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleDevelopmentRegion</key>
            <string>en</string>
            <key>CFBundleExecutable</key>
            <string>\(bundleName)</string>
            <key>CFBundleIdentifier</key>
            <string>\(bundleIdentifier)</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>CFBundleName</key>
            <string>\(bundleName)</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleShortVersionString</key>
            <string>\(version)</string>
            <key>CFBundleVersion</key>
            <string>\(version)</string>
            <key>CFBundleIconFile</key>
            <string>\(iconName)</string>
            <key>CFBundleIconFiles</key>
            <array>
                <string>\(iconName)</string>
            </array>
            <key>LSUIElement</key>
            <true/>
            <key>NSPrincipalClass</key>
            <string>NSApplication</string>
        </dict>
        </plist>
        """
        try infoPlist.write(to: infoPlistURL, atomically: true, encoding: .utf8)

        // Copy bundled icon so macOS shows it in System Settings.
        if let iconSource = findAppIcon() {
            let destination = resourcesURL.appendingPathComponent("\(iconName).icns")
            try? manager.removeItem(at: destination)
            try manager.copyItem(at: iconSource, to: destination)
        }

        return bundleURL
    }

    private static func findAppIcon() -> URL? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            return url
        }
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns") {
            return url
        }
        #endif
        return nil
    }

    private static func ensureIconPresent(in bundleURL: URL) {
        let manager = FileManager.default
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)
        let iconName = "AppIcon"
        let iconURL = resourcesURL.appendingPathComponent("\(iconName).icns")

        var plistDict: [String: Any] = [:]
        if
            let data = try? Data(contentsOf: infoPlistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let dict = plist as? [String: Any]
        {
            plistDict = dict
        }

        var changed = false
        if (plistDict["CFBundleIconFile"] as? String)?.isEmpty ?? true {
            plistDict["CFBundleIconFile"] = iconName
            changed = true
        }

        if plistDict["CFBundleIconFiles"] == nil {
            plistDict["CFBundleIconFiles"] = [iconName]
            changed = true
        }

        if changed,
           let data = try? PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        {
            try? manager.createDirectory(at: contentsURL, withIntermediateDirectories: true)
            try? data.write(to: infoPlistURL)
        }

        if !manager.fileExists(atPath: iconURL.path),
           let iconSource = findAppIcon()
        {
            try? manager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
            try? manager.copyItem(at: iconSource, to: iconURL)
        }
    }
}
