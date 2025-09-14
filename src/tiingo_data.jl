# Tiingo Data Module
# API client for accessing historical stock data from Tiingo.com
# Used as fallback for delisted tickers not available in Stooq bulk data

module TiingoData

using HTTP, JSON, DataFrames, Dates, Statistics
using FileIO  # for cache with .jld2

export get_historical_prices, test_tiingo_connection, get_tiingo_status,
       clear_tiingo_cache, check_rate_limit_status, search_ticker,
       download_tiingo_eod

# =================================================================
# RATE LIMITING
# =================================================================

mutable struct DailyRateLimiter
    requests_today::Int
    last_reset::Date  
    daily_limit::Int
    enabled::Bool
end

"""
    download_tiingo_eod(ticker, start_date, end_date; use_cache=true, cache_dir, verbose=true)

Compat: baixa dados via Tiingo e retorna DataFrame padronizado com colunas 'Date', 'Open', 'High', 'Low', 'Close', 'Volume'.
"""
function download_tiingo_eod(
    ticker::String,
    start_date::Date,
    end_date::Date;
    use_cache::Bool = true,
    cache_dir::String = "data/cache/tiingo",
    verbose::Bool = true
)::DataFrame
    raw = get_historical_prices(
        ticker;
        start_date=start_date,
        end_date=end_date,
        use_cache=use_cache,
        cache_dir=cache_dir,
        verbose=verbose
    )

    if isempty(raw)
        return raw  # vazio compatível
    end

    # Normalizar nomes de colunas
    df = copy(raw)
    if "date" in names(df)
        rename!(df, "date" => "Date")
    end
    if "open" in names(df)
        rename!(df, "open" => "Open")
    end
    if "high" in names(df)
        rename!(df, "high" => "High")
    end
    if "low" in names(df)
        rename!(df, "low" => "Low")
    end
    if "close" in names(df)
        rename!(df, "close" => "Close")
    end
    if "volume" in names(df)
        rename!(df, "volume" => "Volume")
    end

    # Garantir tipos corretos
    if eltype(df[!, "Date"]) != Date
        try
            df[!, "Date"] = Date.(df[!, "Date"])
        catch
            return raw
        end
    end

    sort!(df, :Date)
    return df
end

# Global rate limiter instance
const RATE_LIMITER = DailyRateLimiter(0, today() - Day(1), 1000, true)

"""
Verifica se ainda há requests disponíveis hoje.
"""
function check_rate_limit()
    if !RATE_LIMITER.enabled
        return true
    end
    
    # Reset contador se mudou o dia
    if RATE_LIMITER.last_reset < today()
        RATE_LIMITER.requests_today = 0
        RATE_LIMITER.last_reset = today()
    end
    
    # Verificar limite
    if RATE_LIMITER.requests_today >= RATE_LIMITER.daily_limit
        error("Limite diário Tiingo atingido: $(RATE_LIMITER.daily_limit) requests. " *
              "Aguarde até amanhã ou obtenha plano pago.")
    end
    
    return true
end

"""
Incrementa contador de requests.
"""
function increment_request_count()
    if RATE_LIMITER.enabled
        RATE_LIMITER.requests_today += 1
    end
end

"""
Retorna status do rate limiting.
"""
function get_rate_limit_status()
    if RATE_LIMITER.last_reset < today()
        remaining = RATE_LIMITER.daily_limit
    else
        remaining = RATE_LIMITER.daily_limit - RATE_LIMITER.requests_today
    end
    
    return (
        requests_today = RATE_LIMITER.requests_today,
        daily_limit = RATE_LIMITER.daily_limit,
        requests_remaining = remaining,
        reset_date = RATE_LIMITER.last_reset + Day(1)
    )
end

"""
Status público do rate limiting.
"""
function check_rate_limit_status()
    status = get_rate_limit_status()
    println("📊 Status Tiingo Rate Limiting:")
    println("   Requests hoje: $(status.requests_today)/$(status.daily_limit)")
    println("   Restantes: $(status.requests_remaining)")
    if status.requests_remaining == 0
        println("   ⚠️  Limite atingido! Reset em: $(status.reset_date)")
    end
    return status
end

# =================================================================
# API CONFIGURATION
# =================================================================

"""
Obter API key do ambiente ou arquivo .env.
"""
function get_api_key()::String
    # Primeiro tentar variável de ambiente
    api_key = get(ENV, "TIINGO_API_KEY", "")
    
    # Se não encontrou, tentar carregar do arquivo .env
    if isempty(api_key) || api_key == "YOUR_API_KEY_HERE"
        env_file = joinpath(@__DIR__, "..", ".env")
        if isfile(env_file)
            try
                lines = readlines(env_file)
                for line in lines
                    if startswith(line, "TIINGO_API_KEY=") && !startswith(line, "#")
                        api_key = strip(split(line, "=", limit=2)[2])
                        if !isempty(api_key) && api_key != "YOUR_API_KEY_HERE"
                            # Setar na variável de ambiente para uso futuro
                            ENV["TIINGO_API_KEY"] = api_key
                            return api_key
                        end
                    end
                end
            catch e
                @warn "Erro lendo arquivo .env: $e"
            end
        end
        return ""
    end
    
    return api_key
end

"""
Verificar se API key está configurada.
"""
function has_api_key()::Bool
    return !isempty(get_api_key())
end

# =================================================================
# CACHE SYSTEM
# =================================================================

"""
Gerar chave de cache para ticker e período.
"""
function cache_key(ticker::String, start_date::Date, end_date::Date)::String
    return "$(ticker)_$(start_date)_$(end_date).jld2"
end

"""
Obter dados do cache se disponível.
"""
function get_from_cache(ticker::String, start_date::Date, end_date::Date, cache_dir::String)
    cache_path = joinpath(cache_dir, cache_key(ticker, start_date, end_date))
    
    if isfile(cache_path)
        try
            data = load(cache_path, "tiingo_data")
            return data
        catch
            # Cache corrompido, remover
            rm(cache_path, force=true)
            return nothing
        end
    end
    
    return nothing
end

"""
Salvar dados no cache.
"""
function save_to_cache(data::DataFrame, ticker::String, start_date::Date, 
                       end_date::Date, cache_dir::String)
    try
        mkpath(cache_dir)
        cache_path = joinpath(cache_dir, cache_key(ticker, start_date, end_date))
        save(cache_path, "tiingo_data", data)
    catch e
        # Falha no cache não é crítica
        @warn "Erro salvando cache Tiingo: $e"
    end
end

"""
Limpar todo o cache do Tiingo.
"""
function clear_tiingo_cache(cache_dir::String = "data/cache/tiingo")
    if isdir(cache_dir)
        for file in readdir(cache_dir)
            if endswith(file, ".jld2")
                rm(joinpath(cache_dir, file), force=true)
            end
        end
        println("🗑️  Cache Tiingo limpo: $cache_dir")
    end
end

# =================================================================
# API CLIENT
# =================================================================

"""
Buscar dados históricos de um ticker via API Tiingo.
"""
function get_historical_prices(
    ticker::String;
    start_date::Date,
    end_date::Date,
    use_cache::Bool = true,
    cache_dir::String = "data/cache/tiingo",
    verbose::Bool = true
)::DataFrame
    
    if verbose
        println("📊 Buscando $ticker via Tiingo API...")
    end
    
    # Verificar API key
    if !has_api_key()
        if verbose
            println("   ⚠️  API key Tiingo não configurada, retornando vazio")
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
    
    # Verificar cache primeiro
    if use_cache
        cached_data = get_from_cache(ticker, start_date, end_date, cache_dir)
        if cached_data !== nothing
            if verbose
                println("   📂 Dados encontrados no cache ($(nrow(cached_data)) pontos)")
            end
            return cached_data
        end
    end
    
    try
        # Verificar rate limit
        check_rate_limit()
        
        # Preparar request
        api_key = get_api_key()
        url = "https://api.tiingo.com/tiingo/daily/$(ticker)/prices"
        
        params = Dict(
            "startDate" => string(start_date),
            "endDate" => string(end_date),
            "token" => api_key,
            "format" => "json"
        )
        
        if verbose
            println("   🌐 Fazendo request para Tiingo API...")
        end
        
        # HTTP request com timeout
        response = HTTP.get(url, query=params, readtimeout=30)
        increment_request_count()

        if response.status != 200
            error("HTTP $(response.status)")
        end
        
        # Parse JSON response
        data = JSON.parse(String(response.body))
        
        if isempty(data)
            if verbose
                println("   ❌ Nenhum dado retornado pela API")
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
        
        # Converter para DataFrame
        df = parse_tiingo_response(data, ticker)
        
        # Filtrar por período (API pode retornar mais dados)
        df = filter(row -> row.date >= start_date && row.date <= end_date, df)
        
        if verbose
            if nrow(df) > 0
                println("   ✅ $(nrow(df)) pontos obtidos ($(minimum(df.date)) a $(maximum(df.date)))")
            else
                println("   ❌ Nenhum dado no período solicitado")
            end
        end
        
        # Salvar no cache
        if use_cache && nrow(df) > 0
            save_to_cache(df, ticker, start_date, end_date, cache_dir)
        end
        
        return df
        
    catch e
        # Tratamento simples de erros
        if verbose
            println("   ❌ Erro na API Tiingo: $e")
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
Parser da resposta JSON do Tiingo para DataFrame.
"""
function parse_tiingo_response(data::Vector, ticker::String)::DataFrame
    dates = Date[]
    opens = Float64[]
    highs = Float64[]
    lows = Float64[]
    closes = Float64[]
    volumes = Int64[]
    
    for row in data
        try
            # Tiingo retorna datas no formato ISO
            date_str = row["date"][1:10]  # Pegar apenas YYYY-MM-DD
            push!(dates, Date(date_str))
            
            push!(opens, Float64(row["open"]))
            push!(highs, Float64(row["high"]))
            push!(lows, Float64(row["low"]))
            push!(closes, Float64(row["adjClose"]))  # Usar preço ajustado
            push!(volumes, Int64(get(row, "volume", 0)))
        catch e
            # Ignorar linha com erro
            @warn "Erro parseando linha Tiingo para $ticker: $e"
            continue
        end
    end
    
    df = DataFrame(
        date = dates,
        open = opens,
        high = highs,
        low = lows,
        close = closes,
        volume = volumes
    )
    
    # Ordenar por data
    sort!(df, :date)
    
    return df
end

# =================================================================
# UTILITIES
# =================================================================

"""
Testar conexão com API Tiingo.
"""
function test_tiingo_connection(;verbose::Bool = true)::Bool
    if verbose
        println("🔗 Testando conexão com Tiingo API...")
    end
    
    if !has_api_key()
        if verbose
            println("❌ API key não configurada")
        end
        return false
    end
    
    try
        # Testar com AAPL - dados sempre disponíveis
        test_data = get_historical_prices("AAPL", 
                                          start_date=today()-Day(30), 
                                          end_date=today()-Day(1),
                                          use_cache=false,
                                          verbose=false)
        
        if nrow(test_data) > 0
            if verbose
                println("✅ Conexão bem-sucedida!")
                println("   $(nrow(test_data)) pontos de teste obtidos")
                status = get_rate_limit_status()
                println("   Rate limit: $(status.requests_today)/$(status.daily_limit) requests hoje")
            end
            return true
        else
            if verbose
                println("❌ Conexão falhou - nenhum dado retornado")
            end
            return false
        end
        
    catch e
        if verbose
            println("❌ Erro na conexão: $e")
        end
        return false
    end
end

"""
Status geral do sistema Tiingo.
"""
function get_tiingo_status()
    println("📊 Status do Sistema Tiingo:")
    println("="^50)
    
    # API Key
    if has_api_key()
        println("🔑 API Key: ✅ Configurada")
    else
        println("🔑 API Key: ❌ Não configurada ou inválida")
        println("   Configure TIINGO_API_KEY no arquivo .env")
        return
    end
    
    # Conexão
    if test_tiingo_connection(verbose=false)
        println("🌐 Conexão: ✅ Funcionando")
    else
        println("🌐 Conexão: ❌ Falha")
        return
    end
    
    # Rate limiting
    status = get_rate_limit_status()
    println("📊 Rate Limit:")
    println("   Requests hoje: $(status.requests_today)/$(status.daily_limit)")
    println("   Restantes: $(status.requests_remaining)")
    
    # Cache
    cache_dir = get(ENV, "TIINGO_CACHE_DIR", "data/cache/tiingo")
    if isdir(cache_dir)
        cache_files = length([f for f in readdir(cache_dir) if endswith(f, ".jld2")])
        println("💾 Cache: $cache_files arquivos em $cache_dir")
    else
        println("💾 Cache: Diretório não existe")
    end
    
    println("\n✅ Sistema Tiingo operacional!")
end

"""
Buscar informações de ticker usando a Tiingo Search API.
Útil para encontrar tickers alternativos ou resolver problemas de símbolo.
"""
function search_ticker(query::String; verbose::Bool = true)::Vector{Dict{String, Any}}
    if verbose
        println("🔍 Buscando ticker '$query' via Tiingo Search...")
    end

    # Verificar API key
    if !has_api_key()
        if verbose
            println("   ⚠️  API key Tiingo não configurada")
        end
        return Dict{String, Any}[]
    end

    try
        # Verificar rate limit
        check_rate_limit()

        # Preparar request
        api_key = get_api_key()
        url = "https://api.tiingo.com/tiingo/utilities/search"

        params = Dict(
            "query" => query,
            "token" => api_key,
            "format" => "json"
        )

        if verbose
            println("   🌐 Fazendo request para Tiingo Search API...")
        end

        # HTTP request com timeout
        response = HTTP.get(url, query=params, readtimeout=30)
        increment_request_count()

        if response.status != 200
            error("HTTP $(response.status)")
        end

        # Parse JSON response
        results = JSON.parse(String(response.body))

        if isempty(results)
            if verbose
                println("   ❌ Nenhum resultado encontrado")
            end
            return Dict{String, Any}[]
        end

        if verbose
            println("   ✅ $(length(results)) resultado(s) encontrado(s)")
            for (i, result) in enumerate(results)
                ticker = get(result, "ticker", "N/A")
                name = get(result, "name", "N/A")
                permaTicker = get(result, "permaTicker", "N/A")
                assetType = get(result, "assetType", "N/A")
                println("   $i. $ticker - $name ($assetType)")
                if permaTicker != ticker && permaTicker != "N/A"
                    println("      PermaID: $permaTicker")
                end
            end
        end

        return results

    catch e
        # Tratamento simples de erros
        if verbose
            println("   ❌ Erro na Tiingo Search API: $e")
        end
        return Dict{String, Any}[]
    end
end

end  # module TiingoData
