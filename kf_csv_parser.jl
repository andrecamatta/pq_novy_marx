# Kenneth French parser using CSV.jl to avoid Julia world age issues
using HTTP, CSV, DataFrames, Dates, Statistics

println("📥 KENNETH FRENCH PARSER USING CSV.jl")
println("=" ^ 50)

try
    # Download data
    url = "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/F-F_Research_Data_5_Factors_2x3_CSV.zip"
    response = HTTP.get(url, timeout=30)
    println("✅ Downloaded $(length(response.body)) bytes")
    
    # Save and extract ZIP
    temp_zip = tempname() * ".zip"
    open(temp_zip, "w") do f
        write(f, response.body)
    end
    
    temp_dir = mktempdir()
    cd(temp_dir) do
        run(`unzip -q $temp_zip`)
        
        csv_files = filter(f -> endswith(lowercase(f), ".csv"), readdir("."))
        csv_file = csv_files[1]
        println("📄 Found CSV file: $csv_file")
        
        # Read the raw content to find where data starts
        csv_content = read(csv_file, String)
        lines = split(csv_content, "\n")
        
        # Find header line
        header_idx = 0
        for (i, line) in enumerate(lines)
            if contains(line, "Mkt-RF") && contains(line, "SMB") && contains(line, "HML")
                header_idx = i
                println("📊 Found header at line $i")
                break
            end
        end
        
        # Find where monthly data ends (before annual data starts)
        data_end_idx = length(lines)
        for i in (header_idx + 1):length(lines)
            line = strip(lines[i])
            if contains(lowercase(line), "copyright") || match(r"^\d{4}[^0-9]", line) !== nothing
                data_end_idx = i - 1
                println("📅 Data ends at line $(data_end_idx)")
                break
            end
        end
        
        # Extract just the data section and create a new CSV string
        data_section = [lines[header_idx]]  # Header
        
        # Add monthly data lines (6-digit dates)
        monthly_count = 0
        for i in (header_idx + 1):data_end_idx
            line = strip(lines[i])
            if !isempty(line) && match(r"^\d{6}", line) !== nothing
                push!(data_section, line)
                monthly_count += 1
            end
        end
        
        println("🔍 Found $monthly_count monthly observations")
        
        # Create clean CSV content
        clean_csv = join(data_section, "\n")
        
        # Write to temporary file
        temp_csv = "kf_clean.csv"
        open(temp_csv, "w") do f
            write(f, clean_csv)
        end
        
        # Read with CSV.jl
        println("📈 Reading with CSV.jl...")
        df_raw = CSV.read(temp_csv, DataFrame)
        
        println("✅ Successfully read $(nrow(df_raw)) rows")
        println("   Columns: $(names(df_raw))")
        
        # Clean up column names (remove leading comma artifacts)
        rename_dict = Dict()
        for name in names(df_raw)
            clean_name = replace(string(name), r"^Column\d+$" => "Date")
            clean_name = replace(clean_name, r"Mkt.RF" => "MKT_RF")
            if clean_name != string(name)
                rename_dict[name] = Symbol(clean_name)
            end
        end
        
        # Handle the weird first column situation
        if names(df_raw)[1] == :Column1
            rename!(df_raw, :Column1 => :Date_Raw)
        end
        
        # Show first few rows for debugging
        println("\n📊 First 3 rows of raw data:")
        for i in 1:min(3, nrow(df_raw))
            println("   Row $i: $(df_raw[i, :])")
        end
        
        # Convert dates manually (since CSV.jl parsed successfully)
        df_clean = DataFrame(
            Date = Date[],
            MKT_RF = Float64[],
            SMB = Float64[],
            HML = Float64[],
            RMW = Float64[],
            CMA = Float64[],
            RF = Float64[]
        )
        
        println("\n🔄 Converting data...")
        for row in eachrow(df_raw)
            try
                # Get the first column value (date)
                date_val = string(row[1])
                
                # Parse date manually - using the built-in Julia parsing
                if length(date_val) == 6 && all(isdigit, date_val)
                    year = parse(Int, date_val[1:4])
                    month = parse(Int, date_val[5:6])
                    date = Date(year, month, 1)
                    
                    # Get other columns (assuming they're in order)
                    mkt_rf = Float64(row[2])
                    smb = Float64(row[3])
                    hml = Float64(row[4])
                    rmw = Float64(row[5])
                    cma = Float64(row[6])
                    rf = Float64(row[7])
                    
                    push!(df_clean, (date, mkt_rf, smb, hml, rmw, cma, rf))
                end
            catch e
                println("   ⚠️ Skipping row: $e")
            end
        end
        
        println("✅ Converted $(nrow(df_clean)) observations")
        
        if nrow(df_clean) > 0
            # Filter for recent years
            recent_data = filter(row -> row.Date >= Date(2020, 1, 1), df_clean)
            
            println("\n📊 RESULTS:")
            println("   Total observations: $(nrow(df_clean))")
            println("   Date range: $(minimum(df_clean.Date)) to $(maximum(df_clean.Date))")
            println("   Recent data (2020+): $(nrow(recent_data)) observations")
            
            if nrow(recent_data) > 0
                println("\n📈 Recent data sample:")
                for i in 1:min(5, nrow(recent_data))
                    row = recent_data[i, :]
                    println("   $(row.Date): MKT-RF=$(row.MKT_RF)%, RF=$(row.RF)%")
                end
                
                # Quick stats
                println("\n📊 Summary statistics (2020+):")
                println("   MKT-RF: $(round(mean(recent_data.MKT_RF), digits=2))% ± $(round(std(recent_data.MKT_RF), digits=2))%")
                println("   SMB: $(round(mean(recent_data.SMB), digits=2))% ± $(round(std(recent_data.SMB), digits=2))%")
                println("   HML: $(round(mean(recent_data.HML), digits=2))% ± $(round(std(recent_data.HML), digits=2))%")
                println("   RF: $(round(mean(recent_data.RF), digits=2))% ± $(round(std(recent_data.RF), digits=2))%")
                
                println("\n🎉 SUCCESS! Real Kenneth French data parsed correctly!")
            end
        else
            println("❌ No valid data converted")
        end
        
        # Cleanup
        rm(temp_zip, force=true)
        rm(temp_csv, force=true)
    end
    
catch e
    println("❌ Error: $e")
    println("\nStacktrace:")
    for (i, frame) in enumerate(stacktrace())
        println("  $i: $frame")
        if i > 8 break end
    end
end