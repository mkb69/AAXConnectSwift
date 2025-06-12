import Foundation
import Crypto
import CommonCrypto

public struct AAXConnectCrypto {
    
    public struct DecryptedVoucher: Codable {
        public let key: String
        public let iv: String
        public let asin: String?
        public let rules: [[String: Any]]?
        
        public init(key: String, iv: String, asin: String? = nil, rules: [[String: Any]]? = nil) {
            self.key = key
            self.iv = iv
            self.asin = asin
            self.rules = rules
        }
        
        enum CodingKeys: String, CodingKey {
            case key, iv, asin, rules
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(key, forKey: .key)
            try container.encode(iv, forKey: .iv)
            try container.encodeIfPresent(asin, forKey: .asin)
            // Encode rules as AnyCodable array
            if let rules = rules {
                let encodableRules = rules.map { rule in
                    rule.mapValues { AnyCodable($0) }
                }
                try container.encode(encodableRules, forKey: .rules)
            }
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            key = try container.decode(String.self, forKey: .key)
            iv = try container.decode(String.self, forKey: .iv)
            asin = try container.decodeIfPresent(String.self, forKey: .asin)
            // Decode rules if present
            if let encodableRules = try container.decodeIfPresent([[String: AnyCodable]].self, forKey: .rules) {
                rules = encodableRules.map { rule in
                    rule.mapValues { $0.value }
                }
            } else {
                rules = nil
            }
        }
    }
    
    public static func decryptVoucherFromLicenseRequest(
        deviceInfo: [String: Any],
        customerInfo: [String: Any],
        licenseResponse: [String: Any]
    ) throws -> DecryptedVoucher {
        
        guard let deviceSerialNumber = deviceInfo["device_serial_number"] as? String,
              let deviceType = deviceInfo["device_type"] as? String else {
            throw AAXConnectError.missingDeviceInfo
        }
        
        guard let customerId = customerInfo["user_id"] as? String else {
            throw AAXConnectError.missingCustomerInfo
        }
        
        guard let contentLicense = licenseResponse["content_license"] as? [String: Any],
              let asin = contentLicense["asin"] as? String,
              let encryptedVoucher = contentLicense["license_response"] as? String else {
            throw AAXConnectError.decryptionFailed("Missing license data")
        }
        
        return try decryptVoucher(
            deviceSerialNumber: deviceSerialNumber,
            customerId: customerId,
            deviceType: deviceType,
            asin: asin,
            voucher: encryptedVoucher
        )
    }
    
    private static func decryptVoucher(
        deviceSerialNumber: String,
        customerId: String,
        deviceType: String,
        asin: String,
        voucher: String
    ) throws -> DecryptedVoucher {
        
        // Create buffer string for hashing
        let bufferString = deviceType + deviceSerialNumber + customerId + asin
        guard let bufferData = bufferString.data(using: .ascii) else {
            throw AAXConnectError.decryptionFailed("Failed to create buffer data")
        }
        
        // Calculate SHA256 hash
        let digest = SHA256.hash(data: bufferData)
        let digestData = Data(digest)
        
        // Extract key and IV from hash
        let key = digestData.prefix(16)
        let iv = digestData.suffix(from: 16)
        
        // Decode base64 voucher
        guard let voucherData = Data(base64Encoded: voucher) else {
            throw AAXConnectError.decryptionFailed("Failed to decode base64 voucher")
        }
        
        // Decrypt using AES-CBC with no padding
        guard let decryptedData = try? aesCBCDecrypt(data: voucherData, key: key, iv: iv, padding: false) else {
            throw AAXConnectError.decryptionFailed("AES decryption failed")
        }
        
        // Remove null padding and convert to string
        let decryptedString = String(data: decryptedData, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""
        
        // Try to parse as JSON first
        if let jsonData = decryptedString.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let keyValue = jsonObject["key"] as? String,
           let ivValue = jsonObject["iv"] as? String {
            let rules = jsonObject["rules"] as? [[String: Any]]
            return DecryptedVoucher(key: keyValue, iv: ivValue, asin: asin, rules: rules)
        }
        
        // Fallback to regex parsing
        let pattern = #"^{"key":"([^"]*?)","iv":"([^"]*?)","#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(decryptedString.startIndex..<decryptedString.endIndex, in: decryptedString)
        
        if let match = regex.firstMatch(in: decryptedString, range: range) {
            let keyRange = Range(match.range(at: 1), in: decryptedString)
            let ivRange = Range(match.range(at: 2), in: decryptedString)
            
            if let keyRange = keyRange, let ivRange = ivRange {
                let keyValue = String(decryptedString[keyRange])
                let ivValue = String(decryptedString[ivRange])
                // For regex parsing, we don't attempt to parse rules
                return DecryptedVoucher(key: keyValue, iv: ivValue, asin: asin, rules: nil)
            }
        }
        
        throw AAXConnectError.decryptionFailed("Failed to parse voucher")
    }
    
    /// AES-CBC decryption function
    private static func aesCBCDecrypt(data: Data, key: Data, iv: Data, padding: Bool = true) throws -> Data {
        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var numBytesDecrypted: size_t = 0
        
        let options = padding ? CCOptions(kCCOptionPKCS7Padding) : CCOptions(0)
        
        let status = data.withUnsafeBytes { dataBytes in
            key.withUnsafeBytes { keyBytes in
                iv.withUnsafeBytes { ivBytes in
                    buffer.withUnsafeMutableBytes { bufferBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            options,
                            keyBytes.bindMemory(to: UInt8.self).baseAddress,
                            key.count,
                            ivBytes.bindMemory(to: UInt8.self).baseAddress,
                            dataBytes.bindMemory(to: UInt8.self).baseAddress,
                            data.count,
                            bufferBytes.bindMemory(to: UInt8.self).baseAddress,
                            bufferSize,
                            &numBytesDecrypted
                        )
                    }
                }
            }
        }
        
        guard status == kCCSuccess else {
            throw AAXConnectError.decryptionFailed("AES decryption failed with status: \(status)")
        }
        
        return Data(buffer.prefix(numBytesDecrypted))
    }
    
    /// AES-CBC encryption function
    public static func aesCBCEncrypt(data: Data, key: Data, iv: Data, padding: Bool = true) throws -> Data {
        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var numBytesEncrypted: size_t = 0
        
        let options = padding ? CCOptions(kCCOptionPKCS7Padding) : CCOptions(0)
        
        let status = data.withUnsafeBytes { dataBytes in
            key.withUnsafeBytes { keyBytes in
                iv.withUnsafeBytes { ivBytes in
                    buffer.withUnsafeMutableBytes { bufferBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            options,
                            keyBytes.bindMemory(to: UInt8.self).baseAddress,
                            key.count,
                            ivBytes.bindMemory(to: UInt8.self).baseAddress,
                            dataBytes.bindMemory(to: UInt8.self).baseAddress,
                            data.count,
                            bufferBytes.bindMemory(to: UInt8.self).baseAddress,
                            bufferSize,
                            &numBytesEncrypted
                        )
                    }
                }
            }
        }
        
        guard status == kCCSuccess else {
            throw AAXConnectError.decryptionFailed("AES encryption failed with status: \(status)")
        }
        
        return Data(buffer.prefix(numBytesEncrypted))
    }
}