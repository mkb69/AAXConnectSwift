import Foundation

public struct AAXConnectRegister {
    
    public struct RegistrationResponse {
        public let adpToken: String
        public let devicePrivateKey: String
        public let accessToken: String
        public let refreshToken: String
        public let expires: TimeInterval
        public let websiteCookies: [String: String]
        public let storeAuthenticationCookie: [String: Any]
        public let deviceInfo: [String: Any]
        public let customerInfo: [String: Any]
    }
    
    public static func registerDevice(
        authorizationCode: String,
        codeVerifier: String,
        domain: String,
        serial: String,
        withUsername: Bool = false
    ) async throws -> RegistrationResponse {
        
        let body: [String: Any] = [
            "requested_token_type": [
                "bearer",
                "mac_dms",
                "website_cookies",
                "store_authentication_cookie"
            ],
            "cookies": [
                "website_cookies": [],
                "domain": ".amazon.\(domain)"
            ],
            "registration_data": [
                "domain": "Device",
                "app_version": "3.56.2",
                "device_serial": serial,
                "device_type": "A2CZJZGLK2JJVM",
                "device_name": "%FIRST_NAME%%FIRST_NAME_POSSESSIVE_STRING%%DUPE_STRATEGY_1ST%Audible for iPhone",
                "os_version": "15.0.0",
                "software_version": "35602678",
                "device_model": "iPhone",
                "app_name": "Audible"
            ],
            "auth_data": [
                "client_id": AAXConnectLogin.buildClientId(serial: serial),
                "authorization_code": authorizationCode,
                "code_verifier": codeVerifier,
                "code_algorithm": "SHA-256",
                "client_domain": "DeviceLegacy"
            ],
            "requested_extensions": ["device_info", "customer_info"]
        ]
        
        let targetDomain = withUsername ? "audible" : "amazon"
        let urlString = "https://api.\(targetDomain).\(domain)/auth/register"
        
        guard let url = URL(string: urlString) else {
            throw AAXConnectError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw AAXConnectError.decodingError(error)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AAXConnectError.networkError(URLError(.badServerResponse))
        }
        
        guard let responseJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AAXConnectError.decodingError(URLError(.cannotParseResponse))
        }
        
        
        if httpResponse.statusCode != 200 {
            let errorMessage = responseJson.description
            throw AAXConnectError.registrationFailed(errorMessage)
        }
        
        guard let response = responseJson["response"] as? [String: Any],
              let successResponse = response["success"] as? [String: Any] else {
            throw AAXConnectError.registrationFailed("Invalid response structure")
        }
        
        guard let tokens = successResponse["tokens"] as? [String: Any],
              let macDms = tokens["mac_dms"] as? [String: Any],
              let bearer = tokens["bearer"] as? [String: Any],
              let websiteCookiesArray = tokens["website_cookies"] as? [[String: Any]],
              let storeAuthCookie = tokens["store_authentication_cookie"] as? [String: Any],
              let extensions = successResponse["extensions"] as? [String: Any],
              let deviceInfo = extensions["device_info"] as? [String: Any],
              let customerInfo = extensions["customer_info"] as? [String: Any] else {
            throw AAXConnectError.registrationFailed("Missing required tokens or extensions")
        }
        
        guard let adpToken = macDms["adp_token"] as? String,
              let devicePrivateKey = macDms["device_private_key"] as? String,
              let accessToken = bearer["access_token"] as? String,
              let refreshToken = bearer["refresh_token"] as? String else {
            throw AAXConnectError.registrationFailed("Missing required token data")
        }
        
        // Handle expires_in as either String or Int
        let expiresIn: Int
        if let expiresString = bearer["expires_in"] as? String,
           let expiresValue = Int(expiresString) {
            expiresIn = expiresValue
        } else if let expiresValue = bearer["expires_in"] as? Int {
            expiresIn = expiresValue
        } else {
            throw AAXConnectError.registrationFailed("Missing or invalid expires_in value")
        }
        
        let expires = Date().addingTimeInterval(TimeInterval(expiresIn)).timeIntervalSince1970
        
        // Process website cookies
        var websiteCookies: [String: String] = [:]
        for cookie in websiteCookiesArray {
            if let name = cookie["Name"] as? String,
               let value = cookie["Value"] as? String {
                websiteCookies[name] = value.replacingOccurrences(of: "\"", with: "")
            }
        }
        
        return RegistrationResponse(
            adpToken: adpToken,
            devicePrivateKey: devicePrivateKey,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expires: expires,
            websiteCookies: websiteCookies,
            storeAuthenticationCookie: storeAuthCookie,
            deviceInfo: deviceInfo,
            customerInfo: customerInfo
        )
    }
    
    public static func deregisterDevice(
        accessToken: String,
        domain: String,
        deregisterAll: Bool = false,
        withUsername: Bool = false
    ) async throws -> [String: Any] {
        
        let body: [String: Any] = [
            "deregister_all_existing_accounts": deregisterAll
        ]
        
        let targetDomain = withUsername ? "audible" : "amazon"
        let urlString = "https://api.\(targetDomain).\(domain)/auth/deregister"
        
        guard let url = URL(string: urlString) else {
            throw AAXConnectError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw AAXConnectError.decodingError(error)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AAXConnectError.networkError(URLError(.badServerResponse))
        }
        
        guard let responseJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AAXConnectError.decodingError(URLError(.cannotParseResponse))
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = responseJson.description
            throw AAXConnectError.registrationFailed(errorMessage)
        }
        
        return responseJson
    }
}