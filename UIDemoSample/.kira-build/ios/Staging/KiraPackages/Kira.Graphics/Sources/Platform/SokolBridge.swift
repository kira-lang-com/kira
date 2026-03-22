import Foundation

public enum SokolBridge {
    public static func chooseDefaultBackend() -> PlatformBackend {
        // Scaffold: real implementation would select Metal/Vulkan/D3D/WebGPU via Sokol.
        NullBackend()
    }
}

