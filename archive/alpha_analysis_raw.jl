# ANÁLISE DE ALFA SEM AJUSTES POR FATORES
# Examinando performance bruta do portfolio Long-Short de baixa volatilidade

using HTTP
using JSON3
using DataFrames
using Dates
using CSV
using Statistics
using StatsBase
using Printf
using Distributions
using HypothesisTests

# Configurações
const START_DATE = Date(2000, 1, 1)
const END_DATE = Date(2024, 11, 30)
const PROXY_URL = get(ENV, "HTTPS_PROXY", "")

println("=" ^ 80)
println("ANÁLISE DE ALFA SEM AJUSTES POR FATORES")
println("Testando se existe excesso de retorno bruto da estratégia low-vol")
println("Período: $START_DATE a $END_DATE")
println("=" ^ 80)

# Usar uma amostra menor mas representativa para análise focada
function get_representative_tickers()
    return [
        # Large Cap Tech (10)
        "AAPL", "MSFT", "GOOGL", "AMZN", "NVDA", "META", "TSLA", "ORCL", "ADBE", "CSCO",
        
        # Large Cap Finance (10) 
        "JPM", "BAC", "WFC", "C", "GS", "MS", "BLK", "AXP", "SCHW", "USB",
        
        # Large Cap Healthcare (10)
        "JNJ", "UNH", "PFE", "ABBV", "LLY", "MRK", "ABT", "TMO", "DHR", "BMY",
        
        # Large Cap Consumer (10)
        "PG", "HD", "WMT", "KO", "PEP", "COST", "MCD", "NKE", "DIS", "LOW",
        
        # Large Cap Industrial (10)
        "BA", "CAT", "UNP", "HON", "UPS", "RTX", "LMT", "DE", "GE", "MMM",
        
        # Energy & Materials (10)
        "XOM", "CVX", "COP", "EOG", "SLB", "LIN", "APD", "NEM", "FCX", "DOW",
        
        # Utilities & REITs (10)
        "NEE", "SO", "DUK", "D", "AEP", "PLD", "AMT", "CCI", "EQIX", "PSA",
        
        # Mid-Cap representative (20)
        "AMD", "QCOM", "INTC", "AMAT", "MU", "TXN", "ADI", "LRCX", "KLAC", "MRVL",
        "V", "MA", "SPGI", "MCO", "ICE", "CME", "CB", "PGR", "TRV", "AFL"
    ]
end

# Download simplificado e robusto
function download_simplified_data(tickers, start_date, end_date)
    println("\nBaixando dados de $(length(tickers)) ações selecionadas...")
    
    all_data = DataFrame()
    success_count = 0
    
    period1 = Int(Dates.datetime2unix(DateTime(start_date)))
    period2 = Int(Dates.datetime2unix(DateTime(end_date)))
    
    for (i, ticker) in enumerate(tickers)
        if i % 20 == 0
            println("  Progresso: $i/$(length(tickers))")
        end
        
        try
            url = "https://query2.finance.yahoo.com/v8/finance/chart/$ticker"
            
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
                    
                    if haskey(result, "timestamp") && length(result["timestamp"]) > 500
                        timestamps = result["timestamp"]
                        quotes = result["indicators"]["quote"][1]
                        
                        df = DataFrame(
                            timestamp = [Date(Dates.unix2datetime(ts)) for ts in timestamps],
                            ticker = ticker,
                            close = [ismissing(v) ? missing : Float64(v) for v in quotes["close"]],
                            volume = [ismissing(v) ? missing : Float64(v) for v in quotes["volume"]]
                        )
                        
                        # Adjusted close
                        if haskey(result["indicators"], "adjclose")
                            adjclose_data = result["indicators"]["adjclose"][1]["adjclose"]
                            df[!, :adjclose] = [ismissing(v) ? missing : Float64(v) for v in adjclose_data]
                        else
                            df[!, :adjclose] = df.close
                        end
                        
                        # Filtros básicos
                        df = df[.!ismissing.(df.adjclose) .& (df.adjclose .>= 1.0), :]
                        
                        if nrow(df) > 500  # Mínimo 2 anos
                            all_data = isempty(all_data) ? df : vcat(all_data, df)
                            success_count += 1
                        end
                    end
                end
            end
        catch e
            # Continue
        end
        
        sleep(0.05)  # Pequena pausa
    end
    
    println("  Download concluído! $success_count/$(length(tickers)) ações")
    return all_data
end

# Calcular estratégia de baixa volatilidade simplificada
function calculate_low_vol_strategy(price_data)
    println("\nCalculando estratégia de baixa volatilidade...")
    
    # Calcular retornos
    sort!(price_data, [:ticker, :timestamp])
    
    returns_with_vol = DataFrame()
    
    for gdf in groupby(price_data, :ticker)
        ticker = first(gdf.ticker)
        
        if nrow(gdf) >= 300  # Mínimo para análise robusta
            # Calcular retornos
            log_returns = [missing; diff(log.(gdf.adjclose))]
            
            # Filtrar extremos
            log_returns = [abs(r) > log(2.0) ? missing : r for r in log_returns]
            
            ticker_data = DataFrame(
                timestamp = gdf.timestamp,
                ticker = ticker,
                adjclose = gdf.adjclose,
                log_return = log_returns
            )
            
            # Calcular volatilidade rolling 252 dias
            volatilities = Float64[]
            
            for i in 253:nrow(ticker_data)
                window_returns = ticker_data.log_return[i-251:i]
                window_returns = window_returns[.!ismissing.(window_returns)]
                
                if length(window_returns) >= 200  # 80% dos dados válidos
                    vol = std(window_returns) * sqrt(252)
                    push!(volatilities, vol)
                else
                    push!(volatilities, missing)
                end
            end
            
            # Adicionar volatilidade ao DataFrame
            ticker_data[253:end, :volatility] = volatilities
            
            # Filtrar apenas dados com volatilidade calculada
            ticker_data = ticker_data[253:end, :]
            dropmissing!(ticker_data, [:log_return, :volatility])
            
            if nrow(ticker_data) > 0
                returns_with_vol = isempty(returns_with_vol) ? ticker_data : vcat(returns_with_vol, ticker_data)
            end
        end
    end
    
    println("  Dados processados: $(nrow(returns_with_vol)) observações de $(length(unique(returns_with_vol.ticker))) ações")
    
    return returns_with_vol
end

# Formar portfolios quintis mensalmente
function form_monthly_portfolios(data)
    println("\nFormando portfolios mensais baseados em volatilidade...")
    
    data[!, :month] = Dates.yearmonth.(data.timestamp)
    
    portfolio_returns = DataFrame()
    unique_months = sort(unique(data.month))
    
    valid_months = 0
    
    for i in 2:length(unique_months)
        current_month = unique_months[i]
        previous_month = unique_months[i-1]
        
        # Volatilidades do mês anterior para classificação
        prev_month_data = filter(row -> row.month == previous_month, data)
        
        if nrow(prev_month_data) >= 30  # Mínimo 30 ações
            # Última volatilidade de cada ação no mês anterior
            last_vol = combine(groupby(prev_month_data, :ticker), :volatility => last => :volatility)
            
            # Formar quintis
            n_stocks = nrow(last_vol)
            q20 = quantile(last_vol.volatility, 0.2)  # 20° percentil
            q80 = quantile(last_vol.volatility, 0.8)  # 80° percentil
            
            # Classificar ações
            last_vol[!, :portfolio] = map(last_vol.volatility) do vol
                if vol <= q20
                    "Low_Vol"
                elseif vol >= q80
                    "High_Vol"  
                else
                    "Mid_Vol"
                end
            end
            
            # Retornos do mês atual
            curr_month_data = filter(row -> row.month == current_month, data)
            curr_returns = innerjoin(curr_month_data, last_vol[!, [:ticker, :portfolio]], on=:ticker)
            
            if nrow(curr_returns) > 0
                # Calcular retorno médio diário por portfolio
                daily_port_ret = combine(groupby(curr_returns, [:timestamp, :portfolio]),
                                       :log_return => mean => :portfolio_return)
                
                portfolio_returns = isempty(portfolio_returns) ? daily_port_ret : vcat(portfolio_returns, daily_port_ret)
                valid_months += 1
            end
        end
    end
    
    println("  Portfolios formados para $valid_months meses")
    return portfolio_returns
end

# Calcular retornos mensais e Long-Short
function calculate_monthly_long_short(portfolio_returns)
    println("\nCalculando retornos mensais e portfolio Long-Short...")
    
    # Adicionar coluna mês
    portfolio_returns[!, :month] = Dates.yearmonth.(portfolio_returns.timestamp)
    
    # Agregar para mensal (retorno composto)
    monthly = combine(groupby(portfolio_returns, [:month, :portfolio]),
                     :portfolio_return => (x -> exp(sum(x)) - 1) => :monthly_return)
    
    # Formato wide
    monthly_wide = unstack(monthly, :month, :portfolio, :monthly_return)
    
    # Verificar se temos os portfolios necessários
    if hasproperty(monthly_wide, :Low_Vol) && hasproperty(monthly_wide, :High_Vol)
        # Calcular Long-Short (Low Vol - High Vol)
        monthly_wide[!, :LS_Portfolio] = monthly_wide.Low_Vol .- monthly_wide.High_Vol
        
        return monthly_wide
    else
        println("  Erro: Não foi possível formar portfolios Low_Vol e High_Vol")
        return nothing
    end
end

# Baixar SPY para comparação
function download_spy_benchmark(start_date, end_date)
    println("\nBaixando benchmark SPY...")
    
    spy_data = download_simplified_data(["SPY"], start_date, end_date)
    
    if isempty(spy_data)
        println("  Erro ao baixar SPY")
        return DataFrame()
    end
    
    # Calcular retornos mensais do SPY
    sort!(spy_data, :timestamp)
    spy_data[!, :log_return] = [missing; diff(log.(spy_data.adjclose))]
    spy_data[!, :month] = Dates.yearmonth.(spy_data.timestamp)
    
    # Retornos mensais
    spy_monthly = combine(groupby(spy_data, :month),
                         :log_return => (x -> exp(sum(skipmissing(x))) - 1) => :SPY_return)
    
    return spy_monthly
end

# Análise de performance bruta sem ajustes
function analyze_raw_performance(monthly_data, spy_data)
    println("\n" * ("=" ^ 60))
    println("ANÁLISE DE PERFORMANCE BRUTA (SEM AJUSTES POR FATORES)")
    println("=" ^ 60)
    
    if !hasproperty(monthly_data, :LS_Portfolio)
        println("Portfolio Long-Short não disponível")
        return nothing
    end
    
    # Juntar com SPY
    analysis_data = innerjoin(monthly_data, spy_data, on=:month)
    
    # Dados do Long-Short
    ls_returns = analysis_data.LS_Portfolio
    ls_returns = ls_returns[.!ismissing.(ls_returns)]
    
    spy_returns = analysis_data.SPY_return
    spy_returns = spy_returns[.!ismissing.(spy_returns)]
    
    n_months = length(ls_returns)
    
    println("\nDados disponíveis: $n_months meses")
    
    # === 1. TESTE T SIMPLES DO RETORNO MÉDIO ===
    println("\n1. TESTE T DO RETORNO MÉDIO MENSAL:")
    println("-" ^ 40)
    
    mean_return = mean(ls_returns)
    std_return = std(ls_returns)
    t_stat = mean_return / (std_return / sqrt(n_months))
    
    # P-value bilateral
    p_value = 2 * (1 - cdf(TDist(n_months-1), abs(t_stat)))
    
    println(@sprintf("  Retorno médio mensal:    %7.4f (%6.2f%% anualizado)", mean_return, mean_return * 12 * 100))
    println(@sprintf("  Desvio padrão mensal:    %7.4f (%6.2f%% anualizado)", std_return, std_return * sqrt(12) * 100))
    println(@sprintf("  Erro padrão da média:    %7.4f", std_return / sqrt(n_months)))
    println(@sprintf("  Estatística t:           %7.2f", t_stat))
    println(@sprintf("  P-value (bilateral):     %7.4f", p_value))
    
    significance = if p_value < 0.001
        "*** (altamente significativo)"
    elseif p_value < 0.01
        "** (muito significativo)" 
    elseif p_value < 0.05
        "* (significativo)"
    elseif p_value < 0.10
        ". (marginalmente significativo)"
    else
        "(não significativo)"
    end
    
    println(@sprintf("  Resultado:               %s", significance))
    
    # Intervalo de confiança
    ci_margin = tinv(0.975, n_months-1) * (std_return / sqrt(n_months))
    ci_lower = mean_return - ci_margin
    ci_upper = mean_return + ci_margin
    
    println(@sprintf("  IC 95%%:                 [%7.4f, %7.4f]", ci_lower, ci_upper))
    
    # === 2. COMPARAÇÃO COM SPY ===
    println("\n2. COMPARAÇÃO COM BENCHMARK SPY:")
    println("-" ^ 40)
    
    spy_mean = mean(spy_returns)
    excess_return = mean_return - spy_mean
    
    # Teste t para diferença de médias
    diff_returns = ls_returns .- spy_returns
    diff_mean = mean(diff_returns)
    diff_std = std(diff_returns)
    diff_t_stat = diff_mean / (diff_std / sqrt(n_months))
    diff_p_value = 2 * (1 - cdf(TDist(n_months-1), abs(diff_t_stat)))
    
    println(@sprintf("  SPY retorno médio:       %7.4f (%6.2f%% anualizado)", spy_mean, spy_mean * 12 * 100))
    println(@sprintf("  Excesso de retorno:      %7.4f (%6.2f%% anualizado)", excess_return, excess_return * 12 * 100))
    println(@sprintf("  T-stat (diferença):      %7.2f", diff_t_stat))
    println(@sprintf("  P-value (diferença):     %7.4f", diff_p_value))
    
    excess_significance = if diff_p_value < 0.05
        if excess_return > 0
            "Supera SPY significativamente"
        else
            "Underperforma SPY significativamente"
        end
    else
        "Não há diferença significativa vs. SPY"
    end
    
    println(@sprintf("  Conclusão:               %s", excess_significance))
    
    # === 3. MÉTRICAS DE RISCO-RETORNO PURAS ===
    println("\n3. MÉTRICAS PURAS DE RISCO-RETORNO:")
    println("-" ^ 40)
    
    # Sharpe ratio (assumindo rf = 2% a.a.)
    rf_monthly = 0.02 / 12
    sharpe_ratio = (mean_return - rf_monthly) / std_return
    
    # Downside deviation (vs. zero)
    downside_returns = ls_returns[ls_returns .< 0]
    downside_vol = isempty(downside_returns) ? 0.0 : std(downside_returns)
    sortino_ratio = (mean_return - rf_monthly) / downside_vol
    
    # Maximum drawdown
    cum_returns = cumprod(1 .+ ls_returns)
    running_max = accumulate(max, cum_returns)
    drawdowns = (cum_returns .- running_max) ./ running_max
    max_drawdown = minimum(drawdowns)
    
    # Win rate
    win_rate = mean(ls_returns .> 0)
    
    # Calmar ratio
    calmar_ratio = (mean_return * 12) / abs(max_drawdown)
    
    println(@sprintf("  Sharpe Ratio:            %7.3f", sharpe_ratio))
    println(@sprintf("  Sortino Ratio:           %7.3f", sortino_ratio))
    println(@sprintf("  Calmar Ratio:            %7.3f", calmar_ratio))
    println(@sprintf("  Maximum Drawdown:        %7.2f%%", max_drawdown * 100))
    println(@sprintf("  Taxa de acerto:          %7.1f%%", win_rate * 100))
    
    # === 4. DISTRIBUIÇÃO DOS RETORNOS ===
    println("\n4. CARACTERÍSTICAS DA DISTRIBUIÇÃO:")
    println("-" ^ 40)
    
    skew = skewness(ls_returns)
    kurt = kurtosis(ls_returns)
    
    best_month = maximum(ls_returns)
    worst_month = minimum(ls_returns)
    
    println(@sprintf("  Skewness:                %7.3f", skew))
    println(@sprintf("  Kurtosis:                %7.3f", kurt))
    println(@sprintf("  Melhor mês:              %7.2f%%", best_month * 100))
    println(@sprintf("  Pior mês:                %7.2f%%", worst_month * 100))
    
    # Test de normalidade (Jarque-Bera aproximado)
    jb_stat = n_months * (skew^2 / 6 + (kurt^2) / 24)
    jb_p_value = 1 - cdf(Chisq(2), jb_stat)
    
    println(@sprintf("  Teste Jarque-Bera:       %7.2f (p = %.4f)", jb_stat, jb_p_value))
    
    normality = jb_p_value > 0.05 ? "Distribuição normal" : "Distribuição não-normal"
    println(@sprintf("  Normalidade:             %s", normality))
    
    return Dict(
        :mean_return => mean_return,
        :t_statistic => t_stat,
        :p_value => p_value,
        :excess_vs_spy => excess_return,
        :sharpe => sharpe_ratio,
        :max_drawdown => max_drawdown,
        :win_rate => win_rate,
        :n_months => n_months
    )
end

# Análise por décadas
function analyze_by_decades(monthly_data)
    println("\n" * ("=" ^ 60))
    println("ANÁLISE POR DÉCADAS")
    println("=" ^ 60)
    
    if !hasproperty(monthly_data, :LS_Portfolio)
        return
    end
    
    decades = [
        ("2000-2009", (2000,1), (2009,12)),
        ("2010-2019", (2010,1), (2019,12)), 
        ("2020-2024", (2020,1), (2024,11))
    ]
    
    for (decade_name, start_period, end_period) in decades
        decade_data = filter(row -> start_period <= row.month <= end_period, monthly_data)
        
        if nrow(decade_data) >= 12  # Mínimo 1 ano
            ls_returns = decade_data.LS_Portfolio
            ls_returns = ls_returns[.!ismissing.(ls_returns)]
            
            if length(ls_returns) > 0
                mean_ret = mean(ls_returns)
                std_ret = std(ls_returns)
                n_months = length(ls_returns)
                
                # Teste t
                t_stat = mean_ret / (std_ret / sqrt(n_months))
                p_val = 2 * (1 - cdf(TDist(n_months-1), abs(t_stat)))
                
                # Sharpe
                rf_monthly = 0.02 / 12
                sharpe = (mean_ret - rf_monthly) / std_ret
                
                # Cumulative return
                cum_ret = prod(1 .+ ls_returns) - 1
                
                significance_symbol = p_val < 0.05 ? "*" : ""
                
                println(@sprintf("\n%s (%d meses):", decade_name, n_months))
                println(@sprintf("  Retorno médio:   %6.2f%% a.a.  (t = %5.2f, p = %.3f) %s", 
                                mean_ret*12*100, t_stat, p_val, significance_symbol))
                println(@sprintf("  Sharpe Ratio:    %6.3f", sharpe))  
                println(@sprintf("  Retorno total:   %6.1f%%", cum_ret*100))
            end
        end
    end
end

# Salvar resultados para análise posterior
function save_results(monthly_data)
    if !isnothing(monthly_data)
        CSV.write("alpha_analysis_raw_results.csv", monthly_data)
        println("\nResultados salvos em 'alpha_analysis_raw_results.csv'")
    end
end

# Função principal
function main()
    try
        println("Iniciando análise de alfa sem ajustes...")
        
        # 1. Obter tickers representativos
        tickers = get_representative_tickers()
        println("Usando $(length(tickers)) ações representativas")
        
        # 2. Download de dados
        price_data = download_simplified_data(tickers, START_DATE, END_DATE)
        
        if nrow(price_data) == 0
            println("ERRO: Nenhum dado baixado!")
            return nothing
        end
        
        # 3. Calcular estratégia
        strategy_data = calculate_low_vol_strategy(price_data)
        
        # 4. Formar portfolios
        portfolio_returns = form_monthly_portfolios(strategy_data)
        
        # 5. Calcular Long-Short mensal
        monthly_returns = calculate_monthly_long_short(portfolio_returns)
        
        if isnothing(monthly_returns)
            println("ERRO: Não foi possível formar portfolio Long-Short")
            return nothing
        end
        
        # 6. Baixar SPY para benchmark
        spy_data = download_spy_benchmark(START_DATE, END_DATE)
        
        # 7. Análise de performance bruta
        performance_results = analyze_raw_performance(monthly_returns, spy_data)
        
        # 8. Análise por décadas
        analyze_by_decades(monthly_returns)
        
        # 9. Salvar resultados
        save_results(monthly_returns)
        
        println("\n" * ("=" ^ 80))
        println("ANÁLISE DE ALFA SEM AJUSTES CONCLUÍDA!")
        println("=" ^ 80)
        
        return performance_results
        
    catch e
        println("ERRO: $e")
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
    end
end

# Executar
results = main()