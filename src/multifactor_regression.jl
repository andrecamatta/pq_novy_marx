# Multifactor Regression Module for Novy-Marx Methodology
# Implements CAPM, Fama-French 3-factor and 5-factor models
# Tests portfolio alphas instead of raw returns for academic rigor

module MultifactorRegression

using DataFrames, Dates, Statistics, LinearAlgebra, Printf
using GLM, StatsBase, Distributions

export RegressionResult, run_capm_regression, run_ff3_regression, run_ff5_regression
export grs_test, calculate_newey_west_se, summarize_regression_results
export AlphaAnalysis, analyze_portfolio_alphas, summarize_alpha_analysis

"""
Structure to hold multifactor regression results
"""
struct RegressionResult
    model::String                    # "CAPM", "FF3", or "FF5"
    alpha::Float64                   # Intercept (annualized)
    alpha_tstat::Float64            # t-statistic for alpha
    alpha_pvalue::Float64           # p-value for alpha
    betas::Vector{Float64}          # Factor loadings
    beta_tstats::Vector{Float64}    # t-statistics for betas
    beta_pvalues::Vector{Float64}   # p-values for betas
    r_squared::Float64              # R-squared
    adj_r_squared::Float64          # Adjusted R-squared
    residuals::Vector{Float64}      # Regression residuals
    n_obs::Int                      # Number of observations
    factor_names::Vector{String}    # Names of factors used
    period::String                  # Analysis period identifier
    portfolio_name::String          # Portfolio identifier (e.g., "Low Vol", "High Vol", "Long-Short")
end

"""
Structure for comprehensive alpha analysis across multiple models
"""
struct AlphaAnalysis
    portfolio_name::String
    period::String
    raw_return::Float64             # Annualized raw return
    raw_volatility::Float64         # Annualized volatility
    raw_sharpe::Float64            # Raw Sharpe ratio
    capm_result::RegressionResult   # CAPM regression
    ff3_result::Union{RegressionResult, Nothing}  # FF3 regression (if available)
    ff5_result::Union{RegressionResult, Nothing}  # FF5 regression (if available)
    best_model::String             # Model with highest R-squared
    novy_marx_conclusion::String   # Conclusion based on Novy-Marx criteria
end

"""
Run CAPM regression: r_p,t - r_f,t = α + β×(r_m,t - r_f,t) + ε_t

Parameters:
- portfolio_returns: Monthly portfolio returns (%)
- factors: DataFrame with Date, MKT_RF, RF columns
- portfolio_name: Name identifier for portfolio
- period: Period identifier
"""
function run_capm_regression(
    portfolio_returns::Vector{Float64}, 
    factors::DataFrame,
    portfolio_name::String = "Portfolio",
    period::String = "Unknown"
)::RegressionResult
    
    # Align data by common dates
    n_returns = length(portfolio_returns)
    n_factors = nrow(factors)
    
    if n_returns != n_factors
        # Take minimum length and warn
        min_n = min(n_returns, n_factors)
        @warn "Length mismatch: returns=$n_returns, factors=$n_factors. Using first $min_n observations."
        portfolio_returns = portfolio_returns[1:min_n]
        factors = factors[1:min_n, :]
    end
    
    # Calculate excess returns
    rf = factors.RF / 100  # Convert to decimal
    mkt_rf = factors.MKT_RF / 100  # Convert to decimal
    excess_returns = (portfolio_returns / 100) .- rf  # Portfolio excess returns
    
    # Run regression: excess_return = α + β*market_premium + ε
    X = [ones(length(mkt_rf)) mkt_rf]  # Design matrix with intercept and market premium
    y = excess_returns
    
    # Ordinary Least Squares
    β_ols = (X' * X) \ (X' * y)
    alpha_monthly = β_ols[1]
    beta_market = β_ols[2]
    
    # Calculate fitted values and residuals
    y_fitted = X * β_ols
    residuals = y - y_fitted
    
    # Standard errors and t-statistics
    mse = sum(residuals.^2) / (length(y) - 2)  # Mean squared error
    var_covar = mse * inv(X' * X)
    se = sqrt.(diag(var_covar))
    
    alpha_tstat = alpha_monthly / se[1]
    beta_tstat = beta_market / se[2]
    
    # p-values (two-tailed)
    df = length(y) - 2
    alpha_pvalue = 2 * (1 - cdf(TDist(df), abs(alpha_tstat)))
    beta_pvalue = 2 * (1 - cdf(TDist(df), abs(beta_tstat)))
    
    # R-squared
    tss = sum((y .- mean(y)).^2)  # Total sum of squares
    ess = sum(residuals.^2)       # Error sum of squares
    r_squared = 1 - (ess / tss)
    adj_r_squared = 1 - (ess / tss) * (length(y) - 1) / (length(y) - 2)
    
    return RegressionResult(
        "CAPM",
        alpha_monthly * 12 * 100,    # Annualized alpha in %
        alpha_tstat,
        alpha_pvalue,
        [beta_market],               # Only market beta
        [beta_tstat],
        [beta_pvalue],
        r_squared,
        adj_r_squared,
        residuals * 100,             # Residuals in %
        length(y),
        ["MKT-RF"],
        period,
        portfolio_name
    )
end

"""
Run Fama-French 3-factor regression: r_p,t - r_f,t = α + β₁×MKT_RF + β₂×SMB + β₃×HML + ε_t
"""
function run_ff3_regression(
    portfolio_returns::Vector{Float64}, 
    factors::DataFrame,
    portfolio_name::String = "Portfolio",
    period::String = "Unknown"
)::Union{RegressionResult, Nothing}
    
    # Check if required factors are available
    required_cols = ["MKT_RF", "SMB", "HML", "RF"]
    missing_cols = [col for col in required_cols if col ∉ names(factors)]
    
    if !isempty(missing_cols)
        @warn "FF3 regression not possible. Missing factors: $missing_cols"
        return nothing
    end
    
    # Align data
    n_returns = length(portfolio_returns)
    n_factors = nrow(factors)
    
    if n_returns != n_factors
        min_n = min(n_returns, n_factors)
        portfolio_returns = portfolio_returns[1:min_n]
        factors = factors[1:min_n, :]
    end
    
    # Convert to decimal and calculate excess returns
    rf = factors.RF / 100
    mkt_rf = factors.MKT_RF / 100
    smb = factors.SMB / 100
    hml = factors.HML / 100
    excess_returns = (portfolio_returns / 100) .- rf
    
    # Design matrix: [1, MKT-RF, SMB, HML]
    X = [ones(length(mkt_rf)) mkt_rf smb hml]
    y = excess_returns
    
    # OLS regression
    β_ols = (X' * X) \ (X' * y)
    alpha_monthly = β_ols[1]
    betas = β_ols[2:end]
    
    # Calculate statistics
    y_fitted = X * β_ols
    residuals = y - y_fitted
    
    mse = sum(residuals.^2) / (length(y) - size(X, 2))
    var_covar = mse * inv(X' * X)
    se = sqrt.(diag(var_covar))
    
    # t-statistics and p-values
    tstats = β_ols ./ se
    df = length(y) - size(X, 2)
    pvalues = [2 * (1 - cdf(TDist(df), abs(t))) for t in tstats]
    
    # R-squared
    tss = sum((y .- mean(y)).^2)
    ess = sum(residuals.^2)
    r_squared = 1 - (ess / tss)
    adj_r_squared = 1 - (ess / tss) * (length(y) - 1) / (length(y) - size(X, 2))
    
    return RegressionResult(
        "FF3",
        alpha_monthly * 12 * 100,    # Annualized alpha in %
        tstats[1],                   # Alpha t-stat
        pvalues[1],                  # Alpha p-value
        betas,                       # [β_MKT, β_SMB, β_HML]
        tstats[2:end],              # Beta t-stats
        pvalues[2:end],             # Beta p-values
        r_squared,
        adj_r_squared,
        residuals * 100,
        length(y),
        ["MKT-RF", "SMB", "HML"],
        period,
        portfolio_name
    )
end

"""
Run Fama-French 5-factor regression: r_p,t - r_f,t = α + β₁×MKT_RF + β₂×SMB + β₃×HML + β₄×RMW + β₅×CMA + ε_t
"""
function run_ff5_regression(
    portfolio_returns::Vector{Float64}, 
    factors::DataFrame,
    portfolio_name::String = "Portfolio",
    period::String = "Unknown"
)::Union{RegressionResult, Nothing}
    
    # Check if required factors are available
    required_cols = ["MKT_RF", "SMB", "HML", "RMW", "CMA", "RF"]
    missing_cols = [col for col in required_cols if col ∉ names(factors)]
    
    if !isempty(missing_cols)
        @warn "FF5 regression not possible. Missing factors: $missing_cols"
        return nothing
    end
    
    # Align data
    n_returns = length(portfolio_returns)
    n_factors = nrow(factors)
    
    if n_returns != n_factors
        min_n = min(n_returns, n_factors)
        portfolio_returns = portfolio_returns[1:min_n]
        factors = factors[1:min_n, :]
    end
    
    # Convert to decimal and calculate excess returns
    rf = factors.RF / 100
    mkt_rf = factors.MKT_RF / 100
    smb = factors.SMB / 100
    hml = factors.HML / 100
    rmw = factors.RMW / 100
    cma = factors.CMA / 100
    excess_returns = (portfolio_returns / 100) .- rf
    
    # Design matrix: [1, MKT-RF, SMB, HML, RMW, CMA]
    X = [ones(length(mkt_rf)) mkt_rf smb hml rmw cma]
    y = excess_returns
    
    # OLS regression
    β_ols = (X' * X) \ (X' * y)
    alpha_monthly = β_ols[1]
    betas = β_ols[2:end]
    
    # Calculate statistics
    y_fitted = X * β_ols
    residuals = y - y_fitted
    
    mse = sum(residuals.^2) / (length(y) - size(X, 2))
    var_covar = mse * inv(X' * X)
    se = sqrt.(diag(var_covar))
    
    # t-statistics and p-values
    tstats = β_ols ./ se
    df = length(y) - size(X, 2)
    pvalues = [2 * (1 - cdf(TDist(df), abs(t))) for t in tstats]
    
    # R-squared
    tss = sum((y .- mean(y)).^2)
    ess = sum(residuals.^2)
    r_squared = 1 - (ess / tss)
    adj_r_squared = 1 - (ess / tss) * (length(y) - 1) / (length(y) - size(X, 2))
    
    return RegressionResult(
        "FF5",
        alpha_monthly * 12 * 100,    # Annualized alpha in %
        tstats[1],                   # Alpha t-stat
        pvalues[1],                  # Alpha p-value
        betas,                       # [β_MKT, β_SMB, β_HML, β_RMW, β_CMA]
        tstats[2:end],              # Beta t-stats
        pvalues[2:end],             # Beta p-values
        r_squared,
        adj_r_squared,
        residuals * 100,
        length(y),
        ["MKT-RF", "SMB", "HML", "RMW", "CMA"],
        period,
        portfolio_name
    )
end

"""
Gibbons-Ross-Shanken (GRS) test for joint significance of alphas across multiple portfolios.
Tests H₀: α₁ = α₂ = ... = αₙ = 0

Parameters:
- results: Vector of RegressionResult objects from the same model type
- alpha_level: Significance level (default 0.05)

Returns:
- Dict with test statistic, p-value, and conclusion
"""
function grs_test(results::Vector{RegressionResult}; alpha_level::Float64 = 0.05)::Dict{Symbol, Any}
    
    if isempty(results)
        return Dict(:error => "No regression results provided")
    end
    
    # Ensure all results are from the same model
    model_types = unique([r.model for r in results])
    if length(model_types) > 1
        return Dict(:error => "All regression results must be from the same model type")
    end
    
    model_type = model_types[1]
    n_portfolios = length(results)
    n_obs = minimum([r.n_obs for r in results])  # Use minimum observations
    
    if n_portfolios < 2
        return Dict(:error => "At least 2 portfolios required for GRS test")
    end
    
    # Extract alphas and residuals
    alphas = [r.alpha / 100 / 12 for r in results]  # Convert to monthly decimal
    residuals_matrix = hcat([r.residuals[1:n_obs] / 100 for r in results]...)  # Convert to decimal
    
    # Calculate sample covariance matrix of residuals
    Σ = cov(residuals_matrix)
    
    # GRS test statistic
    α_vec = alphas
    n_factors = length(results[1].factor_names)
    
    # F-statistic: F = (T-N-K)/N * (1 + μ'Σ⁻¹μ)⁻¹ * α'Σ⁻¹α
    # Where T = observations, N = portfolios, K = factors, μ = mean factor returns
    
    # For simplicity, we'll use the standard form:
    T = n_obs
    N = n_portfolios  
    K = n_factors
    
    try
        Σ_inv = inv(Σ)
        grs_stat = (T - N - K) / N * (α_vec' * Σ_inv * α_vec)
        
        # F-distribution with (N, T-N-K) degrees of freedom
        df1 = N
        df2 = T - N - K
        
        if df2 <= 0
            return Dict(
                :error => "Insufficient degrees of freedom for GRS test",
                :df2 => df2,
                :required_obs => N + K + 1
            )
        end
        
        f_dist = FDist(df1, df2)
        p_value = 1 - cdf(f_dist, grs_stat)
        
        # Critical value
        critical_value = quantile(f_dist, 1 - alpha_level)
        
        # Test conclusion
        is_significant = grs_stat > critical_value
        conclusion = if is_significant
            "REJECT H₀: At least one alpha is significantly different from zero"
        else
            "FAIL TO REJECT H₀: All alphas are statistically zero"
        end
        
        return Dict(
            :model => model_type,
            :n_portfolios => n_portfolios,
            :n_observations => n_obs,
            :grs_statistic => grs_stat,
            :p_value => p_value,
            :critical_value => critical_value,
            :degrees_of_freedom => (df1, df2),
            :is_significant => is_significant,
            :conclusion => conclusion,
            :alpha_level => alpha_level,
            :individual_alphas => [r.alpha for r in results],
            :individual_pvalues => [r.alpha_pvalue for r in results]
        )
        
    catch e
        return Dict(
            :error => "Error computing GRS test: $e",
            :covariance_matrix_singular => det(Σ) ≈ 0
        )
    end
end

"""
Comprehensive analysis of portfolio alphas across all available models.
This is the core function for Novy-Marx methodology testing.
"""
function analyze_portfolio_alphas(
    portfolio_returns::Vector{Float64},
    factors::DataFrame,
    portfolio_name::String = "Portfolio",
    period::String = "Unknown Period"
)::AlphaAnalysis
    
    # Calculate raw performance metrics
    returns_decimal = portfolio_returns / 100
    raw_return = mean(returns_decimal) * 12 * 100  # Annualized %
    raw_volatility = std(returns_decimal) * sqrt(12) * 100  # Annualized %
    
    # Calculate Sharpe ratio (assuming RF is average risk-free rate)
    if "RF" in names(factors) && nrow(factors) > 0
        avg_rf = mean(factors.RF)
        raw_sharpe = (raw_return - avg_rf) / raw_volatility
    else
        raw_sharpe = raw_return / raw_volatility  # Assuming RF ≈ 0
    end
    
    # Run regressions
    capm_result = run_capm_regression(portfolio_returns, factors, portfolio_name, period)
    
    ff3_result = run_ff3_regression(portfolio_returns, factors, portfolio_name, period)
    
    ff5_result = run_ff5_regression(portfolio_returns, factors, portfolio_name, period)
    
    # Determine best model (highest R-squared among available models)
    available_results = [capm_result]
    if ff3_result !== nothing
        push!(available_results, ff3_result)
    end
    if ff5_result !== nothing
        push!(available_results, ff5_result)
    end
    
    best_result = available_results[argmax([r.r_squared for r in available_results])]
    best_model = best_result.model
    
    # Novy-Marx conclusion based on alpha significance
    # The key insight: if alpha is not significant after controlling for factors,
    # then the anomaly doesn't provide independent predictive power
    novy_marx_conclusion = if best_result.alpha_pvalue > 0.05
        if best_result.model == "CAPM"
            "SUPPORTS Novy-Marx: No significant alpha after CAPM adjustment"
        elseif best_result.model == "FF3"
            "STRONGLY SUPPORTS Novy-Marx: No significant alpha after FF3 adjustment"  
        else  # FF5
            "VERY STRONGLY SUPPORTS Novy-Marx: No significant alpha after FF5 adjustment"
        end
    else
        if best_result.model == "CAPM"
            "WEAK EVIDENCE against Novy-Marx: Significant alpha remains after CAPM"
        elseif best_result.model == "FF3"
            "CONTRADICTS Novy-Marx: Significant alpha remains after FF3 adjustment"
        else  # FF5
            "STRONGLY CONTRADICTS Novy-Marx: Significant alpha remains after FF5 adjustment"
        end
    end
    
    return AlphaAnalysis(
        portfolio_name,
        period,
        raw_return,
        raw_volatility, 
        raw_sharpe,
        capm_result,
        ff3_result,
        ff5_result,
        best_model,
        novy_marx_conclusion
    )
end

"""
Print comprehensive summary of regression results
"""
function summarize_regression_results(result::RegressionResult)
    println("\n📊 $(result.model) REGRESSION RESULTS")
    println("Portfolio: $(result.portfolio_name)")
    println("Period: $(result.period)")
    println("=" ^ 60)
    
    println(@sprintf("%-20s %10.3f%% (t=%.2f, p=%.3f)", 
            "Alpha (annual):", result.alpha, result.alpha_tstat, result.alpha_pvalue))
    
    for (i, factor) in enumerate(result.factor_names)
        println(@sprintf("%-20s %10.4f  (t=%.2f, p=%.3f)", 
                "β_$factor:", result.betas[i], result.beta_tstats[i], result.beta_pvalues[i]))
    end
    
    println(@sprintf("%-20s %10.3f", "R-squared:", result.r_squared))
    println(@sprintf("%-20s %10.3f", "Adj R-squared:", result.adj_r_squared))
    println(@sprintf("%-20s %10d", "Observations:", result.n_obs))
    
    # Significance interpretation
    if result.alpha_pvalue < 0.01
        println("🔥 Alpha highly significant (p < 0.01)")
    elseif result.alpha_pvalue < 0.05
        println("⚡ Alpha significant (p < 0.05)")
    elseif result.alpha_pvalue < 0.10
        println("⚠️  Alpha marginally significant (p < 0.10)")
    else
        println("✅ Alpha not significant (p ≥ 0.10)")
    end
end

"""
Print comprehensive alpha analysis summary
"""
function summarize_alpha_analysis(analysis::AlphaAnalysis)
    println("\n🎯 COMPREHENSIVE ALPHA ANALYSIS")
    println("Portfolio: $(analysis.portfolio_name)")
    println("Period: $(analysis.period)")
    println("=" ^ 70)
    
    # Raw performance
    println("\n📈 RAW PERFORMANCE:")
    println(@sprintf("   Return:      %8.2f%% annual", analysis.raw_return))
    println(@sprintf("   Volatility:  %8.2f%% annual", analysis.raw_volatility))
    println(@sprintf("   Sharpe:      %8.3f", analysis.raw_sharpe))
    
    # Model comparisons
    println("\n🔬 FACTOR-ADJUSTED PERFORMANCE:")
    
    println(@sprintf("   %-8s Alpha: %7.2f%% (t=%.2f, p=%.3f, R²=%.3f)", 
            "CAPM:", analysis.capm_result.alpha, 
            analysis.capm_result.alpha_tstat, analysis.capm_result.alpha_pvalue,
            analysis.capm_result.r_squared))
    
    if analysis.ff3_result !== nothing
        println(@sprintf("   %-8s Alpha: %7.2f%% (t=%.2f, p=%.3f, R²=%.3f)", 
                "FF3:", analysis.ff3_result.alpha, 
                analysis.ff3_result.alpha_tstat, analysis.ff3_result.alpha_pvalue,
                analysis.ff3_result.r_squared))
    end
    
    if analysis.ff5_result !== nothing
        println(@sprintf("   %-8s Alpha: %7.2f%% (t=%.2f, p=%.3f, R²=%.3f)", 
                "FF5:", analysis.ff5_result.alpha, 
                analysis.ff5_result.alpha_tstat, analysis.ff5_result.alpha_pvalue,
                analysis.ff5_result.r_squared))
    end
    
    println("\n🏆 BEST MODEL: $(analysis.best_model)")
    
    println("\n🧪 NOVY-MARX CONCLUSION:")
    println("   $(analysis.novy_marx_conclusion)")
    
    # Academic interpretation
    println("\n📚 ACADEMIC INTERPRETATION:")
    if contains(analysis.novy_marx_conclusion, "SUPPORTS")
        println("   The anomaly appears to be explained by systematic risk factors.")
        println("   This supports Novy-Marx's critique that apparent anomalies often")
        println("   disappear when proper factor controls are applied.")
    else
        println("   The anomaly generates significant alpha even after factor adjustment.")
        println("   This contradicts Novy-Marx's critique and suggests a genuine")
        println("   market inefficiency that survives rigorous testing.")
    end
end

end