# 🎯 NovoMarxAnalysis.jl

**Implementação Acadêmica Completa da Metodologia Novy-Marx para Teste Rigoroso de Anomalias Financeiras**

[![Julia](https://img.shields.io/badge/Julia-1.6+-blue.svg)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 🏆 Visão Geral

**NovoMarxAnalysis.jl** é uma implementação academicamente rigorosa da crítica de **Novy-Marx (2013)** para teste de anomalias financeiras. O pacote transforma a pesquisa de anomalias de **testes de retornos brutos metodologicamente questionáveis** para **análise de alfas ajustados por fatores academicamente defensável**.

### 💡 Insight Acadêmico Central

A crítica de Novy-Marx demonstra que muitas anomalias financeiras "significativas" desaparecem quando controles adequados de fatores sistemáticos são aplicados. Este pacote implementa essa metodologia rigorosa.

**Transformação Metodológica:**
- ❌ **Antes**: Testa se `H₀: retorno = 0`  
- ✅ **Depois**: Testa se `H₀: α = 0` em `R_p - R_f = α + β₁×MKT_RF + β₂×SMB + β₃×HML + β₄×RMW + β₅×CMA + ε`

## 🎯 Características Principais

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

### Exemplo Básico - Análise de Anomalia

```julia
using NovoMarxAnalysis

# Simular retornos de portfólio (substitua pelos seus dados)
portfolio_returns = randn(48) .* 2 .+ 0.5  # 48 meses de retornos

# Análise completa seguindo metodologia Novy-Marx
results = analyze_low_volatility_anomaly(
    portfolio_returns,
    Date(2020, 1, 1),
    Date(2023, 12, 31),
    verbose=true
)

# Ver conclusão acadêmica
println(results.novy_marx_conclusion)
```

### Exemplo Avançado - Teste Conjunto de Portfólios

```julia
# Múltiplos portfólios para teste GRS
factors = download_fama_french_factors(Date(2020,1,1), Date(2023,12,31))

# Executar regressões individuais
results_low_vol = run_ff5_regression(returns_low_vol, factors, "Low Vol")
results_high_vol = run_ff5_regression(returns_high_vol, factors, "High Vol")

# Teste de significância conjunta
grs_results = test_joint_significance([results_low_vol, results_high_vol])
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
│   └── multifactor_regression.jl # Engine completo de regressões
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
- **Depois**: Testes de alfas ajustados por fatores (academicamente defensável)

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