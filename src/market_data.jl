# Real Market Data Module
# Downloads actual stock price data using hybrid Stooq bulk + Tiingo system
# Creates portfolios based on real historical volatility

module MarketData

using CSV, DataFrames, Dates, Statistics, StatsBase, JSON

# Importar módulo Stooq
include("stooq_data.jl")
using .StooqData

# Importar sistema de resolução de tickers
include("ticker_resolver.jl")
using .TickerResolver

# Importar sistema Tiingo
include("tiingo_data.jl")
using .TiingoData

export load_sp500_constituents, download_stock_data, calculate_returns, 
       create_volatility_quintile_portfolios_pti,
       save_price_cache, load_price_cache, cache_exists, calculate_daily_returns, 
       calculate_252d_volatility, load_historical_sp500_constituents, get_universe_for_period,
       get_eligible_tickers_for_date, clean_ticker_for_stooq, get_quintile_portfolios_pti,
       get_valid_tickers_for_month, get_ticker_validity_period, create_validity_metadata,
       get_ticker_data_hybrid, load_ticker_mappings, test_hybrid_system,
       download_stock_data_hybrid

# =================================================================
# SISTEMA HÍBRIDO STOOQ + TIINGO
# =================================================================

# Cache global para mapeamentos
const TICKER_MAPPINGS_CACHE = Ref{Union{Dict, Nothing}}(nothing)

"""
Carregar mapeamentos de ticker do arquivo JSON.
"""
function load_ticker_mappings(;force_reload::Bool = false)::Dict
    if TICKER_MAPPINGS_CACHE[] !== nothing && !force_reload
        return TICKER_MAPPINGS_CACHE[]
    end
    
    mappings_file = joinpath(@__DIR__, "..", "data", "ticker_mappings.json")
    
    if isfile(mappings_file)
        try
            data = JSON.parsefile(mappings_file)
            TICKER_MAPPINGS_CACHE[] = data
            return data
        catch e
            @warn "Erro carregando mapeamentos: $e"
            return Dict("renames" => Dict())
        end
    else
        @warn "Arquivo de mapeamentos não encontrado: $mappings_file"
        return Dict("renames" => Dict())
    end
end

"""
Obter dados de ticker usando sistema híbrido Stooq bulk + Tiingo.

Lógica:
1. Verificar se é renomeação → usar novo símbolo no Stooq
2. Tentar Stooq bulk primeiro (sem limites de API)  
3. Se não encontrar → fallback para Tiingo (provavelmente delistado)
"""
function get_ticker_data_hybrid(
    ticker::String, 
    start_date::Date, 
    end_date::Date;
    verbose::Bool = true,
    use_tiingo::Bool = true
)::DataFrame
    
    if verbose
        println("🔄 Buscando $ticker via sistema híbrido...")
    end
    
    # Carregar mapeamentos
    mappings = load_ticker_mappings()
    renames = get(mappings, "renames", Dict())
    acquired = get(mappings, "acquired_companies", Dict())
    
    # PASSO 1: Verificar se é renomeação
    actual_ticker = ticker
    if haskey(renames, ticker)
        actual_ticker = renames[ticker]
        if verbose
            println("   🔄 Renomeação detectada: $ticker → $actual_ticker")
        end
    end
    
    # PASSO 1.1: Verificar se é empresa adquirida
    is_acquired = haskey(acquired, ticker)
    acquisition_date = nothing
    if is_acquired
        acquisition_date = Date(acquired[ticker]["date"])
        if verbose
            println("   🏢 Empresa adquirida em $acquisition_date - usando Tiingo prioritário")
        end
    end
    
    # PASSO 2: Para empresas adquiridas, pular Stooq e ir direto ao Tiingo
    if !is_acquired
        # PASSO 2A: Tentar Stooq bulk primeiro (apenas se não for adquirida)
        if verbose && actual_ticker != ticker
            println("   📦 Buscando $actual_ticker no Stooq bulk...")
        else
            println("   📦 Buscando $ticker no Stooq bulk...")
        end
        
        try
            # Usar sistema de download bulk do Stooq
            stooq_data = download_stooq_bulk_us([actual_ticker], verbose=false)
            
            if haskey(stooq_data, actual_ticker) && nrow(stooq_data[actual_ticker]) > 0
                df = stooq_data[actual_ticker]
                
                # Filtrar por período
                df_filtered = filter(row -> row.date >= start_date && row.date <= end_date, df)
                
                if nrow(df_filtered) > 0
                    if verbose
                        println("   ✅ Stooq: $(nrow(df_filtered)) pontos ($(minimum(df_filtered.date)) a $(maximum(df_filtered.date)))")
                    end
                    return df_filtered
                end
            end
            
            if verbose
                println("   ❌ Stooq: Nenhum dado encontrado")
            end
            
        catch e
            if verbose
                println("   ❌ Erro no Stooq: $e")
            end
        end
    end
    
    # PASSO 3: Fallback para Tiingo (ticker original, não renomeado)
    if use_tiingo
        if verbose
            println("   🌐 Tentando Tiingo como fallback para $ticker...")
        end
        
        try
            tiingo_data = get_historical_prices(ticker,
                                              start_date=start_date,
                                              end_date=end_date,
                                              verbose=verbose)
            
            if nrow(tiingo_data) > 0
                if verbose
                    println("   ✅ Tiingo: $(nrow(tiingo_data)) pontos encontrados")
                end
                return tiingo_data
            else
                if verbose
                    println("   ❌ Tiingo: Nenhum dado encontrado")
                end
            end
            
        catch e
            if verbose
                println("   ❌ Erro no Tiingo: $e")
            end
        end
    end
    
    # Retornar DataFrame vazio se nada funcionar
    if verbose
        println("   ❌ Nenhuma fonte retornou dados para $ticker")
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

"""
Testar sistema híbrido com casos conhecidos.
"""
function test_hybrid_system(;verbose::Bool = true)
    test_cases = [
        ("AAPL", "ticker normal (deve usar Stooq)"),
        ("ANTM", "renomeado para ELV (deve mapear)"), 
        ("ABMD", "delistado (deve usar Tiingo)"),
        ("META", "ticker atual (deve usar Stooq)"),
        ("INVALID123", "ticker inexistente (deve falhar)")
    ]
    
    println("🧪 TESTE DO SISTEMA HÍBRIDO")
    println("=" * 60)
    
    test_start = Date(2022, 6, 1)
    test_end = Date(2022, 12, 31)
    
    for (ticker, description) in test_cases
        println("\n📊 Testando $ticker - $description")
        println("-" * 50)
        
        data = get_ticker_data_hybrid(ticker, test_start, test_end, verbose=verbose)
        
        if nrow(data) > 0
            println("   ✅ Sucesso: $(nrow(data)) pontos de dados")
            println("   📅 Período: $(minimum(data.date)) a $(maximum(data.date))")
        else
            println("   ❌ Falha: Nenhum dado obtido")
        end
    end
    
    println("\n🎯 Teste do sistema híbrido concluído!")
end

"""
Versão híbrida da função download_stock_data que usa Stooq + Tiingo.
Compatível com o sistema existente mas com maior taxa de sucesso.
"""
function download_stock_data_hybrid(
    tickers::Vector{String}, 
    start_date::Date, 
    end_date::Date; 
    verbose::Bool = true,
    use_tiingo::Bool = true,
    progress_interval::Int = 10
)::Dict{String, DataFrame}
    
    if verbose
        println("📊 Download híbrido para $(length(tickers)) tickers")
        println("   📅 Período: $start_date a $end_date")
        println("   🔧 Fontes: Stooq bulk + Tiingo fallback")
    end
    
    results = Dict{String, DataFrame}()
    failed_count = 0
    stooq_count = 0
    tiingo_count = 0
    
    for (i, ticker) in enumerate(tickers)
        if verbose && (i % progress_interval == 0 || i == length(tickers))
            println("   📈 Progresso: $i/$(length(tickers)) tickers processados")
        end
        
        data = get_ticker_data_hybrid(ticker, start_date, end_date, 
                                     verbose=false, use_tiingo=use_tiingo)
        
        if nrow(data) > 0
            # Converter para formato esperado pelo sistema existente
            formatted_data = DataFrame(
                date = data.date,
                price = data.close
            )
            results[ticker] = formatted_data
            
            # Contar fonte usada (verificar se foi renomeação ou não)
            mappings = load_ticker_mappings()
            renames = get(mappings, "renames", Dict())
            
            if haskey(renames, ticker) || nrow(data) > 50
                stooq_count += 1  # Provavelmente veio do Stooq
            else
                tiingo_count += 1  # Provavelmente veio do Tiingo
            end
        else
            failed_count += 1
        end
    end
    
    # Estatísticas finais
    success_count = length(results)
    success_rate = round(success_count / length(tickers) * 100, digits=1)
    
    if verbose
        println("\n📊 RESULTADOS DO DOWNLOAD HÍBRIDO:")
        println("="^50)
        println("✅ Sucessos: $success_count/$(length(tickers)) ($success_rate%)")
        println("❌ Falhas: $failed_count")
        println("📦 Via Stooq: ~$stooq_count tickers")
        println("🌐 Via Tiingo: ~$tiingo_count tickers")
        
        if failed_count > 0
            failure_rate = round(failed_count / length(tickers) * 100, digits=1)
            println("📉 Taxa de falha: $failure_rate%")
        end
    end
    
    return results
end

"""
Carrega os constituintes históricos do S&P 500 do arquivo CSV.
Retorna DataFrame com colunas: date, tickers
"""
function load_sp500_constituents(file_path::String = "data/sp_500_historical_components.csv")::DataFrame
    println("📊 Carregando constituintes históricos do S&P 500...")
    # Resolver caminho relativo ao pacote se necessário
    abs_path = isabspath(file_path) ? file_path : normpath(joinpath(@__DIR__, "..", file_path))
    df = CSV.read(abs_path, DataFrame)
    
    # Converter string de tickers para array
    df.tickers_array = [split(tickers, ",") for tickers in df.tickers]
    
    println("✅ Carregados $(nrow(df)) dias de dados históricos ($(minimum(df.date)) a $(maximum(df.date)))")
    return df
end

"""
Verifica se existe cache para um ticker específico.
"""
function cache_exists(ticker::String, cache_dir::String = "data/cache/prices")::Bool
    abs_cache_dir = isabspath(cache_dir) ? cache_dir : normpath(joinpath(@__DIR__, "..", cache_dir))
    cache_file = joinpath(abs_cache_dir, "$(ticker).csv")
    return isfile(cache_file)
end

"""
Convenience function: end-to-end build of P1..P5 PTI portfolios (Novy-Marx compliant).
Baixa preços (com cache), calcula retornos mensais, e forma quintis PTI com lag.

Parâmetros:
- start_date, end_date: período de preços
- method: :monthly12 (default) ou :daily252
- min_coverage: cobertura mínima (por quintil e janela de vol)
- min_per_quintile: mínimo de ações por quintil
- max_tickers: limite de tickers processados (controle operacional)
- force: força redownload de preços ignorando cache
"""
function get_quintile_portfolios_pti(
    start_date::Date,
    end_date::Date;
    method::Symbol = :monthly12,
    min_coverage::Float64 = 0.7,
    min_per_quintile::Int = 8,
    max_tickers::Int = 1500,
    force::Bool = false,
    verbose::Bool = true
)::DataFrame
    verbose && println("🚀 Construindo P1..P5 PTI (E2E)")
    # Universo PTI
    constituents_df = load_historical_sp500_constituents()
    uni = get_universe_for_period(start_date, end_date; constituents_df=constituents_df, verbose=verbose)
    clean_uni = [clean_ticker_for_stooq(t) for t in uni]
    if length(clean_uni) > max_tickers
        verbose && println("   ⚠️ Limitando universo a $max_tickers tickers (de $(length(clean_uni)))")
        clean_uni = clean_uni[1:max_tickers]
    end
    # Preços + retornos
    prices = download_stock_data(clean_uni, start_date, end_date; max_tickers=length(clean_uni), force=force, verbose=verbose)
    returns_df = calculate_returns(prices, start_date, end_date; verbose=verbose)
    # Quintis PTI
    portfolios_df = create_volatility_quintile_portfolios_pti(
        returns_df;
        method=method,
        price_data=prices,
        lookback = method == :monthly12 ? 12 : 252,
        min_coverage=min_coverage,
        min_per_quintile=min_per_quintile,
        constituents_df=constituents_df,
        verbose=verbose
    )
    return portfolios_df
end

"""
Salva dados de preços no cache.
"""
function save_price_cache(ticker::String, data::DataFrame, cache_dir::String = "data/cache/prices")::Nothing
    abs_cache_dir = isabspath(cache_dir) ? cache_dir : normpath(joinpath(@__DIR__, "..", cache_dir))
    mkpath(abs_cache_dir)
    cache_file = joinpath(abs_cache_dir, "$(ticker).csv")
    CSV.write(cache_file, data)
    return nothing
end

"""
Carrega dados de preços do cache.
"""
function load_price_cache(ticker::String, cache_dir::String = "data/cache/prices")::Union{DataFrame, Nothing}
    abs_cache_dir = isabspath(cache_dir) ? cache_dir : normpath(joinpath(@__DIR__, "..", cache_dir))
    cache_file = joinpath(abs_cache_dir, "$(ticker).csv")
    if isfile(cache_file)
        try
            return CSV.read(cache_file, DataFrame)
        catch e
            println("⚠️ Erro ao ler cache para $ticker: $e")
            return nothing
        end
    end
    return nothing
end

"""
Baixa dados de preços históricos usando bulk download do Stooq.com.
Muito mais rápido que downloads individuais - usa cache local inteligente.
"""
function download_stock_data(tickers::Vector{String}, start_date::Date, end_date::Date; 
                           max_tickers::Int = 1500, force::Bool = false, verbose::Bool = true, 
                           use_bulk::Bool = true, batch_size::Int = 50, delay_between_batches::Float64 = 2.0)::Dict{String, DataFrame}
    
    if verbose
        method_str = use_bulk ? "BULK ONLY" : "downloads individuais"
        println("📈 Baixando dados via $method_str do Stooq.com para $(length(tickers)) tickers...")
        println("   Período: $start_date a $end_date")
    end
    
    # Limitar número de tickers se necessário
    limited_tickers = tickers[1:min(length(tickers), max_tickers)]
    
    if verbose && length(tickers) > max_tickers
        println("   ⚠️ Limitando a $max_tickers tickers (de $(length(tickers)) disponíveis)")
    end
    
    # USAR BULK DOWNLOAD POR PADRÃO (com fallback para individuais)
    if use_bulk
        if verbose
            println("   📦 Usando sistema bulk download otimizado...")
        end
        
        # Usar bulk download do StooqData
        bulk_data = StooqData.download_stooq_bulk_us(
            limited_tickers,
            force_download=force,
            verbose=verbose
        )
        
        # Converter formato para compatibilidade
        bulk_data_dict = Dict{String, DataFrame}()
        
        for (ticker, raw_data) in bulk_data
            if nrow(raw_data) > 0
                # Filtrar por período solicitado
                filtered_data = filter(row -> start_date <= row.date <= end_date, raw_data)
                
                if nrow(filtered_data) > 0
                    # Converter para formato esperado
                    data = DataFrame(
                        date = filtered_data.date,
                        price = filtered_data.close
                    )
                    
                    # Adicionar metadados
                    data.ticker_symbol = fill(ticker, nrow(data))
                    data.data_start = fill(minimum(data.date), nrow(data))
                    data.data_end = fill(maximum(data.date), nrow(data))
                    
                    bulk_data_dict[ticker] = data
                end
            end
        end
        
        if !isempty(bulk_data_dict)
            if verbose
                println("✅ Bulk download concluído:")
                println("   📊 Obtidos: $(length(bulk_data_dict)) de $(length(limited_tickers)) tickers solicitados")
                println("   📁 Taxa de sucesso: $(round(length(bulk_data_dict)/length(limited_tickers)*100, digits=1))%")
            end
            return bulk_data_dict
        else
            # Sem fallback: reportar status do arquivo bulk e falhar
            status = StooqData.get_bulk_download_status()
            msg = String(
                "Bulk não retornou dados. Status do arquivo:" *
                "\n   ZIP: $(status.zip_file) | existe=$(status.zip_exists) | tamanho=$(status.zip_size_mb) MB" *
                "\n   IDX: $(status.index_file) | existe=$(status.index_exists) | tamanho=$(status.index_size_mb) MB"
            )
            error(msg)
        end
    end

    # Downloads individuais (apenas se use_bulk=false)
    data_dict = Dict{String, DataFrame}()
    failed_tickers = String[]
    cached_count = 0
    downloaded_count = 0
    
    # Processar com rate limiting adequado
    for (i, ticker) in enumerate(limited_tickers)
        try
            # Verificar cache primeiro
            data = nothing
            if !force && cache_exists(ticker)
                cached_data = load_price_cache(ticker)
                if cached_data !== nothing
                    cache_start = minimum(cached_data.date)
                    cache_end = maximum(cached_data.date)
                    
                    if cache_start <= start_date && cache_end >= end_date
                        data = filter(row -> start_date <= row.date <= end_date, cached_data)
                        cached_count += 1
                        
                        if verbose && i % 50 == 0
                            println("   📁 Cache: $ticker ($(i)/$(length(limited_tickers)))")
                        end
                    end
                end
            end
            
            # Se não tem no cache, baixar do Stooq
            if data === nothing
                raw_data = StooqData.download_stooq_ticker(ticker, start_date=start_date, end_date=end_date, verbose=false)
                
                if nrow(raw_data) > 0
                    # Converter para formato compatível
                    data = DataFrame(
                        date = raw_data.date,
                        price = raw_data.close
                    )
                    
                    # Salvar no cache
                    save_price_cache(ticker, data)
                    downloaded_count += 1
                    
                    if verbose && i % 10 == 0
                        println("   🌐 Baixado: $ticker ($(i)/$(length(limited_tickers)))")
                    end
                else
                    push!(failed_tickers, ticker)
                    continue
                end
            end
            
            # Adicionar metadados e armazenar
            if data !== nothing && nrow(data) > 0
                data.ticker_symbol = fill(ticker, nrow(data))
                data.data_start = fill(minimum(data.date), nrow(data))
                data.data_end = fill(maximum(data.date), nrow(data))
                data_dict[ticker] = data
            else
                push!(failed_tickers, ticker)
            end
            
            # Rate limiting para evitar sobrecarga no Stooq
            if i % 20 == 0 && i < length(limited_tickers)
                sleep(1.0)  # Pausa de 1s a cada 20 tickers
            end
            
        catch e
            if verbose
                println("   ❌ Erro com $ticker: $e")
            end
            push!(failed_tickers, ticker)
        end
    end
    
    if verbose
        println("✅ Download individual concluído:")
        println("   📊 Obtidos com sucesso: $(length(data_dict)) tickers")
        println("   📁 Do cache: $cached_count tickers")
        println("   🌐 Baixados: $downloaded_count tickers")
        if !isempty(failed_tickers)
            println("   ❌ Falharam: $(length(failed_tickers)) tickers")
            if length(failed_tickers) <= 10
                println("   Failed: $(join(failed_tickers, ", "))")
            end
        end
    end
    
    return data_dict
end

"""
Calcula retornos mensais a partir de dados de preços diários.
"""
function calculate_returns(price_data::Dict{String, DataFrame}, 
                          start_date::Date, end_date::Date; verbose::Bool = true)::DataFrame
    
    if verbose
        println("📊 Calculando retornos mensais...")
    end
    
    # Criar datas mensais
    monthly_dates = collect(Date(year(start_date), month(start_date), 1):Month(1):Date(year(end_date), month(end_date), 1))
    
    # DataFrame final com retornos mensais
    returns_df = DataFrame(date = monthly_dates)
    
    valid_tickers = String[]
    
    for (ticker, data) in price_data
        try
            # Garantir que os dados estão ordenados por data
            sort!(data, :date)
            
            monthly_returns = Union{Float64, Missing}[]
            
            for i in 1:(length(monthly_dates)-1)
                current_month = monthly_dates[i]
                next_month = monthly_dates[i+1]
                
                # Preço no final do mês atual e anterior
                current_data = filter(row -> current_month <= row.date < next_month, data)
                
                if nrow(current_data) >= 5  # Pelo menos 5 dias de trading no mês
                    price_end = last(current_data.price)
                    
                    if i == 1
                        # Primeiro mês: usar primeiro preço disponível
                        price_start = first(current_data.price)
                    else
                        # Usar último preço do mês anterior
                        prev_month = monthly_dates[i-1]
                        prev_data = filter(row -> prev_month <= row.date < current_month, data)
                        if nrow(prev_data) > 0
                            price_start = last(prev_data.price)
                        else
                            price_start = first(current_data.price)
                        end
                    end
                    
                    # Calcular retorno mensal em %
                    monthly_return = (price_end / price_start - 1) * 100
                    push!(monthly_returns, monthly_return)
                else
                    push!(monthly_returns, missing)
                end
            end
            
            # Adicionar última observação como missing (não temos mês seguinte)
            push!(monthly_returns, missing)
            
            if length(monthly_returns) == length(monthly_dates)
                returns_df[!, ticker] = monthly_returns
                push!(valid_tickers, ticker)
            end
            
        catch e
            if verbose
                println("   ⚠️ Erro calculando retornos para $ticker: $e")
            end
        end
    end
    
    if verbose
        println("✅ Retornos calculados para $(length(valid_tickers)) ações")
        println("   Período: $(length(monthly_dates)) meses")
    end
    
    return returns_df
end


"""
Calcula retornos diários a partir de dados de preços.
"""
function calculate_daily_returns(price_data::Dict{String, DataFrame}; verbose::Bool = true)::DataFrame
    
    if verbose
        println("📊 Calculando retornos diários...")
    end
    
    # Obter todas as datas únicas e ordenar
    all_dates = Date[]
    for (ticker, data) in price_data
        append!(all_dates, data.date)
    end
    unique_dates = sort(unique(all_dates))
    
    # DataFrame final com retornos diários
    returns_df = DataFrame(date = unique_dates)
    
    valid_tickers = String[]
    
    for (ticker, data) in price_data
        try
            # Garantir que os dados estão ordenados por data
            sort!(data, :date)
            
            daily_returns = Union{Float64, Missing}[]
            
            for date in unique_dates
                # Encontrar preço para esta data
                price_row = filter(row -> row.date == date, data)
                if !isempty(price_row)
                    current_price = price_row.price[1]
                    
                    # Encontrar preço do dia anterior
                    prev_date_idx = findfirst(d -> d < date, reverse(unique_dates))
                    if prev_date_idx !== nothing
                        prev_date = reverse(unique_dates)[prev_date_idx]
                        prev_price_row = filter(row -> row.date == prev_date, data)
                        
                        if !isempty(prev_price_row)
                            prev_price = prev_price_row.price[1]
                            daily_return = (current_price / prev_price - 1) * 100
                            push!(daily_returns, daily_return)
                        else
                            push!(daily_returns, missing)
                        end
                    else
                        push!(daily_returns, missing)  # Primeiro dia
                    end
                else
                    push!(daily_returns, missing)  # Sem dados para esta data
                end
            end
            
            if length(daily_returns) == length(unique_dates)
                returns_df[!, ticker] = daily_returns
                push!(valid_tickers, ticker)
            end
            
        catch e
            if verbose
                println("   ⚠️ Erro calculando retornos diários para $ticker: $e")
            end
        end
    end
    
    if verbose
        println("✅ Retornos diários calculados para $(length(valid_tickers)) ações")
        println("   Período: $(length(unique_dates)) dias")
    end
    
    return returns_df
end

"""
Calcula volatilidade de 252 dias a partir de retornos diários.
"""
function calculate_252d_volatility(daily_returns_df::DataFrame, date::Date; 
                                 window_days::Int = 252, min_obs::Int = 180)::Dict{String, Float64}
    
    ticker_columns = names(daily_returns_df)[2:end]  # Excluir coluna 'date'
    volatilities = Dict{String, Float64}()
    
    # Encontrar índice da data
    date_idx = findfirst(daily_returns_df.date .== date)
    if date_idx === nothing || date_idx <= window_days
        return volatilities  # Não há dados suficientes
    end
    
    # Definir janela de dados
    start_idx = max(1, date_idx - window_days)
    end_idx = date_idx - 1  # Não incluir a data atual (signal lag)
    
    for ticker in ticker_columns
        # Obter retornos históricos
        historical_returns = daily_returns_df[start_idx:end_idx, ticker]
        clean_returns = filter(!ismissing, historical_returns)
        
        if length(clean_returns) >= min_obs  # Pelo menos 180 dias de dados (aprox. 9 meses)
            # Calcular volatilidade anualizada (252 dias de trading por ano)
            daily_vol = std(clean_returns)
            annualized_vol = daily_vol * sqrt(252)
            volatilities[ticker] = annualized_vol
        end
    end
    
    return volatilities
end



"""
    load_historical_sp500_constituents(file_path::String = "data/sp_500_historical_components.csv")::DataFrame

Carrega o arquivo histórico de constituintes do S&P 500 com dados point-in-time.

# Argumentos
- `file_path`: Caminho para o arquivo CSV (default: "data/sp_500_historical_components.csv")

# Retorna
- DataFrame com colunas Date (Date) e Tickers (Vector{String})

# Exemplo
```julia
constituents = load_historical_sp500_constituents()
println("Período: \$(minimum(constituents.Date)) a \$(maximum(constituents.Date))")
println("Total observações: \$(nrow(constituents))")
```
"""
function load_historical_sp500_constituents(file_path::String = "data/sp_500_historical_components.csv")::DataFrame
    abs_path = isabspath(file_path) ? file_path : normpath(joinpath(@__DIR__, "..", file_path))
    if !isfile(abs_path)
        error("Arquivo de constituintes históricos não encontrado: $abs_path")
    end
    
    println("📋 Carregando constituintes históricos do S&P 500...")
    println("   Arquivo: $abs_path")
    
    # Ler arquivo CSV
    try
        raw_df = CSV.read(abs_path, DataFrame)
        
        if !("date" in names(raw_df)) || !("tickers" in names(raw_df))
            error("Arquivo deve conter colunas 'date' e 'tickers'")
        end
        
        println("   ✅ Arquivo lido: $(nrow(raw_df)) observações")
        
        # Converter e processar dados
        processed_df = DataFrame(
            Date = Date[],
            Tickers = Vector{String}[]
        )
        
        for row in eachrow(raw_df)
            # Converter string de data para Date
            date_obj = Date(row.date)
            
            # Converter string de tickers para vetor
            tickers_str = replace(row.tickers, "\"" => "")  # Remove aspas se existirem
            tickers_vec = split(tickers_str, ",")
            tickers_vec = String.(strip.(tickers_vec))  # Remove espaços e converte para String
            
            # Filtrar tickers vazios
            tickers_vec = filter(x -> !isempty(x), tickers_vec)
            
            push!(processed_df, (date_obj, tickers_vec))
        end
        
        # Ordenar por data
        sort!(processed_df, :Date)
        
        println("   ✅ Dados processados:")
        println("      Período: $(minimum(processed_df.Date)) a $(maximum(processed_df.Date))")
        println("      Observações: $(nrow(processed_df))")
        println("      Tickers médios por data: $(round(mean(length.(processed_df.Tickers)), digits=1))")
        
        return processed_df
        
    catch e
        error("Erro ao processar arquivo de constituintes: $e")
    end
end

"""
    get_universe_for_period(start_date::Date, end_date::Date; 
                           constituents_df::Union{DataFrame, Nothing} = nothing,
                           verbose::Bool = true)::Vector{String}

Extrai universo único de tickers que foram membros do S&P 500 durante um período específico.
Elimina viés de sobrevivência incluindo empresas que foram removidas/extintas.

# Argumentos
- `start_date`: Data inicial do período
- `end_date`: Data final do período  
- `constituents_df`: DataFrame de constituintes históricos (carregado automaticamente se não fornecido)
- `verbose`: Se deve imprimir informações de progresso

# Retorna
- Vetor único de tickers que foram membros do S&P 500 no período

# Exemplo
```julia
# Obter universo para análise Novy-Marx de 25 anos
universe = get_universe_for_period(Date(2000,1,1), Date(2024,12,31))
println("Universo: \$(length(universe)) ações únicas")
```
"""
function get_universe_for_period(start_date::Date, end_date::Date; 
                                constituents_df::Union{DataFrame, Nothing} = nothing,
                                verbose::Bool = true)::Vector{String}
    
    if verbose
        println("🎯 Extraindo universo S&P 500 para período point-in-time...")
        println("   Período: $start_date a $end_date")
    end
    
    # Carregar constituintes se não fornecido
    if constituents_df === nothing
        constituents_df = load_historical_sp500_constituents()
    end
    
    # Filtrar por período
    period_data = filter(row -> start_date <= row.Date <= end_date, constituents_df)
    
    if nrow(period_data) == 0
        error("Nenhum dado encontrado para o período $start_date a $end_date")
    end
    
    if verbose
        println("   📊 Observações no período: $(nrow(period_data))")
    end
    
    # Coletar todos os tickers únicos
    all_tickers = Set{String}()
    
    for row in eachrow(period_data)
        for ticker in row.Tickers
            push!(all_tickers, ticker)
        end
    end
    
    # Converter para vetor ordenado
    universe = sort(collect(all_tickers))
    
    # Estatísticas
    if verbose
        println("   ✅ Universo extraído:")
        println("      Total único: $(length(universe)) tickers")
        println("      Primeiros 10: $(join(universe[1:min(10, length(universe))], ", "))")
        if length(universe) > 10
            println("      Últimos 5: $(join(universe[end-4:end], ", "))")
        end
        
        # Identificar algumas empresas extintas/problemáticas para validar
        extinct_found = filter(t -> occursin("Q", t) && endswith(t, "Q"), universe)
        if !isempty(extinct_found) && length(extinct_found) <= 10
            println("      🏴‍☠️ Extintas encontradas: $(join(extinct_found, ", "))")
        elseif length(extinct_found) > 10
            println("      🏴‍☠️ Extintas encontradas: $(length(extinct_found)) empresas")
        end
    end
    
    return universe
end

"""
    clean_ticker_for_stooq(ticker::String)::String

Limpa e mapeia símbolos de tickers para formato compatível com Stooq.com.
Aplica mapeamentos conhecidos para símbolos problemáticos.

# Argumentos  
- `ticker`: Símbolo original

# Retorna
- Símbolo limpo/mapeado para Stooq.com

# Exemplos
```julia
clean_ticker_for_stooq("BRK.B")   # → "BRK.B" 
clean_ticker_for_stooq("BF-B")    # → "BF.B" 
clean_ticker_for_stooq("AAMRQ")   # → "AAMRQ" (extinta, manteremos para tentativa)
```
"""
function clean_ticker_for_stooq(ticker::String)::String
    # Delegar para o módulo Stooq que tem a lógica de limpeza adequada
    return StooqData.clean_stooq_ticker(ticker)
end

"""
Cria quintis P1-P5 point-in-time seguindo metodologia Novy-Marx rigorosa.
Implementa universo point-in-time, defasagem do sinal, e handling correto de missing values.

# Argumentos
- `returns_df`: DataFrame com retornos mensais (colunas: date, ticker1, ticker2, ...)
- `method`: Método de volatilidade (:monthly12 ou :daily252) 
- `price_data`: Dados de preços diários (necessário para :daily252)
- `lookback`: Janela de lookback para volatilidade (12 meses ou 252 dias)
- `min_coverage`: Cobertura mínima de dados (0.7 = 70%)
- `min_per_quintile`: Mínimo de ações por quintil
- `constituents_df`: DataFrame com constituintes históricos S&P 500
- `verbose`: Debug output

# Retorna
DataFrame com colunas: Date, P1, P2, P3, P4, P5, LowMinusHigh
"""
function create_volatility_quintile_portfolios_pti(
    returns_df::DataFrame; 
    method::Symbol = :monthly12,
    price_data::Union{Dict{String, DataFrame}, Nothing} = nothing,
    lookback::Int = 12,
    min_coverage::Float64 = 0.7,
    min_per_quintile::Int = 5,
    constituents_df::Union{DataFrame, Nothing} = nothing,
    verbose::Bool = true
)::DataFrame
    
    if verbose
        println("🔬 Criando quintis P1-P5 point-in-time (metodologia Novy-Marx)")
        println("   Método: $(method == :monthly12 ? "$lookback meses mensais" : "$lookback dias diários")")
        println("   Min coverage: $(round(min_coverage*100, digits=1))%")
        println("   Min por quintil: $min_per_quintile ações")
        println("   Universo point-in-time: $(constituents_df !== nothing)")
    end
    
    # Carregar constituintes históricos se não fornecido
    if constituents_df === nothing
        constituents_df = load_historical_sp500_constituents()
    end
    
    # Verificar dados diários se necessário
    daily_returns_df = nothing
    if method == :daily252
        if price_data === nothing
            error("Método :daily252 requer price_data para calcular retornos diários")
        end
        daily_returns_df = calculate_daily_returns(price_data, verbose=false)
    end
    
    dates = returns_df.date
    
    # Arrays de saída
    P1_returns = Union{Float64, Missing}[]  
    P2_returns = Union{Float64, Missing}[]
    P3_returns = Union{Float64, Missing}[]
    P4_returns = Union{Float64, Missing}[]
    P5_returns = Union{Float64, Missing}[]
    LowMinusHigh_returns = Union{Float64, Missing}[]
    valid_dates = Date[]
    
    processed_months = 0
    skipped_months = 0
    
    # Loop pelos meses de formação de carteiras
    # IMPORTANTE: Começa em lookback+2 para implementar defasagem do sinal
    for i in (lookback + 2):nrow(returns_df)
        formation_date = dates[i-1]  # Mês de formação (t-1)
        holding_date = dates[i]      # Mês de holding (t)
        
        # 1. UNIVERSO POINT-IN-TIME: filtrar tickers elegíveis na data de formação
        # USAR NOVA FUNÇÃO que valida disponibilidade de dados
        eligible_tickers = get_valid_tickers_for_month(
            formation_date, 
            price_data,  # Usar price_data para validação
            constituents_df,
            min_lookback_months=lookback,
            verbose=false
        )
        
        if length(eligible_tickers) < min_per_quintile * 5
            if verbose && skipped_months < 3
                println("   ⚠️ $(Dates.format(holding_date, "yyyy-mm")): poucos tickers elegíveis ($(length(eligible_tickers)))")
            end
            skipped_months += 1
            continue
        end
        
        # 2. CÁLCULO DE VOLATILIDADE HISTÓRICA até t-1 (defasagem do sinal)
        volatilities = Dict{String, Float64}()
        
        if method == :monthly12
            # Volatilidade baseada em retornos mensais (janela: i-lookback-1 até i-1)
            for ticker in eligible_tickers
                hist_start_idx = max(1, i - lookback - 1)
                hist_end_idx = i - 1
                
                historical_returns = returns_df[hist_start_idx:hist_end_idx, ticker]
                clean_returns = filter(!ismissing, historical_returns)
                
                min_obs_required = Int(ceil(lookback * min_coverage))
                if length(clean_returns) >= min_obs_required
                    volatilities[ticker] = std(clean_returns)
                end
            end
        elseif method == :daily252
            # Volatilidade baseada em retornos diários (252 dias até formation_date)
            volatilities = calculate_252d_volatility(daily_returns_df, formation_date, 
                                                   window_days=lookback, min_obs=Int(ceil(lookback * min_coverage)))
            # Filtrar apenas tickers elegíveis
            volatilities = Dict(k => v for (k, v) in volatilities if k in eligible_tickers)
        end
        
        # 3. FORMAÇÃO DOS QUINTIS por volatilidade crescente
        if length(volatilities) >= min_per_quintile * 5
            sorted_vols = sort(collect(volatilities), by = x -> x[2])  # ordenar por volatilidade
            n_stocks = length(sorted_vols)
            quintile_size = div(n_stocks, 5)
            
            if quintile_size >= min_per_quintile
                # Dividir em 5 quintis de tamanhos iguais
                quintile_indices = [
                    1:quintile_size,                                    # P1 (menor vol)
                    (quintile_size+1):(2*quintile_size),              # P2
                    (2*quintile_size+1):(3*quintile_size),            # P3  
                    (3*quintile_size+1):(4*quintile_size),            # P4
                    (4*quintile_size+1):(5*quintile_size)             # P5 (maior vol)
                ]
                
                quintile_tickers = [
                    [ticker for (ticker, vol) in sorted_vols[idx]]
                    for idx in quintile_indices
                ]
                
                # 4. CÁLCULO DOS RETORNOS EQUAL-WEIGHTED no mês de holding (t)
                quintile_returns = Float64[]
                
                for q_tickers in quintile_tickers
                    valid_returns = Float64[]
                    
                    for ticker in q_tickers
                        ret = returns_df[i, ticker]  # Retorno em holding_date
                        if !ismissing(ret)
                            push!(valid_returns, ret)
                        else
                            # FORCED SALE: Se ticker não tem retorno no mês atual,
                            # verificar se tinha dados anteriormente (empresa que parou)
                            prev_ret = nothing
                            for prev_i in (i-1):-1:max(1, i-12)  # Buscar até 12 meses atrás
                                if !ismissing(returns_df[prev_i, ticker])
                                    prev_ret = 0.0  # Forced sale = retorno 0% (preço constante)
                                    break
                                end
                            end
                            if prev_ret !== nothing
                                push!(valid_returns, prev_ret)
                                # Log apenas ocasionalmente para não sobrecarregar
                                if rand() < 0.01  # 1% das vezes
                                    if verbose
                                        println("   📌 Forced sale: $ticker → 0.0% em $(Dates.format(holding_date, "yyyy-mm"))")
                                    end
                                end
                            end
                        end
                    end
                    
                    # Exigir cobertura mínima no mês de holding
                    required_coverage = Int(ceil(length(q_tickers) * min_coverage))
                    if length(valid_returns) >= required_coverage
                        avg_return = mean(valid_returns)
                        push!(quintile_returns, avg_return)
                    else
                        # Cobertura insuficiente - marcar mês como missing
                        break
                    end
                end
                
                # 5. ARMAZENAR RESULTADOS (apenas se todos os quintis são válidos)
                if length(quintile_returns) == 5
                    push!(P1_returns, quintile_returns[1])
                    push!(P2_returns, quintile_returns[2])
                    push!(P3_returns, quintile_returns[3])
                    push!(P4_returns, quintile_returns[4])
                    push!(P5_returns, quintile_returns[5])
                    
                    # Long-Short: P1 - P5 (Low Vol - High Vol)
                    lmh_return = quintile_returns[1] - quintile_returns[5]
                    push!(LowMinusHigh_returns, lmh_return)
                    push!(valid_dates, holding_date)
                    
                    processed_months += 1
                else
                    # Cobertura insuficiente - pular este mês
                    skipped_months += 1
                end
            else
                skipped_months += 1
            end
        else
            skipped_months += 1
        end
        
        # Progress feedback
        if verbose && (processed_months + skipped_months) % 50 == 0
            println("   📊 Processados: $processed_months meses, pulados: $skipped_months")
        end
    end
    
    # Criar DataFrame final
    result_df = DataFrame(
        Date = valid_dates,
        P1 = P1_returns,
        P2 = P2_returns, 
        P3 = P3_returns,
        P4 = P4_returns,
        P5 = P5_returns,
        LowMinusHigh = LowMinusHigh_returns
    )
    
    if verbose
        println("✅ Quintis point-in-time criados: $(nrow(result_df)) meses válidos")
        println("   📈 Período efetivo: $(minimum(valid_dates)) a $(maximum(valid_dates))")
        println("   📊 Taxa de sucesso: $(round(processed_months/(processed_months + skipped_months)*100, digits=1))%")
        
        if nrow(result_df) > 0
            println("   📊 ESTATÍSTICAS DOS QUINTIS (médias anualizadas):")
            for col in [:P1, :P2, :P3, :P4, :P5, :LowMinusHigh]
                valid_data = filter(!ismissing, result_df[!, col])
                if length(valid_data) > 0
                    ret_mean = mean(valid_data) * 12  # Anualizar
                    ret_vol = std(valid_data) * sqrt(12)
                    sharpe = ret_mean / ret_vol
                    println("   $(string(col)): $(round(ret_mean, digits=1))% a.a., Vol=$(round(ret_vol, digits=1))%, SR=$(round(sharpe, digits=3))")
                end
            end
        end
    end
    
    return result_df
end

"""
Função auxiliar para obter tickers elegíveis em uma data específica.
"""
function get_eligible_tickers_for_date(constituents_df::DataFrame, date::Date, available_tickers::Vector{String})::Vector{String}
    # Encontrar a observação mais próxima (anterior ou igual) à data
    valid_obs = filter(row -> row.Date <= date, constituents_df)
    
    if nrow(valid_obs) == 0
        return String[]
    end
    
    # Usar a observação mais recente
    latest_obs = sort(valid_obs, :Date, rev=true)[1, :]
    sp500_tickers = latest_obs.Tickers
    
    # Interseção: tickers que estão no S&P 500 E têm dados disponíveis
    eligible = String[]
    for ticker in sp500_tickers
        # Normalizar ticker para formato Stooq
        clean_ticker = clean_ticker_for_stooq(ticker)
        if clean_ticker in available_tickers
            push!(eligible, clean_ticker)
        # Também tentar o ticker original sem sufixo
        elseif ticker in available_tickers
            push!(eligible, ticker)
        end
    end
    
    return eligible
end

"""
Retorna período de validade de um ticker baseado nos dados baixados.
"""
function get_ticker_validity_period(price_data::Dict{String, DataFrame}, ticker::String)::Union{Tuple{Date, Date}, Nothing}
    if !haskey(price_data, ticker)
        return nothing
    end
    
    data = price_data[ticker]
    if nrow(data) == 0
        return nothing
    end
    
    return (minimum(data.date), maximum(data.date))
end

"""
Retorna lista de tickers válidos para um mês específico.
Considera tanto a disponibilidade de dados quanto a inclusão no S&P 500.
"""
function get_valid_tickers_for_month(
    target_date::Date,
    price_data::Dict{String, DataFrame},
    constituents_df::Union{DataFrame, Nothing} = nothing;
    min_lookback_months::Int = 6,
    verbose::Bool = false
)::Vector{String}
    
    valid_tickers = String[]
    lookback_date = target_date - Month(min_lookback_months)
    
    if verbose
        println("🔍 Buscando tickers válidos para $(Dates.format(target_date, "yyyy-mm")):")
        println("   Lookback mínimo: $(Dates.format(lookback_date, "yyyy-mm")) ($(min_lookback_months) meses)")
    end
    
    # Verificar cada ticker nos dados baixados
    for (ticker, data) in price_data
        if nrow(data) == 0
            continue
        end
        
        data_start = minimum(data.date)
        data_end = maximum(data.date)
        
        # Ticker é válido se:
        # 1. Tem pelo menos min_lookback_months de dados antes da data alvo
        # 2. Para forced sale: aceita tickers que param antes do fim (usará último preço)
        
        target_month = Date(year(target_date), month(target_date), 1)
        
        # Modificação: inclui tickers com dados suficientes para lookback, mesmo que parem antes do fim
        if data_start <= lookback_date && data_end >= lookback_date
            # Verificar se estava no S&P 500 naquele período (se constituents_df fornecido)
            if constituents_df !== nothing
                eligible = get_eligible_tickers_for_date(constituents_df, target_date, [ticker])
                if ticker in eligible
                    push!(valid_tickers, ticker)
                elseif verbose
                    println("   ❌ $ticker: não estava no S&P 500 em $(Dates.format(target_date, "yyyy-mm"))")
                end
            else
                push!(valid_tickers, ticker)
            end
            
            if verbose && length(valid_tickers) % 50 == 0
                println("   📊 Válidos até agora: $(length(valid_tickers))")
            end
        elseif verbose && rand() < 0.1  # Amostra de 10% para não sobrecarregar logs
            if data_end < target_month
                println("   ⏰ $ticker: dados terminam em $(Dates.format(data_end, "yyyy-mm")) (antes do alvo)")
            elseif data_start > lookback_date
                println("   ⏰ $ticker: dados começam em $(Dates.format(data_start, "yyyy-mm")) (insuficiente lookback)")
            end
        end
    end
    
    if verbose
        println("   ✅ Total válidos: $(length(valid_tickers)) tickers")
    end
    
    return sort(valid_tickers)
end

"""
Cria metadados detalhados sobre períodos de validade dos tickers.
"""
function create_validity_metadata(price_data::Dict{String, DataFrame})::DataFrame
    
    metadata_rows = []
    
    for (ticker, data) in price_data
        if nrow(data) == 0
            continue
        end
        
        data_start = minimum(data.date)
        data_end = maximum(data.date)
        total_obs = nrow(data)
        
        # Calcular estatísticas básicas
        duration_days = (data_end - data_start).value
        duration_years = duration_days / 365.25
        
        # Detectar gaps grandes nos dados
        dates_sorted = sort(data.date)
        gaps = diff(dates_sorted)
        max_gap = maximum(gaps).value
        avg_gap = mean([g.value for g in gaps])
        
        push!(metadata_rows, [
            ticker,
            data_start,
            data_end,
            total_obs,
            duration_days,
            round(duration_years, digits=2),
            max_gap,
            round(avg_gap, digits=1)
        ])
    end
    
    return DataFrame(
        ticker = [row[1] for row in metadata_rows],
        data_start = [row[2] for row in metadata_rows],
        data_end = [row[3] for row in metadata_rows],
        total_observations = [row[4] for row in metadata_rows],
        duration_days = [row[5] for row in metadata_rows],
        duration_years = [row[6] for row in metadata_rows],
        max_gap_days = [row[7] for row in metadata_rows],
        avg_gap_days = [row[8] for row in metadata_rows]
    )
end

end
