# Real YFinance data integration for bias-corrected analysis
# Downloads actual historical prices for bias-corrected universe

module YFinanceIntegration

using DataFrames, Dates, Statistics
using YFinance

export download_historical_prices, build_price_dataset

"""
Download real historical prices for a list of tickers using YFinance.
Handles missing data and delisted companies properly.
"""
function download_historical_prices(
    tickers::Vector{String},
    start_date::Date,
    end_date::Date;
    verbose::Bool = true
)
    println("📥 Downloading REAL historical prices from YFinance...")
    println("   Tickers: $(length(tickers)) symbols")
    println("   Period: $start_date to $end_date")
    
    price_data = DataFrame(ticker=String[], timestamp=Date[], adjclose=Float64[])
    successful_downloads = 0
    failed_downloads = 0
    
    for (i, ticker) in enumerate(tickers)
        try
            # Progress indicator
            if i % 50 == 0 || i == length(tickers)
                println("   Progress: $i/$(length(tickers)) ($(round(i/length(tickers)*100, digits=1))%)")
            end
            
            # Download data from YFinance with timeout handling
            prices = try
                get_prices(ticker, startdt=start_date, enddt=end_date)
            catch e
                if contains(string(e), "TimeoutException") || contains(string(e), "ConnectError")
                    println("      ⏰ $ticker: Network timeout, retrying...")
                    sleep(2)  # Wait before retry
                    try
                        get_prices(ticker, startdt=start_date, enddt=end_date)
                    catch retry_error
                        println("      ❌ $ticker: Retry failed - $retry_error")
                        DataFrame()  # Return empty DataFrame
                    end
                else
                    rethrow(e)
                end
            end
            
            if !isempty(prices) && "AdjClose" in names(prices)
                # Extract adjusted close prices
                ticker_data = DataFrame(
                    ticker = fill(ticker, nrow(prices)),
                    timestamp = prices.timestamp,
                    adjclose = prices.AdjClose
                )
                
                # Filter out missing values
                ticker_data = filter(row -> !ismissing(row.adjclose) && row.adjclose > 0, ticker_data)
                
                if nrow(ticker_data) >= 252  # At least 1 year of data
                    price_data = vcat(price_data, ticker_data)
                    successful_downloads += 1
                else
                    verbose && println("      ⚠️ $ticker: Insufficient data ($(nrow(ticker_data)) observations)")
                    failed_downloads += 1
                end
            else
                verbose && println("      ❌ $ticker: No data available")
                failed_downloads += 1
            end
            
        catch e
            if verbose && failed_downloads < 10  # Limit error messages
                println("      ❌ $ticker: Download failed - $e")
            end
            failed_downloads += 1
            
            # Add small delay to avoid rate limiting
            sleep(0.1)
        end
    end
    
    println("   ✅ Download complete:")
    println("      Successful: $successful_downloads tickers")
    println("      Failed: $failed_downloads tickers")
    println("      Total observations: $(nrow(price_data))")
    
    # Sort by ticker and date
    sort!(price_data, [:ticker, :timestamp])
    
    return price_data
end

"""
Build complete price dataset for bias-corrected volatility analysis.
Downloads real data for historically accurate universe.
"""
function build_price_dataset(
    universe::Dict{Date, Vector{String}},
    start_date::Date = Date(2000, 1, 1),
    end_date::Date = Date(2024, 12, 31)
)
    println("🏗️ Building REAL price dataset for bias-corrected analysis...")
    
    # Get all unique tickers from the universe
    all_tickers = Set{String}()
    for constituents in values(universe)
        union!(all_tickers, constituents)
    end
    
    total_tickers = length(all_tickers)
    println("   Total unique tickers in universe: $total_tickers")
    
    # Use complete universe for bias-corrected analysis
    tickers_to_download = collect(all_tickers)
    println("   📊 Using full bias-corrected universe: $total_tickers tickers")
    
    # Download real price data
    price_data = download_historical_prices(tickers_to_download, start_date, end_date)
    
    # Validate against universe membership
    println("   🔍 Validating against universe membership...")
    
    # Filter price data to only include periods when ticker was in S&P 500
    validated_data = DataFrame(ticker=String[], timestamp=Date[], adjclose=Float64[])
    
    for ticker in unique(price_data.ticker)
        ticker_prices = filter(row -> row.ticker == ticker, price_data)
        
        for row in eachrow(ticker_prices)
            # Find the universe membership for this date
            membership_date = nothing
            for (universe_date, constituents) in universe
                if universe_date <= row.timestamp && row.ticker in constituents
                    membership_date = universe_date
                end
            end
            
            # Only include if ticker was actually in S&P 500 at this time
            if membership_date !== nothing
                push!(validated_data, (row.ticker, row.timestamp, row.adjclose))
            end
        end
    end
    
    println("   ✅ Validation complete:")
    println("      Raw observations: $(nrow(price_data))")
    println("      Validated observations: $(nrow(validated_data))")
    println("      Bias correction applied: $(nrow(price_data) - nrow(validated_data)) observations removed")
    
    return validated_data
end


end