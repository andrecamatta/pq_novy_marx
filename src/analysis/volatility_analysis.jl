"""
Módulo para análise de volatilidade - extrai funções do market_data.jl
"""
module VolatilityAnalysis

using DataFrames, Dates, Statistics

export calculate_252d_volatility, calculate_portfolio_volatilities, calculate_rolling_volatility

"""
    calculate_252d_volatility(daily_returns_df, date; min_days=200)

Calcula volatilidade de 252 dias para todos os tickers em uma data específica
"""
function calculate_252d_volatility(
    daily_returns_df::DataFrame,
    date::Date;
    min_days::Int = 200,
    verbose::Bool = false
)::Dict{String, Float64}

    volatilities = Dict{String, Float64}()

    # Data de início para lookback de 252 dias
    start_date = date - Day(252)

    # Filtrar período
    period_data = filter(row -> start_date <= row.Date <= date, daily_returns_df)

    if nrow(period_data) < min_days
        verbose && println("   ⚠️ Dados insuficientes para volatilidade: $(nrow(period_data)) dias")
        return volatilities
    end

    # Calcular volatilidade para cada ticker
    for col in names(period_data)
        if col == "Date"
            continue
        end

        returns = skipmissing(period_data[!, col])

        if length(returns) >= min_days
            vol = std(returns) * sqrt(252)  # Anualizar
            volatilities[string(col)] = vol
        end
    end

    return volatilities
end

"""
    calculate_252d_volatility(price_data, date; min_days=200)

Versão alternativa que recebe price_data diretamente
"""
function calculate_252d_volatility(
    price_data::Dict{String, DataFrame},
    date::Date;
    min_days::Int = 200,
    verbose::Bool = false
)::Dict{String, Float64}

    volatilities = Dict{String, Float64}()

    for (ticker, df) in price_data
        if isempty(df)
            continue
        end

        vol = calculate_ticker_volatility_252d(df, date, min_days=min_days)
        if !isnan(vol)
            volatilities[ticker] = vol
        end
    end

    if verbose
        println("✅ Volatilidades calculadas para $(length(volatilities)) tickers")
    end

    return volatilities
end

"""
    calculate_ticker_volatility_252d(df, date; min_days=200)

Calcula volatilidade de 252 dias para um ticker específico
"""
function calculate_ticker_volatility_252d(
    df::DataFrame,
    date::Date;
    min_days::Int = 200
)::Float64

    # Período de 252 dias até a data
    start_date = date - Day(252)
    period_data = filter(row -> start_date <= row.Date <= date, df)

    if nrow(period_data) < 2
        return NaN
    end

    # Calcular retornos diários
    prices = period_data.Close
    returns = Float64[]

    for i in 2:length(prices)
        if prices[i-1] > 0 && prices[i] > 0
            push!(returns, log(prices[i] / prices[i-1]))
        end
    end

    if length(returns) < min_days
        return NaN
    end

    # Volatilidade anualizada
    return std(returns) * sqrt(252)
end

"""
    calculate_portfolio_volatilities(portfolio_returns_df; window=12)

Calcula volatilidade móvel para portfolios
"""
function calculate_portfolio_volatilities(
    portfolio_returns_df::DataFrame;
    window::Int = 12
)::DataFrame

    vol_df = DataFrame(Date = portfolio_returns_df.Date)

    for col in names(portfolio_returns_df)
        if col == "Date"
            continue
        end

        returns = portfolio_returns_df[!, col]
        rolling_vols = Float64[]

        for i in 1:nrow(portfolio_returns_df)
            start_idx = max(1, i - window + 1)
            end_idx = i

            if end_idx - start_idx + 1 >= 6  # Mínimo 6 observações
                window_returns = returns[start_idx:end_idx]
                valid_returns = skipmissing(window_returns)

                if length(valid_returns) >= 6
                    vol = std(valid_returns) * sqrt(12)  # Anualizar
                    push!(rolling_vols, vol)
                else
                    push!(rolling_vols, NaN)
                end
            else
                push!(rolling_vols, NaN)
            end
        end

        vol_df[!, Symbol(string(col, "_Vol"))] = rolling_vols
    end

    return vol_df
end

"""
    calculate_rolling_volatility(returns, window; annualize=true)

Calcula volatilidade móvel para uma série de retornos
"""
function calculate_rolling_volatility(
    returns::Vector{Float64},
    window::Int;
    annualize::Bool = true
)::Vector{Float64}

    rolling_vols = Float64[]

    for i in 1:length(returns)
        start_idx = max(1, i - window + 1)
        end_idx = i

        window_returns = returns[start_idx:end_idx]

        if length(window_returns) >= max(3, window ÷ 2)
            vol = std(window_returns)
            if annualize
                vol *= sqrt(252)  # Para retornos diários
            end
            push!(rolling_vols, vol)
        else
            push!(rolling_vols, NaN)
        end
    end

    return rolling_vols
end

"""
    rank_by_volatility(volatilities; ascending=true)

Ordena tickers por volatilidade
"""
function rank_by_volatility(
    volatilities::Dict{String, Float64};
    ascending::Bool = true
)::Vector{String}

    valid_vols = filter(p -> !isnan(p.second), volatilities)

    if ascending
        return sort(collect(keys(valid_vols)), by=t -> valid_vols[t])
    else
        return sort(collect(keys(valid_vols)), by=t -> valid_vols[t], rev=true)
    end
end

"""
    create_volatility_quintiles(tickers, volatilities)

Divide tickers em quintis de volatilidade
"""
function create_volatility_quintiles(
    tickers::Vector{String},
    volatilities::Dict{String, Float64}
)::Dict{Int, Vector{String}}

    # Filtrar tickers com volatilidade válida
    valid_tickers = filter(t -> haskey(volatilities, t) && !isnan(volatilities[t]), tickers)

    if length(valid_tickers) < 10
        return Dict{Int, Vector{String}}()
    end

    # Ordenar por volatilidade (crescente)
    sorted_tickers = sort(valid_tickers, by=t -> volatilities[t])

    # Dividir em quintis
    quintiles = Dict{Int, Vector{String}}()
    n_per_quintile = length(sorted_tickers) ÷ 5

    for q in 1:5
        if q < 5
            quintiles[q] = sorted_tickers[((q-1)*n_per_quintile + 1):(q*n_per_quintile)]
        else
            # Último quintil pega todos os restantes
            quintiles[q] = sorted_tickers[((q-1)*n_per_quintile + 1):end]
        end
    end

    return quintiles
end

end # module