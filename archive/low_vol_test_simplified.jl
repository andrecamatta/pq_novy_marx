# Teste Simplificado da Anomalia de Baixa Volatilidade - Crítica de Novy-Marx
# Versão com menos tickers para teste rápido

using YFinance
using DataFrames
using Dates
using Statistics
using CSV
using HTTP
using GLM
using StatsBase
using LinearAlgebra
using Printf
using Distributions

# Configurações
const START_DATE = Date(2018, 1, 1)  # Período menor para teste
const END_DATE = Date(2023, 12, 31)
const VOL_WINDOW = 60  # Janela menor para teste (3 meses)

println("=" ^ 80)
println("TESTE SIMPLIFICADO - ANOMALIA DE BAIXA VOLATILIDADE")
println("Período: $START_DATE a $END_DATE")
println("=" ^ 80)

# Lista reduzida de tickers para teste
function get_test_tickers()
    # Usar apenas 20 tickers grandes e líquidos
    return [
        "AAPL", "MSFT", "GOOGL", "AMZN", "NVDA", 
        "META", "TSLA", "JPM", "JNJ", "V",
        "UNH", "PG", "XOM", "MA", "HD",
        "CVX", "PFE", "BAC", "KO", "WMT"
    ]
end

# Função simplificada para baixar dados
function download_price_data(tickers)
    println("\nBaixando dados de preços ($(length(tickers)) tickers)...")
    
    all_data = DataFrame()
    success_count = 0
    
    for (i, ticker) in enumerate(tickers)
        print("  $ticker...")
        try
            data = get_prices(ticker, startdt=START_DATE, enddt=END_DATE)
            if !isempty(data)
                data[!, :ticker] = ticker
                all_data = isempty(all_data) ? data : vcat(all_data, data)
                success_count += 1
                println(" OK")
            else
                println(" vazio")
            end
        catch e
            println(" erro")
        end
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

# Calcular volatilidade
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
            
            ticker_vol = DataFrame(ticker=ticker, date=dates, volatility=vols)
            volatility_df = isempty(volatility_df) ? ticker_vol : vcat(volatility_df, ticker_vol)
        end
    end
    
    return volatility_df
end

# Formar portfolios
function form_portfolios(returns_df, volatility_df)
    println("\nFormando portfolios quintis...")
    
    returns_df[!, :month] = yearmonth.(returns_df.timestamp)
    volatility_df[!, :month] = yearmonth.(volatility_df.date)
    
    portfolio_returns = DataFrame()
    unique_months = sort(unique(returns_df.month))
    
    for i in 2:length(unique_months)
        current_month = unique_months[i]
        previous_month = unique_months[i-1]
        
        prev_vol = filter(row -> row.month == previous_month, volatility_df)
        
        if nrow(prev_vol) < 10
            continue
        end
        
        last_vol = combine(groupby(prev_vol, :ticker), :volatility => last => :volatility)
        
        # Criar apenas 3 grupos para simplificar (baixa, média, alta volatilidade)
        n_stocks = nrow(last_vol)
        tercil_size = div(n_stocks, 3)
        
        sort!(last_vol, :volatility)
        last_vol[!, :group] = vcat(
            fill(1, tercil_size),
            fill(2, tercil_size),
            fill(3, n_stocks - 2*tercil_size)
        )
        
        curr_returns = filter(row -> row.month == current_month, returns_df)
        curr_returns = innerjoin(curr_returns, last_vol[!, [:ticker, :group]], on=:ticker)
        
        daily_portfolio = combine(groupby(curr_returns, [:timestamp, :group]),
                                 :log_return => mean => :portfolio_return)
        
        portfolio_returns = isempty(portfolio_returns) ? daily_portfolio : vcat(portfolio_returns, daily_portfolio)
    end
    
    return portfolio_returns
end

# Calcular retornos mensais
function calculate_monthly_returns(portfolio_returns)
    println("\nCalculando retornos mensais...")
    
    portfolio_returns[!, :month] = yearmonth.(portfolio_returns.timestamp)
    
    monthly = combine(groupby(portfolio_returns, [:month, :group]),
                     :portfolio_return => (x -> exp(sum(x)) - 1) => :monthly_return)
    
    monthly_wide = unstack(monthly, :month, :group, :monthly_return)
    
    # Garantir que temos as colunas necessárias
    if !hasproperty(monthly_wide, Symbol("1"))
        monthly_wide[!, Symbol("1")] = zeros(nrow(monthly_wide))
    end
    if !hasproperty(monthly_wide, Symbol("3"))
        monthly_wide[!, Symbol("3")] = zeros(nrow(monthly_wide))
    end
    
    rename!(monthly_wide, 
            Symbol("1") => :P1_LowVol,
            Symbol("3") => :P3_HighVol)
    
    monthly_wide[!, :LS_Portfolio] = monthly_wide.P1_LowVol .- monthly_wide.P3_HighVol
    
    return monthly_wide
end

# Criar fatores sintéticos simples
function create_simple_factors(start_date, end_date)
    println("\nCriando fatores de mercado...")
    
    spy_data = get_prices("SPY", startdt=start_date, enddt=end_date)
    spy_returns = diff(log.(spy_data.adjclose))
    dates = spy_data.timestamp[2:end]
    
    rf = 0.02 / 252
    
    factors = DataFrame(
        date = dates,
        MKT_RF = spy_returns .- rf,
        SMB = randn(length(dates)) * 0.002,
        HML = randn(length(dates)) * 0.002
    )
    
    return factors
end

# Regressões simplificadas
function run_regressions(monthly_returns, factors)
    println("\nExecutando regressões...")
    println("-" * 40)
    
    factors[!, :month] = yearmonth.(factors.date)
    monthly_factors = combine(groupby(factors, :month),
                             [:MKT_RF, :SMB, :HML] .=> mean .=> [:MKT_RF, :SMB, :HML])
    
    reg_data = innerjoin(monthly_returns, monthly_factors, on=:month)
    
    # Verificar se temos dados suficientes
    if nrow(reg_data) < 10
        println("  Dados insuficientes para regressão ($(nrow(reg_data)) observações)")
        return nothing
    end
    
    # Modelo CAPM
    println("\nModelo CAPM:")
    model1 = lm(@formula(LS_Portfolio ~ MKT_RF), reg_data)
    
    coef1 = coef(model1)
    se1 = stderror(model1)
    t_stat1 = coef1 ./ se1
    
    println(@sprintf("  Alpha: %.4f (t-stat: %.2f)", coef1[1], t_stat1[1]))
    println(@sprintf("  Beta: %.4f", coef1[2]))
    println(@sprintf("  R²: %.4f", r2(model1)))
    
    # Modelo Fama-French 3 fatores
    println("\nModelo FF3:")
    model2 = lm(@formula(LS_Portfolio ~ MKT_RF + SMB + HML), reg_data)
    
    coef2 = coef(model2)
    se2 = stderror(model2)
    t_stat2 = coef2 ./ se2
    
    println(@sprintf("  Alpha: %.4f (t-stat: %.2f)", coef2[1], t_stat2[1]))
    println(@sprintf("  R²: %.4f", r2(model2)))
    
    return (model1=model1, model2=model2, data=reg_data)
end

# Performance stats
function calculate_stats(monthly_returns)
    println("\n" * "=" * 40)
    println("ESTATÍSTICAS DE PERFORMANCE")
    println("=" * 40)
    
    ls_returns = monthly_returns.LS_Portfolio
    
    # Retorno e volatilidade anualizados
    mean_ret = mean(ls_returns) * 12
    vol = std(ls_returns) * sqrt(12)
    sharpe = (mean_ret - 0.02) / vol
    
    println(@sprintf("Portfolio Long-Short:"))
    println(@sprintf("  Retorno anual: %.2f%%", mean_ret * 100))
    println(@sprintf("  Volatilidade anual: %.2f%%", vol * 100))
    println(@sprintf("  Sharpe Ratio: %.2f", sharpe))
    
    # Retorno cumulativo
    cum_ret = prod(1 .+ ls_returns) - 1
    println(@sprintf("  Retorno total período: %.2f%%", cum_ret * 100))
    
    # Taxa de acerto
    win_rate = mean(ls_returns .> 0)
    println(@sprintf("  Taxa de acerto: %.1f%%", win_rate * 100))
end

# Main
function main()
    try
        tickers = get_test_tickers()
        
        price_data = download_price_data(tickers)
        
        if nrow(price_data) == 0
            println("\nERRO: Nenhum dado foi baixado!")
            return nothing
        end
        
        returns_data = calculate_returns(price_data)
        volatility_data = calculate_rolling_volatility(returns_data)
        
        if nrow(volatility_data) == 0
            println("\nERRO: Não foi possível calcular volatilidade!")
            return nothing
        end
        
        portfolio_returns = form_portfolios(returns_data, volatility_data)
        
        if nrow(portfolio_returns) == 0
            println("\nERRO: Não foi possível formar portfolios!")
            return nothing
        end
        
        monthly_returns = calculate_monthly_returns(portfolio_returns)
        
        factors = create_simple_factors(START_DATE, END_DATE)
        
        regression_results = run_regressions(monthly_returns, factors)
        
        calculate_stats(monthly_returns)
        
        # Salvar resultados
        CSV.write("test_results.csv", monthly_returns)
        println("\nResultados salvos em 'test_results.csv'")
        
        println("\n" * "=" * 80)
        println("TESTE CONCLUÍDO!")
        println("=" * 80)
        
        return regression_results
        
    catch e
        println("\nERRO: $e")
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
    end
end

# Executar
println("\nIniciando análise simplificada...")
results = main()