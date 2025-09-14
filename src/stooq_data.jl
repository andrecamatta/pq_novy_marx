# Stooq.com Data Module
# ⚠️  MANUAL BULK ONLY - Downloads automáticos desabilitados devido a CAPTCHA
# Processa dados históricos apenas do arquivo bulk manual (d_us_txt.zip)

module StooqData

using HTTP, CSV, DataFrames, Dates, Downloads, ZipFile
using FileIO  # needed for `save`/`load` with .jld2

# Importar sistema de configuração YAML
include("ticker_config.jl")
using .TickerConfig

export download_stooq_bulk_us_selective, parse_stooq_csv, clean_stooq_ticker


"""
Limpa e converte ticker para formato Stooq.com.
"""
function clean_stooq_ticker(ticker::String)::String
    ticker = strip(uppercase(ticker))
    
    # Usar lookup rápido com cache para performance máxima
    try
        ticker = TickerConfig.fast_ticker_lookup(ticker)
    catch e
        # Fallback temporário com mapeamentos críticos
        ticker_map = Dict(
            "ANTM" => "ELV",
            "FB" => "META", 
            "COG" => "CTRA",
            "CTL" => "LUMN",
            "FISV" => "FI",
            "NLOK" => "GEN",
            "VIAC" => "PARA",
            "MYL" => "VTRS",
            "DWDP" => "DD",
            "BRK.B" => "BRK-B",
            "BF.B" => "BF-B"
        )
        ticker = get(ticker_map, ticker, ticker)
    end
    
    # Mapeamentos específicos para formato Stooq (agora apenas formatação, não resolução)
    stooq_format_map = Dict(
        # Índices mantêm formato especial
        "SPX" => "^SPX",
        "SP500" => "^SPX", 
        "S&P500" => "^SPX"
    )
    
    # Aplicar formatação específica do Stooq se existir
    if haskey(stooq_format_map, ticker)
        return stooq_format_map[ticker]
    end
    
    # Se é um índice (começa com ^), manter como está
    if startswith(ticker, "^")
        return ticker
    end
    
    # Se não tem sufixo e não é um índice, adicionar .US
    if !contains(ticker, ".")
        return "$ticker.US"
    end
    
    return ticker
end



"""
Parseia CSV do Stooq.com para DataFrame.
"""
function parse_stooq_csv(csv_content::String, ticker::String; verbose::Bool = true)::DataFrame
    try
        # Criar DataFrame temporário a partir do CSV
        io = IOBuffer(csv_content)
        
        # O formato bulk tem diferentes colunas: <TICKER>,<PER>,<DATE>,<TIME>,<OPEN>,<HIGH>,<LOW>,<CLOSE>,<VOL>,<OPENINT>
        temp_df = CSV.read(io, DataFrame, header=1, delim=',')
        
        # Verificar se tem as colunas esperadas (formato bulk ou formato web)
        bulk_cols = ["<DATE>", "<OPEN>", "<HIGH>", "<LOW>", "<CLOSE>", "<VOL>"]
        web_cols = ["Date", "Open", "High", "Low", "Close", "Volume"]
        
        is_bulk_format = all(col in string.(names(temp_df)) for col in bulk_cols)
        is_web_format = all(col in string.(names(temp_df)) for col in web_cols)
        
        if is_bulk_format
            # Formato bulk do Stooq
            renamed_df = DataFrame(
                date = temp_df[!, "<DATE>"],
                open = temp_df[!, "<OPEN>"],
                high = temp_df[!, "<HIGH>"],
                low = temp_df[!, "<LOW>"],
                close = temp_df[!, "<CLOSE>"],
                volume = temp_df[!, "<VOL>"]
            )
            temp_df = renamed_df
        elseif is_web_format
            # Formato web do Stooq
            rename!(temp_df, 
                :Date => :date,
                :Open => :open, 
                :High => :high,
                :Low => :low,
                :Close => :close,
                :Volume => :volume
            )
        else
            if verbose
                println("   ⚠️ Formato não reconhecido. Colunas disponíveis: $(names(temp_df))")
            end
            # Tentar com nomes alternativos
            col_mapping = Dict(
                "Date" => ["Date", "date", "DATA", "DATE"],
                "Open" => ["Open", "open", "OPEN", "Abertura"],
                "High" => ["High", "high", "HIGH", "Máxima"],
                "Low" => ["Low", "low", "LOW", "Mínima"],
                "Close" => ["Close", "close", "CLOSE", "Fechamento"],
                "Volume" => ["Volume", "volume", "VOLUME", "Vol", "VOL"]
            )
            
            # Mapear colunas se possível
            renamed_df = DataFrame()
            for (std_name, alternatives) in col_mapping
                found_col = nothing
                for alt in alternatives
                    if alt in names(temp_df)
                        found_col = alt
                        break
                    end
                end
                
                if found_col !== nothing
                    renamed_df[!, Symbol(lowercase(std_name))] = temp_df[!, found_col]
                end
            end
            
            if ncol(renamed_df) < 5  # Precisamos pelo menos Date, OHLC, Volume
                error("Não foi possível mapear colunas necessárias")
            end
            
            temp_df = renamed_df
        end
        
        # Converter coluna de data
        if eltype(temp_df.date) == String
            temp_df.date = Date.(temp_df.date, "yyyy-mm-dd")
        elseif eltype(temp_df.date) <: Integer
            # Formato bulk: data como inteiro yyyymmdd (ex: 19840907)
            temp_df.date = [Date(div(d, 10000), div(mod(d, 10000), 100), mod(d, 100)) for d in temp_df.date]
        end
        
        # Converter colunas numéricas
        for col in [:open, :high, :low, :close]
            if col in names(temp_df)
                temp_df[!, col] = Float64.(temp_df[!, col])
            end
        end
        
        if :volume in names(temp_df)
            temp_df.volume = Int64.(temp_df.volume)
        else
            temp_df.volume = zeros(Int64, nrow(temp_df))
        end
        
        # Ordenar por data
        sort!(temp_df, :date)
        
        # Remover linhas com dados inválidos
        temp_df = filter(row -> 
            !ismissing(row.date) && 
            !ismissing(row.close) && 
            row.close > 0, temp_df)
        
        return temp_df
        
    catch e
        if verbose
            println("   ❌ Erro parseando CSV para $ticker: $e")
        end
        return DataFrame(
            date = Date[],
            open = Float64[],
            high = Float64[],
            low = Float64[],
            close = Float64[],
            volume = Int64[]
        )
    end
end


"""
Baixa dados de um subconjunto de tickers diretamente do ZIP bulk, sem carregar o índice inteiro.
Economiza memória em universos grandes.
"""
function download_stooq_bulk_us_selective(
    tickers::Vector{String};
    cache_dir::String = "data/cache/stooq_bulk",
    verbose::Bool = true
)::Dict{String, DataFrame}
    if verbose
        println("📦 Stooq bulk (selective ZIP scan) para $(length(tickers)) tickers...")
    end

    zip_file = joinpath(cache_dir, "d_us_txt.zip")
    if !isfile(zip_file)
        error("Arquivo bulk não encontrado: $zip_file")
    end

    # Preparar mapeamento de nomes de arquivos no ZIP -> ticker original
    config = TickerConfig.load_ticker_config()
    name_to_req = Dict{String, String}()
    for t in tickers
        # Resolver via YAML (se aplicável)
        resolved = try
            r = TickerConfig.resolve_ticker_with_config(t, config)
            r.resolved_ticker
        catch
            t
        end

        variations = String[
            t,
            uppercase(t),
            replace(uppercase(t), ".US" => ""),
            uppercase(resolved),
            replace(uppercase(resolved), "." => "-"),
            replace(uppercase(t), "." => "-"),
        ]

        # Adicionar variações com underscore (comum em alguns tickers)
        push!(variations, replace(uppercase(resolved), "-" => "_"))
        push!(variations, replace(uppercase(t), "-" => "_"))

        for v in variations
            base = lowercase(replace(v, ".US" => ""))
            if isempty(base)
                continue
            end
            fname = string(base, ".us.txt")
            # Priorizar primeira associação se houver colisões
            if !haskey(name_to_req, fname)
                name_to_req[fname] = t
            end
        end
    end

    results = Dict{String, DataFrame}()
    found = 0

    zr = ZipFile.Reader(zip_file)
    try
        for f in zr.files
            if endswith(f.name, ".us.txt") && contains(f.name, "daily/us/") && contains(f.name, "stocks/")
                fname = basename(f.name)
                if haskey(name_to_req, fname)
                    t_req = name_to_req[fname]
                    # Ler e parsear apenas este arquivo
                    content = String(read(f))
                    df = parse_stooq_csv(content, t_req, verbose=false)
                    if nrow(df) > 0
                        results[t_req] = df
                        found += 1
                        if verbose && found % 50 == 0
                            println("   📈 Encontrados: $found")
                        end
                        # Remover do mapa para facilitar early-stop
                        delete!(name_to_req, fname)
                        if isempty(name_to_req)
                            break
                        end
                    end
                end
            end
        end
    finally
        close(zr)
    end

    if verbose
        println("   ✅ Selective ZIP scan concluído: $found tickers encontrados")
    end

    return results
end

"""
Baixa arquivo bulk do Stooq e cria índice local para acesso rápido.
"""
function download_and_index_stooq_bulk(
    tickers::Vector{String}, 
    cache_dir::String, 
    verbose::Bool
)::Dict{String, DataFrame}
    
    if verbose
        println("   📥 Indexando arquivo bulk local do Stooq...")
    end
    
    # Arquivo local pré-baixado
    zip_file = joinpath(cache_dir, "d_us_txt.zip")
    
    try
        # Verificar se arquivo existe localmente
        if !isfile(zip_file)
            error("""
                ❌ Arquivo bulk não encontrado em: $zip_file
                
                📥 DOWNLOAD MANUAL OBRIGATÓRIO:
                1. Acesse: https://stooq.com/db/h/
                2. Baixe: 'US stocks daily' (arquivo d_us_txt.zip com ~500 MB)
                3. Coloque em: $zip_file
                
                Nota: Download automático não é possível devido a CAPTCHA.
            """)
        end
        
        # Verificar tamanho do arquivo
        file_size_mb = round(filesize(zip_file) / 1024 / 1024, digits=1)
        if file_size_mb < 100  # Arquivo deve ter pelo menos 100 MB
            error("Arquivo $zip_file parece estar corrompido (apenas $(file_size_mb) MB). Por favor baixe novamente.")
        end
        
        if verbose
            println("   ✅ Arquivo local encontrado: $(file_size_mb) MB")
            println("   📁 Caminho: $(zip_file)")
        end
        
        # Indexar todo o conteúdo
        stooq_index = index_stooq_zip(zip_file, verbose)
        
        # Salvar índice para uso futuro
        index_file = joinpath(cache_dir, "stooq_index.jld2")
        if verbose
            println("   💾 Salvando índice em $(index_file)...")
        end
        
        # Usar JLD2 para salvar o índice
        save(index_file, "stooq_data", stooq_index)
        
        # Extrair dados dos tickers solicitados
        return extract_tickers_from_index(tickers, stooq_index, verbose)
        
    catch e
        if verbose
            println("   ❌ Erro no download/indexação: $e")
        end
        return Dict{String, DataFrame}()
    end
end

"""
Indexa todo o conteúdo do ZIP do Stooq para acesso rápido.
"""
function index_stooq_zip(zip_file::String, verbose::Bool)::Dict{String, DataFrame}
    
    if verbose
        println("   📂 Indexando conteúdo do ZIP...")
    end
    
    stooq_data = Dict{String, DataFrame}()
    indexed_count = 0
    
    try
        zip_reader = ZipFile.Reader(zip_file)
        
        for file in zip_reader.files
            # Processar arquivos .txt em diretórios de ações US
            # Estrutura real: "data/daily/us/nasdaq stocks/[1-3]/ticker.us.txt"
            if endswith(file.name, ".us.txt") && 
               contains(file.name, "daily/us/") &&
               contains(file.name, "stocks/")
                
                # Extrair ticker do nome do arquivo
                # Exemplo: "data/daily/us/nasdaq stocks/1/aapl.us.txt" -> "AAPL"
                filename = basename(file.name)
                ticker_lower = replace(filename, ".us.txt" => "")
                ticker = uppercase(ticker_lower)
                
                try
                    content = String(read(file))
                    df = parse_stooq_csv(content, ticker, verbose=false)
                    
                    if nrow(df) > 0
                        stooq_data[ticker] = df
                        indexed_count += 1
                        
                        if verbose && indexed_count % 500 == 0
                            println("   📊 Indexados: $indexed_count tickers")
                        end
                    end
                    
                catch e
                    # Ignorar arquivos com problemas silenciosamente
                    continue
                end
            end
        end
        
        close(zip_reader)
        
        if verbose
            println("   ✅ Índice criado: $indexed_count tickers disponíveis")
        end
        
    catch e
        if verbose
            println("   ❌ Erro na indexação: $e")
        end
    end
    
    return stooq_data
end

"""
Carrega dados de tickers específicos do índice local Stooq (versão otimizada).
Carrega o índice uma única vez e processa todos os tickers de uma vez.
"""
function load_from_stooq_index_optimized(
    tickers::Vector{String}, 
    index_file::String, 
    verbose::Bool
)::Dict{String, DataFrame}
    
    if verbose
        println("   📁 Carregando dados do índice local (OTIMIZADO)...")
    end
    
    try
        # Carregar índice completo UMA ÚNICA VEZ
        stooq_data = load(index_file, "stooq_data")
        
        if verbose
            println("   ✅ Índice carregado: $(length(stooq_data)) tickers disponíveis")
        end
        
        return extract_tickers_from_index(tickers, stooq_data, verbose)
        
    catch e
        if verbose
            println("   ❌ Erro carregando índice: $e")
        end
        return Dict{String, DataFrame}()
    end
end

"""
Carrega dados do índice local do Stooq.
"""
function load_from_stooq_index(
    tickers::Vector{String}, 
    index_file::String, 
    verbose::Bool
)::Dict{String, DataFrame}
    
    if verbose
        println("   📁 Carregando dados do índice local...")
    end
    
    try
        # Carregar índice completo
        stooq_data = load(index_file, "stooq_data")
        
        if verbose
            println("   ✅ Índice carregado: $(length(stooq_data)) tickers disponíveis")
        end
        
        return extract_tickers_from_index(tickers, stooq_data, verbose)
        
    catch e
        if verbose
            println("   ❌ Erro carregando índice: $e")
        end
        return Dict{String, DataFrame}()
    end
end

"""
Extrai tickers específicos do índice.
"""
function extract_tickers_from_index(
    tickers::Vector{String}, 
    stooq_data::Dict{String, DataFrame}, 
    verbose::Bool
)::Dict{String, DataFrame}
    
    results = Dict{String, DataFrame}()
    found_count = 0
    
    for ticker in tickers
        # Tentar várias variações do ticker
        # Usar sistema YAML para gerar variações
        yaml_ticker = ticker
        try
            config = TickerConfig.load_ticker_config()
            resolution = TickerConfig.resolve_ticker_with_config(ticker, config)
            if resolution !== nothing && resolution.method != "no_resolution"
                yaml_ticker = resolution.resolved_ticker
            end
        catch e
            # Fallback se houver problema
        end
        
        variations = [
            ticker,
            uppercase(ticker),
            lowercase(ticker),  # Adicionar versão lowercase
            replace(uppercase(ticker), ".US" => ""),
            replace(lowercase(ticker), ".us" => ""),  # Lowercase sem .us
            yaml_ticker,  # Usar resolução YAML se disponível
            uppercase(yaml_ticker),
            lowercase(yaml_ticker),  # Adicionar yaml em lowercase
            replace(uppercase(yaml_ticker), ".US" => ""),
            replace(lowercase(yaml_ticker), ".us" => ""),  # Yaml lowercase sem .us
            replace(uppercase(yaml_ticker), "." => "-"),
            replace(lowercase(yaml_ticker), "." => "-"),  # Yaml lowercase com hífen
            replace(uppercase(ticker), "." => "-"),  # Classes de ações: ponto → hífen (legado)
            replace(lowercase(ticker), "." => "-")  # Lowercase com hífen
        ]
        
        found = false
        for variation in variations
            if haskey(stooq_data, variation)
                results[ticker] = stooq_data[variation]
                found_count += 1
                found = true
                break
            end
        end
        
        if !found && verbose && length(tickers) <= 20
            println("   ❓ $ticker não encontrado no índice")
        end
    end
    
    if verbose
        println("   ✅ Extraídos: $found_count de $(length(tickers)) tickers solicitados")
    end
    
    return results
end

"""
Converte resultado do Stooq para formato compatível com análises.
Retorna dados em formato padronizado para uso nas análises.
"""
function get_prices_stooq_compat(ticker::String; startdt::String, enddt::String, verbose::Bool = false)
    try
        start_date = Date(startdt)
        end_date = Date(enddt)
        
        full_data = download_stooq_ticker(ticker, start_date=start_date, end_date=end_date, verbose=verbose)
        
        if nrow(full_data) == 0
            return Dict(
                "timestamp" => Date[],
                "adjclose" => Float64[]
            )
        end
        
        return Dict(
            "timestamp" => full_data.date,
            "adjclose" => full_data.close  # Stooq já fornece preços ajustados
        )
        
    catch e
        if verbose
            println("❌ Erro em get_prices_stooq_compat para $ticker: $e")
        end
        return Dict(
            "timestamp" => Date[],
            "adjclose" => Float64[]
        )
    end
end

"""
Retorna status do arquivo ZIP bulk e do índice JLD2 (existência e tamanho).
"""
function get_bulk_download_status(; cache_dir::String = "data/cache/stooq_bulk")
    zip_file = joinpath(cache_dir, "d_us_txt.zip")
    index_file = joinpath(cache_dir, "stooq_index.jld2")

    zip_exists = isfile(zip_file)
    zip_size_mb = zip_exists ? round(filesize(zip_file) / 1024 / 1024, digits=1) : 0.0

    idx_exists = isfile(index_file)
    idx_size_mb = idx_exists ? round(filesize(index_file) / 1024 / 1024, digits=1) : 0.0

    return (
        zip_file = zip_file,
        zip_exists = zip_exists,
        zip_size_mb = zip_size_mb,
        index_file = index_file,
        index_exists = idx_exists,
        index_size_mb = idx_size_mb,
    )
end

end  # module StooqData
