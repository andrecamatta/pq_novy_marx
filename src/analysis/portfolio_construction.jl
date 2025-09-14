"""
Módulo para construção de portfolios - extrai funções do market_data.jl
"""
module PortfolioConstruction

using DataFrames, Dates, Statistics

export create_volatility_quintile_portfolios_pti, get_quintile_portfolios_pti,
       get_valid_tickers_for_month, get_eligible_tickers_for_date

# Cache leve para acelerar consulta de constituintes point-in-time
const _pti_constituents_cache = Dict{Date, Vector{String}}()
const _pti_sorted_dates_cache = Ref{Vector{Date}}(Vector{Date}())

"""
    create_volatility_quintile_portfolios_pti(returns_df, constituents_df; kwargs...)

Cria portfolios de quintis baseados em volatilidade usando metodologia point-in-time
Compatible with original system methodology: volatility from monthly returns
"""
function create_volatility_quintile_portfolios_pti(
    returns_df::DataFrame,
    constituents_df::DataFrame;
    method::Symbol = :monthly12,
    lookback::Int = 12,
    min_coverage::Float64 = 0.7,
    min_per_quintile::Int = 5,
    verbose::Bool = true
)::DataFrame

    if verbose
        println("🔬 Criando quintis P1-P5 point-in-time (metodologia Novy-Marx)")
        println("   Método: $(method == :monthly12 ? "$lookback meses mensais" : "$lookback dias diários")")
        println("   Min coverage: $(round(min_coverage*100, digits=1))%")
        println("   Min por quintil: $min_per_quintile ações")
        println("   Universo point-in-time: S&P 500 constituents")
    end

    # Verificar estrutura do DataFrame de retornos
    date_col = if "date" in names(returns_df)
        "date"
    elseif "Date" in names(returns_df)
        "Date"
    else
        error("returns_df deve ter coluna 'date' ou 'Date'")
    end

    dates = returns_df[!, date_col]
    ticker_columns = [name for name in names(returns_df) if name != date_col]

    if verbose
        println("   📊 DataFrame retornos: $(nrow(returns_df)) meses, $(length(ticker_columns)) tickers")
    end

    # Arrays de saída (seguindo formato original)
    P1_returns = Union{Float64, Missing}[]
    P2_returns = Union{Float64, Missing}[]
    P3_returns = Union{Float64, Missing}[]
    P4_returns = Union{Float64, Missing}[]
    P5_returns = Union{Float64, Missing}[]
    LowMinusHigh_returns = Union{Float64, Missing}[]

    # Iterar por cada mês (a partir do 2º mês para ter dados históricos)
    for i in (lookback + 2):nrow(returns_df)
        formation_date = dates[i-1]  # Mês de formação (t-1)
        holding_date = dates[i]      # Mês de holding (t)

        # 1. UNIVERSO POINT-IN-TIME: filtrar tickers elegíveis na data de formação
        eligible_tickers = get_eligible_tickers_for_date(
            constituents_df,
            formation_date,
            ticker_columns
        )

        if length(eligible_tickers) < min_per_quintile * 5
            # Pular mês se poucos tickers elegíveis
            push!(P1_returns, missing)
            push!(P2_returns, missing)
            push!(P3_returns, missing)
            push!(P4_returns, missing)
            push!(P5_returns, missing)
            push!(LowMinusHigh_returns, missing)
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
                    volatilities[ticker] = std(clean_returns)  # SEM anualização (como original!)
                end
            end
        end

        # 3. FORMAÇÃO DE QUINTIS (ordenação crescente por volatilidade)
        valid_vol_tickers = collect(keys(volatilities))
        if length(valid_vol_tickers) < min_per_quintile * 5
            # Pular se volatilidades insuficientes
            push!(P1_returns, missing)
            push!(P2_returns, missing)
            push!(P3_returns, missing)
            push!(P4_returns, missing)
            push!(P5_returns, missing)
            push!(LowMinusHigh_returns, missing)
            continue
        end

        # Ordenar tickers por volatilidade (crescente: P1=baixa, P5=alta)
        sorted_tickers = sort(valid_vol_tickers, by=t -> volatilities[t])

        # Dividir em quintis
        n_per_quintile = length(sorted_tickers) ÷ 5
        quintiles = Dict{Int, Vector{String}}()

        for q in 1:5
            if q < 5
                quintiles[q] = sorted_tickers[((q-1)*n_per_quintile + 1):(q*n_per_quintile)]
            else
                # Último quintil pega todos os restantes
                quintiles[q] = sorted_tickers[((q-1)*n_per_quintile + 1):end]
            end
        end

        # 4. CÁLCULO DE RETORNOS DOS PORTFOLIOS (equal weight)
        portfolio_returns = Float64[]

        for q in 1:5
            q_returns = Float64[]
            for ticker in quintiles[q]
                if !ismissing(returns_df[i, ticker])
                    push!(q_returns, returns_df[i, ticker])
                end
            end

            # Retorno médio do quintil (equal weight)
            avg_return = isempty(q_returns) ? 0.0 : mean(q_returns)
            push!(portfolio_returns, avg_return)
        end

        # 5. ARMAZENAR RESULTADOS
        push!(P1_returns, portfolio_returns[1])
        push!(P2_returns, portfolio_returns[2])
        push!(P3_returns, portfolio_returns[3])
        push!(P4_returns, portfolio_returns[4])
        push!(P5_returns, portfolio_returns[5])
        push!(LowMinusHigh_returns, portfolio_returns[1] - portfolio_returns[5])  # P1 - P5

        if verbose && i <= (lookback + 4)  # Debug primeiros meses
            println("   📅 $(Dates.format(holding_date, "yyyy-mm")): P1=$(round(portfolio_returns[1], digits=2))%, P5=$(round(portfolio_returns[5], digits=2))%, LMH=$(round(portfolio_returns[1] - portfolio_returns[5], digits=2))%")
        end
    end

    # Criar DataFrame resultado
    result_dates = dates[(lookback + 2):end]

    portfolio_df = DataFrame(
        Date = result_dates,
        P1 = P1_returns,
        P2 = P2_returns,
        P3 = P3_returns,
        P4 = P4_returns,
        P5 = P5_returns,
        LowMinusHigh = LowMinusHigh_returns
    )

    if verbose
        valid_months = sum(.!ismissing.(portfolio_df.P1))
        println("✅ Portfolios formados: $(valid_months) meses válidos de $(nrow(portfolio_df)) totais")
    end

    return portfolio_df
end

"""
    get_valid_tickers_for_month(price_data, constituents_df, month_date; kwargs...)

Obtém tickers válidos para formação de portfolio em determinado mês
"""
function get_valid_tickers_for_month(
    price_data::Dict{String, DataFrame},
    constituents_df::DataFrame,
    month_date::Date;
    lookback_days::Int = 252,
    min_coverage::Float64 = 0.8,
    verbose::Bool = false
)::Vector{String}

    # Data de formação (último dia do mês anterior)
    formation_date = Date(year(month_date), month(month_date), 1) - Day(1)

    # Tickers que eram constituintes na data
    eligible_tickers = get_eligible_tickers_for_date(
        constituents_df,
        formation_date,
        collect(keys(price_data))
    )

    valid_tickers = String[]

    for ticker in eligible_tickers
        if !haskey(price_data, ticker)
            continue
        end

        df = price_data[ticker]

        # Verificar se tem dados suficientes
        start_check = formation_date - Day(lookback_days)
        historical_data = filter(row -> start_check <= row.Date <= formation_date, df)

        if nrow(historical_data) >= lookback_days * min_coverage
            push!(valid_tickers, ticker)
        end
    end

    return valid_tickers
end

"""
    get_eligible_tickers_for_date(constituents_df, date, available_tickers)

Retorna tickers que eram constituintes do S&P 500 em determinada data
"""
function get_eligible_tickers_for_date(
    constituents_df::DataFrame,
    date::Date,
    available_tickers::Vector{String}
)::Vector{String}

    # Determinar coluna de data
    if "date" in names(constituents_df)
        date_col = :date
    else
        date_col = :Date
    end

    # Popular cache de datas ordenadas uma vez
    if isempty(_pti_sorted_dates_cache[]) || length(_pti_sorted_dates_cache[]) != length(unique(constituents_df[!, date_col]))
        _pti_sorted_dates_cache[] = sort(unique(constituents_df[!, date_col]))
    end

    # Encontrar a data mais próxima via busca binária + checagem vizinha
    sd = _pti_sorted_dates_cache[]
    if isempty(sd)
        return String[]
    end
    idx = searchsortedlast(sd, date)
    if idx < 1
        idx = 1
    end
    # Candidato seguinte (se mais próximo por diferença absoluta)
    if idx < length(sd)
        next_idx = idx + 1
        if abs(sd[next_idx] - date) < abs(sd[idx] - date)
            idx = next_idx
        end
    end
    closest_date = sd[idx]

    # Consultar cache por data
    if !haskey(_pti_constituents_cache, closest_date)
        date_constituents = filter(row -> row[date_col] == closest_date, constituents_df)
        if nrow(date_constituents) == 0
            _pti_constituents_cache[closest_date] = String[]
        else
            tickers_str = date_constituents[1, :tickers]
            if ismissing(tickers_str)
                _pti_constituents_cache[closest_date] = String[]
            else
                # Parse tickers uma única vez por data
                parsed = String[]
                for ticker_raw in split(string(tickers_str), ",")
                    t = strip(string(ticker_raw))
                    t = replace(t, r"\s*\(.*\)$" => "")  # remover anotações
                    t = strip(t)
                    if !isempty(t)
                        push!(parsed, t)
                    end
                end
                _pti_constituents_cache[closest_date] = parsed
            end
        end
    end

    # Filtrar pelos disponíveis nos dados de retornos
    return intersect(_pti_constituents_cache[closest_date], available_tickers)
end

"""
    calculate_ticker_volatility(df, date, lookback_days)

Calcula volatilidade de um ticker para determinada data
"""
function calculate_ticker_volatility(
    df::DataFrame,
    date::Date,
    lookback_days::Int;
    debug_ticker::String = ""
)::Float64

    start_date = date - Day(lookback_days)
    hist_data = filter(row -> start_date <= row.Date <= date, df)

    if debug_ticker != ""
        println("    🔍 DEBUG $debug_ticker:")
        println("      Data formation: $date")
        println("      Start lookback: $start_date")
        println("      DataFrame size: $(nrow(df))")
        println("      Filtered size: $(nrow(hist_data))")
        println("      Columns: $(names(df))")

        if nrow(hist_data) > 0
            println("      Date range: $(minimum(hist_data.Date)) to $(maximum(hist_data.Date))")
            if "Close" in names(hist_data)
                println("      Close values: $(length(hist_data.Close)) obs, range: $(extrema(hist_data.Close))")
                println("      Has zeros/negatives: $(any(hist_data.Close .<= 0))")
            else
                println("      ❌ Column 'Close' not found!")
            end
        end
    end

    if nrow(hist_data) < lookback_days * 0.8
        debug_ticker != "" && println("      ❌ Insufficient data: $(nrow(hist_data)) < $(lookback_days * 0.8)")
        return NaN
    end

    # Verificar se coluna Close existe
    if !("Close" in names(hist_data))
        debug_ticker != "" && println("      ❌ Column 'Close' not found in filtered data")
        return NaN
    end

    # Calcular retornos diários
    prices = hist_data.Close

    # Filtrar preços válidos (positivos)
    valid_prices = filter(p -> !ismissing(p) && p > 0, prices)

    if length(valid_prices) < 2
        debug_ticker != "" && println("      ❌ Insufficient valid prices: $(length(valid_prices))")
        return NaN
    end

    try
        returns = diff(log.(valid_prices))

        if debug_ticker != ""
            println("      Returns calculated: $(length(returns)) values")
            println("      Returns range: $(extrema(returns))")
            println("      Has infinite/NaN: $(any(!isfinite.(returns)))")
        end

        # Filtrar retornos finitos
        finite_returns = filter(isfinite, returns)

        if length(finite_returns) < 20
            debug_ticker != "" && println("      ❌ Insufficient finite returns: $(length(finite_returns))")
            return NaN
        end

        # Volatilidade anualizada
        vol = std(finite_returns) * sqrt(252)
        debug_ticker != "" && println("      ✅ Volatility calculated: $(round(vol, digits=4))")

        return vol

    catch e
        debug_ticker != "" && println("      ❌ Error in volatility calculation: $e")
        return NaN
    end
end

"""
    calculate_portfolio_returns(price_data, quintiles, start_date, end_date)

Calcula retornos mensais para cada quintil
"""
function calculate_portfolio_returns(
    price_data::Dict{String, DataFrame},
    quintiles::Dict{Int, Vector{String}},
    start_date::Date,
    end_date::Date
)::Dict{Int, Float64}

    returns = Dict{Int, Float64}()

    for q in 1:5
        q_returns = Float64[]

        for ticker in quintiles[q]
            if !haskey(price_data, ticker)
                continue
            end

            df = price_data[ticker]

            # Preços início e fim
            start_data = filter(row -> row.Date <= start_date, df)
            end_data = filter(row -> row.Date <= end_date, df)

            if !isempty(start_data) && !isempty(end_data)
                start_price = last(start_data).Close
                end_price = last(end_data).Close

                if start_price > 0 && end_price > 0
                    ret = (end_price - start_price) / start_price * 100
                    push!(q_returns, ret)
                end
            end
        end

        # Retorno médio do quintil (equal weight)
        returns[q] = isempty(q_returns) ? 0.0 : mean(q_returns)
    end

    return returns
end

"""
    get_quintile_portfolios_pti(lookback_months)

Função simplificada para obter nome dos portfolios
"""
function get_quintile_portfolios_pti(lookback_months::Int)::Vector{String}
    return ["P1", "P2", "P3", "P4", "P5", "Low_High"]
end

end # module
