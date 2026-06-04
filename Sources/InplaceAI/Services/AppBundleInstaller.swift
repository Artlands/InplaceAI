import AppKit
import CryptoKit
import Foundation

@MainActor
enum AppBundleInstaller {
    private static let bundleName = "InplaceAI"
    private static let bundleIdentifier = "com.inplaceai.desktop"
    private static let bundleSchemaVersion = "3"
    private static let sourceExecutableHashKey = "InplaceAISourceExecutableSHA256"
    private static let fixGrammarServiceMenuTitle = "Fix Grammar with InplaceAI"
    private static let fixGrammarServiceMessage = "fixGrammar"
    private static let explainServiceMenuTitle = "Explain with InplaceAI"
    private static let explainServiceMessage = "explainSelection"
    private static let servicePasteboardTypes = [
        "NSStringPboardType",
        NSPasteboard.PasteboardType.string.rawValue
    ]

    /// Ensures the app is running from a proper `.app` bundle so macOS can grant Accessibility privileges.
    /// Returns `true` if execution should continue in the current process, or `false` if a relaunch was triggered.
    @discardableResult
    static func ensureRunningFromBundle() -> Bool {
        if Bundle.main.bundlePath.hasSuffix(".app") {
            return true
        }

        let executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])

        do {
            let appURL = try installBundleIfNeeded(executableURL: executableURL)
            NSWorkspace.shared.open(appURL)
            NSApp.terminate(nil)
            return false
        } catch {
            NSLog("InplaceAI: failed to install helper bundle: \(error.localizedDescription)")
            return true
        }
    }

    private static func installBundleIfNeeded(executableURL: URL) throws -> URL {
        let manager = FileManager.default
        let applicationsDir = manager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        try manager.createDirectory(at: applicationsDir, withIntermediateDirectories: true)

        let bundleURL = applicationsDir.appendingPathComponent("\(bundleName).app", isDirectory: true)
        let sourceExecutableHash = try executableSHA256(executableURL)
        if installedBundleMatches(bundleURL: bundleURL, sourceExecutableHash: sourceExecutableHash) {
            return bundleURL
        }

        return try installBundle(
            executableURL: executableURL,
            sourceExecutableHash: sourceExecutableHash,
            destination: bundleURL
        )
    }

    private static func installBundle(
        executableURL: URL,
        sourceExecutableHash: String,
        destination bundleURL: URL
    ) throws -> URL {
        let manager = FileManager.default
        let tempURL = bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(bundleName).app.\(UUID().uuidString)", isDirectory: true)
        let tempContentsURL = tempURL.appendingPathComponent("Contents", isDirectory: true)
        let tempMacOSURL = tempContentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let tempResourcesURL = tempContentsURL.appendingPathComponent("Resources", isDirectory: true)

        try? manager.removeItem(at: tempURL)
        try manager.createDirectory(at: tempMacOSURL, withIntermediateDirectories: true)
        try manager.createDirectory(at: tempResourcesURL, withIntermediateDirectories: true)

        let binaryURL = tempMacOSURL.appendingPathComponent(bundleName, isDirectory: false)
        try manager.copyItem(at: executableURL, to: binaryURL)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)

        let infoPlistURL = tempContentsURL.appendingPathComponent("Info.plist", isDirectory: false)
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
            <key>InplaceAIBundleSchemaVersion</key>
            <string>\(bundleSchemaVersion)</string>
            <key>\(sourceExecutableHashKey)</key>
            <string>\(sourceExecutableHash)</string>
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
            <key>NSServices</key>
            <array>
                <dict>
                    <key>NSMenuItem</key>
                    <dict>
                        <key>default</key>
                        <string>\(fixGrammarServiceMenuTitle)</string>
                    </dict>
                    <key>NSMessage</key>
                    <string>\(fixGrammarServiceMessage)</string>
                    <key>NSPortName</key>
                    <string>\(bundleName)</string>
                    <key>NSSendTypes</key>
                    <array>
                        <string>\(servicePasteboardTypes[0])</string>
                        <string>\(servicePasteboardTypes[1])</string>
                    </array>
                    <key>NSReturnTypes</key>
                    <array>
                        <string>\(servicePasteboardTypes[0])</string>
                        <string>\(servicePasteboardTypes[1])</string>
                    </array>
                </dict>
                <dict>
                    <key>NSMenuItem</key>
                    <dict>
                        <key>default</key>
                        <string>\(explainServiceMenuTitle)</string>
                    </dict>
                    <key>NSMessage</key>
                    <string>\(explainServiceMessage)</string>
                    <key>NSPortName</key>
                    <string>\(bundleName)</string>
                    <key>NSSendTypes</key>
                    <array>
                        <string>\(servicePasteboardTypes[0])</string>
                        <string>\(servicePasteboardTypes[1])</string>
                    </array>
                </dict>
            </array>
        </dict>
        </plist>
        """
        try infoPlist.write(to: infoPlistURL, atomically: true, encoding: .utf8)

        copyResourceBundle(to: tempResourcesURL)

        // Copy bundled icon so macOS shows it in System Settings.
        if let iconSource = findAppIcon() {
            let destination = tempResourcesURL.appendingPathComponent("\(iconName).icns")
            try manager.copyItem(at: iconSource, to: destination)
        }

        signBundle(tempURL)

        try? manager.removeItem(at: bundleURL)
        try manager.moveItem(at: tempURL, to: bundleURL)
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

    private static func installedBundleMatches(bundleURL: URL, sourceExecutableHash: String) -> Bool {
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)
        let binaryURL = contentsURL
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(bundleName, isDirectory: false)

        guard FileManager.default.fileExists(atPath: binaryURL.path),
            let data = try? Data(contentsOf: infoPlistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let dict = plist as? [String: Any]
        else
        {
            return false
        }

        return dict["CFBundleIdentifier"] as? String == bundleIdentifier
            && dict["InplaceAIBundleSchemaVersion"] as? String == bundleSchemaVersion
            && dict[sourceExecutableHashKey] as? String == sourceExecutableHash
            && dict["NSServices"] != nil
    }

    private static func copyResourceBundle(to resourcesURL: URL) {
        #if SWIFT_PACKAGE
        let manager = FileManager.default
        let bundleURL = Bundle.module.bundleURL
        guard bundleURL.pathExtension == "bundle" else { return }
        let destination = resourcesURL.appendingPathComponent(bundleURL.lastPathComponent, isDirectory: true)
        try? manager.removeItem(at: destination)
        try? manager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try? manager.copyItem(at: bundleURL, to: destination)
        #endif
    }

    private static func executableSHA256(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func signBundle(_ bundleURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = [
            "--force",
            "--deep",
            "--sign",
            "-",
            "--identifier",
            bundleIdentifier,
            bundleURL.path
        ]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                NSLog("InplaceAI: ad-hoc codesign failed with status \(process.terminationStatus)")
            }
        } catch {
            NSLog("InplaceAI: ad-hoc codesign failed: \(error.localizedDescription)")
        }
    }
}
