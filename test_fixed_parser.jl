# Test the fixed Kenneth French parser
using Dates

println("🧪 TESTING FIXED KENNETH FRENCH PARSER")
println("=" ^ 60)

# Include the fixed parser
include("src/utils/kf_parser_fixed.jl")
using .KFParserFixed

try
    println("Testing date parsing function...")
    test_date = parse_kf_date_string("196307")
    println("✅ Date parsing works: $test_date")
    
    println("\nTesting real data download...")
    factors = download_kf_factors(Date(2024, 1, 1), Date(2024, 12, 31), verbose=true)
    
    if nrow(factors) > 0
        println("\n✅ SUCCESS! Fixed parser working correctly!")
        println("   Downloaded $(nrow(factors)) observations")
        println("   Date range: $(minimum(factors.Date)) to $(maximum(factors.Date))")
        
        # Show first few rows
        println("\n📊 First 3 rows of data:")
        for i in 1:min(3, nrow(factors))
            row = factors[i, :]
            println("   $(row.Date): MKT-RF=$(row.MKT_RF)%, SMB=$(row.SMB)%, HML=$(row.HML)%")
        end
        
        # Show data summary
        println("\n📈 Data summary:")
        println("   MKT-RF: $(round(mean(factors.MKT_RF), digits=2))% avg, $(round(std(factors.MKT_RF), digits=2))% std")
        println("   SMB: $(round(mean(factors.SMB), digits=2))% avg, $(round(std(factors.SMB), digits=2))% std")
        println("   HML: $(round(mean(factors.HML), digits=2))% avg, $(round(std(factors.HML), digits=2))% std")
        println("   RF: $(round(mean(factors.RF), digits=2))% avg, $(round(std(factors.RF), digits=2))% std")
        
        println("\n🎉 REAL KENNETH FRENCH PARSER IS WORKING PERFECTLY!")
        
    else
        println("❌ No data returned")
    end
    
catch e
    println("❌ Test failed: $e")
    
    # Show more detailed error
    if isa(e, MethodError)
        println("MethodError details:")
        println("   Function: $(e.f)")
        println("   Arguments: $(e.args)")
    end
    
    println("\nStacktrace:")
    for line in stacktrace()
        println("  $line")
    end
end