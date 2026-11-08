import Foundation

enum FinderExtensionBridge {
    static func requestID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == "claudvault",
              url.host?.lowercased() == "radial",
              url.path == "/open"
                else {
            return nil
        }

        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ),
              let rawID = components.queryItems?.first(
                  where: { $0.name == "request" }
              )?.value,
              let id = UUID(uuidString: rawID) else { return nil }
        return id
    }

    static func fileSelection(
        from request: RadialMenuRequest
    ) -> FileSelection {
        let source: SelectionSource
        switch request.source {
        case .finderSync: source = .finderSync
        case .services: source = .services
        case .accessibility: source = .accessibility
        case .dragAndDrop: source = .dragAndDrop
        case .clipboard: source = .clipboard
        }
        return FileSelection(urls: request.fileURLs, source: source)
    }
}
