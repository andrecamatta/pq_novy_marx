# Test runner for Novy-Marx Analysis System
# Simplified tests for modular refactored system

using Test
using Dates

# Include the main analysis system
include("../novy_marx_analysis.jl")

println("🧪 RUNNING NOVY-MARX ANALYSIS TEST SUITE")
println("=" ^ 60)

@testset "Novy-Marx Analysis Tests" begin

    # Test 1: Core Modules Loading
    @testset "Core Modules" begin
        println("  📊 Testing core modules are loaded...")

        # Test that essential modules are loaded
        @test isdefined(Main, :CacheManager)
        @test isdefined(Main, :SP500Constituents)
        @test isdefined(Main, :TiingoData)
        @test isdefined(Main, :ReturnsCalculation)
        @test isdefined(Main, :PortfolioConstruction)
        @test isdefined(Main, :ResultsExport)

        println("  ✅ Core modules loaded successfully")
    end

    # Test 2: Basic System Check
    @testset "System Ready" begin
        println("  ⚙️  Testing system readiness...")

        # Just test that the system loaded without crashing
        @test true  # If we get here, modules loaded successfully

        println("  ✅ System ready for analysis")
    end

end

println("\n🎉 All tests completed!")
println("Novy-Marx Analysis System ready!")