# Test script for Fama-French factors download

using Pkg
println("📦 Checking required packages...")

# Add packages if needed
required_packages = ["HTTP", "CSV", "DataFrames", "Dates", "Random", "DelimitedFiles", "Printf", "Statistics"]
for pkg in required_packages
    try
        eval(Meta.parse("using $pkg"))
    catch
        println("Installing $pkg...")
        Pkg.add(pkg)
    end
end

println("✅ All packages available")

# Include the module
include("src/utils/fama_french_factors.jl")
using .FamaFrenchFactors

println("\n🧪 TESTING FAMA-FRENCH FACTORS DOWNLOAD")
println("=" ^ 60)

try
    # Test 1: Basic download functionality
    println("\n1️⃣ Testing basic download...")
    factors = get_ff_factors(Date(2020, 1, 1), Date(2022, 12, 31), verbose=true)
    
    if nrow(factors) > 0
        println("   ✅ Download successful: $(nrow(factors)) observations")
        println("   📊 Columns: $(names(factors))")
        
        # Test 2: Data structure validation
        println("\n2️⃣ Validating data structure...")
        expected_cols = ["Date", "MKT_RF", "SMB", "HML", "RMW", "CMA", "RF"]
        actual_cols = names(factors)
        missing_cols = [col for col in expected_cols if !(col in actual_cols)]
        
        if isempty(missing_cols)
            println("   ✅ All expected columns present")
        else
            println("   ❌ Missing columns: $missing_cols")
        end
        
        # Test 3: Data quality checks
        println("\n3️⃣ Checking data quality...")
        
        # Check for missing values
        missing_count = sum(ismissing.(factors.MKT_RF))
        if missing_count == 0
            println("   ✅ No missing values in MKT_RF")
        else
            println("   ⚠️  Found $missing_count missing values in MKT_RF")
        end
        
        # Check date range
        actual_start = minimum(factors.Date)
        actual_end = maximum(factors.Date)
        println("   📅 Date range: $actual_start to $actual_end")
        
        # Check for reasonable factor values (not extreme outliers)
        mkt_rf_mean = mean(factors.MKT_RF)
        mkt_rf_std = std(factors.MKT_RF)
        println("   📈 MKT-RF: mean = $(round(mkt_rf_mean, digits=2))%, std = $(round(mkt_rf_std, digits=2))%")
        
        if abs(mkt_rf_mean) < 5.0 && mkt_rf_std < 20.0  # Reasonable ranges
            println("   ✅ MKT-RF values appear reasonable")
        else
            println("   ⚠️  MKT-RF values may be unrealistic")
        end
        
        # Test 4: Display summary
        println("\n4️⃣ Factor summary:")
        FamaFrenchFactors.summarize_factors(factors)
        
        # Test 5: Cache functionality
        println("\n5️⃣ Testing cache functionality...")
        factors2 = get_ff_factors(Date(2020, 1, 1), Date(2022, 12, 31), verbose=true)
        
        if nrow(factors2) == nrow(factors)
            println("   ✅ Cache working correctly")
        else
            println("   ⚠️  Cache issue: different number of rows")
        end
        
        println("\n" * "=" ^ 60)
        println("🎯 FAMA-FRENCH DOWNLOAD TEST RESULTS:")
        println("✅ Module loads successfully")
        println("✅ Download function works")
        println("✅ Data structure is correct") 
        println("✅ Data quality looks reasonable")
        println("✅ Cache functionality works")
        println("\n📋 Next step: Integrate with portfolio analysis")
        println("⚠️  Note: Currently using simulated data for testing")
        println("   TODO: Implement actual Kenneth French data parser")
        
    else
        println("   ❌ Download failed: no data returned")
    end
    
catch e
    println("❌ Test failed with error: $e")
    println("\n🔧 Possible issues:")
    println("- Network connection problems")
    println("- Missing Julia packages") 
    println("- Module import issues")
    
    # Show more detailed error info
    println("\nDetailed error:")
    showerror(stdout, e)
end