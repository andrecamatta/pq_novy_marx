#!/usr/bin/env julia

# Main script for Volatility Anomaly Analysis
# Clean, professional interface for testing Novy-Marx critique

using Pkg

# Ensure required packages are available
required_packages = ["YFinance", "DataFrames", "Dates", "CSV", "JSON", "StatsBase", "Distributions", "Printf"]
for pkg in required_packages
    try
        eval(Meta.parse("using $pkg"))
    catch
        println("Installing $pkg...")
        Pkg.add(pkg)
    end
end

# Include main module
include("src/VolatilityAnomalyAnalysis.jl")
using .VolatilityAnomalyAnalysis

"""
Display help information for the analysis tool.
"""
function show_help()
    println("""
    🔬 VOLATILITY ANOMALY ANALYSIS TOOL
    Testing Novy-Marx Critique with Academic Standards
    ================================================
    
    USAGE:
      julia main_analysis.jl [command] [options]
    
    COMMANDS:
      full      Run complete analysis (default)
      test      Quick test with small universe
      results   Display saved results
      help      Show this help message
    
    EXAMPLES:
      julia main_analysis.jl                  # Full analysis
      julia main_analysis.jl test            # Quick test
      julia main_analysis.jl results         # Show previous results
      julia main_analysis.jl help            # This help
    
    OUTPUT:
      Results are saved to ./results/ directory:
      - statistical_summary.csv    : Key statistics
      - monthly_returns_*.csv      : Return series  
      - novy_marx_test.json        : Hypothesis test
      - analysis_report.txt        : Full report
    
    METHODOLOGY:
      ✓ Academic standards (1-month lag, proper filtering)
      ✓ Point-in-time analysis (survivorship bias correction)
      ✓ Multiple time periods (2000-2009, 2010-2019, 2020-2024)
      ✓ Comprehensive statistical testing
      ✓ Professional output formatting
    """)
end

"""
Main execution function.
"""
function main(args::Vector{String} = ARGS)
    if isempty(args)
        command = "full"
    else
        command = lowercase(strip(args[1]))
    end
    
    try
        if command in ["help", "-h", "--help"]
            show_help()
            
        elseif command == "test"
            println("🧪 Running Quick Test...")
            results = run_novy_marx_test()
            
        elseif command == "results" 
            println("📊 Displaying Saved Results...")
            display_saved_results()
            
        elseif command == "full"
            println("🚀 Running Full Analysis...")
            
            # Configure for full analysis
            config = AnalysisConfig(
                universe_type = :sp500_approximation,
                periods = [
                    ("2000-2009", "2000-01-01", "2009-12-31"),
                    ("2010-2019", "2010-01-01", "2019-12-31"),  
                    ("2020-2024", "2020-01-01", "2024-11-30")
                ],
                verbose = true
            )
            
            results = analyze_volatility_anomaly_full(config)
            
        else
            println("❌ Unknown command: $command")
            println("Use 'julia main_analysis.jl help' for usage information")
            return
        end
        
    catch e
        if isa(e, InterruptException)
            println("\n⚠️  Analysis interrupted by user")
        else
            println("❌ Error during analysis: $e")
            println("\nFor support, check:")
            println("  - Internet connectivity (YFinance API)")
            println("  - Julia package installations")
            println("  - File system permissions")
            rethrow(e)
        end
    end
end

"""
Quick demonstration function for new users.
"""
function demo()
    println("""
    🎯 DEMO: Volatility Anomaly Analysis
    ===================================
    
    This tool tests whether the "low volatility anomaly" (low-risk stocks 
    outperforming high-risk stocks) holds up to rigorous academic testing.
    
    We implement the critique by Novy-Marx that many financial anomalies
    disappear when proper methodology is applied.
    
    Running quick demo with test universe...
    """)
    
    return run_novy_marx_test()
end

# Handle different execution contexts
if abspath(PROGRAM_FILE) == @__FILE__
    # Direct execution
    main()
elseif isinteractive()
    # Interactive mode - show help
    println("📚 Volatility Anomaly Analysis Tool loaded!")
    println("Call main() to run analysis or demo() for quick demonstration")
    show_help()
end