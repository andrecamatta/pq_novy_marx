# Simple Kenneth French Parser - NO MODULES
using HTTP, DataFrames, Dates, Statistics

function kf_parse_date(date_str::String)::Date
    if length(date_str) == 6
        year = parse(Int, date_str[1:4])
        month = parse(Int, date_str[5:6])
        return Date(year, month, 1)
    else
        error("Invalid KF date format: $date_str")
    end
end

function kf_download_real_factors(start_date::Date, end_date::Date)::DataFrame
    println("📥 Downloading Kenneth French 5-factor data...")
    
    url = "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/F-F_Research_Data_5_Factors_2x3_CSV.zip"
    
    # Download ZIP
    response = HTTP.get(url, timeout=30)
    println("   ✅ Downloaded $(length(response.body)) bytes")
    
    # Save temporary ZIP
    temp_zip = tempname() * ".zip"
    open(temp_zip, "w") do f
        write(f, response.body)
    end
    
    # Extract using system unzip command
    temp_dir = mktempdir()
    cd(temp_dir) do
        run(`unzip -q $temp_zip`)
        
        # Find CSV file
        csv_files = filter(f -> endswith(lowercase(f), ".csv"), readdir("."))
        csv_file = csv_files[1]
        println("   📄 Found CSV file: $csv_file")
        
        # Read CSV content
        csv_content = read(csv_file, String)
        lines = split(csv_content, "\n")
        
        println("🔍 Parsing Kenneth French data...")
        println("   Total lines: $(length(lines))")
        
        # Find header line
        header_idx = 0
        for (i, line) in enumerate(lines)
            if contains(line, "Mkt-RF") && contains(line, "SMB") && contains(line, "HML")
                header_idx = i
                println("   📊 Found header at line $i")
                break
            end
        end
        
        # Create DataFrame
        df = DataFrame(
            Date = Date[],
            MKT_RF = Float64[],
            SMB = Float64[],
            HML = Float64[],
            RMW = Float64[],
            CMA = Float64[],
            RF = Float64[]
        )
        
        # Parse data lines
        parse_count = 0
        error_count = 0
        
        for i in (header_idx + 1):length(lines)
            line = strip(lines[i])
            
            # Skip empty lines
            if isempty(line)
                continue
            end
            
            # Stop at copyright
            if contains(lowercase(line), "copyright")
                println("   🛑 Stopped at copyright line $i")
                break
            end
            
            # Check if line starts with 6 digits (monthly data)
            if match(r"^\d{6}", line) !== nothing
                try
                    # Split by comma
                    parts = split(strip(line), ",")
                    
                    if length(parts) >= 7
                        # Parse date - direct function call
                        date_str = strip(parts[1])
                        date = kf_parse_date(date_str)
                        
                        # Parse factors
                        mkt_rf = parse(Float64, strip(parts[2]))
                        smb = parse(Float64, strip(parts[3]))
                        hml = parse(Float64, strip(parts[4]))
                        rmw = parse(Float64, strip(parts[5]))
                        cma = parse(Float64, strip(parts[6]))
                        rf = parse(Float64, strip(parts[7]))
                        
                        # Add to DataFrame
                        push!(df, (date, mkt_rf, smb, hml, rmw, cma, rf))
                        parse_count += 1
                    end
                catch e
                    println("   ❌ Error on line $i: $e")
                    error_count += 1
                    if error_count > 5
                        break  # Stop if too many errors
                    end
                end
            elseif match(r"^\d{4}", line) !== nothing
                # Annual data - stop here
                println("   📅 Reached annual data at line $i")
                break
            end
        end
        
        println("   ✅ Parsed $parse_count observations ($error_count errors)")
        
        # Filter by date range
        filtered_df = filter(row -> start_date <= row.Date <= end_date, df)
        
        println("   📅 Filtered to $(nrow(filtered_df)) observations for requested period")
        
        # Cleanup
        rm(temp_zip, force=true)
        
        return filtered_df
    end
end

# Test the simple parser
println("🧪 TESTING SIMPLE KENNETH FRENCH PARSER")
println("=" ^ 60)

try
    # Test date parsing
    test_date = kf_parse_date("196307")
    println("✅ Date parsing works: $test_date")
    
    # Download and parse data
    factors = kf_download_real_factors(Date(2024, 1, 1), Date(2024, 12, 31))
    
    if nrow(factors) > 0
        println("\n✅ SUCCESS! Simple parser working!")
        println("   Downloaded $(nrow(factors)) observations")
        println("   Date range: $(minimum(factors.Date)) to $(maximum(factors.Date))")
        
        # Show sample data
        println("\n📊 Sample data:")
        for i in 1:min(5, nrow(factors))
            row = factors[i, :]
            println("   $(row.Date): MKT-RF=$(row.MKT_RF)%, RF=$(row.RF)%")
        end
        
        # Quick stats
        println("\n📈 Quick stats:")
        println("   MKT-RF: $(round(mean(factors.MKT_RF), digits=2))% avg")
        println("   RF: $(round(mean(factors.RF), digits=2))% avg")
        
        println("\n🎉 REAL KENNETH FRENCH PARSER WORKING PERFECTLY!")
        
    else
        println("❌ No data returned")
    end
    
catch e
    println("❌ Test failed: $e")
    println("\nStacktrace:")
    for (i, frame) in enumerate(stacktrace())
        println("  $i: $frame")
        if i > 10 break end  # Limit stacktrace
    end
end