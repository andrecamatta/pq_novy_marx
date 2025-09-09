# Unified volatility calculation module following DRY principle
# Single source of truth for all volatility metrics

module VolatilityCalculator

using DataFrames, Dates, Statistics
include("config.jl")
using .Config

export calculate_rolling_volatility, calculate_ticker_volatility, calculate_downside_volatility

"""
Calculate rolling volatility for all tickers with academic standards.
Consolidated from multiple duplicate implementations.

# Arguments
- `price_data::DataFrame`: Price data with columns [:ticker, :timestamp, :adjclose]
- `window::Int`: Rolling window size (default from config)
- `min_data_pct::Float64`: Minimum data availability percentage

# Returns
- `DataFrame`: Volatility data with columns [:ticker, :date, :volatility]
"""
function calculate_rolling_volatility(
    price_data::DataFrame;
    window::Int = VOLATILITY_CONFIG[:window],
    min_data_pct::Float64 = VOLATILITY_CONFIG[:min_data_pct],
    verbose::Bool = true
)
    verbose && println("📈 Calculating rolling volatility...")
    verbose && println("   Window: $window days, Min data: $(min_data_pct*100)%")
    
    vol_data = DataFrame(ticker=String[], date=Date[], volatility=Float64[])
    processed_tickers = 0
    
    for ticker_group in groupby(price_data, :ticker)
        ticker = ticker_group.ticker[1]
        n_obs = nrow(ticker_group)
        
        # Skip if insufficient data
        if n_obs < window + 30  # Buffer for robust calculation
            continue
        end
        
        # Sort by date to ensure proper time series
        sort!(ticker_group, :timestamp)
        
        # Calculate log returns with academic filters
        log_returns = calculate_filtered_returns(Vector(ticker_group.adjclose))
        
        # Rolling volatility calculation  
        ticker_vol_data = calculate_ticker_volatility(
            log_returns, Vector(ticker_group.timestamp), ticker, window, min_data_pct
        )
        
        if !isempty(ticker_vol_data)
            vol_data = vcat(vol_data, ticker_vol_data)
            processed_tickers += 1
        end
    end
    
    verbose && println("   ✅ Processed $processed_tickers tickers")
    return vol_data
end

"""
Calculate filtered log returns with academic standards.
Removes extreme outliers and handles missing data.
"""
function calculate_filtered_returns(prices::Vector{Float64})::Vector{Union{Missing, Float64}}
    # Academic return filtering
    threshold = VOLATILITY_CONFIG[:extreme_return_threshold]
    min_price = ACADEMIC_CONFIG[:min_price]
    
    log_returns = [missing for _ in 1:length(prices)]
    
    for i in 2:length(prices)
        if prices[i-1] >= min_price && prices[i] >= min_price
            ret = log(prices[i] / prices[i-1])
            # Filter extreme returns
            if abs(ret) <= threshold
                log_returns[i] = ret
            end
        end
    end
    
    return log_returns
end

"""
Calculate volatility for a single ticker with proper handling of missing data.
"""
function calculate_ticker_volatility(
    log_returns::Vector{Union{Missing, Float64}},
    timestamps::Vector{Date},
    ticker::String,
    window::Int,
    min_data_pct::Float64
)::DataFrame
    vol_data = DataFrame(ticker=String[], date=Date[], volatility=Float64[])
    n_obs = length(log_returns)
    min_valid_obs = round(Int, window * min_data_pct)
    
    for i in (window + 1):n_obs
        window_returns = log_returns[max(1, i-window+1):i]
        valid_returns = window_returns[.!ismissing.(window_returns)]
        
        if length(valid_returns) >= min_valid_obs
            vol = std(valid_returns) * sqrt(VOLATILITY_CONFIG[:annualization_factor])
            push!(vol_data, (ticker, timestamps[i], vol))
        end
    end
    
    return vol_data
end

"""
Calculate downside volatility (semi-variance) for risk-adjusted metrics.
Only considers returns below the mean.
"""
function calculate_downside_volatility(returns::Vector{Float64})::Float64
    if length(returns) < 2
        return 0.0
    end
    
    mean_return = mean(returns)
    downside_returns = [r for r in returns if r < mean_return]
    
    if length(downside_returns) < 2
        return 0.0
    end
    
    return sqrt(mean([(r - mean_return)^2 for r in downside_returns]))
end

"""
Calculate multiple volatility metrics for comprehensive analysis.
Returns a dictionary with different volatility measures.
"""
function calculate_volatility_metrics(returns::Vector{Float64})::Dict{Symbol, Float64}
    if length(returns) < 2
        return Dict{Symbol, Float64}()
    end
    
    metrics = Dict{Symbol, Float64}()
    metrics[:standard] = std(returns)
    metrics[:downside] = calculate_downside_volatility(returns)
    metrics[:range] = maximum(returns) - minimum(returns)
    
    # GARCH-like conditional volatility (simple approximation)
    abs_returns = abs.(returns .- mean(returns))
    metrics[:conditional] = mean(abs_returns) * sqrt(π/2)  # Convert MAD to std equivalent
    
    return metrics
end

end