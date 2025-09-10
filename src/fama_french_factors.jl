# Real Fama-French Factors Module
# Downloads and parses actual Kenneth French Data Library factors
# Replaces the simulated data version

module FamaFrenchFactors

using HTTP, CSV, DataFrames, Dates, Statistics, Printf

export download_fama_french_factors, get_ff_factors, get_ff5_factors, summarize_factors, 
       save_factors_cache, load_factors_cache, factors_cache_exists

"""
Verifica se existe cache para os fatores.
"""
function factors_cache_exists(cache_dir::String = "data/cache/factors")::Bool
    abs_cache_dir = isabspath(cache_dir) ? cache_dir : joinpath(pwd(), cache_dir)
    cache_file = joinpath(abs_cache_dir, "ff5_factors.csv")
    return isfile(cache_file)
end

"""
Salva dados de fatores no cache.
"""
function save_factors_cache(data::DataFrame, cache_dir::String = "data/cache/factors")::Nothing
    # Usar caminho absoluto se não for absoluto já
    abs_cache_dir = isabspath(cache_dir) ? cache_dir : joinpath(pwd(), cache_dir)
    mkpath(abs_cache_dir)  # Criar diretório se não existir
    cache_file = joinpath(abs_cache_dir, "ff5_factors.csv")
    CSV.write(cache_file, data)
    return nothing
end

"""
Carrega dados de fatores do cache.
"""
function load_factors_cache(cache_dir::String = "data/cache/factors")::Union{DataFrame, Nothing}
    abs_cache_dir = isabspath(cache_dir) ? cache_dir : joinpath(pwd(), cache_dir)
    cache_file = joinpath(abs_cache_dir, "ff5_factors.csv")
    if isfile(cache_file)
        try
            return CSV.read(cache_file, DataFrame)
        catch e
            println("⚠️ Erro ao ler cache de fatores: $e")
            return nothing
        end
    end
    return nothing
end

"""
Download and parse real Fama-French 5-factor data from Kenneth French Data Library.
Returns DataFrame with Date, MKT_RF, SMB, HML, RMW, CMA, RF columns.

Parameters:
- start_date: Starting date for data (default: 2000-01-01)
- end_date: Ending date for data (default: 2024-12-31)  
- verbose: Print progress messages (default: true)

Returns:
- DataFrame with factor data
"""
function download_fama_french_factors(
    start_date::Date = Date(2000, 1, 1),
    end_date::Date = Date(2024, 12, 31);
    force::Bool = false,
    verbose::Bool = true
)::DataFrame
    
    verbose && println("📥 Obtendo dados reais de fatores Fama-French 5...")
    verbose && println("   Cache: $(force ? "FORÇAR download" : "usar cache se disponível")")
    
    # Armazenar diretório original para cache
    original_dir = pwd()
    cache_dir = joinpath(original_dir, "data/cache/factors")
    
    # Verificar cache primeiro (a menos que force=true)
    if !force && factors_cache_exists(cache_dir)
        cached_data = load_factors_cache(cache_dir)
        if cached_data !== nothing
            # Verificar se o cache cobre o período solicitado
            cache_start = minimum(cached_data.Date)
            cache_end = maximum(cached_data.Date)
            
            if cache_start <= start_date && cache_end >= end_date
                # Filtrar dados do cache para o período solicitado
                result_data = filter(row -> start_date <= row.Date <= end_date, cached_data)
                verbose && println("   📁 Usando dados do cache ($(nrow(result_data)) observações)")
                return result_data
            else
                verbose && println("   ⚠️ Cache existe mas não cobre período completo, baixando dados atualizados...")
            end
        end
    end
    
    verbose && println("   🌐 Baixando do Kenneth French Data Library...")
    url = "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/F-F_Research_Data_5_Factors_2x3_CSV.zip"
    
    try
        # Download ZIP file
        verbose && println("   📡 Downloading from: $(url)")
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
        
        # Extract ZIP file
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
            
            # Read raw content to locate data section
            csv_content = read(csv_file, String)
            lines = split(csv_content, "\n")
            
            verbose && println("   🔍 Parsing CSV structure ($(length(lines)) lines)...")
            
            # Find header line (contains factor names)
            header_idx = 0
            for (i, line) in enumerate(lines)
                if contains(line, "Mkt-RF") && contains(line, "SMB") && contains(line, "HML")
                    header_idx = i
                    verbose && println("   📊 Found header at line $i")
                    break
                end
            end
            
            if header_idx == 0
                error("Could not find header line with Fama-French factors")
            end
            
            # Find end of monthly data (before annual data or copyright)
            data_end_idx = length(lines)
            for i in (header_idx + 1):length(lines)
                line = strip(lines[i])
                if contains(lowercase(line), "copyright") || match(r"^\d{4}[^0-9]", line) !== nothing
                    data_end_idx = i - 1
                    verbose && println("   📅 Monthly data ends at line $(data_end_idx)")
                    break
                end
            end
            
            # Extract clean data section
            data_section = [lines[header_idx]]  # Include header
            
            monthly_count = 0
            for i in (header_idx + 1):data_end_idx
                line = strip(lines[i])
                if !isempty(line) && match(r"^\d{6}", line) !== nothing
                    push!(data_section, line)
                    monthly_count += 1
                end
            end
            
            verbose && println("   ✅ Found $monthly_count monthly observations")
            
            # Create clean CSV content and save to temporary file
            clean_csv = join(data_section, "\n")
            temp_clean_csv = "ff_factors_clean.csv"
            open(temp_clean_csv, "w") do f
                write(f, clean_csv)
            end
            
            # Read with CSV.jl for reliable parsing
            verbose && println("   📈 Parsing with CSV.jl...")
            df_raw = CSV.read(temp_clean_csv, DataFrame)
            
            # Create properly formatted DataFrame
            df_factors = DataFrame(
                Date = Date[],
                MKT_RF = Float64[],
                SMB = Float64[],
                HML = Float64[],
                RMW = Float64[],
                CMA = Float64[],
                RF = Float64[]
            )
            
            # Convert data row by row
            for row in eachrow(df_raw)
                try
                    # Parse date from first column (YYYYMM format)
                    date_val = string(row[1])
                    
                    if length(date_val) == 6 && all(isdigit, date_val)
                        year = parse(Int, date_val[1:4])
                        month = parse(Int, date_val[5:6])
                        date = Date(year, month, 1)
                        
                        # Extract factor values
                        mkt_rf = Float64(row[2])  # Market excess return
                        smb = Float64(row[3])     # Small minus big
                        hml = Float64(row[4])     # High minus low (book-to-market)
                        rmw = Float64(row[5])     # Robust minus weak (profitability)
                        cma = Float64(row[6])     # Conservative minus aggressive (investment)
                        rf = Float64(row[7])      # Risk-free rate
                        
                        push!(df_factors, (date, mkt_rf, smb, hml, rmw, cma, rf))
                    end
                catch e
                    # Skip problematic rows
                    continue
                end
            end
            
            # Filter by date range
            filtered_factors = filter(row -> start_date <= row.Date <= end_date, df_factors)
            
            verbose && println("   📅 Filtered to $(nrow(filtered_factors)) observations for period $(start_date) to $(end_date)")
            
            if verbose && nrow(filtered_factors) > 0
                println("   📊 Data range: $(minimum(filtered_factors.Date)) to $(maximum(filtered_factors.Date))")
                
                # Quick validation
                avg_mkt = mean(filtered_factors.MKT_RF)
                avg_rf = mean(filtered_factors.RF)
                
                println("   ✅ Validation:")
                println("      Average MKT-RF: $(round(avg_mkt, digits=2))%")
                println("      Average RF: $(round(avg_rf, digits=2))%")
                println("      Total observations: $(nrow(filtered_factors))")
            end
            
            # Salvar no cache para uso futuro (salvamos todos os dados, não apenas o filtrado)
            if nrow(df_factors) > 0
                cache_dir = joinpath(original_dir, "data/cache/factors")
                save_factors_cache(df_factors, cache_dir)
                verbose && println("   💾 Dados salvos no cache")
            end
            
            # Cleanup temporary files
            rm(temp_zip, force=true)
            rm(temp_clean_csv, force=true)
            
            return filtered_factors
        end
        
    catch e
        error("Error downloading/parsing Fama-French data: $e")
    end
end

"""
Get Fama-French factors for a specific date range.
Alias for download_real_ff_factors for compatibility.
"""
function get_ff_factors(start_date::Date, end_date::Date; verbose::Bool = false)::DataFrame
    return download_fama_french_factors(start_date, end_date, force=false, verbose=verbose)
end

"""
Alias conveniente para obter fatores FF5 com opções de cache.

Parâmetros:
- start_date, end_date: período desejado
- use_cache::Bool=true: usar cache se disponível
- force_refresh::Bool=false: forçar redownload ignorando cache
- verbose::Bool=true: logs
"""
function get_ff5_factors(; start_date::Date = Date(2000,1,1),
                            end_date::Date = Date(2024,12,31),
                            use_cache::Bool = true,
                            force_refresh::Bool = false,
                            verbose::Bool = true)::DataFrame
    force = force_refresh || !use_cache
    return download_fama_french_factors(start_date, end_date, force=force, verbose=verbose)
end

"""
Print summary statistics for Fama-French factors DataFrame.
"""
function summarize_factors(factors::DataFrame)
    println("\n📊 FAMA-FRENCH FACTORS SUMMARY")
    println("=" ^ 50)
    println("📅 Period: $(minimum(factors.Date)) to $(maximum(factors.Date))")
    println("📈 Observations: $(nrow(factors))")
    
    println("\n📊 Factor Statistics (Monthly %):")
    println(@sprintf("%8s %8s %8s %8s %8s", "Factor", "Mean", "Std", "Min", "Max"))
    println("-" ^ 45)
    
    factor_cols = [:MKT_RF, :SMB, :HML, :RMW, :CMA, :RF]
    factor_names = ["MKT-RF", "SMB", "HML", "RMW", "CMA", "RF"]
    
    for (col, name) in zip(factor_cols, factor_names)
        if col in names(factors)
            values = factors[!, col]
            println(@sprintf("%8s %8.2f %8.2f %8.2f %8.2f", 
                           name, 
                           mean(values), 
                           std(values), 
                           minimum(values), 
                           maximum(values)))
        end
    end
    
    println("\n📈 Correlations:")
    println("   MKT-RF vs SMB: $(round(cor(factors.MKT_RF, factors.SMB), digits=3))")
    println("   MKT-RF vs HML: $(round(cor(factors.MKT_RF, factors.HML), digits=3))")
    println("   SMB vs HML: $(round(cor(factors.SMB, factors.HML), digits=3))")
    
    println("\n✅ Real Fama-French data loaded successfully!")
end

end
