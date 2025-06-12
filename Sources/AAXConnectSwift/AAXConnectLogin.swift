import Foundation
import Crypto

public class AAXConnectLogin {
    
    public static func createCodeVerifier(length: Int = 32) -> String {
        let verifier = Data((0..<length).map { _ in UInt8.random(in: 0...255) })
        return verifier.base64URLEncodedString()
    }
    
    private static func createS256CodeChallenge(verifierString: String) -> String {
        // Hash the verifier string directly (as UTF-8 bytes)
        let verifierData = verifierString.data(using: .utf8)!
        let hash = SHA256.hash(data: verifierData)
        return Data(hash).base64URLEncodedString()
    }
    
    public static func buildDeviceSerial() -> String {
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased()
    }
    
    public static func buildClientId(serial: String) -> String {
        let clientIdData = serial.data(using: .utf8)! + "#A2CZJZGLK2JJVM".data(using: .utf8)!
        return clientIdData.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Builds the OAuth URL for login to Amazon as an AAXC device
    public static func buildOAuthURL(
        countryCode: String,
        domain: String,
        marketPlaceId: String,
        codeVerifier: String,
        serial: String? = nil,
        withUsername: Bool = false
    ) -> (url: String, serial: String) {
        
        if withUsername && !["de", "com", "co.uk"].contains(domain.lowercased()) {
            fatalError("Login with username is only supported for DE, US and UK marketplaces!")
        }
        
        let deviceSerial = serial ?? buildDeviceSerial()
        let clientId = buildClientId(serial: deviceSerial)
        let codeChallenge = createS256CodeChallenge(verifierString: codeVerifier)
        
        let baseURL: String
        let returnTo: String
        let assocHandle: String
        let pageId: String
        
        if withUsername {
            baseURL = "https://www.audible.\(domain)/ap/signin"
            returnTo = "https://www.audible.\(domain)/ap/maplanding"
            assocHandle = "amzn_audible_ios_lap_\(countryCode)"
            pageId = "amzn_audible_ios_privatepool"
        } else {
            baseURL = "https://www.amazon.\(domain)/ap/signin"
            returnTo = "https://www.amazon.\(domain)/ap/maplanding"
            assocHandle = "amzn_audible_ios_\(countryCode)"
            pageId = "amzn_audible_ios"
        }
        
        let oauthParams: [(String, String)] = [
            ("openid.oa2.response_type", "code"),
            ("openid.oa2.code_challenge_method", "S256"),
            ("openid.oa2.code_challenge", codeChallenge),
            ("openid.return_to", returnTo),
            ("openid.assoc_handle", assocHandle),
            ("openid.identity", "http://specs.openid.net/auth/2.0/identifier_select"),
            ("pageId", pageId),
            ("accountStatusPolicy", "P1"),
            ("openid.claimed_id", "http://specs.openid.net/auth/2.0/identifier_select"),
            ("openid.mode", "checkid_setup"),
            ("openid.ns.oa2", "http://www.amazon.com/ap/ext/oauth/2"),
            ("openid.oa2.client_id", "device:\(clientId)"),
            ("openid.ns.pape", "http://specs.openid.net/extensions/pape/1.0"),
            ("marketPlaceId", marketPlaceId),
            ("openid.oa2.scope", "device_auth_access"),
            ("forceMobileLayout", "true"),
            ("openid.ns", "http://specs.openid.net/auth/2.0"),
            ("openid.pape.max_auth_age", "0")
        ]
        
        let queryString = oauthParams.compactMap { key, value in
            let compatibleCharSet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            guard let encodedKey = key.addingPercentEncoding(withAllowedCharacters: compatibleCharSet),
                  let encodedValue = value.addingPercentEncoding(withAllowedCharacters: compatibleCharSet) else {
                return nil
            }
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        
        let fullURL = "\(baseURL)?\(queryString)"
        
        return (url: fullURL, serial: deviceSerial)
    }
}

// Extension to handle Base64 URL encoding
extension Data {
    func base64URLEncodedData() -> Data {
        let base64String = self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return base64String.data(using: .utf8) ?? Data()
    }
    
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    static func fromBase64URLEncoded(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        
        return Data(base64Encoded: base64)
    }
}