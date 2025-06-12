#!/bin/bash

echo "🎧 AAXConnectSwift Authentication Generator"
echo "========================================"
echo "This will generate fresh auth data in two steps:"
echo "1. Generate login URL"
echo "2. Process redirect URL and save auth"
echo ""

# Ask for locale in bash
echo "🌍 Select your AAXC marketplace:"
echo "1. 🇺🇸 United States (us)"
echo "2. 🇨🇦 Canada (ca)"
echo "3. 🇬🇧 United Kingdom (uk)"
echo "4. 🇩🇪 Germany (de)"
echo "5. 🇫🇷 France (fr)"
echo "6. 🇮🇹 Italy (it)"
echo "7. 🇪🇸 Spain (es)"
echo "8. 🇦🇺 Australia (au)"
echo "9. 🇯🇵 Japan (jp)"
echo ""
echo -n "Enter choice (1-9) or country code: "
read choice

# Convert to lowercase
choice_lower=$(echo "$choice" | tr '[:upper:]' '[:lower:]')

case "$choice_lower" in
    1) COUNTRY_CODE="us" ;;
    2) COUNTRY_CODE="ca" ;;
    3) COUNTRY_CODE="uk" ;;
    4) COUNTRY_CODE="de" ;;
    5) COUNTRY_CODE="fr" ;;
    6) COUNTRY_CODE="it" ;;
    7) COUNTRY_CODE="es" ;;
    8) COUNTRY_CODE="au" ;;
    9) COUNTRY_CODE="jp" ;;
    *) COUNTRY_CODE="$choice_lower" ;;
esac

# Convert to uppercase for display
COUNTRY_UPPER=$(echo "$COUNTRY_CODE" | tr '[:lower:]' '[:upper:]')

# Step 1: Generate auth request
echo ""
echo "📱 STEP 1: Generating authentication request for $COUNTRY_UPPER..."
AAXC_COUNTRY_CODE="${COUNTRY_CODE}" swift test --filter IntegrationTests.testGenerateAuthRequest

# Check if login URL was created
if [ ! -f "./Tests/Bindings/aaxc_login_url.txt" ]; then
    echo "❌ Login URL not generated. Please check for errors above."
    exit 1
fi

echo ""
echo "📋 STEP 2: Complete login in browser"
echo "====================================="
echo "Your login URL:"
cat ./Tests/Bindings/aaxc_login_url.txt
echo ""
echo ""
echo "Commands to open/copy the URL:"
echo "   # Open in browser:"
echo "   open \"\$(cat ./Tests/Bindings/aaxc_login_url.txt)\""
echo ""
echo "   # Copy to clipboard:"
echo "   cat ./Tests/Bindings/aaxc_login_url.txt | pbcopy"
echo ""
echo "After login, Amazon will redirect to a long URL."
echo "Save the COMPLETE redirect URL to: ./Tests/Bindings/aaxc_redirect_url.txt"
echo ""
echo "You can use:"
echo "   echo 'PASTE_FULL_REDIRECT_URL_HERE' > ./Tests/Bindings/aaxc_redirect_url.txt"
echo ""
echo "Press ENTER when you've saved the redirect URL to ./Tests/Bindings/aaxc_redirect_url.txt..."
read

# Check if redirect URL was saved
if [ ! -f "./Tests/Bindings/aaxc_redirect_url.txt" ]; then
    echo "❌ Redirect URL file not found. Please save it and run again."
    exit 1
fi

if [ ! -s "./Tests/Bindings/aaxc_redirect_url.txt" ]; then
    echo "❌ Redirect URL file is empty. Please save the complete URL and run again."
    exit 1
fi

echo ""
echo "🔐 STEP 3: Processing authentication..."
swift test --filter IntegrationTests.testCompleteAuth

echo ""
echo "🎉 Authentication generation complete!"
echo "======================================"
echo "Check above for results. If successful:"
echo "• New auth saved to: ./Tests/Bindings/aaxcAuth.json"
echo "• Library should be listed"
echo ""
echo "🧪 Run tests with new auth:"
echo "   swift test"
echo ""
echo "🗑️  Cleanup:"
echo "   rm ./Tests/Bindings/aaxc_login_url.txt ./Tests/Bindings/aaxc_redirect_url.txt"