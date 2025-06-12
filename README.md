# AAXConnectSwift

A Swift package for compatibility access to purchased AAXC audiobooks.

## Purpose & Intention

This library exists to solve a fundamental compatibility issue: **Amazon sells audiobooks through Audible and provides download access to .aaxc files, but remarkably provides no official player to play these purchased files on many platforms.**

### Key Points:
- **✅ Compatibility, Not Circumvention**: Designed for legitimate access to books you have purchased
- **✅ Filling the Gap**: Audible provides downloads but no universal player
- **✅ License Validation**: Always verify voucher validity before allowing playback  
- **✅ Respecting Rights**: Maintains the integrity of AAXC's license system
- **⚠️ User Responsibility**: Ensure you own the books you access and comply with terms of service

### Typical Use Case:
1. Purchase audiobook from Audible
2. Download .aaxc file from Audible website
3. Use this library to validate license and extract decryption keys
4. Play your purchased content in a compatible player

**This library is intended for compatibility with legitimately purchased content.**

## Features

The package supports the complete Audible workflow:

1. **Authentication** - OAuth login with webview integration
2. **Library Access** - Fetch and manage your book library
3. **SKU-based Downloads** - Download books using SKU_LITE identifiers
4. **Progress Tracking** - Real-time download progress callbacks
5. **License Management** - Full license data including expiry
6. **Voucher Validation** - Verify license validity and expiry dates
7. **Crypto Integration** - Built-in decryption key extraction

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "path/to/AAXConnectSwift", from: "1.0.0")
]
```

## Quick Start

### Authentication Flow

```swift
import AAXConnectSwift

// Step 1: Request authentication URL
let authRequest = try AAXConnectAuth.requestAuth(countryCode: "us")
print("Open in webview: \(authRequest.authURL)")

// Step 2: Complete authentication with redirect URL
let client = try await AAXConnectAuth.completeAuth(redirectURL: redirectURL)

// Step 3: Save auth data for future use
let authData = client.authData
```

### Library Management

```swift
// Load your complete library
let library = try await client.loadLibrary()

print("Found \(library.books.count) books")
for book in library.books.prefix(5) {
    print("\(book.title) (SKU: \(book.skuLite))")
}

let rawData = library.rawLibrary // Full metadata with nulls removed
```

### Download Books

```swift
// Download by SKU with progress tracking
let result = try await client.downloadBook(
    skuLite: "BK_ADBL_002642",
    to: "/path/to/audiobook.aaxc",
    quality: "High"
) { progress in
    print("Download: \(progress.percentage)%")
}

// Get decryption info
print("Key: \(result.decryptionKey)")
print("IV: \(result.decryptionIV)")

// Check license expiry
if let expiry = result.rawLicenseResponse["content_license"]?["license_response"]?["expiry"] {
    print("License expires: \(expiry)")
}
```

### Voucher Validation

**⚠️ Critical for Compliance**: Always validate license vouchers before allowing playback to ensure proper respect for Audible's licensing system:

```swift
// Validate voucher from download info file
let result = try AAXConnectClient.validateVoucherFromFile(
    filePath: "/path/to/downloadInfo_BK_ADBL_002642.json"
)

print("Valid: \(result.isValid)")
print("Status: \(result.status)")
print("Message: \(result.message)")
if let expiryDate = result.expiryDate {
    print("Expires: \(expiryDate)")
}

// Validate custom voucher data
let customVoucher: [String: Any] = [
    "key": "decryption_key",
    "iv": "initialization_vector",
    "rules": [
        [
            "name": "DefaultExpiresRule", 
            "parameters": [
                [
                    "type": "EXPIRES",
                    "expireDate": "3000-01-01T00:00:00Z"
                ]
            ]
        ]
    ]
]

let customResult = AAXConnectClient.validateVoucher(customVoucher)
print("Custom voucher valid: \(customResult.isValid)")

// Check validity at specific date
let futureDate = Calendar.current.date(byAdding: .year, value: 10, to: Date())!
let futureResult = AAXConnectClient.validateVoucher(customVoucher, at: futureDate)
print("Valid in 10 years: \(futureResult.isValid)")
```

### Complete Example

```swift
// Authentication
let authRequest = try AAXConnectAuth.requestAuth(countryCode: "us")
// ... show authRequest.authURL in webview ...
let client = try await AAXConnectAuth.completeAuth(redirectURL: redirectURL)

// Library access  
let library = try await client.loadLibrary()

// Download first book
if let firstBook = library.books.first {
    let result = try await client.downloadBook(
        skuLite: firstBook.skuLite,
        to: "/tmp/\(firstBook.title).aaxc"
    )
    print("Downloaded: \(result.filePath)")
}
```

### Individual Component Usage

```swift
// Create locale
let locale = try AAXConnectLocale(countryCode: "us")
print(locale.domain) // "com"
print(locale.marketPlaceId) // "AF2M0KC94RCEA"

// Generate code verifier
let codeVerifier = AAXConnectLogin.createCodeVerifier()

// Build OAuth URL
let (url, serial) = AAXConnectLogin.buildOAuthURL(
    countryCode: locale.countryCode,
    domain: locale.domain,
    marketPlaceId: locale.marketPlaceId,
    codeVerifier: codeVerifier
)
```

## Testing

Run the test suite:

```bash
# First you need to generate auth credentials:
./generateAuth.sh
# then you can test
swift test --filter "AAXConnectClient.*"
# run tests twice for them all to pass, there is an ordering issue.
```

### Interactive Authentication Testing

For manual authentication testing (requires browser login):

```bash
# Step 1: Generate login URL
AAXC_COUNTRY_CODE=uk swift test --filter testGenerateAuthRequest

# Step 2: Open the generated URL, login, and save redirect URL to /tmp/aaxc_redirect_url.txt
# Then complete authentication:
swift test --filter testCompleteAuth
```

The package includes comprehensive tests covering:
- Unit tests for all core functions  
- Integration tests with real authentication
- Performance tests
- Complete workflow demonstration

### Critical Authentication Implementation Notes

**⚠️ OAuth Parameter Consistency**: The most critical aspect of the authentication flow is maintaining **exact parameter consistency** throughout the OAuth process:

1. **Code Verifier & Serial Persistence**: The `code_verifier` and `serial` generated during login URL creation MUST be the exact same values used during token exchange
2. **Single-Use Authorization Codes**: Authorization codes from Amazon are single-use and expire quickly (typically 10 minutes)
3. **Session State Management**: The authentication session must preserve the original parameters between steps

**Common Authentication Errors:**

- `InvalidValue` Error: Usually indicates mismatched OAuth parameters between login URL generation and token exchange
- `Missing required token data`: Response parsing issue, often due to unexpected data types (e.g., `expires_in` as String vs Int)
- Authorization code reuse: Attempting to use an already-consumed or expired authorization code

**Authentication Flow Debugging:**

The integration tests save parameters to `/tmp/aaxc_login_data.txt` in format:
```
[LOGIN_URL]
CODE_VERIFIER:[verifier]
SERIAL:[serial]  
COUNTRY_CODE:[country]
```

This ensures the same parameters are used in both authentication steps, preventing OAuth mismatches that cause authentication failures.

## Supported Marketplaces

- 🇺🇸 United States (com)
- 🇨🇦 Canada (ca)
- 🇬🇧 United Kingdom (co.uk)
- 🇩🇪 Germany (de)
- 🇫🇷 France (fr)
- 🇮🇹 Italy (it)
- 🇦🇺 Australia (com.au)
- 🇮🇳 India (in)
- 🇯🇵 Japan (co.jp)
- 🇪🇸 Spain (es)
- 🇧🇷 Brazil (com.br)

## Requirements

- iOS 13.0+ / macOS 10.15+
- Swift 5.7+
- Xcode 14.0+

## Dependencies

- [Swift Crypto](https://github.com/apple/swift-crypto) - For cryptographic operations

## Security Note

This package handles authentication tokens and encrypted content. Always:
- Store authentication data securely
- Never commit credentials to version control
- Use proper keychain storage in production apps
- Respect Audible's terms of service

## Error Handling

The package defines comprehensive error types:

```swift
public enum AAXConnectError: Error {
    case localeNotFound
    case invalidURL
    case networkError(Error)
    case registrationFailed(String)
    case decryptionFailed(String)
    case missingDeviceInfo
    case missingCustomerInfo
}
```

## Important: License Validation

**Always verify voucher validity before allowing file playback.** This library provides comprehensive voucher validation tools:

```swift
// Validate before playback
let result = try AAXConnectClient.validateVoucherFromFile(filePath: downloadInfoPath)
guard result.isValid else {
    throw PlaybackError.invalidLicense(result.message)
}

// Proceed with playback only if valid
playAudiobook(decryptionKey: result.key, iv: result.iv)
```

This ensures:
- ✅ Respect for Audible's licensing system
- ✅ Compliance with purchase terms
- ✅ Prevention of unauthorized access
- ✅ Proper handling of expired licenses

## License

This package is released under the MIT License. See LICENSE file for details.

**MIT License** - Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files, to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, subject to the conditions that the above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

**The software is provided "as is", without warranty of any kind. Use responsibly and in compliance with applicable terms of service.**