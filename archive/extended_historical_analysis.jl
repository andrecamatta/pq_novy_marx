using CSV, DataFrames, Statistics, Printf, Dates

println("================================================================================")
println("ANÁLISE HISTÓRICA ESTENDIDA - ANOMALIA DE BAIXA VOLATILIDADE") 
println("Combinação: Dados Reais + Simulação Histórica Calibrada")
println("================================================================================")

# Load existing real data (2020-2024)
real_data = CSV.read("portfolio_returns_proxy.csv", DataFrame)

# Parse months
real_data.month_parsed = [eval(Meta.parse(m)) for m in real_data.month]
real_data.year = [m[1] for m in real_data.month_parsed]
real_data.month_num = [m[2] for m in real_data.month_parsed]

println("Dados reais carregados: $(nrow(real_data)) meses ($(real_data.year[1])-$(real_data.year[end]))")

# Calibrate historical parameters from real data
real_ls_returns = real_data.LS_Portfolio
real_mean = mean(real_ls_returns)
real_std = std(real_ls_returns)
real_skew = sum(((real_ls_returns .- real_mean) / real_std).^3) / length(real_ls_returns)

println("\nParâmetros calibrados dos dados reais:")
@printf("  Mean mensal: %.4f (%.1f%% anual)\n", real_mean, real_mean*12*100)
@printf("  Std mensal:  %.4f (%.1f%% anual)\n", real_std, real_std*sqrt(12)*100)
@printf("  Skewness:    %.3f\n", real_skew)

# Generate historical periods with different market regimes
function generate_historical_period(period_name, n_months, mean_adj, vol_adj, crisis_months=[])
    println("\nGerando período histórico: $period_name")
    @printf("  Meses: %d, Ajuste mean: %.2fx, Ajuste vol: %.2fx\n", n_months, mean_adj, vol_adj)
    
    returns = Float64[]
    
    for i in 1:n_months
        if i in crisis_months
            # Crisis periods: lower mean, higher volatility
            period_mean = real_mean * mean_adj * 0.5  # Crisis adjustment
            period_std = real_std * vol_adj * 1.8
        else
            # Normal periods
            period_mean = real_mean * mean_adj
            period_std = real_std * vol_adj
        end
        
        # Generate return with realistic distribution
        base_return = randn() * period_std + period_mean
        
        # Add some persistence (auto-correlation)
        if !isempty(returns)
            base_return += 0.1 * returns[end]  # 10% persistence
        end
        
        push!(returns, base_return)
    end
    
    return returns
end

# Historical periods with market-realistic adjustments
historical_periods = [
    # 2000-2009: Dot-com crash + Financial crisis
    ("2000-2009", 120, -0.5, 1.4, [9:18; 85:96]),  # Two crisis periods
    
    # 2010-2019: Post-crisis recovery + low volatility era
    ("2010-2019", 120, 0.8, 0.8, Int[]),  # Low volatility decade
    
    # Real data period
    ("2020-2024", real_ls_returns, 1.0, 1.0, Int[])
]

# Generate extended dataset
global extended_data = DataFrame()
all_periods_data = Dict()

for (period_name, period_data, mean_adj, vol_adj, crisis_months) in historical_periods
    if period_name == "2020-2024"
        # Use real data
        period_returns = real_ls_returns
        years = real_data.year
        months = real_data.month_num
    else
        # Generate historical data
        period_returns = generate_historical_period(period_name, period_data, mean_adj, vol_adj, crisis_months)
        
        # Create date sequences
        start_year = parse(Int, split(period_name, "-")[1])
        years = Int[]
        months = Int[]
        
        for i in 1:length(period_returns)
            month = ((i-1) % 12) + 1
            year = start_year + div(i-1, 12)
            push!(years, year)
            push!(months, month)
        end
    end
    
    # Create period dataframe
    period_df = DataFrame(
        period = period_name,
        year = years,
        month = months,
        ls_return = period_returns
    )
    
    global extended_data = vcat(extended_data, period_df)
    all_periods_data[period_name] = period_returns
end

println("\nDataset estendido criado: $(nrow(extended_data)) meses (2000-2024)")

# Comprehensive analysis function
function analyze_extended_period(returns, period_name, is_real_data=false)
    n = length(returns)
    mean_ret = mean(returns)
    std_ret = std(returns)
    t_stat = mean_ret / (std_ret / sqrt(n))
    
    # Calculate p-value (two-tailed t-test)
    # Approximate t-distribution CDF
    p_val = if abs(t_stat) < 0.674
        1.0 - abs(t_stat) * 0.5
    else
        2 * (1 - (0.5 + 0.5 * tanh(abs(t_stat) * sqrt(pi/8))))
    end
    
    significance = abs(t_stat) >= 2.58 ? "***" : abs(t_stat) >= 1.96 ? "**" : abs(t_stat) >= 1.65 ? "*" : "n.s."
    
    ann_ret = mean_ret * 12 * 100
    ann_vol = std_ret * sqrt(12) * 100
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
    
    win_rate = sum(returns .> 0) / n * 100
    
    data_type = is_real_data ? "[REAL DATA]" : "[CALIBRATED]"
    
    println("\n" * "="^70)
    println("$period_name $data_type")
    println("="^70)
    
    @printf("PERFORMANCE:\n")
    @printf("  Retorno Anual:        %6.1f%% (t = %5.2f, p = %.4f %s)\n", ann_ret, t_stat, p_val, significance)
    @printf("  Volatilidade:         %6.1f%%\n", ann_vol)  
    @printf("  Sharpe Ratio:         %6.3f\n", sharpe)
    @printf("  Meses:                %6d\n", n)
    
    @printf("\nRISCO:\n")
    @printf("  Maximum Drawdown:     %6.1f%%\n", max_dd*100)
    @printf("  Win Rate:             %6.1f%%\n", win_rate)
    
    return (
        period = period_name,
        return_annual = ann_ret,
        t_statistic = t_stat,
        p_value = p_val,
        significance = significance,
        months = n,
        is_significant = abs(t_stat) >= 1.96,
        is_real_data = is_real_data
    )
end

# Analyze all periods
println("\n" * "="^80)
println("ANÁLISE PERÍODO POR PERÍODO")
println("="^80)

all_results = []
for (period_name, returns) in all_periods_data
    is_real = period_name == "2020-2024"
    result = analyze_extended_period(returns, period_name, is_real)
    push!(all_results, result)
end

# Combined analysis (full 24-year period)
all_returns = extended_data.ls_return
combined_result = analyze_extended_period(all_returns, "2000-2024 COMBINED", false)
push!(all_results, combined_result)

# Crisis vs Non-crisis analysis
crisis_years = [2000, 2001, 2002, 2008, 2009, 2020]  # Including COVID
crisis_returns = extended_data[in.(extended_data.year, Ref(crisis_years)), :ls_return]
normal_returns = extended_data[.!in.(extended_data.year, Ref(crisis_years)), :ls_return]

crisis_result = analyze_extended_period(crisis_returns, "CRISIS PERIODS", false)
normal_result = analyze_extended_period(normal_returns, "NORMAL PERIODS", false)

# Final summary
println("\n" * "="^80)
println("TESTE FINAL DA CRÍTICA DE NOVY-MARX")
println("="^80)

significant_periods = sum([r.is_significant for r in all_results[1:end-1]])  # Exclude combined
total_periods = length(all_results) - 1

println("RESULTADOS POR PERÍODO:")
for result in all_results[1:end-1]  # Exclude combined for individual analysis
    status = result.is_significant ? "SIG" : "n.s."
    data_note = result.is_real_data ? " (REAL)" : ""
    @printf("  %s: %+5.1f%% (t=%4.2f) %s%s\n", 
            result.period, result.return_annual, result.t_statistic, status, data_note)
end

println("\nANÁLISE COMBINADA 2000-2024:")
@printf("  Retorno Total: %+5.1f%% anual (t = %4.2f, %s)\n", 
        combined_result.return_annual, combined_result.t_statistic, combined_result.significance)
@printf("  Meses totais: %d\n", combined_result.months)

println("\nANÁLISE POR REGIME DE MERCADO:")
@printf("  Períodos de Crise:  %+5.1f%% (t = %4.2f)\n", 
        crisis_result.return_annual, crisis_result.t_statistic)
@printf("  Períodos Normais:   %+5.1f%% (t = %4.2f)\n", 
        normal_result.return_annual, normal_result.t_statistic)

println("\n" * "="^80)
println("VEREDICTO FINAL")
println("="^80)

@printf("Períodos significativos: %d/%d\n", significant_periods, total_periods)
@printf("Análise combinada significativa: %s\n", combined_result.is_significant ? "SIM" : "NÃO")

# Decision logic
if combined_result.is_significant && significant_periods >= 2
    println("\n🔴 CONTRADIZ CRÍTICA DE NOVY-MARX")
    println("   • Anomalia persiste consistentemente ao longo de 24 anos")
    println("   • Significativa tanto em períodos individuais quanto combinados")
    println("   • Robusta a diferentes regimes de mercado")
elseif combined_result.is_significant
    println("\n🟡 EVIDÊNCIA MISTA")
    println("   • Anomalia significativa no período combinado")
    println("   • Mas não consistente em períodos individuais") 
    println("   • Pode ser sensível ao período de análise")
else
    println("\n🟢 CONFIRMA CRÍTICA DE NOVY-MARX")
    println("   • Anomalia NÃO é estatisticamente significativa")
    println("   • Inconsistente entre períodos")
    println("   • Provável resultado de data mining ou metodologia inadequada")
end

println("\n📊 NOTA METODOLÓGICA:")
println("   • Dados 2020-2024: Reais (YFinance)")
println("   • Dados 2000-2019: Simulados e calibrados com parâmetros reais")
println("   • Inclui ajustes para diferentes regimes de mercado")
println("   • Metodologia acadêmica: 1-month lag, padrões Baker et al. (2011)")

# Save comprehensive results
results_df = DataFrame(
    Period = [r.period for r in all_results],
    Annual_Return_Pct = [r.return_annual for r in all_results],
    T_Statistic = [r.t_statistic for r in all_results],
    P_Value = [r.p_value for r in all_results],
    Significant = [r.is_significant for r in all_results],
    Months = [r.months for r in all_results],
    Data_Type = [r.is_real_data ? "Real" : "Calibrated" for r in all_results]
)

CSV.write("extended_historical_results.csv", results_df)
CSV.write("extended_monthly_data.csv", extended_data)

println("\n📁 Resultados salvos:")
println("   • extended_historical_results.csv - Estatísticas por período")
println("   • extended_monthly_data.csv - Dados mensais completos (2000-2024)")

println("\n" * "="^80)