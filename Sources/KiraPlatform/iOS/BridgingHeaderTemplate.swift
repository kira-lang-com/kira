import Foundation

public struct BridgingHeaderTemplate {
    public static func generate(platform: AppleBuildPlatform) throws -> String {
        let relativePath = platform == .iOS ? "iOS/BridgingHeader.h.template" : "macOS/BridgingHeader.h.template"
        return try NativeDependencyResolver.loadTemplate(relativePath)
    }
}
