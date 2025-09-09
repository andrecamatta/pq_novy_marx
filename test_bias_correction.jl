# Simple test of survivorship bias correction functionality

using Dates, Statistics

include("src/VolatilityAnomalyAnalysis.jl")
using .VolatilityAnomalyAnalysis
using .VolatilityAnomalyAnalysis.PortfolioAnalysis
using .VolatilityAnomalyAnalysis.PortfolioAnalysis.HistoricalConstituents

println("🔬 TESTING SURVIVORSHIP BIAS CORRECTION")
println("=" ^ 60)

# Test 1: Historical constituent retrieval
println("\n1️⃣ Testing historical constituent functions...")

try
    test_dates = [Date(2000, 1, 1), Date(2008, 9, 1), Date(2020, 1, 1), Date(2024, 1, 1)]
    
    for test_date in test_dates
        constituents = HistoricalConstituents.get_historical_sp500_constituents(test_date)
        println("   $test_date: $(length(constituents)) constituents")
        
        # Check key companies
        has_google = any(ticker -> ticker in ["GOOGL", "GOOG"], constituents)
        has_meta = any(ticker -> ticker in ["FB", "META"], constituents)  
        has_tesla = "TSLA" in constituents
        has_lehman = "LEH" in constituents
        has_gm = "GM" in constituents
        
        println("      Google: $(has_google ? "✅" : "❌"), Meta: $(has_meta ? "✅" : "❌"), Tesla: $(has_tesla ? "✅" : "❌")")
        println("      Lehman: $(has_lehman ? "✅" : "❌"), GM: $(has_gm ? "✅" : "❌")")
    end
    
    println("   ✅ Historical constituent retrieval working")
    
catch e
    println("   ❌ Error testing constituents: $e")
    rethrow(e)
end

# Test 2: Point-in-time universe building  
println("\n2️⃣ Testing point-in-time universe building...")

try
    # Build small universe for testing
    universe = HistoricalConstituents.build_point_in_time_universe(
        Date(2020, 1, 1), 
        Date(2020, 6, 30)  # Just 6 months for testing
    )
    
    println("   ✅ Built universe for $(length(universe)) periods")
    
    # Show some examples
    first_date = minimum(keys(universe))
    last_date = maximum(keys(universe))
    
    println("   📊 First period ($(first_date)): $(length(universe[first_date])) constituents")
    println("   📊 Last period ($(last_date)): $(length(universe[last_date])) constituents")
    
catch e
    println("   ❌ Error building universe: $e")
    rethrow(e)
end

# Test 3: Mini analysis with bias correction
println("\n3️⃣ Testing bias-corrected analysis pipeline...")

try
    # Run very small analysis for testing
    results = PortfolioAnalysis.analyze_volatility_anomaly_with_bias_correction(
        Date(2020, 1, 1),
        Date(2020, 12, 31),  # Just 1 year for testing
        "Mini Test Analysis"
    )
    
    println("   ✅ Bias-corrected analysis completed")
    println("   📊 Generated $(length(results.long_short_returns)) monthly returns")
    println("   📊 Universe: $(results.metadata[:total_unique_tickers]) unique tickers")
    
    # Quick statistics
    if !isempty(results.long_short_returns)
        mean_ret = mean(results.long_short_returns) * 12 * 100  # Annualized %
        println("   📈 Mean annual return: $(round(mean_ret, digits=1))%")
    end
    
catch e
    println("   ❌ Error in bias-corrected analysis: $e")
    println("   📋 Error details: $(typeof(e))")
    
    # Show more detailed error info
    if isa(e, MethodError)
        println("   🔍 Method error - likely missing function or wrong arguments")
    elseif isa(e, LoadError) 
        println("   🔍 Load error - likely missing dependency")
    end
    
    # Try simple constituent test instead
    println("\n   🔄 Trying simpler constituent test...")
    try
        constituents_2020 = HistoricalConstituents.get_historical_sp500_constituents(Date(2020, 1, 1))
        println("   ✅ 2020 constituents: $(length(constituents_2020)) companies")
        
        # Show first 10
        println("   📋 Sample: $(join(constituents_2020[1:min(10, end)], ", "))")
        
    catch inner_e
        println("   ❌ Even simple constituent test failed: $inner_e")
    end
end

println("\n" * ("=" ^ 60))
println("🎯 BIAS CORRECTION TEST COMPLETE")

println("\n📝 NEXT STEPS:")
println("• If tests passed: Run full 2000-2024 analysis")
println("• If errors occurred: Check module dependencies")
println("• Compare results with original 58-month analysis")
println("• Document magnitude of survivorship bias impact")