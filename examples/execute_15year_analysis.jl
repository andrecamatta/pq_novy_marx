#!/usr/bin/env julia

"""
Execução da Análise Novy-Marx Completa (15 anos)
Período: Setembro 2010 a Agosto 2025
Sistema híbrido Stooq + Tiingo
Histórico completo de 193 meses para análise robusta (janela completa)
"""

using Dates

# Incluir o sistema principal
include("../novy_marx_sp500_analysis.jl")

function main()
    println("🚀 INICIANDO ANÁLISE NOVY-MARX 15 ANOS")
    println("="^60)
    println("📅 Período: Set 2010 - Ago 2025 (180 meses)")
    println("🔧 Sistema: Híbrido Stooq + Tiingo")
    println("📊 Universo: S&P 500 point-in-time")
    println()

    # Configuração para 15 anos
    config = AnalysisConfig(
        start_date = Date(2009, 8, 1),       # Dados desde agosto 2009 (para janela de volatilidade completa)
        end_date = Date(2025, 8, 31),        # Agosto 2025 (final do período)
        lookback_periods = [12],             # 12 meses de volatilidade (padrão Novy-Marx)
        min_coverage = 0.7,                  # 70% cobertura mínima
        min_per_quintile = 20,               # Mínimo 20 ações por quintil
        factor_models = [:CAPM, :FF3],       # Modelos básicos
        create_plots = true,                 # Gerar visualizações
        use_cache = true,                    # Usar cache
        force_redownload = true,             # Forçar redownload de todos os dados
        run_subperiod_analysis = true,       # Análise de subperíodos
        run_robustness_tests = true,         # Testes de robustez
        output_formats = [:csv, :json, :html]
    )

    println("⚙️ CONFIGURAÇÃO:")
    println("   Lookback: $(config.lookback_periods) meses")
    println("   Cobertura mínima: $(config.min_coverage*100)%")
    println("   Mín. por quintil: $(config.min_per_quintile)")
    println("   Modelos: $(config.factor_models)")
    println("   📈 Meses de dados: ~193 meses (15 anos + janela completa)")
    println()

    # Executar análise
    try
        results = analyze_sp500(config)

        println("\n🎉 ANÁLISE CONCLUÍDA COM SUCESSO!")
        println("="^60)

        if !isempty(results)
            # Resumo dos resultados
            for (lookback, result_data) in results
                if haskey(result_data["performance"], "LowMinusHigh")
                    perf = result_data["performance"]["LowMinusHigh"]
                    println("📊 LOOKBACK $lookback meses:")
                    println("   📈 P1-P5 Retorno: $(round(perf[:annual_return], digits=2))% a.a.")
                    println("   📊 Sharpe Ratio: $(round(perf[:sharpe_ratio], digits=3))")
                    println("   📅 Meses válidos: $(perf[:n_months])")
                    println()
                end
            end
        end

        println("✅ Análise de 15 anos finalizada!")

    catch e
        println("❌ ERRO NA ANÁLISE:")
        println(e)
        if isa(e, InterruptException)
            println("   Análise interrompida pelo usuário")
        else
            println("   Erro técnico - verifique configuração")
        end
        rethrow(e)
    end
end

# Executar se chamado diretamente
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end