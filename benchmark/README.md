# Análise Benchmark: VTI-AGG vs Portfólio P1

## Objetivo

Esta análise encontra o peso ótimo para uma carteira balanceada entre:
- **VTI** (Vanguard Total Stock Market ETF) - Ações americanas
- **AGG** (Vanguard Total Bond Market ETF) - Bonds americanos

O objetivo é criar uma carteira `x% VTI + (1-x)% AGG` que tenha exatamente a mesma volatilidade do **Portfólio P1** (baixa volatilidade) da análise Novy-Marx e comparar os retornos obtidos.

## Metodologia

### Dados
- **Período**: Agosto 2009 - Agosto 2025 (180 meses)
- **Fonte**: Sistema híbrido Stooq + Tiingo (mesmo da análise principal)
- **Target**: Volatilidade P1 = 11.83% a.a.

### Otimização
- **Função objetivo**: Minimizar |volatilidade_carteira - 11.83%|
- **Restrições**: 0 ≤ x ≤ 1 (peso em VTI)
- **Método**: Busca numérica usando Optim.jl
- **Fórmula**: σ = √(x²σ_VTI² + (1-x)²σ_AGG² + 2x(1-x)ρσ_VTI σ_AGG)

### Métricas Comparadas
- Retorno anualizado
- Volatilidade anualizada (equalizada por design)
- Sharpe ratio
- Maximum drawdown
- Calmar ratio
- Sortino ratio

## Estrutura

```
benchmark_analysis/
├── vti_agg_benchmark.jl          # Script principal de análise
├── data/                         # Dados baixados (cache)
├── results/                      # Resultados da análise
│   ├── optimization_results.json  # Resultados em JSON
│   ├── portfolio_returns.csv      # Série histórica de retornos
│   └── vti_agg_comparison_report.html  # Relatório visual
└── README.md                     # Esta documentação
```

## Execução

```bash
# Executar análise completa
julia benchmark_analysis/vti_agg_benchmark.jl
```

## Resultados

A análise responde às seguintes questões:

1. **Qual o peso ótimo em VTI** para atingir 11.83% de volatilidade?
2. **Qual o retorno anualizado** dessa carteira benchmark?
3. **Como se compara ao P1** em termos de Sharpe ratio e drawdown?
4. **Qual estratégia é mais eficiente** em retorno ajustado ao risco?

## Interpretação

- **Se VTI-AGG > P1**: O mercado oferece melhor retorno por unidade de risco
- **Se P1 > VTI-AGG**: A estratégia de baixa volatilidade adiciona valor

Esta comparação é fundamental para validar se a anomalia de baixa volatilidade realmente gera alpha ou se é apenas uma questão de exposição a fatores de risco tradicionais.