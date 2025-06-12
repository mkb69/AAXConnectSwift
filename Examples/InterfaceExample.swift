import Foundation
import AAXConnectSwift

/// Simple example demonstrating the core AAXConnectSwift workflow
class InterfaceExample {
    
    static func runExample() async throws {
        // Paths for saving data
        let authPath = "/tmp/aaxc_auth.json"
        let libraryPath = "/tmp/aaxc_library.json"
        let licensePath = "/tmp/aaxc_license.json"
        
        // Step 1: Authenticate
        print("🔐 Step 1: Authenticate")
        let client = try await authenticate()
        
        // Step 2: Save auth JSON
        print("\n💾 Step 2: Save auth JSON")
        try saveAuthJSON(client: client, to: authPath)
        
        // Step 3: Load auth JSON into new client
        print("\n📖 Step 3: Load auth JSON into new client")
        let loadedClient = try loadAuthJSON(from: authPath)
        
        // Step 4: Load library and save to JSON
        print("\n📚 Step 4: Load library and save to JSON")
        let library = try await loadLibrary(client: loadedClient)
        try saveLibraryJSON(client: loadedClient, library: library, to: libraryPath)
        
        // Step 5: Download a book and save license to JSON
        if let firstBook = library.books.first {
            print("\n⬇️ Step 5: Download book and save license to JSON")
            let downloadResult = try await downloadBook(
                client: loadedClient,
                skuLite: firstBook.skuLite,
                title: firstBook.title
            )
            try saveLicenseJSON(client: loadedClient, licenseInfo: downloadResult.license, to: licensePath)
            
            // Step 6: Validate the license
            print("\n✅ Step 6: Validate license")
            validateLicense(licenseInfo: downloadResult.license)
        }
        
        print("\n🎉 Complete workflow finished!")
    }
    
    // MARK: - Step 1: Authenticate
    
    static func authenticate() async throws -> AAXConnectClient {
        // Request auth URL
        let authRequest = try AAXConnectAuth.requestAuth(countryCode: "us")
        
        print("📱 Please open this URL in your browser/webview:")
        print("   \(authRequest.authURL)")
        print("\n⏳ After login, you'll be redirected to:")
        print("   https://127.0.0.1/auth/authorize/complete?openid.oa2.authorization_code=...")
        print("\n🔗 Enter the redirect URL: ", terminator: "")
        
        // In a real app: capture this from your webview
        guard let redirectURL = readLine(), !redirectURL.isEmpty else {
            throw AAXConnectError.authenticationError("No redirect URL provided")
        }
        
        // Complete authentication
        let client = try await AAXConnectAuth.completeAuth(redirectURL: redirectURL)
        print("✅ Authentication successful!")
        
        return client
    }
    
    // MARK: - Step 2: Save Auth JSON
    
    static func saveAuthJSON(client: AAXConnectClient, to path: String) throws {
        let jsonData = try client.exportAuthSessionToJSON()
        try jsonData.write(to: URL(fileURLWithPath: path))
        print("✅ Saved auth to: \(path)")
    }
    
    // MARK: - Step 3: Load Auth JSON
    
    static func loadAuthJSON(from path: String) throws -> AAXConnectClient {
        let jsonData = try Data(contentsOf: URL(fileURLWithPath: path))
        let client = try AAXConnectClient(fromSavedAuthJSON: jsonData)
        print("✅ Loaded client from: \(path)")
        return client
    }
    
    // MARK: - Step 4: Load Library
    
    static func loadLibrary(client: AAXConnectClient) async throws -> LibraryResponse {
        let library = try await client.loadLibrary()
        print("✅ Loaded \(library.books.count) books")
        
        // Show first few books
        for (index, book) in library.books.prefix(3).enumerated() {
            print("   \(index + 1). \(book.title) (\(book.skuLite))")
        }
        
        return library
    }
    
    static func saveLibraryJSON(client: AAXConnectClient, library: LibraryResponse, to path: String) throws {
        let jsonData = try client.exportLibraryToJSON(library: library)
        try jsonData.write(to: URL(fileURLWithPath: path))
        print("✅ Saved library to: \(path)")
    }
    
    // MARK: - Step 5: Download Book
    
    static func downloadBook(client: AAXConnectClient, skuLite: String, title: String) async throws -> DownloadResult {
        let fileName = title.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "", options: .regularExpression)
        let filePath = "/tmp/\(fileName).aaxc"
        
        print("📥 Downloading: \(title)")
        
        let result = try await client.downloadBook(
            skuLite: skuLite,
            to: filePath,
            quality: "High"
        ) { progress in
            let percentage = String(format: "%.1f", progress.percentage)
            print("   Progress: \(percentage)%", terminator: "\r")
            fflush(stdout)
        }
        
        print("\n✅ Downloaded to: \(result.filePath)")
        print("   Key: \(result.license.voucher.key)")
        print("   IV: \(result.license.voucher.iv)")
        
        return result
    }
    
    static func saveLicenseJSON(client: AAXConnectClient, licenseInfo: LicenseInfo, to path: String) throws {
        let jsonData = try client.exportLicenseInfoToJSON(licenseInfo: licenseInfo)
        try jsonData.write(to: URL(fileURLWithPath: path))
        print("✅ Saved license to: \(path)")
    }
    
    // MARK: - Step 6: Validate License
    
    static func validateLicense(licenseInfo: LicenseInfo) {
        // Convert LicenseInfo to dictionary format for validation
        var voucherDict: [String: Any] = [
            "key": licenseInfo.voucher.key,
            "iv": licenseInfo.voucher.iv
        ]
        if let asin = licenseInfo.voucher.asin {
            voucherDict["asin"] = asin
        }
        if let rules = licenseInfo.voucher.rules {
            voucherDict["rules"] = rules
        }
        
        let result = AAXConnectClient.validateVoucher(voucherDict)
        
        print("   Valid: \(result.isValid)")
        print("   Status: \(result.status)")
        print("   Message: \(result.message)")
        
        if let expiryDate = result.expiryDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .short
            print("   Expires: \(formatter.string(from: expiryDate))")
        }
    }
}

// Run the example
Task {
    do {
        try await InterfaceExample.runExample()
    } catch {
        print("❌ Error: \(error)")
    }
}