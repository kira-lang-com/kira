import Foundation
import PathKit
import XcodeProj

public struct XcodeProjGenerator {
    public struct Config: Sendable {
        public enum Platform: Sendable {
            case iOS
            case macOS
        }

        public var appName: String
        public var bundleID: String
        public var teamID: String
        public var minimumVersion: String
        public var targetPlatform: Platform
        public var frameworks: [String]
        public var staticLibs: [String]
        public var headerSearchPaths: [String]
        public var deviceOnlyLibrarySearchPaths: [String]
        public var bytecodePath: String
        public var kiraPackagePath: String
        public var outputPath: String
        public var targetedDeviceFamily: String?

        public init(
            appName: String,
            bundleID: String,
            teamID: String,
            minimumVersion: String,
            targetPlatform: Platform,
            frameworks: [String],
            staticLibs: [String],
            headerSearchPaths: [String],
            deviceOnlyLibrarySearchPaths: [String] = [],
            bytecodePath: String,
            kiraPackagePath: String,
            outputPath: String,
            targetedDeviceFamily: String? = nil
        ) {
            self.appName = appName
            self.bundleID = bundleID
            self.teamID = teamID
            self.minimumVersion = minimumVersion
            self.targetPlatform = targetPlatform
            self.frameworks = frameworks
            self.staticLibs = staticLibs
            self.headerSearchPaths = headerSearchPaths
            self.deviceOnlyLibrarySearchPaths = deviceOnlyLibrarySearchPaths
            self.bytecodePath = bytecodePath
            self.kiraPackagePath = kiraPackagePath
            self.outputPath = outputPath
            self.targetedDeviceFamily = targetedDeviceFamily
        }
    }

    public init() {}

    public func generate(config: Config) throws {
        let xcodeproj = try buildProject(config: config)
        try xcodeproj.write(pathString: config.outputPath, override: true)
    }

    private func buildProject(config: Config) throws -> XcodeProj {
        let projectDirectory = URL(fileURLWithPath: config.outputPath).deletingLastPathComponent()
        let relativePackagePath = NativeDependencyResolver.relativePath(
            from: projectDirectory,
            to: URL(fileURLWithPath: config.kiraPackagePath)
        )

        let mainGroup = PBXGroup(children: [], sourceTree: .group)
        let sourcesGroup = PBXGroup(
            children: [], sourceTree: .group, name: "Sources", path: "Sources")
        let frameworksGroup = PBXGroup(children: [], sourceTree: .group, name: "Frameworks")
        let productsGroup = PBXGroup(children: [], sourceTree: .group, name: "Products")
        let vendorGroup = PBXGroup(children: [], sourceTree: .group, name: "vendor", path: "vendor")
        let sokolGroup = PBXGroup(children: [], sourceTree: .group, name: "sokol", path: "sokol")

        mainGroup.children = [sourcesGroup, frameworksGroup, productsGroup]
        sourcesGroup.children = [vendorGroup]
        vendorGroup.children = [sokolGroup]

        let appDelegateRef = PBXFileReference(
            sourceTree: .group,
            name: "AppDelegate.swift",
            lastKnownFileType: "sourcecode.swift",
            path: "AppDelegate.swift"
        )
        let sokolImplRef = PBXFileReference(
            sourceTree: .group,
            name: "sokol_impl.m",
            lastKnownFileType: "sourcecode.c.objc",
            path: "sokol_impl.m"
        )
        let bridgingHeaderRef = PBXFileReference(
            sourceTree: .group,
            name: "KiraBridging.h",
            lastKnownFileType: "sourcecode.c.h",
            path: "KiraBridging.h"
        )
        let bytecodeRef = PBXFileReference(
            sourceTree: .group,
            name: "\(config.appName).kirbc",
            lastKnownFileType: "file",
            path: "\(config.appName).kirbc"
        )
        let infoPlistRef = PBXFileReference(
            sourceTree: .group,
            name: "Info.plist",
            lastKnownFileType: "text.plist.xml",
            path: "Info.plist"
        )
        let productRef = PBXFileReference(
            sourceTree: .buildProductsDir,
            name: "\(config.appName).app",
            explicitFileType: "wrapper.application",
            path: "\(config.appName).app"
        )

        sourcesGroup.children.append(contentsOf: [
            appDelegateRef, sokolImplRef, bridgingHeaderRef, bytecodeRef, infoPlistRef,
        ])
        productsGroup.children.append(productRef)

        let headerRefs = ["sokol_app.h", "sokol_gfx.h", "sokol_glue.h", "sokol_log.h"].map {
            header in
            return PBXFileReference(
                sourceTree: .group,
                name: header,
                lastKnownFileType: "sourcecode.c.h",
                path: header
            )
        }
        sokolGroup.children.append(contentsOf: headerRefs)

        let frameworkRefs = config.frameworks.map { framework -> PBXFileReference in
            PBXFileReference(
                sourceTree: .sdkRoot,
                name: "\(framework).framework",
                lastKnownFileType: "wrapper.framework",
                path: "System/Library/Frameworks/\(framework).framework"
            )
        }
        frameworksGroup.children.append(contentsOf: frameworkRefs)

        let staticLibRefs = config.staticLibs.map { path -> PBXFileReference in
            PBXFileReference(
                sourceTree: .absolute,
                name: URL(fileURLWithPath: path).lastPathComponent,
                lastKnownFileType: "archive.ar",
                path: path
            )
        }
        frameworksGroup.children.append(contentsOf: staticLibRefs)

        let sourcesBuildFiles = [
            PBXBuildFile(file: appDelegateRef),
            PBXBuildFile(file: sokolImplRef),
        ]
        let resourcesBuildFiles = [
            PBXBuildFile(file: bytecodeRef)
        ]
        let frameworkBuildFiles = frameworkRefs.map { PBXBuildFile(file: $0) }
        let staticLibraryBuildFiles = staticLibRefs.map { PBXBuildFile(file: $0) }

        let sourcesBuildPhase = PBXSourcesBuildPhase(files: sourcesBuildFiles)
        let frameworksBuildPhase = PBXFrameworksBuildPhase(
            files: frameworkBuildFiles + staticLibraryBuildFiles)
        let resourcesBuildPhase = PBXResourcesBuildPhase(files: resourcesBuildFiles)

        let projectDebug = XCBuildConfiguration(
            name: "Debug", buildSettings: projectSettings(config: config))
        let projectRelease = XCBuildConfiguration(
            name: "Release", buildSettings: projectSettings(config: config))
        let projectConfigList = XCConfigurationList(
            buildConfigurations: [projectDebug, projectRelease],
            defaultConfigurationName: "Debug"
        )

        let targetDebug = XCBuildConfiguration(
            name: "Debug", buildSettings: targetSettings(config: config, release: false))
        let targetRelease = XCBuildConfiguration(
            name: "Release", buildSettings: targetSettings(config: config, release: true))
        let targetConfigList = XCConfigurationList(
            buildConfigurations: [targetDebug, targetRelease],
            defaultConfigurationName: "Debug"
        )

        let target = PBXNativeTarget(
            name: config.appName,
            buildConfigurationList: targetConfigList,
            buildPhases: [sourcesBuildPhase, frameworksBuildPhase, resourcesBuildPhase],
            productName: config.appName,
            product: productRef,
            productType: .application
        )
        let localPackageRef = XCLocalSwiftPackageReference(relativePath: relativePackagePath)
        let project = PBXProject(
            name: config.appName,
            buildConfigurationList: projectConfigList,
            compatibilityVersion: "Xcode 15.0",
            preferredProjectObjectVersion: nil,
            minimizedProjectReferenceProxies: nil,
            mainGroup: mainGroup,
            developmentRegion: "en",
            hasScannedForEncodings: 0,
            knownRegions: ["en"],
            productsGroup: productsGroup,
            projectDirPath: "",
            projectRoots: [],
            targets: [target],
            packages: [],
            attributes: [:],
            targetAttributes: [:]
        )
        project.localPackages = [localPackageRef]
        if !config.teamID.isEmpty {
            project.setTargetAttributes(["DevelopmentTeam": config.teamID], target: target)
        }

        var objects: [PBXObject] = []
        objects.append(contentsOf: [
            mainGroup, sourcesGroup, frameworksGroup, productsGroup, vendorGroup, sokolGroup,
        ])
        objects.append(contentsOf: [
            appDelegateRef, sokolImplRef, bridgingHeaderRef, bytecodeRef, infoPlistRef, productRef,
        ])
        objects.append(contentsOf: headerRefs)
        objects.append(contentsOf: frameworkRefs)
        objects.append(contentsOf: staticLibRefs)
        objects.append(contentsOf: sourcesBuildFiles)
        objects.append(contentsOf: resourcesBuildFiles)
        objects.append(contentsOf: frameworkBuildFiles)
        objects.append(contentsOf: staticLibraryBuildFiles)
        objects.append(contentsOf: [
            sourcesBuildPhase,
            frameworksBuildPhase,
            resourcesBuildPhase,
            projectDebug,
            projectRelease,
            projectConfigList,
            targetDebug,
            targetRelease,
            targetConfigList,
            localPackageRef,
            target,
            project,
        ])

        let pbxproj = PBXProj(rootObject: project, objects: objects)
        _ = try project.addLocalSwiftPackage(
            path: Path(relativePackagePath),
            productName: "KiraVM",
            targetName: config.appName,
            addFileReference: false
        )
        return XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj)
    }

    private func projectSettings(config: Config) -> BuildSettings {
        var settings: BuildSettings = [
            "PRODUCT_NAME": config.appName,
            "SWIFT_VERSION": "5.0",
            "CURRENT_PROJECT_VERSION": "1",
            "MARKETING_VERSION": "1.0",
        ]
        if !config.teamID.isEmpty {
            settings["DEVELOPMENT_TEAM"] = config.teamID
        }
        return settings
    }

    private func targetSettings(config: Config, release: Bool) -> BuildSettings {
        let configName = release ? "Release" : "Debug"
        let packageBuildPaths = packageBuildDirectories(
            config: config, configurationName: configName)
        let librarySearchPaths = Set(
            config.staticLibs.map {
                URL(fileURLWithPath: $0).deletingLastPathComponent().path
            } + packageBuildPaths
        ).sorted()

        var settings: BuildSettings = [
            "PRODUCT_NAME": config.appName,
            "PRODUCT_BUNDLE_IDENTIFIER": config.bundleID,
            "CURRENT_PROJECT_VERSION": "1",
            "MARKETING_VERSION": "1.0",
            "GENERATE_INFOPLIST_FILE": "NO",
            "INFOPLIST_FILE": "Info.plist",
            "SWIFT_OBJC_BRIDGING_HEADER": "Sources/KiraBridging.h",
            "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/vendor/sokol"] + config.headerSearchPaths,
            "LIBRARY_SEARCH_PATHS": librarySearchPaths,
            "FRAMEWORK_SEARCH_PATHS": packageBuildPaths,
            "SWIFT_INCLUDE_PATHS": packageBuildPaths,
            "ARCHS": "arm64",
            "ONLY_ACTIVE_ARCH": "YES",
            "SWIFT_VERSION": "5.0",
            "ENABLE_BITCODE": "NO",
            "CLANG_ENABLE_MODULES": "YES",
            "SDKROOT": config.targetPlatform == .iOS ? "iphoneos" : "macosx",
            "CODE_SIGN_STYLE": "Automatic",
            "DEBUG_INFORMATION_FORMAT": release ? "dwarf-with-dsym" : "dwarf",
            "SWIFT_OPTIMIZATION_LEVEL": release ? "-O" : "-Onone",
            "GCC_OPTIMIZATION_LEVEL": release ? "s" : "0",
        ]

        if !config.teamID.isEmpty {
            settings["DEVELOPMENT_TEAM"] = config.teamID
        }

        switch config.targetPlatform {
        case .iOS:
            settings["IPHONEOS_DEPLOYMENT_TARGET"] = config.minimumVersion
            settings["TARGETED_DEVICE_FAMILY"] = config.targetedDeviceFamily ?? "1,2"
            settings["SUPPORTED_PLATFORMS"] = "iphoneos iphonesimulator"
            if !config.deviceOnlyLibrarySearchPaths.isEmpty {
                settings["LIBRARY_SEARCH_PATHS[sdk=iphoneos*]"] =
                    librarySearchPaths + config.deviceOnlyLibrarySearchPaths
            }
        case .macOS:
            settings["MACOSX_DEPLOYMENT_TARGET"] = config.minimumVersion
            settings["SUPPORTED_PLATFORMS"] = "macosx"
        }

        return settings
    }

    private func packageBuildDirectories(config: Config, configurationName: String) -> [String] {
        let buildRoot = URL(fileURLWithPath: config.kiraPackagePath)
            .appendingPathComponent("build", isDirectory: true)

        switch config.targetPlatform {
        case .iOS:
            return [
                buildRoot.appendingPathComponent("\(configurationName)-iphoneos", isDirectory: true)
                    .path,
                buildRoot.appendingPathComponent(
                    "\(configurationName)-iphonesimulator", isDirectory: true
                ).path,
                buildRoot.appendingPathComponent(configurationName, isDirectory: true).path,
            ]
        case .macOS:
            return [
                buildRoot.appendingPathComponent(configurationName, isDirectory: true).path
            ]
        }
    }
}
