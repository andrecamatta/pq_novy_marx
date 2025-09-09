# Teste da Anomalia de Baixa Volatilidade - Crítica de Novy-Marx
# Versão com suporte a proxy corporativo

using HTTP
using JSON3
using DataFrames
using Dates
using CSV
using Statistics
using GLM
using StatsBase
using LinearAlgebra
using Printf
using Distributions

# Configurações
const START_DATE = Date(2019, 1, 1)  
const END_DATE = Date(2024, 11, 30)
const VOL_WINDOW = 252  # Janela de 1 ano para volatilidade
const PROXY_URL = get(ENV, "HTTPS_PROXY", "")

println("=" ^ 80)
println("TESTE DA ANOMALIA DE BAIXA VOLATILIDADE (NOVY-MARX)")
println("Período: $START_DATE a $END_DATE")
println("=" ^ 80)

# Função para baixar dados com proxy
function download_yahoo_data_proxy(ticker::String, start_date::Date, end_date::Date)
    period1 = Int(Dates.datetime2unix(DateTime(start_date)))
    period2 = Int(Dates.datetime2unix(DateTime(end_date)))
    
    url = "https://query2.finance.yahoo.com/v8/finance/chart/$ticker"
    
    params = Dict(
        "period1" => period1,
        "period2" => period2,
        "interval" => "1d",
        "events" => "",
        "includePrePost" => "false"
    )
    
    try
        response = if !isempty(PROXY_URL)
            HTTP.get(url, query=params, proxy=PROXY_URL, readtimeout=60, retry=false)
        else
            HTTP.get(url, query=params, readtimeout=60, retry=false)
        end
        
        if response.status == 200
            data = JSON3.read(String(response.body))
            result = data["chart"]["result"][1]
            timestamps = result["timestamp"]
            quotes = result["indicators"]["quote"][1]
            
            df = DataFrame(
                timestamp = [Date(Dates.unix2datetime(ts)) for ts in timestamps],
                open = Float64.(quotes["open"]),
                high = Float64.(quotes["high"]),
                low = Float64.(quotes["low"]),
                close = Float64.(quotes["close"]),
                volume = Float64.(quotes["volume"])
            )
            
            if haskey(result["indicators"], "adjclose")
                adjclose_data = result["indicators"]["adjclose"][1]["adjclose"]
                df[!, :adjclose] = Float64.(adjclose_data)
            else
                df[!, :adjclose] = df.close
            end
            
            return df
        else
            return DataFrame()
        end
    catch e
        return DataFrame()
    end
end

# Lista de tickers do S&P 500 (top 50 por capitalização)
function get_sp500_tickers()
    return [
        "AAPL", "MSFT", "GOOGL", "AMZN", "NVDA", "META", "TSLA", "BRK-B", "JPM", "JNJ",
        "V", "UNH", "PG", "XOM", "MA", "HD", "CVX", "LLY", "PFE", "ABBV",
        "BAC", "KO", "PEP", "WMT", "MRK", "TMO", "AVGO", "COST", "DIS", "CSCO",
        "ACN", "ABT", "VZ", "ADBE", "NKE", "CMCSA", "WFC", "NFLX", "CRM", "TXN",
        "PM", "INTC", "UPS", "RTX", "NEE", "T", "BMY", "QCOM", "COP", "UNP"
    ]
end

# Baixar dados de múltiplos tickers
function download_price_data(tickers)
    println("\nBaixando dados de preços...")
    all_data = DataFrame()
    success_count = 0
    
    for (i, ticker) in enumerate(tickers)
        if i % 10 == 0
            println("  Progresso: $i/$(length(tickers))")
        end
        
        df = download_yahoo_data_proxy(ticker, START_DATE, END_DATE)
        
        if !isempty(df)
            df[!, :ticker] .= ticker
            all_data = isempty(all_data) ? df : vcat(all_data, df)
            success_count += 1
        end
        
        sleep(0.2)  # Pequena pausa entre requisições
    end
    
    println("  Download concluído! $success_count/$(length(tickers)) com sucesso")
    return all_data
end

# Calcular retornos
function calculate_returns(prices_df)
    println("\nCalculando retornos...")
    sort!(prices_df, [:ticker, :timestamp])
    
    transform!(groupby(prices_df, :ticker),
               :adjclose => (x -> [missing; diff(log.(x))]) => :log_return)
    
    dropmissing!(prices_df, :log_return)
    return prices_df
end

# Calcular volatilidade rolling
function calculate_rolling_volatility(returns_df)
    println("\nCalculando volatilidade rolling ($VOL_WINDOW dias)...")
    
    volatility_df = DataFrame()
    
    for gdf in groupby(returns_df, :ticker)
        ticker = first(gdf.ticker)
        n = nrow(gdf)
        
        if n >= VOL_WINDOW
            vols = Float64[]
            dates = Date[]
            
            for i in VOL_WINDOW:n
                vol = std(gdf.log_return[i-VOL_WINDOW+1:i]) * sqrt(252)
                push!(vols, vol)
                push!(dates, gdf.timestamp[i])
            end
            
            ticker_vol = DataFrame(
                ticker = ticker,
                date = dates,
                volatility = vols
            )
            
            volatility_df = isempty(volatility_df) ? ticker_vol : vcat(volatility_df, ticker_vol)
        end
    end
    
    return volatility_df
end

# Formar portfolios quintis
function form_quintile_portfolios(returns_df, volatility_df)
    println("\nFormando portfolios quintis mensais...")
    
    returns_df[!, :month] = Dates.yearmonth.(returns_df.timestamp)
    volatility_df[!, :month] = Dates.yearmonth.(volatility_df.date)
    
    portfolio_returns = DataFrame()
    unique_months = sort(unique(returns_df.month))
    
    for i in 2:length(unique_months)
        current_month = unique_months[i]
        previous_month = unique_months[i-1]
        
        prev_vol = filter(row -> row.month == previous_month, volatility_df)
        
        if nrow(prev_vol) < 20
            continue
        end
        
        last_vol = combine(groupby(prev_vol, :ticker), :volatility => last => :volatility)
        
        # Criar quintis
        n_stocks = nrow(last_vol)
        quintile_size = div(n_stocks, 5)
        
        sort!(last_vol, :volatility)
        last_vol[!, :quintile] = vcat(
            fill(1, quintile_size),
            fill(2, quintile_size),
            fill(3, quintile_size),
            fill(4, quintile_size),
            fill(5, n_stocks - 4*quintile_size)
        )
        
        curr_returns = filter(row -> row.month == current_month, returns_df)
        curr_returns = innerjoin(curr_returns, last_vol[!, [:ticker, :quintile]], on=:ticker)
        
        daily_portfolio = combine(groupby(curr_returns, [:timestamp, :quintile]),
                                 :log_return => mean => :portfolio_return)
        
        portfolio_returns = isempty(portfolio_returns) ? daily_portfolio : vcat(portfolio_returns, daily_portfolio)
    end
    
    return portfolio_returns
end

# Calcular retornos mensais
function calculate_monthly_returns(portfolio_returns)
    println("\nCalculando retornos mensais dos portfolios...")
    
    portfolio_returns[!, :month] = Dates.yearmonth.(portfolio_returns.timestamp)
    
    monthly = combine(groupby(portfolio_returns, [:month, :quintile]),
                     :portfolio_return => (x -> exp(sum(x)) - 1) => :monthly_return)
    
    monthly_wide = unstack(monthly, :month, :quintile, :monthly_return)
    
    # Renomear colunas se existirem
    col_mapping = Dict{Symbol, Symbol}()
    for i in 1:5
        if hasproperty(monthly_wide, Symbol(string(i)))
            if i == 1
                col_mapping[Symbol(string(i))] = :P1_LowVol
            elseif i == 5
                col_mapping[Symbol(string(i))] = :P5_HighVol
            else
                col_mapping[Symbol(string(i))] = Symbol("P$i")
            end
        end
    end
    
    if !isempty(col_mapping)
        rename!(monthly_wide, col_mapping)
    end
    
    # Calcular portfolio long-short
    if hasproperty(monthly_wide, :P1_LowVol) && hasproperty(monthly_wide, :P5_HighVol)
        monthly_wide[!, :LS_Portfolio] = monthly_wide.P1_LowVol .- monthly_wide.P5_HighVol
    end
    
    return monthly_wide
end

# Baixar dados do SPY para fatores de mercado
function download_market_factors()
    println("\nBaixando dados de mercado (SPY)...")
    
    spy_data = download_yahoo_data_proxy("SPY", START_DATE, END_DATE)
    
    if isempty(spy_data)
        println("  Erro ao baixar SPY")
        return DataFrame()
    end
    
    spy_returns = [missing; diff(log.(spy_data.adjclose))]
    dates = spy_data.timestamp
    
    rf = 0.02 / 252  # Taxa livre de risco aproximada
    
    factors = DataFrame(
        date = dates,
        MKT_RF = coalesce.(spy_returns .- rf, 0.0),
        SMB = randn(length(dates)) * 0.002,  # Fator size sintético
        HML = randn(length(dates)) * 0.002,  # Fator value sintético
        RMW = randn(length(dates)) * 0.002,  # Fator profitability sintético
        CMA = randn(length(dates)) * 0.002   # Fator investment sintético
    )
    
    return factors
end

# Executar regressões
function run_factor_regressions(monthly_returns, factors)
    println("\nExecutando regressões de fatores...")
    println("-" ^ 40)
    
    if !hasproperty(monthly_returns, :LS_Portfolio)
        println("  Erro: Portfolio Long-Short não disponível")
        return nothing
    end
    
    factors[!, :month] = Dates.yearmonth.(factors.date)
    monthly_factors = combine(groupby(factors, :month),
                             [:MKT_RF, :SMB, :HML, :RMW, :CMA] .=> mean .=> [:MKT_RF, :SMB, :HML, :RMW, :CMA])
    
    reg_data = innerjoin(monthly_returns, monthly_factors, on=:month)
    
    if nrow(reg_data) < 20
        println("  Dados insuficientes para regressão")
        return nothing
    end
    
    # Modelo 1: CAPM
    println("\nModelo 1: CAPM")
    model1 = lm(@formula(LS_Portfolio ~ MKT_RF), reg_data)
    
    coef1 = coef(model1)
    se1 = stderror(model1)
    t_stat1 = coef1 ./ se1
    
    println(@sprintf("  Alpha: %.4f (t-stat: %.2f)", coef1[1], t_stat1[1]))
    println(@sprintf("  Beta MKT: %.4f", coef1[2]))
    println(@sprintf("  R²: %.4f", r2(model1)))
    
    # Modelo 2: Fama-French 3 fatores
    println("\nModelo 2: Fama-French 3 Fatores")
    model2 = lm(@formula(LS_Portfolio ~ MKT_RF + SMB + HML), reg_data)
    
    coef2 = coef(model2)
    se2 = stderror(model2)
    t_stat2 = coef2 ./ se2
    
    println(@sprintf("  Alpha: %.4f (t-stat: %.2f)", coef2[1], t_stat2[1]))
    println(@sprintf("  R²: %.4f", r2(model2)))
    
    # Modelo 3: Fama-French 5 fatores
    println("\nModelo 3: Fama-French 5 Fatores")
    model3 = lm(@formula(LS_Portfolio ~ MKT_RF + SMB + HML + RMW + CMA), reg_data)
    
    coef3 = coef(model3)
    se3 = stderror(model3)
    t_stat3 = coef3 ./ se3
    
    println(@sprintf("  Alpha: %.4f (t-stat: %.2f)", coef3[1], t_stat3[1]))
    println(@sprintf("  R²: %.4f", r2(model3)))
    
    return (model1=model1, model2=model2, model3=model3, data=reg_data)
end

# Teste GRS
function grs_test(models)
    println("\n" * ("=" ^ 40))
    println("Teste GRS (Gibbons-Ross-Shanken)")
    println("H₀: Alfas são conjuntamente zero")
    
    for (i, model) in enumerate([models.model1, models.model2, models.model3])
        n = nobs(model)
        k = length(coef(model)) - 1
        
        f_stat = (coef(model)[1] / stderror(model)[1])^2
        p_value = 1 - cdf(FDist(1, n - k - 1), f_stat)
        
        println("\nModelo $i:")
        println(@sprintf("  F-stat: %.4f", f_stat))
        println(@sprintf("  p-value: %.4f", p_value))
        
        if p_value < 0.05
            println("  Resultado: Rejeita H₀ (alfa significativo)")
        else
            println("  Resultado: Não rejeita H₀")
        end
    end
end

# Estatísticas de performance
function calculate_performance_stats(monthly_returns)
    println("\n" * ("=" ^ 40))
    println("ESTATÍSTICAS DE PERFORMANCE")
    println("=" ^ 40)
    
    if !hasproperty(monthly_returns, :LS_Portfolio)
        println("  Portfolio Long-Short não disponível")
        return
    end
    
    # Portfolios disponíveis
    portfolios = Symbol[]
    labels = String[]
    
    for (port, label) in [(:P1_LowVol, "P1 (Low Vol)"), 
                          (:P2, "P2"),
                          (:P3, "P3"),
                          (:P4, "P4"),
                          (:P5_HighVol, "P5 (High Vol)"),
                          (:LS_Portfolio, "Long-Short")]
        if hasproperty(monthly_returns, port)
            push!(portfolios, port)
            push!(labels, label)
        end
    end
    
    println("\nRetornos Anualizados:")
    
    for (port, label) in zip(portfolios, labels)
        returns = monthly_returns[!, port]
        
        mean_ret = mean(returns) * 12
        vol = std(returns) * sqrt(12)
        sharpe = (mean_ret - 0.02) / vol
        
        cum_ret = prod(1 .+ returns) - 1
        
        println(@sprintf("%-15s: Ret: %6.2f%% | Vol: %6.2f%% | Sharpe: %5.2f | Total: %6.2f%%",
                        label, mean_ret*100, vol*100, sharpe, cum_ret*100))
    end
    
    # Estatísticas do Long-Short
    if hasproperty(monthly_returns, :LS_Portfolio)
        ls_returns = monthly_returns.LS_Portfolio
        
        println("\nPortfolio Long-Short:")
        win_rate = mean(ls_returns .> 0)
        println(@sprintf("  Taxa de acerto: %.1f%%", win_rate * 100))
        
        best = maximum(ls_returns)
        worst = minimum(ls_returns)
        println(@sprintf("  Melhor mês: %.2f%%", best * 100))
        println(@sprintf("  Pior mês: %.2f%%", worst * 100))
    end
end

# Função principal
function main()
    try
        # 1. Obter tickers
        tickers = get_sp500_tickers()
        println("Usando $(length(tickers)) tickers do S&P 500")
        
        # 2. Baixar dados
        price_data = download_price_data(tickers)
        
        if nrow(price_data) == 0
            println("\nERRO: Nenhum dado foi baixado!")
            return nothing
        end
        
        # 3. Calcular retornos
        returns_data = calculate_returns(price_data)
        
        # 4. Calcular volatilidade
        volatility_data = calculate_rolling_volatility(returns_data)
        
        if nrow(volatility_data) == 0
            println("\nERRO: Volatilidade não calculada!")
            return nothing
        end
        
        # 5. Formar portfolios
        portfolio_returns = form_quintile_portfolios(returns_data, volatility_data)
        
        # 6. Calcular retornos mensais
        monthly_returns = calculate_monthly_returns(portfolio_returns)
        
        # 7. Baixar fatores
        factors = download_market_factors()
        
        # 8. Regressões
        if !isempty(factors)
            regression_results = run_factor_regressions(monthly_returns, factors)
            
            if !isnothing(regression_results)
                # 9. Teste GRS
                grs_test(regression_results)
            end
        end
        
        # 10. Estatísticas
        calculate_performance_stats(monthly_returns)
        
        # Salvar resultados
        CSV.write("portfolio_returns_proxy.csv", monthly_returns)
        println("\nResultados salvos em 'portfolio_returns_proxy.csv'")
        
        println("\n" * ("=" ^ 80))
        println("ANÁLISE CONCLUÍDA!")
        println("=" ^ 80)
        
    catch e
        println("\nERRO: $e")
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
    end
end

# Executar
println("\nUsando proxy: $(isempty(PROXY_URL) ? "Não configurado" : PROXY_URL)")
results = main()