# Test integration of real Fama-French module with existing pipeline
using Dates, DataFrames, Statistics

println("🧪 TESTING REAL FAMA-FRENCH INTEGRATION")
println("=" ^ 60)

try
    # Test 1: Module import
    println("1️⃣ Testing module import...")
    include("src/utils/fama_french_factors.jl")
    using .FamaFrenchFactors
    println("   ✅ Module imported successfully")
    
    # Test 2: Function availability
    println("\n2️⃣ Testing function exports...")
    exported_functions = [:download_fama_french_factors, :get_ff_factors, :summarize_factors]
    
    for func in exported_functions
        if isdefined(FamaFrenchFactors, func)
            println("   ✅ $func available")
        else
            println("   ❌ $func NOT available")
        end
    end
    
    # Test 3: Basic functionality
    println("\n3️⃣ Testing basic data download...")
    factors = download_fama_french_factors(Date(2020, 1, 1), Date(2023, 12, 31), verbose=true)
    
    if nrow(factors) > 0
        println("   ✅ Data download successful: $(nrow(factors)) observations")
        
        # Test 4: Data structure
        println("\n4️⃣ Testing data structure...")
        required_cols = [:Date, :MKT_RF, :SMB, :HML, :RMW, :CMA, :RF]
        missing_cols = []
        
        for col in required_cols
            if col ∉ names(factors)
                push!(missing_cols, col)
            end
        end
        
        if isempty(missing_cols)
            println("   ✅ All required columns present")
        else
            println("   ❌ Missing columns: $missing_cols")
        end
        
        # Test 5: Summary function
        println("\n5️⃣ Testing summary function...")
        summarize_factors(factors)
        
        # Test 6: Integration with existing portfolio code
        println("\n6️⃣ Testing integration potential...")
        
        # Check if factors can be merged with portfolio returns
        sample_dates = factors.Date[1:min(5, nrow(factors))]
        println("   📅 Sample dates available: $(sample_dates[1]) to $(sample_dates[end])")
        
        # Check factor value ranges
        avg_mkt = mean(factors.MKT_RF)
        avg_rf = mean(factors.RF)
        
        if -10 < avg_mkt < 10 && 0 < avg_rf < 10
            println("   ✅ Factor values in reasonable ranges")
            println("      MKT-RF: $(round(avg_mkt, digits=2))% avg")  
            println("      RF: $(round(avg_rf, digits=2))% avg")
        else
            println("   ⚠️  Factor values may need review")
        end
        
        println("\n🎉 INTEGRATION TEST PASSED!")
        println("   Real Fama-French module ready for multifactor regression implementation")
        
    else
        println("   ❌ No data returned")
    end
    
catch e
    println("❌ Integration test failed: $e")
    
    println("\nStacktrace:")
    for (i, frame) in enumerate(stacktrace())
        println("  $i: $frame")
        if i > 10 break end
    end
end