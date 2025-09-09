# Test GitHub-based universe expansion

using Dates, Statistics

include("src/VolatilityAnomalyAnalysis.jl")
using .VolatilityAnomalyAnalysis
using .VolatilityAnomalyAnalysis.PortfolioAnalysis
using .VolatilityAnomalyAnalysis.PortfolioAnalysis.HistoricalConstituents

println("🧪 TESTING EXPANDED GITHUB-BASED UNIVERSE")
println("=" ^ 70)

# Test 1: Load GitHub data and check universe size
println("\n1️⃣ Testing GitHub S&P 500 data loading...")

try
    # Test historical constituent retrieval with new approach
    test_dates = [Date(2000, 1, 1), Date(2008, 9, 1), Date(2020, 1, 1), Date(2024, 1, 1)]
    
    println("   📅 Testing historical constituents:")
    for test_date in test_dates
        constituents = HistoricalConstituents.get_historical_sp500_constituents(test_date)
        println("      $test_date: $(length(constituents)) constituents")
        
        # Check for key companies
        has_google = any(ticker -> ticker in ["GOOGL", "GOOG"], constituents)
        has_meta = any(ticker -> ticker in ["FB", "META"], constituents)  
        has_tesla = "TSLA" in constituents
        has_lehman = "LEH" in constituents
        has_enron = "ENE" in constituents
        has_amazon = "AMZN" in constituents
        
        println("         📊 Key companies: Google:$(has_google ? "✅" : "❌") Meta:$(has_meta ? "✅" : "❌") Tesla:$(has_tesla ? "✅" : "❌") Lehman:$(has_lehman ? "✅" : "❌") Enron:$(has_enron ? "✅" : "❌") Amazon:$(has_amazon ? "✅" : "❌")")
    end
    
    println("   ✅ Historical constituent retrieval working with GitHub data")
    
catch e
    println("   ❌ Error testing GitHub constituents: $e")
    rethrow(e)
end

# Test 2: Build complete universe and validate expansion
println("\n2️⃣ Testing complete universe building...")

try
    # Build universe for validation period  
    universe = HistoricalConstituents.build_point_in_time_universe(
        Date(2000, 1, 1), 
        Date(2024, 12, 31)
    )
    
    # Calculate universe statistics
    all_tickers = Set{String}()
    for constituents in values(universe)
        union!(all_tickers, constituents)
    end
    
    total_unique_tickers = length(all_tickers)
    avg_constituents = round(mean(length(v) for v in values(universe)), digits=1)
    max_constituents = maximum(length(v) for v in values(universe))
    min_constituents = minimum(length(v) for v in values(universe))
    
    println("   📊 UNIVERSE STATISTICS:")
    println("      Total unique tickers: $total_unique_tickers")
    println("      Average constituents per month: $avg_constituents")
    println("      Max constituents: $max_constituents")
    println("      Min constituents: $min_constituents")
    println("      Total monthly snapshots: $(length(universe))")
    
    # Validation against expectation
    expected_range = 800:1200
    if total_unique_tickers in expected_range
        println("   ✅ VALIDATION PASSED: Universe size ($total_unique_tickers) in expected range ($expected_range)")
        validation_status = "PASSED"
    else
        println("   ⚠️ VALIDATION WARNING: Universe size ($total_unique_tickers) outside expected range ($expected_range)")
        validation_status = "NEEDS_REVIEW"
    end
    
    # Sample some tickers to verify diversity
    sample_tickers = collect(all_tickers)[1:min(20, length(all_tickers))]
    println("   📋 Sample tickers: $(join(sample_tickers, ", "))")
    
    # Check for known historical companies
    historical_companies = ["LEH", "ENE", "GM", "YHOO", "AOL", "BSC", "WB", "KM"]
    found_historical = [ticker for ticker in historical_companies if ticker in all_tickers]
    
    println("   🏛️ Historical companies found: $(join(found_historical, ", "))")
    println("   📈 Historical coverage: $(length(found_historical))/$(length(historical_companies)) ($(round(length(found_historical)/length(historical_companies)*100, digits=1))%)")
    
catch e
    println("   ❌ Error building complete universe: $e")
    rethrow(e)
end

# Test 3: Compare with old approach
println("\n3️⃣ Comparing with previous limited approach...")

try
    # Get stats from new approach
    new_stats = HistoricalConstituents.get_universe_stats()
    
    println("   📊 NEW GITHUB APPROACH:")
    println("      Total unique tickers: $(new_stats[:total_unique_tickers])")
    println("      Data source: $(new_stats[:data_source])")
    
    # Compare with old limited approach (estimated)
    old_estimated_tickers = 241  # From our previous Wikipedia-limited approach
    
    improvement_factor = round(new_stats[:total_unique_tickers] / old_estimated_tickers, digits=1)
    additional_tickers = new_stats[:total_unique_tickers] - old_estimated_tickers
    
    println("   📊 COMPARISON:")
    println("      Old approach (limited): ~$old_estimated_tickers tickers")
    println("      New approach (GitHub): $(new_stats[:total_unique_tickers]) tickers")
    println("      Improvement factor: $(improvement_factor)x")
    println("      Additional tickers: +$additional_tickers")
    
    if improvement_factor >= 2.0
        println("   🎯 MAJOR IMPROVEMENT: Universe expanded by $(improvement_factor)x")
        improvement_status = "MAJOR"
    elseif improvement_factor >= 1.5
        println("   ✅ GOOD IMPROVEMENT: Universe expanded by $(improvement_factor)x")
        improvement_status = "GOOD"  
    else
        println("   ⚠️ LIMITED IMPROVEMENT: Only $(improvement_factor)x expansion")
        improvement_status = "LIMITED"
    end
    
catch e
    println("   ❌ Error comparing approaches: $e")
end

# Test 4: Export for validation
println("\n4️⃣ Exporting universe for manual validation...")

try
    export_df = HistoricalConstituents.export_universe("github_sp500_universe_validation.csv")
    
    println("   ✅ Exported universe to CSV for validation")
    println("   📁 File: github_sp500_universe_validation.csv")
    println("   📊 Rows exported: $(nrow(export_df))")
    
    # Sample validation - show timeline for a known company
    sample_ticker = "AAPL"
    aapl_timeline = filter(row -> row.ticker == sample_ticker, export_df)
    
    if !isempty(aapl_timeline)
        first_date = minimum(aapl_timeline.date)
        last_date = maximum(aapl_timeline.date)
        total_months = length(aapl_timeline)
        
        println("   🍎 $sample_ticker timeline validation:")
        println("      First appearance: $first_date")  
        println("      Last appearance: $last_date")
        println("      Total months: $total_months")
    end
    
catch e
    println("   ❌ Error exporting universe: $e")
end

println("\n" * ("=" ^ 70))
println("🎯 GITHUB UNIVERSE VALIDATION COMPLETE")

# Final summary
println("\n📋 FINAL ASSESSMENT:")
if @isdefined(validation_status) && validation_status == "PASSED"
    println("✅ Universe size validation: PASSED")
else
    println("⚠️ Universe size validation: NEEDS REVIEW")  
end

if @isdefined(improvement_status) && improvement_status in ["MAJOR", "GOOD"]
    println("✅ Improvement over old approach: $(improvement_status)")
else
    println("⚠️ Improvement assessment: NEEDS REVIEW")
end

println("\n🚀 READY FOR FULL ANALYSIS:")
println("• Use expanded universe for bias-free volatility anomaly testing")
println("• Compare results with previous limited 241-ticker analysis")  
println("• Document impact of proper survivorship bias correction")
println("• Validate Novy-Marx critique with robust methodology")