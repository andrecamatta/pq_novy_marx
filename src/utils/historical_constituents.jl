# Historical S&P 500 constituents for survivorship bias correction
# Real CSV data integration approach

module HistoricalConstituents

using DataFrames, Dates, Statistics
include("config.jl")
include("real_sp500_data.jl")
using .Config
using .RealSP500Data

export get_historical_sp500_constituents, build_point_in_time_universe

# Global cache for universe data
const UNIVERSE_CACHE = Ref{Union{Nothing, Dict{Date, Vector{String}}}}(nothing)
const TOTAL_TICKERS_CACHE = Ref{Int}(0)

"""
Get S&P 500 constituents at a specific historical date.
Uses real CSV data for complete historical accuracy.
"""
function get_historical_sp500_constituents(target_date::Date)::Vector{String}
    # Load universe if not cached
    if UNIVERSE_CACHE[] === nothing
        println("📊 Loading complete S&P 500 universe from REAL CSV data...")
        universe, total_unique = RealSP500Data.build_real_universe()
        UNIVERSE_CACHE[] = universe
        TOTAL_TICKERS_CACHE[] = total_unique
    end
    
    universe = UNIVERSE_CACHE[]
    
    # Find closest date <= target_date
    valid_dates = [d for d in keys(universe) if d <= target_date]
    if isempty(valid_dates)
        return String[]
    end
    
    closest_date = maximum(valid_dates)
    return universe[closest_date]
end

"""
Build point-in-time universe dictionary for the entire analysis period.
Returns Dict{Date, Vector{String}} with constituents for each month.
Uses GitHub repository data for maximum accuracy.
"""
function build_point_in_time_universe(
    start_date::Date = Date(2000, 1, 1),
    end_date::Date = Date(2024, 12, 31);
    frequency::Symbol = :monthly
)::Dict{Date, Vector{String}}
    
    println("📅 Building point-in-time S&P 500 universe from REAL CSV data...")
    println("   Period: $start_date to $end_date")
    
    # Use real CSV data to build complete universe
    universe, total_unique = RealSP500Data.build_real_universe(start_date, end_date)
    
    # Filter to requested frequency if needed
    if frequency == :monthly
        # Universe is already monthly, return as-is
        filtered_universe = universe
    elseif frequency == :quarterly
        # Keep only quarterly snapshots
        filtered_universe = Dict{Date, Vector{String}}()
        for (date, constituents) in universe
            if month(date) in [1, 4, 7, 10]  # Q1, Q2, Q3, Q4
                filtered_universe[date] = constituents
            end
        end
    else  # yearly
        # Keep only yearly snapshots  
        filtered_universe = Dict{Date, Vector{String}}()
        for (date, constituents) in universe
            if month(date) == 1  # January only
                filtered_universe[date] = constituents
            end
        end
    end
    
    dates_processed = length(filtered_universe)
    
    println("   ✅ Built universe for $dates_processed periods")
    
    # Validation summary
    avg_constituents = round(mean(length(v) for v in values(filtered_universe)), digits=1)
    
    println("   📊 Summary:")
    println("      Total unique tickers: $total_unique")  
    println("      Average constituents per period: $avg_constituents")
    
    # Cache for future use
    UNIVERSE_CACHE[] = universe
    TOTAL_TICKERS_CACHE[] = total_unique
    
    return filtered_universe
end

"""
Get universe statistics for reporting.
"""
function get_universe_stats()
    if UNIVERSE_CACHE[] === nothing
        # Build a small sample to get stats
        sample_universe, total_unique = RealSP500Data.build_real_universe(
            Date(2020, 1, 1), 
            Date(2020, 12, 31)
        )
        return Dict(
            :total_unique_tickers => total_unique,
            :sample_periods => length(sample_universe),
            :data_source => "Real CSV file (sp500_historical_components)"
        )
    else
        return Dict(
            :total_unique_tickers => TOTAL_TICKERS_CACHE[],
            :cached_periods => length(UNIVERSE_CACHE[]),
            :data_source => "Real CSV file (cached)"
        )
    end
end

"""
Export universe for validation and backup.
"""
function export_universe(filename::String = "complete_sp500_universe.csv")
    if UNIVERSE_CACHE[] === nothing
        universe, total_unique = RealSP500Data.build_real_universe()
        UNIVERSE_CACHE[] = universe
        TOTAL_TICKERS_CACHE[] = total_unique
    end
    
    return RealSP500Data.export_real_universe(UNIVERSE_CACHE[], TOTAL_TICKERS_CACHE[], filename)
end

end