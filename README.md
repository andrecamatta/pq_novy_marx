# Novy-Marx S&P 500 Low Volatility Analysis System

**Sistema completo para análise da anomalia de baixa volatilidade no universo S&P 500 usando metodologia point-in-time rigorosa.**

[![Julia](https://img.shields.io/badge/Julia-1.6+-blue.svg)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 🎯 Características Principais

- **Análise flexível**: Qualquer período de 1996 até hoje
- **Universo S&P 500 completo**: ~500+ tickers com dados históricos
- **Metodologia point-in-time**: Elimina survivorship bias
- **Sistema híbrido de dados**: Stooq (bulk) + Tiingo (fallback)
- **Modelos de fatores**: CAPM, Fama-French 3F, 5F
- **Visualizações completas**: Gráficos profissionais com Plots.jl
- **Saídas estruturadas**: CSV, JSON, HTML

## 📥 Sistema de Dados - Download Obrigatório

### ⚠️ IMPORTANTE: Download Manual do Stooq

Este sistema requer dados históricos completos do mercado americano. Devido a proteções anti-bot (CAPTCHA), você **DEVE** baixar manualmente:

1. **Acesse**: https://stooq.com/db/h/
2. **Baixe**: `US stocks daily` (arquivo `d_us_txt.zip` com ~500 MB)
3. **Coloque em**: `data/cache/stooq_bulk/d_us_txt.zip`

```bash
# Criar diretório se não existir
mkdir -p data/cache/stooq_bulk/

# Mover arquivo baixado para o local correto
mv ~/Downloads/d_us_txt.zip data/cache/stooq_bulk/
```

⚠️ **Nota**: Este arquivo não está no GitHub devido ao tamanho. Cada usuário deve baixá-lo individualmente.

### Sistema Híbrido Stooq + Tiingo

O sistema utiliza uma abordagem híbrida para máxima cobertura de dados:

1. **Stooq (Primário)**: Dados bulk sem limites de API
2. **Tiingo (Fallback)**: Para tickers não encontrados no Stooq

#### Configuração do Tiingo (Opcional mas Recomendado)

Para melhor taxa de sucesso, configure uma API key gratuita do Tiingo:

1. Registre-se em https://www.tiingo.com/
2. Obtenha sua API key gratuita
3. Crie arquivo `.env` na raiz do projeto:

```bash
# .env
TIINGO_API_KEY=sua_chave_api_aqui
```

**Limitações do Tiingo (Plano Gratuito):**
- 50 requisições por hora
- 1.000 requisições por dia
- 500 símbolos únicos por mês

## 🔬 Metodologia de Formação dos Quintis

### 1. Universo Point-in-Time (PTI)
- Determina quais ações estavam no S&P 500 na data de formação (mês t-1)
- Usa arquivo `sp_500_historical_components.csv` com constituintes históricos
- Elimina viés de sobrevivência usando apenas ações presentes no índice naquele momento

### 2. Cálculo da Volatilidade Histórica
Para cada ação elegível:
- Calcula o desvio padrão dos retornos mensais dos últimos 12 meses
- Requer mínimo 70% de cobertura (9 dos 12 meses com dados válidos)

### 3. Ordenação e Divisão em Quintis
```
Ordenação: Menor volatilidade → Maior volatilidade

P1: 20% das ações com MENOR volatilidade (Low Vol)
P2: Próximos 20%
P3: 20% médios
P4: Próximos 20%
P5: 20% das ações com MAIOR volatilidade (High Vol)
```

### 4. Formação das Carteiras
- Cada quintil forma uma carteira **equal-weighted**
- Rebalanceamento mensal
- Lag de 1 mês: usa dados até t-1 para formar carteiras em t

### 5. Estratégia Long-Short
```
LowMinusHigh = Retorno(P1) - Retorno(P5)
```
- Positivo: baixa volatilidade supera alta volatilidade (anomalia clássica)
- Negativo: reversão da anomalia (alta vol supera baixa vol)

### Critérios para Mês Válido

Um mês é considerado válido quando:

1. **Universo mínimo**: ≥100 tickers elegíveis (20 por quintil × 5)
2. **Cobertura histórica**: ≥70% dos dados nos 12 meses anteriores
3. **Formação completa**: Todos 5 quintis formados com sucesso
4. **Cobertura no holding**: ≥70% dos tickers com retorno válido
5. **Validação final**: Todos quintis (P1-P5) atendem os critérios

## 🚀 Uso Rápido

```julia
using Pkg
Pkg.activate(".")

include("novy_marx_sp500_analysis.jl")

# Análise padrão (últimos 5 anos)
results = analyze_sp500()

# Análise customizada
config = AnalysisConfig(
    start_date = Date(2010, 1, 1),
    end_date = Date(2024, 12, 31),
    lookback_periods = [12],
    factor_models = [:CAPM, :FF3],
    create_plots = true
)
results = analyze_sp500(config)

# Análise rápida
results = quick_analysis(Date(2015,1,1), Date(2024,12,31))
```

## 🏗️ Estrutura do Projeto

```
pq_novy_marx/
├── novy_marx_sp500_analysis.jl    # Sistema principal unificado
├── src/
│   ├── market_data.jl             # Download e processamento
│   ├── stooq_data.jl              # Sistema bulk Stooq
│   ├── tiingo_data.jl             # API Tiingo fallback
│   ├── ticker_config.jl           # Mapeamentos YAML
│   ├── fama_french_factors.jl     # Fatores Fama-French
│   ├── multifactor_regression.jl  # Análises estatísticas
│   └── visualization.jl           # Visualizações
├── config/
│   └── ticker_config.yaml         # Mapeamentos corporativos
├── data/
│   ├── sp_500_historical_components.csv  # Histórico S&P 500
│   └── cache/                     # Cache de dados
├── examples/                       # Scripts de exemplo
│   ├── execute_5year_analysis.jl
│   ├── execute_10year_analysis.jl
│   └── execute_15year_analysis.jl
├── results/                        # Saídas das análises
└── Project.toml                   # Dependências Julia
```

## ⚙️ Configurações Disponíveis

```julia
AnalysisConfig(
    # Período
    start_date = Date(2010, 1, 1),
    end_date = Date(2024, 12, 31),

    # Metodologia
    lookback_periods = [12],         # Janela de volatilidade (meses)
    min_coverage = 0.7,              # Cobertura mínima (70%)
    min_per_quintile = 20,           # Mínimo 20 ações por quintil

    # Modelos
    factor_models = [:CAPM, :FF3, :FF5],

    # Output
    output_formats = [:csv, :json, :html],
    create_plots = true,

    # Análises adicionais
    run_subperiod_analysis = true,
    run_robustness_tests = true,

    # Cache
    use_cache = true,
    force_redownload = false
)
```

## 📊 Saídas Estruturadas

```
results/YYYY-MM-DD_to_YYYY-MM-DD/
├── portfolios_lookback_12.csv     # Retornos mensais dos quintis
├── results_lookback_12.json       # Performance e fatores
├── report_lookback_12.html        # Relatório formatado
├── subperiod_analysis.json        # Análise temporal
├── robustness_tests.json          # Testes de robustez
├── failed_tickers_report.txt      # Tickers que falharam
├── final_summary.json             # Resumo consolidado
└── figures/
    ├── cumulative_lb12.png        # Retornos cumulativos
    ├── quintiles_lb12.png         # Comparação de quintis
    └── [outros gráficos]
```

## 📚 Fontes de Dados e Créditos

### Dados de Preços Históricos
- **Stooq.com**: Fonte primária de dados históricos de preços (bulk download)
- **Tiingo API**: Fonte secundária para tickers não disponíveis no Stooq
- Licenças: Verificar termos de uso de cada provedor

### Fatores Fama-French
- **Kenneth French Data Library**: https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/data_library.html
- Fatores: MKT-RF, SMB, HML, RMW, CMA, RF
- Cobertura: 1963-presente, atualização mensal
- Cortesia: Tuck School of Business, Dartmouth College

### Composição Histórica S&P 500
- **Fonte**: https://github.com/hanshof/sp500_constituents
- Licença: MIT
- Cobertura: 1996-presente
- Inclui empresas delistadas, adquiridas e falidas (elimina survivorship bias)

### Mapeamentos Corporativos
- **ticker_config.yaml**: Mapeamentos de mudanças corporativas
- Mantido manualmente com base em eventos corporativos públicos
- Inclui: renomeações, fusões, aquisições, falências

## 🧪 Testes de Robustez

- **Múltiplos lookback periods**: Consistência entre janelas
- **Análise de subperíodos**: Estabilidade temporal
- **Rolling Sharpe**: Variação ao longo do tempo
- **Testes GRS**: Significância conjunta de alfas

## ⚠️ Limitações Conhecidas

### Taxa de Sucesso de Dados
- **5 anos**: Tipicamente 98-99% dos tickers
- **10 anos**: Tipicamente 93-99% dos tickers
- **15 anos**: Tipicamente 87-93% dos tickers

### Tickers que Frequentemente Falham
- Empresas adquiridas antes do período (ex: XLNX→AMD, WFM→AMZN)
- Empresas falidas (ex: FRC, SIVB, JCP)
- Empresas delistadas/OTC (ex: ENDP→ENDPQ)
- Mudanças complexas não mapeadas

### Limitações das APIs
- Stooq: Requer download manual (CAPTCHA)
- Tiingo: 50 req/hora no plano gratuito
- Não há suporte para download em lote no Tiingo

## 🛠️ Instalação

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()  # Instala todas as dependências

# Verificar instalação
include("novy_marx_sp500_analysis.jl")
```

## 📖 Referências Acadêmicas

- **Novy-Marx, R.** (2013). "The other side of value: The gross profitability premium". *Journal of Financial Economics*, 108(1), 1-28.

- **Baker, M., Bradley, B., & Wurgler, J.** (2011). "Benchmarks as limits to arbitrage: Understanding the low-volatility anomaly". *Financial Analysts Journal*, 67(1), 40-54.

- **Fama, E. F., & French, K. R.** (2015). "A five-factor asset pricing model". *Journal of Financial Economics*, 116(1), 1-22.

- **Frazzini, A., & Pedersen, L. H.** (2014). "Betting against beta". *Journal of Financial Economics*, 111(1), 1-25.

- **Blitz, D., & Van Vliet, P.** (2007). "The volatility effect". *Journal of Portfolio Management*, 34(1), 102-113.

## 🙏 Agradecimentos

- **Kenneth French** pela disponibilização dos fatores Fama-French
- **Stooq.com** pelos dados históricos abrangentes
- **Tiingo** pela API complementar
- **hanshof** pelos dados de constituintes históricos do S&P 500
- Comunidade Julia pelos pacotes excelentes

## 📄 Licença

MIT License - veja o arquivo [LICENSE](LICENSE) para detalhes.

## 📞 Suporte

Para questões ou sugestões, abrir issue no repositório.

---

**Sistema desenvolvido com rigor acadêmico para análise da anomalia de baixa volatilidade**