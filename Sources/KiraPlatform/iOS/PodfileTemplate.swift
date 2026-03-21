import Foundation

public struct PodfileTemplate {
    public static func generate(appName: String, pods: [String: String], minimumVersion: String) -> String {
        var lines: [String] = [
            "platform :ios, '\(minimumVersion)'",
            "use_frameworks!",
            "",
            "target '\(appName)' do",
        ]

        for (name, version) in pods.sorted(by: { $0.key < $1.key }) {
            lines.append("  pod '\(name)', '\(version)'")
        }

        lines.append("end")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
