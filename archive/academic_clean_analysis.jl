using YFinance, DataFrames, Dates, Statistics, LinearAlgebra, CSV, Printf, HTTP

# Academic universe - S&P 500 historical constituents approximation
function get_academic_universe()
    return [
        # Technology
        "AAPL", "MSFT", "GOOGL", "AMZN", "META", "NVDA", "CRM", "ORCL", "ADBE", "NFLX",
        "CSCO", "INTC", "AMD", "QCOM", "IBM", "HPQ", "DELL", "VMW", "AMAT", "LRCX",
        
        # Financial
        "JPM", "BAC", "WFC", "C", "GS", "MS", "AXP", "BLK", "SCHW", "USB",
        "PNC", "TFC", "COF", "BK", "STT", "MTB", "RF", "KEY", "CFG", "FITB",
        
        # Healthcare
        "JNJ", "UNH", "PFE", "ABT", "TMO", "MDT", "DHR", "BMY", "AMGN", "GILD",
        "MRK", "LLY", "CVS", "CI", "ANTM", "HUM", "WLP", "ESRX", "CAH", "MCK",
        
        # Consumer
        "PG", "KO", "PEP", "WMT", "HD", "MCD", "DIS", "NKE", "SBUX", "TGT",
        "LOW", "TJX", "COST", "F", "GM", "TSLA", "CCL", "RCL", "MAR", "HLT",
        
        # Industrial  
        "BA", "GE", "CAT", "MMM", "HON", "UPS", "FDX", "LMT", "RTX", "NOC",
        "DE", "EMR", "ETN", "ITW", "PH", "CMI", "DOV", "FLR", "JCI", "IR",
        
        # Energy & Materials
        "XOM", "CVX", "COP", "SLB", "EOG", "KMI", "OXY", "PSX", "VLO", "MPC",
        "FCX", "NEM", "AA", "X", "CLF", "NUE", "STLD", "CMC", "RS", "WOR",
        
        # Utilities & Telecom
        "T", "VZ", "CMCSA", "S", "CTL", "FTR", "WIN", "DISH", "SIRI", "TMUS",
        "NEE", "DUK", "SO", "EXC", "XEL", "WEC", "ES", "ETR", "FE", "AEP"
    ]
end

# Download function with proper error handling
function download_academic_data(tickers, start_date, end_date)
    println("Download com padrões acadêmicos...")
    println("Período: $start_date a $end_date")
    println("Tickers: $(length(tickers))")
    
    price_data = DataFrame()
    success_count = 0
    
    for (i, ticker) in enumerate(tickers)
        try
            # Use YFinance with correct syntax
            data = get_prices(ticker, startdt=string(start_date), enddt=string(end_date))
            
            if nrow(data) >= 500  # Minimum 2 years of data
                data[!, :ticker] = ticker
                
                # Academic filters
                data = data[data.adjclose .> 5.0, :]  # Min $5 price
                data = data[.!ismissing.(data.adjclose), :]
                
                if nrow(data) >= 400  # Still sufficient after filtering
                    if isempty(price_data)
                        price_data = data
                    else
                        price_data = vcat(price_data, data, cols=:union)
                    end
                    success_count += 1
                end
            end
        catch e
            # Silent failure for missing data (natural delisting/survivorship)
        end
        
        if i % 10 == 0
            println("  Progresso: $i/$(length(tickers))")
        end
    end
    
    println("  Download concluído: $success_count/$(length(tickers)) sucessos")
    return price_data
end

# Academic volatility calculation
function calculate_academic_volatility(price_data::DataFrame, vol_window::Int64=252)
    println("Calculando volatilidade (padrão acadêmico)...")
    
    vol_data = DataFrame(ticker=String[], date=Date[], volatility=Float64[])
    
    processed = 0
    for gdf in groupby(price_data, :ticker)
        ticker = gdf.ticker[1]
        n = nrow(gdf)
        
        if n >= vol_window + 30  # Buffer for robust calculation
            # Log returns
            log_returns = [missing; diff(log.(gdf.adjclose))]
            
            # Filter extreme returns (academic standard)
            log_returns = [!ismissing(r) && abs(r) > log(3.0) ? missing : r for r in log_returns]
            
            # Rolling volatility calculation
            for i in (vol_window + 1):n
                window_returns = log_returns[i-vol_window+1:i]
                valid_returns = window_returns[.!ismissing.(window_returns)]
                
                if length(valid_returns) >= round(Int, vol_window * 0.8)  # 80% data availability
                    vol = std(valid_returns) * sqrt(252)  # Annualized
                    push!(vol_data, (ticker, gdf.timestamp[i], vol))
                end
            end
            processed += 1
        end
    end
    
    println("  Volatilidade calculada: $processed ações")
    return vol_data
end

# Portfolio formation with academic standards
function form_academic_portfolios(vol_data::DataFrame, price_data::DataFrame)
    println("Formação de portfolios (metodologia acadêmica)...")
    println("- Rebalanceamento mensal")
    println("- 1-month lag entre formação e investimento")
    println("- End-of-month prices")
    
    # Get end-of-month dates
    vol_monthly = combine(
        groupby(vol_data, [:ticker, Date.(year.(vol_data.date), month.(vol_data.date))]),
        :volatility => last => :volatility,
        :date => last => :date_end
    )
    rename!(vol_monthly, :date_function => :month)
    
    portfolio_data = DataFrame()
    months_formed = 0
    
    for month_group in groupby(vol_monthly, :month)
        month = month_group.month[1]
        
        if nrow(month_group) >= 20  # Academic minimum
            # Sort by volatility
            sort!(month_group, :volatility)
            n = nrow(month_group)
            
            # Quintile formation (academic standard)
            breakpoints = [0.2, 0.4, 0.6, 0.8, 1.0]
            month_group[!, :portfolio] = Int[]
            
            for i in 1:n
                rank_pct = i / n
                port = findfirst(bp -> rank_pct <= bp, breakpoints)
                push!(month_group.portfolio, port)
            end
            
            month_group[!, :form_month] = month
            portfolio_data = vcat(portfolio_data, month_group[:, [:ticker, :form_month, :portfolio]], cols=:union)
            months_formed += 1
        end
    end
    
    println("  Portfolios formados com $months_formed meses de dados")
    return portfolio_data
end

# Calculate monthly returns with 1-month lag
function calculate_monthly_returns(price_data::DataFrame, portfolio_data::DataFrame)
    println("Calculando retornos mensais...")
    
    # Monthly prices (end-of-month)
    monthly_prices = combine(
        groupby(price_data, [:ticker, Date.(year.(price_data.timestamp), month.(price_data.timestamp))]),
        :adjclose => last => :price,
        :timestamp => last => :date_end
    )
    rename!(monthly_prices, :timestamp_function => :month)
    
    # Calculate returns
    returns_data = DataFrame()
    
    for ticker_group in groupby(monthly_prices, :ticker)
        ticker = ticker_group.ticker[1]
        sort!(ticker_group, :month)
        
        if nrow(ticker_group) >= 2
            for i in 2:nrow(ticker_group)
                ret = ticker_group.price[i] / ticker_group.price[i-1] - 1
                
                push!(returns_data, (
                    ticker = ticker,
                    month = ticker_group.month[i],
                    ret = ret
                ))
            end
        end
    end
    
    # Apply 1-month lag: use portfolio assignment from previous month
    portfolio_data[!, :invest_month] = portfolio_data.form_month .+ Month(1)
    
    # Merge returns with lagged portfolio assignments
    portfolio_returns = leftjoin(returns_data, 
                                select(portfolio_data, :ticker, :invest_month => :month, :portfolio),
                                on = [:ticker, :month])
    
    # Calculate value-weighted portfolio returns (equal-weighted here for simplicity)
    monthly_portfolio_returns = combine(
        groupby(dropmissing(portfolio_returns, :portfolio), [:month, :portfolio]),
        :ret => mean => :portfolio_return
    )
    
    return monthly_portfolio_returns
end

# Calculate Long-Short returns
function calculate_long_short(monthly_returns::DataFrame)
    ls_returns = DataFrame()
    
    for month_group in groupby(monthly_returns, :month)
        month = month_group.month[1]
        
        p1_data = month_group[month_group.portfolio .== 1, :]  # Low volatility
        p5_data = month_group[month_group.portfolio .== 5, :]  # High volatility
        
        if nrow(p1_data) > 0 && nrow(p5_data) > 0
            ls_return = p1_data.portfolio_return[1] - p5_data.portfolio_return[1]
            push!(ls_returns, (month = month, ls_return = ls_return))
        end
    end
    
    return ls_returns
end

# Statistics calculation
function calculate_academic_statistics(returns::Vector{Float64}, name::String)
    n = length(returns)
    if n == 0
        println("Erro: Sem dados para $name")
        return nothing
    end
    
    mean_ret = mean(returns)
    std_ret = std(returns)
    t_stat = mean_ret / (std_ret / sqrt(n))
    
    # Additional metrics
    ann_ret = mean_ret * 12
    ann_vol = std_ret * sqrt(12)
    sharpe = mean_ret / std_ret
    
    # Risk metrics
    max_dd = 0.0
    cumulative = 0.0
    peak = 0.0
    
    for r in returns
        cumulative += r
        peak = max(peak, cumulative)
        drawdown = peak - cumulative
        max_dd = max(max_dd, drawdown)
    end
    
    downside_returns = returns[returns .< 0]
    downside_vol = isempty(downside_returns) ? 0.0 : std(downside_returns) * sqrt(12)
    win_rate = sum(returns .> 0) / n
    
    # Distribution
    skewness_val = sum(((returns .- mean_ret) / std_ret).^3) / n
    kurtosis_val = sum(((returns .- mean_ret) / std_ret).^4) / n - 3
    
    # P-value (approximate)
    p_val = 2 * (1 - (0.5 + 0.5 * tanh(abs(t_stat) * sqrt(pi/8))))
    significance = abs(t_stat) >= 2.58 ? "***" : abs(t_stat) >= 1.96 ? "**" : abs(t_stat) >= 1.65 ? "*" : "n.s."
    
    println("\n" * "="^60)
    println("ANÁLISE ACADÊMICA - $name")  
    println("="^60)
    
    println("\nRETURN STATISTICS:")
    @printf("  Months:              %3d\n", n)
    @printf("  Mean Monthly:       %6.3f%% (t = %5.2f)\n", mean_ret*100, t_stat)
    @printf("  Annualized:         %6.2f%%\n", ann_ret*100)
    @printf("  Volatility:         %6.2f%%\n", ann_vol*100)
    @printf("  Sharpe Ratio:       %7.3f\n", sharpe)
    @printf("  P-value:            %7.4f\n", p_val)
    @printf("  Significance:       %8s\n", significance)
    
    println("\nRISK METRICS:")
    @printf("  Maximum Drawdown:   %6.2f%%\n", max_dd*100)
    @printf("  Downside Volatility:%6.2f%%\n", downside_vol*100)
    @printf("  Win Rate:           %6.1f%%\n", win_rate*100)
    
    println("\nDISTRIBUTION:")
    @printf("  Skewness:           %7.3f\n", skewness_val)
    @printf("  Kurtosis:           %7.3f\n", kurtosis_val)
    @printf("  Min Monthly:        %6.2f%%\n", minimum(returns)*100)
    @printf("  Max Monthly:        %6.2f%%\n", maximum(returns)*100)
    
    return (
        mean_monthly = mean_ret,
        annualized = ann_ret,
        volatility = ann_vol,
        sharpe = sharpe,
        t_statistic = t_stat,
        p_value = p_val,
        significance = significance,
        months = n
    )
end

# Main analysis function for each period
function analyze_period(start_date, end_date, period_name)
    println("\n" * "="^80)
    println("PERÍODO: $period_name")
    println("="^80)
    
    # Get universe
    universe = get_academic_universe()
    println("Universo acadêmico: $(length(universe)) ações")
    
    # Download data
    price_data = download_academic_data(universe, start_date, end_date)
    
    if nrow(price_data) == 0
        println("ERRO: Nenhum dado baixado para o período $period_name")
        return nothing
    end
    
    # Calculate volatility
    vol_data = calculate_academic_volatility(price_data)
    
    if nrow(vol_data) == 0
        println("ERRO: Nenhuma volatilidade calculada para o período $period_name")
        return nothing
    end
    
    # Form portfolios
    portfolio_data = form_academic_portfolios(vol_data, price_data)
    
    if nrow(portfolio_data) == 0
        println("ERRO: Nenhum portfolio formado para o período $period_name")
        return nothing
    end
    
    # Calculate returns
    monthly_returns = calculate_monthly_returns(price_data, portfolio_data)
    
    if nrow(monthly_returns) == 0
        println("ERRO: Nenhum retorno calculado para o período $period_name")
        return nothing
    end
    
    # Long-Short analysis
    ls_returns = calculate_long_short(monthly_returns)
    
    if nrow(ls_returns) == 0
        println("ERRO: Nenhum retorno Long-Short para o período $period_name")
        return nothing
    end
    
    # Calculate statistics
    stats = calculate_academic_statistics(ls_returns.ls_return, period_name)
    
    # Save results
    CSV.write("academic_results_$(replace(period_name, "-" => "_")).csv", ls_returns)
    println("\n📊 Resultados salvos: academic_results_$(replace(period_name, "-" => "_")).csv")
    
    return stats
end

# Main execution
function run_clean_academic_analysis()
    println("="^80)
    println("ANÁLISE ACADÊMICA LIMPA - ANOMALIA DE BAIXA VOLATILIDADE")
    println("Metodologia: Baker, Bradley & Wurgler (2011) - Dados Reais YFinance")
    println("="^80)
    
    periods = [
        (Date(2000, 1, 1), Date(2009, 12, 31), "2000-2009"),
        (Date(2010, 1, 1), Date(2019, 12, 31), "2010-2019"),
        (Date(2020, 1, 1), Date(2024, 11, 30), "2020-2024")
    ]
    
    all_results = []
    
    for (start_date, end_date, period_name) in periods
        result = analyze_period(start_date, end_date, period_name)
        if !isnothing(result)
            push!(all_results, (period = period_name, stats = result))
        end
    end
    
    # Summary
    println("\n" * "="^80)
    println("RESUMO FINAL - CRÍTICA DE NOVY-MARX")
    println("="^80)
    
    total_significant = 0
    for (period, stats) in all_results
        is_sig = abs(stats.t_statistic) >= 1.96
        total_significant += is_sig
        
        println("$period: Return = $(round(stats.annualized*100, digits=1))%, t = $(round(stats.t_statistic, digits=2)), $(stats.significance)")
    end
    
    println("\nCONCLUSÃO:")
    if total_significant >= 2
        println("Anomalia persiste em múltiplos períodos - CONTRADIZ Novy-Marx")
    else
        println("Anomalia não é consistentemente significativa - CONFIRMA Novy-Marx")
    end
    
    return all_results
end

# Execute
results = run_clean_academic_analysis()