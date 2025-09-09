# Statistical analysis utilities  
# Comprehensive statistical tests and performance metrics

module Statistics

using StatsBase, Printf, Distributions
export StatisticalResults, calculate_performance_statistics, format_statistical_output
export test_novy_marx_hypothesis, create_results_summary

# Struct to hold comprehensive statistical results
struct StatisticalResults
    # Basic statistics
    n_observations::Int
    mean_monthly::Float64
    std_monthly::Float64
    
    # Annualized metrics
    annual_return::Float64
    annual_volatility::Float64
    sharpe_ratio::Float64
    
    # Statistical inference
    t_statistic::Float64
    p_value::Float64
    confidence_interval_95::Tuple{Float64, Float64}
    significance_level::String
    
    # Risk metrics
    maximum_drawdown::Float64
    downside_volatility::Float64
    win_rate::Float64
    
    # Distribution properties
    skewness::Float64
    kurtosis::Float64
    min_return::Float64
    max_return::Float64
    
    # Economic significance
    effect_size_cohens_d::Float64
    economic_significance::String
    
    # Metadata
    analysis_period::String
    data_source::String
end

"""
Calculate comprehensive performance statistics for return series.

# Arguments
- `returns::Vector{Float64}`: Monthly return series
- `analysis_name::String`: Name/description of the analysis
- `confidence_level::Float64`: Confidence level for intervals (default 0.95)

# Returns
- `StatisticalResults`: Complete statistical analysis
"""
function calculate_performance_statistics(
    returns::Vector{Float64},
    analysis_name::String = "Analysis";
    confidence_level::Float64 = 0.95,
    data_source::String = "YFinance"
)::StatisticalResults
    
    n = length(returns)
    if n == 0
        throw(ArgumentError("Empty returns vector provided"))
    end
    
    # Basic statistics
    mean_ret = mean(returns)
    std_ret = std(returns)
    
    # Statistical inference
    t_stat = mean_ret / (std_ret / sqrt(n))
    
    # P-value calculation (two-tailed t-test)
    t_dist = TDist(n - 1)
    p_val = 2 * (1 - cdf(t_dist, abs(t_stat)))
    
    # Significance level classification
    significance = if abs(t_stat) >= 2.807  # p < 0.01
        "***"
    elseif abs(t_stat) >= 2.042  # p < 0.05  
        "**"
    elseif abs(t_stat) >= 1.684  # p < 0.10
        "*" 
    else
        "n.s."
    end
    
    # Confidence interval
    t_critical = quantile(t_dist, 1 - (1 - confidence_level) / 2)
    margin_error = t_critical * (std_ret / sqrt(n))
    ci_95 = (mean_ret - margin_error, mean_ret + margin_error)
    
    # Annualized metrics
    annual_return = mean_ret * 12
    annual_volatility = std_ret * sqrt(12)
    sharpe_ratio = mean_ret / std_ret
    
    # Risk metrics
    max_drawdown = calculate_maximum_drawdown(returns)
    downside_vol = calculate_downside_volatility(returns) * sqrt(12)
    win_rate = sum(returns .> 0) / n
    
    # Distribution properties
    skew = StatsBase.skewness(returns)
    kurt = StatsBase.kurtosis(returns)  # Excess kurtosis
    min_ret = minimum(returns)
    max_ret = maximum(returns)
    
    # Effect size (Cohen's d)
    cohens_d = abs(mean_ret) / std_ret
    
    # Economic significance classification
    econ_sig = if abs(annual_return) >= 0.10  # 10% annual
        "High"
    elseif abs(annual_return) >= 0.05  # 5% annual
        "Medium"
    elseif abs(annual_return) >= 0.02  # 2% annual
        "Low"
    else
        "Negligible"
    end
    
    return StatisticalResults(
        n, mean_ret, std_ret,
        annual_return, annual_volatility, sharpe_ratio,
        t_stat, p_val, ci_95, significance,
        max_drawdown, downside_vol, win_rate,
        skew, kurt, min_ret, max_ret,
        cohens_d, econ_sig,
        analysis_name, data_source
    )
end

"""
Calculate maximum drawdown from return series.
"""
function calculate_maximum_drawdown(returns::Vector{Float64})::Float64
    if isempty(returns)
        return 0.0
    end
    
    cumulative = cumsum(returns)
    peak = cumulative[1]
    max_dd = 0.0
    
    for cum_ret in cumulative
        peak = max(peak, cum_ret)
        drawdown = peak - cum_ret
        max_dd = max(max_dd, drawdown)
    end
    
    return max_dd
end

"""
Calculate downside volatility (volatility of negative returns only).
"""
function calculate_downside_volatility(returns::Vector{Float64})::Float64
    downside_returns = returns[returns .< 0]
    return isempty(downside_returns) ? 0.0 : std(downside_returns)
end

"""
Format statistical results for display.

# Arguments  
- `stats::StatisticalResults`: Statistical results to format
- `verbose::Bool`: Include detailed output

# Returns
- `String`: Formatted output string
"""
function format_statistical_output(
    stats::StatisticalResults; 
    verbose::Bool = true
)::String
    
    output = String[]
    
    # Header
    push!(output, "=" ^ 80)
    push!(output, "STATISTICAL ANALYSIS: $(stats.analysis_period)")
    push!(output, "=" ^ 80)
    
    # Performance summary
    push!(output, "\nPERFORMANCE SUMMARY:")
    push!(output, @sprintf("  Observations:         %6d months", stats.n_observations))
    push!(output, @sprintf("  Mean Monthly Return:  %6.3f%% (t = %5.2f %s)", 
                          stats.mean_monthly * 100, stats.t_statistic, stats.significance_level))
    push!(output, @sprintf("  Annual Return:        %6.2f%%", stats.annual_return * 100))
    push!(output, @sprintf("  Annual Volatility:    %6.2f%%", stats.annual_volatility * 100))
    push!(output, @sprintf("  Sharpe Ratio:         %6.3f", stats.sharpe_ratio))
    
    # Statistical inference
    push!(output, "\nSTATISTICAL INFERENCE:")
    push!(output, @sprintf("  T-Statistic:          %6.3f", stats.t_statistic))
    push!(output, @sprintf("  P-Value (two-tailed): %6.4f", stats.p_value))
    push!(output, @sprintf("  95%% Confidence Int.:  [%5.3f%%, %5.3f%%]", 
                          stats.confidence_interval_95[1] * 100,
                          stats.confidence_interval_95[2] * 100))
    push!(output, @sprintf("  Significance:         %s", stats.significance_level))
    
    if verbose
        # Risk metrics
        push!(output, "\nRISK METRICS:")
        push!(output, @sprintf("  Maximum Drawdown:     %6.2f%%", stats.maximum_drawdown * 100))
        push!(output, @sprintf("  Downside Volatility:  %6.2f%%", stats.downside_volatility * 100))
        push!(output, @sprintf("  Win Rate:            %6.1f%%", stats.win_rate * 100))
        
        # Distribution
        push!(output, "\nDISTRIBUTION PROPERTIES:")
        push!(output, @sprintf("  Skewness:            %6.3f", stats.skewness))
        push!(output, @sprintf("  Excess Kurtosis:     %6.3f", stats.kurtosis))
        push!(output, @sprintf("  Minimum Monthly:     %6.2f%%", stats.min_return * 100))
        push!(output, @sprintf("  Maximum Monthly:     %6.2f%%", stats.max_return * 100))
        
        # Effect size
        push!(output, "\nEFFECT SIZE:")
        push!(output, @sprintf("  Cohen's d:           %6.3f", stats.effect_size_cohens_d))
        push!(output, @sprintf("  Economic Significance: %s", stats.economic_significance))
    end
    
    push!(output, "=" ^ 80)
    
    return join(output, "\n")
end

"""
Test Novy-Marx hypothesis specifically.

# Arguments
- `results::Vector{StatisticalResults}`: Results from multiple periods/analyses
- `alpha_threshold::Float64`: Significance threshold (default 0.05)

# Returns  
- `Dict`: Test results and interpretation
"""
function test_novy_marx_hypothesis(
    results::Vector{StatisticalResults};
    alpha_threshold::Float64 = 0.05
)::Dict{Symbol, Any}
    
    n_analyses = length(results)
    significant_analyses = sum([res.p_value < alpha_threshold for res in results])
    
    # Calculate meta-statistics
    all_t_stats = [res.t_statistic for res in results]
    mean_t_stat = mean(all_t_stats)
    
    all_returns = [res.annual_return for res in results]
    mean_annual_return = mean(all_returns)
    
    # Decision logic
    hypothesis_result = if significant_analyses == 0
        "STRONGLY CONFIRMS Novy-Marx critique"
    elseif significant_analyses < n_analyses / 2
        "CONFIRMS Novy-Marx critique"  
    elseif significant_analyses == n_analyses
        "CONTRADICTS Novy-Marx critique"
    else
        "MIXED EVIDENCE"
    end
    
    confidence = if significant_analyses == 0 || significant_analyses == n_analyses
        "HIGH"
    elseif significant_analyses <= 1 || significant_analyses >= n_analyses - 1
        "MEDIUM" 
    else
        "LOW"
    end
    
    return Dict(
        :n_analyses => n_analyses,
        :n_significant => significant_analyses,
        :significance_rate => significant_analyses / n_analyses,
        :mean_t_statistic => mean_t_stat,
        :mean_annual_return => mean_annual_return,
        :hypothesis_result => hypothesis_result,
        :confidence => confidence,
        :interpretation => interpret_novy_marx_results(hypothesis_result, significant_analyses, n_analyses)
    )
end

"""
Interpret Novy-Marx test results in plain language.
"""
function interpret_novy_marx_results(result::String, sig_count::Int, total_count::Int)::String
    base_msg = "Based on $total_count analyses, $sig_count showed statistical significance. "
    
    if result == "STRONGLY CONFIRMS Novy-Marx critique"
        return base_msg * "This strongly supports Novy-Marx's argument that apparent anomalies " *
               "disappear under rigorous testing. The low volatility anomaly appears to be a " *
               "statistical artifact rather than a genuine market inefficiency."
    elseif result == "CONFIRMS Novy-Marx critique"  
        return base_msg * "This generally supports Novy-Marx's critique. While some evidence " *
               "of the anomaly exists, it is inconsistent and likely due to data mining or " *
               "specific market conditions rather than a robust, exploitable effect."
    elseif result == "CONTRADICTS Novy-Marx critique"
        return base_msg * "This contradicts Novy-Marx's critique and suggests the low volatility " *
               "anomaly is a genuine, persistent market phenomenon that survives rigorous testing."
    else
        return base_msg * "The evidence is mixed and inconclusive. The anomaly may exist in " *
               "certain periods or market conditions but is not consistently significant."
    end
end

"""
Create comprehensive results summary for reporting.
"""
function create_results_summary(
    results::Vector{StatisticalResults},
    novy_marx_test::Dict{Symbol, Any}
)::String
    
    output = String[]
    
    push!(output, "=" ^ 90)
    push!(output, "COMPREHENSIVE VOLATILITY ANOMALY ANALYSIS")
    push!(output, "Testing Novy-Marx Critique with Academic Methodology")
    push!(output, "=" ^ 90)
    
    # Individual results summary
    push!(output, "\nINDIVIDUAL PERIOD RESULTS:")
    push!(output, "-" ^ 90)
    push!(output, @sprintf("%-15s %12s %12s %12s %12s", 
                          "Period", "Annual Ret%", "T-Stat", "P-Value", "Significant"))
    push!(output, "-" ^ 90)
    
    for result in results
        is_sig = result.p_value < 0.05 ? "YES" : "NO"
        push!(output, @sprintf("%-15s %11.1f%% %11.2f %11.4f %12s",
                              result.analysis_period,
                              result.annual_return * 100,
                              result.t_statistic,
                              result.p_value,
                              is_sig))
    end
    
    # Meta-analysis
    push!(output, "\n" * "=" ^ 90)
    push!(output, "META-ANALYSIS RESULTS")
    push!(output, "=" ^ 90)
    
    push!(output, @sprintf("Analyses Conducted:        %d", novy_marx_test[:n_analyses]))
    push!(output, @sprintf("Significant Results:       %d (%.1f%%)", 
                          novy_marx_test[:n_significant],
                          novy_marx_test[:significance_rate] * 100))
    push!(output, @sprintf("Mean T-Statistic:          %.2f", novy_marx_test[:mean_t_statistic]))
    push!(output, @sprintf("Mean Annual Return:        %.1f%%", novy_marx_test[:mean_annual_return] * 100))
    
    # Final verdict
    push!(output, "\n" * "=" ^ 90)
    push!(output, "FINAL VERDICT")
    push!(output, "=" ^ 90)
    
    push!(output, @sprintf("Hypothesis Test Result: %s (Confidence: %s)",
                          novy_marx_test[:hypothesis_result],
                          novy_marx_test[:confidence]))
    
    push!(output, "\nInterpretation:")
    push!(output, novy_marx_test[:interpretation])
    
    push!(output, "\n" * "=" ^ 90)
    
    return join(output, "\n")
end

end