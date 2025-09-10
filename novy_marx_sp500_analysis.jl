"""
Sistema Unificado de Análise Novy-Marx S&P 500
Análise completa da anomalia de baixa volatilidade com todas as funcionalidades
"""

using Pkg
Pkg.activate(".")

# Importar módulos
include("src/market_data.jl")
include("src/fama_french_factors.jl")
include("src/multifactor_regression.jl")
include("src/visualization.jl")
using .MarketData, .FamaFrenchFactors, .MultifactorRegression, .Visualization
using DataFrames, Dates, Statistics, Printf, CSV, JSON, JLD2
using ProgressMeter

# ================================================================================
# ESTRUTURA DE CONFIGURAÇÃO
# ================================================================================

"""
Configuração completa para análise
"""
Base.@kwdef struct AnalysisConfig
    # Período de análise
    start_date::Date = Date(2020, 1, 1)
    end_date::Date = Date(2024, 10, 31)
    
    # Parâmetros metodológicos
    lookback_periods::Vector{Int} = [12]  # Múltiplas janelas de volatilidade
    min_coverage::Float64 = 0.6
    min_per_quintile::Int = 5
    
    # Universo
    use_sp500::Bool = true
    custom_tickers::Vector{String} = String[]
    
    # Modelos de fatores
    factor_models::Vector{Symbol} = [:CAPM, :FF3, :FF5]
    
    # Output
    output_dir::String = "results"
    output_formats::Vector{Symbol} = [:csv, :json, :html]
    create_plots::Bool = true
    
    # Cache e performance
    cache_dir::String = "data/cache"
    use_cache::Bool = true
    force_redownload::Bool = false
    batch_size::Int = 100
    
    # Análises adicionais
    run_subperiod_analysis::Bool = true
    run_sector_analysis::Bool = false
    run_robustness_tests::Bool = true
end

# ================================================================================
# FUNÇÕES DE DOWNLOAD E CACHE
# ================================================================================

"""
Download inteligente com múltiplas APIs e cache persistente
"""
function download_universe_data(config::AnalysisConfig)
    println("\n📥 DOWNLOAD DE DADOS")
    println("="^60)
    
    # Determinar universo
    if config.use_sp500
        universe = extract_sp500_universe(config.start_date, config.end_date)
        println("📊 Universo S&P 500: $(length(universe)) tickers")
    else
        universe = config.custom_tickers
        println("📊 Universo customizado: $(length(universe)) tickers")
    end
    
    # Cache file
    cache_key = string(hash((universe, config.start_date, config.end_date)))
    cache_file = joinpath(config.cache_dir, "data_$(cache_key).jld2")
    
    # Verificar cache
    if config.use_cache && !config.force_redownload && isfile(cache_file)
        println("📂 Carregando do cache: $cache_file")
        try
            data = JLD2.load(cache_file)
            println("✅ Cache carregado: $(length(data["price_data"])) tickers")
            return data["price_data"], universe
        catch e
            println("⚠️  Erro no cache, fazendo download: $e")
        end
    end
    
    # Download com progress bar
    println("🌐 Iniciando download de $(length(universe)) tickers...")
    
    price_data = Dict{String, DataFrame}()
    failed_tickers = String[]
    
    # Progress bar
    p = Progress(length(universe), desc="Baixando dados: ")
    
    # Download em batches
    for i in 1:config.batch_size:length(universe)
        batch_end = min(i + config.batch_size - 1, length(universe))
        batch = universe[i:batch_end]
        
        try
            batch_data = download_stock_data(
                batch,
                config.start_date,
                config.end_date,
                verbose=false
            )
            merge!(price_data, batch_data)
            
            # Atualizar progress
            for _ in 1:length(batch)
                next!(p)
            end
            
            # Pausa entre batches
            if batch_end < length(universe)
                sleep(1)
            end
        catch e
            append!(failed_tickers, batch)
            for _ in 1:length(batch)
                next!(p)
            end
        end
    end
    
    finish!(p)
    
    # Estatísticas
    success_rate = length(price_data) / length(universe) * 100
    println("\n📊 Download concluído:")
    println("   ✅ Sucesso: $(length(price_data)) tickers ($(round(success_rate, digits=1))%)")
    println("   ❌ Falhou: $(length(failed_tickers)) tickers")
    
    # Salvar cache
    if config.use_cache && length(price_data) > 0
        mkpath(config.cache_dir)
        try
            JLD2.save(cache_file, Dict(
                "price_data" => price_data,
                "universe" => universe,
                "timestamp" => now()
            ))
            println("   💾 Cache salvo: $cache_file")
        catch e
            println("   ⚠️  Erro ao salvar cache: $e")
        end
    end
    
    return price_data, universe
end

"""
Extrai universo S&P 500 para período
"""
function extract_sp500_universe(start_date::Date, end_date::Date)
    sp500_file = "data/sp_500_historical_components.csv"
    sp500_data = CSV.read(sp500_file, DataFrame)
    sp500_data.date = Date.(sp500_data.date)
    
    period_data = filter(row -> start_date <= row.date <= end_date, sp500_data)
    
    all_tickers = Set{String}()
    for row in eachrow(period_data)
        if !ismissing(row.tickers)
            for ticker in split(row.tickers, ",")
                push!(all_tickers, strip(ticker))
            end
        end
    end
    
    return sort(collect(all_tickers))
end

# ================================================================================
# ANÁLISE PRINCIPAL
# ================================================================================

"""
Executa análise completa com múltiplas configurações
"""
function run_complete_analysis(config::AnalysisConfig = AnalysisConfig())
    println("\n🚀 ANÁLISE COMPLETA NOVY-MARX S&P 500")
    println("="^70)
    println("📅 Período: $(config.start_date) → $(config.end_date)")
    println("🔍 Lookback periods: $(config.lookback_periods)")
    println("📊 Modelos: $(join(config.factor_models, ", "))")
    println()
    
    # Criar estrutura de diretórios
    period_str = "$(config.start_date)_to_$(config.end_date)"
    output_dir = joinpath(config.output_dir, period_str)
    mkpath(output_dir)
    mkpath(joinpath(output_dir, "figures"))
    
    # 1. Download de dados
    price_data, universe = download_universe_data(config)
    
    if isempty(price_data)
        error("❌ Nenhum dado obtido. Verifique conectividade.")
    end
    
    # 2. Calcular retornos
    println("\n📊 PROCESSAMENTO DE DADOS")
    println("="^40)
    returns_df = calculate_returns(price_data, config.start_date, config.end_date, verbose=false)
    println("✅ Retornos calculados: $(nrow(returns_df)) meses × $(ncol(returns_df)-1) tickers")
    
    # 3. Análise para cada lookback period
    all_results = Dict{Int, Any}()
    
    for lookback in config.lookback_periods
        println("\n🔍 ANÁLISE COM LOOKBACK = $lookback MESES")
        println("-"^50)
        
        # Formar quintis
        portfolios_df = create_volatility_quintile_portfolios_pti(
            returns_df,
            method=:monthly12,
            price_data=price_data,
            lookback=lookback,
            min_coverage=config.min_coverage,
            min_per_quintile=config.min_per_quintile,
            verbose=false
        )
        
        if nrow(portfolios_df) == 0
            println("⚠️  Sem dados suficientes para lookback=$lookback")
            continue
        end
        
        println("✅ Quintis formados: $(nrow(portfolios_df)) meses")
        
        # Calcular performance
        performance = calculate_portfolio_performance(portfolios_df)
        
        # Análise de fatores
        factor_results = if length(config.factor_models) > 0
            analyze_factor_models(portfolios_df, config)
        else
            nothing
        end
        
        # Armazenar resultados
        all_results[lookback] = Dict(
            "portfolios" => portfolios_df,
            "performance" => performance,
            "factor_results" => factor_results,
            "lookback" => lookback
        )
        
        # Salvar resultados parciais
        save_results(portfolios_df, performance, factor_results, output_dir, lookback, config)
    end
    
    # 4. Análises adicionais
    if config.run_subperiod_analysis && !isempty(all_results)
        println("\n📊 ANÁLISE DE SUBPERÍODOS")
        println("-"^40)
        subperiod_results = analyze_subperiods(all_results, config)
        save_subperiod_analysis(subperiod_results, output_dir)
    end
    
    if config.run_robustness_tests && !isempty(all_results)
        println("\n🧪 TESTES DE ROBUSTEZ")
        println("-"^40)
        robustness_results = run_robustness_tests(all_results, config)
        save_robustness_tests(robustness_results, output_dir)
    end
    
    # 5. Criar visualizações
    if config.create_plots && !isempty(all_results)
        println("\n📈 CRIANDO VISUALIZAÇÕES")
        println("-"^30)
        create_all_visualizations(all_results, output_dir)
    end
    
    # 6. Gerar relatório final
    println("\n📝 GERANDO RELATÓRIO FINAL")
    println("-"^30)
    generate_final_report(all_results, config, output_dir)
    
    println("\n✅ ANÁLISE COMPLETA!")
    println("📂 Resultados salvos em: $output_dir")
    
    return all_results
end

# ================================================================================
# CÁLCULOS DE PERFORMANCE
# ================================================================================

"""
Calcula métricas de performance para todos os portfólios
"""
function calculate_portfolio_performance(portfolios_df::DataFrame)
    results = Dict{String, Dict{Symbol, Float64}}()
    
    for col in [:P1, :P2, :P3, :P4, :P5, :LowMinusHigh]
        returns = filter(!ismissing, portfolios_df[!, col])
        
        if !isempty(returns)
            # Métricas básicas
            mean_ret = mean(returns) * 12
            vol = std(returns) * sqrt(12)
            sharpe = mean_ret / vol
            
            # Métricas adicionais
            sortino = mean_ret / (std(filter(x -> x < 0, returns .- mean(returns))) * sqrt(12))
            max_dd = maximum_drawdown(returns)
            calmar = mean_ret / abs(max_dd)
            
            # Estatísticas
            skew = length(returns) > 3 ? skewness(returns) : NaN
            kurt = length(returns) > 3 ? kurtosis(returns) : NaN
            
            results[string(col)] = Dict(
                :annual_return => mean_ret,
                :annual_vol => vol,
                :sharpe_ratio => sharpe,
                :sortino_ratio => sortino,
                :max_drawdown => max_dd,
                :calmar_ratio => calmar,
                :skewness => skew,
                :kurtosis => kurt,
                :n_months => length(returns)
            )
        end
    end
    
    return results
end

"""
Calcula drawdown máximo
"""
function maximum_drawdown(returns::Vector{Float64})
    cumulative = cumprod(1 .+ returns)
    running_max = accumulate(max, cumulative)
    drawdowns = (cumulative .- running_max) ./ running_max
    return minimum(drawdowns)
end

# Função helper para skewness
function skewness(x::Vector{Float64})
    n = length(x)
    m = mean(x)
    s = std(x)
    return sum(((x .- m) ./ s).^3) / n
end

# Função helper para kurtosis
function kurtosis(x::Vector{Float64})
    n = length(x)
    m = mean(x)
    s = std(x)
    return sum(((x .- m) ./ s).^4) / n - 3
end

# ================================================================================
# ANÁLISE DE FATORES
# ================================================================================

"""
Analisa modelos de fatores configurados
"""
function analyze_factor_models(portfolios_df::DataFrame, config::AnalysisConfig)
    # Download fatores
    factors_df = download_fama_french_factors(
        minimum(portfolios_df.Date),
        maximum(portfolios_df.Date),
        verbose=false
    )
    
    if nrow(factors_df) == 0
        return nothing
    end
    
    results = Dict{Symbol, Any}()
    
    for model in config.factor_models
        try
            if model == :CAPM
                results[:CAPM] = run_capm_analysis(portfolios_df, factors_df)
            elseif model == :FF3
                results[:FF3] = run_ff3_analysis(portfolios_df, factors_df)
            elseif model == :FF5
                results[:FF5] = run_ff5_analysis(portfolios_df, factors_df)
            end
        catch e
            println("⚠️  Erro em $model: $e")
        end
    end
    
    return results
end

"""
Análise CAPM
"""
function run_capm_analysis(portfolios_df::DataFrame, factors_df::DataFrame)
    results = Dict()
    
    for col in [:P1, :P2, :P3, :P4, :P5, :LowMinusHigh]
        try
            result = analyze_portfolio_alphas_aligned(
                portfolios_df, factors_df, string(col), string(col)
            )
            results[col] = result.capm_result
        catch e
            results[col] = nothing
        end
    end
    
    return results
end

"""
Análise FF3
"""
function run_ff3_analysis(portfolios_df::DataFrame, factors_df::DataFrame)
    results = Dict()
    
    for col in [:P1, :P2, :P3, :P4, :P5, :LowMinusHigh]
        try
            result = analyze_portfolio_alphas_aligned(
                portfolios_df, factors_df, string(col), string(col)
            )
            results[col] = result.ff3_result
        catch e
            results[col] = nothing
        end
    end
    
    return results
end

"""
Análise FF5
"""
function run_ff5_analysis(portfolios_df::DataFrame, factors_df::DataFrame)
    results = Dict()
    
    for col in [:P1, :P2, :P3, :P4, :P5, :LowMinusHigh]
        try
            result = analyze_portfolio_alphas_aligned(
                portfolios_df, factors_df, string(col), string(col)
            )
            results[col] = result.ff5_result
        catch e
            results[col] = nothing
        end
    end
    
    return results
end

# ================================================================================
# ANÁLISES ADICIONAIS
# ================================================================================

"""
Análise de subperíodos
"""
function analyze_subperiods(all_results::Dict, config::AnalysisConfig)
    # Dividir período em metades
    mid_date = config.start_date + Day(Int((config.end_date - config.start_date).value / 2))
    
    subperiod_results = Dict()
    
    for (lookback, results) in all_results
        portfolios_df = results["portfolios"]
        
        # Primeira metade
        first_half = filter(row -> row.Date <= mid_date, portfolios_df)
        if nrow(first_half) > 12
            subperiod_results["first_half_$lookback"] = calculate_portfolio_performance(first_half)
        end
        
        # Segunda metade
        second_half = filter(row -> row.Date > mid_date, portfolios_df)
        if nrow(second_half) > 12
            subperiod_results["second_half_$lookback"] = calculate_portfolio_performance(second_half)
        end
    end
    
    return subperiod_results
end

"""
Testes de robustez
"""
function run_robustness_tests(all_results::Dict, config::AnalysisConfig)
    robustness = Dict()
    
    # Teste 1: Consistência entre lookback periods
    if length(config.lookback_periods) > 1
        correlations = Dict()
        lookbacks = sort(collect(keys(all_results)))
        
        for i in 1:(length(lookbacks)-1)
            for j in (i+1):length(lookbacks)
                lb1, lb2 = lookbacks[i], lookbacks[j]
                port1 = all_results[lb1]["portfolios"]
                port2 = all_results[lb2]["portfolios"]
                
                # Alinhar datas
                common_dates = intersect(port1.Date, port2.Date)
                if length(common_dates) > 12
                    p1_aligned = filter(row -> row.Date in common_dates, port1)
                    p2_aligned = filter(row -> row.Date in common_dates, port2)
                    
                    if nrow(p1_aligned) > 0 && nrow(p2_aligned) > 0
                        corr = cor(
                            filter(!ismissing, p1_aligned.LowMinusHigh),
                            filter(!ismissing, p2_aligned.LowMinusHigh)
                        )
                        correlations["$(lb1)_vs_$(lb2)"] = corr
                    end
                end
            end
        end
        
        robustness["lookback_correlations"] = correlations
    end
    
    # Teste 2: Estabilidade temporal (rolling window)
    for (lookback, results) in all_results
        portfolios_df = results["portfolios"]
        
        if nrow(portfolios_df) >= 36  # Mínimo 3 anos
            rolling_sharpes = Float64[]
            rolling_dates = Date[]
            
            for i in 12:(nrow(portfolios_df)-11)
                window = portfolios_df[i:(i+11), :]
                returns = filter(!ismissing, window.LowMinusHigh)
                
                if length(returns) >= 6
                    sharpe = mean(returns) * 12 / (std(returns) * sqrt(12))
                    push!(rolling_sharpes, sharpe)
                    push!(rolling_dates, window.Date[end])
                end
            end
            
            if length(rolling_sharpes) > 0
                robustness["rolling_sharpe_$lookback"] = Dict(
                    "dates" => rolling_dates,
                    "sharpes" => rolling_sharpes,
                    "mean" => mean(rolling_sharpes),
                    "std" => std(rolling_sharpes),
                    "min" => minimum(rolling_sharpes),
                    "max" => maximum(rolling_sharpes)
                )
            end
        end
    end
    
    return robustness
end

# ================================================================================
# SALVAMENTO DE RESULTADOS
# ================================================================================

"""
Salva resultados em múltiplos formatos
"""
function save_results(portfolios_df::DataFrame, performance::Dict, 
                      factor_results, output_dir::String, lookback::Int, 
                      config::AnalysisConfig)
    
    # CSV - Portfólios
    if :csv in config.output_formats
        csv_file = joinpath(output_dir, "portfolios_lookback_$(lookback).csv")
        CSV.write(csv_file, portfolios_df)
        println("   💾 CSV: $csv_file")
    end
    
    # JSON - Performance e fatores
    if :json in config.output_formats
        json_data = Dict(
            "lookback" => lookback,
            "period" => Dict(
                "start" => string(config.start_date),
                "end" => string(config.end_date)
            ),
            "performance" => performance,
            "factor_results" => factor_results
        )
        
        json_file = joinpath(output_dir, "results_lookback_$(lookback).json")
        open(json_file, "w") do io
            JSON.print(io, json_data, 2)
        end
        println("   💾 JSON: $json_file")
    end
    
    # HTML - Tabela formatada
    if :html in config.output_formats
        html_file = joinpath(output_dir, "report_lookback_$(lookback).html")
        generate_html_report(portfolios_df, performance, factor_results, html_file, lookback)
        println("   💾 HTML: $html_file")
    end
end

"""
Salva análise de subperíodos
"""
function save_subperiod_analysis(results::Dict, output_dir::String)
    json_file = joinpath(output_dir, "subperiod_analysis.json")
    open(json_file, "w") do io
        JSON.print(io, results, 2)
    end
    println("   💾 Subperíodos: $json_file")
end

"""
Salva testes de robustez
"""
function save_robustness_tests(results::Dict, output_dir::String)
    json_file = joinpath(output_dir, "robustness_tests.json")
    open(json_file, "w") do io
        JSON.print(io, results, 2)
    end
    println("   💾 Robustez: $json_file")
end

# ================================================================================
# VISUALIZAÇÕES
# ================================================================================

"""
Cria todas as visualizações
"""
function create_all_visualizations(all_results::Dict, output_dir::String)
    figures_dir = joinpath(output_dir, "figures")
    
    for (lookback, results) in all_results
        portfolios_df = results["portfolios"]
        performance = results["performance"]
        
        # Plot 1: Retornos cumulativos
        plot_cumulative_returns(portfolios_df, joinpath(figures_dir, "cumulative_lb$(lookback).png"))
        
        # Plot 2: Rolling Sharpe
        plot_rolling_metrics(portfolios_df, joinpath(figures_dir, "rolling_sharpe_lb$(lookback).png"))
        
        # Plot 3: Comparação de quintis
        plot_quintile_comparison(performance, joinpath(figures_dir, "quintiles_lb$(lookback).png"))
        
        # Plot 4: Factor loadings (se disponível)
        if results["factor_results"] !== nothing
            plot_factor_loadings(results["factor_results"], joinpath(figures_dir, "factors_lb$(lookback).png"))
        end
    end
    
    println("   📈 Visualizações criadas em: $figures_dir")
end

# ================================================================================
# RELATÓRIO FINAL
# ================================================================================

"""
Gera relatório HTML final consolidado
"""
function generate_html_report(portfolios_df::DataFrame, performance::Dict, 
                             factor_results, filename::String, lookback::Int)
    
    html = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Novy-Marx Analysis - Lookback $lookback months</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; }
            h1 { color: #2c3e50; }
            h2 { color: #34495e; border-bottom: 2px solid #ecf0f1; padding-bottom: 10px; }
            table { border-collapse: collapse; width: 100%; margin: 20px 0; }
            th, td { border: 1px solid #ddd; padding: 12px; text-align: right; }
            th { background-color: #3498db; color: white; }
            tr:nth-child(even) { background-color: #f2f2f2; }
            .metric { font-size: 24px; font-weight: bold; color: #2980b9; }
            .positive { color: #27ae60; }
            .negative { color: #e74c3c; }
        </style>
    </head>
    <body>
        <h1>Novy-Marx Low Volatility Analysis</h1>
        <h2>Configuration</h2>
        <p>Lookback Period: <span class="metric">$lookback months</span></p>
        <p>Analysis Period: $(minimum(portfolios_df.Date)) to $(maximum(portfolios_df.Date))</p>
        <p>Total Months: <span class="metric">$(nrow(portfolios_df))</span></p>
        
        <h2>Portfolio Performance (Annualized)</h2>
        <table>
            <tr>
                <th>Portfolio</th>
                <th>Return (%)</th>
                <th>Volatility (%)</th>
                <th>Sharpe Ratio</th>
                <th>Max Drawdown (%)</th>
            </tr>
    """
    
    for (name, metrics) in performance
        ret_class = metrics[:annual_return] > 0 ? "positive" : "negative"
        html *= """
            <tr>
                <td><strong>$name</strong></td>
                <td class="$ret_class">$(round(metrics[:annual_return], digits=2))</td>
                <td>$(round(metrics[:annual_vol], digits=2))</td>
                <td>$(round(metrics[:sharpe_ratio], digits=3))</td>
                <td>$(round(metrics[:max_drawdown] * 100, digits=2))</td>
            </tr>
        """
    end
    
    html *= """
        </table>
        
        <h2>Low Volatility Anomaly</h2>
    """
    
    if haskey(performance, "LowMinusHigh")
        lmh = performance["LowMinusHigh"]
        anomaly_status = if lmh[:annual_return] > 2.0
            "<span class='positive'>STRONG ANOMALY DETECTED</span>"
        elseif lmh[:annual_return] > 0.0
            "<span class='positive'>WEAK ANOMALY DETECTED</span>"
        else
            "<span class='negative'>ANOMALY REVERSED</span>"
        end
        
        html *= """
        <p>P1 - P5 Annual Return: <span class="metric">$(round(lmh[:annual_return], digits=2))%</span></p>
        <p>P1 - P5 Sharpe Ratio: <span class="metric">$(round(lmh[:sharpe_ratio], digits=3))</span></p>
        <p>Status: $anomaly_status</p>
        """
    end
    
    html *= """
    </body>
    </html>
    """
    
    open(filename, "w") do io
        write(io, html)
    end
end

"""
Gera relatório final consolidado
"""
function generate_final_report(all_results::Dict, config::AnalysisConfig, output_dir::String)
    summary = Dict(
        "analysis_period" => Dict(
            "start" => string(config.start_date),
            "end" => string(config.end_date)
        ),
        "lookback_periods" => config.lookback_periods,
        "factor_models" => config.factor_models,
        "results_summary" => Dict()
    )
    
    for (lookback, results) in all_results
        if haskey(results["performance"], "LowMinusHigh")
            lmh = results["performance"]["LowMinusHigh"]
            summary["results_summary"][lookback] = Dict(
                "annual_return" => lmh[:annual_return],
                "sharpe_ratio" => lmh[:sharpe_ratio],
                "n_months" => lmh[:n_months]
            )
        end
    end
    
    # Salvar resumo final
    summary_file = joinpath(output_dir, "final_summary.json")
    open(summary_file, "w") do io
        JSON.print(io, summary, 2)
    end
    
    println("📊 Resumo final: $summary_file")
end

# ================================================================================
# FUNÇÃO PRINCIPAL
# ================================================================================

"""
Interface principal do sistema

Exemplos:
```julia
# Análise padrão 2020-2024
results = analyze_sp500()

# Análise customizada
config = AnalysisConfig(
    start_date = Date(2010, 1, 1),
    end_date = Date(2020, 12, 31),
    lookback_periods = [6, 12, 24],
    factor_models = [:CAPM, :FF3, :FF5],
    create_plots = true
)
results = analyze_sp500(config)
```
"""
function analyze_sp500(config::AnalysisConfig = AnalysisConfig())
    return run_complete_analysis(config)
end

# Atalho para análise rápida
function quick_analysis(start_date::Date, end_date::Date)
    config = AnalysisConfig(
        start_date = start_date,
        end_date = end_date,
        lookback_periods = [12],
        factor_models = [:CAPM],
        create_plots = false,
        run_subperiod_analysis = false,
        run_robustness_tests = false
    )
    return analyze_sp500(config)
end

# ================================================================================
# EXECUÇÃO
# ================================================================================

if abspath(PROGRAM_FILE) == @__FILE__
    println("🎯 Sistema Unificado Novy-Marx S&P 500")
    println("📖 Uso: results = analyze_sp500()")
    println("📖 Config: config = AnalysisConfig(start_date=Date(2020,1,1), end_date=Date(2024,10,31))")
    println("📖 Quick: results = quick_analysis(Date(2020,1,1), Date(2024,10,31))")
end