# Debug Julia function resolution
using Dates

function test_date_parse(date_str::String)::Date
    println("Inside test_date_parse with: '$date_str' (type: $(typeof(date_str)))")
    
    if length(date_str) == 6
        year_str = date_str[1:4]
        month_str = date_str[5:6]
        println("  Year: '$year_str', Month: '$month_str'")
        
        year = parse(Int, year_str)
        month = parse(Int, month_str)
        println("  Parsed year: $year, month: $month")
        
        result = Date(year, month, 1)
        println("  Created date: $result")
        return result
    else
        error("Invalid date format: $date_str (length: $(length(date_str)))")
    end
end

println("🔍 JULIA FUNCTION DEBUGGING")
println("=" ^ 40)

# Test 1: Direct call
println("\n1️⃣ Testing direct call...")
try
    result = test_date_parse("196307")
    println("✅ Direct call worked: $result")
catch e
    println("❌ Direct call failed: $e")
end

# Test 2: Function reference
println("\n2️⃣ Testing function reference...")
try
    func = test_date_parse
    result = func("196307")
    println("✅ Function reference worked: $result")
catch e
    println("❌ Function reference failed: $e")
end

# Test 3: Inside another function
function wrapper_function()
    println("Inside wrapper_function")
    return test_date_parse("196307")
end

println("\n3️⃣ Testing from wrapper function...")
try
    result = wrapper_function()
    println("✅ Wrapper call worked: $result")
catch e
    println("❌ Wrapper call failed: $e")
    println("Error type: $(typeof(e))")
    if isa(e, MethodError)
        println("   Function: $(e.f)")
        println("   Arguments: $(e.args)")
    end
end

# Test 4: Check function exists
println("\n4️⃣ Checking function existence...")
println("Function test_date_parse exists: $(isdefined(Main, :test_date_parse))")
println("Function methods: $(methods(test_date_parse))")

# Test 5: Simple string operation
println("\n5️⃣ Testing simple string operations...")
test_str = "196307"
println("Test string: '$test_str'")
println("Length: $(length(test_str))")
println("First 4: '$(test_str[1:4])'")
println("Last 2: '$(test_str[5:6])'")

# Test 6: Call in try-catch with detailed error
println("\n6️⃣ Testing with detailed error handling...")
test_string = "196307"
try
    println("About to call test_date_parse with '$test_string'")
    result = test_date_parse(test_string)
    println("✅ Success: $result")
catch e
    println("❌ Failed with error: $e")
    println("   Error type: $(typeof(e))")
    
    if isa(e, MethodError)
        println("   Function object: $(e.f)")
        println("   Function name: $(nameof(e.f))")
        println("   Arguments: $(e.args)")
        println("   Argument types: $(typeof.(e.args))")
        
        # Check if function signature matches
        println("   Available methods:")
        for method in methods(e.f)
            println("     $method")
        end
    end
    
    # Print stacktrace
    println("\n   Stacktrace:")
    for (i, frame) in enumerate(stacktrace())
        println("     $i: $frame")
        if i > 5 break end
    end
end