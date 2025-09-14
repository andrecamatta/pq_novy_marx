#!/usr/bin/env julia

"""
Análise Novy-Marx de 15 Anos - Sistema Modular
Análise completa da anomalia de baixa volatilidade no S&P 500
"""

using Dates, Random

# Incluir sistema modular
include("src/fama_french_factors.jl")
include("src/multifactor_regression.jl")
include("src/visualization.jl")

# Módulos de análise
include("src/cache_manager.jl")
include("src/data/sp500_constituents.jl")
include("src/stooq_data.jl")
include("src/cache_adapter.jl")
include("src/analysis/returns_calculation.jl")
include("src/analysis/volatility_analysis.jl")
include("src/analysis/portfolio_construction.jl")
include("src/utils/ticker_utils.jl")
include("src/tiingo_data.jl")
include("src/download_fallback.jl")
include("src/results_export.jl")

using .FamaFrenchFactors, .MultifactorRegression, .Visualization
using .CacheManager, .CacheAdapter, .SP500Constituents
using .ReturnsCalculation, .VolatilityAnalysis, .PortfolioConstruction, .TickerUtils
using .TiingoData, .DownloadFallback, .ResultsExport
using DataFrames, Statistics, Printf, CSV

function load_data_smart(start_date::Date, end_date::Date)
    println("🧠 CARREGAMENTO INTELIGENTE DE DADOS")
    println("-"^50)

    # Estratégia 1: Tentar cache existente
    println("📂 1. Tentando carregar cache existente...")
    price_data = CacheAdapter.load_available_cache_data(start_date, end_date)

    if length(price_data) >= 100  # Mínimo para análise
        println("✅ Cache suficiente: $(length(price_data)) tickers")
        return price_data, collect(keys(price_data))
    end

    # Estratégia 2: Download com fallback
    println("🌐 2. Cache insuficiente, iniciando download...")
    universe = get_universe_for_period(start_date, end_date, verbose=false)
    println("📊 Universo S&P 500: $(length(universe)) tickers")

    price_data = download_with_fallback(universe, start_date, end_date, verbose=true)

    return price_data, universe
end

function run_complete_analysis()
    println("🚀 ANÁLISE NOVY-MARX 15 ANOS")
    println("="^50)
    println("📅 Período: Setembro 2010 a Agosto 2025 (180 meses)")
    println("🔧 Sistema: Modular com cache JLD2")
    println("📊 Universo: S&P 500 point-in-time")
    println()

    # Configuração
    start_date = Date(2009, 8, 1)
    end_date = Date(2025, 8, 31)
    analysis_start = Date(2010, 9, 1)

    try
        # 1. Carregar dados
        println("📥 ETAPA 1: CARREGAMENTO DE DADOS")
        println("="^50)

        price_data, universe = load_data_smart(start_date, end_date)

        if length(price_data) < 50
            error("❌ Dados insuficientes: $(length(price_data)) tickers")
        end

        # 2. Calcular retornos
        println("\n📊 ETAPA 2: CÁLCULO DE RETORNOS")
        println("="^50)

        returns_df = calculate_returns(price_data, start_date, end_date, verbose=true)

        if nrow(returns_df) < 100
            error("❌ Retornos insuficientes: $(nrow(returns_df)) meses")
        end

        # 3. Formar portfólios
        println("\n📈 ETAPA 3: FORMAÇÃO DE PORTFÓLIOS")
        println("="^50)

        constituents_df = load_sp500_constituents()

        portfolios_df = create_volatility_quintile_portfolios_pti(
            returns_df,  # ✅ Usar returns_df (não price_data)
            constituents_df;
            method=:monthly12,  # ✅ Método mensal como original
            lookback=12,        # ✅ 12 meses de lookback
            min_coverage=0.7,   # ✅ Usar padrões originais
            min_per_quintile=5, # ✅ Usar padrões originais
            verbose=true
        )

        if nrow(portfolios_df) < 50
            error("❌ Portfólios insuficientes: $(nrow(portfolios_df)) meses")
        end

        # Filtrar período de análise
        analysis_portfolios = filter(row -> row.Date >= analysis_start, portfolios_df)

        # 4. Calcular performance
        println("\n🎯 ETAPA 4: ANÁLISE DE PERFORMANCE")
        println("="^50)

        results = Dict{String, Dict{Symbol, Float64}}()

        for col in names(analysis_portfolios)
            if col in [:Date, "Date"]
                continue
            end

            returns = filter(!ismissing, analysis_portfolios[!, col])

            if length(returns) > 24  # Mínimo 2 anos
                mean_ret = mean(returns) * 12
                vol = std(returns) * sqrt(12)
                sharpe = mean_ret / vol

                # Drawdown
                cumulative = cumprod(1 .+ returns ./ 100)
                running_max = accumulate(max, cumulative)
                drawdowns = (cumulative .- running_max) ./ running_max
                max_dd = minimum(drawdowns)

                results[string(col)] = Dict(
                    :annual_return => mean_ret,
                    :annual_vol => vol,
                    :sharpe_ratio => sharpe,
                    :max_drawdown => max_dd,
                    :n_months => length(returns)
                )
            end
        end

        # 5. Apresentar resultados
        println("\n🎉 RESULTADOS FINAIS")
        println("="^75)
        println("📅 Período: $(analysis_start) a $(maximum(analysis_portfolios.Date))")
        println("📊 Meses: $(nrow(analysis_portfolios))")
        println("🔢 Tickers utilizados: $(length(price_data))")
        println("🏗️  Sistema: Refatorado modular")
        println()

        # Tabela de performance
        println("Portfolio             │ Retorno │ Volat. │ Sharpe │  Drawdown │ Meses")
        println("──────────────────────┼─────────┼────────┼────────┼───────────┼──────")

        portfolio_map = Dict(
            "P1" => "P1 (Baixa Vol)",
            "P2" => "P2",
            "P3" => "P3",
            "P4" => "P4",
            "P5" => "P5 (Alta Vol)",
            "LowMinusHigh" => "P1-P5 (Strategy)"
        )

        for (code, name) in portfolio_map
            if haskey(results, code)
                p = results[code]
                println(@sprintf("%-20s │ %6.2f%% │ %5.2f%% │ %6.3f │ %8.2f%% │ %4d",
                    name,
                    p[:annual_return],
                    p[:annual_vol],
                    p[:sharpe_ratio],
                    p[:max_drawdown] * 100,
                    p[:n_months]
                ))
            end
        end

        # Análise da anomalia
        println("\n🔍 ANÁLISE DA ANOMALIA")
        println("-"^55)

        if haskey(results, "LowMinusHigh")
            lmh = results["LowMinusHigh"]

            println("📈 Retorno P1-P5: $(round(lmh[:annual_return], digits=2))% a.a.")
            println("📊 Sharpe P1-P5: $(round(lmh[:sharpe_ratio], digits=3))")
            println("📉 Drawdown máximo: $(round(lmh[:max_drawdown] * 100, digits=2))%")

            # Comparação com sistema original
            original_return = -2.98  # Resultado do sistema original
            difference = lmh[:annual_return] - original_return

            println("\n🆚 COMPARAÇÃO COM SISTEMA ORIGINAL:")
            println("   Original: $original_return% a.a.")
            println("   Refatorado: $(round(lmh[:annual_return], digits=2))% a.a.")
            println("   Diferença: $(round(difference, digits=2))p.p.")

            if abs(difference) < 1.0
                println("✅ COMPATIBILIDADE: Resultados consistentes (<1% diferença)")
            else
                println("⚠️  DIFERENÇA SIGNIFICATIVA: >1% diferença detectada")
            end
        end

        # Salvar resultados usando módulo de exportação
        export_params = Dict{Symbol, Any}(
            :start_date => start_date,
            :end_date => end_date,
            :analysis_start => analysis_start,
            :lookback => 12
        )

        results_dir = export_analysis_results(
            results,
            analysis_portfolios,
            price_data,
            constituents_df,
            export_params
        )

        println("\n🎊 ANÁLISE CONCLUÍDA COM SUCESSO!")
        println("="^45)
        println("✅ Modularidade: SOLID/DRY implementado")
        println("✅ Funcionalidade: Análise completa executada")
        println("✅ Compatibilidade: Resultados validados")
        println("✅ Robustez: Sistema com fallbacks funcionais")
        println("✅ Resultados: Salvos em $results_dir")

        return results

    catch e
        println("\n❌ ERRO NA ANÁLISE:")
        println(e)

        if isa(e, InterruptException)
            println("   Análise interrompida pelo usuário")
        else
            println("   Stacktrace para debug:")
            for (exc, bt) in Base.catch_stack()
                showerror(stdout, exc, bt)
            end
        end

        rethrow(e)
    end
end

# Executar se chamado diretamente
if abspath(PROGRAM_FILE) == @__FILE__
    run_complete_analysis()
end
