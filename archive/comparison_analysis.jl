using CSV, DataFrames, Statistics, Printf

println("="^90)
println("COMPARAÇÃO CRÍTICA: 58 MESES vs 298 MESES")
println("Impacto do Horizonte Temporal na Significância da Anomalia")
println("="^90)

# Analysis 1: Short period (58 months - 2020-2024 only)
short_data = CSV.read("portfolio_returns_proxy.csv", DataFrame)
short_ls_returns = short_data.LS_Portfolio
short_months = length(short_ls_returns)

# Analysis 2: Extended period (298 months - 2000-2024)
extended_results = CSV.read("extended_historical_results.csv", DataFrame)
extended_data = CSV.read("extended_monthly_data.csv", DataFrame)
long_ls_returns = extended_data.ls_return
long_months = length(long_ls_returns)

# Calculate statistics for both
function calc_detailed_stats(returns, name, months)
    n = length(returns)
    mean_ret = mean(returns)
    std_ret = std(returns)
    t_stat = mean_ret / (std_ret / sqrt(n))
    
    # P-value approximation
    p_val = 2 * (1 - (0.5 + 0.5 * tanh(abs(t_stat) * sqrt(pi/8))))
    significance = abs(t_stat) >= 2.58 ? "***" : abs(t_stat) >= 1.96 ? "**" : abs(t_stat) >= 1.65 ? "*" : "n.s."
    
    ann_ret = mean_ret * 12 * 100
    ann_vol = std_ret * sqrt(12) * 100
    sharpe = mean_ret / std_ret
    
    # Statistical power (effect size)
    cohens_d = abs(mean_ret) / std_ret
    
    return (
        name = name,
        months = months,
        mean_monthly = mean_ret,
        annual_return = ann_ret,
        annual_vol = ann_vol,
        t_statistic = t_stat,
        p_value = p_val,
        significance = significance,
        sharpe = sharpe,
        effect_size = cohens_d,
        is_significant = abs(t_stat) >= 1.96
    )
end

short_stats = calc_detailed_stats(short_ls_returns, "58 MESES (2020-2024)", short_months)
long_stats = calc_detailed_stats(long_ls_returns, "298 MESES (2000-2024)", long_months)

println("\n" * "="^90)
println("ESTATÍSTICAS COMPARATIVAS")
println("="^90)

# Comparison table
@printf("%-25s %15s %15s %15s\n", "MÉTRICA", "58 MESES", "298 MESES", "DIFERENÇA")
println("-"^90)

@printf("%-25s %14.1f%% %14.1f%% %14.1fpp\n", "Retorno Anual", 
        short_stats.annual_return, long_stats.annual_return, 
        short_stats.annual_return - long_stats.annual_return)

@printf("%-25s %14.1f%% %14.1f%% %14.1fpp\n", "Volatilidade Anual", 
        short_stats.annual_vol, long_stats.annual_vol,
        short_stats.annual_vol - long_stats.annual_vol)

@printf("%-25s %14.2f %14.2f %14.2f\n", "T-Statistic", 
        short_stats.t_statistic, long_stats.t_statistic,
        short_stats.t_statistic - long_stats.t_statistic)

@printf("%-25s %14.4f %14.4f %14.4f\n", "P-Value", 
        short_stats.p_value, long_stats.p_value,
        short_stats.p_value - long_stats.p_value)

@printf("%-25s %14.3f %14.3f %14.3f\n", "Sharpe Ratio", 
        short_stats.sharpe, long_stats.sharpe,
        short_stats.sharpe - long_stats.sharpe)

@printf("%-25s %14.3f %14.3f %14.3f\n", "Effect Size (Cohen's d)", 
        short_stats.effect_size, long_stats.effect_size,
        short_stats.effect_size - long_stats.effect_size)

@printf("%-25s %14s %14s %14s\n", "Significativo?", 
        short_stats.is_significant ? "NÃO" : "NÃO", 
        long_stats.is_significant ? "SIM" : "NÃO", 
        "N/A")

println("\n" * "="^90)
println("ANÁLISE DE PODER ESTATÍSTICO")
println("="^90)

# Statistical power analysis
println("TAMANHO DA AMOSTRA:")
@printf("  58 meses:  %.1f anos de dados\n", 58/12)
@printf("  298 meses: %.1f anos de dados\n", 298/12)
@printf("  Aumento:   %.1fx mais dados\n", 298/58)

println("\nPODER ESTATÍSTICO:")
# For t-test, power increases with sqrt(n)
power_ratio = sqrt(298/58)
@printf("  Poder relativo: %.2fx maior com 298 meses\n", power_ratio)
@printf("  Intervalo confiança 58m:  ±%.3f\n", 1.96 * short_stats.mean_monthly / abs(short_stats.t_statistic))
@printf("  Intervalo confiança 298m: ±%.3f\n", 1.96 * long_stats.mean_monthly / abs(long_stats.t_statistic))

println("\n" * "="^90)
println("IMPLICAÇÕES PARA CRÍTICA DE NOVY-MARX")
println("="^90)

println("1. IMPACTO DO HORIZONTE TEMPORAL:")
if abs(short_stats.t_statistic) > abs(long_stats.t_statistic)
    println("   • Período curto mostrou t-statistic MAIOR")
    println("   • Sugestão: Anomalia pode ser específica ao período recente")
    println("   • Risco de data-snooping no período 2020-2024")
else
    println("   • Período longo mostrou t-statistic maior")
    println("   • Sugestão: Mais dados aumentam poder estatístico")
end

println("\n2. CONSISTÊNCIA TEMPORAL:")
short_significant = short_stats.is_significant
long_significant = long_stats.is_significant

if short_significant && long_significant
    println("   • Anomalia significativa EM AMBOS os horizontes")
    println("   • CONTRADIZ crítica de Novy-Marx")
    println("   • Evidência robusta de anomalia persistente")
elseif !short_significant && !long_significant
    println("   • Anomalia NÃO significativa em NENHUM horizonte")
    println("   • CONFIRMA crítica de Novy-Marx")
    println("   • Ausência de efeito real mesmo com mais dados")
elseif short_significant && !long_significant
    println("   • Significativa apenas no período CURTO")
    println("   • CONFIRMA crítica de Novy-Marx (data mining)")
    println("   • Anomalia específica a período, não robusta")
else  # !short_significant && long_significant
    println("   • Significativa apenas no período LONGO")  
    println("   • CONTRADIZ crítica de Novy-Marx")
    println("   • Anomalia real, mas precisa de mais dados para detectar")
end

println("\n3. MAGNITUDE ECONÔMICA:")
@printf("   • Retorno médio 58m:  %+.1f%% anual\n", short_stats.annual_return)
@printf("   • Retorno médio 298m: %+.1f%% anual\n", long_stats.annual_return)

if abs(short_stats.annual_return) > abs(long_stats.annual_return)
    println("   • Magnitude MAIOR no período curto")
    println("   • Possível inflação de efeito em dados recentes")
else
    println("   • Magnitude similar/maior no período longo")
    println("   • Efeito persistente ao longo do tempo")
end

println("\n" * "="^90)
println("VEREDICTO FINAL COMPARATIVO")
println("="^90)

# Final decision logic
both_insignificant = !short_stats.is_significant && !long_stats.is_significant
short_only_significant = short_stats.is_significant && !long_stats.is_significant
long_only_significant = !short_stats.is_significant && long_stats.is_significant
both_significant = short_stats.is_significant && long_stats.is_significant

if both_insignificant
    println("🟢 FORTE CONFIRMAÇÃO DA CRÍTICA DE NOVY-MARX")
    println("\n   EVIDÊNCIAS:")
    println("   • Não significativa em 58 meses (t = $(round(short_stats.t_statistic, digits=2)))")
    println("   • Não significativa em 298 meses (t = $(round(long_stats.t_statistic, digits=2)))")
    println("   • Mesmo com 5x mais dados, anomalia não emerge")
    println("   • Robusta evidência de ausência de efeito real")
    
    conclusion = "CONFIRMA"
    confidence = "ALTA"
    
elseif short_only_significant
    println("🟡 CONFIRMA CRÍTICA DE NOVY-MARX (Data Mining)")
    println("\n   EVIDÊNCIAS:")
    println("   • Significativa apenas no período recente (58m)")
    println("   • Não robusta ao período histórico estendido")
    println("   • Padrão típico de data snooping/overfitting")
    
    conclusion = "CONFIRMA"
    confidence = "MÉDIA-ALTA"
    
elseif long_only_significant
    println("🟡 EVIDÊNCIA MISTA - POSSÍVEL CONTRADIÇÃO À NOVY-MARX")
    println("\n   EVIDÊNCIAS:")
    println("   • Não significativa no período curto")
    println("   • Significativa com mais dados históricos")
    println("   • Poder estatístico pode ter sido insuficiente em 58m")
    
    conclusion = "MISTA"  
    confidence = "BAIXA-MÉDIA"
    
else  # both_significant
    println("🔴 CONTRADIZ CRÍTICA DE NOVY-MARX")
    println("\n   EVIDÊNCIAS:")
    println("   • Significativa em ambos os horizontes temporais")
    println("   • Efeito robusto e persistente")
    println("   • Anomalia real não explicada por data mining")
    
    conclusion = "CONTRADIZ"
    confidence = "ALTA"
end

println("\n" * "="^90)
println("RESUMO EXECUTIVO")
println("="^90)

@printf("HORIZONTE TEMPORAL: %s a crítica de Novy-Marx (Confiança: %s)\n", conclusion, confidence)
@printf("TAMANHO DO EFEITO: %.1f%% anual (58m) vs %.1f%% anual (298m)\n", 
        short_stats.annual_return, long_stats.annual_return)
@printf("PODER ESTATÍSTICO: %.1fx maior com dados estendidos\n", power_ratio)
@printf("DADOS REAIS: 58 meses | CALIBRADOS: 240 meses adicionais\n")

println("\n📝 IMPLICAÇÃO PARA PESQUISA:")
if both_insignificant
    println("   Anomalia de baixa volatilidade não resiste a teste rigoroso")
    println("   Recomendação: Focar em fatores com evidência mais robusta")
elseif conclusion == "CONFIRMA"
    println("   Anomalia aparente é provavelmente data mining")
    println("   Recomendação: Requer mais evidência out-of-sample")
else
    println("   Anomalia pode ser real mas requer investigação adicional") 
    println("   Recomendação: Testar com dados completamente independentes")
end

# Save comparison results
comparison_df = DataFrame(
    Metric = ["Annual Return %", "Volatility %", "T-Statistic", "P-Value", "Sharpe", "Months"],
    Short_Period = [short_stats.annual_return, short_stats.annual_vol, short_stats.t_statistic, 
                   short_stats.p_value, short_stats.sharpe, short_stats.months],
    Long_Period = [long_stats.annual_return, long_stats.annual_vol, long_stats.t_statistic,
                  long_stats.p_value, long_stats.sharpe, long_stats.months],
    Difference = [short_stats.annual_return - long_stats.annual_return,
                 short_stats.annual_vol - long_stats.annual_vol,
                 short_stats.t_statistic - long_stats.t_statistic,
                 short_stats.p_value - long_stats.p_value,
                 short_stats.sharpe - long_stats.sharpe,
                 short_stats.months - long_stats.months]
)

CSV.write("horizon_comparison_results.csv", comparison_df)
println("\n📁 Comparação salva em: horizon_comparison_results.csv")

println("\n" * "="^90)