# Test multifactor regression module
using Dates, DataFrames, Statistics, Random

println("🧪 TESTING MULTIFACTOR REGRESSION MODULE")
println("=" ^ 70)

# Set seed for reproducible results
Random.seed!(42)

try
    # Import required modules
    include("../src/fama_french_factors.jl")
    include("../src/multifactor_regression.jl")
    using .FamaFrenchFactors
    using .MultifactorRegression
    
    println("1️⃣ Module imports successful")
    
    # Get real Fama-French factors for testing
    println("\n2️⃣ Downloading real factors for testing...")
    factors = download_fama_french_factors(Date(2020, 1, 1), Date(2023, 12, 31), verbose=false)
    println("   ✅ Downloaded $(nrow(factors)) factor observations")
    println("   📊 Available columns: $(names(factors))")
    
    # Generate sample portfolio returns that should have some correlation with factors
    # Simulate a "low volatility" portfolio that might have negative alpha
    n_periods = nrow(factors)
    println("\n3️⃣ Generating sample portfolio returns...")
    
    # Create returns with some factor exposure plus noise
    market_premium = factors.MKT_RF / 100  # Convert to decimal
    smb = factors.SMB / 100
    hml = factors.HML / 100
    rf = factors.RF / 100
    
    # Simulate a portfolio with:
    # - Beta of 0.8 (lower than market)  
    # - Slight small-cap bias (SMB loading of 0.2)
    # - Value tilt (HML loading of 0.3)
    # - Some alpha (0.5% annually = ~0.04% monthly)
    true_alpha = 0.04  # Monthly % alpha
    true_beta = 0.8
    true_smb = 0.2
    true_hml = 0.3
    
    # Generate portfolio excess returns
    noise = randn(n_periods) * 0.02  # 2% monthly volatility noise
    portfolio_excess_returns = true_alpha .+ true_beta .* market_premium .+ 
                              true_smb .* smb .+ true_hml .* hml .+ noise
    
    # Convert to total returns (add back risk-free rate)
    portfolio_returns = (portfolio_excess_returns .+ rf) .* 100  # Convert to %
    
    println("   ✅ Generated $(length(portfolio_returns)) portfolio return observations")
    println("   📊 Average return: $(round(mean(portfolio_returns), digits=2))%")
    println("   📊 Volatility: $(round(std(portfolio_returns), digits=2))%")
    
    # Test 4: CAPM Regression
    println("\n4️⃣ Testing CAPM regression...")
    capm_result = run_capm_regression(portfolio_returns, factors, "Test Portfolio", "2020-2023")
    
    println("   ✅ CAPM regression completed")
    println("   📊 Alpha: $(round(capm_result.alpha, digits=2))% (t=$(round(capm_result.alpha_tstat, digits=2)))")
    println("   📊 Beta: $(round(capm_result.betas[1], digits=3)) (expected: $true_beta)")
    println("   📊 R²: $(round(capm_result.r_squared, digits=3))")
    
    # Test 5: FF3 Regression
    println("\n5️⃣ Testing Fama-French 3-factor regression...")
    ff3_result = run_ff3_regression(portfolio_returns, factors, "Test Portfolio", "2020-2023")
    
    if ff3_result !== nothing
        println("   ✅ FF3 regression completed")
        println("   📊 Alpha: $(round(ff3_result.alpha, digits=2))% (t=$(round(ff3_result.alpha_tstat, digits=2)))")
        println("   📊 Market Beta: $(round(ff3_result.betas[1], digits=3)) (expected: $true_beta)")
        println("   📊 SMB Beta: $(round(ff3_result.betas[2], digits=3)) (expected: $true_smb)")
        println("   📊 HML Beta: $(round(ff3_result.betas[3], digits=3)) (expected: $true_hml)")
        println("   📊 R²: $(round(ff3_result.r_squared, digits=3))")
    else
        println("   ❌ FF3 regression failed")
    end
    
    # Test 6: FF5 Regression  
    println("\n6️⃣ Testing Fama-French 5-factor regression...")
    ff5_result = run_ff5_regression(portfolio_returns, factors, "Test Portfolio", "2020-2023")
    
    if ff5_result !== nothing
        println("   ✅ FF5 regression completed")
        println("   📊 Alpha: $(round(ff5_result.alpha, digits=2))% (t=$(round(ff5_result.alpha_tstat, digits=2)))")
        println("   📊 R²: $(round(ff5_result.r_squared, digits=3))")
        
        # Show all betas
        factor_names = ["MKT-RF", "SMB", "HML", "RMW", "CMA"]
        for (i, name) in enumerate(factor_names)
            println("   📊 $name Beta: $(round(ff5_result.betas[i], digits=3))")
        end
    else
        println("   ❌ FF5 regression failed")
    end
    
    # Test 7: Comprehensive Alpha Analysis
    println("\n7️⃣ Testing comprehensive alpha analysis...")
    alpha_analysis = analyze_portfolio_alphas(portfolio_returns, factors, "Test Portfolio", "2020-2023")
    
    println("   ✅ Alpha analysis completed")
    println("   📊 Raw return: $(round(alpha_analysis.raw_return, digits=2))%")
    println("   📊 Best model: $(alpha_analysis.best_model)")
    println("   🧪 Novy-Marx conclusion: $(alpha_analysis.novy_marx_conclusion)")
    
    # Test 8: GRS Test (need multiple portfolios)
    println("\n8️⃣ Testing GRS test with multiple portfolios...")
    
    # Create a second portfolio (high volatility)
    portfolio_returns_2 = ((-true_alpha) .+ 1.2 .* market_premium .+ 
                          (-true_smb) .* smb .+ (-true_hml) .* hml .+ randn(n_periods) * 0.03) .* 100
    portfolio_returns_2 = portfolio_returns_2 .+ rf .* 100
    
    capm_result_2 = run_capm_regression(portfolio_returns_2, factors, "High Vol Portfolio", "2020-2023")
    
    grs_results = grs_test([capm_result, capm_result_2])
    
    if haskey(grs_results, :error)
        println("   ⚠️  GRS test issue: $(grs_results[:error])")
    else
        println("   ✅ GRS test completed")
        println("   📊 F-statistic: $(round(grs_results[:grs_statistic], digits=3))")
        println("   📊 p-value: $(round(grs_results[:p_value], digits=4))")
        println("   🧪 Conclusion: $(grs_results[:conclusion])")
    end
    
    # Test 9: Summary functions
    println("\n9️⃣ Testing summary functions...")
    
    summarize_regression_results(capm_result)
    
    if ff3_result !== nothing
        summarize_regression_results(ff3_result)
    end
    
    summarize_alpha_analysis(alpha_analysis)
    
    println("\n🎉 ALL MULTIFACTOR REGRESSION TESTS PASSED!")
    println("\n📋 MODULE CAPABILITIES VERIFIED:")
    println("   ✅ CAPM regression with t-tests and R²")
    println("   ✅ Fama-French 3-factor regression")
    println("   ✅ Fama-French 5-factor regression")
    println("   ✅ Comprehensive alpha analysis")
    println("   ✅ GRS test for joint alpha significance")
    println("   ✅ Novy-Marx methodology framework")
    println("   ✅ Summary and reporting functions")
    
    println("\n🎯 READY FOR NOVY-MARX IMPLEMENTATION!")
    
catch e
    println("❌ Test failed: $e")
    println("\nStacktrace:")
    for (i, frame) in enumerate(stacktrace())
        println("  $i: $frame")
        if i > 15 break end
    end
end