import Testing
@testable import AAXConnectSwift
import Foundation

@Suite("AAXConnectSwift Integration Tests")
struct IntegrationTests {
    
    @Test("Generate Auth Request")
    func testGenerateAuthRequest() async throws {
        print("\n🎧 AAXConnectSwift Auth Step 1 - Generate Login URL")
        print("=" + String(repeating: "=", count: 50))
        
        // Read country code from environment variable (provided by bash script)
        let countryCode = ProcessInfo.processInfo.environment["AAXC_COUNTRY_CODE"] ?? "us"
        print("\n📱 Generating authentication request for: \(countryCode.uppercased())")
        
        // Ensure Tests/Bindings directory exists
        let fileManager = FileManager.default
        let testsDirectory = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // .../AAXConnectSwift/Tests/AAXConnectSwiftTests
            .deletingLastPathComponent() // .../AAXConnectSwift/Tests
        let bindingsDirectory = testsDirectory.appendingPathComponent("Bindings")
        
        if !fileManager.fileExists(atPath: bindingsDirectory.path) {
            try fileManager.createDirectory(at: bindingsDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        
        // Request authentication using real AAXConnectSwift
        let authRequest = try AAXConnectAuth.requestAuth(countryCode: countryCode)
        
        // Save all auth data for step 2
        let authRequestData: [String: Any] = [
            "country_code": countryCode,
            "code_verifier": authRequest.codeVerifier,
            "serial": authRequest.serial,
            "auth_url": authRequest.authURL,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        let authRequestFile = bindingsDirectory.appendingPathComponent("aaxc_auth_request.json").path
        let jsonData = try JSONSerialization.data(withJSONObject: authRequestData, options: .prettyPrinted)
        try jsonData.write(to: URL(fileURLWithPath: authRequestFile))
        
        // Save login URL AND parameters to the same file for easy access
        let urlAndParamsFile = bindingsDirectory.appendingPathComponent("aaxc_login_data.txt").path
        let loginData = """
        \(authRequest.authURL)
        CODE_VERIFIER:\(authRequest.codeVerifier)
        SERIAL:\(authRequest.serial)
        COUNTRY_CODE:\(countryCode)
        """
        try loginData.write(to: URL(fileURLWithPath: urlAndParamsFile), atomically: true, encoding: .utf8)
        
        // Also save just the URL for backwards compatibility
        let urlFile = bindingsDirectory.appendingPathComponent("aaxc_login_url.txt").path
        try authRequest.authURL.write(to: URL(fileURLWithPath: urlFile), atomically: true, encoding: .utf8)
        
        print("✅ Authentication request generated!")
        print("   🔑 Code Verifier: \(authRequest.codeVerifier)")
        print("   📱 Serial: \(authRequest.serial)")
        print("   📁 Auth data saved: Tests/Bindings/aaxc_auth_request.json")
        print("   🔗 Login URL and params saved: Tests/Bindings/aaxc_login_data.txt")
        print("   🔗 Login URL saved: Tests/Bindings/aaxc_login_url.txt")
    }
    
    @Test("Complete Auth")
    func testCompleteAuth() async throws {
        print("\n🎧 AAXConnectSwift Auth Step 2 - Complete Authentication")
        print("=" + String(repeating: "=", count: 55))
        
        // Ensure Tests/Bindings directory exists
        let fileManager = FileManager.default
        let testsDirectory = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // .../AAXConnectSwift/Tests/AAXConnectSwiftTests
            .deletingLastPathComponent() // .../AAXConnectSwift/Tests
        let bindingsDirectory = testsDirectory.appendingPathComponent("Bindings")
        
        if !fileManager.fileExists(atPath: bindingsDirectory.path) {
            try fileManager.createDirectory(at: bindingsDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        
        // Load auth parameters from the login data file
        let urlAndParamsFile = bindingsDirectory.appendingPathComponent("aaxc_login_data.txt").path
        guard FileManager.default.fileExists(atPath: urlAndParamsFile) else {
            throw NSError(domain: "AuthError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Login data file not found at \(urlAndParamsFile). Run step 1 first."])
        }
        
        let loginDataContent = try String(contentsOfFile: urlAndParamsFile, encoding: .utf8)
        let lines = loginDataContent.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        // Parse the parameters
        guard lines.count >= 4,
              let codeVerifierLine = lines.first(where: { $0.hasPrefix("CODE_VERIFIER:") }),
              let serialLine = lines.first(where: { $0.hasPrefix("SERIAL:") }),
              let countryCodeLine = lines.first(where: { $0.hasPrefix("COUNTRY_CODE:") }) else {
            throw NSError(domain: "AuthError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid login data format"])
        }
        
        let codeVerifier = String(codeVerifierLine.dropFirst("CODE_VERIFIER:".count))
        let serial = String(serialLine.dropFirst("SERIAL:".count))
        let countryCode = String(countryCodeLine.dropFirst("COUNTRY_CODE:".count))
        
        print("📖 Loaded parameters from login data file:")
        print("   🔑 Code Verifier: \(codeVerifier)")
        print("   📱 Serial: \(serial)")
        print("   🌍 Country: \(countryCode)")
        
        // Load redirect URL
        let redirectFile = bindingsDirectory.appendingPathComponent("aaxc_redirect_url.txt").path
        guard FileManager.default.fileExists(atPath: redirectFile) else {
            throw NSError(domain: "AuthError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Redirect URL not found at \(redirectFile). Please save it to this location."])
        }
        
        let redirectURL = try String(contentsOfFile: redirectFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !redirectURL.isEmpty else {
            throw NSError(domain: "AuthError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Redirect URL is empty"])
        }
        
        print("🔐 Processing authentication with redirect URL (\(redirectURL.count) chars)")
        
        // Recreate the auth session using the saved parameters
        // This works because we enhanced requestAuth to accept codeVerifier and serial
        _ = try AAXConnectAuth.requestAuth(
            countryCode: countryCode,
            codeVerifier: codeVerifier,
            serial: serial
        )
        
        print("✅ Recreated auth session with saved parameters")
        
        // Now use the proper AAXConnectSwift API
        let client = try await AAXConnectAuth.completeAuth(redirectURL: redirectURL)
        
        print("✅ Authentication completed successfully!")
        print("   Device: \(client.authData.deviceInfo["device_name"] as? String ?? "Unknown")")
        print("   User: \(client.authData.customerInfo["name"] as? String ?? "Unknown")")
        print("   Locale: \(client.locale.countryCode)")
        print("")
        
        // Test library access
        print("📚 Testing library access...")
        let library = try await client.loadLibrary()
        print("✅ Successfully loaded library with \(library.books.count) books!")
        
        if library.books.count > 0 {
            print("   📖 First few books:")
            for i in 0..<min(3, library.books.count) {
                print("      \(i+1). \(library.books[i].title) (SKU: \(library.books[i].skuLite))")
            }
            if library.books.count > 3 {
                print("      ... and \(library.books.count - 3) more books")
            }
        }
        print("")
        
        // Save working auth data using AAXConnectClient's built-in helper
        print("💾 Saving working auth data...")
        
        let workingAuthFile = bindingsDirectory.appendingPathComponent("aaxcAuth.json").path
        let workingAuthJsonData = try client.exportAuthSessionToJSON()
        try workingAuthJsonData.write(to: URL(fileURLWithPath: workingAuthFile))
        
        print("✅ Working auth data saved to: Tests/Bindings/aaxcAuth.json")
        print("")
        
        // Verify the saved auth works using the new fromSavedAuthJSON initializer
        print("🔄 Verifying saved auth data...")
        let savedAuthData = try Data(contentsOf: URL(fileURLWithPath: workingAuthFile))
        let newClient = try AAXConnectClient(fromSavedAuthJSON: savedAuthData)
        let verifyLibrary = try await newClient.loadLibrary()
        
        print("✅ Verified: Saved auth works, loaded \(verifyLibrary.books.count) books")
        print("")
        print("🎉 Authentication generation complete!")
    }
}