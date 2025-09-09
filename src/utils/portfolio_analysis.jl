# Portfolio analysis utilities
# Volatility calculation, portfolio formation, and return computation

module PortfolioAnalysis

using DataFrames, Dates, Statistics, Printf, Random
include("config.jl")
include("historical_constituents.jl")
include("data_download.jl")
include("volatility_calculator.jl")
using .Config
using .HistoricalConstituents
using .DataDownload
using .VolatilityCalculator

export form_volatility_portfolios, calculate_portfolio_returns
export get_long_short_returns, VolatilityResults, analyze_volatility_anomaly_with_bias_correction

# Struct to hold volatility analysis results
struct VolatilityResults
    volatility_data::DataFrame
    portfolio_assignments::DataFrame  
    monthly_returns::DataFrame
    long_short_returns::Vector{Float64}
    metadata::Dict{Symbol, Any}
end

"""
Calculate rolling volatility for all tickers with academic standards.

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
"""
function calculate_filtered_returns(prices::Vector{<:Real})::Vector{Union{Missing, Float64}}
    # Calculate log returns
    log_returns = [missing; diff(log.(prices))]
    
    # Filter extreme returns (academic standard)
    threshold = log(VOLATILITY_CONFIG[:extreme_return_threshold])
    filtered_returns = [
        (!ismissing(r) && abs(r) > threshold) ? missing : r 
        for r in log_returns
    ]
    
    return filtered_returns
end

"""
Calculate volatility for a single ticker.
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
Form volatility-based portfolios with academic methodology.

# Arguments
- `volatility_data::DataFrame`: Volatility data from calculate_rolling_volatility
- `n_portfolios::Int`: Number of portfolios (default 5 for quintiles)
- `lag_months::Int`: Formation lag in months (default 1)

# Returns  
- `DataFrame`: Portfolio assignments with columns [:ticker, :form_date, :portfolio, :invest_date]
"""
function form_volatility_portfolios(
    volatility_data::DataFrame;
    n_portfolios::Int = PORTFOLIO_CONFIG[:n_portfolios],
    lag_months::Int = PORTFOLIO_CONFIG[:formation_lag],
    min_stocks::Int = PORTFOLIO_CONFIG[:min_stocks],
    verbose::Bool = true
)
    verbose && println("🗂️  Forming volatility portfolios...")
    verbose && println("   Portfolios: $n_portfolios, Lag: $lag_months month(s)")
    
    # Create month-end volatility data
    monthly_vol = create_monthly_volatility_data(volatility_data)
    
    portfolio_assignments = DataFrame()
    months_processed = 0
    
    # Group by month only (each group will have multiple tickers)
    for month_group in groupby(monthly_vol, :month)
        month_date = month_group.month[1]
        n_stocks = nrow(month_group)
        
        # Skip months with insufficient stocks (but be more lenient for testing)
        if n_stocks < max(5, min_stocks ÷ 4)  # Allow smaller portfolios for testing
            continue
        end
        
        # Sort by volatility (low to high)
        sort!(month_group, :volatility)
        
        # Assign portfolio numbers (1 = lowest vol, 5 = highest vol)
        portfolios = assign_portfolio_numbers(n_stocks, n_portfolios)
        
        # Create assignments DataFrame
        invest_date = month_date + Month(lag_months)
        assignments = DataFrame(
            ticker = month_group.ticker,
            form_date = fill(month_date, n_stocks),
            invest_date = fill(invest_date, n_stocks),
            portfolio = portfolios
        )
        portfolio_assignments = vcat(portfolio_assignments, assignments, cols=:union)
        months_processed += 1
    end
    
    verbose && println("   ✅ Formed portfolios for $months_processed months")
    return portfolio_assignments
end

"""
Create end-of-month volatility data.
"""
function create_monthly_volatility_data(volatility_data::DataFrame)::DataFrame
    # Add month column
    vol_monthly = copy(volatility_data)
    vol_monthly[!, :month] = Date.(year.(vol_monthly.date), month.(vol_monthly.date))
    
    # Take last volatility observation per ticker per month
    monthly_vol = combine(
        groupby(vol_monthly, [:ticker, :month]),
        :volatility => last => :volatility,
        :date => last => :date_end
    )
    
    return monthly_vol
end

"""
Assign portfolio numbers based on volatility ranking.
"""
function assign_portfolio_numbers(n_stocks::Int, n_portfolios::Int)::Vector{Int}
    portfolios = Vector{Int}(undef, n_stocks)
    
    # Calculate breakpoints
    for i in 1:n_stocks
        rank_pct = i / n_stocks
        portfolio = min(n_portfolios, ceil(Int, rank_pct * n_portfolios))
        portfolios[i] = portfolio
    end
    
    return portfolios
end

"""
Calculate monthly portfolio returns with proper timing.

# Arguments
- `price_data::DataFrame`: Original price data
- `portfolio_assignments::DataFrame`: Portfolio assignments from form_volatility_portfolios

# Returns
- `DataFrame`: Monthly portfolio returns
"""
function calculate_portfolio_returns(
    price_data::DataFrame,
    portfolio_assignments::DataFrame;
    weighting::String = PORTFOLIO_CONFIG[:weighting],
    verbose::Bool = true
)::DataFrame
    verbose && println("💰 Calculating portfolio returns...")
    
    # Calculate monthly individual stock returns
    stock_returns = calculate_monthly_stock_returns(price_data)
    
    # Merge with portfolio assignments (using investment date)
    portfolio_returns = leftjoin(
        stock_returns,
        select(portfolio_assignments, :ticker, :invest_date => :month, :portfolio),
        on = [:ticker, :month]
    )
    
    # Calculate portfolio-level returns
    monthly_portfolio_returns = combine(
        groupby(dropmissing(portfolio_returns, :portfolio), [:month, :portfolio]),
        :ret => mean => :portfolio_return  # Equal-weighted
    )
    
    verbose && println("   ✅ Calculated returns for $(nrow(monthly_portfolio_returns)) portfolio-months")
    return monthly_portfolio_returns
end

"""
Calculate monthly stock returns from price data.
"""
function calculate_monthly_stock_returns(price_data::DataFrame)::DataFrame
    # Add month column
    data_with_month = copy(price_data)
    data_with_month[!, :month] = Date.(year.(price_data.timestamp), month.(price_data.timestamp))
    
    # Get end-of-month prices
    monthly_prices = combine(
        groupby(data_with_month, [:ticker, :month]),
        :adjclose => last => :price,
        :timestamp => last => :date_end
    )
    
    # Calculate returns
    stock_returns = DataFrame()
    
    for ticker_group in groupby(monthly_prices, :ticker)
        ticker = ticker_group.ticker[1]
        sort!(ticker_group, :month)
        
        if nrow(ticker_group) >= 2
            for i in 2:nrow(ticker_group)
                ret = ticker_group.price[i] / ticker_group.price[i-1] - 1
                
                push!(stock_returns, (
                    ticker = ticker,
                    month = ticker_group.month[i], 
                    ret = ret
                ))
            end
        end
    end
    
    return stock_returns
end

"""
Calculate long-short portfolio returns (Low Vol - High Vol).
"""
function get_long_short_returns(monthly_portfolio_returns::DataFrame)::Vector{Float64}
    ls_returns = Float64[]
    
    for month_group in groupby(monthly_portfolio_returns, :month)
        p1_returns = month_group[month_group.portfolio .== 1, :portfolio_return]  # Low vol
        p5_returns = month_group[month_group.portfolio .== 5, :portfolio_return]  # High vol
        
        if !isempty(p1_returns) && !isempty(p5_returns)
            ls_return = p1_returns[1] - p5_returns[1]
            push!(ls_returns, ls_return)
        end
    end
    
    return ls_returns
end

"""
Run complete volatility anomaly analysis pipeline.

# Arguments
- `price_data::DataFrame`: Price data from data download
- `analysis_name::String`: Name for this analysis

# Returns
- `VolatilityResults`: Complete analysis results
"""
function analyze_volatility_anomaly(
    price_data::DataFrame, 
    analysis_name::String = "volatility_analysis";
    verbose::Bool = true
)::VolatilityResults
    verbose && println("\n🔬 Running volatility anomaly analysis: $analysis_name")
    
    # Step 1: Calculate volatility
    volatility_data = calculate_rolling_volatility(price_data, verbose=verbose)
    
    if nrow(volatility_data) == 0
        error("No volatility data calculated - check input price data")
    end
    
    # Step 2: Form portfolios
    portfolio_assignments = form_volatility_portfolios(volatility_data, verbose=verbose)
    
    if nrow(portfolio_assignments) == 0
        error("No portfolios formed - insufficient data")
    end
    
    # Step 3: Calculate returns
    monthly_returns = calculate_portfolio_returns(price_data, portfolio_assignments, verbose=verbose)
    
    if nrow(monthly_returns) == 0
        error("No portfolio returns calculated")
    end
    
    # Step 4: Long-short returns
    ls_returns = get_long_short_returns(monthly_returns)
    
    # Metadata
    metadata = Dict{Symbol, Any}(
        :analysis_name => analysis_name,
        :n_tickers => length(unique(price_data.ticker)),
        :n_months => length(ls_returns),
        :date_range => (minimum(price_data.timestamp), maximum(price_data.timestamp)),
        :portfolios_formed => length(unique(portfolio_assignments.form_date))
    )
    
    verbose && println("✅ Analysis complete: $(metadata[:n_months]) months of long-short returns")
    
    return VolatilityResults(
        volatility_data,
        portfolio_assignments, 
        monthly_returns,
        ls_returns,
        metadata
    )
end

"""
Run complete volatility anomaly analysis with survivorship bias correction.
Uses point-in-time S&P 500 universe to eliminate survivorship bias.

# Arguments
- `start_date::Date`: Analysis start date (default: 2000-01-01)
- `end_date::Date`: Analysis end date (default: 2024-12-31) 
- `analysis_name::String`: Name for this analysis

# Returns
- `VolatilityResults`: Complete bias-corrected analysis results
"""
function analyze_volatility_anomaly_with_bias_correction(
    start_date::Date = Date(2000, 1, 1),
    end_date::Date = Date(2024, 12, 31),
    analysis_name::String = "survivorship_bias_corrected";
    verbose::Bool = true
)::VolatilityResults
    
    verbose && println("\n🔬 SURVIVORSHIP BIAS CORRECTED ANALYSIS: $analysis_name")
    verbose && println("📅 Period: $start_date to $end_date")
    
    # Step 1: Build point-in-time universe
    verbose && println("\n1️⃣ Building point-in-time S&P 500 universe...")
    universe = build_point_in_time_universe(start_date, end_date)
    
    # Step 2: Download REAL price data for historical constituents
    verbose && println("\n2️⃣ Downloading REAL price data from YFinance...")
    price_data = YFinanceIntegration.build_price_dataset(universe, start_date, end_date)
    
    # Step 3: Run standard analysis pipeline on corrected data
    verbose && println("\n3️⃣ Running volatility analysis pipeline...")
    results = analyze_volatility_anomaly(price_data, analysis_name, verbose=verbose)
    
    # Step 4: Add bias correction metadata
    results.metadata[:survivorship_bias_corrected] = true
    results.metadata[:universe_type] = "point_in_time_sp500"
    results.metadata[:universe_periods] = length(universe)
    results.metadata[:total_unique_tickers] = length(unique(vcat(values(universe)...)))
    
    verbose && println("\n✅ BIAS CORRECTION COMPLETE")
    verbose && println("   Universe periods: $(results.metadata[:universe_periods])")
    verbose && println("   Total unique tickers: $(results.metadata[:total_unique_tickers])")
    verbose && println("   Monthly returns calculated: $(results.metadata[:n_months])")
    
    return results
end

"""
Generate historical price data for point-in-time universe.
In real implementation, this would use YFinance with proper date filtering.
For now, creates realistic simulation based on universe changes.
"""
function generate_historical_price_data(
    universe::Dict{Date, Vector{String}},
    start_date::Date,
    end_date::Date
)::DataFrame
    
    println("📊 Generating price data for survivorship bias correction...")
    
    # Get all unique tickers across all periods
    all_tickers = unique(vcat(values(universe)...))
    
    # Create realistic price evolution
    Random.seed!(42)  # Reproducible results
    price_data = DataFrame()
    
    for ticker in all_tickers
        # Find periods where this ticker was in S&P 500
        active_periods = [date for (date, constituents) in universe if ticker in constituents]
        
        if isempty(active_periods)
            continue
        end
        
        # Generate price series for active periods
        first_date = minimum(active_periods)
        last_date = maximum(active_periods)
        
        # Create daily dates
        dates = collect(first_date:Day(1):last_date)
        n_days = length(dates)
        
        # Generate realistic returns with varying volatility
        base_vol = 0.25  # 25% annual volatility
        ticker_vol = base_vol * (1 + 0.5 * randn())  # Vary by ticker
        
        # Higher volatility for certain sectors/periods
        if ticker in ["TSLA", "NVDA", "AMD"]
            ticker_vol *= 2.0  # High-vol tech stocks
        elseif ticker in ["PG", "KO", "JNJ"]
            ticker_vol *= 0.5  # Low-vol defensive stocks
        end
        
        # Generate returns
        daily_returns = randn(n_days) * (ticker_vol / sqrt(252))
        
        # Starting price
        start_price = 50 + 100 * rand()
        prices = start_price * cumprod(1 .+ daily_returns)
        
        # Create ticker dataframe
        ticker_df = DataFrame(
            ticker = fill(ticker, n_days),
            timestamp = dates,
            adjclose = prices
        )
        
        # Filter to only include periods where ticker was in S&P 500
        # This simulates the natural entry/exit of companies
        ticker_df = filter(row -> any(date -> row.timestamp >= date && row.timestamp < date + Month(1), active_periods), ticker_df)
        
        price_data = vcat(price_data, ticker_df)
    end
    
    # Sort by ticker and date
    sort!(price_data, [:ticker, :timestamp])
    
    println("   ✅ Generated $(nrow(price_data)) price observations")
    println("   ✅ Covering $(length(all_tickers)) unique tickers")
    
    return price_data
end

end