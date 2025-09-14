# Main test runner for Novy-Marx S&P 500 Analysis System
# Comprehensive test suite for unified analysis system

using Test
using Dates

# Include the main analysis system
include("../novy_marx_sp500_analysis.jl")

println("🧪 RUNNING NOVY-MARX S&P 500 ANALYSIS TEST SUITE")
println("=" ^ 60)

@testset "Novy-Marx S&P 500 Analysis Tests" begin
    
    # Test 1: Configuration System
    @testset "Configuration System" begin
        @test_nowarn AnalysisConfig()
        
        config = AnalysisConfig(
            start_date = Date(2023, 1, 1),
            end_date = Date(2023, 12, 31),
            lookback_periods = [6, 12]
        )
        
        @test config.start_date == Date(2023, 1, 1)
        @test config.lookback_periods == [6, 12]
        @test config.factor_models == [:CAPM, :FF3, :FF5]
        println("  ✅ Configuration system tests passed")
    end
    
    # Test 2: Core Modules Integration
    @testset "Core Modules" begin
        println("  📊 Testing core modules integration...")
        
        # Test that modules are loaded correctly
        @test isdefined(Main, :MarketData)
        @test isdefined(Main, :FamaFrenchFactors) 
        @test isdefined(Main, :MultifactorRegression)
        @test isdefined(Main, :Visualization)
        
        println("  ✅ Core modules loaded successfully")
    end
    
    # Test 3: Fama-French Integration
    @testset "Fama-French Data Integration" begin
        println("  📊 Testing Fama-French factor integration...")
        include("test_ff_integration.jl")
    end
    
    # Test 4: Multifactor Regression
    @testset "Multifactor Regression Engine" begin  
        println("  🔬 Testing multifactor regression engine...")
        include("test_multifactor_regression.jl")
    end
    
    # Test 5: Main API Functions
    @testset "Main API Functions" begin
        # Test that main functions are available
        @test isdefined(Main, :analyze_sp500)
        @test isdefined(Main, :quick_analysis)
        @test isdefined(Main, :run_complete_analysis)
        
        # Test quick analysis with minimal config (should not crash)
        println("  🏃 Testing quick_analysis API...")
        @test_nowarn quick_analysis(Date(2023, 10, 1), Date(2023, 12, 31))
        
        println("  ✅ Main API tests passed")
    end
end

println("\n🎉 All tests completed!")
println("Novy-Marx S&P 500 Analysis System is ready for academic anomaly research!")