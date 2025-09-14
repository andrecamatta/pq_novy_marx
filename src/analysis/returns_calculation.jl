"""
Módulo para cálculo de retornos - extrai funções do market_data.jl
"""
module ReturnsCalculation

using DataFrames, Dates, Statistics

export calculate_returns, calculate_daily_returns, calculate_monthly_returns

"""
    calculate_returns(price_data, start_date, end_date; verbose=false)

Calcula retornos mensais a partir de dados de preços
"""
function calculate_returns(
    price_data::Dict{String, DataFrame},
    start_date::Date,
    end_date::Date;
    verbose::Bool = false
)::DataFrame

    if verbose
        println("\n📊 CALCULANDO RETORNOS MENSAIS")
        println("="^60)
    end

    # Inicializar DataFrame de retornos
    returns_df = DataFrame(Date = Date[])

    # Gerar datas mensais
    current_date = Date(year(start_date), month(start_date), lastdayofmonth(start_date))
    dates = Date[]

    while current_date <= end_date
        push!(dates, current_date)
        current_date = lastdayofmonth(current_date + Day(1))
    end

    returns_df.Date = dates

    # Calcular retornos para cada ticker
    tickers_processados = 0
    tickers_com_dados = 0

    for (ticker, df) in price_data
        if isempty(df)
            continue
        end

        tickers_processados += 1

        # Calcular retornos mensais
        monthly_returns = Float64[]

        for i in 1:length(dates)
            month_end = dates[i]
            month_start = i == 1 ? start_date : dates[i-1] + Day(1)

            # Buscar preços
            start_data = filter(row -> row.Date <= month_start, df)
            end_data = filter(row -> row.Date <= month_end, df)

            if !isempty(start_data) && !isempty(end_data)
                start_price = last(start_data).Close
                end_price = last(end_data).Close

                if start_price > 0 && end_price > 0
                    ret = (end_price - start_price) / start_price * 100
                    push!(monthly_returns, ret)
                else
                    push!(monthly_returns, missing)
                end
            else
                push!(monthly_returns, missing)
            end
        end

        # Adicionar ao DataFrame se tem dados válidos
        if any(!ismissing, monthly_returns)
            returns_df[!, Symbol(ticker)] = monthly_returns
            tickers_com_dados += 1
        end
    end

    if verbose
        println("✅ Retornos calculados para $tickers_com_dados de $tickers_processados tickers")
        println("📅 Período: $(first(dates)) a $(last(dates))")
        println("📊 Total de meses: $(length(dates))")
    end

    return returns_df
end

"""
    calculate_daily_returns(price_data; verbose=false)

Calcula retornos diários para todos os tickers
"""
function calculate_daily_returns(
    price_data::Dict{String, DataFrame};
    verbose::Bool = false
)::DataFrame

    if verbose
        println("\n📊 CALCULANDO RETORNOS DIÁRIOS")
        println("="^60)
    end

    # Coletar todas as datas únicas
    all_dates = Set{Date}()
    for (_, df) in price_data
        if !isempty(df)
            union!(all_dates, df.Date)
        end
    end

    dates = sort(collect(all_dates))

    # Inicializar DataFrame
    returns_df = DataFrame(Date = dates)

    # Calcular retornos para cada ticker
    tickers_processados = 0

    for (ticker, df) in price_data
        if isempty(df) || nrow(df) < 2
            continue
        end

        tickers_processados += 1

        # Ordenar por data
        sort!(df, :Date)

        # Criar série de retornos alinhada com todas as datas
        returns = Vector{Union{Float64, Missing}}(missing, length(dates))

        for i in 2:nrow(df)
            date = df.Date[i]
            date_idx = findfirst(d -> d == date, dates)

            if !isnothing(date_idx)
                prev_price = df.Close[i-1]
                curr_price = df.Close[i]

                if prev_price > 0 && curr_price > 0
                    # Retorno log
                    returns[date_idx] = log(curr_price / prev_price)
                end
            end
        end

        returns_df[!, Symbol(ticker)] = returns
    end

    if verbose
        println("✅ Retornos diários calculados para $tickers_processados tickers")
        println("📅 Período: $(first(dates)) a $(last(dates))")
        println("📊 Total de dias: $(length(dates))")
    end

    return returns_df
end

"""
    calculate_monthly_returns(daily_returns_df)

Converte retornos diários em mensais
"""
function calculate_monthly_returns(daily_returns_df::DataFrame)::DataFrame
    # Agrupar por mês e somar retornos log
    monthly_df = DataFrame()

    # Extrair ano-mês de cada data
    daily_returns_df.YearMonth = Dates.format.(daily_returns_df.Date, "yyyy-mm")

    # Agrupar por YearMonth
    grouped = groupby(daily_returns_df, :YearMonth)

    for group in grouped
        month_data = Dict{Symbol, Any}()
        month_data[:Date] = lastdayofmonth(last(group.Date))

        # Para cada ticker, somar retornos log
        for col in names(group)
            if col ∉ [:Date, :YearMonth]
                returns = skipmissing(group[!, col])
                if !isempty(returns)
                    # Converter de log para retorno simples mensal
                    month_data[col] = (exp(sum(returns)) - 1) * 100
                else
                    month_data[col] = missing
                end
            end
        end

        if isempty(monthly_df)
            monthly_df = DataFrame(month_data)
        else
            push!(monthly_df, month_data)
        end
    end

    select!(monthly_df, Not(:YearMonth))
    return monthly_df
end

end # module