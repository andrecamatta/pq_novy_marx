# Simple YFinance connectivity test

using YFinance, Dates

println("🔍 Testing YFinance basic connectivity...")

try
    # Try a very simple request with a longer timeout
    println("Attempting to download MSFT data...")
    
    # Try with a more recent period to avoid potential data issues
    test_start = Date(2024, 1, 1)
    test_end = Date(2024, 3, 31)
    
    prices = get_prices("MSFT", startdt=test_start, enddt=test_end)
    
    if !isempty(prices)
        println("✅ Success! Downloaded $(nrow(prices)) observations")
        println("Columns: $(names(prices))")
        if "AdjClose" in names(prices)
            println("AdjClose range: $(minimum(prices.AdjClose)) - $(maximum(prices.AdjClose))")
        end
    else
        println("❌ No data returned")
    end
    
catch e
    println("❌ Error: $e")
    
    if contains(string(e), "TimeoutException")
        println("🌐 Network timeout issue detected")
        println("💡 Possible solutions:")
        println("   - Check internet connection")
        println("   - Try VPN if corporate firewall blocks Yahoo Finance")
        println("   - Consider using cached data or alternative data source")
    end
end

println("\n🔍 Checking if we can access Yahoo Finance URLs...")
try
    using HTTP
    response = HTTP.get("https://finance.yahoo.com", timeout=10)
    println("✅ Can access Yahoo Finance homepage (status: $(response.status))")
catch e
    println("❌ Cannot access Yahoo Finance: $e")
end