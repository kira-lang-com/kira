import Foundation

public struct AppDelegateTemplate {
    public static func generate(appName: String, projectName: String, targetAppIdentifier: String, title: String, width: Int, height: Int) throws -> String {
        var template = try NativeDependencyResolver.loadTemplate("iOS/AppDelegate.swift.template")
        template = template.replacingOccurrences(of: "{{APP_NAME}}", with: appName)
        template = template.replacingOccurrences(of: "{{PROJECT_NAME}}", with: projectName)
        template = template.replacingOccurrences(of: "{{APP_ID}}", with: targetAppIdentifier)
        template = template.replacingOccurrences(of: "{{TITLE}}", with: escaped(title))
        template = template.replacingOccurrences(of: "{{WIDTH}}", with: "\(width)")
        template = template.replacingOccurrences(of: "{{HEIGHT}}", with: "\(height)")
        return template
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\\\"")
    }
}
