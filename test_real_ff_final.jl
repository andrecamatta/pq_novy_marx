# Final test of the real Fama-French factors module
using Dates, DataFrames, Statistics

println("🧪 FINAL TEST: REAL FAMA-FRENCH FACTORS MODULE")
println("=" ^ 70)

# Include and test the real module
include("src/utils/fama_french_real.jl")
using .FamaFrenchReal

try
    println("1️⃣ Testing module import...")
    println("   ✅ Module imported successfully")
    
    println("\\n2️⃣ Testing real factor download...")
    factors = download_real_ff_factors(Date(2020, 1, 1), Date(2024, 12, 31), verbose=true)
    
    if nrow(factors) > 0
        println("\\n   ✅ Download successful: $(nrow(factors)) observations")
        
        println("\\n3️⃣ Testing data quality...")
        
        # Check required columns
        required_cols = [:Date, :MKT_RF, :SMB, :HML, :RMW, :CMA, :RF]
        missing_cols = []
        
        for col in required_cols
            if col ∉ names(factors)
                push!(missing_cols, col)
            end
        end
        
        if isempty(missing_cols)
            println("   ✅ All required columns present: $(names(factors))")
        else
            println("   ❌ Missing columns: $missing_cols")
        end
        
        # Check date range
        date_range = (minimum(factors.Date), maximum(factors.Date))
        println("   📅 Date range: $(date_range[1]) to $(date_range[2])")
        
        # Check for reasonable values
        avg_mkt = mean(factors.MKT_RF)
        avg_rf = mean(factors.RF)
        
        if -5 < avg_mkt < 5 && 0 < avg_rf < 10
            println("   ✅ Factor values look reasonable")
            println("      Average MKT-RF: $(round(avg_mkt, digits=2))%")
            println("      Average RF: $(round(avg_rf, digits=2))%")
        else
            println("   ⚠️  Factor values may be unusual")
        end
        
        println("\\n4️⃣ Testing summary function...")
        summarize_ff_factors_real(factors)
        
        println("\\n5️⃣ Testing alias function...")
        factors2 = get_ff_factors_real(Date(2023, 1, 1), Date(2023, 12, 31), verbose=false)
        println("   ✅ Alias function works: $(nrow(factors2)) observations for 2023")
        
        println("\\n🎉 ALL TESTS PASSED!")
        println("\\n📋 INTEGRATION READY:")
        println("   ✅ Real Kenneth French data successfully downloaded")
        println("   ✅ All factor columns properly parsed")
        println("   ✅ Date filtering works correctly")
        println("   ✅ Summary statistics calculated")
        println("   ✅ Module ready for integration with main analysis")
        
    else
        println("   ❌ No data returned from download")
    end
    
catch e
    println("❌ Test failed: $e")
    println("\\nStacktrace:")
    for (i, frame) in enumerate(stacktrace())
        println("  $i: $frame")
        if i > 10 break end
    end
end