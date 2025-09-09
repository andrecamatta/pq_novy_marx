# Unified data download module following DRY principle
# Single interface for all data download operations

module DataDownload

using YFinance, DataFrames, Dates, Printf
include("config.jl")
using .Config

export download_market_data, download_historical_prices, build_price_dataset

"""
Download market data for given tickers and date range with robust error handling.

# Arguments
- `tickers::Vector{String}`: List of ticker symbols
- `start_date::String`: Start date in "YYYY-MM-DD" format  
- `end_date::String`: End date in "YYYY-MM-DD" format
- `max_retries::Int`: Maximum retry attempts per ticker
- `verbose::Bool`: Print progress information

# Returns
- `DataFrame`: Combined price data with ticker column
- `Int`: Number of successful downloads

# Example
```julia
data, success_count = download_market_data(["AAPL", "MSFT"], "2020-01-01", "2023-12-31")
```
"""
function download_market_data(
    tickers::Vector{String}, 
    start_date::Union{String, Date}, 
    end_date::Union{String, Date};
    max_retries::Int = 2,
    verbose::Bool = true,
    min_data_days::Int = ACADEMIC_CONFIG[:min_market_days]
)
    # Convert dates if needed
    start_dt = start_date isa String ? Date(start_date) : start_date
    end_dt = end_date isa String ? Date(end_date) : end_date
    
    verbose && println("📥 Downloading market data...")
    verbose && println("   Period: $start_dt to $end_dt")
    verbose && println("   Tickers: $(length(tickers))")
    
    price_data = DataFrame()
    success_count = 0
    failed_tickers = String[]
    
    for (i, ticker) in enumerate(tickers)
        success = false
        
        # Retry logic for each ticker
        for attempt in 1:max_retries
            try
                data = get_prices(ticker, startdt=start_date, enddt=end_date)
                
                # Validate data quality
                if validate_ticker_data(data, ticker, min_data_days)
                    data[!, :ticker] = ticker
                    
                    if isempty(price_data)
                        price_data = data
                    else
                        price_data = vcat(price_data, data, cols=:union)
                    end
                    
                    success_count += 1
                    success = true
                    break  # Success, exit retry loop
                end
                
            catch e
                if attempt == max_retries
                    push!(failed_tickers, ticker)
                    verbose && @printf("   ❌ %s: %s\n", ticker, string(typeof(e)))
                end
                # Continue to next retry attempt
            end
        end
        
        # Progress reporting
        if verbose && (i % 25 == 0 || i == length(tickers))
            @printf("   Progress: %d/%d (✅ %d successful)\n", i, length(tickers), success_count)
        end
    end
    
    verbose && println("📊 Download complete: $success_count/$(length(tickers)) successful")
    
    if !isempty(failed_tickers) && verbose
        println("   ⚠️  Failed tickers: $(join(failed_tickers[1:min(10, end)], ", "))" * 
                (length(failed_tickers) > 10 ? "..." : ""))
    end
    
    return price_data, success_count
end

"""
Validate downloaded ticker data meets quality requirements.
"""
function validate_ticker_data(data::DataFrame, ticker::String, min_days::Int)::Bool
    if isempty(data) || nrow(data) < min_days
        return false
    end
    
    # Check for required columns
    required_cols = [:timestamp, :adjclose]
    if !all(col -> hasproperty(data, col), required_cols)
        return false
    end
    
    # Check for sufficient non-missing prices
    valid_prices = sum(.!ismissing.(data.adjclose))
    if valid_prices < min_days
        return false
    end
    
    # Apply academic price filter
    min_price = ACADEMIC_CONFIG[:min_price]
    valid_price_data = data[data.adjclose .>= min_price, :]
    if nrow(valid_price_data) < min_days * 0.8  # Allow 20% filtered out
        return false
    end
    
    return true
end

"""
Download data with automatic retry and fallback strategies.
"""
function download_with_retry(
    tickers::Vector{String},
    periods::Vector{Tuple{String, String, String}};
    verbose::Bool = true
)
    all_results = Dict{String, DataFrame}()
    
    for (period_name, start_date, end_date) in periods
        verbose && println("\n🗓️  Period: $period_name")
        
        data, success_count = download_market_data(
            tickers, start_date, end_date, 
            verbose=verbose
        )
        
        if success_count > 0
            all_results[period_name] = data
            verbose && println("   ✅ Saved $(nrow(data)) price records")
        else
            verbose && println("   ❌ No data successfully downloaded")
        end
    end
    
    return all_results
end

"""
Get standard universe of tickers based on configuration.
"""
function get_universe(universe_type::Symbol = :sp500_approximation)::Vector{String}
    return UNIVERSE_CONFIG[universe_type]
end

"""
Generate standard analysis periods.
"""
function get_analysis_periods()::Vector{Tuple{String, String, String}}
    return [
        ("2000-2009", "2000-01-01", "2009-12-31"),
        ("2010-2019", "2010-01-01", "2019-12-31"),
        ("2020-2024", "2020-01-01", "2024-11-30")
    ]
end

"""
Download historical prices using unified interface (replaces yfinance_integration.jl).
"""
function download_historical_prices(
    tickers::Vector{String},
    start_date::Date,
    end_date::Date;
    verbose::Bool = true
)
    return download_market_data(
        tickers, 
        string(start_date), 
        string(end_date),
        verbose=verbose
    )[1]  # Return only the DataFrame, not the count
end

"""
Build price dataset for bias-corrected analysis (consolidating functionality).
"""
function build_price_dataset(
    universe::Dict{Date, Vector{String}},
    start_date::Date = Date(2000, 1, 1),
    end_date::Date = Date(2024, 12, 31)
)
    println("🏗️ Building price dataset for bias-corrected analysis...")
    
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
    
    # Download real price data using unified interface
    return download_historical_prices(tickers_to_download, start_date, end_date)
end

end