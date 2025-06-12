import Foundation

// MARK: - Main Public Interface

/// Main AAXConnectSwift authentication interface
public class AAXConnectAuth {
    private static var authSession: AuthSession?
    
    /// - Parameters:
    ///   - countryCode: Country code for the AAXConnect marketplace
    ///   - codeVerifier: Optional code verifier (will be generated if not provided)
    ///   - serial: Optional device serial (will be generated if not provided)
    public static func requestAuth(
        countryCode: String, 
        codeVerifier: String? = nil, 
        serial: String? = nil
    ) throws -> AuthRequest {
        let locale = try AAXConnectLocale(countryCode: countryCode)
        let actualCodeVerifier = codeVerifier ?? AAXConnectLogin.createCodeVerifier()
        let actualSerial = serial ?? AAXConnectLogin.buildDeviceSerial()
        
        let (oauthURL, _) = AAXConnectLogin.buildOAuthURL(
            countryCode: locale.countryCode,
            domain: locale.domain,
            marketPlaceId: locale.marketPlaceId,
            codeVerifier: actualCodeVerifier,
            serial: actualSerial
        )
        
        // Use the serial we passed in, not the one returned (they should be the same)
        let finalSerial = actualSerial
        
        // Store auth session for later use
        authSession = AuthSession(
            codeVerifier: actualCodeVerifier,
            serial: finalSerial,
            locale: locale
        )
        
        return AuthRequest(
            authURL: oauthURL,
            codeVerifier: actualCodeVerifier,
            serial: finalSerial
        )
    }
    
    public static func completeAuth(redirectURL: String) async throws -> AAXConnectClient {
        guard let session = authSession else {
            throw AAXConnectError.registrationFailed("No active auth session - call requestAuth first")
        }
        
        guard let url = URL(string: redirectURL),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw AAXConnectError.invalidURL
        }
        
        var authorizationCode: String?
        for item in queryItems {
            if item.name == "openid.oa2.authorization_code" {
                authorizationCode = item.value
                break
            }
        }
        
        guard let code = authorizationCode else {
            throw AAXConnectError.registrationFailed("Authorization code not found in response URL")
        }
        
        let registrationResponse = try await AAXConnectRegister.registerDevice(
            authorizationCode: code,
            codeVerifier: session.codeVerifier,
            domain: session.locale.domain,
            serial: session.serial
        )
        
        authSession = nil
        
        return AAXConnectClient(
            locale: session.locale,
            registrationResponse: registrationResponse
        )
    }
}

/// Main AAXConnectSwift client for library and download operations
public class AAXConnectClient {
    public let locale: AAXConnectLocale
    public var authData: AuthData
    
    internal init(locale: AAXConnectLocale, registrationResponse: AAXConnectRegister.RegistrationResponse) {
        self.locale = locale
        self.authData = AuthData(
            adpToken: registrationResponse.adpToken,
            devicePrivateKey: registrationResponse.devicePrivateKey,
            accessToken: registrationResponse.accessToken,
            refreshToken: registrationResponse.refreshToken,
            expires: registrationResponse.expires,
            websiteCookies: registrationResponse.websiteCookies,
            storeAuthenticationCookie: registrationResponse.storeAuthenticationCookie,
            deviceInfo: registrationResponse.deviceInfo,
            customerInfo: registrationResponse.customerInfo
        )
    }
    
    public init(authData: AuthData, locale: AAXConnectLocale) {
        self.authData = authData
        self.locale = locale
    }
    
    public func loadLibrary() async throws -> LibraryResponse {
        // Check if access token is expired and refresh if needed
        let currentAuthData = try await refreshTokenIfNeeded()
        
        let urlString = "https://api.audible.\(locale.domain)/1.0/library"
        guard let url = URL(string: urlString) else {
            throw AAXConnectError.invalidURL
        }
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "num_results", value: "1000"),
            URLQueryItem(name: "response_groups", value: "product_desc,product_attrs,contributors,series,product_details,customer_rights,product_extended_attrs,sku,categories,is_playable,is_visible"),
            URLQueryItem(name: "sort_by", value: "Author")
        ]
        
        guard let finalURL = components?.url else {
            throw AAXConnectError.invalidURL
        }
        
        var request = URLRequest(url: finalURL)
        request.setValue("Bearer \(currentAuthData.accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let mainJsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mainItemsArray = mainJsonObject["items"] as? [[String: Any]] else {
            print("Critical: Failed to re-parse JSON for main function logic after logging.")
            throw AAXConnectError.decodingError(URLError(.cannotParseResponse))
        }
        
        let processedItems = mainItemsArray.map { item in
            item.compactMapValues { value -> Any? in
                if value is NSNull { return nil }
                return value
            }
        }
        
        let books = processedItems.compactMap { item -> Book? in
            guard let skuLite = item["sku_lite"] as? String,
                  let title = item["title"] as? String else {
                return nil
            }

            let asin = item["asin"] as? String
            let sku = item["sku"] as? String
            let subtitle = item["subtitle"] as? String

            // Authors
            var authorsList: [String] = []
            if let authorsArray = item["authors"] as? [[String: Any]] { // Direct field from API
                authorsList = authorsArray.compactMap { $0["name"] as? String }
            }
            
            // Narrators
            var narratorsList: [String] = []
            if let narratorsArray = item["narrators"] as? [[String: Any]] { // Direct field from API
                narratorsList = narratorsArray.compactMap { $0["name"] as? String }
            }

            let contributorsArray = item["contributors"] as? [[String: Any]]
            // Fallback or supplement from contributors array if direct fields were empty or incomplete
            // This also ensures the raw contributors data is captured if present
            if let contributorsData = contributorsArray {
                if authorsList.isEmpty { // Only populate if primary source was empty
                    authorsList.append(contentsOf: contributorsData.compactMap { c in
                        if let role = c["role"] as? String, role.lowercased() == "author", let name = c["name"] as? String {
                            return name
                        }
                        return nil
                    })
                }
                if narratorsList.isEmpty { // Only populate if primary source was empty
                    narratorsList.append(contentsOf: contributorsData.compactMap { c in
                        if let role = c["role"] as? String, role.lowercased() == "narrator", let name = c["name"] as? String {
                            return name
                        }
                        return nil
                    })
                }
            }

            let releaseDate = item["release_date"] as? String
            let purchaseDate = item["purchase_date"] as? String
            let issueDate = item["issue_date"] as? String
            let publicationDatetime = item["publication_datetime"] as? String
            
            var dateAddedToLibrary: String? = nil
            if let libraryStatus = item["library_status"] as? [String: Any] {
                dateAddedToLibrary = libraryStatus["date_added"] as? String
            }

            let merchandisingSummary = item["merchandising_summary"] as? String
            let publisherName = item["publisher_name"] as? String
            let language = item["language"] as? String

            let seriesRawArray = item["series"] as? [[String: Any]]
            let firstSeriesTitle = (seriesRawArray?.first?["title"] as? String)

            let runtimeLengthMin = item["runtime_length_min"] as? Int
            let formatType = item["format_type"] as? String
            let contentType = item["content_type"] as? String
            let contentDeliveryType = item["content_delivery_type"] as? String
            
            let status = item["status"] as? String
            let isListenable = item["is_listenable"] as? Bool
            let isAdultProduct = item["is_adult_product"] as? Bool
            let isPlayable = item["is_playable"] as? Bool
            let isVisible = item["is_visible"] as? Bool
            let isFinished = item["is_finished"] as? Bool
            let isDownloaded = item["is_downloaded"] as? Bool
            let percentComplete = item["percent_complete"] as? Int

            let imageUrl = item["image_url"] as? String
            let sampleUrl = item["sample_url"] as? String
            let pdfUrl = item["pdf_url"] as? String
            let productImages = item["product_images"] as? [String: String]

            let isbn = item["isbn"] as? String

            // Serialize/Deserialize complex fields
            var contributorsData: Data? = nil
            if let contributorsDict = item["contributors"] as? [[String: Any]] {
                contributorsData = try? JSONSerialization.data(withJSONObject: contributorsDict)
            }
            var seriesListData: Data? = nil
            if let seriesListArray = item["series"] as? [[String: Any]] {
                seriesListData = try? JSONSerialization.data(withJSONObject: seriesListArray)
            }
            
            var customerRightsObject: CustomerRights? = nil
            if let customerRightsDict = item["customer_rights"] as? [String: Any] {
                do {
                    let customerRightsJSONData = try JSONSerialization.data(withJSONObject: customerRightsDict)
                    customerRightsObject = try JSONDecoder().decode(CustomerRights.self, from: customerRightsJSONData)
                } catch {
                    print("Error decoding CustomerRights for book \(title): \(error)")
                    // customerRightsObject remains nil
                }
            }

            var categoriesData: Data? = nil
            if let categoriesArray = item["categories"] as? [[String: Any]] {
                categoriesData = try? JSONSerialization.data(withJSONObject: categoriesArray)
            }
            var productExtendedAttrsData: Data? = nil
            if let productExtendedAttrsDict = item["product_extended_attrs"] as? [String: Any] {
                productExtendedAttrsData = try? JSONSerialization.data(withJSONObject: productExtendedAttrsDict)
            }
            var contentRatingData: Data? = nil
            if let contentRatingDict = item["content_rating"] as? [String: Any] {
                contentRatingData = try? JSONSerialization.data(withJSONObject: contentRatingDict)
            }

            return Book(
                skuLite: skuLite,
                asin: asin,
                sku: sku,
                title: title,
                subtitle: subtitle,
                authors: authorsList,
                narrators: narratorsList,
                contributors: contributorsData,
                releaseDate: releaseDate,
                purchaseDate: purchaseDate,
                issueDate: issueDate,
                publicationDatetime: publicationDatetime,
                dateAddedToLibrary: dateAddedToLibrary,
                merchandisingSummary: merchandisingSummary,
                publisherName: publisherName,
                language: language,
                seriesList: seriesListData,
                primarySeriesTitle: firstSeriesTitle,
                runtimeLengthMin: runtimeLengthMin,
                formatType: formatType,
                contentType: contentType,
                contentDeliveryType: contentDeliveryType,
                status: status,
                isListenable: isListenable,
                isAdultProduct: isAdultProduct,
                isPlayable: isPlayable,
                isVisible: isVisible,
                isFinished: isFinished,
                isDownloaded: isDownloaded,
                percentComplete: percentComplete,
                imageUrl: imageUrl,
                sampleUrl: sampleUrl,
                pdfUrl: pdfUrl,
                productImages: productImages,
                isbn: isbn,
                customerRights: customerRightsObject,
                categories: categoriesData,
                productExtendedAttrs: productExtendedAttrsData,
                contentRating: contentRatingData
            )
        }
        
        return LibraryResponse(
            books: books,
            totalResults: mainJsonObject["total_results"] as? Int ?? books.count
        )
    }
    
    /// Download a book by SKU to specified path with progress tracking
    public func downloadBook(
        skuLite: String, 
        to filePath: String,
        quality: String = "High",
        progressHandler: ((DownloadProgress) -> Void)? = nil
    ) async throws -> DownloadResult {
        
        // Find ASIN for the SKU (needed for license API)
        guard let asin = try await getASINForSKU(skuLite: skuLite) else {
            throw AAXConnectError.registrationFailed("Book with SKU '\(skuLite)' not found")
        }
        
        // Get license response
        let licenseResponse = try await getLicenseResponse(asin: asin, quality: quality)
        
        // Extract download URL
        guard let contentLicense = licenseResponse["content_license"] as? [String: Any],
              let contentMetadata = contentLicense["content_metadata"] as? [String: Any],
              let contentURL = contentMetadata["content_url"] as? [String: Any],
              let offlineURL = contentURL["offline_url"] as? String else {
            throw AAXConnectError.decryptionFailed("Missing download URL in license response")
        }
        
        // Decrypt voucher for decryption keys
        let voucher = try AAXConnectCrypto.decryptVoucherFromLicenseRequest(
            deviceInfo: authData.deviceInfo,
            customerInfo: authData.customerInfo,
            licenseResponse: licenseResponse
        )
        
        // Download file with progress
        try await downloadFile(
            from: offlineURL,
            to: filePath,
            progressHandler: progressHandler
        )
        
        return DownloadResult(
            skuLite: skuLite,
            filePath: filePath,
            license: LicenseInfo(contentLicense: contentLicense.mapValues { AnyCodable($0) }, voucher: voucher)
        )
    }
    
    private func refreshTokenIfNeeded() async throws -> AuthData {
        // Check if access token is expired
        if Date().timeIntervalSince1970 > authData.expires {
            // Token is expired, refresh it
            let refreshedAuthData = try await refreshAccessToken()
            // Update the stored auth data
            self.authData = refreshedAuthData
            return refreshedAuthData
        }
        
        return authData
    }
    
    private func refreshAccessToken() async throws -> AuthData {
        let body: [String: Any] = [
            "app_name": "Audible",
            "app_version": "3.56.2",
            "source_token": authData.refreshToken,
            "requested_token_type": "access_token",
            "source_token_type": "refresh_token"
        ]
        
        let urlString = "https://api.amazon.\(locale.domain)/auth/token"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Convert to form data
        let formData = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = formData.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AAXConnectError.networkError(URLError(.badServerResponse))
        }
        
        guard let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = responseDict["access_token"] as? String,
              let expiresInSec = responseDict["expires_in"] as? Int else {
            throw AAXConnectError.decodingError(URLError(.cannotParseResponse))
        }
        
        let newExpires = Date().timeIntervalSince1970 + Double(expiresInSec)
        
        return AuthData(
            adpToken: authData.adpToken,
            devicePrivateKey: authData.devicePrivateKey,
            accessToken: newAccessToken,
            refreshToken: authData.refreshToken,
            expires: newExpires,
            websiteCookies: authData.websiteCookies,
            storeAuthenticationCookie: authData.storeAuthenticationCookie,
            deviceInfo: authData.deviceInfo,
            customerInfo: authData.customerInfo
        )
    }
    
    /// Validate if a voucher is currently valid by checking expiry rules and ad-supported playback requirements
    public static func validateVoucher(licenseInfo: LicenseInfo, at date: Date = Date()) -> VoucherValidationResult {
        // First check if ad-supported playback is required
        if let requiresAdSupportedPlaybackAnyCodable = licenseInfo.contentLicense["requires_ad_supported_playback"],
           let requiresAdSupportedPlayback = requiresAdSupportedPlaybackAnyCodable.value as? Int,
           requiresAdSupportedPlayback == 1 {
            return VoucherValidationResult(
                isValid: false,
                status: .requiresAdSupportedPlayback,
                expiryDate: nil,
                message: "License requires ad-supported playback"
            )
        }
        
        // Extract license rules from the contentLicense part of LicenseInfo
        // The rules are expected to be under a "rules" key within the contentLicense dictionary.
        var rulesToProcess: [[String: Any]]?

        // First check if rules are in the decrypted voucher (this is where they typically are)
        if let voucherRules = licenseInfo.voucher.rules {
            rulesToProcess = voucherRules
        } else if let rulesAnyCodable = licenseInfo.contentLicense["rules"],
           let rules = rulesAnyCodable.value as? [[String: Any]] {
            rulesToProcess = rules
        } else if let licenseResponseAnyCodable = licenseInfo.contentLicense["license_response"],
                  let licenseResponseDict = licenseResponseAnyCodable.value as? [String: Any],
                  let nestedRules = licenseResponseDict["rules"] as? [[String: Any]] {
            rulesToProcess = nestedRules
        } else if let licenseResponseStrAnyCodable = licenseInfo.contentLicense["license_response"],
                  let licenseResponseStr = licenseResponseStrAnyCodable.value as? String,
                  let licenseResponseData = licenseResponseStr.data(using: .utf8),
                  let licenseResponseJson = try? JSONSerialization.jsonObject(with: licenseResponseData) as? [String: Any],
                  let nestedRules = licenseResponseJson["rules"] as? [[String: Any]] {
            rulesToProcess = nestedRules
        }

        guard let actualRules = rulesToProcess else {
            // If no rules are found in any expected location, consider it valid as per new requirement.
            print("Debug: No 'rules' array found in any expected location within contentLicense or nested license_response. Treating as valid.")
            return VoucherValidationResult(
                isValid: true, // Changed from false
                status: .noRules, // Status remains .noRules
                expiryDate: nil,
                message: "No license rules found, voucher considered valid by default." // Updated message
            )
        }
        
        let processingResult = processRules(actualRules, at: date)

        // If processing rules results in .noExpiryRule, it means EXPIRES rules were not found or malformed.
        // As per new requirement, this should also be considered valid.
        if processingResult.status == .noExpiryRule {
            return VoucherValidationResult(
                isValid: true, // Changed from false
                status: .noExpiryRule, // Status remains .noExpiryRule
                expiryDate: nil, // No expiry date found
                message: "No EXPIRES rules found or rules were malformed, voucher considered valid by default." // Updated message
            )
        }
        
        // For other statuses (e.g., .valid, .expired), return the result directly.
        return processingResult
    }

    // Helper function to process voucher rules
    private static func processRules(_ rules: [[String: Any]], at date: Date) -> VoucherValidationResult {
        var earliestExpiry: Date?
        var hasValidExpiresRule = false // Changed from hasValidRule to be specific to EXPIRES
        
        // Check each rule
        for rule in rules {
            guard let ruleName = rule["name"] as? String,
                  let parameters = rule["parameters"] as? [[String: Any]] else {
                continue
            }
            
            // Process rule parameters
            for parameter in parameters {
                guard let type = parameter["type"] as? String else { continue }
                
                if type == "EXPIRES" {
                    if let expireDateString = parameter["expireDate"] as? String {
                        let formatter = ISO8601DateFormatter()
                        // Try with fractional seconds first
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        var expiryDate = formatter.date(from: expireDateString)
                        
                        // If that fails, try without fractional seconds
                        if expiryDate == nil {
                            formatter.formatOptions = [.withInternetDateTime]
                            expiryDate = formatter.date(from: expireDateString)
                        }
                        
                        if let expiryDate = expiryDate {
                            hasValidExpiresRule = true // An EXPIRES rule was found and parsed
                            
                            // Track earliest expiry
                            if earliestExpiry == nil || expiryDate < earliestExpiry! {
                                earliestExpiry = expiryDate
                            }
                            
                            // Check if this rule is expired
                            if date > expiryDate {
                                return VoucherValidationResult(
                                    isValid: false,
                                    status: .expired,
                                    expiryDate: expiryDate,
                                    message: "License expired on \(expireDateString) (Rule: \(ruleName))"
                                )
                            }
                        }
                    }
                }
            }
        }
        
        // If we found and processed at least one EXPIRES rule and none caused an early 'expired' return, voucher is valid.
        if hasValidExpiresRule {
            return VoucherValidationResult(
                isValid: true,
                status: .valid, // Status is .valid because EXPIRES rules were processed
                expiryDate: earliestExpiry,
                message: earliestExpiry != nil ? "Valid until \(ISO8601DateFormatter().string(from: earliestExpiry!))" : "Valid (EXPIRES rules processed without specific future date, or date is in future)"
            )
        } else {
            // If no EXPIRES rules were found or were malformed (hasValidExpiresRule is false)
            return VoucherValidationResult(
                isValid: false, // This will be overridden by the caller as per new requirement
                status: .noExpiryRule,
                expiryDate: nil,
                message: "No EXPIRES rules found in voucher or EXPIRES rules were malformed."
            )
        }
    }
    
    public static func validateVoucherFromFile(filePath: String, at date: Date = Date()) throws -> VoucherValidationResult {
        let url = URL(fileURLWithPath: filePath)
        let data = try Data(contentsOf: url)
        
        let decoder = JSONDecoder()
        let licenseInfo = try decoder.decode(LicenseInfo.self, from: data)
        
        return validateVoucher(licenseInfo: licenseInfo, at: date)
    }

    public convenience init(fromSavedAuthJSON jsonData: Data) throws {
        guard let jsonDictionary = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw AAXConnectError.decodingError(URLError(.cannotParseResponse, userInfo: [NSLocalizedDescriptionKey: "Failed to parse saved auth JSON data into a dictionary."]))
        }

        guard let localeCode = jsonDictionary["locale_code"] as? String else {
            throw AAXConnectError.invalidAuthDataJSON(message: "Missing 'locale_code' in saved auth JSON.")
        }
        let locale = try AAXConnectLocale(countryCode: localeCode)

        guard let adpToken = jsonDictionary["adp_token"] as? String,
              let devicePrivateKey = jsonDictionary["device_private_key"] as? String,
              let accessToken = jsonDictionary["access_token"] as? String,
              let refreshToken = jsonDictionary["refresh_token"] as? String,
              let expires = jsonDictionary["expires"] as? TimeInterval,
              let websiteCookies = jsonDictionary["website_cookies"] as? [String: String],
              let storeAuthCookie = jsonDictionary["store_authentication_cookie"] as? [String: Any],
              let deviceInfo = jsonDictionary["device_info"] as? [String: Any],
              let customerInfo = jsonDictionary["customer_info"] as? [String: Any]
        else {
            throw AAXConnectError.invalidAuthDataJSON(message: "Saved auth JSON is missing required fields or has incorrect types for AuthData components.")
        }

        let authData = AuthData(
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

        self.init(authData: authData, locale: locale)
    }

    public func exportAuthSessionToJSON() throws -> Data {
        let authSessionDict: [String: Any] = [
            "locale_code": self.locale.countryCode,
            "adp_token": self.authData.adpToken,
            "device_private_key": self.authData.devicePrivateKey,
            "access_token": self.authData.accessToken,
            "refresh_token": self.authData.refreshToken,
            "expires": self.authData.expires,
            "website_cookies": self.authData.websiteCookies,
            "store_authentication_cookie": self.authData.storeAuthenticationCookie,
            "device_info": self.authData.deviceInfo,
            "customer_info": self.authData.customerInfo
        ]
        do {
            return try JSONSerialization.data(withJSONObject: authSessionDict, options: [.prettyPrinted])
        } catch {
            throw AAXConnectError.encodingError(message: "Failed to serialize combined auth session to JSON: \(error.localizedDescription)")
        }
    }

    /// Exports a LibraryResponse object to JSON Data.
    /// - Parameter library: The LibraryResponse object to export.
    /// - Returns: JSON Data representing the library.
    /// - Throws: An error if JSON encoding fails.
    public func exportLibraryToJSON(library: LibraryResponse) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted // For readable JSON
        do {
            return try encoder.encode(library)
        } catch {
            throw AAXConnectError.encodingError(message: "Failed to serialize LibraryResponse to JSON: \(error.localizedDescription)")
        }
    }

    public func exportLicenseInfoToJSON(licenseInfo: LicenseInfo) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        do {
            return try encoder.encode(licenseInfo)
        } catch {
            throw AAXConnectError.encodingError(message: "Failed to serialize LicenseInfo to JSON: \(error.localizedDescription)")
        }
    }
}

// MARK: - Public Data Types

/// Authentication request containing login URL and session data
public struct AuthRequest {
    public let authURL: String
    public let codeVerifier: String
    public let serial: String
}

/// Library response containing processed books and raw data
public struct LibraryResponse: Encodable, @unchecked Sendable {
    public let books: [Book]
    public let totalResults: Int

    enum CodingKeys: String, CodingKey {
        case books
        case totalResults
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(books, forKey: .books)
        try container.encode(totalResults, forKey: .totalResults)

        // The rawLibrary field is intentionally not encoded here
        // to exclude it from the JSON output as per user request.
    }
}

/// Download progress information
public struct DownloadProgress {
    public let bytesDownloaded: Int64
    public let totalBytes: Int64
    public let percentage: Double
}

/// Contains the license information including the content license and the decrypted voucher.
public struct LicenseInfo: Codable {
    public let contentLicense: [String: AnyCodable] // The raw content_license part of the license response
    public let voucher: AAXConnectCrypto.DecryptedVoucher // The decrypted voucher

    enum CodingKeys: String, CodingKey {
        case contentLicense = "content_license"
        case voucher
    }
}

/// Download result containing file info and decryption data
public struct DownloadResult {
    public let skuLite: String
    public let filePath: String
    public let license: LicenseInfo // Changed from individual key/IV and rawLicenseResponse
}

/// Voucher validation status
public enum VoucherValidationStatus {
    case valid
    case expired
    case noRules
    case noExpiryRule
    case requiresAdSupportedPlayback
}

/// Result of voucher validation
public struct VoucherValidationResult {
    public let isValid: Bool
    public let status: VoucherValidationStatus
    public let expiryDate: Date?
    public let message: String
}

/// Authentication data structure
public struct AuthData: Codable {
    public let adpToken: String
    public let devicePrivateKey: String
    public let accessToken: String
    public let refreshToken: String
    public let expires: TimeInterval
    public let websiteCookies: [String: String]
    public let storeAuthenticationCookie: [String: Any]
    public let deviceInfo: [String: Any]
    public let customerInfo: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case adpToken = "adp_token"
        case devicePrivateKey = "device_private_key"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expires, websiteCookies, storeAuthenticationCookie, deviceInfo, customerInfo
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(adpToken, forKey: .adpToken)
        try container.encode(devicePrivateKey, forKey: .devicePrivateKey)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(refreshToken, forKey: .refreshToken)
        try container.encode(expires, forKey: .expires)
        try container.encode(websiteCookies, forKey: .websiteCookies)
        
        // Handle Any types by converting to JSON data
        let storeAuthData = try JSONSerialization.data(withJSONObject: storeAuthenticationCookie)
        try container.encode(storeAuthData, forKey: .storeAuthenticationCookie)
        
        let deviceInfoData = try JSONSerialization.data(withJSONObject: deviceInfo)
        try container.encode(deviceInfoData, forKey: .deviceInfo)
        
        let customerInfoData = try JSONSerialization.data(withJSONObject: customerInfo)
        try container.encode(customerInfoData, forKey: .customerInfo)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        adpToken = try container.decode(String.self, forKey: .adpToken)
        devicePrivateKey = try container.decode(String.self, forKey: .devicePrivateKey)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        expires = try container.decode(TimeInterval.self, forKey: .expires)
        websiteCookies = try container.decode([String: String].self, forKey: .websiteCookies)
        
        // Decode JSON data back to Any types
        let storeAuthData = try container.decode(Data.self, forKey: .storeAuthenticationCookie)
        storeAuthenticationCookie = try JSONSerialization.jsonObject(with: storeAuthData) as? [String: Any] ?? [:]
        
        let deviceInfoData = try container.decode(Data.self, forKey: .deviceInfo)
        deviceInfo = try JSONSerialization.jsonObject(with: deviceInfoData) as? [String: Any] ?? [:]
        
        let customerInfoData = try container.decode(Data.self, forKey: .customerInfo)
        customerInfo = try JSONSerialization.jsonObject(with: customerInfoData) as? [String: Any] ?? [:]
    }
    
    internal init(
        adpToken: String,
        devicePrivateKey: String,
        accessToken: String,
        refreshToken: String,
        expires: TimeInterval,
        websiteCookies: [String: String],
        storeAuthenticationCookie: [String: Any],
        deviceInfo: [String: Any],
        customerInfo: [String: Any]
    ) {
        self.adpToken = adpToken
        self.devicePrivateKey = devicePrivateKey
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expires = expires
        self.websiteCookies = websiteCookies
        self.storeAuthenticationCookie = storeAuthenticationCookie
        self.deviceInfo = deviceInfo
        self.customerInfo = customerInfo
    }
}

// MARK: - Internal Types

internal struct AuthSession {
    let codeVerifier: String
    let serial: String
    let locale: AAXConnectLocale
}

// MARK: - Helper Extensions

extension AAXConnectClient {
    
    /// Get ASIN for a given SKU by searching the library
    private func getASINForSKU(skuLite: String) async throws -> String? {
        let library = try await loadLibrary()
        return library.books.first { $0.skuLite.lowercased() == skuLite.lowercased() }?.asin
    }
    
    /// Create RSA signature for API request authentication
    private func createRSASignature(method: String, path: String, body: Data) throws -> (signature: String, timestamp: String) {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        
        // Create signature string: method\npath\ntimestamp\nbody\nadp_token
        let signatureString = "\(method)\n\(path)\n\(timestamp)\n\(bodyString)\n\(authData.adpToken)"
        
        guard let signatureData = signatureString.data(using: .utf8) else {
            throw AAXConnectError.registrationFailed("Failed to create signature data")
        }
        
        // Parse the private key
        guard let privateKeyData = authData.devicePrivateKey.data(using: .utf8) else {
            throw AAXConnectError.registrationFailed("Invalid private key format")
        }
        
        let privateKey = try parsePrivateKey(from: privateKeyData)
        
        // Sign with RSA-SHA256
        let signature = try signData(signatureData, with: privateKey)
        let signatureWithTimestamp = signature + ":" + timestamp
        
        return (signature: signatureWithTimestamp, timestamp: timestamp)
    }
    
    /// Parse PEM private key
    private func parsePrivateKey(from data: Data) throws -> SecKey {
        let keyString = String(data: data, encoding: .utf8) ?? ""
        let cleanKey = keyString
            .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        
        guard let keyData = Data(base64Encoded: cleanKey) else {
            throw AAXConnectError.registrationFailed("Invalid private key base64")
        }
        
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]
        
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            throw AAXConnectError.registrationFailed("Failed to create SecKey: \(error?.takeRetainedValue().localizedDescription ?? "Unknown error")")
        }
        
        return secKey
    }
    
    /// Sign data with RSA private key using SHA256
    private func signData(_ data: Data, with privateKey: SecKey) throws -> String {
        var error: Unmanaged<CFError>?
        guard let signatureData = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error
        ) else {
            throw AAXConnectError.registrationFailed("Failed to sign data: \(error?.takeRetainedValue().localizedDescription ?? "Unknown error")")
        }
        
        return (signatureData as Data).base64EncodedString()
    }
    
    /// Get license response for a book using ASIN
    private func getLicenseResponse(asin: String, quality: String) async throws -> [String: Any] {
        let urlString = "https://api.audible.\(locale.domain)/1.0/content/\(asin)/licenserequest"
        guard let url = URL(string: urlString) else {
            throw AAXConnectError.invalidURL
        }
        
        let body: [String: Any] = [
            "drm_type": "Adrm",
            "consumption_type": "Download",
            "quality": quality
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        
        // Create RSA signature for authentication
        let path = "/1.0/content/\(asin)/licenserequest"
        let (signature, _) = try createRSASignature(method: "POST", path: path, body: bodyData)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Use RSA signing headers instead of Bearer token
        request.setValue(authData.adpToken, forHTTPHeaderField: "x-adp-token")
        request.setValue("SHA256withRSA:1.0", forHTTPHeaderField: "x-adp-alg")
        request.setValue(signature, forHTTPHeaderField: "x-adp-signature")
        
        request.httpBody = bodyData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AAXConnectError.networkError(URLError(.badServerResponse))
        }
        
        // If not successful, try to get error details
        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("License request failed with status \(httpResponse.statusCode):")
                if let jsonData = try? JSONSerialization.data(withJSONObject: errorJson, options: [.prettyPrinted]),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    print(jsonString)
                }
            }
            throw AAXConnectError.networkError(URLError(.badServerResponse))
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AAXConnectError.decodingError(URLError(.cannotParseResponse))
        }
        
        return json
    }
    
    /// Download file with progress tracking
    private func downloadFile(
        from urlString: String,
        to filePath: String,
        progressHandler: ((DownloadProgress) -> Void)?
    ) async throws {
        guard let downloadURL = URL(string: urlString) else {
            throw AAXConnectError.invalidURL
        }
        
        let destinationURL = URL(fileURLWithPath: filePath)
        
        var request = URLRequest(url: downloadURL)
        request.setValue("Audible/671 CFNetwork/1240.0.4 Darwin/20.6.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AAXConnectError.networkError(URLError(.badServerResponse))
        }
        
        try data.write(to: destinationURL)
        
        if let progressHandler = progressHandler {
            let progress = DownloadProgress(
                bytesDownloaded: Int64(data.count),
                totalBytes: Int64(data.count),
                percentage: 100.0
            )
            progressHandler(progress)
        }
    }
}

public enum AAXConnectError: Error, LocalizedError {
    case registrationFailed(String)
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case decryptionFailed(String)
    case invalidAuthDataJSON(message: String)
    case encodingError(message: String)
    case localeNotFound
    case marketplaceNotFound
    case countryCodeNotFound
    case missingDeviceInfo
    case missingCustomerInfo

    public var errorDescription: String? {
        switch self {
        case .registrationFailed(let message):
            return "Registration failed: \(message)"
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .decryptionFailed(let message):
            return "Decryption failed: \(message)"
        case .invalidAuthDataJSON(let message):
            return "Invalid Saved Auth JSON: \(message)"
        case .encodingError(let message):
            return "Encoding Error: \(message)"
        case .localeNotFound:
            return "Locale not found"
        case .marketplaceNotFound:
            return "Marketplace ID not found during locale autodetect"
        case .countryCodeNotFound:
            return "Country code not found during locale autodetect"
        case .missingDeviceInfo:
            return "Device information is missing or incomplete"
        case .missingCustomerInfo:
            return "Customer information is missing or incomplete"
        }
    }
}

// Helper for encoding/decoding mixed type dictionaries for Codable
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictionaryValue = try? container.decode([String: AnyCodable].self) {
            value = dictionaryValue.mapValues { $0.value }
        } else {
            // This was the previous line that caused a type mismatch error for certain structures, 
            // especially if a nil value was encountered that wasn't one of the explicitly checked types.
            // For wider compatibility, if none of the above decode, we might assume it's meant to be nil or throw a more specific error.
            // However, the original code threw a typeMismatch, so we maintain that for now unless a specific case requires nil.
            // If it's truly an unsupported type for decoding, throwing is appropriate.
            // If it *could* be nil, `try? container.decodeNil()` would be an option, then assign a default or handle.
            guard container.decodeNil() == false else {
                // It was successfully decoded as nil. This is tricky because AnyCodable(nil) is not directly representable
                // unless we define `value` as `Any?`. Assuming `value: Any` means it should hold a concrete value or NSNull.
                // A common way to represent 'absence of value' that can be stored in 'Any' is NSNull.
                value = NSNull() // Or handle as an error if nil is not expected here.
                return
            }
            throw DecodingError.typeMismatch(AnyCodable.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported AnyCodable type"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let boolValue = value as? Bool {
            try container.encode(boolValue)
        } else if let arrayValue = value as? [Any] {
            try container.encode(arrayValue.map { AnyCodable($0) })
        } else if let dictionaryValue = value as? [String: Any] {
            try container.encode(dictionaryValue.mapValues { AnyCodable($0) })
        } else {
            let mirror = Mirror(reflecting: value)
            if value is NSNull || (mirror.displayStyle == .optional && mirror.children.isEmpty) {
                 try container.encodeNil()
            } else {
                 throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported AnyCodable value type: \\(type(of: value))"))
            }
        }
    }
}