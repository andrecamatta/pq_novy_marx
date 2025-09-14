"""
Módulo para construção de portfolios - extrai funções do market_data.jl
"""
module PortfolioConstruction

using DataFrames, Dates, Statistics

export create_volatility_quintile_portfolios_pti, get_quintile_portfolios_pti,
       get_valid_tickers_for_month, get_eligible_tickers_for_date

"""
    create_volatility_quintile_portfolios_pti(price_data, constituents_df, start_date, end_date; kwargs...)

Cria portfolios de quintis baseados em volatilidade usando metodologia point-in-time
"""
function create_volatility_quintile_portfolios_pti(
    price_data::Dict{String, DataFrame},
    constituents_df::DataFrame,
    start_date::Date,
    end_date::Date;
    lookback_days::Int = 252,
    min_coverage::Float64 = 0.8,
    min_per_quintile::Int = 10,
    verbose::Bool = false
)::DataFrame

    portfolios = DataFrame()
    current_date = start_date

    while current_date <= end_date
        month_start = Date(year(current_date), month(current_date), 1)
        month_end = min(lastdayofmonth(month_start), end_date)

        if verbose
            println("\n📅 Formando portfolios para $(Dates.format(month_start, "yyyy-mm"))")
        end

        # Obter tickers válidos para o mês
        valid_tickers = get_valid_tickers_for_month(
            price_data,
            constituents_df,
            month_start,
            lookback_days=lookback_days,
            min_coverage=min_coverage,
            verbose=verbose
        )

        if length(valid_tickers) < min_per_quintile * 5
            if verbose
                println("   ⚠️ Poucos tickers válidos: $(length(valid_tickers))")
            end
            current_date = month_start + Month(1)
            continue
        end

        # Calcular volatilidades
        volatilities = Dict{String, Float64}()
        formation_date = month_start - Day(1)  # Último dia do mês anterior

        for ticker in valid_tickers
            vol = calculate_ticker_volatility(price_data[ticker], formation_date, lookback_days)
            if !isnan(vol) && vol > 0
                volatilities[ticker] = vol
            end
        end

        if length(volatilities) < min_per_quintile * 5
            if verbose
                println("   ⚠️ Volatilidades insuficientes: $(length(volatilities))")
            end
            current_date = month_start + Month(1)
            continue
        end

        # Criar quintis
        sorted_tickers = sort(collect(keys(volatilities)), by=t -> volatilities[t])
        n_per_quintile = length(sorted_tickers) ÷ 5

        quintiles = Dict{Int, Vector{String}}()
        for q in 1:5
            if q < 5
                quintiles[q] = sorted_tickers[((q-1)*n_per_quintile + 1):(q*n_per_quintile)]
            else
                quintiles[q] = sorted_tickers[((q-1)*n_per_quintile + 1):end]
            end
        end

        # Calcular retornos dos portfolios
        monthly_returns = calculate_portfolio_returns(
            price_data,
            quintiles,
            month_start,
            month_end
        )

        # Adicionar ao DataFrame
        row = Dict(
            "Date" => month_end,
            "P1" => monthly_returns[1],
            "P2" => monthly_returns[2],
            "P3" => monthly_returns[3],
            "P4" => monthly_returns[4],
            "P5" => monthly_returns[5],
            "Low_High" => monthly_returns[1] - monthly_returns[5],
            "tickers_used" => length(volatilities)
        )

        if isempty(portfolios)
            portfolios = DataFrame(row)
        else
            push!(portfolios, row)
        end

        if verbose
            println("   ✅ Portfolios formados com $(length(volatilities)) tickers")
        end

        current_date = month_start + Month(1)
    end

    return portfolios
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

    # Filtrar constituintes para a data
    date_str = Dates.format(date, "yyyy-mm-dd")

    if "date" in names(constituents_df)
        date_col = :date
    else
        date_col = :Date
    end

    # Encontrar a data mais próxima
    constituents_df.temp_date = constituents_df[!, date_col]
    valid_dates = unique(constituents_df.temp_date)
    closest_date = valid_dates[argmin(abs.(valid_dates .- date))]

    date_constituents = filter(row -> row.temp_date == closest_date, constituents_df)

    if nrow(date_constituents) == 0
        return String[]
    end

    # Extrair tickers
    tickers_str = date_constituents[1, :tickers]
    tickers = [strip(t) for t in split(tickers_str, ",")]

    # Filtrar pelos disponíveis
    return intersect(tickers, available_tickers)
end

"""
    calculate_ticker_volatility(df, date, lookback_days)

Calcula volatilidade de um ticker para determinada data
"""
function calculate_ticker_volatility(
    df::DataFrame,
    date::Date,
    lookback_days::Int
)::Float64

    start_date = date - Day(lookback_days)
    hist_data = filter(row -> start_date <= row.Date <= date, df)

    if nrow(hist_data) < lookback_days * 0.8
        return NaN
    end

    # Calcular retornos diários
    prices = hist_data.Close
    returns = diff(log.(prices))

    if length(returns) < 20
        return NaN
    end

    # Volatilidade anualizada
    return std(returns) * sqrt(252)
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