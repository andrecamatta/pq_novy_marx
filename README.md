# 🎯 Testando a Anomalia de Baixa Volatilidade com Correção de Viés de Sobrevivência

## Visão Geral

Este projeto testa se a **anomalia de baixa volatilidade** em retornos de ações possui alfa independente após controlar por fatores conhecidos, examinando especificamente a **crítica de Novy-Marx** de que muitas anomalias financeiras desaparecem sob metodologia rigorosa.

### Inovação Principal: Eliminação Completa do Viés de Sobrevivência

- **1.128 tickers únicos** de constituintes históricos do S&P 500 (1996-2025)
- **Universo point-in-time** usando dados reais de participação histórica
- **Metodologia adequada** seguindo padrões acadêmicos (Baker, Bradley & Wurgler 2011)

## 🎓 Contexto Acadêmico

**Crítica de Novy-Marx**: Muitas anomalias financeiras documentadas são artefatos estatísticos que desaparecem quando:
1. O viés de sobrevivência é adequadamente eliminado
2. Testes estatísticos rigorosos são aplicados
3. Custos de transação e restrições de implementação são considerados

**Anomalia de Baixa Volatilidade**: A descoberta empírica de que ações de baixo risco tendem a superar ações de alto risco em base ajustada ao risco.

## 📊 Dados e Metodologia

### Fontes de Dados
- **Constituintes históricos do S&P 500**: Dados obtidos de [hanshof/sp500_constituents](https://github.com/hanshof/sp500_constituents) (Licença MIT)
  - Arquivo: `sp_500_historical_components.csv` (29 anos de dados diários)
  - Fornece participação point-in-time no S&P 500 de 1996-2025
  - 1.128 tickers únicos rastreados ao longo do tempo
- **Dados de preços**: YFinance.jl para preços históricos reais
- **Modelos de fatores**: CAPM e modelos Fama-French para benchmarking

### Metodologia
1. **Construção de universo point-in-time** a partir da participação histórica no S&P 500
2. **Volatilidade móvel de 252 dias** com filtros acadêmicos
3. **Formação mensal de portfólios** (quintis) com lag de 1 mês
4. **Retornos de portfólio long-short** (baixa vol - alta vol)
5. **Testes estatísticos** via testes-t e testes GRS

## 🏗️ Estrutura do Projeto

```
pq_novy_marx/
├── sp_500_historical_components.csv    # Dados históricos do S&P 500 (1996-2025)
├── src/
│   ├── VolatilityAnomalyAnalysis.jl    # Módulo principal de análise
│   └── utils/
│       ├── config.jl                   # Parâmetros de análise
│       ├── portfolio_analysis.jl       # Funções centrais de portfólio
│       ├── historical_constituents.jl  # Utilitários de correção de viés
│       ├── real_sp500_data.jl         # Construtor de universo histórico
│       └── data_download.jl           # Download de dados reais
├── test_*.jl                          # Scripts de análise diversos
└── *.csv                              # Resultados gerados
```

## 🚀 Início Rápido

### Pré-requisitos
```julia
using Pkg
Pkg.add(["DataFrames", "Dates", "Statistics", "Distributions", "YFinance", "CSV"])
```

### Uso Básico
```julia
include("src/VolatilityAnomalyAnalysis.jl")
using .VolatilityAnomalyAnalysis

# Executar análise com correção de viés
results = PortfolioAnalysis.analyze_volatility_anomaly_with_bias_correction(
    Date(2000, 1, 1),
    Date(2024, 12, 31),
    "Teste de Baixa Volatilidade"
)

# Visualizar resultados
println("Retorno anual (Baixa Vol - Alta Vol): ", results.long_short_returns)
```

## 📈 Principais Descobertas (Trabalho em Progresso)

### Impacto do Viés de Sobrevivência
- **Antes da correção**: ~500 empresas atuais do S&P 500
- **Após a correção**: 1.128 constituintes históricos únicos
- **Melhoria**: universo 5,8x mais abrangente

### Validação da Linha do Tempo
- ✅ **2000**: Inclui Enron (ENRNQ), exclui Google/Meta/Tesla
- ✅ **2008**: Inclui Google, exclui Enron (pós-falência)
- ✅ **2020**: Stack tecnológico moderno presente, falências históricas ausentes
- ✅ **2024**: Configuração atual do S&P 500

## 🧪 Scripts de Teste

- `test_real_universe.jl` - Valida integração do universo de 1.128 tickers
- `test_bias_correction.jl` - Testa correção de viés de sobrevivência
- `test_yfinance.jl` - Testa download de dados reais

## 📚 Resultados Esperados

Baseado na literatura acadêmica pós-2000:
- **Alta volatilidade deve superar** baixa volatilidade
- **Efeito deve ser estatisticamente significativo** sob testes adequados
- **Confirma crítica de Novy-Marx** se anomalia desaparecer com correção de viés

## ⚠️ Status Atual

**🚧 Trabalho em Progresso**

- ✅ Correção de viés de sobrevivência implementada e validada
- ✅ Universo histórico (1.128 tickers) integrado com sucesso
- ✅ Metodologia point-in-time funcionando corretamente
- 🔄 Integração YFinance para download de dados reais (em progresso)
- 🔄 Execução completa da análise com dataset completo
- 📋 Resultados estatísticos finais e interpretação

## 🤝 Contributing

Este é um projeto de pesquisa ativo. Contribuições bem-vindas para:
- Otimização de código e correção de bugs
- Metodologias adicionais de correção de viés
- Integração de fontes de dados alternativas
- Melhorias em testes estatísticos
- Documentação e exemplos

## 📖 References

- Baker, M., Bradley, B., & Wurgler, J. (2011). Benchmarks as limits to arbitrage
- Novy-Marx, R. (2013). The other side of value: The gross profitability premium  
- Ang, A., Hodrick, R. J., Xing, Y., & Zhang, X. (2006). The cross‐section of volatility and expected returns

## 🙏 Agradecimentos e Atribuição de Dados

- **Dados Históricos do S&P 500**: Agradecimentos especiais a [hanshof/sp500_constituents](https://github.com/hanshof/sp500_constituents) por fornecer dados abrangentes de constituintes históricos do S&P 500 sob Licença MIT. Este dataset é crucial para nossa metodologia de correção de viés de sobrevivência.

## 📄 Licença

Licença MIT - veja o arquivo LICENSE para detalhes.

## 📧 Contato

**André Camatta** - [@andrecamatta](https://github.com/andrecamatta)

---

*Este projeto visa contribuir para o entendimento acadêmico de anomalias financeiras e a importância de metodologia rigorosa em pesquisa de finanças empíricas.*

**Testando a Crítica de Novy-Marx com Padrões Acadêmicos**

Uma implementação limpa e modular para testar se a anomalia de baixa volatilidade persiste sob metodologia acadêmica rigorosa.


## 🚀 Quick Start

### Installation
```bash
# Clone repository
git clone <repository-url>
cd volatility-anomaly-analysis

# Julia will auto-install required packages on first run
```

### Basic Usage
```bash
# Run complete analysis (recommended)
julia main_analysis.jl

# Quick test with smaller universe
julia main_analysis.jl test

# View previous results
julia main_analysis.jl results

# Show help
julia main_analysis.jl help
```

### Interactive Usage
```julia
julia> include("main_analysis.jl")
julia> demo()  # Quick demonstration
```

## 📊 Output

Analysis results are saved to `./results/`:

- **`statistical_summary.csv`** - Key statistics by period
- **`monthly_returns_*.csv`** - Monthly return series
- **`novy_marx_test.json`** - Hypothesis test results  
- **`analysis_report.txt`** - Comprehensive text report

## 🔬 Methodology

### Academic Standards Implemented
- ✅ **1-month formation lag** (Baker, Bradley & Wurgler 2011 standard)
- ✅ **Point-in-time analysis** (survivorship bias correction)
- ✅ **Academic filtering** (minimum price $5, sufficient data)
- ✅ **Proper statistical testing** (t-tests, confidence intervals)
- ✅ **Multiple time periods** (2000-2009, 2010-2019, 2020-2024)

### Portfolio Formation Process
1. **Volatility Calculation**: Rolling 252-day volatility
2. **Monthly Ranking**: Sort stocks by volatility  
3. **Quintile Portfolios**: 5 portfolios (P1=Low Vol, P5=High Vol)
4. **Academic Lag**: 1-month lag between formation and investment
5. **Return Calculation**: Equal-weighted portfolio returns

### Statistical Testing
- **T-statistics** with proper degrees of freedom
- **Two-tailed hypothesis testing** 
- **95% confidence intervals**
- **Effect size measurement** (Cohen's d)
- **Economic significance** classification

## 📁 Project Structure

```
src/
├── VolatilityAnomalyAnalysis.jl      # Main module
└── utils/
    ├── config.jl                     # Configuration parameters
    ├── data_download.jl              # YFinance data utilities  
    ├── portfolio_analysis.jl         # Portfolio formation & returns
    └── statistics.jl                 # Statistical testing

main_analysis.jl                      # Executable script
results/                              # Output directory
archive/                              # Previous development versions
```

## ⚙️ Configuration

Modify analysis parameters in `src/utils/config.jl`:

```julia
# Volatility calculation
VOLATILITY_CONFIG = Dict(
    :window => 252,                    # Rolling window (days)
    :min_data_pct => 0.8,             # Minimum data availability
    :extreme_return_threshold => 3.0   # Filter extreme returns
)

# Portfolio formation  
PORTFOLIO_CONFIG = Dict(
    :n_portfolios => 5,               # Number of portfolios
    :formation_lag => 1,              # Academic lag (months)
    :min_stocks => 20                 # Minimum stocks per portfolio
)
```

## 📈 Expected Results

### Hypothesis Testing
The analysis tests whether the low volatility anomaly:
- **CONFIRMS** Novy-Marx critique → Not statistically significant
- **CONTRADICTS** Novy-Marx critique → Statistically significant
- **MIXED EVIDENCE** → Inconsistent across periods

### Typical Output
```
NOVY-MARX HYPOTHESIS TEST
------------------------
Result: CONFIRMS Novy-Marx critique (Confidence: HIGH)
Significant Periods: 1/3
Mean Annual Return: -8.2%
Mean T-Statistic: -1.30

Interpretation: Based on rigorous testing, the low volatility 
anomaly does not persist under academic standards, supporting 
Novy-Marx's critique of factor mining in finance literature.
```

## 🛠️ Requisitos

- **Julia** 1.6+ (testado em 1.9+)
- **Conexão com internet** (para API do YFinance)
- **Pacotes** (instalados automaticamente):
  - YFinance.jl
  - DataFrames.jl  
  - Dates.jl
  - CSV.jl
  - JSON.jl
  - StatsBase.jl
  - Distributions.jl

## 🔧 Solução de Problemas

### Problemas Comuns

**Timeouts da API YFinance**
```bash
# Verifique a conexão com internet
# Algumas redes corporativas bloqueiam Yahoo Finance
# Tente universo menor: julia main_analysis.jl test
```

**Erros de Instalação de Pacotes**
```julia
# Instalação manual de pacotes
using Pkg
Pkg.add(["YFinance", "DataFrames", "CSV", "JSON", "StatsBase"])
```

**Dados Insuficientes**
```
# Reduza os requisitos mínimos de dados em config.jl
# Ou use períodos menores
```

## 📚 Referências Acadêmicas

- **Baker, Bradley & Wurgler (2011)** - "Benchmarks as Limits to Arbitrage"
- **Novy-Marx (2012)** - "Is momentum really momentum?"  
- **Frazzini & Pedersen (2014)** - "Betting Against Beta"

## 🤝 Contribuindo

1. **Issues**: Relate bugs ou sugira funcionalidades
2. **Pull Requests**: Siga o estilo de código existente
3. **Testes**: Adicione testes unitários para novas funcionalidades
4. **Documentação**: Atualize docstrings e README

## 📄 License

MIT License - see LICENSE file for details.

## 📞 Suporte

Para perguntas ou problemas:
- Verifique `julia main_analysis.jl help`
- Revise a seção de solução de problemas
- Abra uma issue no GitHub com:
  - Versão do Julia
  - Mensagens de erro
  - Detalhes do sistema

---

**Aviso Legal**: Esta ferramenta é para propósitos de pesquisa acadêmica. Os resultados devem ser validados independentemente antes de tomar decisões de investimento.