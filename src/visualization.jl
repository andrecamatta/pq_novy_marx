"""
Módulo de Visualização - Gráficos para análise Novy-Marx

Fornece funções utilitárias para criar gráficos de retorno acumulado e outras visualizações 
necessárias para a análise de anomalias financeiras segundo a metodologia Novy-Marx.

Funcionalidades principais:
- Gráficos de retorno acumulado (bruto e residual)
- Gráficos por quintil de portfolios
- Função utilitária plot_cumulative usando Plots.jl
"""

module Visualization

using DataFrames, Dates, Statistics, Plots, Printf

export plot_cumulative, plot_quintile_returns, plot_residual_returns,
       save_all_plots, create_performance_summary_plot, plot_annual_returns_bars, plot_annual_sharpe_bars

"""
    plot_cumulative(series::Vector{Float64}; 
                   dates::Vector{Date} = Date[],
                   title::String = "Retorno Acumulado", 
                   ylabel::String = "Retorno Acumulado (%)",
                   savepath::String = "",
                   show_plot::Bool = true)::Plots.Plot

Cria gráfico de retorno acumulado de uma série temporal.

# Argumentos
- `series`: Vetor de retornos (em %, ex: 2.5 para 2.5%)
- `dates`: Vetor de datas correspondentes (opcional)
- `title`: Título do gráfico
- `ylabel`: Label do eixo Y
- `savepath`: Caminho para salvar o gráfico (opcional, .png será adicionado)
- `show_plot`: Se deve mostrar o gráfico (default: true)

# Retorna
- Objeto Plot do Plots.jl

# Exemplo
```julia
retornos = [1.2, -0.8, 2.1, 0.5, -1.1]
datas = [Date(2020,i,1) for i in 1:5]
plot_cumulative(retornos, dates=datas, title="Portfolio Low Vol", savepath="low_vol_cumret")
```
"""
function plot_cumulative(series::Vector{Float64}; 
                        dates::Vector{Date} = Date[],
                        title::String = "Retorno Acumulado", 
                        ylabel::String = "Retorno Acumulado (%)",
                        savepath::String = "",
                        show_plot::Bool = true)::Plots.Plot
    
    if isempty(series)
        error("Série de retornos está vazia")
    end
    
    # Calcular retorno acumulado (1 + r1) * (1 + r2) * ... - 1
    cumulative_returns = cumprod(1.0 .+ series ./ 100.0) .- 1.0
    cumulative_returns .*= 100.0  # Converter de volta para %
    
    # Usar índices se datas não fornecidas
    x_axis = isempty(dates) ? (1:length(series)) : dates
    
    if length(x_axis) != length(series)
        error("Tamanho de dates ($(length(dates))) deve ser igual ao de series ($(length(series)))")
    end
    
    # Criar gráfico
    p = plot(x_axis, cumulative_returns,
             title = title,
             ylabel = ylabel,
             xlabel = isempty(dates) ? "Período" : "Data",
             linewidth = 2,
             color = :blue,
             legend = false,
             grid = true,
             gridwidth = 1,
             gridcolor = :lightgray,
             background_color = :white)
    
    # Adicionar linha zero para referência
    hline!([0], color = :red, linestyle = :dash, alpha = 0.7, linewidth = 1)
    
    # Salvar se caminho fornecido
    if !isempty(savepath)
        save_path = savepath
        if !endswith(savepath, ".png")
            save_path = savepath * ".png"
        end
        savefig(p, save_path)
        println("📊 Gráfico salvo: $save_path")
    end
    
    if show_plot
        display(p)
    end
    
    return p
end

"""
    plot_quintile_returns(portfolio_df::DataFrame; 
                         title::String = "Retornos por Quintil",
                         savepath::String = "",
                         show_plot::Bool = true)::Plots.Plot

Cria gráfico com retornos acumulados de todos os quintis (P1-P5) e Long-Short.

# Argumentos
- `portfolio_df`: DataFrame com colunas Date, P1, P2, P3, P4, P5, LowMinusHigh
- `title`: Título do gráfico
- `savepath`: Caminho para salvar (opcional)
- `show_plot`: Se deve mostrar o gráfico

# Retorna
- Objeto Plot do Plots.jl
"""
function plot_quintile_returns(portfolio_df::DataFrame; 
                              title::String = "Retornos por Quintil de Volatilidade",
                              savepath::String = "",
                              show_plot::Bool = true)::Plots.Plot
    
    if nrow(portfolio_df) == 0
        error("DataFrame de portfolios está vazio")
    end
    
    required_cols = ["Date", "P1", "P2", "P3", "P4", "P5", "LowMinusHigh"]
    missing_cols = setdiff(required_cols, names(portfolio_df))
    if !isempty(missing_cols)
        error("Colunas faltando no DataFrame: $(join(missing_cols, ", "))")
    end
    
    dates = portfolio_df.Date
    
    # Calcular retornos acumulados para cada série
    p1_cum = cumprod(1.0 .+ portfolio_df.P1 ./ 100.0) .- 1.0
    p2_cum = cumprod(1.0 .+ portfolio_df.P2 ./ 100.0) .- 1.0
    p3_cum = cumprod(1.0 .+ portfolio_df.P3 ./ 100.0) .- 1.0
    p4_cum = cumprod(1.0 .+ portfolio_df.P4 ./ 100.0) .- 1.0
    p5_cum = cumprod(1.0 .+ portfolio_df.P5 ./ 100.0) .- 1.0
    lmh_cum = cumprod(1.0 .+ portfolio_df.LowMinusHigh ./ 100.0) .- 1.0
    
    # Converter para %
    p1_cum .*= 100.0
    p2_cum .*= 100.0
    p3_cum .*= 100.0
    p4_cum .*= 100.0
    p5_cum .*= 100.0
    lmh_cum .*= 100.0
    
    # Criar gráfico
    p = plot(title = title,
             ylabel = "Retorno Acumulado (%)",
             xlabel = "Data",
             grid = true,
             gridwidth = 1,
             gridcolor = :lightgray,
             background_color = :white,
             size = (800, 500))
    
    # Plotar quintis
    plot!(dates, p1_cum, label = "P1 (Baixa Vol)", linewidth = 2, color = :darkgreen)
    plot!(dates, p2_cum, label = "P2", linewidth = 2, color = :lightgreen)
    plot!(dates, p3_cum, label = "P3", linewidth = 2, color = :gray)
    plot!(dates, p4_cum, label = "P4", linewidth = 2, color = :orange)
    plot!(dates, p5_cum, label = "P5 (Alta Vol)", linewidth = 2, color = :red)
    
    # Destacar Long-Short
    plot!(dates, lmh_cum, label = "Low-High", linewidth = 3, color = :blue, linestyle = :dash)
    
    # Linha zero para referência
    hline!([0], color = :black, linestyle = :dot, alpha = 0.5, linewidth = 1, label = "")
    
    # Salvar se caminho fornecido
    if !isempty(savepath)
        save_path = savepath
        if !endswith(savepath, ".png")
            save_path = savepath * ".png"
        end
        savefig(p, save_path)
        println("📊 Gráfico salvo: $save_path")
    end
    
    if show_plot
        display(p)
    end
    
    return p
end

"""
    plot_residual_returns(residual_df::DataFrame; 
                         title::String = "Retornos Residuais (Ajustados por Fatores)",
                         savepath::String = "",
                         show_plot::Bool = true)::Plots.Plot

Cria gráfico de retornos residuais (alphas) acumulados após ajuste por fatores.

# Argumentos
- `residual_df`: DataFrame com Date e colunas de alphas residuais
- `title`: Título do gráfico  
- `savepath`: Caminho para salvar
- `show_plot`: Se deve mostrar o gráfico

# Retorna
- Objeto Plot do Plots.jl
"""
function plot_residual_returns(residual_df::DataFrame; 
                              title::String = "Retornos Residuais (Ajustados por Fatores)",
                              savepath::String = "",
                              show_plot::Bool = true)::Plots.Plot
    
    if nrow(residual_df) == 0
        error("DataFrame de resíduos está vazio")
    end
    
    if !("Date" in names(residual_df))
        error("DataFrame deve conter coluna 'Date'")
    end
    
    dates = residual_df.Date
    
    p = plot(title = title,
             ylabel = "Alpha Acumulado (%)",
             xlabel = "Data", 
             grid = true,
             gridwidth = 1,
             gridcolor = :lightgray,
             background_color = :white,
             size = (800, 500))
    
    # Plotar todas as colunas exceto Date
    col_names = filter(x -> x != "Date", names(residual_df))
    colors = [:darkgreen, :lightgreen, :gray, :orange, :red, :blue]
    
    for (i, col) in enumerate(col_names)
        if i <= length(colors)
            series_data = residual_df[!, col]
            cum_data = cumprod(1.0 .+ series_data ./ 100.0) .- 1.0
            cum_data .*= 100.0
            
            linestyle = col == "LowMinusHigh" ? :dash : :solid
            linewidth = col == "LowMinusHigh" ? 3 : 2
            
            plot!(dates, cum_data, 
                  label = col, 
                  linewidth = linewidth, 
                  color = colors[i],
                  linestyle = linestyle)
        end
    end
    
    # Linha zero
    hline!([0], color = :black, linestyle = :dot, alpha = 0.5, linewidth = 1, label = "")
    
    # Salvar se caminho fornecido
    if !isempty(savepath)
        save_path = savepath
        if !endswith(savepath, ".png")
            save_path = savepath * ".png"
        end
        savefig(p, save_path)
        println("📊 Gráfico salvo: $save_path")
    end
    
    if show_plot
        display(p)
    end
    
    return p
end

"""
    create_performance_summary_plot(portfolio_df::DataFrame;
                                   title::String = "Resumo de Performance - Anomalia Low Vol",
                                   savepath::String = "",
                                   show_plot::Bool = true)::Plots.Plot

Cria gráfico de resumo com performance dos portfolios e estatísticas principais.

# Argumentos
- `portfolio_df`: DataFrame com retornos dos portfolios
- `title`: Título do gráfico
- `savepath`: Caminho para salvar
- `show_plot`: Se deve mostrar o gráfico

# Retorna  
- Objeto Plot do Plots.jl
"""
function create_performance_summary_plot(portfolio_df::DataFrame;
                                        title::String = "Resumo de Performance - Anomalia Low Vol",
                                        savepath::String = "",
                                        show_plot::Bool = true)::Plots.Plot
    
    # Layout com 4 subplots
    p1 = plot_quintile_returns(portfolio_df, title = "Retornos Acumulados", show_plot = false)
    
    # Calcular estatísticas resumo (anualizadas)
    lmh_ret_ann = mean(portfolio_df.LowMinusHigh) * 12  # Anualizar retorno
    lmh_vol_ann = std(portfolio_df.LowMinusHigh) * sqrt(12)  # Anualizar volatilidade
    lmh_sharpe = lmh_ret_ann / lmh_vol_ann

    p1_ret_ann = mean(portfolio_df.P1) * 12
    p5_ret_ann = mean(portfolio_df.P5) * 12
    p1_vol_ann = std(portfolio_df.P1) * sqrt(12)
    p5_vol_ann = std(portfolio_df.P5) * sqrt(12)

    # Subplot com barras de retorno anualizado
    returns_bar = [p1_ret_ann, mean(portfolio_df.P2) * 12, mean(portfolio_df.P3) * 12,
                   mean(portfolio_df.P4) * 12, p5_ret_ann]

    p2 = bar(1:5, returns_bar,
             title = "Retorno Anualizado por Quintil",
             xlabel = "Quintil (1=Baixa Vol, 5=Alta Vol)",
             ylabel = "Retorno Anual (%)",
             color = [:darkgreen, :lightgreen, :gray, :orange, :red],
             legend = false,
             grid = true)

    # Subplot com barras de volatilidade anualizada
    vol_bar = [p1_vol_ann, std(portfolio_df.P2) * sqrt(12), std(portfolio_df.P3) * sqrt(12),
               std(portfolio_df.P4) * sqrt(12), p5_vol_ann]

    p3 = bar(1:5, vol_bar,
             title = "Volatilidade Anualizada por Quintil",
             xlabel = "Quintil (1=Baixa Vol, 5=Alta Vol)",
             ylabel = "Volatilidade Anual (%)",
             color = [:darkgreen, :lightgreen, :gray, :orange, :red],
             legend = false,
             grid = true)

    # Subplot com estatísticas texto (anualizadas)
    stats_text = ["Long-Short (Anualizado):",
                  @sprintf("Retorno: %.2f%% a.a.", lmh_ret_ann),
                  @sprintf("Volatilidade: %.2f%% a.a.", lmh_vol_ann),
                  @sprintf("Sharpe: %.3f", lmh_sharpe),
                  "",
                  "Quintis (Anualizados):",
                  @sprintf("P1 vs P5 ret: %.2f%% vs %.2f%%", p1_ret_ann, p5_ret_ann),
                  @sprintf("P1 vs P5 vol: %.2f%% vs %.2f%%", p1_vol_ann, p5_vol_ann)]
    
    p4 = plot([0], [0], 
              title = "Estatísticas Resumo",
              xlim = (0, 1), ylim = (0, length(stats_text)),
              axis = false, grid = false, legend = false,
              showaxis = false)
    
    for (i, text_str) in enumerate(reverse(stats_text))
        annotate!(p4, 0.05, i-0.5, (text_str, 8, :left))
    end
    
    # Combinar subplots
    final_plot = plot(p1, p2, p3, p4, 
                      layout = (2, 2), 
                      size = (1000, 800),
                      plot_title = title)
    
    # Salvar se caminho fornecido
    if !isempty(savepath)
        save_path = savepath
        if !endswith(savepath, ".png")
            save_path = savepath * ".png"
        end
        savefig(final_plot, save_path)
        println("📊 Gráfico resumo salvo: $save_path")
    end
    
    if show_plot
        display(final_plot)
    end
    
    return final_plot
end

"""
    save_all_plots(portfolio_df::DataFrame;
                  output_dir::String = "plots",
                  prefix::String = "novy_marx")::Nothing

Salva todos os gráficos principais da análise em um diretório.

# Argumentos
- `portfolio_df`: DataFrame com retornos dos portfolios  
- `output_dir`: Diretório para salvar os gráficos
- `prefix`: Prefixo para os nomes dos arquivos
"""
function save_all_plots(portfolio_df::DataFrame;
                       output_dir::String = "plots",
                       prefix::String = "novy_marx")::Nothing
    
    # Criar diretório se não existir
    if !isdir(output_dir)
        mkpath(output_dir)
        println("📁 Diretório criado: $output_dir")
    end
    
    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    
    # Salvar gráficos principais
    println("💾 Salvando gráficos da análise...")
    
    # 1. Retornos por quintil
    quintile_path = joinpath(output_dir, "$(prefix)_quintis_$(timestamp)")
    plot_quintile_returns(portfolio_df, savepath = quintile_path, show_plot = false)
    
    # 2. Long-Short isolado
    lmh_path = joinpath(output_dir, "$(prefix)_long_short_$(timestamp)")
    plot_cumulative(portfolio_df.LowMinusHigh, 
                   dates = portfolio_df.Date,
                   title = "Estratégia Low Vol (Long-Short)",
                   savepath = lmh_path, 
                   show_plot = false)
    
    # 3. Resumo de performance
    summary_path = joinpath(output_dir, "$(prefix)_resumo_$(timestamp)")
    create_performance_summary_plot(portfolio_df,
                                   savepath = summary_path,
                                   show_plot = false)

    # 4. Retornos anuais por barras
    annual_returns_path = joinpath(output_dir, "$(prefix)_retornos_anuais_$(timestamp)")
    plot_annual_returns_bars(portfolio_df,
                            savepath = annual_returns_path,
                            show_plot = false)

    # 5. Sharpe anual por barras
    annual_sharpe_path = joinpath(output_dir, "$(prefix)_sharpe_anual_$(timestamp)")
    plot_annual_sharpe_bars(portfolio_df,
                           savepath = annual_sharpe_path,
                           show_plot = false)
    
    println("✅ Todos os gráficos salvos em: $output_dir")
    println("   Timestamp: $timestamp")
    
    return nothing
end

"""
    plot_annual_returns_bars(portfolio_df::DataFrame;
                            title::String = "Retorno Anual - Estratégia Low-High",
                            savepath::String = "",
                            show_plot::Bool = true)::Plots.Plot

Cria gráfico de barras com retornos anuais da estratégia low-high (LowMinusHigh).
Para anos incompletos (como 2010 e 2025), mostra o retorno do período esperado sem anualização.

# Argumentos
- `portfolio_df`: DataFrame com colunas Date e LowMinusHigh
- `title`: Título do gráfico
- `savepath`: Caminho para salvar
- `show_plot`: Se deve mostrar o gráfico

# Retorna
- Objeto Plot do Plots.jl
"""
function plot_annual_returns_bars(portfolio_df::DataFrame;
                                 title::String = "Retorno Anual - Estratégia Low-High",
                                 savepath::String = "",
                                 show_plot::Bool = true)::Plots.Plot

    if nrow(portfolio_df) == 0
        error("DataFrame de portfolios está vazio")
    end

    if !("Date" in names(portfolio_df)) || !("LowMinusHigh" in names(portfolio_df))
        error("DataFrame deve conter colunas 'Date' e 'LowMinusHigh'")
    end

    # Calcular retornos por ano
    portfolio_df.Year = year.(portfolio_df.Date)
    annual_returns = Dict{Int, Float64}()

    for yr in unique(portfolio_df.Year)
        year_data = filter(row -> row.Year == yr, portfolio_df)
        clean_returns = filter(!ismissing, year_data.LowMinusHigh)

        if !isempty(clean_returns)
            # Retorno composto do período (não anualizado)
            annual_ret = prod(1 .+ clean_returns ./ 100) - 1
            annual_returns[yr] = annual_ret * 100  # Converter para %
        end
    end

    if isempty(annual_returns)
        error("Não foi possível calcular retornos anuais")
    end

    # Preparar dados para o gráfico
    years = sort(collect(keys(annual_returns)))
    returns = [annual_returns[yr] for yr in years]

    # Cores melhoradas: verde para positivo, vermelho para negativo
    colors = [ret >= 0 ? :steelblue : :crimson for ret in returns]

    # Calcular margem para os annotations
    y_range = maximum(returns) - minimum(returns)
    y_margin = y_range * 0.15

    # Criar gráfico de barras com melhor formatação
    p = bar(years, returns,
            title = title,
            xlabel = "Ano",
            ylabel = "Retorno P1-P5 (%)",
            color = colors,
            legend = false,
            grid = true,
            gridwidth = 1,
            gridcolor = :lightgray,
            gridopacity = 0.3,
            background_color = :white,
            size = (1000, 600),
            xticks = years,
            xrotation = 45,
            ylims = (minimum(returns) - y_margin, maximum(returns) + y_margin),
            titlefontsize = 14,
            guidefontsize = 12,
            tickfontsize = 10,
            margin = 5Plots.mm)

    # Linha zero para referência
    hline!([0], color = :black, linestyle = :dash, alpha = 0.8, linewidth = 2)

    # Adicionar valores nas barras com melhor posicionamento
    for (yr, ret) in zip(years, returns)
        y_pos = ret + (ret >= 0 ? y_margin * 0.3 : -y_margin * 0.3)
        annotate!(yr, y_pos,
                 (@sprintf("%.1f", ret), 9, :center, ret >= 0 ? :steelblue : :crimson))
    end

    # Salvar se caminho fornecido
    if !isempty(savepath)
        save_path = savepath
        if !endswith(savepath, ".png")
            save_path = savepath * ".png"
        end
        savefig(p, save_path)
        println("📊 Gráfico de retornos anuais salvo: $save_path")
    end

    if show_plot
        display(p)
    end

    return p
end

"""
    plot_annual_sharpe_bars(portfolio_df::DataFrame;
                           title::String = "Índice de Sharpe Anual - Estratégia Low-High",
                           savepath::String = "",
                           show_plot::Bool = true)::Plots.Plot

Cria gráfico de barras com índice de Sharpe anual da estratégia low-high (LowMinusHigh).
Para anos incompletos, calcula o Sharpe com base nos dados disponíveis sem anualização.

# Argumentos
- `portfolio_df`: DataFrame com colunas Date e LowMinusHigh
- `title`: Título do gráfico
- `savepath`: Caminho para salvar
- `show_plot`: Se deve mostrar o gráfico

# Retorna
- Objeto Plot do Plots.jl
"""
function plot_annual_sharpe_bars(portfolio_df::DataFrame;
                                title::String = "Índice de Sharpe Anual - Estratégia Low-High",
                                savepath::String = "",
                                show_plot::Bool = true)::Plots.Plot

    if nrow(portfolio_df) == 0
        error("DataFrame de portfolios está vazio")
    end

    if !("Date" in names(portfolio_df)) || !("LowMinusHigh" in names(portfolio_df))
        error("DataFrame deve conter colunas 'Date' e 'LowMinusHigh'")
    end

    # Calcular Sharpe por ano
    portfolio_df.Year = year.(portfolio_df.Date)
    annual_sharpes = Dict{Int, Float64}()

    for yr in unique(portfolio_df.Year)
        year_data = filter(row -> row.Year == yr, portfolio_df)
        clean_returns = filter(!ismissing, year_data.LowMinusHigh)

        if length(clean_returns) >= 3  # Mínimo 3 observações para calcular Sharpe
            mean_ret = mean(clean_returns)
            vol = std(clean_returns)

            if vol > 0
                sharpe = mean_ret / vol  # Sharpe sem anualização
                annual_sharpes[yr] = sharpe
            end
        end
    end

    if isempty(annual_sharpes)
        error("Não foi possível calcular Sharpe anuais")
    end

    # Preparar dados para o gráfico
    years = sort(collect(keys(annual_sharpes)))
    sharpes = [annual_sharpes[yr] for yr in years]

    # Cores melhoradas: azul para positivo, vermelho para negativo
    colors = [sharpe >= 0 ? :darkgreen : :crimson for sharpe in sharpes]

    # Calcular margem para os annotations
    y_range = maximum(sharpes) - minimum(sharpes)
    y_margin = y_range * 0.15

    # Criar gráfico de barras com melhor formatação
    p = bar(years, sharpes,
            title = title,
            xlabel = "Ano",
            ylabel = "Sharpe P1-P5",
            color = colors,
            legend = false,
            grid = true,
            gridwidth = 1,
            gridcolor = :lightgray,
            gridopacity = 0.3,
            background_color = :white,
            size = (1000, 600),
            xticks = years,
            xrotation = 45,
            ylims = (minimum(sharpes) - y_margin, maximum(sharpes) + y_margin),
            titlefontsize = 14,
            guidefontsize = 12,
            tickfontsize = 10,
            margin = 5Plots.mm)

    # Linha zero para referência
    hline!([0], color = :black, linestyle = :dash, alpha = 0.8, linewidth = 2)

    # Adicionar valores nas barras com melhor posicionamento
    for (yr, sharpe) in zip(years, sharpes)
        y_pos = sharpe + (sharpe >= 0 ? y_margin * 0.3 : -y_margin * 0.3)
        annotate!(yr, y_pos,
                 (@sprintf("%.2f", sharpe), 9, :center, sharpe >= 0 ? :darkgreen : :crimson))
    end

    # Salvar se caminho fornecido
    if !isempty(savepath)
        save_path = savepath
        if !endswith(savepath, ".png")
            save_path = savepath * ".png"
        end
        savefig(p, save_path)
        println("📊 Gráfico de Sharpe anual salvo: $save_path")
    end

    if show_plot
        display(p)
    end

    return p
end

end # module Visualization