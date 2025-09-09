# Test real YFinance data download with bias-corrected universe

using Dates, Statistics
using YFinance

include("src/VolatilityAnomalyAnalysis.jl")
using .VolatilityAnomalyAnalysis
using .VolatilityAnomalyAnalysis.PortfolioAnalysis
using .VolatilityAnomalyAnalysis.PortfolioAnalysis.HistoricalConstituents

println("📥 REAL YFINANCE DATA TEST - BIAS CORRECTED")
println("=" ^ 60)
println("Testing actual price download for volatility analysis")

# Test 1: Verify YFinance is working
println("\n1️⃣ Testing YFinance connectivity...")

try
    # Test with a simple, known ticker
    test_ticker = "AAPL"
    test_start = Date(2023, 1, 1)  
    test_end = Date(2023, 12, 31)
    
    println("   Testing download: $test_ticker from $test_start to $test_end")
    
    prices = get_prices(test_ticker, startdt=test_start, enddt=test_end)
    
    if !isempty(prices) && "AdjClose" in names(prices)
        println("   ✅ YFinance working: $(nrow(prices)) daily observations")
        println("   📊 Price range: \$$(round(minimum(prices.AdjClose), digits=2)) - \$$(round(maximum(prices.AdjClose), digits=2))")
    else
        println("   ❌ YFinance test failed: No data returned")
        exit(1)
    end
    
catch e
    println("   ❌ YFinance connectivity failed: $e")
    println("   🔧 Please check internet connection and YFinance.jl package")
    exit(1)
end

# Test 2: Get bias-corrected sample universe
println("\n2️⃣ Getting bias-corrected sample for analysis...")

# Get representative sample from different time periods
sample_dates = [Date(2000, 1, 1), Date(2010, 1, 1), Date(2020, 1, 1)]
sample_tickers = Set{String}()

for sample_date in sample_dates
    constituents = HistoricalConstituents.get_historical_sp500_constituents(sample_date)
    
    # Add first 10 from each period for variety
    for (i, ticker) in enumerate(constituents)
        if i <= 10
            push!(sample_tickers, ticker)
        end
    end
    
    println("   $sample_date: $(length(constituents)) constituents, sampled first 10")
end

sample_list = collect(sample_tickers)
println("   📊 Total unique tickers for testing: $(length(sample_list))")
println("   📋 Sample: $(join(sample_list[1:min(10, end)], ", "))")

# Test 3: Download real data for sample
println("\n3️⃣ Downloading real price data for sample...")

analysis_start = Date(2020, 1, 1)  # Recent period for faster download
analysis_end = Date(2023, 12, 31)

price_data = DataFrame(ticker=String[], timestamp=Date[], adjclose=Float64[])
successful_downloads = 0
failed_downloads = 0

# Limit to manageable sample for testing
test_tickers = sample_list[1:min(20, length(sample_list))]

for (i, ticker) in enumerate(test_tickers)
    try
        println("   Downloading $i/$(length(test_tickers)): $ticker")
        
        prices = get_prices(ticker, startdt=analysis_start, enddt=analysis_end)
        
        if !isempty(prices) && "AdjClose" in names(prices)
            ticker_data = DataFrame(
                ticker = fill(ticker, nrow(prices)),
                timestamp = prices.timestamp,
                adjclose = prices.AdjClose
            )
            
            # Filter missing values
            ticker_data = filter(row -> !ismissing(row.adjclose) && row.adjclose > 0, ticker_data)
            
            if nrow(ticker_data) >= 100  # At least some data
                price_data = vcat(price_data, ticker_data)
                successful_downloads += 1
                println("      ✅ Success: $(nrow(ticker_data)) observations")
            else
                println("      ⚠️ Insufficient data: $(nrow(ticker_data)) observations")
                failed_downloads += 1
            end
        else
            println("      ❌ No data returned")
            failed_downloads += 1
        end
        
        # Small delay to be nice to Yahoo servers
        sleep(0.5)
        
    catch e
        println("      ❌ Download failed: $e")
        failed_downloads += 1
    end
end

println("\n📊 DOWNLOAD RESULTS:")
println("   Successful downloads: $successful_downloads")
println("   Failed downloads: $failed_downloads")
println("   Total price observations: $(nrow(price_data))")
println("   Date range: $(minimum(price_data.timestamp)) to $(maximum(price_data.timestamp))")

# Test 4: Quick volatility calculation on real data
if nrow(price_data) > 1000  # Need reasonable amount of data
    println("\n4️⃣ Testing volatility calculation on REAL data...")
    
    # Calculate simple volatilities for available tickers
    volatilities = Dict{String, Float64}()
    
    for ticker in unique(price_data.ticker)
        ticker_prices = filter(row -> row.ticker == ticker, price_data)
        
        if nrow(ticker_prices) >= 100
            sort!(ticker_prices, :timestamp)
            returns = diff(log.(ticker_prices.adjclose))
            vol = std(returns) * sqrt(252)  # Annualized volatility
            volatilities[ticker] = vol
        end
    end
    
    if !isempty(volatilities)
        println("   ✅ Calculated volatilities for $(length(volatilities)) tickers")
        
        # Show results
        sorted_vols = sort(collect(volatilities), by=x->x[2])
        
        println("   📊 VOLATILITY RESULTS (Annualized):")
        println("      Lowest volatility:  $(sorted_vols[1][1]) = $(round(sorted_vols[1][2]*100, digits=1))%")
        println("      Median volatility:  $(sorted_vols[div(end,2)][1]) = $(round(sorted_vols[div(end,2)][2]*100, digits=1))%")
        println("      Highest volatility: $(sorted_vols[end][1]) = $(round(sorted_vols[end][2]*100, digits=1))%")
        
        # Simple low-vol vs high-vol test
        n_tickers = length(sorted_vols)
        low_vol_tickers = [sorted_vols[i][1] for i in 1:div(n_tickers, 3)]
        high_vol_tickers = [sorted_vols[i][1] for i in (2*div(n_tickers, 3)+1):n_tickers]
        
        println("   🔍 ANOMALY TEST PREVIEW:")
        println("      Low volatility group:  $(length(low_vol_tickers)) tickers")
        println("      High volatility group: $(length(high_vol_tickers)) tickers")
        println("      Low vol examples: $(join(low_vol_tickers[1:min(3, end)], ", "))")
        println("      High vol examples: $(join(high_vol_tickers[1:min(3, end)], ", "))")
        
        # Quick return comparison (very simplified)
        low_vol_returns = Float64[]
        high_vol_returns = Float64[]
        
        for ticker in low_vol_tickers
            ticker_prices = filter(row -> row.ticker == ticker, price_data)
            if nrow(ticker_prices) >= 50
                sort!(ticker_prices, :timestamp)
                total_return = log(ticker_prices.adjclose[end] / ticker_prices.adjclose[1])
                push!(low_vol_returns, total_return)
            end
        end
        
        for ticker in high_vol_tickers
            ticker_prices = filter(row -> row.ticker == ticker, price_data)
            if nrow(ticker_prices) >= 50
                sort!(ticker_prices, :timestamp)
                total_return = log(ticker_prices.adjclose[end] / ticker_prices.adjclose[1])
                push!(high_vol_returns, total_return)
            end
        end
        
        if !isempty(low_vol_returns) && !isempty(high_vol_returns)
            low_vol_mean = mean(low_vol_returns)
            high_vol_mean = mean(high_vol_returns)
            anomaly_direction = low_vol_mean > high_vol_mean ? "Low volatility wins" : "High volatility wins"
            anomaly_magnitude = abs(low_vol_mean - high_vol_mean)
            
            println("   🎯 SIMPLE ANOMALY TEST RESULT:")
            println("      Low vol mean return:  $(round(low_vol_mean*100, digits=1))%")
            println("      High vol mean return: $(round(high_vol_mean*100, digits=1))%")
            println("      Direction: $anomaly_direction")
            println("      Magnitude: $(round(anomaly_magnitude*100, digits=1))% difference")
            
            if anomaly_direction == "High volatility wins"
                println("      📚 Literature alignment: ✅ CONSISTENT (post-2000 high-vol outperformance)")
            else
                println("      📚 Literature alignment: ⚠️ INCONSISTENT (expected high-vol outperformance)")
            end
        end
        
    else
        println("   ❌ Could not calculate volatilities")
    end
else
    println("\n4️⃣ Skipping volatility test - insufficient data")
end

println("\n" * ("=" ^ 60))
println("📥 REAL YFINANCE DATA TEST COMPLETE")

# Summary
if successful_downloads > 0
    println("\n🎯 SUCCESS: Real YFinance data integration working")
    println("✅ Downloaded $(nrow(price_data)) real price observations")
    println("✅ Bias-corrected universe providing representative sample")
    println("✅ Ready for full volatility anomaly analysis with real data")
    println("\n🚀 NEXT STEP: Run complete analysis with expanded ticker universe")
else
    println("\n❌ FAILED: YFinance integration not working")
    println("🔧 Check internet connection and YFinance.jl package installation")
end