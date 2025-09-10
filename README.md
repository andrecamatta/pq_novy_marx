# Novy-Marx S&P 500 Low Volatility Analysis System

**Sistema completo e unificado para análise da anomalia de baixa volatilidade no universo S&P 500 usando metodologia point-in-time rigorosa.**

[![Julia](https://img.shields.io/badge/Julia-1.6+-blue.svg)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 🎯 Características Principais

- **Análise flexível**: Qualquer período de 1996 até hoje
- **Universo S&P 500 completo**: ~500+ tickers com dados históricos
- **Metodologia point-in-time**: Elimina survivorship bias
- **Modelos de fatores**: CAPM, Fama-French 3F, 5F
- **Visualizações completas**: Gráficos profissionais com Plots.jl
- **Saídas estruturadas**: CSV, JSON, HTML
- **Cache inteligente**: Otimização de downloads

## 🚀 Uso Rápido

```julia
using Pkg
Pkg.activate(".")

include("novy_marx_sp500_analysis.jl")

# Análise padrão (2020-2024)
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

# Análise rápida
results = quick_analysis(Date(2020,1,1), Date(2024,10,31))
```

## 📊 Resultados 2020-2024

Baseado em testes preliminares com amostra do S&P 500:

```
📈 PERFORMANCE DOS QUINTIS (Anualizada):
P1 (Low Vol):    11.4% retorno anual
P5 (High Vol):   38.9% retorno anual
P1 - P5:        -27.6% (Sharpe: -1.045)

🔄 REVERSÃO DA ANOMALIA DETECTADA!
Alta volatilidade superou baixa volatilidade no período COVID
```

## 🏆 Visão Geral

**Sistema unificado** que implementa rigorosamente a metodologia **Novy-Marx (2013)** para teste da anomalia de baixa volatilidade no S&P 500, com eliminação completa do survivorship bias através de análise point-in-time.

### 💡 Insight Acadêmico Central

Transforma análise de anomalias de **testes de retornos brutos** para **análise de alfas ajustados por fatores**:
- ❌ **Antes**: Testa se `H₀: retorno = 0`  
- ✅ **Depois**: Testa se `H₀: α = 0` em `R_p - R_f = α + β₁×MKT_RF + β₂×SMB + β₃×HML + ε`

## 🗂️ Estrutura do Projeto

```
pq_novy_marx/
├── novy_marx_sp500_analysis.jl    # ✨ Sistema principal unificado
├── src/                           
│   ├── market_data.jl             # Download e processamento
│   ├── fama_french_factors.jl     # Fatores Fama-French
│   ├── multifactor_regression.jl  # Análises estatísticas
│   ├── ticker_resolver.jl         # Resolução de símbolos
│   ├── visualization.jl           # Visualizações completas
│   └── NovoMarxAnalysis.jl        # Módulo principal
├── data/
│   └── sp_500_historical_components.csv  # Histórico S&P 500
├── results/                        # Saídas das análises
├── test/                          # Testes unitários
└── Project.toml                   # Dependências Julia
```

## ⚙️ Configurações Disponíveis

```julia
AnalysisConfig(
    # Período
    start_date = Date(2020, 1, 1),
    end_date = Date(2024, 10, 31),
    
    # Metodologia
    lookback_periods = [6, 12, 24],  # Múltiplas janelas
    min_coverage = 0.6,              # Cobertura mínima
    min_per_quintile = 5,            # Mín por quintil
    
    # Modelos
    factor_models = [:CAPM, :FF3, :FF5],
    
    # Output
    output_formats = [:csv, :json, :html],
    create_plots = true,
    
    # Análises adicionais
    run_subperiod_analysis = true,
    run_robustness_tests = true
)
```

## 📈 Visualizações Geradas

1. **Retornos Cumulativos**: Performance de cada quintil ao longo do tempo
2. **Rolling Metrics**: Sharpe ratio e volatilidade móvel
3. **Comparação de Quintis**: Barras com retorno/risco por quintil
4. **Factor Loadings**: Exposição a fatores de risco
5. **Drawdown Analysis**: Análise de perdas máximas
6. **Dashboard Completo**: Visão consolidada

## 📊 Saídas Estruturadas

```
results/2020-01-01_to_2024-10-31/
├── portfolios_lookback_12.csv     # Retornos mensais
├── results_lookback_12.json       # Performance e fatores
├── report_lookback_12.html        # Relatório formatado
├── subperiod_analysis.json        # Análise temporal
├── robustness_tests.json          # Testes de robustez
├── final_summary.json             # Resumo consolidado
└── figures/
    ├── cumulative_lb12.png
    ├── rolling_sharpe_lb12.png
    ├── quintiles_lb12.png
    └── factors_lb12.png
```

## 🔬 Metodologia

### Point-in-Time
- Usa apenas dados disponíveis em cada momento histórico
- Inclui empresas extintas/adquiridas quando relevantes
- Elimina survivorship bias completamente

### Formação de Quintis
1. Calcula volatilidade histórica (lookback period)
2. Ordena ações por volatilidade
3. Forma 5 portfolios equally-weighted
4. Rebalanceia mensalmente

### Análise de Fatores
- **CAPM**: Ajusta por risco de mercado
- **FF3**: + Size (SMB) e Value (HML)  
- **FF5**: + Profitability (RMW) e Investment (CMA)

## 🧪 Testes de Robustez

- **Múltiplos lookback periods**: Consistência entre janelas
- **Análise de subperíodos**: Estabilidade temporal
- **Rolling Sharpe**: Variação ao longo do tempo
- **Correlação entre períodos**: Persistência da estratégia

## 🔧 Funcionalidades Técnicas

### 📊 Dados Reais de Fatores
- ✅ **Kenneth French Data Library**: Download automático de fatores reais
- ✅ **744+ observações mensais** (1963-2025)
- ✅ **Fatores Fama-French 5**: MKT-RF, SMB, HML, RMW, CMA, RF
- ✅ **Parsing robusto** com tratamento de erros

### 🔬 Engine de Regressões Multifator
- ✅ **CAPM**: `R_p - R_f = α + β×(R_m - R_f) + ε`
- ✅ **FF3**: Adicionalmente SMB e HML
- ✅ **FF5**: Modelo completo com RMW e CMA
- ✅ **Estatísticas completas**: t-testes, p-valores, R²
- ✅ **Seleção automática** do melhor modelo

## 📚 Referências

- Novy-Marx, R. (2013). "The other side of value: The gross profitability premium"
- Baker, Bradley, Wurgler (2011). "Benchmarks as Limits to Arbitrage"
- Frazzini, Pedersen (2014). "Betting Against Beta"
- Blitz, Van Vliet (2007). "The Volatility Effect"

## 🛠️ Instalação

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()  # Instala todas as dependências
```

## ⚠️ Limitações Conhecidas

- API Yahoo Finance tem rate limits (aguardar 1-2h se atingir)
- Alguns tickers extintos podem não ter dados disponíveis
- Período mínimo recomendado: 2+ anos para significância

## 📞 Suporte

Para questões ou sugestões, abrir issue no repositório.

---

**Sistema desenvolvido com rigor acadêmico para análise da anomalia de baixa volatilidade**
- ✅ **CAPM**: `R_p - R_f = α + β×(R_m - R_f) + ε`
- ✅ **FF3**: Adicionalmente SMB e HML
- ✅ **FF5**: Modelo completo com RMW e CMA
- ✅ **Estatísticas completas**: t-testes, p-valores, R²
- ✅ **Seleção automática** do melhor modelo

### 🧪 Testes de Significância Conjunta
- ✅ **Teste GRS**: Significância conjunta de alfas em múltiplos portfólios
- ✅ **Interpretação automática**: Conclusões seguindo metodologia Novy-Marx
- ✅ **Comparação de modelos**: CAPM vs FF3 vs FF5

### 📦 Estrutura Julia Profissional
- ✅ **Pacote padrão Julia** com Project.toml
- ✅ **API limpa** através do módulo principal
- ✅ **Testes abrangentes** em suite automatizada
- ✅ **Exemplos práticos** para aprendizado

## 📦 Instalação

### Como Pacote Julia (Recomendado)

```julia
using Pkg
Pkg.develop(path="caminho/para/NovoMarxAnalysis")

# Ou clone e instale
Pkg.develop(url="https://github.com/andrecamatta/pq_novy_marx.git")
```

### Dependências
O pacote instala automaticamente:
- DataFrames.jl, Dates.jl, Statistics.jl
- Distributions.jl, StatsBase.jl, LinearAlgebra.jl  
- HTTP.jl, CSV.jl, Printf.jl

## 🚀 Uso Rápido

### Exemplo Rápido (Alinhado por Data, 25+ anos)

```julia
using NovoMarxAnalysis, .NovoMarxAnalysis
include("src/market_data.jl"); using .MarketData
include("src/fama_french_factors.jl"); using .FamaFrenchFactors

# 1) Portfólios P1..P5 point-in-time (1999–2024) com lag do sinal
portfolios = MarketData.get_quintile_portfolios_pti(Date(1999,1,1), Date(2024,12,31))

# 2) Fatores FF5 reais
factors = FamaFrenchFactors.get_ff5_factors(start_date=Date(1999,1,1), end_date=Date(2024,12,31))

# 3) Análise alinhada (preferível acadêmicamente)
analysis = analyze_low_volatility_anomaly_aligned(portfolios, factors, "LowMinusHigh", verbose=true)

# 4) Conclusão acadêmica
println(analysis.novy_marx_conclusion)
```

### Exemplo Avançado - Teste Conjunto (GRS completo)

```julia
# Assumindo `portfolios` e `factors` como acima
quintile_cols = ["P1","P2","P3","P4","P5"]
ff5_results = RegressionResult[]
for col in quintile_cols
    res = run_ff5_regression_aligned(portfolios, factors, col, portfolio_name=col, robust=true)
    if res !== nothing
        push!(ff5_results, res)
    end
end
grs_results = grs_test_full(ff5_results, factors, model=:FF5)
println(grs_results[:conclusion])
```

### API Simplificada

```julia
# Informações do pacote
package_info()

# Dados de exemplo
sample_data = get_sample_data()

# Download de fatores Fama-French
factors = download_fama_french_factors(Date(2020,1,1), Date(2023,12,31))

# Resumo dos fatores
summarize_factors(factors)
```

## 🏗️ Estrutura do Projeto

```
📦 NovoMarxAnalysis.jl/
├── 📄 Project.toml              # Manifesto do pacote Julia
├── 📄 README.md                 # Este arquivo
├── 📄 LICENSE                   # Licença MIT
│
├── 📁 src/                      # Código principal
│   ├── NovoMarxAnalysis.jl      # Módulo principal com API limpa
│   ├── fama_french_factors.jl   # Download e parsing de dados reais FF
│   └── multifactor_regression.jl # Engine completo de regressões (inclui versões alinhadas + GRS completo)
│
├── 📁 test/                     # Suite de testes
│   ├── runtests.jl              # Executor principal de testes  
│   ├── test_ff_integration.jl   # Testes de integração Fama-French
│   └── test_multifactor_regression.jl # Testes das regressões
│
├── 📁 examples/                 # Exemplos e demonstrações
│   ├── demo_novy_marx_methodology.jl # Demonstração metodológica
│   └── novy_marx_analysis.jl   # Análise completa de exemplo
│
└── 📁 data/                     # Dados essenciais
    ├── sp_500_historical_components.csv # Dados survivorship S&P 500
    ├── real_sp500_universe_validation.csv # Validação de universo
    └── github_sp500_universe_validation.csv # Validação GitHub
```

## 🧪 Executar Testes

```julia
# Na pasta do projeto
using Pkg
Pkg.test()

# Ou manualmente
include("test/runtests.jl")
```

## 📊 Dados e Correção de Viés de Sobrevivência  

### Universo Histórico S&P 500
- **1.128 tickers únicos** de constituintes históricos (1996-2025)
- **Análise point-in-time** usando participação real histórica
- **Eliminação completa do viés de sobrevivência**

### Fonte de Dados
Dados históricos do S&P 500 obtidos de [hanshof/sp500_constituents](https://github.com/hanshof/sp500_constituents) sob licença MIT, incluindo empresas que faliram, foram adquiridas ou removidas do índice.

## 🎓 Contexto Acadêmico

### Crítica de Novy-Marx
Robert Novy-Marx (2013) demonstrou que muitas anomalias financeiras documentadas são **artefatos estatísticos** que desaparecem quando:

1. ✅ **Viés de sobrevivência é adequadamente eliminado**
2. ✅ **Controles de fatores sistemáticos são aplicados**  
3. ✅ **Testes estatísticos rigorosos são utilizados**
4. ✅ **Custos de transação são considerados**

### Padrão Acadêmico Moderno
- **Antes**: Testes de retornos brutos (metodologicamente insuficiente)
- **Depois**: Testes de alfas ajustados por fatores (academicamente defensável), com alinhamento por data (Date join), GRS completo e erros‑padrão robustos quando necessário.

Este pacote implementa o padrão moderno, tornando-se ferramenta essencial para pesquisa acadêmica rigorosa.

## 💡 Casos de Uso

### 🎯 Pesquisa Acadêmica
- Teste de anomalias financeiras com rigor metodológico
- Validação de estratégias de investimento
- Pesquisa em finanças comportamentais
- Estudos de eficiência de mercado

### 🏦 Aplicações Práticas  
- Avaliação de performance de fundos
- Desenvolvimento de estratégias quantitativas
- Análise de risco-retorno ajustada por fatores
- Due diligence de produtos de investimento

### 📚 Ensino
- Demonstração de metodologia Novy-Marx
- Comparação entre abordagens metodológicas
- Ensino de regressões multifator
- Ilustração de viés de sobrevivência

## ⚡ Performance e Escalabilidade

- ✅ **Downloads otimizados** com cache automático
- ✅ **Cálculos vetorizados** para performance
- ✅ **Tratamento robusto de erros**
- ✅ **Memory-efficient** para datasets grandes
- ✅ **Paralelização** ready para múltiplos portfólios

## 🤝 Contribuições

Contribuições são bem-vindas! Áreas prioritárias:

- 🔬 **Modelos adicionais**: Carhart 4-factor, Q-factor model
- 📊 **Visualizações**: Plots e gráficos integrados
- 🚀 **Performance**: Otimizações de código
- 📚 **Documentação**: Exemplos e tutoriais
- 🧪 **Testes**: Cobertura adicional

## 📖 Referências Acadêmicas

- **Novy-Marx, R.** (2013). The other side of value: The gross profitability premium. *Journal of Financial Economics*, 108(1), 1-28.

- **Baker, M., Bradley, B., & Wurgler, J.** (2011). Benchmarks as limits to arbitrage: Understanding the low-volatility anomaly. *Financial Analysts Journal*, 67(1), 40-54.

- **Fama, E. F., & French, K. R.** (2015). A five-factor asset pricing model. *Journal of Financial Economics*, 116(1), 1-22.

- **Gibbons, M. R., Ross, S. A., & Shanken, J.** (1989). A test of the efficiency of a given portfolio. *Econometrica*, 57(5), 1121-1152.

## 🙏 Agradecimentos

### Dados Históricos S&P 500
Agradecimentos especiais a [hanshof/sp500_constituents](https://github.com/hanshof/sp500_constituents) por fornecer dados abrangentes de constituentes históricos do S&P 500 sob Licença MIT. Este dataset é **crucial** para nossa metodologia de correção de viés de sobrevivência.

### Kenneth French Data Library
Dados de fatores Fama-French obtidos da [Kenneth French Data Library](https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/data_library.html) da Tuck School of Business, Dartmouth College.

## 📄 Licença

**MIT License** - veja o arquivo [LICENSE](LICENSE) para detalhes.

## 📧 Contato

**André Camatta** - [@andrecamatta](https://github.com/andrecamatta)

---

## 🎯 Mensagem Final

> *"Este pacote visa elevar o padrão de pesquisa em anomalias financeiras, transformando testes metodologicamente questionáveis em análises academicamente defensáveis. A crítica de Novy-Marx não é apenas técnica—é fundamental para o entendimento correto de eficiência de mercado."*

**🏆 NovoMarxAnalysis.jl - Onde Rigor Metodológico Encontra Implementação Prática**

---

*Testando Anomalias Financeiras com Padrões Acadêmicos do Século XXI*
