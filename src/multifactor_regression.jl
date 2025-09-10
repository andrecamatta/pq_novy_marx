# Multifactor Regression Module for Novy-Marx Methodology
# Implements CAPM, Fama-French 3-factor and 5-factor models
# Tests portfolio alphas instead of raw returns for academic rigor

module MultifactorRegression

using DataFrames, Dates, Statistics, LinearAlgebra, Printf
using GLM, StatsBase, Distributions

export RegressionResult, run_capm_regression, run_ff3_regression, run_ff5_regression
export grs_test, calculate_newey_west_se, run_robust_regression, summarize_regression_results
export AlphaAnalysis, analyze_portfolio_alphas, summarize_alpha_analysis
export run_capm_regression_aligned, run_ff3_regression_aligned, run_ff5_regression_aligned
export calculate_sharpe_ratio_corrected, grs_test_full
export analyze_portfolio_alphas_aligned

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
Comprehensive analysis of portfolio alphas using aligned data (Date join).
Uses CAPM, FF3, FF5 aligned regressions and correct Sharpe calculation.

Parâmetros:
- portfolios_df: DataFrame com colunas :Date e uma coluna de retorno (%) do portfólio
- factors_df: DataFrame Fama-French com :Date, MKT_RF, SMB, HML, RMW, CMA, RF
- portfolio_col: nome da coluna do portfólio (ex.: "LowMinusHigh")
- portfolio_name: rótulo do portfólio
"""
function analyze_portfolio_alphas_aligned(
    portfolios_df::DataFrame,
    factors_df::DataFrame,
    portfolio_col::String,
    portfolio_name::String = portfolio_col
)::AlphaAnalysis
    # Alinhar por Date e remover missings
    @assert "Date" in names(portfolios_df) "portfolios_df precisa da coluna Date"
    @assert "Date" in names(factors_df) "factors_df precisa da coluna Date"
    @assert portfolio_col in names(portfolios_df) "Coluna do portfólio não encontrada: $portfolio_col"

    merged = innerjoin(portfolios_df, factors_df, on=:Date)
    complete = .!ismissing.(merged[!, portfolio_col]) .& .!ismissing.(merged[!, :RF])
    df = merged[complete, :]
    if nrow(df) < 12
        error("Dados insuficientes após alinhamento: $(nrow(df)) observações")
    end

    # Performance bruta (anualizada) - remover missing values
    rets_raw = df[!, portfolio_col]
    valid_idx = .!ismissing.(rets_raw)
    
    if sum(valid_idx) < 12
        error("Dados insuficientes: apenas $(sum(valid_idx)) observações válidas")
    end
    
    rets = collect(skipmissing(rets_raw)) ./ 100
    raw_return = mean(rets) * 12 * 100
    raw_volatility = std(rets) * sqrt(12) * 100
    
    # Sharpe usando apenas observações válidas  
    portfolio_valid = collect(skipmissing(df[valid_idx, portfolio_col]))
    rf_valid = df[valid_idx, :RF]
    _, raw_sharpe_annual = calculate_sharpe_ratio_corrected(portfolio_valid, rf_valid)

    # Regressões alinhadas
    capm = run_capm_regression_aligned(portfolios_df, factors_df, portfolio_col,
        portfolio_name=portfolio_name, robust=false)
    ff3 = run_ff3_regression_aligned(portfolios_df, factors_df, portfolio_col,
        portfolio_name=portfolio_name, robust=false)
    ff5 = run_ff5_regression_aligned(portfolios_df, factors_df, portfolio_col,
        portfolio_name=portfolio_name, robust=false)

    # Selecionar melhor modelo por R²
    results = [capm]
    if ff3 !== nothing; push!(results, ff3); end
    if ff5 !== nothing; push!(results, ff5); end
    best = results[argmax(getfield.(results, :r_squared))]
    best_model = best.model

    conclusion = if best.alpha_pvalue > 0.05
        best_model == "CAPM" ? "SUPPORTS Novy-Marx: No significant alpha after CAPM" :
        best_model == "FF3"  ? "STRONGLY SUPPORTS Novy-Marx: No alpha after FF3" :
                                "VERY STRONGLY SUPPORTS Novy-Marx: No alpha after FF5"
    else
        best_model == "CAPM" ? "WEAK EVIDENCE against Novy-Marx: Alpha after CAPM" :
        best_model == "FF3"  ? "CONTRADICTS Novy-Marx: Alpha after FF3" :
                                "STRONGLY CONTRADICTS Novy-Marx: Alpha after FF5"
    end

    return AlphaAnalysis(
        portfolio_name,
        "$(minimum(df.Date)) - $(maximum(df.Date))",
        raw_return,
        raw_volatility,
        raw_sharpe_annual,
        capm,
        ff3,
        ff5,
        best_model,
        conclusion
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

"""
Calculate Newey-West robust standard errors for time series regression.
Accounts for both heteroskedasticity and autocorrelation in residuals.

Parameters:
- y: Dependent variable vector
- X: Matrix of independent variables (including intercept column)
- lags: Number of lags to account for autocorrelation (default: 3)

Returns:
- robust_se: Vector of robust standard errors for each coefficient
"""
function calculate_newey_west_se(y::Vector{Float64}, X::Matrix{Float64}; lags::Int = 3)::Vector{Float64}
    
    n, k = size(X)
    
    # OLS estimation
    XtX_inv = inv(X' * X)
    beta = XtX_inv * (X' * y)
    residuals = y - X * beta
    
    # Initialize Newey-West covariance matrix
    S = zeros(k, k)
    
    # Add contemporaneous component (j=0)
    for i in 1:n
        xi_ei = X[i, :] * residuals[i]
        S += xi_ei * xi_ei'
    end
    
    # Add autocovariance components (j=1 to lags)
    for j in 1:lags
        weight = 1 - j / (lags + 1)  # Bartlett kernel weights
        
        # Forward autocovariance
        Sj = zeros(k, k)
        for i in (j+1):n
            xi_ei = X[i, :] * residuals[i]
            xi_minus_j_ei_minus_j = X[i-j, :] * residuals[i-j]
            Sj += xi_ei * xi_minus_j_ei_minus_j'
        end
        
        # Add symmetric component (forward + backward)
        S += weight * (Sj + Sj')
    end
    
    # Newey-West covariance matrix
    V_nw = XtX_inv * S * XtX_inv / n
    
    # Extract standard errors (diagonal elements)
    robust_se = sqrt.(diag(V_nw))
    
    return robust_se
end

"""
Enhanced regression function with Newey-West robust standard errors option.
"""
function run_robust_regression(
    y::Vector{Float64},
    X::Matrix{Float64},
    factor_names::Vector{String},
    model_name::String,
    portfolio_name::String,
    period::String;
    robust::Bool = false,
    lags::Int = 3
)::RegressionResult
    
    n, k = size(X)
    
    # OLS estimation
    XtX_inv = inv(X' * X)
    beta = XtX_inv * (X' * y)
    fitted = X * beta
    residuals = y - fitted
    
    # Calculate R-squared
    y_mean = mean(y)
    tss = sum((y .- y_mean).^2)
    rss = sum(residuals.^2)
    r_squared = 1 - rss / tss
    adj_r_squared = 1 - (rss / (n - k)) / (tss / (n - 1))
    
    # Calculate standard errors
    if robust
        se = calculate_newey_west_se(y, X, lags=lags)
    else
        # Standard OLS standard errors
        sigma_squared = rss / (n - k)
        se = sqrt.(diag(XtX_inv * sigma_squared))
    end
    
    # Calculate t-statistics and p-values
    t_stats = beta ./ se
    p_values = 2 .* (1 .- cdf.(TDist(n - k), abs.(t_stats)))
    
    # Annualize alpha (first coefficient is intercept) in %
    alpha_annual = beta[1] * 12 * 100
    
    return RegressionResult(
        model_name,
        alpha_annual,
        t_stats[1],
        p_values[1],
        beta[2:end],      # Exclude intercept from betas
        t_stats[2:end],   # Exclude intercept from beta t-stats
        p_values[2:end],  # Exclude intercept from beta p-values
        r_squared,
        adj_r_squared,
        residuals .* 100,
        n,
        factor_names,
        period,
        portfolio_name
    )
end

"""
Convenience OLS used in examples/tests: regress monthly excess returns y (%) on factor columns (%).
Returns a Dict with monthly alpha (decimal), t-stats, p-values, R² and coefficients.
Assumes y and factors_df are already time-aligned.
"""
function run_regression(y::Vector{Float64}, factors_df::DataFrame, factor_cols::Vector{String})::Dict{String,Any}
    n = length(y)
    if n == 0
        error("Vetor de retornos vazio")
    end
    # Normalize factor column names
    available = Set(Symbol.(names(factors_df)))
    cols_syms = Symbol[]
    for c in factor_cols
        s = Symbol(c)
        if s in available
            push!(cols_syms, s)
        else
            alt = Symbol(uppercase(replace(c, "Mkt_RF"=>"MKT_RF")))
            if alt in available
                push!(cols_syms, alt)
            else
                error("Fator não encontrado: $c. Disponíveis: $(join(names(factors_df), ", "))")
            end
        end
    end
    if nrow(factors_df) != n
        min_n = min(nrow(factors_df), n)
        y = y[1:min_n]
        factors_df = factors_df[1:min_n, :]
        n = min_n
    end
    # Build matrices in decimals
    y_dec = y ./ 100
    X = ones(n)
    for s in cols_syms
        X = [X factors_df[!, s] ./ 100]
    end
    k = size(X,2)
    β = (X'X) \ (X'y_dec)
    fitted = X * β
    resid = y_dec - fitted
    rss = sum(resid.^2)
    tss = sum((y_dec .- mean(y_dec)).^2)
    dof = n - k
    σ² = rss / dof
    vcov = σ² * inv(X'X)
    se = sqrt.(diag(vcov))
    tstats = β ./ se
    pvals = 2 .* (1 .- cdf.(TDist(dof), abs.(tstats)))
    r2 = 1 - rss/tss
    return Dict(
        "alpha" => β[1],
        "alpha_se" => se[1],
        "alpha_t" => tstats[1],
        "alpha_pval" => pvals[1],
        "coefficients" => β[2:end],
        "r_squared" => r2
    )
end

"""
Robust (Newey-West) version used in examples: same inputs as run_regression.
Returns Dict with robust alpha t-stat and p-value; alpha remains monthly decimal.
"""
function run_robust_regression(y::Vector{Float64}, factors_df::DataFrame, factor_cols::Vector{String}; lags::Int = 3)::Dict{String,Any}
    n = length(y)
    if n == 0
        error("Vetor de retornos vazio")
    end
    # Normalize factor names
    available = Set(Symbol.(names(factors_df)))
    cols_syms = Symbol[]
    for c in factor_cols
        s = Symbol(c)
        if s in available
            push!(cols_syms, s)
        else
            alt = Symbol(uppercase(replace(c, "Mkt_RF"=>"MKT_RF")))
            if alt in available
                push!(cols_syms, alt)
            else
                error("Fator não encontrado: $c. Disponíveis: $(join(names(factors_df), ", "))")
            end
        end
    end
    if nrow(factors_df) != n
        min_n = min(nrow(factors_df), n)
        y = y[1:min_n]
        factors_df = factors_df[1:min_n, :]
        n = min_n
    end
    y_dec = y ./ 100
    X = ones(n)
    for s in cols_syms
        X = [X factors_df[!, s] ./ 100]
    end
    β = (X'X) \ (X'y_dec)
    se_nw = calculate_newey_west_se(y_dec, Matrix{Float64}(X), lags=lags)
    dof = n - size(X,2)
    t_alpha = β[1] / se_nw[1]
    p_alpha = 2 * (1 - cdf(TDist(dof), abs(t_alpha)))
    return Dict(
        "alpha" => β[1],
        "alpha_t_robust" => t_alpha,
        "alpha_pval_robust" => p_alpha
    )
end

"""
Run CAPM regression with proper date alignment using innerjoin.
Corrects the issue of aligning by length instead of by date.

# Argumentos
- `portfolios_df`: DataFrame com colunas Date e retornos dos portfolios
- `factors_df`: DataFrame com fatores Fama-French (colunas Date, MKT_RF, RF, etc.)
- `portfolio_col`: Nome da coluna de retorno do portfolio (e.g., "LowMinusHigh")
- `robust`: Se true, usar Newey-West standard errors
- `lags`: Número de lags para Newey-West
"""
function run_capm_regression_aligned(
    portfolios_df::DataFrame,
    factors_df::DataFrame,
    portfolio_col::String;
    portfolio_name::String = portfolio_col,
    robust::Bool = false,
    lags::Int = 3
)::Union{RegressionResult, Nothing}
    
    # 1. ALINHAMENTO POR DATA usando innerjoin
    if !("Date" in names(portfolios_df)) || !("Date" in names(factors_df))
        error("Ambos DataFrames devem ter coluna 'Date'")
    end
    
    # Verificar colunas necessárias
    if !(portfolio_col in names(portfolios_df))
        error("Coluna '$portfolio_col' não encontrada no DataFrame de portfolios")
    end
    
    required_factors = ["MKT_RF", "RF"]
    missing_factors = [f for f in required_factors if !(f in names(factors_df))]
    if !isempty(missing_factors)
        @warn "CAPM: fatores ausentes: $missing_factors"
        return nothing
    end
    
    # Inner join por Date - CORREÇÃO CRÍTICA
    merged_df = innerjoin(portfolios_df, factors_df, on = :Date)
    
    if nrow(merged_df) == 0
        @warn "Nenhuma data comum encontrada entre portfolios e fatores"
        return nothing
    end
    
    # 2. REMOVER MISSING VALUES (nunca preencher com zero)
    complete_rows = .!ismissing.(merged_df[!, portfolio_col]) .& 
                   .!ismissing.(merged_df[!, :MKT_RF]) .& 
                   .!ismissing.(merged_df[!, :RF])
    
    clean_df = merged_df[complete_rows, :]
    
    if nrow(clean_df) < 12
        @warn "Dados insuficientes após remover missing: $(nrow(clean_df)) observações"
        return nothing
    end
    
    # 3. CALCULAR EXCESS RETURNS em decimais
    portfolio_returns = clean_df[!, portfolio_col] / 100  # % para decimal
    rf = clean_df[!, :RF] / 100
    mkt_rf = clean_df[!, :MKT_RF] / 100
    
    excess_returns = portfolio_returns .- rf  # Excess return em decimais
    
    # 4. MATRIZ DE DESIGN
    X = [ones(length(mkt_rf)) mkt_rf]
    y = excess_returns
    
    # 5. REGRESSÃO (OLS ou Robust)
    if robust
        result = run_robust_regression(
            y, X, ["MKT_RF"], "CAPM", portfolio_name, 
            "$(minimum(clean_df.Date)) - $(maximum(clean_df.Date))",
            robust=true, lags=lags
        )
    else
        result = run_robust_regression(
            y, X, ["MKT_RF"], "CAPM", portfolio_name,
            "$(minimum(clean_df.Date)) - $(maximum(clean_df.Date))", 
            robust=false, lags=lags
        )
    end
    
    return result
end

"""
Run FF3 regression with proper date alignment.
"""
function run_ff3_regression_aligned(
    portfolios_df::DataFrame,
    factors_df::DataFrame, 
    portfolio_col::String;
    portfolio_name::String = portfolio_col,
    robust::Bool = false,
    lags::Int = 3
)::Union{RegressionResult, Nothing}
    
    # 1. ALINHAMENTO POR DATA
    if !("Date" in names(portfolios_df)) || !("Date" in names(factors_df))
        error("Ambos DataFrames devem ter coluna 'Date'")
    end
    
    if !(portfolio_col in names(portfolios_df))
        error("Coluna '$portfolio_col' não encontrada")
    end
    
    required_factors = ["MKT_RF", "SMB", "HML", "RF"]  
    missing_factors = [f for f in required_factors if !(f in names(factors_df))]
    if !isempty(missing_factors)
        @warn "FF3: fatores ausentes: $missing_factors"
        return nothing
    end
    
    # Inner join por Date
    merged_df = innerjoin(portfolios_df, factors_df, on = :Date)
    
    if nrow(merged_df) == 0
        @warn "Nenhuma data comum encontrada"
        return nothing
    end
    
    # 2. REMOVER MISSING VALUES
    complete_rows = .!ismissing.(merged_df[!, portfolio_col]) .& 
                   .!ismissing.(merged_df[!, :MKT_RF]) .&
                   .!ismissing.(merged_df[!, :SMB]) .&
                   .!ismissing.(merged_df[!, :HML]) .&
                   .!ismissing.(merged_df[!, :RF])
    
    clean_df = merged_df[complete_rows, :]
    
    if nrow(clean_df) < 12
        @warn "Dados insuficientes: $(nrow(clean_df)) observações"
        return nothing
    end
    
    # 3. EXCESS RETURNS em decimais
    portfolio_returns = clean_df[!, portfolio_col] / 100
    rf = clean_df[!, :RF] / 100
    excess_returns = portfolio_returns .- rf
    
    # 4. FATORES em decimais
    mkt_rf = clean_df[!, :MKT_RF] / 100
    smb = clean_df[!, :SMB] / 100
    hml = clean_df[!, :HML] / 100
    
    # 5. MATRIZ DE DESIGN
    X = [ones(length(mkt_rf)) mkt_rf smb hml]
    y = excess_returns
    
    # 6. REGRESSÃO
    result = run_robust_regression(
        y, X, ["MKT_RF", "SMB", "HML"], "FF3", portfolio_name,
        "$(minimum(clean_df.Date)) - $(maximum(clean_df.Date))",
        robust=robust, lags=lags
    )
    
    return result
end

"""
Run FF5 regression with proper date alignment.
"""
function run_ff5_regression_aligned(
    portfolios_df::DataFrame,
    factors_df::DataFrame,
    portfolio_col::String;
    portfolio_name::String = portfolio_col, 
    robust::Bool = false,
    lags::Int = 3
)::Union{RegressionResult, Nothing}
    
    # 1. ALINHAMENTO POR DATA  
    if !("Date" in names(portfolios_df)) || !("Date" in names(factors_df))
        error("Ambos DataFrames devem ter coluna 'Date'")
    end
    
    if !(portfolio_col in names(portfolios_df))
        error("Coluna '$portfolio_col' não encontrada")
    end
    
    required_factors = ["MKT_RF", "SMB", "HML", "RMW", "CMA", "RF"]
    missing_factors = [f for f in required_factors if !(f in names(factors_df))]
    if !isempty(missing_factors)
        @warn "FF5: fatores ausentes: $missing_factors" 
        return nothing
    end
    
    # Inner join por Date
    merged_df = innerjoin(portfolios_df, factors_df, on = :Date)
    
    if nrow(merged_df) == 0
        @warn "Nenhuma data comum encontrada"
        return nothing
    end
    
    # 2. REMOVER MISSING VALUES
    complete_rows = .!ismissing.(merged_df[!, portfolio_col]) .&
                   .!ismissing.(merged_df[!, :MKT_RF]) .&
                   .!ismissing.(merged_df[!, :SMB]) .&
                   .!ismissing.(merged_df[!, :HML]) .&
                   .!ismissing.(merged_df[!, :RMW]) .&
                   .!ismissing.(merged_df[!, :CMA]) .&
                   .!ismissing.(merged_df[!, :RF])
    
    clean_df = merged_df[complete_rows, :]
    
    if nrow(clean_df) < 12
        @warn "Dados insuficientes: $(nrow(clean_df)) observações"
        return nothing
    end
    
    # 3. EXCESS RETURNS em decimais
    portfolio_returns = clean_df[!, portfolio_col] / 100
    rf = clean_df[!, :RF] / 100
    excess_returns = portfolio_returns .- rf
    
    # 4. FATORES em decimais
    mkt_rf = clean_df[!, :MKT_RF] / 100
    smb = clean_df[!, :SMB] / 100
    hml = clean_df[!, :HML] / 100
    rmw = clean_df[!, :RMW] / 100
    cma = clean_df[!, :CMA] / 100
    
    # 5. MATRIZ DE DESIGN
    X = [ones(length(mkt_rf)) mkt_rf smb hml rmw cma]
    y = excess_returns
    
    # 6. REGRESSÃO
    result = run_robust_regression(
        y, X, ["MKT_RF", "SMB", "HML", "RMW", "CMA"], "FF5", portfolio_name,
        "$(minimum(clean_df.Date)) - $(maximum(clean_df.Date))",
        robust=robust, lags=lags
    )
    
    return result
end

"""
Calcula Sharpe ratio correto seguindo especificação Novy-Marx.
# Argumentos
- `portfolio_returns`: Retornos mensais do portfolio em % (ex: [1.2, -0.8, 2.1])
- `risk_free_returns`: Retornos mensais RF em % (ex: [0.1, 0.1, 0.1])  
# Retorna
- `sharpe_monthly`: Sharpe mensal
- `sharpe_annual`: Sharpe anualizado (mensal * sqrt(12))
"""
function calculate_sharpe_ratio_corrected(
    portfolio_returns::Vector{Float64}, 
    risk_free_returns::Vector{Float64}
)::Tuple{Float64, Float64}
    
    if length(portfolio_returns) != length(risk_free_returns)
        error("Portfolio e RF devem ter o mesmo número de observações")
    end
    
    # Converter para decimais
    portfolio_dec = portfolio_returns / 100
    rf_dec = risk_free_returns / 100
    
    # Calcular excess returns em decimais
    excess_returns = portfolio_dec .- rf_dec
    
    # Sharpe mensal
    mean_excess = mean(excess_returns)
    std_excess = std(excess_returns)
    
    sharpe_monthly = mean_excess / std_excess
    
    # Anualizar
    sharpe_annual = sharpe_monthly * sqrt(12)
    
    return sharpe_monthly, sharpe_annual
end

"""
Versão para DataFrames com alinhamento automático por Date.
"""
function calculate_sharpe_ratio_corrected(
    portfolios_df::DataFrame,
    factors_df::DataFrame, 
    portfolio_col::String
)::Tuple{Float64, Float64}
    
    # Alinhamento por data
    if !("Date" in names(portfolios_df)) || !("Date" in names(factors_df))
        error("Ambos DataFrames devem ter coluna 'Date'")
    end
    
    if !("RF" in names(factors_df))
        error("Fatores devem conter coluna 'RF'")
    end
    
    # Inner join e remoção de missing
    merged_df = innerjoin(portfolios_df, factors_df, on = :Date)
    complete_rows = .!ismissing.(merged_df[!, portfolio_col]) .& .!ismissing.(merged_df[!, :RF])
    clean_df = merged_df[complete_rows, :]
    
    if nrow(clean_df) < 12
        @warn "Dados insuficientes para Sharpe: $(nrow(clean_df)) observações"
        return NaN, NaN
    end
    
    # Calcular Sharpe (garantir tipos corretos)
    portfolio_rets = Vector{Float64}(clean_df[!, portfolio_col])
    rf_rets = Vector{Float64}(clean_df[!, :RF])
    
    return calculate_sharpe_ratio_corrected(portfolio_rets, rf_rets)
end

"""
Implementa GRS test completo seguindo fórmula exata da especificação.
Testa H₀: todos os alfas são zero vs H₁: pelo menos um alfa ≠ 0

Fórmula: F = ((T - N - K) / N) × (1 + μ_f' Σ_f^{-1} μ_f)^{-1} × α' Σ_ε^{-1} α
onde:
- T = número de observações temporais
- N = número de portfólios 
- K = número de fatores
- μ_f = média dos fatores (K×1)
- Σ_f = covariância dos fatores (K×K)
- α = vetor de alfas (N×1) 
- Σ_ε = covariância dos resíduos (N×N)

# Argumentos
- `results`: Vetor de RegressionResult (mesmo modelo para todos)
- `factors_df`: DataFrame com fatores alinhados temporalmente
- `model`: Modelo usado (:CAPM, :FF3, :FF5)
- `alpha_level`: Nível de significância (default: 0.05)
"""
function grs_test_full(
    results::Vector{RegressionResult},
    factors_df::DataFrame;
    model::Symbol = :FF5,
    alpha_level::Float64 = 0.05
)::Dict{Symbol, Any}
    
    if isempty(results)
        error("Vetor de resultados vazio")
    end
    
    # Validar que todos são do mesmo modelo
    if !all(r.model == string(model) for r in results)
        error("Todos os resultados devem ser do mesmo modelo: $model")
    end
    
    N = length(results)  # Número de portfólios
    T = results[1].n_obs  # Número de observações temporais
    
    # Verificar consistência temporal
    if !all(r.n_obs == T for r in results)
        error("Todos os portfólios devem ter o mesmo número de observações temporais")
    end
    
    # Definir fatores por modelo
    factor_columns = if model == :CAPM
        ["MKT_RF"]
    elseif model == :FF3
        ["MKT_RF", "SMB", "HML"]
    elseif model == :FF5  
        ["MKT_RF", "SMB", "HML", "RMW", "CMA"]
    else
        error("Modelo não suportado: $model")
    end
    
    K = length(factor_columns)
    
    # Verificar que fatores existem
    missing_factors = [f for f in factor_columns if !(f in names(factors_df))]
    if !isempty(missing_factors)
        error("Fatores ausentes: $missing_factors")
    end
    
    if nrow(factors_df) != T
        error("Número de observações nos fatores ($(nrow(factors_df))) ≠ regressões ($T)")
    end
    
    # Graus de liberdade
    if T - N - K <= 0
        error("Graus de liberdade insuficientes: T=$T, N=$N, K=$K → df=$(T-N-K)")
    end
    
    println("📊 GRS Test Completo:")
    println("   Modelo: $model")
    println("   Portfólios: $N")
    println("   Fatores: $K ($(join(factor_columns, ", ")))")
    println("   Observações: $T")
    println("   Graus liberdade: $(T-N-K)")
    
    try
        # 1. VETOR DE ALFAS (N×1) - converter para decimais mensais
        α = [r.alpha / 100 / 12 for r in results]  # Anualizado % → mensal decimal
        
        # 2. MÉDIA DOS FATORES (K×1) - converter para decimais
        factor_matrix = Matrix{Float64}(factors_df[!, factor_columns]) / 100  # % → decimal
        μ_f = vec(mean(factor_matrix, dims=1))
        
        # 3. COVARIÂNCIA DOS FATORES (K×K)
        Σ_f = cov(factor_matrix)
        
        # Regularização se singular
        if det(Σ_f) ≈ 0
            println("   ⚠️ Σ_f singular, aplicando regularização...")
            Σ_f += I * 1e-8
        end
        
        # 4. MATRIZ DE RESÍDUOS (T×N) - converter para decimais
        residuals_matrix = hcat([r.residuals / 100 for r in results]...)  # % → decimal
        
        # 5. COVARIÂNCIA DOS RESÍDUOS (N×N)
        Σ_ε = cov(residuals_matrix, dims=1)
        
        # Regularização se singular
        if det(Σ_ε) ≈ 0
            println("   ⚠️ Σ_ε singular, aplicando regularização...")
            Σ_ε += I * 1e-8
        end
        
        # 6. CÁLCULO DA ESTATÍSTICA F
        # Termo 1: ((T - N - K) / N)
        term1 = (T - N - K) / N
        
        # Termo 2: (1 + μ_f' Σ_f^{-1} μ_f)^{-1}
        μf_Σf_inv_μf = μ_f' * inv(Σ_f) * μ_f
        term2 = 1 / (1 + μf_Σf_inv_μf)
        
        # Termo 3: α' Σ_ε^{-1} α
        term3 = α' * inv(Σ_ε) * α
        
        # Estatística F completa
        F_stat = term1 * term2 * term3
        
        println("   🔍 Componentes:")
        println("      Term1 ($(T-N-K)/$N): $(round(term1, digits=4))")
        println("      Term2 (factor adj): $(round(term2, digits=4))") 
        println("      Term3 (α'Σ⁻¹α): $(round(term3, digits=6))")
        println("      F-statistic: $(round(F_stat, digits=4))")
        
        # 7. DISTRIBUIÇÃO F(N, T-N-K) e p-valor
        f_dist = FDist(N, T - N - K)
        p_value = 1 - cdf(f_dist, F_stat)
        critical_value = quantile(f_dist, 1 - alpha_level)
        
        # 8. CONCLUSÃO
        is_significant = F_stat > critical_value
        conclusion = if is_significant
            "REJEITA H₀: Pelo menos um alfa é significativamente diferente de zero (nível $alpha_level)"
        else
            "FALHA EM REJEITAR H₀: Todos os alfas são estatisticamente zero (nível $alpha_level)"
        end
        
        println("   📈 Resultado:")
        println("      F-crítico: $(round(critical_value, digits=4))")
        println("      p-valor: $(round(p_value, digits=6))")
        println("      Significativo: $(is_significant ? "SIM" : "NÃO")")
        println("   🎯 $conclusion")
        
        return Dict{Symbol, Any}(
            :model => model,
            :n_portfolios => N,
            :n_factors => K,
            :n_obs => T,
            :degrees_of_freedom => T - N - K,
            :F_statistic => F_stat,
            :critical_value => critical_value,
            :p_value => p_value,
            :is_significant => is_significant,
            :conclusion => conclusion,
            :alpha_level => alpha_level,
            :factor_names => factor_columns,
            # Componentes para auditoria
            :alpha_vector => α,
            :factor_means => μ_f,
            :factor_cov_term => μf_Σf_inv_μf,
            :term1 => term1,
            :term2 => term2, 
            :term3 => term3
        )
        
    catch e
        @error "Erro no cálculo do GRS test completo" exception=e
        return Dict{Symbol, Any}(
            :model => model,
            :error => string(e),
            :conclusion => "ERRO: Não foi possível calcular o teste GRS",
            :is_significant => false,
            :p_value => NaN
        )
    end
end

end
