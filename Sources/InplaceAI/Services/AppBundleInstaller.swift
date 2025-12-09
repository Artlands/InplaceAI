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
            <key>LSUIElement</key>
            <true/>
            <key>NSPrincipalClass</key>
            <string>NSApplication</string>
        </dict>
        </plist>
        """
        try infoPlist.write(to: infoPlistURL, atomically: true, encoding: .utf8)

        return bundleURL
    }
}
