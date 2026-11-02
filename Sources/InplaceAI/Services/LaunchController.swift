import Foundation

final class LaunchController {
    private let jobLabel = "com.inplaceai.desktop.launch"
    private let plistURL: URL
    private let applicationURL: URL

    init(directory: URL? = nil, applicationURL: URL = Bundle.main.bundleURL) {
        let directory = directory ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("LaunchAgents", isDirectory: true)
        self.plistURL = directory.appendingPathComponent(jobLabel + ".plist")
        self.applicationURL = applicationURL
    }

    func isStartAtLogin() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func setStartAtLogin(_ enabled: Bool) throws {
        if enabled {
            guard applicationURL.pathExtension == "app" else {
                throw LaunchError.appBundleRequired
            }
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "Label": jobLabel,
                "ProgramArguments": ["/usr/bin/open", "-g", "-a", applicationURL.path, "--args", "--background"],
                "RunAtLoad": true,
                "KeepAlive": false
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } else if isStartAtLogin() {
            try FileManager.default.removeItem(at: plistURL)
        }
    }
}

private enum LaunchError: LocalizedError {
    case appBundleRequired
    var errorDescription: String? {
        "Launch the installed InplaceAI app before enabling Start at login."
    }
}
