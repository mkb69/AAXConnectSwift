import Testing
@testable import AAXConnectSwift
import Foundation

// TestSetupError and Character.isHexDigit are now expected to be in a shared TestHelpers.swift

// MARK: - Login Logic Tests

// Local error for voucher test if TestSetupError is not available
enum VoucherTestError: Error, CustomStringConvertible {
    case voucherFileNotFound(String)
    var description: String {
        switch self {
            case .voucherFileNotFound(let path):
                return "aaxcLicense.json not found at \(path). Run aaxcClient_bookDownload test first to generate it."
        }
    }
}

@Suite("AAXConnectClient AAXConnectLogin Tests")
struct AAXConnectClientAAXConnectLoginTests {

    @Test("AAXConnectClient: Code Verifier Creation")
    func aaxcClient_createCodeVerifier() {
        let codeVerifier = AAXConnectLogin.createCodeVerifier()
        #expect(codeVerifier.count > 0, "Code verifier should not be empty")

        let customVerifier = AAXConnectLogin.createCodeVerifier(length: 64)
        #expect(customVerifier.count > 0, "Custom length code verifier should not be empty")

        #expect(codeVerifier != customVerifier, "Code verifiers generated with different parameters or times should be different")
    }

    @Test("AAXConnectClient: Build Device Serial")
    func aaxcClient_buildDeviceSerial() {
        let serial1 = AAXConnectLogin.buildDeviceSerial()
        let serial2 = AAXConnectLogin.buildDeviceSerial()

        #expect(serial1.count == 32, "Serial number should be 32 characters long (UUID without dashes)")
        #expect(serial2.count == 32, "Serial number should be 32 characters long")
        #expect(serial1 != serial2, "Consecutively generated serials should be different")
        #expect(serial1.allSatisfy { $0.isUppercase || $0.isNumber }, "Serial should contain only uppercase letters or numbers")
    }

    @Test("AAXConnectClient: Build Client ID")
    func aaxcClient_buildClientId() {
        let serial = "TEST123SERIAL456"
        let clientId = AAXConnectLogin.buildClientId(serial: serial)

        #expect(clientId.count > 0, "Client ID should not be empty")
        #expect(clientId.allSatisfy { $0.isHexDigit }, "Client ID should contain only hex digits") // Will use isHexDigit from TestHelpers.swift
    }

    @Test("AAXConnectClient: Build OAuth URL")
    func aaxcClient_buildOAuthURL() {
        let codeVerifier = AAXConnectLogin.createCodeVerifier()
        let result = AAXConnectLogin.buildOAuthURL(
            countryCode: "ca",
            domain: "ca",
            marketPlaceId: "A2CQZ5RBY40XE",
            codeVerifier: codeVerifier
        )

        #expect(result.url.contains("amazon.ca"), "URL should contain amazon.ca domain")
        #expect(result.url.contains("oauth"), "URL should contain 'oauth'")
        #expect(result.serial.count == 32, "Generated serial in OAuth URL result should be 32 characters")

        let resultWithUsername = AAXConnectLogin.buildOAuthURL(
            countryCode: "us",
            domain: "com",
            marketPlaceId: "AF2M0KC94RCEA",
            codeVerifier: codeVerifier,
            withUsername: true
        )
        #expect(resultWithUsername.url.contains("audible.com"), "URL with username login should contain audible.com domain")
    }

    @Test("AAXConnectClient: Validate Voucher From File")
    func aaxcClient_validateVoucherFromFile() throws {
        let fileManager = FileManager.default
        let testsDirectory = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // .../AAXConnectSwift/Tests/AAXConnectSwiftTests
            .deletingLastPathComponent() // .../AAXConnectSwift/Tests
        let bindingsDirectory = testsDirectory.appendingPathComponent("Bindings")
        let licenseJSONURL = bindingsDirectory.appendingPathComponent("aaxcLicense.json")

        guard fileManager.fileExists(atPath: licenseJSONURL.path) else {
            let error = VoucherTestError.voucherFileNotFound(licenseJSONURL.path)
            print("⚠️ [AAXConnectClient Test] \(error.description)")
            Issue.record(error)
            // To make this test runnable independently, consider skipping or providing a fallback.
            // For now, it depends on the download test having run successfully prior.
            return // Or throw an error indicating dependency not met
        }

        print("Found aaxcLicense.json at \(licenseJSONURL.path), attempting validation...")
        
        let validationResult = try AAXConnectClient.validateVoucherFromFile(filePath: licenseJSONURL.path)
        
        #expect(validationResult.isValid, "Voucher from file should be valid. Status: \(validationResult.status), Message: \(validationResult.message)")
        print("✅ [AAXConnectClient Test] Voucher validation from file successful.")
        print("   Voucher Status: \(validationResult.status)")
        print("   Voucher Message: \(validationResult.message)")
        if let expiryDate = validationResult.expiryDate {
            print("   Voucher Expires: \(expiryDate)")
        }
    }

    @Test("AAXConnectClient: Validate Expired Voucher")
    func aaxcClient_validateExpiredVoucher() throws {
        let fileManager = FileManager.default
        let testsDirectory = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bindingsDirectory = testsDirectory.appendingPathComponent("Bindings")
        let licenseJSONURL = bindingsDirectory.appendingPathComponent("aaxcLicense.json")

        guard fileManager.fileExists(atPath: licenseJSONURL.path) else {
            let error = VoucherTestError.voucherFileNotFound(licenseJSONURL.path)
            print("⚠️ [AAXConnectClient Test] \(error.description) - Skipping expired voucher test.")
            Issue.record(error)
            return
        }

        let licenseData = try Data(contentsOf: licenseJSONURL)
        let originalLicenseInfo = try JSONDecoder().decode(LicenseInfo.self, from: licenseData)

        var modifiedVoucher = originalLicenseInfo.voucher
        var finalLicenseInfoToTest = originalLicenseInfo

        if var updatedRules = originalLicenseInfo.voucher.rules, !updatedRules.isEmpty {
            if var firstRule = updatedRules.first, var parameters = firstRule["parameters"] as? [[String: Any]], !parameters.isEmpty {
                if var firstParameter = parameters.first, firstParameter["type"] as? String == "EXPIRES" {
                    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime]
                    firstParameter["expireDate"] = formatter.string(from: yesterday)
                    
                    parameters[0] = firstParameter
                    firstRule["parameters"] = parameters
                    updatedRules[0] = firstRule
                    
                    // Create a new DecryptedVoucher with the modified rules
                    modifiedVoucher = AAXConnectCrypto.DecryptedVoucher(
                        key: originalLicenseInfo.voucher.key,
                        iv: originalLicenseInfo.voucher.iv,
                        asin: originalLicenseInfo.voucher.asin,
                        rules: updatedRules
                    )
                    // Create a new LicenseInfo with the modified voucher
                    finalLicenseInfoToTest = LicenseInfo(
                        contentLicense: originalLicenseInfo.contentLicense,
                        voucher: modifiedVoucher
                    )
                } else {
                    print("⚠️ [AAXConnectClient Test] Could not find EXPIRES parameter in the first rule of voucher. Skipping modification.")
                    return
                }
            } else {
                print("⚠️ [AAXConnectClient Test] Voucher rules do not contain expected parameters. Skipping modification.")
                return
            }
        } else {
            print("⚠️ [AAXConnectClient Test] Voucher does not contain rules or rules are empty. Skipping modification for expired test.")
            return
        }
        
        print("Attempting validation with a manually expired voucher...")
        // Validate using the new LicenseInfo struct that contains the modified voucher
        let validationResult = AAXConnectClient.validateVoucher(licenseInfo: finalLicenseInfoToTest)
        
        #expect(!validationResult.isValid, "Expired voucher should be invalid.")
        #expect(validationResult.status == .expired, "Expired voucher status should be .expired. Was \(validationResult.status)")
        print("✅ [AAXConnectClient Test] Expired voucher validation successful (isValid: false, status: .expired).")
        if let expiryDate = validationResult.expiryDate {
            print("   Reported Expiry Date: \(expiryDate)")
        }
        print("   Message: \(validationResult.message)")
    }

    @Test("AAXConnectClient: Validate Ad-Supported Playback Voucher")
    func aaxcClient_validateAdSupportedPlaybackVoucher() throws {
        let fileManager = FileManager.default
        let testsDirectory = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bindingsDirectory = testsDirectory.appendingPathComponent("Bindings")
        let licenseJSONURL = bindingsDirectory.appendingPathComponent("aaxcLicense.json")

        guard fileManager.fileExists(atPath: licenseJSONURL.path) else {
            let error = VoucherTestError.voucherFileNotFound(licenseJSONURL.path)
            print("⚠️ [AAXConnectClient Test] \(error.description) - Skipping ad-supported playback voucher test.")
            Issue.record(error)
            return
        }

        let licenseData = try Data(contentsOf: licenseJSONURL)
        let originalLicenseInfo = try JSONDecoder().decode(LicenseInfo.self, from: licenseData)

        // Modify the content license to require ad-supported playback
        var modifiedContentLicense = originalLicenseInfo.contentLicense
        modifiedContentLicense["requires_ad_supported_playback"] = AnyCodable(1)
        
        // Create a new LicenseInfo with the modified content license
        let finalLicenseInfoToTest = LicenseInfo(
            contentLicense: modifiedContentLicense,
            voucher: originalLicenseInfo.voucher
        )
        
        print("Attempting validation with a voucher that requires ad-supported playback...")
        // Validate using the new LicenseInfo struct that contains the modified content license
        let validationResult = AAXConnectClient.validateVoucher(licenseInfo: finalLicenseInfoToTest)
        
        #expect(!validationResult.isValid, "Ad-supported playback voucher should be invalid.")
        #expect(validationResult.status == .requiresAdSupportedPlayback, "Ad-supported playback voucher status should be .requiresAdSupportedPlayback. Was \(validationResult.status)")
        print("✅ [AAXConnectClient Test] Ad-supported playback voucher validation successful (isValid: false, status: .requiresAdSupportedPlayback).")
        print("   Message: \(validationResult.message)")
    }
}

// MARK: - Locale Logic Tests

@Suite("AAXConnectClient Locale Tests")
struct AAXConnectClientLocaleTests {

    @Test("AAXConnectClient: Locale Init With Country Code")
    func aaxcClient_localeInitWithCountryCode() throws {
        let locale = try AAXConnectLocale(countryCode: "ca")
        #expect(locale.countryCode == "ca")
        #expect(locale.domain == "ca")
        #expect(locale.marketPlaceId == "A2CQZ5RBY40XE")
    }

    @Test("AAXConnectClient: Locale Init With Domain")
    func aaxcClient_localeInitWithDomain() throws {
        let locale = try AAXConnectLocale(domain: "com")
        #expect(locale.countryCode == "us")
        #expect(locale.domain == "com")
        #expect(locale.marketPlaceId == "AF2M0KC94RCEA")
    }

    @Test("AAXConnectClient: Locale Init With Invalid Data")
    func aaxcClient_localeInitWithInvalidData() {
        #expect(throws: AAXConnectError.self) {
            _ = try AAXConnectLocale(countryCode: "invalid")
        }
    }

    @Test("AAXConnectClient: Locale To Dictionary")
    func aaxcClient_localeToDictionary() throws {
        let locale = try AAXConnectLocale(countryCode: "uk")
        let dict = locale.toDictionary()

        #expect(dict["countryCode"] == "uk")
        #expect(dict["domain"] == "co.uk")
        #expect(dict["marketPlaceId"] == "A2I9A3Q2GNFNGQ")
    }
}

// MARK: - Utility Tests

@Suite("AAXConnectClient Utility Tests")
struct AAXConnectClientUtilityTests {

    @Test("AAXConnectClient: Base64 URL Encoding")
    func aaxcClient_base64URLEncoding() {
        let testData = "Hello, World!".data(using: .utf8)!
        let encoded = testData.base64URLEncodedString()

        #expect(!encoded.contains("+"), "Base64URL encoded string should not contain '+'")
        #expect(!encoded.contains("/"), "Base64URL encoded string should not contain '/'")
        #expect(!encoded.contains("="), "Base64URL encoded string should not contain '=' (padding)")

        let decoded = Data.fromBase64URLEncoded(encoded)
        #expect(decoded != nil, "Decoded data should not be nil")
        #expect(decoded == testData, "Decoded data should match original test data")
    }
}

// MARK: - AAXConnectAuth (Non-Authenticated) Tests

@Suite("AAXConnectClient AAXConnectAuth Tests")
struct AAXConnectClientAAXConnectAuthTests {

    @Test("AAXConnectClient: Generate Login URL (Integration)")
    func aaxcClient_generateLoginURL() throws {
        let result = try AAXConnectAuth.requestAuth(countryCode: "ca")

        #expect(result.authURL.contains("amazon.ca"))
        #expect(result.authURL.contains("oauth"))
        #expect(result.codeVerifier.count > 0)
        #expect(result.serial.count == 32)
    }
}


// MARK: - Authenticated API Tests

@Suite("AAXConnectClient Authenticated API Tests")
struct AAXConnectClientAuthenticatedAPITests {
    let testAuthData: [String: Any]

    init() async throws {
        let authURL = URL(fileURLWithPath: "Tests/Bindings/aaxcAuth.json")
        guard FileManager.default.fileExists(atPath: authURL.path) else {
            throw TestSetupError(message: "aaxcAuth.json not found at \(authURL.path). Ensure test data is present.") // Uses TestSetupError from TestHelpers.swift
        }
        let data = try Data(contentsOf: authURL)
        guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TestSetupError(message: "Failed to deserialize aaxcAuth.json.") // Uses TestSetupError from TestHelpers.swift
        }
        self.testAuthData = jsonObject
    }

    @Test("AAXConnectClient: Create Authenticator From Test Data")
    func aaxcClient_createAuthenticatorFromTestData() async throws {
        #expect(!self.testAuthData.isEmpty, "Test auth data should be loaded.")
        let client = try createClientFromTestDataHelper(self.testAuthData)
        #expect(client.locale.countryCode == testAuthData["locale_code"] as? String)
        #expect(client.authData.accessToken.count > 0)
        #expect(client.authData.deviceInfo.count > 0)
        #expect(client.authData.customerInfo.count > 0)
        print("✅ [AAXConnectClient Test] Successfully created authenticator from test data")
    }

    @Test("AAXConnectClient: Library Access")
    func aaxcClient_libraryAccess() async throws {
        #expect(!self.testAuthData.isEmpty, "Test auth data should be loaded.")
        let client = try createClientFromTestDataHelper(self.testAuthData)
        
        let library = try await client.loadLibrary()
        #expect(library.books.count > 0, "Library should contain books.")
        print("Found \(library.books.count) books in library")

        if let firstBook = library.books.first {
            #expect(firstBook.title.count > 0, "First book should have a title.")
            #expect(firstBook.skuLite.count > 0, "First book should have an SKU.")
            print("First book: \(firstBook.title) (SKU: \(firstBook.skuLite))")
            
            // Verify cover art is populated
            #expect(firstBook.productImages != nil, "First book should have a product image URL")
            if let imageURL = firstBook.productImages {
                #expect(imageURL.contains("https://"), "Product image URL should be a valid HTTPS URL")
                #expect(imageURL.contains(".jpg") || imageURL.contains(".png"), "Product image URL should be an image file")
                print("First book cover art: \(imageURL)")
            }
        }
        
        // Verify that most books have cover art
        let booksWithImages = library.books.filter { $0.productImages != nil }
        let imagePercentage = Double(booksWithImages.count) / Double(library.books.count) * 100
        print("\(booksWithImages.count) out of \(library.books.count) books have cover art (\(String(format: "%.1f", imagePercentage))%)")
        #expect(booksWithImages.count > 0, "At least some books should have cover art")

        // Save the library to JSON using the new client method
        let libraryData = try client.exportLibraryToJSON(library: library)
        
        let fileManager = FileManager.default
        let testsDirectory = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // .../AAXConnectSwift/Tests/AAXConnectSwiftTests
            .deletingLastPathComponent() // .../AAXConnectSwift/Tests
        let bindingsDirectory = testsDirectory.appendingPathComponent("Bindings") // .../AAXConnectSwift/Tests/Bindings
        
        // Create Bindings directory if it doesn't exist
        if !fileManager.fileExists(atPath: bindingsDirectory.path) {
            try fileManager.createDirectory(at: bindingsDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        
        let libraryJSONURL = bindingsDirectory.appendingPathComponent("aaxcLibrary.json")
        
        try libraryData.write(to: libraryJSONURL)
        print("Successfully saved library to \(libraryJSONURL.path)")
    }

    @Test("AAXConnectClient: Book Download")
    func aaxcClient_bookDownload() async throws {
        #expect(!self.testAuthData.isEmpty, "Test auth data should be loaded.")
        let client = try createClientFromTestDataHelper(self.testAuthData)
        let library = try await client.loadLibrary()

        // Find a book with download rights (is_consumable_offline = true)
        guard let bookToDownload = library.books.first(where: { book in
            // Check if the book has offline consumption rights
            if let rights = book.customerRights,
               let isConsumableOffline = rights.isConsumableOffline {
                return isConsumableOffline
            }
            return false
        }) else {
            print("⚠️ No books with download rights found in library")
            for (index, book) in library.books.enumerated() {
                if let rights = book.customerRights,
                   let isConsumableOffline = rights.isConsumableOffline {
                    print("   \(index). \(book.title) - consumable_offline: \(isConsumableOffline)")
                } else {
                    print("   \(index). \(book.title) - no rights info")
                }
            }
            throw AAXConnectError.registrationFailed("No downloadable books available")
        }
        
        print("Testing download for first book: \(bookToDownload.title)")
        
        let fileManager = FileManager.default
        let testsDirectory = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // .../AAXConnectSwift/Tests/AAXConnectSwiftTests
            .deletingLastPathComponent() // .../AAXConnectSwift/Tests
        let bindingsDirectory = testsDirectory.appendingPathComponent("Bindings")
        
        // Create Bindings directory if it doesn't exist
        if !fileManager.fileExists(atPath: bindingsDirectory.path) {
            try fileManager.createDirectory(at: bindingsDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        
        let downloadURL = bindingsDirectory.appendingPathComponent("\(bookToDownload.skuLite).aaxc")
        
        // Clean up previous download if it exists
        try? FileManager.default.removeItem(at: downloadURL)

        let result = try await client.downloadBook(
            skuLite: bookToDownload.skuLite,
            to: downloadURL.path
        )

        #expect(result.license.voucher.key.count > 0, "Decryption key should be present for first book.")
        #expect(result.license.voucher.iv.count > 0, "Decryption IV should be present for first book.")
        #expect(result.skuLite == bookToDownload.skuLite, "Downloaded SKU should match first book SKU.")
        
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: downloadURL.path, isDirectory: &isDirectory), "Downloaded file should exist.")
        #expect(isDirectory.boolValue == false, "Downloaded path should be a file, not a directory.")
        
        let attributes = try FileManager.default.attributesOfItem(atPath: downloadURL.path)
        let fileSize = attributes[.size] as? Int ?? 0
        #expect(fileSize > 0, "Downloaded file size should be greater than 0 for first book.")
        
        print("Successfully downloaded first book: \(bookToDownload.skuLite)")
        print("Key: \(result.license.voucher.key)")
        print("IV: \(result.license.voucher.iv)")
        print("File size: \(fileSize) bytes")
        
        // Save the license info to JSON using the new client method
        let licenseData = try client.exportLicenseInfoToJSON(licenseInfo: result.license)
        let licenseJSONURL = bindingsDirectory.appendingPathComponent("aaxcLicense.json")
        try licenseData.write(to: licenseJSONURL)
        print("Successfully saved license info to \(licenseJSONURL.path)")
        print("Downloaded book file saved to: \(downloadURL.path)")
    }

    @Test("AAXConnectClient: Token Refresh on Expired Access Token")
    func aaxcClient_tokenRefreshOnExpiredAccessToken() async throws {
        #expect(!self.testAuthData.isEmpty, "Test auth data should be loaded for refresh test.")

        // 1. Get original (hopefully valid) auth data
        let originalAuthDataMap = self.testAuthData
        let originalAccessToken = originalAuthDataMap["access_token"] as? String
        #expect(originalAccessToken != nil && originalAccessToken!.isEmpty == false, "Original access token must exist in testAuthData.")

        // 2. Create AuthData with an expired 'expires' timestamp
        //    We'll use other values from the loaded testAuthData, assuming they are valid for constructing AuthData.
        guard let localeCode = originalAuthDataMap["locale_code"] as? String,
              let adpToken = originalAuthDataMap["adp_token"] as? String,
              let devicePrivateKey = originalAuthDataMap["device_private_key"] as? String,
              let refreshToken = originalAuthDataMap["refresh_token"] as? String, // Crucial for the refresh
              let websiteCookies = originalAuthDataMap["website_cookies"] as? [String: String],
              let storeAuthCookie = originalAuthDataMap["store_authentication_cookie"] as? [String: Any],
              let deviceInfo = originalAuthDataMap["device_info"] as? [String: Any],
              let customerInfo = originalAuthDataMap["customer_info"] as? [String: Any] else {
            Issue.record("Could not extract all necessary fields from testAuthData to construct expired AuthData.")
            return
        }

        let expiredTimestamp = Date().timeIntervalSince1970 - 3600 // 1 hour in the past
        
        let expiredAuthData = AuthData(
            adpToken: adpToken,
            devicePrivateKey: devicePrivateKey,
            accessToken: originalAccessToken!, // Use the original one, but mark it as expired
            refreshToken: refreshToken,
            expires: expiredTimestamp, // Set to be expired
            websiteCookies: websiteCookies,
            storeAuthenticationCookie: storeAuthCookie,
            deviceInfo: deviceInfo,
            customerInfo: customerInfo
        )

        let locale = try AAXConnectLocale(countryCode: localeCode)
        let client = AAXConnectClient(authData: expiredAuthData, locale: locale)

        // 3. Call a method that should trigger a token refresh
        //    This will make a LIVE network call for token refresh if refreshTokenIfNeeded is triggered.
        //    It will also make a LIVE network call for loadLibrary.
        print("Attempting to load library with an access token marked as expired. Expecting a token refresh...")
        let library = try await client.loadLibrary()

        // 4. Assertions
        #expect(library.books.count >= 0, "Loading library should succeed after token refresh (actual book count may vary).")
        
        let newAccessToken = client.authData.accessToken
        let newExpiry = client.authData.expires

        #expect(newAccessToken != originalAccessToken, "Access token should have been refreshed and changed.")
        #expect(newExpiry > Date().timeIntervalSince1970, "New expiry timestamp should be in the future.")
        #expect(newExpiry > expiredTimestamp, "New expiry should be greater than the deliberately expired one.")

        print("✅ Token refresh successful: New access token obtained, and expiry is in the future.")
        print("   Old Access Token (first 5 chars): \(originalAccessToken?.prefix(5) ?? "N/A")***")
        print("   New Access Token (first 5 chars): \(newAccessToken.prefix(5))***")
        print("   Old Expiry: \(Date(timeIntervalSince1970: expiredTimestamp))")
        print("   New Expiry: \(Date(timeIntervalSince1970: newExpiry))")
    }

    private func createClientFromTestDataHelper(_ authDataDict: [String: Any]) throws -> AAXConnectClient {
        guard let localeCode = authDataDict["locale_code"] as? String,
              let deviceInfo = authDataDict["device_info"] as? [String: Any],
              let customerInfo = authDataDict["customer_info"] as? [String: Any],
              let websiteCookies = authDataDict["website_cookies"] as? [String: String],
              let storeAuthCookie = authDataDict["store_authentication_cookie"] as? [String: Any] else {
            throw TestSetupError(message: "Test auth data (aaxcAuth.json) is missing required keys or has incorrect types.") // Uses TestSetupError from TestHelpers.swift
        }
        let locale = try AAXConnectLocale(countryCode: localeCode)
        let registrationResponse = AAXConnectRegister.RegistrationResponse(
            adpToken: authDataDict["adp_token"] as? String ?? "",
            devicePrivateKey: authDataDict["device_private_key"] as? String ?? "",
            accessToken: authDataDict["access_token"] as? String ?? "",
            refreshToken: authDataDict["refresh_token"] as? String ?? "",
            expires: authDataDict["expires"] as? TimeInterval ?? Date().timeIntervalSince1970 + 3600,
            websiteCookies: websiteCookies,
            storeAuthenticationCookie: storeAuthCookie,
            deviceInfo: deviceInfo,
            customerInfo: customerInfo
        )
        let clientAuthData = AuthData(
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
        return AAXConnectClient(authData: clientAuthData, locale: locale)
    }
}

// MARK: - Performance-Related Functional Tests

@Suite("AAXConnectClient Performance Functional Tests")
struct AAXConnectClientPerformanceFunctionalTests {

    @Test("AAXConnectClient: Login URL Generation (Functional)")
    func aaxcClient_loginURLGenerationPerformance_functional() throws {
        _ = try AAXConnectAuth.requestAuth(countryCode: "ca")
    }

    @Test("AAXConnectClient: Code Verifier Generation (Functional)")
    func aaxcClient_codeVerifierGenerationPerformance_functional() {
        let verifier = AAXConnectLogin.createCodeVerifier()
        #expect(verifier.count > 0, "Generated verifier should not be empty.")
    }
}