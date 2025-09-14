"""
Módulo para exportação de resultados em formato compatível com sistema legado
"""
module ResultsExport

using Dates, DataFrames, CSV, JSON, Statistics, Printf
using ..TickerUtils: clean_ticker_for_stooq
using Plots

export export_analysis_results

"""
    export_analysis_results(results, portfolios_df, price_data, constituents_df, params)

Exporta resultados da análise em estrutura organizada similar ao sistema legado
"""
function export_analysis_results(
    results::Dict{String, Dict{Symbol, Float64}},
    portfolios_df::DataFrame,
    price_data::Dict,
    constituents_df::DataFrame,
    params::Dict{Symbol, Any}
)
    # Extrair parâmetros
    start_date = get(params, :start_date, Date(2009, 8, 1))
    end_date = get(params, :end_date, Date(2025, 8, 31))
    analysis_start = get(params, :analysis_start, Date(2010, 9, 1))
    lookback = get(params, :lookback, 12)

    # Criar estrutura de diretórios
    base_dir = "results/$(Dates.format(start_date, "yyyy-mm-dd"))_to_$(Dates.format(end_date, "yyyy-mm-dd"))"
    mkpath(base_dir)
    mkpath(joinpath(base_dir, "figures"))

    println("\n💾 EXPORTANDO RESULTADOS")
    println("="^50)
    println("📁 Diretório: $base_dir")

    # 1. Calcular estatísticas de tickers dinamicamente
    failed_tickers, ticker_stats = calculate_ticker_statistics(
        price_data, constituents_df, start_date, end_date
    )

    # 2. Salvar portfolios CSV
    portfolios_file = joinpath(base_dir, "portfolios_lookback_$(lookback).csv")
    CSV.write(portfolios_file, portfolios_df)
    println("✅ Portfolios salvos: $(basename(portfolios_file))")

    # 3. Criar e salvar results JSON detalhado
    results_json = create_detailed_results(results, portfolios_df, lookback)
    results_file = joinpath(base_dir, "results_lookback_$(lookback).json")
    open(results_file, "w") do f
        JSON.print(f, results_json, 4)
    end
    println("✅ Resultados detalhados: $(basename(results_file))")

    # 4. Criar final_summary.json
    summary = Dict(
        "analysis_period" => Dict(
            "start" => Dates.format(start_date, "yyyy-mm-dd"),
            "end" => Dates.format(end_date, "yyyy-mm-dd")
        ),
        "ticker_statistics" => ticker_stats,
        "results_summary" => Dict(
            string(lookback) => Dict(
                "annual_return" => get(results, "LowMinusHigh", Dict(:annual_return => 0.0))[:annual_return],
                "sharpe_ratio" => get(results, "LowMinusHigh", Dict(:sharpe_ratio => 0.0))[:sharpe_ratio],
                "n_months" => Float64(nrow(portfolios_df))
            )
        ),
        "lookback_periods" => [lookback],
        "factor_models" => ["CAPM"]
    )

    summary_file = joinpath(base_dir, "final_summary.json")
    open(summary_file, "w") do f
        JSON.print(f, summary, 4)
    end
    println("✅ Resumo final: $(basename(summary_file))")

    # 5. Salvar relatório de tickers faltantes
    if !isempty(failed_tickers)
        failed_file = joinpath(base_dir, "failed_tickers_report.txt")
        open(failed_file, "w") do f
            println(f, "RELATÓRIO DE TICKERS FALTANTES")
            println(f, "="^50)
            println(f, "Data: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")
            println(f, "Total: $(length(failed_tickers)) tickers")
            println(f, "="^50)
            println(f)
            for ticker in sort(collect(failed_tickers))
                println(f, ticker)
            end
        end
        println("✅ Relatório de falhas: $(basename(failed_file))")
    end

    # 6. Gerar figuras
    figures_dir = joinpath(base_dir, "figures")
    mkpath(figures_dir)
    generate_analysis_figures(portfolios_df, results, figures_dir, params)

    # 7. Gerar relatório HTML
    html_file = joinpath(base_dir, "report_lookback_$(lookback).html")
    generate_html_report(results, portfolios_df, ticker_stats, html_file, params)
    println("✅ Relatório HTML: $(basename(html_file))")

    println("\n📊 RESUMO DA EXPORTAÇÃO:")
    println("   Total de tickers: $(ticker_stats["total_tickers"])")
    println("   Taxa de sucesso: $(round(ticker_stats["success_rate"], digits=1))%")
    println("   Tickers faltantes: $(length(failed_tickers))")
    println("   Figuras geradas: 4")
    println("   Arquivos gerados: 10+")

    return base_dir
end

"""
    calculate_ticker_statistics(price_data, constituents_df, start_date, end_date)

Calcula estatísticas de tickers dinamicamente baseado nos constituintes S&P 500
"""
function calculate_ticker_statistics(price_data, constituents_df, start_date, end_date)
    # Obter todos os tickers únicos do S&P 500 no período
    date_col = "date" in names(constituents_df) ? :date : :Date
    relevant_dates = filter(d -> start_date <= d <= end_date,
                           unique(constituents_df[!, date_col]))

    all_sp500_tickers = Set{String}()
    for date in relevant_dates
        date_row = filter(row -> row[date_col] == date, constituents_df)
        if nrow(date_row) > 0
            tickers_str = date_row[1, :tickers]
            for ticker_raw in split(string(tickers_str), ",")
                ticker = strip(replace(string(ticker_raw), r"\s*\(.*\)$" => ""))
                if !isempty(ticker)
                    # Normalizar para evitar mismatch de separadores ('.' vs '-')
                    push!(all_sp500_tickers, clean_ticker_for_stooq(string(ticker)))
                end
            end
        end
    end

    # Calcular interseção com dados disponíveis
    available_tickers = Set(clean_ticker_for_stooq(string(t)) for t in keys(price_data))
    successful_tickers = intersect(all_sp500_tickers, available_tickers)
    failed_tickers = setdiff(all_sp500_tickers, available_tickers)

    ticker_stats = Dict(
        "total_tickers" => length(all_sp500_tickers),
        "successful_tickers" => length(successful_tickers),
        "failed_tickers" => sort(collect(failed_tickers)),
        "failed_tickers_count" => length(failed_tickers),
        "success_rate" => length(successful_tickers) / length(all_sp500_tickers) * 100
    )

    return failed_tickers, ticker_stats
end

"""
    create_detailed_results(results, portfolios_df, lookback)

Cria estrutura JSON detalhada com todos os resultados
"""
function create_detailed_results(results, portfolios_df, lookback)
    # Calcular estatísticas mensais para cada portfolio
    portfolio_stats = Dict{String, Any}()

    for col in names(portfolios_df)
        if col in ["Date", :Date]
            continue
        end

        returns = filter(!ismissing, portfolios_df[!, col])
        if length(returns) > 0
            portfolio_stats[string(col)] = Dict(
                "mean_return" => mean(returns),
                "std_return" => std(returns),
                "min_return" => minimum(returns),
                "max_return" => maximum(returns),
                "n_months" => length(returns),
                "positive_months" => sum(returns .> 0),
                "negative_months" => sum(returns .< 0)
            )
        end
    end

    # Estrutura completa de resultados
    detailed_results = Dict(
        "metadata" => Dict(
            "analysis_date" => Dates.format(now(), "yyyy-mm-dd HH:MM:SS"),
            "lookback_months" => lookback,
            "n_portfolios" => 6,
            "portfolio_names" => ["P1", "P2", "P3", "P4", "P5", "LowMinusHigh"]
        ),
        "performance_metrics" => results,
        "monthly_statistics" => portfolio_stats,
        "period_info" => Dict(
            "start_date" => string(minimum(portfolios_df.Date)),
            "end_date" => string(maximum(portfolios_df.Date)),
            "total_months" => nrow(portfolios_df)
        )
    )

    return detailed_results
end

"""
    generate_html_report(results, portfolios_df, ticker_stats, filename, params)

Gera relatório HTML formatado
"""
function generate_html_report(results, portfolios_df, ticker_stats, filename, params)
    open(filename, "w") do f
        # Header HTML
        println(f, """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Análise Novy-Marx - Relatório</title>
            <style>
                body { font-family: Arial, sans-serif; margin: 40px; }
                h1 { color: #333; }
                h2 { color: #666; border-bottom: 2px solid #eee; padding-bottom: 5px; }
                table { border-collapse: collapse; width: 100%; margin: 20px 0; }
                th, td { border: 1px solid #ddd; padding: 8px; text-align: right; }
                th { background-color: #f2f2f2; }
                .metric { font-size: 24px; font-weight: bold; color: #2c3e50; }
                .positive { color: green; }
                .negative { color: red; }
            </style>
        </head>
        <body>
        """)

        # Título e período
        println(f, "<h1>Análise Novy-Marx - Anomalia de Baixa Volatilidade</h1>")
        println(f, "<p>Período: $(get(params, :analysis_start, "")) a $(maximum(portfolios_df.Date))</p>")
        println(f, "<p>Gerado em: $(Dates.format(now(), "dd/mm/yyyy HH:MM"))</p>")

        # Estatísticas de tickers
        println(f, "<h2>Cobertura de Dados</h2>")
        println(f, "<p>Total de tickers S&P 500: $(ticker_stats["total_tickers"])</p>")
        println(f, "<p>Tickers processados: $(ticker_stats["successful_tickers"])</p>")
        println(f, "<p>Taxa de sucesso: $(round(ticker_stats["success_rate"], digits=1))%</p>")

        # Tabela de performance
        println(f, "<h2>Performance dos Portfolios</h2>")
        println(f, "<table>")
        println(f, "<tr><th>Portfolio</th><th>Retorno Anual</th><th>Volatilidade</th><th>Sharpe Ratio</th><th>Max Drawdown</th></tr>")

        for (name, metrics) in sort(collect(results), by=x->x[1])
            ret_class = metrics[:annual_return] >= 0 ? "positive" : "negative"
            println(f, "<tr>")
            println(f, "<td style='text-align:left'>$name</td>")
            println(f, "<td class='$ret_class'>$(round(metrics[:annual_return], digits=2))%</td>")
            println(f, "<td>$(round(metrics[:annual_vol], digits=2))%</td>")
            println(f, "<td>$(round(metrics[:sharpe_ratio], digits=3))</td>")
            println(f, "<td class='negative'>$(round(metrics[:max_drawdown]*100, digits=2))%</td>")
            println(f, "</tr>")
        end

        println(f, "</table>")

        # Estratégia P1-P5
        if haskey(results, "LowMinusHigh")
            lmh = results["LowMinusHigh"]
            println(f, "<h2>Estratégia P1-P5 (Low Minus High)</h2>")
            println(f, "<p class='metric'>Retorno: <span class='$(lmh[:annual_return] >= 0 ? "positive" : "negative")'>$(round(lmh[:annual_return], digits=2))%</span> a.a.</p>")
            println(f, "<p>Sharpe Ratio: $(round(lmh[:sharpe_ratio], digits=3))</p>")
            println(f, "<p>Volatilidade: $(round(lmh[:annual_vol], digits=2))%</p>")
        end

        # Footer
        println(f, """
        </body>
        </html>
        """)
    end
end

"""
    generate_analysis_figures(portfolios_df, results, figures_dir, params)

Gera todas as figuras da análise Novy-Marx
"""
function generate_analysis_figures(portfolios_df, results, figures_dir, params)
    println("🎨 Gerando figuras...")

    try
        # Gerar apenas gráficos legados (completos) + drawdown
        plot_strategy_drawdown(portfolios_df, figures_dir)
        generate_legacy_figures(portfolios_df, figures_dir, params)

        println("✅ Figuras salvas em: figures/")

    catch e
        println("⚠️  Erro ao gerar figuras: $e")
    end
end

# Função removida: plot_cumulative_returns (redundante com cumulative_lb12.png)

# Função removida: plot_quintile_performance (redundante com quintiles_lb12.png)

# Função removida: plot_annual_strategy_returns (redundante com annual_returns_lb12.png)

"""
    plot_strategy_drawdown(portfolios_df, output_dir)

Gráfico de drawdown da estratégia
"""
function plot_strategy_drawdown(portfolios_df, output_dir)
    if !("LowMinusHigh" in names(portfolios_df))
        return
    end

    returns = filter(!ismissing, portfolios_df.LowMinusHigh)
    dates = portfolios_df.Date[1:length(returns)]

    # Calcular drawdown
    cumulative = cumprod(1 .+ returns ./ 100)
    running_max = accumulate(max, cumulative)
    drawdowns = (cumulative .- running_max) ./ running_max .* 100

    # Criar ticks de anos para o gráfico de linha
    year_dates = Date[]
    year_labels = String[]
    for year in 2011:2024
        jan_date = Date(year, 1, 1)
        if jan_date >= dates[1] && jan_date <= dates[end]
            push!(year_dates, jan_date)
            push!(year_labels, string(year))
        end
    end

    p = plot(dates, drawdowns,
             title="Drawdown da Estratégia P1-P5",
             xlabel="Ano", ylabel="Drawdown (%)",
             color=:red, linewidth=2, legend=false,
             fill=(0, :red, 0.3), size=(1000, 400),
             xticks=(year_dates, year_labels),
             xrotation=45)

    savefig(p, joinpath(output_dir, "strategy_drawdown.png"))
end

"""
    generate_legacy_figures(portfolios_df, figures_dir, params)

Gera gráficos no formato legado usando módulo Visualization
"""
function generate_legacy_figures(portfolios_df, figures_dir, params)
    lookback = get(params, :lookback, 12)

    try
        # 1. Gráfico de retorno acumulado (estilo legado)
        cumulative_plot = plot_cumulative_legacy(portfolios_df)
        savefig(cumulative_plot, joinpath(figures_dir, "cumulative_lb$(lookback).png"))

        # 2. Gráfico de quintis (barras, estilo legado)
        quintiles_plot = plot_quintiles_legacy(portfolios_df)
        savefig(quintiles_plot, joinpath(figures_dir, "quintiles_lb$(lookback).png"))

        # 3. Retornos anuais por ano (barras coloridas)
        annual_returns_plot = plot_annual_returns_legacy(portfolios_df)
        savefig(annual_returns_plot, joinpath(figures_dir, "annual_returns_lb$(lookback).png"))

        # 4. Sharpe anuais por ano
        annual_sharpe_plot = plot_annual_sharpe_legacy(portfolios_df)
        savefig(annual_sharpe_plot, joinpath(figures_dir, "annual_sharpe_lb$(lookback).png"))

        println("✅ Gráficos legados gerados")

    catch e
        println("⚠️  Erro ao gerar gráficos legados: $e")
    end
end

"""
    plot_cumulative_legacy(portfolios_df)

Gráfico de retorno acumulado no estilo legado
"""
function plot_cumulative_legacy(portfolios_df)
    dates = portfolios_df.Date

    # Criar ticks de anos para o gráfico
    year_dates = Date[]
    year_labels = String[]
    for year in 2011:2025
        jan_date = Date(year, 1, 1)
        if jan_date >= dates[1] && jan_date <= dates[end]
            push!(year_dates, jan_date)
            push!(year_labels, string(year))
        end
    end

    # Calcular retornos acumulados para todos os portfolios
    p = plot(title="Retornos Acumulados dos Portfolios - Análise Novy-Marx",
             xlabel="Ano", ylabel="Retorno Acumulado (%)",
             legend=:topleft, size=(1200, 700),
             dpi=300,
             xticks=(year_dates, year_labels),
             xrotation=45)

    portfolios = [("P1", :darkgreen, "P1 (Baixa Vol)"),
                  ("P2", :lightgreen, "P2"),
                  ("P3", :gray, "P3"),
                  ("P4", :orange, "P4"),
                  ("P5", :red, "P5 (Alta Vol)"),
                  ("LowMinusHigh", :blue, "Estratégia P1-P5")]

    for (col, color, label) in portfolios
        if col in names(portfolios_df)
            returns = replace(portfolios_df[!, col], missing => 0.0)
            cumret = cumprod(1 .+ returns ./ 100) .- 1
            cumret_pct = cumret .* 100
            plot!(p, dates, cumret_pct, label=label, color=color, linewidth=2.5)
        end
    end

    return p
end

"""
    plot_quintiles_legacy(portfolios_df)

Gráfico de barras dos quintis no estilo legado
"""
function plot_quintiles_legacy(portfolios_df)
    portfolios = ["P1", "P2", "P3", "P4", "P5"]
    returns = Float64[]
    vols = Float64[]

    for p in portfolios
        if p in names(portfolios_df)
            p_returns = filter(!ismissing, portfolios_df[!, p])
            if !isempty(p_returns)
                push!(returns, mean(p_returns) * 12)  # Anualizar
                push!(vols, std(p_returns) * sqrt(12))  # Anualizar
            else
                push!(returns, 0.0)
                push!(vols, 0.0)
            end
        else
            push!(returns, 0.0)
            push!(vols, 0.0)
        end
    end

    # Subplot de retornos
    p1 = bar(1:5, returns,
             title="Retorno Anualizado por Quintil de Volatilidade",
             xlabel="Quintil (1=Baixa Vol → 5=Alta Vol)",
             ylabel="Retorno Anual (%)",
             color=[:darkgreen, :lightgreen, :gray, :orange, :red],
             legend=false, size=(600, 400))

    # Adicionar valores nas barras de retorno
    for (i, ret) in enumerate(returns)
        annotate!(p1, i, ret + (ret >= 0 ? 0.5 : -0.5),
                 Plots.text(@sprintf("%.1f%%", ret), 9, :center, :black))
    end

    # Subplot de volatilidades
    p2 = bar(1:5, vols,
             title="Volatilidade Anualizada por Quintil",
             xlabel="Quintil (1=Baixa Vol → 5=Alta Vol)",
             ylabel="Volatilidade Anual (%)",
             color=[:darkgreen, :lightgreen, :gray, :orange, :red],
             legend=false, size=(600, 400))

    # Adicionar valores nas barras de volatilidade
    for (i, vol) in enumerate(vols)
        annotate!(p2, i, vol + 0.5,
                 Plots.text(@sprintf("%.1f%%", vol), 9, :center, :black))
    end

    combined = plot(p1, p2, layout=(2,1), size=(800, 900), dpi=300)
    return combined
end

"""
    plot_annual_returns_legacy(portfolios_df)

Gráfico de retornos anuais da estratégia no formato legado
"""
function plot_annual_returns_legacy(portfolios_df)
    if !("LowMinusHigh" in names(portfolios_df))
        return plot()
    end

    # Agrupar por anos completos
    years = unique(Dates.year.(portfolios_df.Date))
    filter!(y -> y >= 2011 && y <= 2024, years)  # Anos completos
    sort!(years)

    annual_returns = Float64[]

    for year in years
        year_data = filter(row -> Dates.year(row.Date) == year, portfolios_df)
        year_returns = filter(!ismissing, year_data.LowMinusHigh)

        if length(year_returns) >= 10  # Pelo menos 10 meses
            annual_ret = prod(1 .+ year_returns ./ 100) - 1
            push!(annual_returns, annual_ret * 100)
        else
            push!(annual_returns, 0.0)
        end
    end

    # Cores: verde para positivo, vermelho para negativo
    bar_colors = [ret >= 0 ? :green : :red for ret in annual_returns]

    p = bar(years, annual_returns,
            title="Retorno Anual da Estratégia P1-P5 (Low Minus High)",
            xlabel="Ano", ylabel="Retorno (%)",
            color=bar_colors, legend=false,
            size=(1000, 600), dpi=300,
            xticks=(years, string.(years)),
            xrotation=45)

    # Linha zero
    hline!([0], color=:black, linestyle=:dash, alpha=0.7)

    # Adicionar valores nas barras
    for (i, (year, ret)) in enumerate(zip(years, annual_returns))
        annotate!(year, ret + (ret >= 0 ? 1 : -1),
                 Plots.text(@sprintf("%.1f%%", ret), 8, :center))
    end

    return p
end

"""
    plot_annual_sharpe_legacy(portfolios_df)

Gráfico de Sharpe ratio anual da estratégia
"""
function plot_annual_sharpe_legacy(portfolios_df)
    if !("LowMinusHigh" in names(portfolios_df))
        return plot()
    end

    # Agrupar por anos completos
    years = unique(Dates.year.(portfolios_df.Date))
    filter!(y -> y >= 2011 && y <= 2024, years)
    sort!(years)

    annual_sharpes = Float64[]

    for year in years
        year_data = filter(row -> Dates.year(row.Date) == year, portfolios_df)
        year_returns = filter(!ismissing, year_data.LowMinusHigh)

        if length(year_returns) >= 10
            mean_ret = mean(year_returns)
            vol_ret = std(year_returns)
            sharpe = vol_ret > 0 ? mean_ret / vol_ret : 0.0
            push!(annual_sharpes, sharpe)
        else
            push!(annual_sharpes, 0.0)
        end
    end

    # Cores baseadas em positivo/negativo
    bar_colors = [s >= 0 ? :blue : :red for s in annual_sharpes]

    p = bar(years, annual_sharpes,
            title="Sharpe Ratio Anual da Estratégia P1-P5",
            xlabel="Ano", ylabel="Sharpe Ratio",
            color=bar_colors, legend=false,
            size=(1000, 600), dpi=300,
            xticks=(years, string.(years)),
            xrotation=45)

    # Linha zero
    hline!([0], color=:black, linestyle=:dash, alpha=0.7)

    # Adicionar valores nas barras
    for (i, (year, sharpe)) in enumerate(zip(years, annual_sharpes))
        annotate!(year, sharpe + (sharpe >= 0 ? 0.05 : -0.05),
                 Plots.text(@sprintf("%.2f", sharpe), 8, :center))
    end

    return p
end

end # module
