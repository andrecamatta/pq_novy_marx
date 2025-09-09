# ANÁLISE PADRÃO ACADÊMICO - ANOMALIA DE BAIXA VOLATILIDADE
# Metodologia seguindo Baker, Bradley & Wurgler (2011) e padrões de top journals

using HTTP
using JSON3
using DataFrames
using Dates
using CSV
using Statistics
using StatsBase
using Printf
using Distributions
using Random

const PROXY_URL = get(ENV, "HTTPS_PROXY", "")

println("=" ^ 80)
println("ANÁLISE PADRÃO ACADÊMICO - ANOMALIA DE BAIXA VOLATILIDADE")
println("Metodologia: Baker, Bradley & Wurgler (2011) + Top Journal Standards")
println("=" ^ 80)

# Configurações acadêmicas padrão
const FORMATION_LAG = 1  # 1-month lag (padrão acadêmico)
const MIN_PRICE = 5.0   # Filtro penny stocks
const MIN_MARKET_CAP = 100_000_000  # $100M minimum (proxy)
const REBALANCE_FREQUENCY = "monthly"
const VOLATILITY_WINDOW = 252  # 1 year daily returns
const MIN_OBSERVATIONS = 200  # Minimum for volatility calculation

# Academic-grade ticker lists por período (baseado em pesquisa histórica)
function get_academic_universe()
    # Baseado em constituintes históricos conhecidos e literatura acadêmica
    return Dict{String, Vector{String}}(
        
        # Era pré-2008 (includes many that failed in crisis)
        "2000-2009" => [
            # Large Tech (survivors + failed)
            "AAPL", "MSFT", "GOOGL", "AMZN", "INTC", "CSCO", "ORCL", "IBM", "HPQ",
            # Financial (many failed)  
            "JPM", "BAC", "C", "WFC", "WB", "LEH", "BSC", "MER", "AIG", "USB", "KEY", "RF", "PNC",
            # Energy
            "XOM", "CVX", "COP", "SLB", "HAL", "OXY", "DVN", "APC", "EOG",
            # Industrial
            "GE", "CAT", "MMM", "HON", "UTX", "BA", "UPS", "FDX", "EMR",
            # Consumer
            "WMT", "HD", "PG", "KO", "PEP", "MCD", "DIS", "TGT", "LOW", "COST",
            # Healthcare  
            "JNJ", "PFE", "MRK", "LLY", "ABBV", "ABT", "MDT", "BMY", "AMGN",
            # Autos (strugglers)
            "F", "GM", 
            # Telecom
            "T", "VZ",
            # Utilities
            "SO", "DUK", "D", "NEE", "AEP"
        ],
        
        # Post-crisis era (2010-2019)  
        "2010-2019" => [
            # FAANG emergence
            "AAPL", "GOOGL", "GOOG", "AMZN", "META", "NFLX",
            # Established tech
            "MSFT", "INTC", "CSCO", "ORCL", "IBM", "QCOM", "TXN", "NVDA", "AMD",
            # Recovered financials
            "JPM", "BAC", "WFC", "C", "USB", "PNC", "COF", "GS", "MS", "AXP",
            # Energy boom/bust
            "XOM", "CVX", "COP", "SLB", "HAL", "EOG", "PXD", "DVN", "OXY", "HES",
            # Healthcare expansion
            "JNJ", "UNH", "PFE", "MRK", "LLY", "ABBV", "ABT", "GILD", "BIIB", "AMGN",
            # Consumer resilience  
            "WMT", "HD", "PG", "KO", "PEP", "MCD", "DIS", "NKE", "SBUX", "TGT", "LOW", "COST",
            # Industrials
            "GE", "CAT", "BA", "MMM", "HON", "UNP", "UPS", "FDX",
            # REITs growth
            "PLD", "AMT", "CCI", "SPG", "EQIX"
        ],
        
        # Modern era (2020-2024)
        "2020-2024" => [
            # Mega-cap dominance
            "AAPL", "MSFT", "GOOGL", "GOOG", "AMZN", "META", "TSLA", "NVDA",
            # Cloud/Software 
            "CRM", "ADBE", "ORCL", "NOW", "WDAY", "SNOW",
            # Semiconductors
            "NVDA", "AMD", "INTC", "QCOM", "AVGO", "TXN", "ADI", "MRVL",
            # Payments/Fintech
            "V", "MA", "PYPL", "SQ", 
            # Traditional finance
            "JPM", "BAC", "WFC", "C", "GS", "MS",
            # Healthcare/Biotech
            "JNJ", "UNH", "PFE", "MRNA", "LLY", "ABBV", "JNJ",
            # Consumer 
            "WMT", "HD", "PG", "KO", "DIS", "NKE",
            # Energy transition
            "XOM", "CVX", "COP", "SLB"
        ]
    )
end

# Events database (falências, aquisições, delistings)
function get_corporate_events_academic()
    return Dict{String, Dict}(
        # 2008 Financial Crisis casualties
        "LEH" => Dict("type" => "bankruptcy", "date" => Date(2008, 9, 15), "return" => -1.0),
        "BSC" => Dict("type" => "acquisition", "date" => Date(2008, 3, 16), "return" => -0.85),
        "MER" => Dict("type" => "acquisition", "date" => Date(2008, 9, 15), "return" => -0.70),
        "WB" => Dict("type" => "acquisition", "date" => Date(2008, 9, 29), "return" => -0.65),
        "AIG" => Dict("type" => "bailout", "date" => Date(2008, 9, 16), "return" => -0.95),
        
        # Auto industry restructuring
        "GM" => Dict("type" => "bankruptcy", "date" => Date(2009, 6, 1), "return" => -1.0),
        
        # Energy sector casualties (shale bust)
        "CHK" => Dict("type" => "bankruptcy", "date" => Date(2020, 6, 28), "return" => -1.0),
        "WLL" => Dict("type" => "bankruptcy", "date" => Date(2020, 3, 31), "return" => -1.0),
        
        # Retail disruption
        "SHLD" => Dict("type" => "delisted", "date" => Date(2018, 10, 15), "return" => -0.95),
        "JCP" => Dict("type" => "bankruptcy", "date" => Date(2020, 5, 15), "return" => -0.90),
        
        # Tech M&A
        "YHOO" => Dict("type" => "acquisition", "date" => Date(2017, 6, 13), "return" => -0.15),
    )
end

# Point-in-time data download with academic standards
function download_academic_data(tickers, start_date, end_date, corporate_events)
    println("\nDownload com padrões acadêmicos...")
    println("Período: $start_date a $end_date")
    println("Tickers: $(length(tickers))")
    
    all_data = DataFrame()
    success_count = 0
    
    period1 = Int(Dates.datetime2unix(DateTime(start_date)))
    period2 = Int(Dates.datetime2unix(DateTime(end_date)))
    
    for (i, ticker) in enumerate(tickers)
        if i % 25 == 0
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
                    
                    if haskey(result, "timestamp") && length(result["timestamp"]) > MIN_OBSERVATIONS
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
                        
                        # Academic filters
                        df = df[.!ismissing.(df.adjclose) .& 
                               .!ismissing.(df.volume) .&
                               (df.adjclose .>= MIN_PRICE), :]
                        
                        # Handle corporate events (survivorship bias correction)
                        if haskey(corporate_events, ticker)
                            event_info = corporate_events[ticker]
                            event_date = event_info["date"]
                            
                            if start_date <= event_date <= end_date
                                # Cut data at event date
                                df = df[df.timestamp .<= event_date, :]
                                
                                # Apply final return
                                if nrow(df) > 0 && event_info["return"] < 0
                                    final_price = df.adjclose[end] * (1 + event_info["return"])
                                    
                                    push!(df, [event_date, ticker, final_price, missing, final_price])
                                end
                                
                                println("    $ticker: $(event_info["type"]) event applied")
                            end
                        end
                        
                        if nrow(df) >= MIN_OBSERVATIONS
                            all_data = isempty(all_data) ? df : vcat(all_data, df)
                            success_count += 1
                        end
                    end
                end
            end
            
        catch e
            # Silent for failed downloads (expected for some delisted firms)
        end
        
        sleep(0.02)  # Rate limiting
    end
    
    println("  Download concluído: $success_count/$(length(tickers)) sucessos")
    return all_data
end

# Academic-standard volatility calculation
function calculate_academic_volatility(price_data, vol_window=VOLATILITY_WINDOW)
    println("\nCalculando volatilidade (padrão acadêmico)...")
    
    sort!(price_data, [:ticker, :timestamp])
    
    all_vol_data = DataFrame()
    
    for gdf in groupby(price_data, :ticker)
        ticker = first(gdf.ticker)
        n = nrow(gdf)
        
        if n >= vol_window + 30  # Buffer for robust calculation
            # Log returns
            log_returns = [missing; diff(log.(gdf.adjclose))]
            
            # Filter extreme returns (academic standard)
            log_returns = [!ismissing(r) && abs(r) > log(3.0) ? missing : r for r in log_returns]
            
            # Rolling volatility calculation
            volatilities = Float64[]
            dates = Date[]
            
            for i in (vol_window + 1):n
                window_returns = log_returns[i-vol_window+1:i]
                valid_returns = window_returns[.!ismissing.(window_returns)]
                
                if length(valid_returns) >= round(Int, vol_window * 0.8)  # 80% data availability
                    vol = std(valid_returns) * sqrt(252)  # Annualized
                    push!(volatilities, vol)
                    push!(dates, gdf.timestamp[i])
                end
            end
            
            if length(volatilities) > 0
                vol_df = DataFrame(
                    ticker = ticker,
                    date = dates,
                    volatility = volatilities
                )
                
                all_vol_data = isempty(all_vol_data) ? vol_df : vcat(all_vol_data, vol_df)
            end
        end
    end
    
    println("  Volatilidade calculada: $(length(unique(all_vol_data.ticker))) ações")
    return all_vol_data
end

# Academic portfolio formation with 1-month lag
function form_academic_portfolios(price_data, vol_data)
    println("\nFormação de portfolios (metodologia acadêmica)...")
    println("- Rebalanceamento mensal")
    println("- 1-month lag entre formação e investimento") 
    println("- End-of-month prices")
    
    # Calculate returns
    sort!(price_data, [:ticker, :timestamp])
    returns_data = DataFrame()
    
    for gdf in groupby(price_data, :ticker)
        ticker = first(gdf.ticker)
        log_returns = [missing; diff(log.(gdf.adjclose))]
        
        ticker_returns = DataFrame(
            timestamp = gdf.timestamp,
            ticker = ticker,
            adjclose = gdf.adjclose,
            log_return = log_returns
        )
        
        returns_data = isempty(returns_data) ? ticker_returns : vcat(returns_data, ticker_returns)
    end
    
    dropmissing!(returns_data, :log_return)
    
    # Monthly portfolio formation
    returns_data[!, :month] = Dates.yearmonth.(returns_data.timestamp)
    vol_data[!, :month] = Dates.yearmonth.(vol_data.date)
    
    portfolio_returns = DataFrame()
    unique_months = sort(unique(returns_data.month))
    
    for i in 3:length(unique_months)  # Start from month 3 to allow for lags
        formation_month = unique_months[i-2]  # Formation period
        investment_month = unique_months[i-1]  # 1-month lag  
        return_month = unique_months[i]       # Return period
        
        # Get end-of-formation-month volatilities
        formation_vol = filter(row -> row.month == formation_month, vol_data)
        
        if nrow(formation_vol) >= 30  # Minimum for robust portfolios
            # Last volatility observation per stock in formation month
            last_vol = combine(groupby(formation_vol, :ticker), :volatility => last => :volatility)
            
            # Form quintiles based on volatility
            n_stocks = nrow(last_vol)
            
            if n_stocks >= 50  # Academic minimum for quintiles
                # Quintile breakpoints
                sort!(last_vol, :volatility)
                q20 = quantile(last_vol.volatility, 0.2)
                q40 = quantile(last_vol.volatility, 0.4) 
                q60 = quantile(last_vol.volatility, 0.6)
                q80 = quantile(last_vol.volatility, 0.8)
                
                # Assign quintiles
                last_vol[!, :quintile] = map(last_vol.volatility) do vol
                    if vol <= q20
                        1  # Low volatility
                    elseif vol <= q40
                        2
                    elseif vol <= q60
                        3  
                    elseif vol <= q80
                        4
                    else
                        5  # High volatility
                    end
                end
                
                # Get returns for the return month (with 1-month lag)
                return_data = filter(row -> row.month == return_month, returns_data)
                portfolio_data = innerjoin(return_data, last_vol[!, [:ticker, :quintile]], on=:ticker)
                
                if nrow(portfolio_data) > 0
                    # Equal-weighted portfolio returns by day
                    daily_port = combine(groupby(portfolio_data, [:timestamp, :quintile]),
                                       :log_return => mean => :portfolio_return)
                    
                    portfolio_returns = isempty(portfolio_returns) ? daily_port : vcat(portfolio_returns, daily_port)
                end
            end
        end
    end
    
    println("  Portfolios formados com $(length(unique(portfolio_returns.timestamp))) dias de dados")
    return portfolio_returns
end

# Calculate monthly returns with academic standards
function calculate_monthly_returns_academic(portfolio_returns)
    println("\nCalculando retornos mensais...")
    
    portfolio_returns[!, :month] = Dates.yearmonth.(portfolio_returns.timestamp)
    
    # Compound daily returns to monthly
    monthly = combine(groupby(portfolio_returns, [:month, :quintile]),
                     :portfolio_return => (x -> exp(sum(x)) - 1) => :monthly_return)
    
    # Pivot to wide format
    monthly_wide = unstack(monthly, :month, :quintile, :monthly_return)
    
    # Rename columns 
    col_renames = Dict{Symbol, Symbol}()
    for i in 1:5
        if hasproperty(monthly_wide, Symbol(string(i)))
            if i == 1
                col_renames[Symbol(string(i))] = :Q1_LowVol
            elseif i == 5  
                col_renames[Symbol(string(i))] = :Q5_HighVol
            else
                col_renames[Symbol(string(i))] = Symbol("Q$i")
            end
        end
    end
    
    if !isempty(col_renames)
        rename!(monthly_wide, col_renames)
    end
    
    # Calculate Long-Short portfolio
    if hasproperty(monthly_wide, :Q1_LowVol) && hasproperty(monthly_wide, :Q5_HighVol)
        monthly_wide[!, :LowVol_HighVol] = monthly_wide.Q1_LowVol .- monthly_wide.Q5_HighVol
    end
    
    return monthly_wide
end

# Academic-standard performance analysis
function analyze_academic_performance(monthly_returns, period_name)
    println("\n" * ("=" ^ 60))
    println("ANÁLISE ACADÊMICA - $period_name")
    println("=" ^ 60)
    
    if !hasproperty(monthly_returns, :LowVol_HighVol)
        println("Portfolio Long-Short não disponível")
        return nothing
    end
    
    ls_returns = monthly_returns.LowVol_HighVol
    ls_returns = ls_returns[.!ismissing.(ls_returns)]
    
    if length(ls_returns) < 24  # Minimum 2 years
        println("Dados insuficientes ($(length(ls_returns)) meses)")
        return nothing
    end
    
    n_months = length(ls_returns)
    
    # === BASIC STATISTICS ===
    mean_monthly = mean(ls_returns)
    std_monthly = std(ls_returns)
    
    # Annualized metrics
    mean_annual = mean_monthly * 12
    std_annual = std_monthly * sqrt(12)
    sharpe_annual = mean_annual / std_annual
    
    # t-statistic for significance
    t_stat = mean_monthly / (std_monthly / sqrt(n_months))
    p_value = 2 * (1 - cdf(TDist(n_months-1), abs(t_stat)))
    
    println(@sprintf("\nRETURN STATISTICS:"))
    println(@sprintf("  Months:              %d", n_months))
    println(@sprintf("  Mean Monthly:        %6.3f%% (t = %5.2f)", mean_monthly * 100, t_stat))
    println(@sprintf("  Annualized:          %6.2f%%", mean_annual * 100))
    println(@sprintf("  Volatility:          %6.2f%%", std_annual * 100))
    println(@sprintf("  Sharpe Ratio:        %6.3f", sharpe_annual))
    println(@sprintf("  P-value:             %6.4f", p_value))
    
    significance = if p_value < 0.001
        "***"
    elseif p_value < 0.01
        "**"
    elseif p_value < 0.05
        "*"
    else
        "n.s."
    end
    println(@sprintf("  Significance:        %s", significance))
    
    # === RISK METRICS ===
    cum_returns = cumprod(1 .+ ls_returns)
    running_max = accumulate(max, cum_returns)
    drawdowns = (cum_returns .- running_max) ./ running_max
    max_dd = minimum(drawdowns)
    
    # Downside deviation
    downside_returns = ls_returns[ls_returns .< 0]
    downside_vol = isempty(downside_returns) ? 0.0 : std(downside_returns) * sqrt(12)
    
    # Win rate
    win_rate = mean(ls_returns .> 0)
    
    println(@sprintf("\nRISK METRICS:"))
    println(@sprintf("  Maximum Drawdown:    %6.2f%%", max_dd * 100))
    println(@sprintf("  Downside Volatility: %6.2f%%", downside_vol * 100))
    println(@sprintf("  Win Rate:            %6.1f%%", win_rate * 100))
    
    # === DISTRIBUTION ===
    skew = skewness(ls_returns)
    kurt = kurtosis(ls_returns)
    
    println(@sprintf("\nDISTRIBUTION:"))
    println(@sprintf("  Skewness:            %6.3f", skew))
    println(@sprintf("  Kurtosis:            %6.3f", kurt))
    println(@sprintf("  Min Monthly:         %6.2f%%", minimum(ls_returns) * 100))
    println(@sprintf("  Max Monthly:         %6.2f%%", maximum(ls_returns) * 100))
    
    # Return results for comparison
    return Dict(
        :period => period_name,
        :n_months => n_months,
        :mean_annual => mean_annual,
        :vol_annual => std_annual, 
        :sharpe => sharpe_annual,
        :t_stat => t_stat,
        :p_value => p_value,
        :max_dd => max_dd,
        :win_rate => win_rate,
        :significance => significance
    )
end

# Monte Carlo simulation for robustness
function monte_carlo_delisting(base_results, n_simulations=50)
    println("\n" * ("=" ^ 60))
    println("SIMULAÇÃO MONTE CARLO - ROBUSTEZ A DELISTING")
    println("=" ^ 60)
    
    # Simulate random delisting events
    # Academic literature suggests ~4-6% annual delisting rate
    annual_delisting_rate = 0.05
    monthly_delisting_rate = annual_delisting_rate / 12
    
    # Average return penalty for delisting (academic estimates)
    delisting_penalty = -0.30  # -30% average
    
    println("Simulação de robustez com:")
    println("- Taxa de delisting: $(annual_delisting_rate * 100)% ao ano")  
    println("- Penalidade média: $(delisting_penalty * 100)%")
    println("- Simulações: $n_simulations")
    
    Random.seed!(42)  # Reproducible results
    
    original_return = base_results[:mean_annual]
    simulated_returns = Float64[]
    
    for sim in 1:n_simulations
        # Simulate delisting events over the period
        n_months = base_results[:n_months]
        adjusted_return = original_return
        
        # Apply random delisting penalty
        for month in 1:n_months
            if rand() < monthly_delisting_rate
                # Random stock gets delisted with penalty
                portfolio_impact = delisting_penalty * (1/50)  # Assume 50 stocks per portfolio
                adjusted_return += portfolio_impact
            end
        end
        
        push!(simulated_returns, adjusted_return)
    end
    
    # Statistics of simulated returns
    sim_mean = mean(simulated_returns)
    sim_std = std(simulated_returns)
    sim_p05 = quantile(simulated_returns, 0.05)
    sim_p95 = quantile(simulated_returns, 0.95)
    
    println(@sprintf("\nRESULTADOS DA SIMULAÇÃO:"))
    println(@sprintf("  Original:            %6.2f%%", original_return * 100))
    println(@sprintf("  Média simulada:      %6.2f%%", sim_mean * 100))
    println(@sprintf("  Desvio padrão:       %6.2f%%", sim_std * 100))
    println(@sprintf("  IC 90%%:             [%5.2f%%, %5.2f%%]", sim_p05 * 100, sim_p95 * 100))
    
    # Test if still significant
    t_stat_adjusted = sim_mean / (sim_std / sqrt(n_simulations))
    still_significant = abs(t_stat_adjusted) > 1.96
    
    println(@sprintf("  T-stat ajustado:     %6.2f", t_stat_adjusted))
    println(@sprintf("  Ainda significativo: %s", still_significant ? "Sim" : "Não"))
    
    return Dict(:adjusted_return => sim_mean, :still_significant => still_significant)
end

# Main academic analysis
function run_academic_analysis()
    println("Iniciando análise com padrões acadêmicos...")
    
    universe = get_academic_universe()
    events = get_corporate_events_academic()
    
    all_results = Dict[]
    
    # Analyze each period
    periods = [
        ("2000-2009", Date(2000, 1, 1), Date(2009, 12, 31), "2000-2009"),
        ("2010-2019", Date(2010, 1, 1), Date(2019, 12, 31), "2010-2019"),  
        ("2020-2024", Date(2020, 1, 1), Date(2024, 10, 31), "2020-2024")
    ]
    
    for (period_name, start_date, end_date, universe_key) in periods
        println("\n" * ("=" ^ 80))
        println("PERÍODO: $period_name")
        println("=" ^ 80)
        
        tickers = universe[universe_key]
        println("Universo acadêmico: $(length(tickers)) ações")
        
        # Download data
        price_data = download_academic_data(tickers, start_date, end_date, events)
        
        if nrow(price_data) > 5000  # Sufficient data
            # Calculate volatility
            vol_data = calculate_academic_volatility(price_data)
            
            if nrow(vol_data) > 0
                # Form portfolios
                portfolio_returns = form_academic_portfolios(price_data, vol_data)
                
                if nrow(portfolio_returns) > 0
                    # Monthly returns
                    monthly_returns = calculate_monthly_returns_academic(portfolio_returns)
                    
                    # Analysis
                    results = analyze_academic_performance(monthly_returns, period_name)
                    
                    if !isnothing(results)
                        push!(all_results, results)
                        
                        # Monte Carlo for this period
                        mc_results = monte_carlo_delisting(results, 50)
                    end
                end
            end
        else
            println("Dados insuficientes para $period_name")
        end
    end
    
    # Overall summary
    if length(all_results) > 0
        println("\n" * ("=" ^ 80))
        println("RESUMO GERAL - PADRÕES ACADÊMICOS")  
        println("=" ^ 80)
        
        for result in all_results
            println(@sprintf("%s: %6.2f%% (Sharpe: %5.2f, t: %5.2f) %s",
                           result[:period], result[:mean_annual]*100, 
                           result[:sharpe], result[:t_stat], result[:significance]))
        end
        
        # Cross-period statistics
        annual_returns = [r[:mean_annual] for r in all_results]
        mean_across_periods = mean(annual_returns)
        t_stat_across = mean_across_periods / (std(annual_returns) / sqrt(length(annual_returns)))
        
        println("\n" * ("-" ^ 60))
        println(@sprintf("MÉDIA CROSS-PERIOD: %6.2f%% (t = %5.2f)", mean_across_periods*100, t_stat_across))
        
        if abs(t_stat_across) > 1.96
            println("RESULTADO: Anomalia estatisticamente significativa")
        else
            println("RESULTADO: Anomalia NÃO significativa (confirma Novy-Marx)")
        end
    end
    
    return all_results
end

# Execute academic analysis
results = run_academic_analysis()