import Foundation

/// ID generation (standard library UUID, no third-party dependencies)
public struct IdUtil {
    /// Generates a globally unique ID
    public static func genId() -> String {
        UUID().uuidString
    }
}
