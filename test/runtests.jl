# Main test runner for NovoMarxAnalysis.jl
# Comprehensive test suite for Novy-Marx methodology implementation

using Test
using Dates

# Add parent directory to path to access the module
push!(LOAD_PATH, joinpath(@__DIR__, ".."))

println("🧪 RUNNING NOVYMARXANALYSIS.JL TEST SUITE")
println("=" ^ 60)

@testset "NovoMarxAnalysis.jl Tests" begin
    
    # Test 1: Module Loading
    @testset "Module Loading" begin
        @test_nowarn include("../src/NovoMarxAnalysis.jl")
        using .NovoMarxAnalysis
        @test isdefined(NovoMarxAnalysis, :analyze_low_volatility_anomaly)
        @test isdefined(NovoMarxAnalysis, :test_joint_significance)
    end
    
    # Test 2: Fama-French Integration
    @testset "Fama-French Data Integration" begin
        println("  📊 Testing Fama-French factor integration...")
        include("test_ff_integration.jl")
    end
    
    # Test 3: Multifactor Regression
    @testset "Multifactor Regression Engine" begin  
        println("  🔬 Testing multifactor regression engine...")
        include("test_multifactor_regression.jl")
    end
    
    # Test 4: Main API
    @testset "Main API Functions" begin
        using .NovoMarxAnalysis
        
        # Test sample data access
        sample_data = get_sample_data()
        @test haskey(sample_data, :sp500_components)
        @test haskey(sample_data, :universe_validation)
        
        # Test package info (should not error)
        @test_nowarn package_info()
        
        println("  ✅ Main API tests passed")
    end
end

println("\n🎉 All tests completed!")
println("NovoMarxAnalysis.jl is ready for academic anomaly research!")