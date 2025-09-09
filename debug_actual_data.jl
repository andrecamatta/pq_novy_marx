# Debug the actual Kenneth French data parsing
using HTTP, Dates

# Simple working date parser
function parse_kf_date_debug(date_str::String)::Date
    println("🔍 parse_kf_date_debug called with: '$(repr(date_str))' (length: $(length(date_str)))")
    
    # Check for hidden characters
    for (i, char) in enumerate(date_str)
        println("  Char $i: '$(char)' (code: $(Int(char)))")
    end
    
    if length(date_str) == 6
        year = parse(Int, date_str[1:4])
        month = parse(Int, date_str[5:6])
        return Date(year, month, 1)
    else
        error("Invalid KF date format: $date_str")
    end
end

println("🔍 DEBUGGING ACTUAL KENNETH FRENCH DATA")
println("=" ^ 50)

try
    # Download and examine the real data
    url = "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/F-F_Research_Data_5_Factors_2x3_CSV.zip"
    response = HTTP.get(url, timeout=30)
    
    # Save and extract
    temp_zip = tempname() * ".zip"
    open(temp_zip, "w") do f
        write(f, response.body)
    end
    
    temp_dir = mktempdir()
    cd(temp_dir) do
        run(`unzip -q $temp_zip`)
        
        csv_files = filter(f -> endswith(lowercase(f), ".csv"), readdir("."))
        csv_file = csv_files[1]
        
        # Read and examine the content
        csv_content = read(csv_file, String)
        lines = split(csv_content, "\n")
        
        println("📄 Examining CSV content...")
        println("   Total lines: $(length(lines))")
        
        # Find header
        header_idx = 0
        for (i, line) in enumerate(lines)
            if contains(line, "Mkt-RF") && contains(line, "SMB")
                header_idx = i
                println("   Header found at line $i: $(repr(line))")
                break
            end
        end
        
        # Examine first few data lines
        println("\n🔍 Examining first data lines:")
        for i in (header_idx + 1):(header_idx + 5)
            if i <= length(lines)
                line = lines[i]
                println("   Line $i: $(repr(line))")
                
                # Try to parse this line
                line_stripped = strip(line)
                if !isempty(line_stripped) && match(r"^\d{6}", line_stripped) !== nothing
                    parts = split(line_stripped, ",")
                    if length(parts) >= 7
                        date_part = strip(parts[1])
                        println("     Date part: $(repr(date_part))")
                        
                        # Try to parse the date
                        try
                            result = parse_kf_date_debug(date_part)
                            println("     ✅ Parsed successfully: $result")
                        catch e
                            println("     ❌ Parse error: $e")
                        end
                    end
                end
            end
        end
        
        # Cleanup
        rm(temp_zip, force=true)
    end
    
catch e
    println("❌ Error: $e")
end