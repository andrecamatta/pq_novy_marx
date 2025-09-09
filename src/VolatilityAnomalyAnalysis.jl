# Main module for Volatility Anomaly Analysis
# Clean, modular implementation testing Novy-Marx critique

module VolatilityAnomalyAnalysis

using DataFrames, Dates, CSV, JSON, Printf

# Include utility modules
include("utils/config.jl")
include("utils/data_download.jl") 
include("utils/portfolio_analysis.jl")
include("utils/statistics.jl")

# Import and re-export key functionality
using .Config, .DataDownload, .PortfolioAnalysis
using .DataDownload: get_universe, get_analysis_periods
using .Statistics: StatisticalResults, calculate_performance_statistics, 
                   test_novy_marx_hypothesis, create_results_summary, format_statistical_output

export analyze_volatility_anomaly_full, run_novy_marx_test, save_results
export AnalysisConfig, AnalysisResults

# Configuration struct for analysis parameters
struct AnalysisConfig
    universe_type::Symbol
    periods::Vector{Tuple{String, String, String}}
    volatility_window::Int
    n_portfolios::Int
    formation_lag::Int
    output_dir::String
    verbose::Bool
end

# Default configuration
function AnalysisConfig(;
    universe_type::Symbol = :sp500_approximation,
    periods::Vector{Tuple{String, String, String}} = get_analysis_periods(),
    volatility_window::Int = VOLATILITY_CONFIG[:window],
    n_portfolios::Int = PORTFOLIO_CONFIG[:n_portfolios], 
    formation_lag::Int = PORTFOLIO_CONFIG[:formation_lag],
    output_dir::String = "results",
    verbose::Bool = true
)
    return AnalysisConfig(universe_type, periods, volatility_window, n_portfolios, 
                         formation_lag, output_dir, verbose)
end

# Results struct to hold complete analysis
struct AnalysisResults
    config::AnalysisConfig
    period_results::Dict{String, VolatilityResults}
    statistical_results::Dict{String, StatisticalResults}
    novy_marx_test::Dict{Symbol, Any}
    metadata::Dict{Symbol, Any}
end

"""
Run complete volatility anomaly analysis testing Novy-Marx critique.

# Arguments
- `config::AnalysisConfig`: Analysis configuration (optional)

# Returns
- `AnalysisResults`: Complete analysis results

# Example
```julia
# Run with default settings
results = analyze_volatility_anomaly_full()

# Run with custom configuration  
config = AnalysisConfig(universe_type=:test_universe, verbose=false)
results = analyze_volatility_anomaly_full(config)
```
"""
function analyze_volatility_anomaly_full(
    config::AnalysisConfig = AnalysisConfig()
)::AnalysisResults
    
    config.verbose && println("🚀 Starting Volatility Anomaly Analysis")
    config.verbose && println("   Testing Novy-Marx Critique with Academic Standards")
    config.verbose && println("=" ^ 80)
    
    # Create output directory
    if !isdir(config.output_dir)
        mkdir(config.output_dir)
        config.verbose && println("📁 Created output directory: $(config.output_dir)")
    end
    
    # Get universe
    tickers = get_universe(config.universe_type)
    config.verbose && println("🎯 Universe: $(length(tickers)) tickers ($(config.universe_type))")
    
    # Download data for all periods
    config.verbose && println("\n📥 DOWNLOADING MARKET DATA")
    config.verbose && println("-" ^ 50)
    
    all_price_data = download_with_retry(tickers, config.periods, verbose=config.verbose)
    
    if isempty(all_price_data)
        error("❌ No price data downloaded successfully")
    end
    
    # Analyze each period
    period_results = Dict{String, VolatilityResults}()
    statistical_results = Dict{String, StatisticalResults}()
    
    config.verbose && println("\n🔬 RUNNING PORTFOLIO ANALYSIS")  
    config.verbose && println("-" ^ 50)
    
    for (period_name, start_date, end_date) in config.periods
        if haskey(all_price_data, period_name)
            config.verbose && println("\n📊 Analyzing period: $period_name")
            
            # Portfolio analysis
            vol_results = analyze_volatility_anomaly(
                all_price_data[period_name], 
                period_name,
                verbose=config.verbose
            )
            period_results[period_name] = vol_results
            
            # Statistical analysis
            if !isempty(vol_results.long_short_returns)
                stats = calculate_performance_statistics(
                    vol_results.long_short_returns,
                    period_name
                )
                statistical_results[period_name] = stats
                
                if config.verbose
                    println(format_statistical_output(stats, verbose=false))
                end
            end
        else
            config.verbose && println("⚠️  Skipping $period_name - no data available")
        end
    end
    
    # Test Novy-Marx hypothesis
    config.verbose && println("\n🧪 TESTING NOVY-MARX HYPOTHESIS")
    config.verbose && println("-" ^ 50)
    
    novy_marx_test = test_novy_marx_hypothesis(collect(values(statistical_results)))
    
    # Create metadata
    metadata = Dict{Symbol, Any}(
        :analysis_date => now(),
        :total_periods => length(config.periods),
        :successful_periods => length(period_results),
        :total_tickers => length(tickers),
        :configuration => config
    )
    
    results = AnalysisResults(
        config,
        period_results,
        statistical_results, 
        novy_marx_test,
        metadata
    )
    
    # Display summary
    if config.verbose
        summary = create_results_summary(collect(values(statistical_results)), novy_marx_test)
        println("\n" * summary)
    end
    
    # Auto-save results
    save_results(results)
    
    config.verbose && println("\n✅ Analysis complete! Results saved to $(config.output_dir)/")
    
    return results
end

"""
Quick test of Novy-Marx critique with minimal configuration.

# Returns
- `AnalysisResults`: Results using test universe and short periods
"""
function run_novy_marx_test()::AnalysisResults
    println("🧪 Quick Novy-Marx Test (Test Universe)")
    
    config = AnalysisConfig(
        universe_type = :test_universe,
        periods = [("2020-2024", "2020-01-01", "2024-11-30")],
        verbose = true
    )
    
    return analyze_volatility_anomaly_full(config)
end

"""
Save analysis results to files.

# Arguments  
- `results::AnalysisResults`: Results to save
- `custom_dir::String`: Custom output directory (optional)
"""
function save_results(
    results::AnalysisResults;
    custom_dir::String = results.config.output_dir
)
    # Ensure directory exists
    if !isdir(custom_dir)
        mkdir(custom_dir)
    end
    
    # Save statistical summary
    stats_summary = DataFrame(
        Period = [stat.analysis_period for stat in values(results.statistical_results)],
        Annual_Return_Pct = [stat.annual_return * 100 for stat in values(results.statistical_results)],
        Annual_Volatility_Pct = [stat.annual_volatility * 100 for stat in values(results.statistical_results)],
        T_Statistic = [stat.t_statistic for stat in values(results.statistical_results)],
        P_Value = [stat.p_value for stat in values(results.statistical_results)],
        Sharpe_Ratio = [stat.sharpe_ratio for stat in values(results.statistical_results)],
        Significance = [stat.significance_level for stat in values(results.statistical_results)],
        Observations = [stat.n_observations for stat in values(results.statistical_results)]
    )
    
    CSV.write(joinpath(custom_dir, "statistical_summary.csv"), stats_summary)
    
    # Save monthly returns for each period
    for (period_name, vol_results) in results.period_results
        if !isempty(vol_results.long_short_returns)
            monthly_df = DataFrame(
                month = 1:length(vol_results.long_short_returns),
                long_short_return = vol_results.long_short_returns
            )
            
            filename = "monthly_returns_$(replace(period_name, " " => "_")).csv"
            CSV.write(joinpath(custom_dir, filename), monthly_df)
        end
    end
    
    # Save Novy-Marx test results
    test_results = Dict(
        "novy_marx_test" => results.novy_marx_test,
        "metadata" => results.metadata,
        "configuration" => Dict(
            "universe_type" => string(results.config.universe_type),
            "periods" => results.config.periods,
            "volatility_window" => results.config.volatility_window,
            "n_portfolios" => results.config.n_portfolios,
            "formation_lag" => results.config.formation_lag
        )
    )
    
    # Convert datetime to string for JSON serialization
    test_results["metadata"][:analysis_date] = string(results.metadata[:analysis_date])
    
    open(joinpath(custom_dir, "novy_marx_test.json"), "w") do f
        JSON.print(f, test_results, 4)  # Pretty print with 4-space indent
    end
    
    # Save comprehensive text report
    if !isempty(results.statistical_results)
        report = create_results_summary(
            collect(values(results.statistical_results)), 
            results.novy_marx_test
        )
        
        open(joinpath(custom_dir, "analysis_report.txt"), "w") do f
            write(f, report)
        end
    end
    
    println("💾 Results saved to:")
    println("   📊 statistical_summary.csv - Key statistics by period")
    println("   📈 monthly_returns_*.csv - Monthly return series")  
    println("   🧪 novy_marx_test.json - Hypothesis test results")
    println("   📄 analysis_report.txt - Comprehensive report")
end

"""
Load and display previous analysis results.

# Arguments
- `results_dir::String`: Directory containing saved results

# Returns  
- `Nothing`: Displays results to console
"""
function display_saved_results(results_dir::String = "results")
    if !isdir(results_dir)
        println("❌ Results directory not found: $results_dir")
        return
    end
    
    # Load statistical summary
    stats_file = joinpath(results_dir, "statistical_summary.csv")
    if isfile(stats_file)
        stats = CSV.read(stats_file, DataFrame)
        println("\n📊 STATISTICAL SUMMARY")
        println("-" ^ 60)
        show(stats, show_row_number=false, allrows=true, allcols=true)
    end
    
    # Load Novy-Marx test results
    test_file = joinpath(results_dir, "novy_marx_test.json")
    if isfile(test_file)
        test_data = JSON.parsefile(test_file)
        novy_marx = test_data["novy_marx_test"]
        
        println("\n\n🧪 NOVY-MARX HYPOTHESIS TEST")
        println("-" ^ 60)
        println("Result: $(novy_marx["hypothesis_result"])")
        println("Confidence: $(novy_marx["confidence"])")
        println("Significant Periods: $(novy_marx["n_significant"])/$(novy_marx["n_analyses"])")
        println("Mean Annual Return: $(round(novy_marx["mean_annual_return"]*100, digits=1))%")
        println("Mean T-Statistic: $(round(novy_marx["mean_t_statistic"], digits=2))")
        
        println("\nInterpretation:")
        println(novy_marx["interpretation"])
    end
    
    # Load full report if available
    report_file = joinpath(results_dir, "analysis_report.txt")
    if isfile(report_file)
        println("\n📄 FULL REPORT AVAILABLE: $report_file")
    end
end

end  # module VolatilityAnomalyAnalysis