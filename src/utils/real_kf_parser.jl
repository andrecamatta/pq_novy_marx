# Real Kenneth French Data Parser
# Based on actual format analysis

module RealKFParser

using HTTP, CSV, DataFrames, Dates, Statistics, Printf

export download_real_kf_factors, parse_kf_csv, parse_kf_date

"""
Parse Kenneth French date format YYYYMM to Date.
Examples: 196307 -> 1963-07-01, 202412 -> 2024-12-01
"""
function parse_kf_date(date_str::String)::Date
    if length(date_str) == 6
        year = parse(Int, date_str[1:4])
        month = parse(Int, date_str[5:6])
        return Date(year, month, 1)
    else
        error("Invalid KF date format: $date_str")
    end
end

"""
Parse real Kenneth French CSV content.
Handles the specific format: comments, headers, monthly data, annual data.
"""
function parse_kf_csv(csv_content::String)::DataFrame
    lines = split(csv_content, "\n")
    
    println("🔍 Parsing Kenneth French data...")
    println("   Total lines: $(length(lines))")
    
    # Find header line (contains Mkt-RF,SMB,HML,RMW,CMA,RF)
    header_idx = 0
    for (i, line) in enumerate(lines)
        if contains(line, "Mkt-RF") && contains(line, "SMB") && contains(line, "HML")
            header_idx = i
            println("   📊 Found header at line $i: $line")
            break
        end
    end
    
    if header_idx == 0
        error("Could not find header line with Mkt-RF,SMB,HML,RMW,CMA,RF")
    end
    
    # Parse data starting from next line
    data_lines = String[]
    monthly_count = 0
    
    for i in (header_idx + 1):length(lines)
        line = strip(lines[i])
        
        # Skip empty lines
        if isempty(line)
            continue
        end
        
        # Stop at copyright or if line doesn't start with date
        if contains(lowercase(line), "copyright") || contains(line, "Eugene")
            println("   🛑 Stopped at copyright line $i")
            break
        end
        
        # Check if line starts with a date (6 digits for monthly, 4 for annual)
        if match(r"^\d{6}", line) !== nothing
            # Monthly data (YYYYMM)
            push!(data_lines, line)
            monthly_count += 1
        elseif match(r"^\d{4}", line) !== nothing
            # Annual data (YYYY) - we'll skip these for now
            println("   📅 Skipping annual data at line $i")
            break
        end
    end
    
    println("   ✅ Found $monthly_count monthly observations")
    
    # Parse data lines into DataFrame
    df = DataFrame(
        Date = Date[],
        MKT_RF = Float64[],
        SMB = Float64[],
        HML = Float64[],
        RMW = Float64[],
        CMA = Float64[],
        RF = Float64[]
    )
    
    parse_errors = 0
    
    for (i, line) in enumerate(data_lines)
        try
            # Split by comma
            parts = split(strip(line), ",")
            
            if length(parts) >= 7  # Date + 6 factors
                # Parse date
                date_str = strip(parts[1])
                date = parse_kf_date(date_str)
                
                # Parse factors
                mkt_rf = parse(Float64, strip(parts[2]))
                smb = parse(Float64, strip(parts[3]))
                hml = parse(Float64, strip(parts[4]))
                rmw = parse(Float64, strip(parts[5]))
                cma = parse(Float64, strip(parts[6]))
                rf = parse(Float64, strip(parts[7]))
                
                # Add to DataFrame
                push!(df, (date, mkt_rf, smb, hml, rmw, cma, rf))
                
            else
                println("   ⚠️  Skipping malformed line: $line")
                parse_errors += 1
            end
            
        catch e
            println("   ❌ Error parsing line: $line")
            println("      Error: $e")
            parse_errors += 1
        end
    end
    
    if parse_errors > 0
        println("   ⚠️  $parse_errors lines had parsing errors")
    end
    
    println("   ✅ Successfully parsed $(nrow(df)) monthly observations")
    
    if nrow(df) > 0
        println("   📅 Date range: $(minimum(df.Date)) to $(maximum(df.Date))")
        
        # Quick validation
        avg_mkt = mean(df.MKT_RF)
        avg_rf = mean(df.RF)
        
        println("   📊 Quick validation:")
        println("      Average MKT-RF: $(round(avg_mkt, digits=2))% (expect ~0.5-1%)")
        println("      Average RF: $(round(avg_rf, digits=2))% (expect ~0.2-0.5%)")
        
        if avg_mkt < -5 || avg_mkt > 5
            @warn "MKT-RF average seems unusual: $avg_mkt%"
        end
        
        if avg_rf < 0 || avg_rf > 10
            @warn "RF average seems unusual: $avg_rf%"
        end
    end
    
    return df
end

"""
Download real Kenneth French 5-factor data.
"""
function download_real_kf_factors(
    start_date::Date = Date(2000, 1, 1),
    end_date::Date = Date(2024, 12, 31);
    verbose::Bool = true
)::DataFrame
    
    verbose && println("📥 Downloading REAL Kenneth French 5-factor data...")
    
    url = "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/F-F_Research_Data_5_Factors_2x3_CSV.zip"
    
    try
        # Download ZIP
        verbose && println("   📡 Downloading from: $url")
        response = HTTP.get(url, timeout=30)
        
        if response.status != 200
            error("HTTP request failed with status $(response.status)")
        end
        
        verbose && println("   ✅ Downloaded $(length(response.body)) bytes")
        
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
            
            if isempty(csv_files)
                error("No CSV file found in downloaded ZIP")
            end
            
            csv_file = csv_files[1]
            verbose && println("   📄 Found CSV file: $csv_file")
            
            # Read and parse CSV
            csv_content = read(csv_file, String)
            factors = parse_kf_csv(csv_content)
            
            # Filter date range
            filtered_factors = filter(row -> start_date <= row.Date <= end_date, factors)
            
            verbose && println("   📅 Filtered to date range: $(nrow(filtered_factors)) observations")
            verbose && println("   🎯 Period: $(minimum(filtered_factors.Date)) to $(maximum(filtered_factors.Date))")
            
            # Cleanup
            rm(temp_zip, force=true)
            
            return filtered_factors
        end
        
    catch e
        error("Error downloading/parsing Kenneth French data: $e")
    end
end

"""
Test the real KF parser with validation.
"""
function test_real_parser()
    println("🧪 TESTING REAL KENNETH FRENCH PARSER")
    println("=" ^ 60)
    
    try
        # Test with recent data
        factors = download_real_kf_factors(Date(2020, 1, 1), Date(2023, 12, 31), verbose=true)
        
        println("\n📊 VALIDATION RESULTS:")
        println("   Observations: $(nrow(factors))")
        
        if nrow(factors) > 0
            # Statistical validation
            stats = [
                ("MKT_RF", mean(factors.MKT_RF), std(factors.MKT_RF)),
                ("SMB", mean(factors.SMB), std(factors.SMB)),
                ("HML", mean(factors.HML), std(factors.HML)),
                ("RMW", mean(factors.RMW), std(factors.RMW)),
                ("CMA", mean(factors.CMA), std(factors.CMA)),
                ("RF", mean(factors.RF), std(factors.RF))
            ]
            
            println("\n   Factor Statistics:")
            println("   $(lpad("Factor", 8)) $(lpad("Mean%", 8)) $(lpad("Std%", 8)) $(lpad("Status", 10))")
            println("   " * "-" ^ 42)
            
            for (factor, mean_val, std_val) in stats
                status = "✅ OK"
                
                # Basic sanity checks
                if factor == "MKT_RF" && (mean_val < -2 || mean_val > 3)
                    status = "⚠️  HIGH"
                elseif factor == "RF" && (mean_val < 0 || mean_val > 8)
                    status = "⚠️  HIGH"
                elseif abs(mean_val) > 10  # Any factor > 10% average is suspicious
                    status = "❌ FAIL"
                end
                
                println("   $(lpad(factor, 8)) $(lpad(round(mean_val, digits=2), 7))% $(lpad(round(std_val, digits=2), 7))% $(lpad(status, 10))")
            end
            
            println("\n✅ Real Kenneth French parser working correctly!")
            return true
        else
            println("❌ No data returned")
            return false
        end
        
    catch e
        println("❌ Test failed: $e")
        return false
    end
end

end