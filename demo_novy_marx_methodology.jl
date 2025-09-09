# Demonstration of Novy-Marx Methodology
# Uses synthetic data to show the complete framework
# Tests factor-adjusted alphas instead of raw returns

using DataFrames, Dates, Statistics, Random, Printf, Distributions

println("🧪 NOVY-MARX METHODOLOGY DEMONSTRATION")
println("=" ^ 60)
println("Synthetic data example showing academic approach")
println("Testing factor-adjusted alphas vs raw returns\\n")

try
    # Import required modules
    include("src/utils/fama_french_factors.jl")
    include("src/utils/multifactor_regression.jl")
    
    using .FamaFrenchFactors
    using .MultifactorRegression
    
    println("✅ Modules imported successfully")
    
    # Download real Fama-French factors
    println("\\n📥 DOWNLOADING REAL FACTORS")
    println("-" ^ 40)
    
    factors = download_fama_french_factors(Date(2020, 1, 1), Date(2023, 12, 31), verbose=false)
    println("📊 Downloaded $(nrow(factors)) monthly factor observations")
    println("📅 Data range: $(minimum(factors.Date)) to $(maximum(factors.Date))")
    
    # Generate synthetic portfolios with known characteristics
    println("\\n🔬 GENERATING SYNTHETIC PORTFOLIOS")
    println("-" ^ 50)
    
    Random.seed!(42)
    n_obs = nrow(factors)
    
    # Convert factors to decimal
    mkt_rf = factors.MKT_RF / 100
    smb = factors.SMB / 100  
    hml = factors.HML / 100
    rf = factors.RF / 100
    
    # Portfolio 1: Low Vol (should have low alpha after factor adjustment)
    # True characteristics: beta=0.7, slight SMB exposure
    low_vol_returns = (
        0.02 .+                      # Small true alpha (0.2% monthly)
        0.7 .* mkt_rf .+            # Low market beta
        0.1 .* smb .+               # Slight small-cap tilt
        randn(n_obs) .* 0.015       # Low noise (1.5% monthly volatility)
    ) .* 100 .+ rf .* 100  # Convert to % and add risk-free rate
    
    # Portfolio 2: High Vol (higher alpha, higher systematic risk)
    # True characteristics: beta=1.3, negative SMB (large cap bias)
    high_vol_returns = (
        0.05 .+                      # Higher true alpha (0.5% monthly) 
        1.3 .* mkt_rf .+            # High market beta
        -0.2 .* smb .+              # Large-cap bias
        randn(n_obs) .* 0.04        # High noise (4% monthly volatility)
    ) .* 100 .+ rf .* 100
    
    # Portfolio 3: "Pure Alpha" - should maintain significance after adjustment
    # True characteristics: market neutral with genuine alpha
    pure_alpha_returns = (
        0.08 .+                      # High true alpha (0.8% monthly)
        0.2 .* mkt_rf .+            # Very low market beta (market neutral)
        0.05 .* smb .+              # Minimal SMB exposure
        randn(n_obs) .* 0.025       # Moderate noise
    ) .* 100 .+ rf .* 100
    
    # Long-Short Portfolio (traditional anomaly test)
    long_short_returns = low_vol_returns - high_vol_returns
    
    portfolios = [
        ("Low Volatility", low_vol_returns),
        ("High Volatility", high_vol_returns), 
        ("Long-Short", long_short_returns),
        ("Pure Alpha", pure_alpha_returns)
    ]
    
    println("✅ Generated $(length(portfolios)) synthetic portfolios")
    for (name, returns) in portfolios
        println("   📊 $name: Return=$(round(mean(returns), digits=2))%, Vol=$(round(std(returns), digits=2))%")
    end
    
    # Traditional Analysis (Raw Returns) 
    println("\\n📈 TRADITIONAL ANALYSIS (RAW RETURNS)")
    println("=" ^ 60)
    println("This is what most studies do - test raw return significance")
    println()
    
    traditional_results = []
    for (name, returns) in portfolios
        # Simple t-test of returns vs zero
        mean_ret = mean(returns)
        std_ret = std(returns)
        t_stat = sqrt(n_obs) * mean_ret / std_ret
        p_value = 2 * (1 - cdf(TDist(n_obs-1), abs(t_stat)))
        
        significance = p_value < 0.05 ? "SIGNIFICANT" : "Not Significant"
        
        println("$name:")
        println("   Return: $(round(mean_ret, digits=2))% monthly")
        println("   t-statistic: $(round(t_stat, digits=2))")
        println("   p-value: $(round(p_value, digits=4))")  
        println("   Traditional Conclusion: $significance")
        println()
        
        push!(traditional_results, (name, mean_ret, p_value, significance))
    end
    
    # Novy-Marx Analysis (Factor-Adjusted Alphas)
    println("🧪 NOVY-MARX ANALYSIS (FACTOR-ADJUSTED ALPHAS)")
    println("=" ^ 60)
    println("This is the academically rigorous approach")
    println()
    
    novy_marx_results = []
    alpha_analyses = AlphaAnalysis[]
    
    for (name, returns) in portfolios
        println("🔬 $name:")
        
        # Run comprehensive alpha analysis
        alpha_analysis = analyze_portfolio_alphas(returns, factors, name, "2020-2023")
        push!(alpha_analyses, alpha_analysis)
        
        # Display detailed results
        println("   📊 Raw Performance:")
        println("      Return: $(round(alpha_analysis.raw_return, digits=2))% annual")
        println("      Volatility: $(round(alpha_analysis.raw_volatility, digits=2))% annual")
        println("      Sharpe: $(round(alpha_analysis.raw_sharpe, digits=3))")
        
        println("   🔬 Factor-Adjusted Performance:")
        println("      CAPM Alpha: $(round(alpha_analysis.capm_result.alpha, digits=2))% (t=$(round(alpha_analysis.capm_result.alpha_tstat, digits=2)), p=$(round(alpha_analysis.capm_result.alpha_pvalue, digits=4)))")
        
        if alpha_analysis.ff3_result !== nothing
            println("      FF3 Alpha: $(round(alpha_analysis.ff3_result.alpha, digits=2))% (t=$(round(alpha_analysis.ff3_result.alpha_tstat, digits=2)), p=$(round(alpha_analysis.ff3_result.alpha_pvalue, digits=4)))")
        end
        
        if alpha_analysis.ff5_result !== nothing
            println("      FF5 Alpha: $(round(alpha_analysis.ff5_result.alpha, digits=2))% (t=$(round(alpha_analysis.ff5_result.alpha_tstat, digits=2)), p=$(round(alpha_analysis.ff5_result.alpha_pvalue, digits=4)))")
        end
        
        println("   🏆 Best Model: $(alpha_analysis.best_model)")
        println("   🎯 Novy-Marx Conclusion: $(alpha_analysis.novy_marx_conclusion)")
        println()
        
        push!(novy_marx_results, alpha_analysis)
    end
    
    # GRS Test for Joint Significance
    println("🧪 GRS TEST FOR JOINT ALPHA SIGNIFICANCE")
    println("=" ^ 60)
    
    # Test CAPM alphas jointly
    capm_results = [analysis.capm_result for analysis in alpha_analyses]
    grs_capm = grs_test(capm_results)
    
    if haskey(grs_capm, :error)
        println("CAPM GRS Test: $(grs_capm[:error])")
    else
        println("CAPM GRS Test:")
        println("   F-statistic: $(round(grs_capm[:grs_statistic], digits=3))")
        println("   p-value: $(round(grs_capm[:p_value], digits=4))")
        println("   Conclusion: $(grs_capm[:conclusion])")
    end
    
    # Test FF3 alphas jointly (if available)
    ff3_results = [analysis.ff3_result for analysis in alpha_analyses if analysis.ff3_result !== nothing]
    if length(ff3_results) >= 2
        grs_ff3 = grs_test(ff3_results)
        
        if haskey(grs_ff3, :error)
            println("\\nFF3 GRS Test: $(grs_ff3[:error])")
        else
            println("\\nFF3 GRS Test:")
            println("   F-statistic: $(round(grs_ff3[:grs_statistic], digits=3))")
            println("   p-value: $(round(grs_ff3[:p_value], digits=4))")
            println("   Conclusion: $(grs_ff3[:conclusion])")
        end
    end
    
    # Comparison and Academic Insights
    println("\\n📚 TRADITIONAL VS NOVY-MARX COMPARISON")
    println("=" ^ 70)
    
    println("Traditional Analysis (Raw Returns):")
    significant_traditional = sum([result[4] == "SIGNIFICANT" for result in traditional_results])
    println("   Portfolios with significant raw returns: $significant_traditional / $(length(traditional_results))")
    
    println("\\nNovy-Marx Analysis (Factor-Adjusted Alphas):")
    significant_alphas = sum([
        (analysis.best_model == "CAPM" ? analysis.capm_result.alpha_pvalue : 
         analysis.best_model == "FF3" ? analysis.ff3_result.alpha_pvalue : 
         analysis.ff5_result.alpha_pvalue) < 0.05 
        for analysis in alpha_analyses
    ])
    println("   Portfolios with significant alphas: $significant_alphas / $(length(alpha_analyses))")
    
    println("\\n🎯 KEY INSIGHTS:")
    
    if significant_traditional > significant_alphas
        println("   ✅ DEMONSTRATES NOVY-MARX CRITIQUE:")
        println("      • Traditional analysis finds more 'significant' results")
        println("      • Factor adjustment reveals many are not genuine anomalies")
        println("      • Apparent outperformance explained by systematic risk factors")
        println("      • This supports academic skepticism about anomaly robustness")
    else
        println("   🚨 CONTRADICTS NOVY-MARX CRITIQUE:")
        println("      • Factor-adjusted analysis still finds significant alphas")
        println("      • Anomalies survive rigorous factor control")
        println("      • Evidence for genuine market inefficiencies")
    end
    
    println("\\n📖 METHODOLOGICAL DIFFERENCE:")
    println("   Traditional: Tests whether returns ≠ 0")
    println("   Novy-Marx: Tests whether α ≠ 0 in: R_p = α + β₁×MKT + β₂×SMB + β₃×HML + ε")
    println("   
   Key Point: Returns can be significant due to systematic risk exposure")
    println("              Alphas represent unexplained outperformance after risk adjustment")
    
    println("\\n🎓 ACADEMIC STANDARD:")
    println("   • Modern finance requires factor-adjusted performance measurement")
    println("   • Raw return tests are considered methodologically insufficient")  
    println("   • Novy-Marx methodology is now the gold standard for anomaly testing")
    println("   • Survivorship bias correction + factor adjustment = robust research")
    
    println("\\n🎉 NOVY-MARX METHODOLOGY DEMONSTRATION COMPLETE!")
    
catch e
    println("❌ Demo failed: $e")
    println("\\nStacktrace:")
    for (i, frame) in enumerate(stacktrace(catch_backtrace()))
        println("  $i: $frame") 
        if i > 15 break end
    end
end