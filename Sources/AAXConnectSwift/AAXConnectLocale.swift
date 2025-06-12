import Foundation

public struct AAXConnectLocale {
    public let countryCode: String
    public let domain: String
    public let marketPlaceId: String
    
    public init(countryCode: String? = nil, domain: String? = nil, marketPlaceId: String? = nil) throws {
        if let countryCode = countryCode, let template = AAXConnectLocale.searchTemplate(key: "countryCode", value: countryCode) {
            self.countryCode = template.countryCode
            self.domain = template.domain
            self.marketPlaceId = template.marketPlaceId
        } else if let domain = domain, let template = AAXConnectLocale.searchTemplate(key: "domain", value: domain) {
            self.countryCode = template.countryCode
            self.domain = template.domain
            self.marketPlaceId = template.marketPlaceId
        } else if let marketPlaceId = marketPlaceId, let template = AAXConnectLocale.searchTemplate(key: "marketPlaceId", value: marketPlaceId) {
            self.countryCode = template.countryCode
            self.domain = template.domain
            self.marketPlaceId = template.marketPlaceId
        } else if let countryCode = countryCode, let domain = domain, let marketPlaceId = marketPlaceId {
            self.countryCode = countryCode
            self.domain = domain
            self.marketPlaceId = marketPlaceId
        } else {
            throw AAXConnectError.localeNotFound
        }
    }
    
    public init(countryCode: String) throws {
        try self.init(countryCode: countryCode, domain: nil, marketPlaceId: nil)
    }
    
    public func toDictionary() -> [String: String] {
        return [
            "countryCode": countryCode,
            "domain": domain,
            "marketPlaceId": marketPlaceId
        ]
    }
    
    // MARK: - Template Management
    
    private static let localeTemplates: [String: (countryCode: String, domain: String, marketPlaceId: String)] = [
        "germany": (countryCode: "de", domain: "de", marketPlaceId: "AN7V1F1VY261K"),
        "united_states": (countryCode: "us", domain: "com", marketPlaceId: "AF2M0KC94RCEA"),
        "united_kingdom": (countryCode: "uk", domain: "co.uk", marketPlaceId: "A2I9A3Q2GNFNGQ"),
        "france": (countryCode: "fr", domain: "fr", marketPlaceId: "A2728XDNODOQ8T"),
        "canada": (countryCode: "ca", domain: "ca", marketPlaceId: "A2CQZ5RBY40XE"),
        "italy": (countryCode: "it", domain: "it", marketPlaceId: "A2N7FU2W2BU2ZC"),
        "australia": (countryCode: "au", domain: "com.au", marketPlaceId: "AN7EY7DTAW63G"),
        "india": (countryCode: "in", domain: "in", marketPlaceId: "AJO3FBRUE6J4S"),
        "japan": (countryCode: "jp", domain: "co.jp", marketPlaceId: "A1QAP3MOU4173J"),
        "spain": (countryCode: "es", domain: "es", marketPlaceId: "ALMIKO4SZCSAR"),
        "brazil": (countryCode: "br", domain: "com.br", marketPlaceId: "A10J1VAYUDTYRN")
    ]
    
    private static func searchTemplate(key: String, value: String) -> (countryCode: String, domain: String, marketPlaceId: String)? {
        for (_, locale) in localeTemplates {
            switch key {
            case "countryCode":
                if locale.countryCode == value {
                    return locale
                }
            case "domain":
                if locale.domain == value {
                    return locale
                }
            case "marketPlaceId":
                if locale.marketPlaceId == value {
                    return locale
                }
            default:
                break
            }
        }
        return nil
    }
    
    public static func autodetectLocale(domain: String) async throws -> AAXConnectLocale {
        let cleanDomain = domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let siteURL = "https://www.audible.\(cleanDomain)"
        
        guard let url = URL(string: siteURL) else {
            throw AAXConnectError.invalidURL
        }
        
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = [
            URLQueryItem(name: "ipRedirectOverride", value: "true"),
            URLQueryItem(name: "overrideBaseCountry", value: "true")
        ]
        
        guard let finalURL = urlComponents?.url else {
            throw AAXConnectError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: finalURL)
        let responseString = String(data: data, encoding: .utf8) ?? ""
        
        // Extract marketplace ID
        guard let marketPlaceMatch = responseString.range(of: #"ue_mid = '(.*)'"#, options: .regularExpression),
              let marketPlaceId = String(responseString[marketPlaceMatch]).split(separator: "'").dropFirst().first else {
            throw AAXConnectError.marketplaceNotFound
        }
        
        // Extract country code
        guard let aliasMatch = responseString.range(of: #"autocomplete_config.searchAlias = "(.*)""#, options: .regularExpression),
              let alias = String(responseString[aliasMatch]).split(separator: "\"").dropFirst().first,
              let countryCode = alias.split(separator: "-").last else {
            throw AAXConnectError.countryCodeNotFound
        }
        
        return try AAXConnectLocale(
            countryCode: String(countryCode),
            domain: cleanDomain,
            marketPlaceId: String(marketPlaceId)
        )
    }
}