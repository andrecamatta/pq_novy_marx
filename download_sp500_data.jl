# Download real S&P 500 historical components data from GitHub

using HTTP, CSV, DataFrames, Dates

# GitHub repository URLs
const SP500_REPO_URL = "https://raw.githubusercontent.com/hanshof/sp500_constituents/main/"
const CSV_FILES = [
    "sp_500_historical_components.csv",
    "constituents.csv",  # Current constituents
    "changes.csv"        # Historical changes (if available)
]

println("📥 DOWNLOADING REAL S&P 500 DATA FROM GITHUB")
println("=" ^ 60)

# Create data directory
data_dir = "data"
if !isdir(data_dir)
    mkdir(data_dir)
    println("📁 Created data directory")
end

# Download files
downloaded_files = String[]
for csv_file in CSV_FILES
    try
        url = SP500_REPO_URL * csv_file
        println("\n📡 Downloading: $csv_file")
        println("   URL: $url")
        
        # Download the file
        response = HTTP.get(url)
        
        # Save to local file
        local_path = joinpath(data_dir, csv_file)
        open(local_path, "w") do file
            write(file, String(response.body))
        end
        
        push!(downloaded_files, local_path)
        println("   ✅ Downloaded: $local_path")
        
        # Quick analysis of the file
        if endswith(csv_file, ".csv")
            try
                df = CSV.read(local_path, DataFrame)
                println("   📊 Rows: $(nrow(df)), Columns: $(ncol(df))")
                println("   📋 Columns: $(names(df))")
                
                # Show first few rows
                if nrow(df) > 0
                    println("   🔍 Sample rows:")
                    display(first(df, min(3, nrow(df))))
                end
                
            catch e
                println("   ⚠️ Could not parse CSV: $e")
            end
        end
        
    catch e
        println("   ❌ Failed to download $csv_file: $e")
    end
end

println("\n" * ("=" ^ 60))
println("📋 DOWNLOAD SUMMARY:")
println("✅ Successfully downloaded: $(length(downloaded_files)) files")

for file in downloaded_files
    println("   📄 $file")
end

if !isempty(downloaded_files)
    println("\n🚀 NEXT STEPS:")
    println("1. Analyze the structure of sp_500_historical_components.csv")
    println("2. Update GitHub data integration code to use real data")
    println("3. Re-run universe validation with actual data")
    println("4. Expect 800-1000+ unique tickers from real dataset")
else
    println("\n❌ NO FILES DOWNLOADED")
    println("🔧 ALTERNATIVE APPROACHES:")
    println("1. Manual download from GitHub web interface")
    println("2. Use git clone of the repository")
    println("3. Create enhanced simulated dataset based on known S&P history")
end