import Foundation

// Custom error for test setup issues
struct TestSetupError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

// Shared Character extension
extension Character {
    var isHexDigit: Bool {
        return self.isASCII && (self.isNumber || ("a"..."f").contains(self.lowercased()))
    }
} 