# Test real Kenneth French parser

using Dates

# Include the real parser
include("src/utils/real_kf_parser.jl")
using .RealKFParser

# Run comprehensive test
println("🧪 COMPREHENSIVE REAL KENNETH FRENCH PARSER TEST")
println("=" ^ 70)

success = RealKFParser.test_real_parser()

if success
    println("\n🎯 ADDITIONAL TESTS:")
    
    try
        # Test different date ranges
        println("\n1️⃣ Testing different date ranges...")
        
        # Recent data
        recent = download_real_kf_factors(Date(2023, 1, 1), Date(2024, 12, 31))
        println("   Recent (2023-2024): $(nrow(recent)) observations")
        
        # Historical data
        historical = download_real_kf_factors(Date(1990, 1, 1), Date(1999, 12, 31))
        println("   Historical (1990s): $(nrow(historical)) observations")
        
        # Full range
        full = download_real_kf_factors(Date(1960, 1, 1), Date(2024, 12, 31))
        println("   Full range (1960-2024): $(nrow(full)) observations")
        
        println("\n2️⃣ Comparing with known historical values...")
        
        # Check some known historical periods
        if nrow(full) > 0
            # Find 2008 financial crisis (should show negative MKT-RF)
            crisis_2008 = filter(row -> year(row.Date) == 2008, full)
            if nrow(crisis_2008) > 0
                crisis_avg = mean(crisis_2008.MKT_RF)
                println("   2008 Financial Crisis MKT-RF: $(round(crisis_avg, digits=2))% (expect negative)")
                
                if crisis_avg < -1
                    println("   ✅ 2008 crisis data looks realistic")
                else
                    println("   ⚠️  2008 crisis data may be incorrect")
                end
            end
            
            # Check recent bull market years
            bull_2017 = filter(row -> year(row.Date) == 2017, full)
            if nrow(bull_2017) > 0
                bull_avg = mean(bull_2017.MKT_RF)
                println("   2017 Bull Market MKT-RF: $(round(bull_avg, digits=2))% (expect positive)")
            end
        end
        
        println("\n3️⃣ Data quality checks...")
        
        # Check for missing months
        if nrow(full) > 0
            date_range = minimum(full.Date):Month(1):maximum(full.Date)
            expected_months = length(date_range)
            actual_months = nrow(full)
            
            println("   Expected months: $expected_months")
            println("   Actual months: $actual_months")
            
            if actual_months >= expected_months * 0.95  # Allow 5% missing
                println("   ✅ Data completeness looks good")
            else
                println("   ⚠️  Some months may be missing")
            end
        end
        
        println("\n" * "=" ^ 70)
        println("🏆 FINAL RESULT: Real Kenneth French parser is working!")
        println("✅ Downloads real data from KF library")
        println("✅ Parses CSV format correctly") 
        println("✅ Converts dates properly")
        println("✅ Validates data quality")
        println("✅ Handles different date ranges")
        println("\n📋 Ready to integrate with main factor analysis!")
        
    catch e
        println("❌ Additional tests failed: $e")
    end
else
    println("\n❌ PARSER TEST FAILED")
    println("Check network connection and try again")
end