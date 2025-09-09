# Real S&P 500 historical constituents from downloaded CSV
# Uses actual point-in-time data for complete survivorship bias elimination

module RealSP500Data

using DataFrames, Dates, CSV, Statistics

export load_real_sp500_data, build_real_universe, get_real_constituents_for_date

"""
Load the real S&P 500 historical components CSV file.
Returns DataFrame with date and constituents information.
"""
function load_real_sp500_data(csv_path::String = "sp_500_historical_components.csv")
    println("📊 Loading REAL S&P 500 historical data...")
    println("   File: $csv_path")
    
    if !isfile(csv_path)
        error("❌ File not found: $csv_path. Please ensure the sp_500_historical_components.csv file is in the current directory.")
    end
    
    # Read the CSV file
    df = CSV.read(csv_path, DataFrame)
    
    println("   ✅ Loaded $(nrow(df)) daily records")
    println("   📅 Date range: $(minimum(df.date)) to $(maximum(df.date))")
    
    # Parse ticker strings into arrays
    df.ticker_list = [split(tickers, ",") for tickers in df.tickers]
    
    # Show sample statistics
    sample_counts = [length(ticker_list) for ticker_list in df.ticker_list[1:min(10, nrow(df))]]
    avg_constituents = round(mean(sample_counts), digits=1)
    
    println("   📊 Average constituents per day (sample): $avg_constituents")
    
    return df
end

"""
Calculate total unique tickers across the entire historical dataset.
This is the key metric for survivorship bias elimination.
"""
function count_unique_tickers(df::DataFrame)
    println("🔢 Counting unique tickers across full history...")
    
    all_tickers = Set{String}()
    
    for ticker_list in df.ticker_list
        union!(all_tickers, ticker_list)
    end
    
    total_unique = length(all_tickers)
    println("   ✅ Found $total_unique unique tickers in historical data")
    
    # Show sample of historical tickers
    sample_tickers = collect(all_tickers)[1:min(20, length(all_tickers))]
    println("   📋 Sample tickers: $(join(sample_tickers, ", "))")
    
    # Look for key historical companies
    historical_companies = ["ENRNQ", "YHOO", "GM", "KM", "MER", "BSC", "LEH", "WB"]
    found_historical = [ticker for ticker in historical_companies if ticker in all_tickers]
    
    println("   🏛️ Key historical companies found: $(join(found_historical, ", "))")
    println("   📈 Historical coverage: $(length(found_historical))/$(length(historical_companies)) ($(round(length(found_historical)/length(historical_companies)*100, digits=1))%)")
    
    return total_unique, collect(all_tickers)
end

"""
Get S&P 500 constituents for a specific date using real historical data.
"""
function get_real_constituents_for_date(target_date::Date, df::DataFrame)::Vector{String}
    # Find the closest date <= target_date
    valid_rows = filter(row -> row.date <= target_date, df)
    
    if isempty(valid_rows)
        return String[]  # No data available for this early date
    end
    
    # Get the most recent data <= target_date
    max_index = argmax(valid_rows.date)
    closest_row = valid_rows[max_index, :]
    
    return closest_row.ticker_list
end

"""
Build complete point-in-time universe using real historical data.
This replaces our simulated approach with actual S&P 500 historical membership.
"""
function build_real_universe(
    start_date::Date = Date(2000, 1, 1),
    end_date::Date = Date(2024, 12, 31);
    frequency::Symbol = :monthly,
    csv_path::String = "sp_500_historical_components.csv"
)
    println("🏗️ Building REAL S&P 500 universe from historical data...")
    println("   Period: $start_date to $end_date")
    println("   Frequency: $frequency")
    
    # Load real data
    df = load_real_sp500_data(csv_path)
    
    # Count total unique tickers for validation
    total_unique, all_tickers = count_unique_tickers(df)
    
    # Build universe timeline based on frequency
    universe_timeline = Dict{Date, Vector{String}}()
    
    current_date = start_date
    processed_dates = 0
    
    while current_date <= end_date
        # Get constituents for this date
        constituents = get_real_constituents_for_date(current_date, df)
        
        if !isempty(constituents)
            universe_timeline[current_date] = constituents
            processed_dates += 1
        end
        
        # Move to next date based on frequency
        if frequency == :monthly
            current_date = current_date + Month(1)
        elseif frequency == :quarterly
            current_date = current_date + Month(3)
        elseif frequency == :yearly
            current_date = current_date + Year(1)
        else  # daily
            current_date = current_date + Day(1)
        end
    end
    
    # Calculate statistics
    if !isempty(universe_timeline)
        avg_constituents = round(mean(length(v) for v in values(universe_timeline)), digits=1)
        max_constituents = maximum(length(v) for v in values(universe_timeline))
        min_constituents = minimum(length(v) for v in values(universe_timeline))
        
        println("   ✅ Built universe for $processed_dates periods")
        println("   📊 Total unique tickers: $total_unique")
        println("   📊 Average constituents per period: $avg_constituents")
        println("   📊 Min/Max constituents: $min_constituents/$max_constituents")
        
        # Show sample evolution
        sample_dates = [Date(2000,1,1), Date(2008,9,1), Date(2020,1,1), Date(2024,1,1)]
        for sample_date in sample_dates
            if haskey(universe_timeline, sample_date) || any(d -> abs(Dates.value(d - sample_date)) < 40, keys(universe_timeline))
                # Find closest available date
                available_dates = collect(keys(universe_timeline))
                closest_date = available_dates[argmin([abs(Dates.value(d - sample_date)) for d in available_dates])]
                count = length(universe_timeline[closest_date])
                println("   📋 $closest_date: $count constituents")
            end
        end
    else
        println("   ❌ No data found for the specified date range")
    end
    
    return universe_timeline, total_unique
end

"""
Export real universe to CSV for validation.
"""
function export_real_universe(
    universe::Dict{Date, Vector{String}},
    total_unique::Int,
    filename::String = "real_sp500_universe.csv"
)
    println("💾 Exporting REAL universe to CSV...")
    
    export_df = DataFrame(
        date = Date[],
        ticker = String[]
    )
    
    for (date, tickers) in universe
        for ticker in tickers
            push!(export_df, (date, ticker))
        end
    end
    
    sort!(export_df, [:date, :ticker])
    CSV.write(filename, export_df)
    
    println("   ✅ Exported to $filename")
    println("   📊 Total rows: $(nrow(export_df))")
    println("   📊 Unique tickers: $total_unique") 
    
    return export_df
end

"""
Validate the real universe against known historical events.
"""
function validate_real_universe(universe::Dict{Date, Vector{String}})
    println("✅ Validating REAL universe against historical events...")
    
    validation_results = Dict{String, Any}()
    
    # Test 1: Enron should be present before 2001, absent after
    enron_pre_2001 = haskey(universe, Date(2001, 1, 1)) && "ENRNQ" in get(universe, Date(2001, 1, 1), String[])
    enron_post_2002 = haskey(universe, Date(2002, 1, 1)) && "ENRNQ" in get(universe, Date(2002, 1, 1), String[])
    
    validation_results[:enron_timeline] = (pre_2001 = enron_pre_2001, post_2002 = enron_post_2002)
    
    # Test 2: Google should appear around 2004
    google_2003 = any(date -> date <= Date(2003, 12, 31) && ("GOOGL" in get(universe, date, String[]) || "GOOG" in get(universe, date, String[])), keys(universe))
    google_2005 = any(date -> date >= Date(2005, 1, 1) && ("GOOGL" in get(universe, date, String[]) || "GOOG" in get(universe, date, String[])), keys(universe))
    
    validation_results[:google_timeline] = (pre_2004 = google_2003, post_2004 = google_2005)
    
    # Test 3: Tesla should be recent (post-2020)
    tesla_2019 = any(date -> date <= Date(2019, 12, 31) && "TSLA" in get(universe, date, String[]), keys(universe))
    tesla_2021 = any(date -> date >= Date(2021, 1, 1) && "TSLA" in get(universe, date, String[]), keys(universe))
    
    validation_results[:tesla_timeline] = (pre_2020 = tesla_2019, post_2020 = tesla_2021)
    
    # Display results
    println("   📊 VALIDATION RESULTS:")
    for (test, result) in validation_results
        println("      $test: $result")
    end
    
    return validation_results
end

end