# Real Market Data Module
# Downloads actual stock price data using YFinance.jl
# Creates portfolios based on real historical volatility

module MarketData

using YFinance, CSV, DataFrames, Dates, Statistics, StatsBase

# Importar sistema de resolução de tickers
include("ticker_resolver.jl")
using .TickerResolver

export load_sp500_constituents, download_stock_data, calculate_returns, 
       create_volatility_portfolios, create_volatility_quintile_portfolios, 
       create_volatility_quintile_portfolios_pti, get_real_portfolio_returns,
       save_price_cache, load_price_cache, cache_exists, calculate_daily_returns, 
       calculate_252d_volatility, load_historical_sp500_constituents, get_universe_for_period,
       get_eligible_tickers_for_date, clean_ticker_for_yahoo, get_quintile_portfolios_pti,
       get_valid_tickers_for_month, get_ticker_validity_period, create_validity_metadata

"""
Carrega os constituintes históricos do S&P 500 do arquivo CSV.
Retorna DataFrame com colunas: date, tickers
"""
function load_sp500_constituents(file_path::String = "data/sp_500_historical_components.csv")::DataFrame
    println("📊 Carregando constituintes históricos do S&P 500...")
    
    df = CSV.read(file_path, DataFrame)
    
    # Converter string de tickers para array
    df.tickers_array = [split(tickers, ",") for tickers in df.tickers]
    
    println("✅ Carregados $(nrow(df)) dias de dados históricos ($(minimum(df.date)) a $(maximum(df.date)))")
    return df
end

"""
Verifica se existe cache para um ticker específico.
"""
function cache_exists(ticker::String, cache_dir::String = "data/cache/prices")::Bool
    cache_file = joinpath(cache_dir, "$(ticker).csv")
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
    clean_uni = [clean_ticker_for_yahoo(t) for t in uni]
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
    cache_file = joinpath(cache_dir, "$(ticker).csv")
    CSV.write(cache_file, data)
    return nothing
end

"""
Carrega dados de preços do cache.
"""
function load_price_cache(ticker::String, cache_dir::String = "data/cache/prices")::Union{DataFrame, Nothing}
    cache_file = joinpath(cache_dir, "$(ticker).csv")
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
Baixa dados de preços históricos para uma lista de tickers usando YFinance.jl.
Agora com sistema de cache para evitar redownloads.
"""
function download_stock_data(tickers::Vector{String}, start_date::Date, end_date::Date; 
                           max_tickers::Int = 1500, force::Bool = false, verbose::Bool = true, 
                           batch_size::Int = 50, delay_between_batches::Float64 = 2.0)::Dict{String, DataFrame}
    
    if verbose
        println("📈 Baixando dados de preços para $(length(tickers)) tickers...")
        println("   Período: $start_date a $end_date")
        println("   Cache: $(force ? "FORÇAR download" : "usar cache se disponível")")
    end
    
    # Limitar número de tickers se necessário
    limited_tickers = tickers[1:min(length(tickers), max_tickers)]
    
    if verbose && length(tickers) > max_tickers
        println("   ⚠️ Limitando a $max_tickers tickers (de $(length(tickers)) disponíveis)")
    end
    
    # Estatísticas de processamento
    data_dict = Dict{String, DataFrame}()
    failed_tickers = String[]
    cached_count = 0
    downloaded_count = 0
    total_tickers = length(limited_tickers)
    
    # Processar em lotes para evitar rate limiting
    num_batches = ceil(Int, total_tickers / batch_size)
    
    if verbose && total_tickers > batch_size
        println("   🔄 Processamento em $num_batches lotes de $batch_size tickers cada")
    end
    
    for batch_num in 1:num_batches
        start_idx = (batch_num - 1) * batch_size + 1
        end_idx = min(batch_num * batch_size, total_tickers)
        batch_tickers = limited_tickers[start_idx:end_idx]
        
        if verbose
            println("   📦 Lote $batch_num/$num_batches: processando $(length(batch_tickers)) tickers")
        end
        
        for (i_in_batch, ticker) in enumerate(batch_tickers)
            global_index = start_idx + i_in_batch - 1
            
            # RESOLVER TICKER usando sistema inteligente
            resolved_ticker, metadata = TickerResolver.resolve_ticker(ticker)
            
            # METODOLOGIA POINT-IN-TIME: Tentar baixar mesmo se extinto (dados parciais são válidos)
            # Só pular se não tiver símbolo para tentar (resolved_ticker vazio)
            if isempty(resolved_ticker)
                push!(failed_tickers, ticker)
                if verbose
                    println("   ❌ Erro baixando $ticker: $(metadata["reason"])")
                end
                continue
            end
            
            # Usar ticker resolvido (pode ser o mesmo ou mapeado)
            actual_ticker = isempty(resolved_ticker) ? ticker : resolved_ticker
            
            if verbose && metadata["status"] != "original"
                println("   🔄 $ticker → $actual_ticker ($(metadata["reason"]))")
            end
            
            try
            
            # Verificar cache primeiro (a menos que force=true)
            # Usar ticker original para cache (mantém compatibilidade)
            data = nothing
            if !force && cache_exists(ticker)
                cached_data = load_price_cache(ticker)
                if cached_data !== nothing
                    # Verificar se o cache cobre o período solicitado
                    cache_start = minimum(cached_data.date)
                    cache_end = maximum(cached_data.date)
                    
                    if cache_start <= start_date && cache_end >= end_date
                        # Filtrar dados do cache para o período solicitado
                        data = filter(row -> start_date <= row.date <= end_date, cached_data)
                        cached_count += 1
                        
                        if verbose && i % 20 == 0
                            println("   📁 Usando cache para $ticker")
                        end
                    end
                end
            end
            
            # Se não encontrou no cache ou force=true, baixar dados
            if data === nothing
                # FALLBACK HIERARCHY: Tentar múltiplas estratégias
                download_success = false
                attempts = [actual_ticker]
                
                # Se ticker foi mapeado, também tentar o original como fallback
                if metadata["status"] == "mapped" && actual_ticker != ticker
                    push!(attempts, ticker)
                end
                
                for attempt_ticker in attempts
                    try
                        # Download data from YFinance usando ticker resolvido
                        raw_data = get_prices(attempt_ticker, startdt=string(start_date), enddt=string(end_date))
                        
                        # Convert OrderedDict to DataFrame
                        data = DataFrame(
                            date = raw_data["timestamp"],
                            price = raw_data["adjclose"]
                        )
                        
                        # Salvar no cache para uso futuro
                        save_price_cache(ticker, data)
                        downloaded_count += 1
                        download_success = true
                        
                        if verbose && global_index % 20 == 0
                            success_ticker = attempt_ticker == ticker ? ticker : "$ticker→$attempt_ticker"
                            println("   🌐 Baixado $success_ticker")
                        end
                        break  # Sair do loop se sucesso
                        
                    catch download_error
                        if verbose && length(attempts) > 1
                            println("   ⚠️ Falha com $attempt_ticker: $download_error")
                        end
                        continue  # Tentar próximo ticker
                    end
                end
                
                # Se todos os attempts falharam
                if !download_success
                    if verbose
                        println("   ❌ Falha após $(length(attempts)) tentativas: $ticker")
                    end
                    push!(failed_tickers, ticker)
                    continue
                end
            end
            
            # NOVA LÓGICA: Aceitar QUALQUER dado válido (point-in-time real)
            if nrow(data) > 0  # Qualquer dado é válido
                # Adicionar metadados de período válido
                data.ticker_symbol = fill(ticker, nrow(data))
                data.data_start = fill(minimum(data.date), nrow(data))  
                data.data_end = fill(maximum(data.date), nrow(data))
                data_dict[ticker] = data
                
                if verbose && nrow(data) < 250  # Menos de 1 ano, informar
                    period_days = (maximum(data.date) - minimum(data.date)).value
                    println("   ⚠️ $ticker: apenas $(nrow(data)) observações (~$(round(period_days/365, digits=1)) anos)")
                end
            else
                push!(failed_tickers, ticker)
                if verbose
                    println("   ❌ $ticker: sem dados válidos")
                end
            end
            
        catch e
            if verbose
                println("   ❌ Erro baixando $ticker: $e")
            end
            push!(failed_tickers, ticker)
        end
        
            # Pausa pequena para evitar rate limiting entre tickers
            sleep(0.1)
        end  # End ticker loop
        
        # Delay entre lotes para evitar rate limiting
        if batch_num < num_batches && delay_between_batches > 0
            if verbose
                println("   ⏰ Pausa de $(delay_between_batches)s entre lotes...")
            end
            sleep(delay_between_batches)
        end
    end  # End batch loop
    
    if verbose
        println("✅ Obtidos com sucesso: $(length(data_dict)) tickers")
        println("   📁 Do cache: $cached_count tickers")
        println("   🌐 Baixados: $downloaded_count tickers")
        if !isempty(failed_tickers)
            println("❌ Falharam: $(length(failed_tickers)) tickers")
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
Cria portfólios baseados em volatilidade histórica real.
"""
function create_volatility_portfolios(returns_df::DataFrame; 
                                    volatility_window::Int = 12,
                                    portfolio_size::Int = 20,
                                    verbose::Bool = true)::Dict{String, Vector{Float64}}
    
    if verbose
        println("🔬 Criando portfólios baseados em volatilidade histórica...")
        println("   Janela de volatilidade: $volatility_window meses")
        println("   Tamanho do portfólio: $portfolio_size ações")
    end
    
    dates = returns_df.date
    ticker_columns = names(returns_df)[2:end]  # Excluir coluna 'date'
    
    low_vol_returns = Union{Float64, Missing}[]
    high_vol_returns = Union{Float64, Missing}[]
    long_short_returns = Union{Float64, Missing}[]
    
    for i in (volatility_window + 1):nrow(returns_df)
        current_date = dates[i]
        
        # Calcular volatilidade histórica para cada ação
        volatilities = Dict{String, Float64}()
        
        for ticker in ticker_columns
            # Usar dados dos últimos 'volatility_window' meses
            historical_returns = returns_df[i-volatility_window:i-1, ticker]
            
            # Remover valores missing
            clean_returns = filter(!ismissing, historical_returns)
            
            if length(clean_returns) >= volatility_window * 0.7  # Pelo menos 70% dos dados
                vol = std(clean_returns)
                volatilities[ticker] = vol
            end
        end
        
        if length(volatilities) >= portfolio_size * 2  # Dados suficientes para formar portfólios
            # Ordenar por volatilidade
            sorted_vols = sort(collect(volatilities), by = x -> x[2])
            
            # Selecionar ações de baixa e alta volatilidade
            low_vol_tickers = [ticker for (ticker, vol) in sorted_vols[1:portfolio_size]]
            high_vol_tickers = [ticker for (ticker, vol) in sorted_vols[end-portfolio_size+1:end]]
            
            # Calcular retornos dos portfólios (equally weighted)
            low_vol_ret = 0.0
            high_vol_ret = 0.0
            n_low = 0
            n_high = 0
            
            # Portfólio Low Vol
            for ticker in low_vol_tickers
                ret = returns_df[i, ticker]
                if !ismissing(ret)
                    low_vol_ret += ret
                    n_low += 1
                end
            end
            
            # Portfólio High Vol
            for ticker in high_vol_tickers
                ret = returns_df[i, ticker]
                if !ismissing(ret)
                    high_vol_ret += ret
                    n_high += 1
                end
            end
            
            if n_low > 0 && n_high > 0
                low_vol_avg = low_vol_ret / n_low
                high_vol_avg = high_vol_ret / n_high
                long_short_avg = low_vol_avg - high_vol_avg
                
                push!(low_vol_returns, low_vol_avg)
                push!(high_vol_returns, high_vol_avg)
                push!(long_short_returns, long_short_avg)
            else
                # CORREÇÃO: usar missing ao invés de zeros
                push!(low_vol_returns, missing)
                push!(high_vol_returns, missing)
                push!(long_short_returns, missing)
            end
        else
            # CORREÇÃO: usar missing ao invés de zeros
            push!(low_vol_returns, missing)
            push!(high_vol_returns, missing)
            push!(long_short_returns, missing)
        end
    end
    
    portfolios = Dict(
        "Baixa Volatilidade" => low_vol_returns,
        "Alta Volatilidade" => high_vol_returns,
        "Long-Short" => long_short_returns
    )
    
    if verbose
        println("✅ Portfólios criados com $(length(low_vol_returns)) observações mensais")
        for (name, returns) in portfolios
            println("   $name: Retorno médio = $(round(mean(returns), digits=2))%, Vol = $(round(std(returns), digits=2))%")
        end
    end
    
    return portfolios
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
Cria 5 portfólios de quintis baseados em volatilidade histórica real.
Conforme especificação: P1=menor vol ... P5=maior vol, equal-weighted.

Métodos de volatilidade disponíveis:
- :monthly12 - Desvio padrão de retornos mensais em janela de 12 meses (implementado)
- :daily252 - Volatilidade anualizada a partir de retornos diários em janela de 252 pregões (implementado - requer price_data)
"""
function create_volatility_quintile_portfolios(returns_df::DataFrame; 
                                              method::Symbol = :monthly12,
                                              price_data::Union{Dict{String, DataFrame}, Nothing} = nothing,
                                              min_obs::Int = 12,
                                              min_per_quintile::Int = 5,
                                              verbose::Bool = true)::DataFrame
    
    if verbose
        println("🔬 Criando 5 quintis baseados em volatilidade histórica...")
        println("   Método: $(method == :monthly12 ? "12 meses mensais" : "252 dias diários")")
        println("   Mín observações: $min_obs $(method == :monthly12 ? "meses" : "dias")")
        println("   Mín por quintil: $min_per_quintile ações")
    end
    
    # Verificar se o método :daily252 requer dados de preços
    if method == :daily252 && price_data === nothing
        error("Método :daily252 requer price_data para calcular retornos diários")
    end
    
    # Calcular retornos diários se necessário
    daily_returns_df = nothing
    if method == :daily252
        daily_returns_df = calculate_daily_returns(price_data, verbose=verbose)
    end
    
    dates = returns_df.date
    ticker_columns = names(returns_df)[2:end]  # Excluir coluna 'date'
    
    # Preparar arrays para os retornos dos quintis
    P1_returns = Float64[]  # Menor volatilidade
    P2_returns = Float64[]
    P3_returns = Float64[]
    P4_returns = Float64[]
    P5_returns = Float64[]  # Maior volatilidade
    LowMinusHigh_returns = Float64[]  # P1 - P5
    valid_dates = Date[]
    
    # Janela de volatilidade baseada no método
    volatility_window = method == :monthly12 ? 12 : 252  # 12 meses ou 252 dias
    
    for i in (volatility_window + 1):nrow(returns_df)
        current_date = dates[i]
        
        # Calcular volatilidade histórica para cada ação
        volatilities = Dict{String, Float64}()
        
        if method == :monthly12
            # Método tradicional com retornos mensais
            for ticker in ticker_columns
                # Usar dados dos últimos meses para volatilidade
                historical_returns = returns_df[i-volatility_window:i-1, ticker]
                
                # Remover valores missing
                clean_returns = filter(!ismissing, historical_returns)
                
                if length(clean_returns) >= min_obs * 0.7  # Pelo menos 70% dos dados
                    vol = std(clean_returns)
                    volatilities[ticker] = vol
                end
            end
        elseif method == :daily252
            # Método com retornos diários (252 dias de trading)
            volatilities = calculate_252d_volatility(daily_returns_df, current_date, 
                                                   window_days=252, min_obs=min_obs)
        end
        
        # Precisamos de pelo menos min_per_quintile * 5 ações para formar 5 quintis
        if length(volatilities) >= min_per_quintile * 5
            # Ordenar por volatilidade crescente
            sorted_vols = sort(collect(volatilities), by = x -> x[2])
            n_stocks = length(sorted_vols)
            quintile_size = div(n_stocks, 5)
            
            # Garantir que temos pelo menos min_per_quintile ações por quintil
            if quintile_size >= min_per_quintile
                # Dividir em 5 quintis
                P1_tickers = [ticker for (ticker, vol) in sorted_vols[1:quintile_size]]
                P2_tickers = [ticker for (ticker, vol) in sorted_vols[quintile_size+1:2*quintile_size]]
                P3_tickers = [ticker for (ticker, vol) in sorted_vols[2*quintile_size+1:3*quintile_size]]
                P4_tickers = [ticker for (ticker, vol) in sorted_vols[3*quintile_size+1:4*quintile_size]]
                P5_tickers = [ticker for (ticker, vol) in sorted_vols[4*quintile_size+1:5*quintile_size]]
                
                # Calcular retornos equal-weighted para cada quintil
                quintile_data = [
                    (P1_tickers, "P1"),
                    (P2_tickers, "P2"), 
                    (P3_tickers, "P3"),
                    (P4_tickers, "P4"),
                    (P5_tickers, "P5")
                ]
                
                quintile_returns = Union{Float64, Missing}[]
                
                for (tickers, name) in quintile_data
                    total_return = 0.0
                    valid_count = 0
                    
                    for ticker in tickers
                        ret = returns_df[i, ticker]
                        if !ismissing(ret)
                            total_return += ret
                            valid_count += 1
                        end
                    end
                    
                    if valid_count > 0
                        avg_return = total_return / valid_count
                        push!(quintile_returns, avg_return)
                    else
                        # CORREÇÃO: usar missing ao invés de zero quando não há dados válidos
                        push!(quintile_returns, missing)
                    end
                end
                
                # Armazenar os retornos dos quintis (tratar missing values)
                if length(quintile_returns) == 5 && !any(ismissing, quintile_returns)
                    push!(P1_returns, quintile_returns[1])
                    push!(P2_returns, quintile_returns[2])
                    push!(P3_returns, quintile_returns[3])
                    push!(P4_returns, quintile_returns[4])
                    push!(P5_returns, quintile_returns[5])
                    push!(LowMinusHigh_returns, quintile_returns[1] - quintile_returns[5])  # P1 - P5
                    push!(valid_dates, current_date)
                end
            else
                # Não há ações suficientes para formar quintis válidos
                continue
            end
        else
            # Não há dados suficientes para formar quintis
            continue
        end
    end
    
    # Criar DataFrame final com os resultados
    result_df = DataFrame(
        date = valid_dates,
        P1 = P1_returns,
        P2 = P2_returns,
        P3 = P3_returns,
        P4 = P4_returns,
        P5 = P5_returns,
        LowMinusHigh = LowMinusHigh_returns
    )
    
    if verbose
        println("✅ Quintis criados com $(nrow(result_df)) observações mensais")
        println("   📊 ESTATÍSTICAS DOS QUINTIS:")
        for col in [:P1, :P2, :P3, :P4, :P5, :LowMinusHigh]
            ret_mean = mean(result_df[!, col])
            ret_vol = std(result_df[!, col])
            println("   $(string(col)): Ret=$(round(ret_mean, digits=2))%, Vol=$(round(ret_vol, digits=2))%")
        end
    end
    
    return result_df
end

"""
Função principal para obter retornos de portfólios reais.
"""
function get_real_portfolio_returns(start_date::Date = Date(2000, 1, 1),
                                   end_date::Date = Date(2024, 12, 31);
                                   max_tickers::Int = 100,
                                   portfolio_size::Int = 20,
                                   force::Bool = false,
                                   verbose::Bool = true)::Dict{String, Vector{Float64}}
    
    if verbose
        println("🚀 INICIANDO DOWNLOAD DE DADOS REAIS DE MERCADO")
        println("=" ^ 60)
        println("Período: $start_date a $end_date")
        println("Max tickers: $max_tickers")
        println("Tamanho do portfólio: $portfolio_size")
        println()
    end
    
    # 1. Carregar constituintes históricos
    constituents_df = load_sp500_constituents()
    
    # 2. Obter lista única de tickers no período
    period_data = filter(row -> start_date <= row.date <= end_date, constituents_df)
    all_tickers = String[]
    
    for row in eachrow(period_data)
        append!(all_tickers, row.tickers_array)
    end
    
    unique_tickers = unique(all_tickers)
    
    if verbose
        println("📊 Encontrados $(length(unique_tickers)) tickers únicos no período")
    end
    
    # 3. Baixar dados de preços
    price_data = download_stock_data(unique_tickers, start_date, end_date, 
                                   max_tickers=max_tickers, force=force, verbose=verbose)
    
    if isempty(price_data)
        error("❌ Nenhum dado de preços foi baixado com sucesso")
    end
    
    # 4. Calcular retornos mensais
    returns_df = calculate_returns(price_data, start_date, end_date, verbose=verbose)
    
    # 5. Criar portfólios por volatilidade
    portfolios = create_volatility_portfolios(returns_df, portfolio_size=portfolio_size, verbose=verbose)
    
    if verbose
        println("\n🎉 DADOS REAIS CARREGADOS COM SUCESSO!")
        println("=" ^ 60)
    end
    
    return portfolios
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
    if !isfile(file_path)
        error("Arquivo de constituintes históricos não encontrado: $file_path")
    end
    
    println("📋 Carregando constituintes históricos do S&P 500...")
    println("   Arquivo: $file_path")
    
    # Ler arquivo CSV
    try
        raw_df = CSV.read(file_path, DataFrame)
        
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
    clean_ticker_for_yahoo(ticker::String)::String

Limpa e mapeia símbolos de tickers para formato compatível com Yahoo Finance.
Aplica mapeamentos conhecidos para símbolos problemáticos.

# Argumentos  
- `ticker`: Símbolo original

# Retorna
- Símbolo limpo/mapeado para Yahoo Finance

# Exemplos
```julia
clean_ticker_for_yahoo("BRK.B")   # → "BRK-B" 
clean_ticker_for_yahoo("BF-B")    # → "BF-B" (já correto)
clean_ticker_for_yahoo("AAMRQ")   # → "AAMRQ" (extinta, manteremos para tentativa)
```
"""
function clean_ticker_for_yahoo(ticker::String)::String
    # Remove espaços e converte para uppercase
    ticker = strip(uppercase(ticker))
    
    # Mapeamentos específicos (ticker histórico → ticker Yahoo atual)
    mappings = Dict(
        # Classes de ações (pontos → hífens)
        "BRK.B" => "BRK-B",
        "BRK.A" => "BRK-A",
        "BF.B" => "BF-B",
        "BF.A" => "BF-A",
        
        # Casos históricos importantes
        "FB" => "META",     # Facebook → Meta
        "GOOG" => "GOOGL",  # Usar classe votante
        
        # Mapeamentos de qualidade conhecidos
        "BERKSHIRE HATHAWAY B" => "BRK-B",
        "BERKSHIRE HATHAWAY A" => "BRK-A",
        
        # Tickers problemáticos comuns
        "GOOGL" => "GOOGL",
        "AAPL" => "AAPL", 
        "MSFT" => "MSFT",
        "AMZN" => "AMZN",
        "TSLA" => "TSLA",
        "NVDA" => "NVDA",
        "META" => "META",
        "JPM" => "JPM",
        "V" => "V",
        "JNJ" => "JNJ",
        "WMT" => "WMT",
        "PG" => "PG",
        "UNH" => "UNH",
        "MA" => "MA",
        "HD" => "HD",
        "CVX" => "CVX",
        "LLY" => "LLY",
        "ABBV" => "ABBV",
        "PFE" => "PFE",
        "KO" => "KO",
        "BAC" => "BAC",
        "AVGO" => "AVGO",
        "PEP" => "PEP",
        "TMO" => "TMO",
        "COST" => "COST",
        "MRK" => "MRK",
        "ACN" => "ACN",
        "ADBE" => "ADBE",
        "NFLX" => "NFLX",
        "ABT" => "ABT",
        "CSCO" => "CSCO",
        "CRM" => "CRM",
        "XOM" => "XOM",
        "DHR" => "DHR",
        "ORCL" => "ORCL",
        "VZ" => "VZ",
        "NKE" => "NKE",
        "DIS" => "DIS",
        "INTC" => "INTC",
        "TXN" => "TXN",
        "CMCSA" => "CMCSA",
        "AMD" => "AMD",
        "IBM" => "IBM",
        "WFC" => "WFC",
        "MCD" => "MCD",
        "NEE" => "NEE",
        "UNP" => "UNP",
        "PM" => "PM",
        "RTX" => "RTX",
        "T" => "T",
        "QCOM" => "QCOM",
        "LOW" => "LOW",
        "SPGI" => "SPGI",
        "HON" => "HON",
        "COP" => "COP",
        "INTU" => "INTU",
        "UPS" => "UPS",
        "AXP" => "AXP",
        "MS" => "MS",
        "CAT" => "CAT",
        "GE" => "GE",
        "BKNG" => "BKNG",
        "MDT" => "MDT",
        "DE" => "DE",
        "ISRG" => "ISRG",
        "AMGN" => "AMGN",
        "NOW" => "NOW",
        "BLK" => "BLK",
        "SCHW" => "SCHW",
        "SYK" => "SYK",
        "TJX" => "TJX",
        "LMT" => "LMT",
        "VRTX" => "VRTX",
        "MMM" => "MMM",
        "ELV" => "ELV",
        "GILD" => "GILD",
        "PANW" => "PANW",
        "GS" => "GS",
        "CVS" => "CVS",
        "ADI" => "ADI",
        "CI" => "CI",
        "ADP" => "ADP",
        "C" => "C",
        "BSX" => "BSX",
        "SO" => "SO",
        "TMUS" => "TMUS",
        "ETN" => "ETN",
        "MO" => "MO",
        "CME" => "CME",
        "CB" => "CB",
        "ZTS" => "ZTS",
        "EQIX" => "EQIX",
        "APH" => "APH",
        "MMC" => "MMC",
        "ITW" => "ITW",
        "PGR" => "PGR",
        "AON" => "AON",
        "MDLZ" => "MDLZ",
        "SHW" => "SHW",
        "DUK" => "DUK",
        "ICE" => "ICE",
        "PYPL" => "PYPL",
        "REGN" => "REGN",
        "TGT" => "TGT",
        "NSC" => "NSC",
        "KLAC" => "KLAC",
        "CL" => "CL",
        "FCX" => "FCX",
        "EMR" => "EMR",
        "LRCX" => "LRCX",
        "TFC" => "TFC",
        "SNPS" => "SNPS",
        "ABNB" => "ABNB"
    )
    
    # Aplicar mapeamento direto se existir  
    if haskey(mappings, ticker)
        return mappings[ticker]
    end
    
    # Substituições genéricas em ordem
    cleaned = ticker
    
    # 1. Classes de ações: pontos → hífens (regex para .A ou .B no final)
    cleaned = replace(cleaned, r"\.([AB])$" => s"-\1")
    
    # 2. Remove sufixos corporativos comuns
    cleaned = replace(cleaned, r"\s+(INC|CORP|CO|LTD|LLC)\.?$" => "")
    cleaned = replace(cleaned, r"\s+CLASS\s+[AB]$" => "")
    
    # 3. Outros pontos → hífens (caso não seja .A/.B)  
    cleaned = replace(cleaned, "." => "-")
    
    # 4. Remove espaços extras e caracteres especiais
    cleaned = replace(cleaned, r"[^A-Z0-9\-]" => "")
    
    # 5. Truncar se muito longo (Yahoo raramente > 8 chars)
    if length(cleaned) > 8
        cleaned = cleaned[1:5]
    end
    
    return cleaned
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
        # Normalizar ticker para formato Yahoo
        clean_ticker = clean_ticker_for_yahoo(ticker)
        if clean_ticker in available_tickers
            push!(eligible, clean_ticker)
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
        # 1. Tem dados na data alvo (ou próximo)
        # 2. Tem pelo menos min_lookback_months de dados antes da data alvo
        
        target_month = Date(year(target_date), month(target_date), 1)
        
        if data_start <= lookback_date && data_end >= target_month
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
