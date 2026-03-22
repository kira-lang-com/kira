import Foundation

public enum FontRasterizer {
    public static func estimateAdvance(pointSize: Double, weightScale: Double = 0.6, characterCount: Int) -> Double {
        Double(characterCount) * pointSize * weightScale
    }
}
