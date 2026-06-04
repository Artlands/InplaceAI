import Foundation

final class LaunchController {
    private let jobLabel = "com.inplaceai.desktop.launch"
    private lazy var launchDirectory: URL = {
        FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("LaunchAgents", isDirectory: true)
    }()
    
    private lazy var plistURL = launchDirectory.appendingPathComponent(jobLabel + ".plist")
    
    func isStartAtLogin() -> Bool {
        return FileManager.default.fileExists(atPath: plistURL.path)
    }
    
    func setStartAtLogin(_ enabled: Bool) {
        if enabled {
            createLaunchAgentPlist()
        } else {
            deleteLaunchAgentPlist()
        }
    }
    
    private func createLaunchAgentPlist() {
        try? FileManager.default.createDirectory(
            at: launchDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        let appPath = Bundle.main.bundlePath
        
        let plist: [String: Any] = [
            "Label": jobLabel,
            "ProgramArguments": ["open", "-a", appPath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]
        
        let data = try? PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        
        try? data?.write(to: plistURL)
    }
    
    private func deleteLaunchAgentPlist() {
        try? FileManager.default.removeItem(at: plistURL)
    }
}
