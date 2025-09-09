# Simple test with fresh Julia session
using Dates

println("🧪 SIMPLE KENNETH FRENCH PARSER TEST")
println("=" ^ 50)

# Include parser
include("src/utils/real_kf_parser.jl")
using .RealKFParser

# Test just one function call
try
    println("Testing simple download with limited data...")
    
    # Download a small sample  
    factors = download_real_kf_factors(Date(2024, 1, 1), Date(2024, 12, 31), verbose=true)
    
    if nrow(factors) > 0
        println("\n✅ SUCCESS! Parser working correctly!")
        println("   Downloaded $(nrow(factors)) observations")
        println("   Date range: $(minimum(factors.Date)) to $(maximum(factors.Date))")
        
        # Show first few rows
        println("\n📊 First 3 rows of data:")
        for i in 1:min(3, nrow(factors))
            row = factors[i, :]
            println("   $(row.Date): MKT-RF=$(row.MKT_RF)%, SMB=$(row.SMB)%, HML=$(row.HML)%")
        end
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
end