# Novy-Marx Compliant Low Volatility Anomaly Analysis
# Tests factor-adjusted alphas instead of raw returns
# Uses real Fama-French data for academic rigor

using DataFrames, Dates, Statistics, CSV, Printf

println("🧪 NOVY-MARX COMPLIANT LOW VOLATILITY ANALYSIS")
println("=" ^ 70)
println("Testing factor-adjusted alphas rather than raw returns")
println("Following Novy-Marx (2013) critique methodology\n")

try
    # Import required modules
    include("src/utils/fama_french_factors.jl")
    include("src/utils/multifactor_regression.jl")
    include("src/utils/data_download.jl")
    include("src/utils/portfolio_analysis.jl")
    include("src/utils/config.jl")
    
    using .FamaFrenchFactors
    using .MultifactorRegression
    using .DataDownload
    using .PortfolioAnalysis
    using .Config
    
    println("✅ All modules imported successfully")
    
    # Configuration
    analysis_periods = [
        ("2000-2009", Date(2000, 1, 1), Date(2009, 12, 31)),
        ("2010-2019", Date(2010, 1, 1), Date(2019, 12, 31)),
        ("2020-2023", Date(2020, 1, 1), Date(2023, 12, 31))
    ]
    
    universe_type = :sp500_approximation  
    n_portfolios = 5  # Low vol, 2, 3, 4, High vol
    
    # Get universe and download factor data
    println("\n📥 PREPARING DATA")
    println("-" ^ 40)
    
    tickers = get_universe(universe_type)
    println("🎯 Universe: $(length(tickers)) stocks ($(universe_type))")
    
    # Download all factor data for entire analysis period
    all_factors = download_fama_french_factors(Date(1999, 1, 1), Date(2024, 12, 31), verbose=false)
    println("📊 Downloaded $(nrow(all_factors)) monthly factor observations")
    println("📅 Factor data range: $(minimum(all_factors.Date)) to $(maximum(all_factors.Date))")
    
    # Download price data for all periods
    all_price_data = download_with_retry(tickers, [(period[1], string(period[2]), string(period[3])) for period in analysis_periods], verbose=true)
    
    # Results storage
    all_period_results = Dict{String, Dict{String, Any}}()
    all_alpha_analyses = Dict{String, Vector{AlphaAnalysis}}()
    
    # Analyze each period
    println("\n🔬 PERIOD-BY-PERIOD NOVY-MARX ANALYSIS")
    println("-" ^ 60)
    
    for (period_name, start_date, end_date) in analysis_periods
        if haskey(all_price_data, period_name)
            println("\n📊 ANALYZING PERIOD: $period_name")
            println("=" ^ 50)
            
            # Get factors for this period
            period_factors = filter(row -> start_date <= row.Date <= end_date, all_factors)
            println("📈 Factor observations for period: $(nrow(period_factors))")
            
            if nrow(period_factors) < 24  # Need at least 2 years of data
                println("⚠️  Insufficient factor data for period $period_name")
                continue
            end
            
            # Portfolio analysis - same as before to get portfolio returns
            vol_results = analyze_volatility_anomaly(
                all_price_data[period_name], 
                period_name,
                verbose=false  # Reduce noise
            )
            
            if isempty(vol_results.portfolio_returns)
                println("❌ No portfolio returns available for $period_name")
                continue
            end
            
            # Key change: Run multifactor regressions instead of raw return tests
            println("🔬 Running multifactor regressions on $(length(vol_results.portfolio_returns)) portfolios...")
            
            alpha_analyses = AlphaAnalysis[]
            
            for (portfolio_name, returns) in vol_results.portfolio_returns
                if length(returns) >= nrow(period_factors) && !all(isnan.(returns))
                    
                    # Align returns with factors by taking minimum length
                    aligned_length = min(length(returns), nrow(period_factors))
                    aligned_returns = returns[1:aligned_length]
                    aligned_factors = period_factors[1:aligned_length, :]
                    
                    # Skip if insufficient data
                    if aligned_length < 24
                        continue
                    end
                    
                    # Run comprehensive alpha analysis
                    alpha_analysis = analyze_portfolio_alphas(
                        aligned_returns,
                        aligned_factors,
                        portfolio_name,
                        period_name
                    )
                    
                    push!(alpha_analyses, alpha_analysis)
                    
                    # Print summary for this portfolio
                    best_alpha = if alpha_analysis.best_model == "CAPM"
                        alpha_analysis.capm_result.alpha
                    elseif alpha_analysis.best_model == "FF3" && alpha_analysis.ff3_result !== nothing
                        alpha_analysis.ff3_result.alpha
                    else
                        alpha_analysis.ff5_result.alpha
                    end
                    
                    best_pvalue = if alpha_analysis.best_model == "CAPM"
                        alpha_analysis.capm_result.alpha_pvalue
                    elseif alpha_analysis.best_model == "FF3" && alpha_analysis.ff3_result !== nothing
                        alpha_analysis.ff3_result.alpha_pvalue
                    else
                        alpha_analysis.ff5_result.alpha_pvalue
                    end
                    
                    println("   📊 $portfolio_name:")
                    println("      Raw Return: $(round(alpha_analysis.raw_return, digits=2))%")
                    println("      Best Model: $(alpha_analysis.best_model)")
                    println("      Alpha: $(round(best_alpha, digits=2))%")
                    println("      Alpha p-value: $(round(best_pvalue, digits=4))")
                end
            end
            
            all_alpha_analyses[period_name] = alpha_analyses
            
            if !isempty(alpha_analyses)
                # GRS Test for joint significance of alphas
                println("\n🧪 GRS Test for Joint Alpha Significance:")
                
                # Use the best model results (highest average R-squared)
                best_model_results = []
                
                for analysis in alpha_analyses
                    if analysis.best_model == "CAPM"
                        push!(best_model_results, analysis.capm_result)
                    elseif analysis.best_model == "FF3" && analysis.ff3_result !== nothing
                        push!(best_model_results, analysis.ff3_result)
                    elseif analysis.best_model == "FF5" && analysis.ff5_result !== nothing
                        push!(best_model_results, analysis.ff5_result)
                    else
                        push!(best_model_results, analysis.capm_result)  # Fallback
                    end
                end
                
                if length(best_model_results) >= 2
                    grs_results = grs_test(best_model_results)
                    
                    if haskey(grs_results, :error)
                        println("   ⚠️  GRS Test Error: $(grs_results[:error])")
                    else
                        println("   📊 GRS F-statistic: $(round(grs_results[:grs_statistic], digits=3))")
                        println("   📊 p-value: $(round(grs_results[:p_value], digits=4))")
                        println("   🧪 Joint Test: $(grs_results[:conclusion])")
                    end
                    
                    all_period_results[period_name] = Dict(
                        "alpha_analyses" => alpha_analyses,
                        "grs_results" => grs_results,
                        "n_portfolios" => length(alpha_analyses)
                    )
                end
                
                # Period-level Novy-Marx conclusion
                significant_alphas = sum([
                    (analysis.best_model == "CAPM" ? analysis.capm_result.alpha_pvalue : 
                     analysis.best_model == "FF3" ? analysis.ff3_result.alpha_pvalue : 
                     analysis.ff5_result.alpha_pvalue) < 0.05 
                    for analysis in alpha_analyses
                ])
                
                period_conclusion = if significant_alphas == 0
                    "STRONGLY SUPPORTS Novy-Marx: No significant alphas in any portfolio"
                elseif significant_alphas < length(alpha_analyses) / 2
                    "SUPPORTS Novy-Marx: Most alphas not significant"
                elseif significant_alphas == length(alpha_analyses) 
                    "CONTRADICTS Novy-Marx: All portfolios have significant alpha"
                else
                    "MIXED EVIDENCE: Some portfolios have significant alpha"
                end
                
                println("\n🎯 PERIOD CONCLUSION: $period_conclusion")
                println("   Significant alphas: $significant_alphas / $(length(alpha_analyses))")
                
            else
                println("❌ No valid portfolios for alpha analysis in $period_name")
            end
            
        else
            println("⚠️  No price data available for $period_name")
        end
    end
    
    # Overall Novy-Marx Analysis
    println("\n🏆 OVERALL NOVY-MARX ANALYSIS")
    println("=" ^ 70)
    
    if !isempty(all_period_results)
        total_periods = length(all_period_results)
        total_portfolios = sum([results["n_portfolios"] for results in values(all_period_results)])
        
        # Count significant alphas across all periods and portfolios
        total_significant_alphas = 0
        total_tested_portfolios = 0
        
        for (period, results) in all_period_results
            for analysis in results["alpha_analyses"]
                total_tested_portfolios += 1
                alpha_pvalue = if analysis.best_model == "CAPM"
                    analysis.capm_result.alpha_pvalue
                elseif analysis.best_model == "FF3" && analysis.ff3_result !== nothing
                    analysis.ff3_result.alpha_pvalue
                elseif analysis.best_model == "FF5" && analysis.ff5_result !== nothing
                    analysis.ff5_result.alpha_pvalue
                else
                    analysis.capm_result.alpha_pvalue
                end
                
                if alpha_pvalue < 0.05
                    total_significant_alphas += 1
                end
            end
        end
        
        println("📊 Analysis Summary:")
        println("   Periods analyzed: $total_periods")
        println("   Total portfolios tested: $total_tested_portfolios") 
        println("   Portfolios with significant alpha: $total_significant_alphas")
        println("   Percentage significant: $(round(100 * total_significant_alphas / total_tested_portfolios, digits=1))%")
        
        # Final Novy-Marx Verdict
        overall_conclusion = if total_significant_alphas == 0
            "🎯 STRONGLY CONFIRMS NOVY-MARX CRITIQUE: No low volatility alpha survives factor adjustment"
        elseif total_significant_alphas < total_tested_portfolios * 0.1
            "🎯 CONFIRMS NOVY-MARX CRITIQUE: Low volatility anomaly largely explained by factors" 
        elseif total_significant_alphas < total_tested_portfolios * 0.5
            "🤔 MIXED EVIDENCE: Some alpha survives but most is factor-explained"
        else
            "🚨 CONTRADICTS NOVY-MARX CRITIQUE: Low volatility anomaly shows genuine alpha"
        end
        
        println("\n$overall_conclusion")
        
        println("\n📚 ACADEMIC INTERPRETATION:")
        if total_significant_alphas < total_tested_portfolios * 0.2
            println("   The analysis supports Novy-Marx's critique that apparent anomalies")
            println("   often disappear when proper factor controls are applied. The low")
            println("   volatility effect appears to be largely explained by systematic")
            println("   risk factors rather than representing a genuine market inefficiency.")
        else
            println("   The analysis suggests the low volatility anomaly contains genuine")
            println("   alpha that survives factor adjustment. This contradicts Novy-Marx's")
            println("   critique and provides evidence for market inefficiency in the")
            println("   pricing of low volatility stocks.")
        end
        
        # Save results
        println("\n💾 SAVING RESULTS")
        println("-" ^ 30)
        
        if !isdir("results")
            mkdir("results")
        end
        
        # Create summary CSV
        summary_data = []
        for (period, results) in all_period_results
            for analysis in results["alpha_analyses"]
                push!(summary_data, [
                    period,
                    analysis.portfolio_name,
                    analysis.best_model,
                    round(analysis.raw_return, digits=2),
                    round(analysis.best_model == "CAPM" ? analysis.capm_result.alpha : 
                          analysis.best_model == "FF3" ? analysis.ff3_result.alpha : 
                          analysis.ff5_result.alpha, digits=2),
                    round(analysis.best_model == "CAPM" ? analysis.capm_result.alpha_pvalue : 
                          analysis.best_model == "FF3" ? analysis.ff3_result.alpha_pvalue : 
                          analysis.ff5_result.alpha_pvalue, digits=4),
                    (analysis.best_model == "CAPM" ? analysis.capm_result.alpha_pvalue : 
                     analysis.best_model == "FF3" ? analysis.ff3_result.alpha_pvalue : 
                     analysis.ff5_result.alpha_pvalue) < 0.05 ? "Significant" : "Not Significant"
                ])
            end
        end
        
        summary_df = DataFrame(
            Period = [row[1] for row in summary_data],
            Portfolio = [row[2] for row in summary_data], 
            BestModel = [row[3] for row in summary_data],
            RawReturn = [row[4] for row in summary_data],
            Alpha = [row[5] for row in summary_data],
            AlphaPValue = [row[6] for row in summary_data],
            Significance = [row[7] for row in summary_data]
        )
        
        CSV.write("results/novy_marx_alpha_analysis.csv", summary_df)
        println("✅ Saved detailed results to: results/novy_marx_alpha_analysis.csv")
        
        println("\n🎉 NOVY-MARX ANALYSIS COMPLETE!")
        
    else
        println("❌ No results to analyze - insufficient data or processing errors")
    end
    
catch e
    println("❌ Analysis failed: $e")
    println("\\nStacktrace:")
    for (i, frame) in enumerate(stacktrace(catch_backtrace()))
        println("  $i: $frame")
        if i > 15 break end
    end
end