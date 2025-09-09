using YFinance, DataFrames, Dates, Statistics, LinearAlgebra, CSV, Printf

# Academic universe (smaller for testing)
academic_tickers = ["AAPL", "MSFT", "GOOGL", "AMZN", "TSLA", "META", "BRK.A", "NVDA", "JNJ", "JPM",
                   "V", "PG", "UNH", "HD", "DIS", "PYPL", "BAC", "ADBE", "CRM", "NFLX"]

println("=== TESTE ANÁLISE ACADÊMICA ===")
println("Tickers: $(length(academic_tickers))")

# Download data for 2020-2023 period
start_date = "2020-01-01"
end_date = "2023-12-31"

println("Baixando dados: $start_date a $end_date")

price_data = DataFrame()
success_count = 0

for (i, ticker) in enumerate(academic_tickers)
    try
        data = get_prices(ticker, start_date=start_date, end_date=end_date)
        if nrow(data) > 500  # Minimum data requirement
            data[!, :ticker] = ticker
            if isempty(price_data)
                price_data = data
            else
                price_data = vcat(price_data, data)
            end
            success_count += 1
        end
    catch e
        println("Erro $ticker: $e")
    end
    
    if i % 5 == 0
        println("Progresso: $i/$(length(academic_tickers)) - Sucessos: $success_count")
    end
end

println("Download completo: $success_count sucessos")

# Calculate volatility with academic standards
function calculate_simple_volatility(data::DataFrame)
    vol_data = DataFrame(ticker=String[], date=Date[], volatility=Float64[])
    
    for gdf in groupby(data, :ticker)
        ticker = gdf.ticker[1]
        n = nrow(gdf)
        
        if n >= 300  # Minimum for rolling volatility
            log_returns = diff(log.(gdf.adjclose))
            log_returns = log_returns[.!isnan.(log_returns)]  # Remove NaN
            
            vol_window = 60
            for i in vol_window:length(log_returns)
                window_returns = log_returns[i-vol_window+1:i]
                vol = std(window_returns) * sqrt(252)
                
                push!(vol_data, (ticker, gdf.timestamp[i+1], vol))
            end
        end
    end
    
    return vol_data
end

println("Calculando volatilidade...")
volatility_data = calculate_simple_volatility(price_data)
println("Volatilidades calculadas: $(nrow(volatility_data))")

# Form portfolios monthly
function form_monthly_portfolios(vol_data::DataFrame, price_data::DataFrame)
    # Get month-end dates
    vol_data[!, :month] = Date.(year.(vol_data.date), month.(vol_data.date))
    monthly_vol = combine(groupby(vol_data, [:ticker, :month]), :volatility => last => :volatility)
    
    portfolio_data = DataFrame()
    
    for month_group in groupby(monthly_vol, :month)
        month = month_group.month[1]
        
        if nrow(month_group) >= 10  # Minimum stocks for portfolio formation
            # Sort by volatility and create portfolios
            sort!(month_group, :volatility)
            n_stocks = nrow(month_group)
            
            # Quintiles
            q1 = max(1, round(Int, n_stocks * 0.2))
            q2 = round(Int, n_stocks * 0.4)
            q3 = round(Int, n_stocks * 0.6)
            q4 = round(Int, n_stocks * 0.8)
            
            month_group[!, :portfolio] = [
                i <= q1 ? 1 : i <= q2 ? 2 : i <= q3 ? 3 : i <= q4 ? 4 : 5
                for i in 1:n_stocks
            ]
            
            month_group[!, :month_form] = month
            portfolio_data = vcat(portfolio_data, month_group[:, [:ticker, :month_form, :portfolio]])
        end
    end
    
    return portfolio_data
end

println("Formando portfólios mensais...")
portfolio_assignments = form_monthly_portfolios(volatility_data, price_data)
println("Portfólios formados: $(nrow(portfolio_assignments)) assignments")

# Calculate monthly returns
function calculate_monthly_returns(price_data::DataFrame, portfolio_data::DataFrame)
    # Get monthly prices
    price_monthly = combine(
        groupby(price_data, [:ticker, Date.(year.(price_data.timestamp), month.(price_data.timestamp))]),
        :adjclose => last => :price_end,
        :timestamp => last => :date_end
    )
    rename!(price_monthly, :timestamp_function => :month)
    
    # Calculate returns
    returns_data = DataFrame()
    
    for ticker_group in groupby(price_monthly, :ticker)
        ticker = ticker_group.ticker[1]
        sort!(ticker_group, :month)
        
        if nrow(ticker_group) >= 2
            for i in 2:nrow(ticker_group)
                ret = ticker_group.price_end[i] / ticker_group.price_end[i-1] - 1
                push!(returns_data, (
                    ticker = ticker,
                    month = ticker_group.month[i],
                    return = ret
                ))
            end
        end
    end
    
    # Merge with portfolio assignments
    portfolio_returns = leftjoin(returns_data, portfolio_data, 
                                on = [:ticker, :month => :month_form])
    
    # Calculate portfolio returns
    portfolio_monthly = combine(
        groupby(dropmissing(portfolio_returns, :portfolio), [:month, :portfolio]),
        :return => mean => :portfolio_return
    )
    
    return portfolio_monthly
end

println("Calculando retornos mensais...")
monthly_returns = calculate_monthly_returns(price_data, portfolio_assignments)
println("Retornos mensais calculados: $(nrow(monthly_returns))")

# Calculate Long-Short portfolio (P1 - P5)
ls_returns = DataFrame()
for month_group in groupby(monthly_returns, :month)
    month = month_group.month[1]
    
    p1_ret = month_group[month_group.portfolio .== 1, :portfolio_return]
    p5_ret = month_group[month_group.portfolio .== 5, :portfolio_return]
    
    if !isempty(p1_ret) && !isempty(p5_ret)
        ls_ret = p1_ret[1] - p5_ret[1]
        push!(ls_returns, (month = month, ls_return = ls_ret))
    end
end

println("Retornos Long-Short calculados: $(nrow(ls_returns))")

if nrow(ls_returns) > 0
    # Calculate statistics
    mean_ret = mean(ls_returns.ls_return)
    std_ret = std(ls_returns.ls_return)
    t_stat = mean_ret / (std_ret / sqrt(nrow(ls_returns)))
    
    println("\n=== RESULTADOS TESTE ACADÊMICO ===")
    println(@sprintf("Retorno médio mensal: %.4f (%.2f%%)", mean_ret, mean_ret * 100))
    println(@sprintf("Retorno anualizado: %.2f%%", mean_ret * 12 * 100))
    println(@sprintf("Volatilidade: %.2f%%", std_ret * sqrt(12) * 100))
    println(@sprintf("T-statistic: %.2f", t_stat))
    println(@sprintf("Meses: %d", nrow(ls_returns)))
    
    # Save results
    CSV.write("test_academic_results.csv", ls_returns)
    println("Resultados salvos em: test_academic_results.csv")
else
    println("ERRO: Nenhum retorno Long-Short calculado")
end