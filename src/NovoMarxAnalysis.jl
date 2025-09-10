# NovoMarxAnalysis.jl
# Main module for academically rigorous financial anomaly testing
# Implements Novy-Marx (2013) methodology for factor-adjusted alpha analysis

module NovoMarxAnalysis

using DataFrames, Dates, Statistics, LinearAlgebra, Printf
using Distributions, StatsBase

# Include core modules
include("fama_french_factors.jl")
include("multifactor_regression.jl")

# Re-export essential functionality from submodules
using .FamaFrenchFactors
using .MultifactorRegression

export download_fama_french_factors, get_ff_factors, summarize_factors
export run_capm_regression, run_ff3_regression, run_ff5_regression
export run_capm_regression_aligned, run_ff3_regression_aligned, run_ff5_regression_aligned
export analyze_portfolio_alphas, analyze_portfolio_alphas_aligned, grs_test, grs_test_full
export RegressionResult, AlphaAnalysis
export summarize_regression_results, summarize_alpha_analysis
export calculate_sharpe_ratio_corrected
export analyze_low_volatility_anomaly_aligned
export calculate_sharpe_ratio_corrected

"""
    analyze_low_volatility_anomaly(returns, start_date, end_date; verbose=true)

Complete Novy-Marx compliant analysis of low volatility anomaly.

This function implements the academically rigorous approach of testing 
factor-adjusted alphas rather than raw returns, following Novy-Marx (2013)
critique that most anomalies disappear under proper factor controls.

# Arguments
- `returns::Vector{Float64}`: Portfolio returns (%)
- `start_date::Date`: Analysis start date  
- `end_date::Date`: Analysis end date
- `verbose::Bool=true`: Print detailed output

# Returns
- `AlphaAnalysis`: Comprehensive results with CAPM, FF3, FF5 regressions and conclusions

# Example
```julia
using NovoMarxAnalysis

# Analyze portfolio returns
results = analyze_low_volatility_anomaly(
    portfolio_returns,
    Date(2020, 1, 1),
    Date(2023, 12, 31)
)

println(results.novy_marx_conclusion)
```
"""
function analyze_low_volatility_anomaly(
    returns::Vector{Float64},
    start_date::Date,
    end_date::Date;
    verbose::Bool = true
)::AlphaAnalysis
    
    verbose && println("🧪 NOVY-MARX LOW VOLATILITY ANALYSIS")
    verbose && println("=" ^ 50)
    
    # Download real Fama-French factors
    verbose && println("📥 Downloading Fama-French factors...")
    factors = download_fama_french_factors(start_date, end_date, verbose=false)
    
    if nrow(factors) < 12
        error("Insufficient factor data: need at least 12 months, got $(nrow(factors))")
    end
    
    verbose && println("✅ Downloaded $(nrow(factors)) factor observations")
    
    # Run comprehensive alpha analysis
    verbose && println("🔬 Running multifactor regressions...")
    analysis = analyze_portfolio_alphas(
        returns, 
        factors, 
        "Low Volatility Portfolio",
        "$(start_date) to $(end_date)"
    )

    @warn "For academically rigorous, date-aligned analysis, prefer analyze_low_volatility_anomaly_aligned(...) with Date-joined data."

    if verbose
        println("\n📊 RESULTS SUMMARY:")
        summarize_alpha_analysis(analysis)
    end
    
    return analysis
end

"""
    analyze_low_volatility_anomaly_aligned(portfolios_df, factors_df, portfolio_col; verbose=true)

Novy-Marx compliant analysis using Date-aligned data. This version is preferred for
academic use. It joins by Date, drops missing rows, and runs CAPM/FF3/FF5 with
correct Sharpe handling.
"""
function analyze_low_volatility_anomaly_aligned(
    portfolios_df::DataFrame,
    factors_df::DataFrame,
    portfolio_col::String;
    verbose::Bool = true
)::AlphaAnalysis
    verbose && println("🧪 NOVY-MARX LOW VOL (ALIGNED) ANALYSIS")
    verbose && println("=" ^ 50)

    if !("Date" in names(portfolios_df)) || !("Date" in names(factors_df))
        error("Both portfolios_df and factors_df must have a Date column")
    end

    verbose && println("🔬 Running aligned multifactor regressions...")
    analysis = analyze_portfolio_alphas_aligned(
        portfolios_df, factors_df, portfolio_col, portfolio_col
    )

    if verbose
        println("\n📊 RESULTS SUMMARY:")
        summarize_alpha_analysis(analysis)
    end

    return analysis
end

"""
    test_joint_significance(portfolio_results; alpha_level=0.05)

Test joint significance of alphas across multiple portfolios using GRS test.

# Arguments  
- `portfolio_results::Vector{RegressionResult}`: Results from multiple portfolios
- `alpha_level::Float64=0.05`: Significance level for test

# Returns
- `Dict`: GRS test results with F-statistic, p-value, and conclusion
"""
function test_joint_significance(
    portfolio_results::Vector{RegressionResult}; 
    alpha_level::Float64 = 0.05
)::Dict{Symbol, Any}
    
    return grs_test(portfolio_results, alpha_level=alpha_level)
end

"""
    get_sample_data()

Returns paths to sample data files included with the package.
Useful for testing and demonstrations.

# Returns
- `Dict{Symbol, String}`: Paths to sample data files
"""
function get_sample_data()::Dict{Symbol, String}
    
    data_dir = joinpath(@__DIR__, "..", "data")
    
    return Dict(
        :sp500_components => joinpath(data_dir, "sp_500_historical_components.csv"),
        :universe_validation => joinpath(data_dir, "real_sp500_universe_validation.csv"),
        :github_validation => joinpath(data_dir, "github_sp500_universe_validation.csv")
    )
end

"""
Print package information and usage examples.
"""
function package_info()
    println("""
    📦 NovoMarxAnalysis.jl
    ═════════════════════
    
    Academic-grade implementation of Novy-Marx (2013) methodology
    for testing financial anomalies with factor-adjusted alpha analysis.
    
    🎯 Key Features:
    • Real Fama-French factor data from Kenneth French Data Library  
    • CAPM, FF3, and FF5 multifactor regressions
    • GRS test for joint significance across portfolios
    • Automatic model selection and academic conclusions
    
    📖 Quick Start:
    
    using NovoMarxAnalysis
    
    # Download factors
    factors = download_fama_french_factors(Date(2020,1,1), Date(2023,12,31))
    
    # Analyze portfolio  
    results = analyze_low_volatility_anomaly(returns, Date(2020,1,1), Date(2023,12,31))
    
    # View conclusion
    println(results.novy_marx_conclusion)
    
    🏆 Academic Standard:
    This implementation transforms anomaly research from methodologically 
    questionable raw return testing to academically defensible factor-adjusted
    alpha analysis, following modern finance best practices.
    """)
end

# Print info on module load
function __init__()
    println("📦 NovoMarxAnalysis.jl loaded - Academic anomaly testing with factor controls")
end

end # module NovoMarxAnalysis
