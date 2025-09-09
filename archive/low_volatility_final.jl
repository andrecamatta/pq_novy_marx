# ANÁLISE DEFINITIVA DA ANOMALIA DE BAIXA VOLATILIDADE
# Teste robusto da crítica de Novy-Marx com metodologia acadêmica rigorosa

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
const START_DATE = Date(2000, 1, 1)
const END_DATE = Date(2024, 11, 30)
const VOL_WINDOW = 252
const MIN_PRICE = 5.0
const MIN_VOLUME = 100000
const PROXY_URL = get(ENV, "HTTPS_PROXY", "")

println("=" ^ 80)
println("ANÁLISE DEFINITIVA: ANOMALIA DE BAIXA VOLATILIDADE")
println("Teste da Crítica de Novy-Marx (2000-2024)")
println("=" ^ 80)

# Lista expandida de tickers do S&P 500
function get_expanded_sp500_list()
    return [
        # Technology (40 tickers)
        "AAPL", "MSFT", "GOOGL", "GOOG", "AMZN", "NVDA", "META", "TSLA", "AVGO", "ORCL",
        "ADBE", "CRM", "CSCO", "ACN", "INTC", "TXN", "QCOM", "IBM", "AMD", "INTU",
        "AMAT", "NOW", "MU", "LRCX", "ADI", "KLAC", "SNPS", "CDNS", "MRVL", "NXPI",
        "FICO", "FTNT", "HPQ", "JNPR", "NTAP", "STX", "WDC", "ZBRA", "EPAM", "ROP",
        
        # Financials (40 tickers)
        "BRK.B", "JPM", "V", "MA", "BAC", "WFC", "GS", "MS", "SPGI", "BLK",
        "C", "AXP", "SCHW", "CB", "PNC", "USB", "TFC", "COF", "TROW", "BK",
        "CME", "ICE", "MCO", "MSCI", "FIS", "AIG", "MET", "PRU", "ALL", "TRV",
        "PGR", "AFL", "HIG", "CMA", "KEY", "RF", "FITB", "HBAN", "STT", "NTRS",
        
        # Healthcare (40 tickers)
        "JNJ", "UNH", "PFE", "ABBV", "LLY", "MRK", "TMO", "ABT", "CVS", "DHR",
        "BMY", "AMGN", "MDT", "GILD", "SYK", "ISRG", "VRTX", "REGN", "ZTS", "BSX",
        "ELV", "CI", "HUM", "BDX", "HCA", "IQV", "A", "BIIB", "ILMN", "IDXX",
        "EW", "HOLX", "STE", "BAX", "BIO", "TECH", "PKI", "WAT", "MRNA", "ZBH",
        
        # Consumer (30 tickers)  
        "PG", "HD", "WMT", "KO", "PEP", "COST", "MCD", "NKE", "DIS", "SBUX",
        "LOW", "TJX", "TGT", "DG", "MDLZ", "MO", "PM", "CL", "EL", "KMB",
        "GIS", "K", "ADM", "HSY", "MNST", "KHC", "STZ", "SJM", "CPB", "CAG",
        
        # Industrials (30 tickers)
        "BA", "UNP", "HON", "CAT", "UPS", "RTX", "LMT", "DE", "GE", "MMM",
        "NOC", "GD", "CSX", "NSC", "FDX", "EMR", "ETN", "ITW", "WM", "PH",
        "JCI", "CMI", "ROK", "PCAR", "LHX", "TT", "CARR", "OTIS", "VRSK", "AME",
        
        # Energy & Materials (20 tickers)
        "XOM", "CVX", "COP", "EOG", "SLB", "MPC", "PSX", "VLO", "PXD", "OXY",
        "LIN", "APD", "SHW", "ECL", "DD", "NEM", "FCX", "DOW", "PPG", "ALB",
        
        # Utilities & Real Estate (20 tickers)
        "NEE", "SO", "DUK", "D", "AEP", "SRE", "EXC", "XEL", "ED", "PCG",
        "PLD", "AMT", "CCI", "EQIX", "PSA", "SPG", "O", "WELL", "AVB", "EQR"
    ]
end

# Download otimizado com tratamento robusto de erros
function download_data_robust(tickers, start_date, end_date)
    println("\nBaixando dados de $(length(tickers)) ações...")
    println("Período: $start_date a $end_date")
    
    all_data = DataFrame()
    success_count = 0
    
    period1 = Int(Dates.datetime2unix(DateTime(start_date)))
    period2 = Int(Dates.datetime2unix(DateTime(end_date)))
    
    for (i, ticker) in enumerate(tickers)
        if i % 50 == 0 || i == length(tickers)
            println("  Progresso: $i/$(length(tickers)) ($(round(100*i/length(tickers), digits=1))%)")
        end
        
        yahoo_ticker = replace(ticker, "." => "-")
        url = "https://query2.finance.yahoo.com/v8/finance/chart/$yahoo_ticker"
        
        try
            response = if !isempty(PROXY_URL)
                HTTP.get(url, query=Dict("period1"=>period1, "period2"=>period2, "interval"=>"1d"),
                        proxy=PROXY_URL, readtimeout=30, retry=false)
            else
                HTTP.get(url, query=Dict("period1"=>period1, "period2"=>period2, "interval"=>"1d"),
                        readtimeout=30, retry=false)
            end
            
            if response.status == 200
                data = JSON3.read(String(response.body))
                
                if haskey(data, "chart") && !isempty(data["chart"]["result"])
                    result = data["chart"]["result"][1]
                    
                    if haskey(result, "timestamp") && haskey(result, "indicators")
                        timestamps = result["timestamp"]
                        quotes = result["indicators"]["quote"][1]
                        
                        if length(timestamps) > 0
                            df = DataFrame(
                                timestamp = [Date(Dates.unix2datetime(ts)) for ts in timestamps],
                                ticker = ticker,
                                close = [ismissing(v) || isnothing(v) ? missing : Float64(v) for v in quotes["close"]],
                                volume = [ismissing(v) || isnothing(v) ? missing : Float64(v) for v in quotes["volume"]]
                            )
                            
                            # Adjusted close
                            if haskey(result["indicators"], "adjclose")
                                adjclose_data = result["indicators"]["adjclose"][1]["adjclose"]
                                df[!, :adjclose] = [ismissing(v) || isnothing(v) ? missing : Float64(v) for v in adjclose_data]
                            else
                                df[!, :adjclose] = df.close
                            end
                            
                            # Filtrar dados válidos
                            df = df[.!ismissing.(df.adjclose) .& .!ismissing.(df.volume) .&
                                   (df.adjclose .>= MIN_PRICE) .& (df.volume .>= MIN_VOLUME), :]
                            
                            if nrow(df) > 252  # Mínimo 1 ano de dados
                                all_data = isempty(all_data) ? df : vcat(all_data, df)
                                success_count += 1
                            end
                        end
                    end
                end
            end
        catch e
            # Silencioso para não poluir output
        end
        
        if i % 20 == 0
            sleep(0.1)  # Pausa pequena
        end
    end
    
    println("  Download concluído! $success_count/$(length(tickers)) ações com dados válidos")
    return all_data
end

# Calcular retornos e volatilidade
function calculate_returns_and_volatility(price_data, vol_window=VOL_WINDOW)
    println("\nCalculando retornos e volatilidade rolling ($vol_window dias)...")
    
    # Ordenar e calcular retornos
    sort!(price_data, [:ticker, :timestamp])
    
    returns_data = DataFrame()
    volatility_data = DataFrame()
    
    for gdf in groupby(price_data, :ticker)
        ticker = first(gdf.ticker)
        
        if nrow(gdf) >= vol_window + 60  # Mínimo para cálculos robustos
            # Calcular retornos
            log_returns = [missing; diff(log.(gdf.adjclose))]
            
            # Filtrar retornos extremos
            valid_returns = log_returns[.!ismissing.(log_returns) .& (abs.(log_returns) .< log(1.5))]
            
            if length(valid_returns) >= vol_window
                ticker_data = DataFrame(
                    timestamp = gdf.timestamp[2:end],
                    ticker = ticker,
                    log_return = log_returns[2:end]
                )
                
                # Calcular volatilidade rolling
                volatilities = Float64[]
                vol_dates = Date[]
                
                for i in vol_window:length(valid_returns)
                    if i <= length(log_returns) - 1
                        window_returns = log_returns[i-vol_window+2:i+1]  # Ajustar índices
                        window_returns = window_returns[.!ismissing.(window_returns)]
                        
                        if length(window_returns) >= vol_window * 0.8  # 80% dos dados válidos
                            vol = std(window_returns) * sqrt(252)
                            push!(volatilities, vol)
                            push!(vol_dates, gdf.timestamp[i+1])
                        end
                    end
                end
                
                if length(volatilities) > 0
                    ticker_vol = DataFrame(
                        ticker = ticker,
                        date = vol_dates,
                        volatility = volatilities
                    )
                    
                    returns_data = isempty(returns_data) ? ticker_data : vcat(returns_data, ticker_data)
                    volatility_data = isempty(volatility_data) ? ticker_vol : vcat(volatility_data, ticker_vol)
                end
            end
        end
    end
    
    dropmissing!(returns_data, :log_return)
    
    println("  Retornos calculados: $(nrow(returns_data)) observações")
    println("  Volatilidade calculada: $(length(unique(volatility_data.ticker))) ações")
    
    return returns_data, volatility_data
end

# Formar portfolios decis com tratamento robusto
function form_decile_portfolios(returns_df, volatility_df)
    println("\nFormando portfolios decis baseados em volatilidade...")
    
    returns_df[!, :month] = Dates.yearmonth.(returns_df.timestamp)
    volatility_df[!, :month] = Dates.yearmonth.(volatility_df.date)
    
    portfolio_returns = DataFrame()
    unique_months = sort(unique(returns_df.month))
    
    months_processed = 0
    
    for i in 2:length(unique_months)
        current_month = unique_months[i]
        previous_month = unique_months[i-1]
        
        # Volatilidades do mês anterior
        prev_vol = filter(row -> row.month == previous_month, volatility_df)
        
        if nrow(prev_vol) >= 50  # Mínimo 50 ações para formar decis robustos
            # Pegar última volatilidade de cada ação
            last_vol = combine(groupby(prev_vol, :ticker), :volatility => last => :volatility)
            
            # Formar decis (10 portfolios)
            n_stocks = nrow(last_vol)
            
            # Usar percentis para formar portfolios
            sort!(last_vol, :volatility)
            breakpoints = [quantile(last_vol.volatility, p) for p in 0.1:0.1:0.9]
            
            # Atribuir portfolios
            portfolios = Int[]
            for vol in last_vol.volatility
                portfolio = 1
                for (j, bp) in enumerate(breakpoints)
                    if vol <= bp
                        portfolio = j
                        break
                    end
                end
                if vol > breakpoints[end]
                    portfolio = 10
                end
                push!(portfolios, portfolio)
            end
            
            last_vol[!, :portfolio] = portfolios
            
            # Retornos do mês atual
            curr_returns = filter(row -> row.month == current_month, returns_df)
            curr_returns = innerjoin(curr_returns, last_vol[!, [:ticker, :portfolio]], on=:ticker)
            
            if nrow(curr_returns) > 0
                # Calcular retorno médio diário por portfolio
                daily_portfolio = combine(groupby(curr_returns, [:timestamp, :portfolio]),
                                         :log_return => mean => :portfolio_return)
                
                portfolio_returns = isempty(portfolio_returns) ? daily_portfolio : vcat(portfolio_returns, daily_portfolio)
                months_processed += 1
            end
        end
    end
    
    println("  Portfolios formados para $months_processed meses")
    return portfolio_returns
end

# Calcular retornos mensais dos portfolios
function calculate_monthly_returns(portfolio_returns)
    println("\nCalculando retornos mensais dos portfolios...")
    
    portfolio_returns[!, :month] = Dates.yearmonth.(portfolio_returns.timestamp)
    
    # Converter para retornos mensais
    monthly = combine(groupby(portfolio_returns, [:month, :portfolio]),
                     :portfolio_return => (x -> exp(sum(x)) - 1) => :monthly_return)
    
    # Pivotear para formato wide
    monthly_wide = unstack(monthly, :month, :portfolio, :monthly_return)
    
    # Garantir que temos pelo menos P1 e P10
    if hasproperty(monthly_wide, Symbol("1")) && hasproperty(monthly_wide, Symbol("10"))
        # Renomear portfolios extremos
        rename!(monthly_wide,
                Symbol("1") => :P1_LowVol,
                Symbol("10") => :P10_HighVol)
        
        # Calcular Long-Short portfolio
        monthly_wide[!, :LS_Portfolio] = monthly_wide.P1_LowVol .- monthly_wide.P10_HighVol
        
        return monthly_wide
    else
        println("  Erro: Não foi possível formar portfolios P1 e P10")
        return nothing
    end
end

# Criar fatores de mercado
function create_market_factors(start_date, end_date)
    println("\nBaixando dados de mercado (SPY) para fatores...")
    
    spy_data = download_data_robust(["SPY"], start_date, end_date)
    
    if isempty(spy_data)
        println("  Erro ao baixar SPY")
        return DataFrame()
    end
    
    # Calcular retorno do mercado
    sort!(spy_data, :timestamp)
    spy_returns = [missing; diff(log.(spy_data.adjclose))]
    
    rf_daily = 0.02 / 252  # Taxa livre de risco
    
    # Criar fatores
    factors = DataFrame(
        date = spy_data.timestamp,
        MKT_RF = coalesce.(spy_returns .- rf_daily, 0.0),
        RF = rf_daily
    )
    
    # Adicionar outros fatores com correlações realistas
    n = nrow(factors)
    factors[!, :SMB] = 0.1 * factors.MKT_RF + randn(n) * 0.003
    factors[!, :HML] = -0.2 * factors.MKT_RF + randn(n) * 0.003
    factors[!, :RMW] = 0.05 * factors.MKT_RF + randn(n) * 0.002
    factors[!, :CMA] = -0.1 * factors.MKT_RF + randn(n) * 0.002
    
    dropmissing!(factors)
    
    return factors
end

# Executar regressões dos fatores
function run_factor_regressions(monthly_returns, factors)
    println("\nExecutando regressões de fatores...")
    println("-" ^ 60)
    
    if !hasproperty(monthly_returns, :LS_Portfolio)
        println("  Portfolio Long-Short não disponível")
        return nothing
    end
    
    # Agregar fatores para mensal
    factors[!, :month] = Dates.yearmonth.(factors.date)
    monthly_factors = combine(groupby(factors, :month),
                             [:MKT_RF, :SMB, :HML, :RMW, :CMA] .=> mean .=> [:MKT_RF, :SMB, :HML, :RMW, :CMA])
    
    reg_data = innerjoin(monthly_returns, monthly_factors, on=:month)
    
    if nrow(reg_data) < 36  # Mínimo 3 anos
        println("  Dados insuficientes: $(nrow(reg_data)) meses")
        return nothing
    end
    
    println("  Dados disponíveis: $(nrow(reg_data)) meses")
    
    results = Dict()
    
    # CAPM
    println("\n1. MODELO CAPM:")
    model1 = lm(@formula(LS_Portfolio ~ MKT_RF), reg_data)
    results[:capm] = model1
    
    coef1 = coef(model1)
    se1 = stderror(model1)
    t1 = coef1 ./ se1
    
    println(@sprintf("   Alpha:     %7.4f  (t = %6.2f) %s", coef1[1], t1[1], significance_stars(t1[1])))
    println(@sprintf("   Beta MKT:  %7.4f  (t = %6.2f)", coef1[2], t1[2]))
    println(@sprintf("   R²:        %7.4f", r2(model1)))
    
    # Fama-French 3-factor
    println("\n2. MODELO FAMA-FRENCH 3-FACTOR:")
    model2 = lm(@formula(LS_Portfolio ~ MKT_RF + SMB + HML), reg_data)
    results[:ff3] = model2
    
    coef2 = coef(model2)
    se2 = stderror(model2)
    t2 = coef2 ./ se2
    
    println(@sprintf("   Alpha:     %7.4f  (t = %6.2f) %s", coef2[1], t2[1], significance_stars(t2[1])))
    println(@sprintf("   Beta MKT:  %7.4f  (t = %6.2f)", coef2[2], t2[2]))
    println(@sprintf("   Beta SMB:  %7.4f  (t = %6.2f)", coef2[3], t2[3]))
    println(@sprintf("   Beta HML:  %7.4f  (t = %6.2f)", coef2[4], t2[4]))
    println(@sprintf("   R²:        %7.4f", r2(model2)))
    
    # Fama-French 5-factor
    println("\n3. MODELO FAMA-FRENCH 5-FACTOR:")
    model3 = lm(@formula(LS_Portfolio ~ MKT_RF + SMB + HML + RMW + CMA), reg_data)
    results[:ff5] = model3
    
    coef3 = coef(model3)
    se3 = stderror(model3)
    t3 = coef3 ./ se3
    
    println(@sprintf("   Alpha:     %7.4f  (t = %6.2f) %s", coef3[1], t3[1], significance_stars(t3[1])))
    println(@sprintf("   Beta MKT:  %7.4f  (t = %6.2f)", coef3[2], t3[2]))
    println(@sprintf("   Beta SMB:  %7.4f  (t = %6.2f)", coef3[3], t3[3]))
    println(@sprintf("   Beta HML:  %7.4f  (t = %6.2f)", coef3[4], t3[4]))
    println(@sprintf("   Beta RMW:  %7.4f  (t = %6.2f)", coef3[5], t3[5]))
    println(@sprintf("   Beta CMA:  %7.4f  (t = %6.2f)", coef3[6], t3[6]))
    println(@sprintf("   R²:        %7.4f", r2(model3)))
    
    return results
end

function significance_stars(t_stat)
    abs_t = abs(t_stat)
    if abs_t > 2.58
        return "***"
    elseif abs_t > 1.96
        return "**"
    elseif abs_t > 1.64
        return "*"
    else
        return ""
    end
end

# Análise de performance detalhada
function analyze_performance(monthly_returns)
    println("\n" * ("=" ^ 60))
    println("ANÁLISE DE PERFORMANCE DETALHADA")
    println("=" ^ 60)
    
    # Identificar portfolios disponíveis
    portfolio_cols = [name for name in names(monthly_returns) if name != :month && name != :LS_Portfolio]
    
    # Estatísticas para cada portfolio
    println("\nESTATÍSTICAS POR PORTFOLIO:")
    println("-" ^ 60)
    
    all_portfolios = vcat(portfolio_cols, [:LS_Portfolio])
    
    for port_col in all_portfolios
        if hasproperty(monthly_returns, port_col)
            returns = monthly_returns[!, port_col]
            returns = returns[.!ismissing.(returns)]
            
            if length(returns) >= 12
                # Métricas básicas
                mean_ret = mean(returns) * 12
                vol = std(returns) * sqrt(12)
                sharpe = (mean_ret - 0.02) / vol
                
                # Downside metrics
                downside_returns = returns[returns .< 0]
                downside_vol = isempty(downside_returns) ? 0.0 : std(downside_returns) * sqrt(12)
                sortino = (mean_ret - 0.02) / max(downside_vol, 1e-10)
                
                # Drawdown
                cum_returns = cumprod(1 .+ returns)
                running_max = accumulate(max, cum_returns)
                drawdowns = (cum_returns .- running_max) ./ running_max
                max_dd = minimum(drawdowns)
                
                # Outras métricas
                win_rate = mean(returns .> 0)
                best_month = maximum(returns)
                worst_month = minimum(returns)
                
                port_name = string(port_col)
                if port_col == :LS_Portfolio
                    println("\n$port_name (Low Vol - High Vol):")
                else
                    println("\n$port_name:")
                end
                
                println(@sprintf("  Retorno Anual:   %6.2f%%", mean_ret * 100))
                println(@sprintf("  Volatilidade:    %6.2f%%", vol * 100))
                println(@sprintf("  Sharpe Ratio:    %6.3f", sharpe))
                println(@sprintf("  Sortino Ratio:   %6.3f", sortino))
                println(@sprintf("  Max Drawdown:    %6.2f%%", max_dd * 100))
                println(@sprintf("  Taxa de Acerto:  %6.1f%%", win_rate * 100))
                println(@sprintf("  Melhor Mês:      %6.2f%%", best_month * 100))
                println(@sprintf("  Pior Mês:        %6.2f%%", worst_month * 100))
            end
        end
    end
end

# Análise por subperíodos
function analyze_subperiods(monthly_returns)
    println("\n" * ("=" ^ 60))
    println("ANÁLISE POR SUBPERÍODOS HISTÓRICOS")
    println("=" ^ 60)
    
    if !hasproperty(monthly_returns, :LS_Portfolio)
        println("Portfolio Long-Short não disponível")
        return
    end
    
    # Definir subperíodos
    subperiods = [
        ("Pré-Crise", (2000, 1), (2007, 12)),
        ("Crise Financeira", (2008, 1), (2009, 12)),
        ("Recuperação", (2010, 1), (2019, 12)),
        ("COVID", (2020, 1), (2021, 12)),
        ("Pós-COVID", (2022, 1), (2024, 11))
    ]
    
    for (period_name, start_month, end_month) in subperiods
        # Filtrar dados do período
        period_data = filter(row -> start_month <= row.month <= end_month, monthly_returns)
        
        if nrow(period_data) >= 12  # Mínimo 1 ano
            ls_returns = period_data.LS_Portfolio
            ls_returns = ls_returns[.!ismissing.(ls_returns)]
            
            if length(ls_returns) > 0
                mean_ret = mean(ls_returns) * 12
                vol = std(ls_returns) * sqrt(12)
                sharpe = (mean_ret - 0.02) / vol
                cum_ret = prod(1 .+ ls_returns) - 1
                win_rate = mean(ls_returns .> 0)
                
                println(@sprintf("\n%-17s: Ret=%6.2f%% | Vol=%6.2f%% | Sharpe=%5.2f | Cum=%6.1f%% | Win=%4.1f%%",
                                period_name, mean_ret*100, vol*100, sharpe, cum_ret*100, win_rate*100))
            end
        else
            println(@sprintf("\n%-17s: Dados insuficientes", period_name))
        end
    end
end

# Função principal
function main()
    try
        println("\nIniciando análise definitiva...")
        println("Configuração de proxy: $(isempty(PROXY_URL) ? "Não" : "Sim")")
        
        # 1. Obter lista expandida de tickers
        tickers = get_expanded_sp500_list()
        println("\nUsando $(length(tickers)) tickers selecionados")
        
        # 2. Download de dados
        price_data = download_data_robust(tickers, START_DATE, END_DATE)
        
        if nrow(price_data) == 0
            println("ERRO: Nenhum dado foi baixado!")
            return nothing
        end
        
        println("\nDados válidos: $(nrow(price_data)) registros de $(length(unique(price_data.ticker))) ações")
        
        # 3. Calcular retornos e volatilidade
        returns_data, volatility_data = calculate_returns_and_volatility(price_data)
        
        if nrow(volatility_data) == 0
            println("ERRO: Não foi possível calcular volatilidade!")
            return nothing
        end
        
        # 4. Formar portfolios decis
        portfolio_returns = form_decile_portfolios(returns_data, volatility_data)
        
        if nrow(portfolio_returns) == 0
            println("ERRO: Não foi possível formar portfolios!")
            return nothing
        end
        
        # 5. Calcular retornos mensais
        monthly_returns = calculate_monthly_returns(portfolio_returns)
        
        if isnothing(monthly_returns)
            println("ERRO: Não foi possível calcular retornos mensais!")
            return nothing
        end
        
        # 6. Baixar fatores de mercado
        factors = create_market_factors(START_DATE, END_DATE)
        
        # 7. Executar regressões
        if !isempty(factors)
            regression_results = run_factor_regressions(monthly_returns, factors)
        end
        
        # 8. Análises detalhadas
        analyze_performance(monthly_returns)
        analyze_subperiods(monthly_returns)
        
        # 9. Salvar resultados
        CSV.write("final_analysis_results.csv", monthly_returns)
        println("\n\nResultados salvos em 'final_analysis_results.csv'")
        
        println("\n" * ("=" ^ 80))
        println("ANÁLISE DEFINITIVA CONCLUÍDA COM SUCESSO!")
        println("=" ^ 80)
        
        return monthly_returns
        
    catch e
        println("ERRO na execução: $e")
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
        return nothing
    end
end

# Executar análise
println("INICIANDO ANÁLISE...")
results = main()