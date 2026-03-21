import Foundation

public struct SokolVendor {
    static let requiredHeaders = [
        "sokol_app.h",
        "sokol_gfx.h",
        "sokol_glue.h",
        "sokol_log.h",
    ]

    public static func resolve(into destination: String) throws -> String {
        let localVendor = FileManager.default.currentDirectoryPath + "/vendor/sokol"
        if hasAllHeaders(at: localVendor) {
            try copyHeaders(from: localVendor, to: destination)
            return destination
        }

        let toolchainCache = "\(NSHomeDirectory())/.kira/toolchain/vendor/sokol"
        if hasAllHeaders(at: toolchainCache) {
            try copyHeaders(from: toolchainCache, to: destination)
            return destination
        }

        print("  Sokol headers not found locally, downloading...")
        try downloadSokol(to: toolchainCache)
        try copyHeaders(from: toolchainCache, to: destination)
        return destination
    }

    private static func hasAllHeaders(at path: String) -> Bool {
        requiredHeaders.allSatisfy { header in
            FileManager.default.fileExists(atPath: "\(path)/\(header)")
        }
    }

    private static func copyHeaders(from source: String, to destination: String) throws {
        try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
        for header in requiredHeaders {
            let sourcePath = "\(source)/\(header)"
            let destinationPath = "\(destination)/\(header)"
            if FileManager.default.fileExists(atPath: destinationPath) {
                try FileManager.default.removeItem(atPath: destinationPath)
            }
            try FileManager.default.copyItem(atPath: sourcePath, toPath: destinationPath)
        }
    }

    private static func downloadSokol(to destination: String) throws {
        let baseURL = "https://raw.githubusercontent.com/floooh/sokol/master"
        try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
        for header in requiredHeaders {
            guard let url = URL(string: "\(baseURL)/\(header)") else {
                continue
            }
            let data = try Data(contentsOf: url)
            try data.write(to: URL(fileURLWithPath: "\(destination)/\(header)"))
            print("    Downloaded \(header)")
        }
    }
}
