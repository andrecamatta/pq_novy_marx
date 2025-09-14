"""
Adaptador de cache para compatibilidade com JLD2 existente
Corrige problemas de deserialização
"""
module CacheAdapter

using DataFrames, JLD2, Dates, CSV
using ..CacheManager
using ..SP500Constituents
using ..StooqData

export load_legacy_cache, convert_jld2_to_modern_cache

"""
    load_legacy_cache(file_path::String)::Dict{String, DataFrame}

Carrega cache JLD2 antigo com tratamento de erros de deserialização
"""
function load_legacy_cache(file_path::String)::Dict{String, DataFrame}
    println("📂 Tentando carregar cache JLD2: $file_path")

    try
        # Tentar carregamento direto primeiro
        data = JLD2.load(file_path)

        if haskey(data, "price_data")
            price_data = data["price_data"]

            # Se for SerializedDict, tentar converter
            if isa(price_data, JLD2.SerializedDict)
                println("⚠️  Cache serializado detectado, convertendo...")
                return convert_serialized_dict(price_data)
            elseif isa(price_data, Dict)
                println("✅ Cache direto carregado: $(length(price_data)) tickers")
                return normalize_dataframes(price_data)
            else
                println("⚠️  Tipo não reconhecido: $(typeof(price_data))")
                return Dict{String, DataFrame}()
            end
        else
            println("⚠️  Chave 'price_data' não encontrada")
            return Dict{String, DataFrame}()
        end

    catch e
        println("❌ Erro ao carregar cache JLD2: $e")
        return Dict{String, DataFrame}()
    end
end

"""
    convert_serialized_dict(serialized_dict)::Dict{String, DataFrame}

Converte JLD2.SerializedDict para Dict{String, DataFrame}
"""
function convert_serialized_dict(serialized_dict)::Dict{String, DataFrame}
    result = Dict{String, DataFrame}()

    try
        # Tentar extrair dados manualmente
        for (key, value) in pairs(serialized_dict)
            try
                if isa(value, DataFrame) || (hasmethod(DataFrame, (typeof(value),)))
                    result[string(key)] = DataFrame(value)
                end
            catch
                continue
            end
        end

        println("✅ Convertidos $(length(result)) tickers do cache serializado")

    catch e
        println("❌ Erro na conversão: $e")
    end

    return result
end

"""
    normalize_dataframes(price_data::Dict{String, DataFrame})::Dict{String, DataFrame}

Normaliza nomes de colunas dos DataFrames para garantir compatibilidade
"""
function normalize_dataframes(price_data::Dict{String, DataFrame})::Dict{String, DataFrame}
    normalized_data = Dict{String, DataFrame}()

    for (ticker, df) in price_data
        if isempty(df)
            continue
        end

        # Criar cópia para não modificar original
        normalized_df = copy(df)

        # Mapear nomes de colunas comuns
        column_mapping = Dict{String, String}(
            "date" => "Date",
            "price" => "Close",  # Mapear price para Close
            "open" => "Open",
            "high" => "High",
            "low" => "Low",
            "close" => "Close",
            "volume" => "Volume",
            "adj_close" => "AdjClose",
            "adjClose" => "AdjClose"
        )

        # Renomear colunas se existirem
        for (old_name, new_name) in column_mapping
            if old_name in names(normalized_df)
                rename!(normalized_df, old_name => new_name)
            end
        end

        # Verificar se tem colunas mínimas necessárias
        required_cols = ["Date", "Close"]
        has_required = all(col -> col in names(normalized_df), required_cols)

        if has_required
            # Adicionar colunas OHLC faltantes usando Close se necessário
            if !("Open" in names(normalized_df))
                normalized_df.Open = normalized_df.Close
            end
            if !("High" in names(normalized_df))
                normalized_df.High = normalized_df.Close
            end
            if !("Low" in names(normalized_df))
                normalized_df.Low = normalized_df.Close
            end
            if !("Volume" in names(normalized_df))
                normalized_df.Volume = fill(1000000, nrow(normalized_df))  # Volume padrão
            end
            # Converter coluna Date se necessário
            if eltype(normalized_df.Date) != Date
                try
                    if eltype(normalized_df.Date) <: AbstractString
                        normalized_df.Date = Date.(normalized_df.Date)
                    end
                catch
                    continue  # Skip se não conseguir converter
                end
            end

            # Ordenar por data
            sort!(normalized_df, :Date)

            normalized_data[ticker] = normalized_df
        end
    end

    return normalized_data
end

"""
    convert_jld2_to_modern_cache(old_file::String, output_dir::String="data/cache/converted")

Converte cache JLD2 antigo para formato moderno
"""
function convert_jld2_to_modern_cache(old_file::String, output_dir::String="data/cache/converted")
    mkpath(output_dir)

    println("🔄 Convertendo cache JLD2 para formato moderno...")

    # Carregar dados antigos
    old_data = load_legacy_cache(old_file)

    if isempty(old_data)
        println("❌ Nenhum dado para converter")
        return false
    end

    # Salvar no novo formato
    success_count = 0
    for (ticker, df) in old_data
        if !isempty(df) && nrow(df) > 0
            try
                cache_key = "$(ticker)_legacy_converted"
                save_cache("prices", cache_key, df)
                success_count += 1
            catch e
                println("⚠️  Erro ao salvar $ticker: $e")
            end
        end
    end

    println("✅ Cache convertido: $success_count tickers salvos em $output_dir")
    return success_count > 0
end

"""
    load_available_cache_data(start_date::Date, end_date::Date)::Dict{String, DataFrame}

Carrega todos os dados disponíveis em cache (JLD2 + CSV)
"""
function load_available_cache_data(start_date::Date, end_date::Date)::Dict{String, DataFrame}
    println("📂 Carregando dados de todos os caches disponíveis...")
    println("🔍 DETALHAMENTO DE CACHES:")

    price_data = Dict{String, DataFrame}()
    cache_hits = 0
    cache_misses = 0

    # 1. Tentar carregar cache JLD2 legacy
    jld2_files = [
        "data/cache/data_10182009528636122451.jld2",
        "data/cache/data_11486366684984746809.jld2",
        "data/cache/data_12423095779436327369.jld2"
    ]

    for jld2_file in jld2_files
        if isfile(jld2_file)
            println("📦 Carregando JLD2 legacy: $(basename(jld2_file))")
            jld2_data = load_legacy_cache(jld2_file)

            # Filtrar por período e qualidade
            for (ticker, df) in jld2_data
                if !isempty(df) && nrow(df) > 50  # Mínimo 50 observações
                    # Verificar se tem dados no período
                    if "Date" in names(df) || "date" in names(df)
                        date_col = "Date" in names(df) ? df[!, "Date"] : df[!, "date"]
                        period_data = filter(row -> start_date <= row <= end_date, date_col)

                        if length(period_data) > 20  # Pelo menos 20 observações no período
                            # Não sobrescrever se já temos dados para o ticker
                            if !haskey(price_data, ticker)
                                price_data[ticker] = df
                                cache_hits += 1
                            end
                        end
                    end
                end
            end

            if !isempty(jld2_data)
                println("✅ JLD2 $jld2_file: $(length(jld2_data)) tickers (mesclados)")
            end
        end
    end

    # 2. Complementar com cache Tiingo (CSV e JLD2)
    tiingo_dir = "data/cache/tiingo"
    if isdir(tiingo_dir)
        files = readdir(tiingo_dir)

        # 2a. Ler arquivos CSV (se existirem)
        for csv_file in filter(f -> endswith(f, ".csv"), files)
            ticker = split(split(csv_file, "_")[1], ".")[1]
            if !haskey(price_data, ticker)
                try
                    df = CSV.read(joinpath(tiingo_dir, csv_file), DataFrame)
                    if nrow(df) > 20
                        # Normalizar colunas
                        normalized = normalize_dataframes(Dict(ticker => df))
                        if haskey(normalized, ticker)
                            price_data[ticker] = normalized[ticker]
                        end
                    end
                catch
                    continue
                end
            end
        end

        # 2b. Ler arquivos JLD2 (padrão do TiingoData)
        tiingo_jld2_count = 0
        for jfile in filter(f -> endswith(f, ".jld2"), files)
            # Extrair ticker do nome do arquivo (TICKER_START_END.jld2)
            base = split(jfile, ".")[1]
            parts = split(base, "_")
            if isempty(parts)
                continue
            end
            ticker = parts[1]
            if haskey(price_data, ticker)
                continue
            end
            try
                path = joinpath(tiingo_dir, jfile)
                data = JLD2.load(path)
                if haskey(data, "tiingo_data")
                    df = data["tiingo_data"]
                    if isa(df, DataFrame) && nrow(df) > 20
                        # Normalizar colunas: date->Date, close->Close etc
                        normalized = normalize_dataframes(Dict(ticker => df))
                        if haskey(normalized, ticker)
                            # Filtrar período para garantir cobertura mínima
                            nd = normalized[ticker]
                            if "Date" in names(nd)
                                dvec = nd[!, "Date"]
                                has_period = any(d -> start_date <= d <= end_date, dvec)
                                if has_period
                                    price_data[ticker] = nd
                                    cache_hits += 1
                                    tiingo_jld2_count += 1
                                end
                            end
                        end
                    end
                end
            catch
                continue
            end
        end

        println("✅ Cache Tiingo JLD2: $tiingo_jld2_count tickers carregados")
        println("📊 Total cache hits: $cache_hits tickers")
    end

    # 3. Complementar com Stooq INDEX (JLD2) para tickers do universo que ainda faltam
    try
        index_status = StooqData.get_bulk_download_status()
        if index_status.index_exists
            # Universo alvo do período
            universe = SP500Constituents.get_universe_for_period(start_date, end_date)
            missing = [t for t in universe if !haskey(price_data, t)]

            if !isempty(missing)
                println("🔎 Stooq index: tentando completar $(length(missing)) tickers ausentes...")
                # Carregar somente os ausentes a partir do índice
                stooq_dict = StooqData.load_from_stooq_index_optimized(missing, index_status.index_file, false)

                if !isempty(stooq_dict)
                    # Normalizar colunas e filtrar período
                    normalized = normalize_dataframes(Dict{String, DataFrame}(stooq_dict))
                    added = 0
                    for (ticker, df) in normalized
                        if !isempty(df)
                            d = df[!, "Date"]
                            if any(x -> start_date <= x <= end_date, d)
                                if !haskey(price_data, ticker)
                                    price_data[ticker] = df
                                    added += 1
                                end
                            end
                        end
                    end
                    println("✅ Stooq index: adicionados $added tickers")
                else
                    println("⚠️ Stooq index não retornou dados para os ausentes")
                end
            end
        else
            println("ℹ️  Índice Stooq não encontrado; pulando etapa")
        end
    catch e
        println("⚠️  Erro ao complementar com Stooq index: $e")
    end

    println("📊 Total de dados carregados: $(length(price_data)) tickers")
    return price_data
end

end # module
