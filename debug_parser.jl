# Debug the parser scoping issue

include("src/utils/real_kf_parser.jl")
using .RealKFParser
using Dates

println("🔍 DEBUGGING PARSER SCOPING ISSUE")
println("=" ^ 50)

# Test the parse_kf_date function directly
try
    println("Testing parse_kf_date directly...")
    test_date = RealKFParser.parse_kf_date("196307")
    println("✅ Direct call worked: $test_date")
catch e
    println("❌ Direct call failed: $e")
end

# Test if function is exported
try 
    println("Testing exported function...")
    test_date2 = parse_kf_date("196307") 
    println("✅ Exported function worked: $test_date2")
catch e
    println("❌ Exported function failed: $e")
end

# List available functions
println("\nAvailable functions in RealKFParser:")
for name in names(RealKFParser)
    println("  - $name")
end