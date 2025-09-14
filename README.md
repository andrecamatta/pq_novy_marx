# Sistema de Análise Novy-Marx - Anomalia de Baixa Volatilidade

Sistema modular para análise da anomalia de baixa volatilidade no S&P 500, baseado na metodologia de Robert Novy-Marx. Implementado em Julia com arquitetura SOLID/DRY para robustez e extensibilidade.

[![Julia](https://img.shields.io/badge/Julia-1.6+-blue.svg)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 📊 Visão Geral

O sistema replica a análise clássica de Novy-Marx que demonstra como portfolios de baixa volatilidade superam portfolios de alta volatilidade no mercado americano, contrariando a teoria de finanças tradicional que relaciona maior risco a maior retorno.

### Características Principais
- **Análise de 15 anos** (2010-2025) com dados point-in-time do S&P 500
- **Sistema híbrido de dados**: Stooq bulk + API Tiingo com fallbacks inteligentes
- **Arquitetura modular**: Separação clara entre coleta, processamento e análise
- **Cache inteligente**: Sistema JLD2 para performance e confiabilidade
- **Benchmark integrado**: Comparação com portfolios RSP vs AGG
- **Taxa de sucesso**: 97.9% de coverage com dados reais

## 🚀 Instalação

### Dependências Julia
```julia
using Pkg
Pkg.add([
    "DataFrames", "CSV", "Dates", "Statistics", "Printf",
    "JLD2", "HTTP", "JSON3", "ZipFile", "YAML",
    "Plots", "StatsPlots", "Optim"
])
```

### Estrutura de Diretórios
```
pq_novy_marx/
├── src/                    # Código modular
├── config/                 # Configurações YAML
├── data/cache/            # Cache local (não versionado)
├── benchmark/             # Análise de benchmark
├── results/               # Outputs (não versionado)
└── novy_marx_analysis.jl # Script principal
```

## ⚙️ Configuração de Dados

### 1. Dados Stooq Bulk (Obrigatório)

⚠️ **Download Manual Necessário**: Devido a proteções CAPTCHA, você deve baixar manualmente:

```bash
# 1. Acesse: https://stooq.com/db/h/
# 2. Baixe: "US stocks daily" (d_us_txt.zip - ~506MB)
# 3. Coloque em: data/cache/stooq_bulk/d_us_txt.zip

# Criar diretório e mover arquivo
mkdir -p data/cache/stooq_bulk/
mv ~/Downloads/d_us_txt.zip data/cache/stooq_bulk/

# Verificar
ls -la data/cache/stooq_bulk/d_us_txt.zip
```

### 2. API Tiingo (Complementar)

Para melhorar a taxa de sucesso, configure uma API key gratuita:

```bash
# 1. Criar conta gratuita em https://api.tiingo.com/
# 2. Obter API key (1000 requests/dia grátis)
# 3. Criar arquivo .env na raiz do projeto:

echo "TIINGO_API_KEY=sua_api_key_aqui" > .env
```

**Exemplo .env:**
```
TIINGO_API_KEY=abc123def456ghi789jkl012mno345pqr678stu
TIINGO_DAILY_LIMIT=1000
TIINGO_CACHE_DIR=data/cache/tiingo
```

### 3. Configuração Avançada (Opcional)

Edite `config/ticker_config.yaml` para:
- Mapear tickers com mudanças corporativas
- Configurar preferências de fonte de dados
- Ajustar tratamento de aquisições/fusões

## 📈 Execução

### Análise Principal de 15 Anos
```bash
julia novy_marx_analysis.jl
```

**Outputs gerados:**
```
results/2009-08-01_to_2025-08-31/
├── portfolios_lookback_12.csv     # Retornos mensais dos quintis
├── results_lookback_12.json       # Métricas detalhadas
├── report_lookback_12.html        # Relatório visual completo
├── final_summary.json             # Resumo executivo
├── failed_tickers_report.txt      # Tickers não encontrados
└── figures/                       # Gráficos de performance
    ├── cumulative_lb12.png        # Retornos cumulativos
    ├── quintiles_lb12.png         # Performance por quintil
    ├── annual_returns_lb12.png    # Retornos anuais
    └── annual_sharpe_lb12.png     # Sharpe ratios anuais
```

### Análise de Benchmark
```bash
julia benchmark/rsp_agg_benchmark.jl
```

Compara estratégia P1-P5 contra portfolios RSP (S&P 500 Equal Weight) vs AGG (Bonds) com diferentes alocações para encontrar portfolio com volatilidade equivalente.

## 📊 Interpretação dos Resultados

### Métricas Principais
- **P1-P5 Strategy**: Diferença entre quintil de baixa e alta volatilidade
- **Sharpe Ratio**: Retorno ajustado ao risco
- **Maximum Drawdown**: Maior perda acumulada
- **Calmar Ratio**: Retorno anualizado / Max Drawdown

### Resultados Típicos (15 anos)
- **P1 (Baixa Vol)**: ~12% retorno, ~12% volatilidade
- **P5 (Alta Vol)**: ~15% retorno, ~24% volatilidade
- **P1-P5**: -3% a -4% (anomalia confirmada)
- **Coverage**: 97.9% dos tickers (758/774)

## 🛠️ Arquitetura do Sistema

### Módulos Principais
```
src/
├── data/
│   ├── sp500_constituents.jl    # Universo point-in-time
│   └── tiingo_data.jl           # API Tiingo
├── analysis/
│   ├── portfolio_construction.jl # Formação de quintis
│   ├── returns_calculation.jl    # Cálculo de retornos
│   └── volatility_analysis.jl    # Métricas de risco
├── cache_adapter.jl             # Sistema de cache
├── stooq_data.jl               # Dados Stooq bulk
└── results_export.jl           # Exportação e visualização
```

### Fluxo de Dados
1. **Carregamento**: Cache JLD2 → Stooq bulk → Tiingo API (fallback)
2. **Processamento**: Retornos mensais → Volatilidade rolling 12 meses
3. **Portfolios**: Quintis point-in-time com rebalanceamento mensal
4. **Análise**: Performance, drawdown, métricas de risco
5. **Export**: JSON, CSV, HTML, figuras PNG

### Metodologia Point-in-Time
- **Universo S&P 500**: Apenas ações presentes no índice na data de formação
- **Volatilidade**: Desvio padrão dos retornos mensais (12 meses)
- **Formação**: Equal-weight dentro de cada quintil
- **Rebalanceamento**: Mensal (sempre usando dados t-1)

## 🔄 Funcionalidades Pendentes

### Análise de Fatores
- [ ] **Fama-French 3 Fatores**: Regressão contra Market, SMB, HML
- [ ] **Fama-French 5 Fatores**: Adição de RMW e CMA
- [ ] **Momentum Factor**: Integração com UMD
- [ ] **Alpha decomposition**: Contribuição por fator

### Extensões Analíticas
- [ ] **Períodos alternativos**: 5, 10, 20 anos
- [ ] **Análise setorial**: Por GICS/SIC
- [ ] **Regime analysis**: Bull vs Bear markets
- [ ] **International**: Extensão para outros mercados
- [ ] **Alternative weighting**: Value-weight, risk parity

### Melhorias Técnicas
- [ ] **API alternativas**: Alpha Vantage, Yahoo Finance
- [ ] **Paralelização**: Processamento multi-thread
- [ ] **Dashboard**: Interface web interativa
- [ ] **Docker**: Containerização completa
- [ ] **Testes unitários**: Cobertura de código

## 📝 Exemplo de Uso Rápido

```julia
# Ativar ambiente do projeto
using Pkg; Pkg.activate(".")

# Carregar sistema
include("novy_marx_analysis.jl")

# Executar análise completa de 15 anos
run_complete_analysis()

# Verificar resultados
println("✅ Análise concluída!")
println("📁 Resultados em: results/2009-08-01_to_2025-08-31/")
println("📊 Relatório HTML: results/.../report_lookback_12.html")
```

## 🧪 Sistema de Cache

### Cache JLD2 Inteligente
- **Automático**: Downloads da API são automaticamente salvos
- **Persistente**: Reutilização entre execuções
- **Fallback**: Sistema funciona mesmo com cache vazio
- **Recovery**: Reconstrução completa a partir das fontes

### Hierarquia de Fontes
1. **Cache JLD2 Legacy** (mais rápido)
2. **Cache Tiingo Individual** (arquivos por ticker)
3. **Stooq Bulk Local** (ZIP de 506MB)
4. **Tiingo API Live** (com rate limiting)

## 🐛 Troubleshooting

### Problemas Comuns
- **Erro de API**: Verificar `.env` e limite diário Tiingo (1000/dia)
- **Cache corrompido**: Deletar `data/cache/tiingo/` específico
- **Arquivo Stooq**: Verificar se `d_us_txt.zip` está no local correto
- **Memória**: Análise consome ~2-4GB RAM para período completo
- **Tickers faltantes**: 16/774 falhas são normais (empresas adquiridas/falidas)

### Debug Verbose
```bash
# Ativar logs detalhados
export JULIA_DEBUG=Main
julia novy_marx_analysis.jl
```

### Verificação da Instalação
```julia
# Testar componentes principais
include("src/stooq_data.jl")
using .StooqData
status = StooqData.get_bulk_download_status()
println("Stooq ZIP: ", status.zip_exists ? "✅" : "❌")
```

## 📄 Licença

MIT License - Uso livre para pesquisa acadêmica e análise quantitativa.

## 🔗 Referências

### Acadêmicas
- **Novy-Marx, R.** (2011). "The other side of value: The gross profitability premium"
- **Baker, M., Bradley, B., & Wurgler, J.** (2011). "Benchmarks as limits to arbitrage: Understanding the low-volatility anomaly"
- **Frazzini, A., & Pedersen, L. H.** (2014). "Betting against beta"

### Dados
- **S&P 500 Historical Constituents**: Point-in-time membership
- **Stooq.com**: Dados históricos bulk (primário)
- **Tiingo API**: Dados complementares via API
- **Kenneth French**: Fatores Fama-French (pendente)

## 🙏 Agradecimentos

- **Kenneth French** pela disponibilização dos fatores Fama-French
- **Stooq.com** pelos dados históricos abrangentes
- **Tiingo** pela API complementar robusta
- **Comunidade Julia** pelos pacotes excelentes
- **Robert Novy-Marx** pela metodologia seminal