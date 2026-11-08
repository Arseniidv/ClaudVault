import Foundation

enum AppConfiguration{
    static let name = "ClaudVault"
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""

    static var version:String{
        Bundle.main.infoDictionary?[
            "CFBundleShortVersionString"
        ] as? String ?? "1.0"
    }
    static var buildNumber:String{
        Bundle.main.infoDictionary?[
            "CFBundleVersion"
        ] as? String ?? "1"
    }
}
