# 🎯 Testing the Low Volatility Anomaly with Survivorship Bias Correction

## Overview

This project tests whether the **low volatility anomaly** in stock returns has independent alpha after controlling for known factors, specifically examining **Novy-Marx's critique** that many financial anomalies disappear under rigorous methodology.

### Key Innovation: Complete Survivorship Bias Elimination

- **1,128 unique tickers** from historical S&P 500 constituents (1996-2025)
- **Point-in-time universe** using real historical membership data
- **Proper methodology** following academic standards (Baker, Bradley & Wurgler 2011)

## 🎓 Academic Context

**Novy-Marx Critique**: Many documented financial anomalies are statistical artifacts that disappear when:
1. Survivorship bias is properly eliminated
2. Rigorous statistical testing is applied  
3. Transaction costs and implementation constraints are considered

**Low Volatility Anomaly**: The empirical finding that low-risk stocks tend to outperform high-risk stocks on a risk-adjusted basis.

## 📊 Data & Methodology

### Data Sources
- **Historical S&P 500 constituents**: `sp_500_historical_components.csv` (29 years of daily data)
- **Price data**: YFinance.jl for actual historical prices
- **Factor models**: CAPM and Fama-French models for benchmarking

### Methodology
1. **Point-in-time universe construction** from historical S&P 500 membership
2. **252-day rolling volatility** calculation with academic filters
3. **Monthly portfolio formation** (quintiles) with 1-month lag
4. **Long-short portfolio returns** (low vol - high vol)
5. **Statistical testing** via t-tests and GRS tests

## 🏗️ Project Structure

```
pq_novy_marx/
├── sp_500_historical_components.csv    # Historical S&P 500 data (1996-2025)
├── src/
│   ├── VolatilityAnomalyAnalysis.jl    # Main analysis module
│   └── utils/
│       ├── config.jl                   # Analysis parameters
│       ├── portfolio_analysis.jl       # Core portfolio functions
│       ├── historical_constituents.jl  # Bias correction utilities
│       ├── real_sp500_data.jl         # Historical universe builder
│       └── yfinance_integration.jl     # Real data download
├── test_*.jl                          # Various analysis scripts
└── *.csv                              # Generated results
```

## 🚀 Quick Start

### Prerequisites
```julia
using Pkg
Pkg.add(["DataFrames", "Dates", "Statistics", "Distributions", "YFinance", "CSV"])
```

### Basic Usage
```julia
include("src/VolatilityAnomalyAnalysis.jl")
using .VolatilityAnomalyAnalysis

# Run bias-corrected analysis
results = PortfolioAnalysis.analyze_volatility_anomaly_with_bias_correction(
    Date(2000, 1, 1),
    Date(2024, 12, 31),
    "Low Volatility Test"
)

# View results
println("Annual return (Low-High Vol): ", results.long_short_returns)
```

## 📈 Key Findings (Work in Progress)

### Survivorship Bias Impact
- **Before correction**: ~500 current S&P 500 companies
- **After correction**: 1,128 unique historical constituents  
- **Improvement**: 5.8x more comprehensive universe

### Timeline Validation
- ✅ **2000**: Includes Enron (ENRNQ), excludes Google/Meta/Tesla
- ✅ **2008**: Includes Google, excludes Enron (post-bankruptcy)  
- ✅ **2020**: Modern tech stack present, historical bankruptcies absent
- ✅ **2024**: Current S&P 500 configuration

## 🧪 Testing Scripts

- `test_real_universe.jl` - Validates 1,128-ticker universe integration
- `test_bias_correction.jl` - Tests survivorship bias correction
- `real_yfinance_test.jl` - Tests actual data download
- `quick_bias_test.jl` - Fast analysis with representative sample

## 📚 Expected Results

Based on academic literature post-2000:
- **High volatility should outperform** low volatility  
- **Effect should be statistically significant** under proper testing
- **Confirms Novy-Marx critique** if anomaly disappears under bias correction

## ⚠️ Current Status

**🚧 Work in Progress**

- ✅ Survivorship bias correction implemented and validated
- ✅ Historical universe (1,128 tickers) integrated successfully  
- ✅ Point-in-time methodology working correctly
- 🔄 YFinance integration for real data download (in progress)
- 🔄 Full analysis execution with complete dataset
- 📋 Final statistical results and interpretation

## 🤝 Contributing

This is an active research project. Contributions welcome for:
- Code optimization and bug fixes
- Additional bias correction methodologies  
- Alternative data sources integration
- Statistical testing improvements
- Documentation and examples

## 📖 References

- Baker, M., Bradley, B., & Wurgler, J. (2011). Benchmarks as limits to arbitrage
- Novy-Marx, R. (2013). The other side of value: The gross profitability premium  
- Ang, A., Hodrick, R. J., Xing, Y., & Zhang, X. (2006). The cross‐section of volatility and expected returns

## 📄 License

MIT License - see LICENSE file for details.

## 📧 Contact

**André Camatta** - [@andrecamatta](https://github.com/andrecamatta)

---

*This project aims to contribute to the academic understanding of financial anomalies and the importance of rigorous methodology in empirical finance research.*

**Testing the Novy-Marx Critique with Academic Standards**

A clean, modular implementation for testing whether the low volatility anomaly persists under rigorous academic methodology.

## 🎯 Project Overview

This project implements a comprehensive test of the **low volatility anomaly** - the empirical observation that low-risk stocks tend to outperform high-risk stocks, contradicting traditional finance theory.

We specifically test **Novy-Marx's critique** that many financial anomalies disappear when subjected to proper academic methodology, including:
- Point-in-time analysis (survivorship bias correction)
- Academic filtering standards  
- Proper statistical testing
- Multiple time periods
- Robust error handling

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

## 🛠️ Requirements

- **Julia** 1.6+ (tested on 1.9+)
- **Internet connection** (for YFinance API)
- **Packages** (auto-installed):
  - YFinance.jl
  - DataFrames.jl  
  - Dates.jl
  - CSV.jl
  - JSON.jl
  - StatsBase.jl
  - Distributions.jl

## 🔧 Troubleshooting

### Common Issues

**YFinance API Timeouts**
```bash
# Check internet connection
# Some corporate networks block Yahoo Finance
# Try smaller universe: julia main_analysis.jl test
```

**Package Installation Errors**
```julia
# Manual package installation
using Pkg
Pkg.add(["YFinance", "DataFrames", "CSV", "JSON", "StatsBase"])
```

**Insufficient Data**
```
# Reduce minimum data requirements in config.jl
# Or use smaller date ranges
```

## 📚 Academic References

- **Baker, Bradley & Wurgler (2011)** - "Benchmarks as Limits to Arbitrage"
- **Novy-Marx (2012)** - "Is momentum really momentum?"  
- **Frazzini & Pedersen (2014)** - "Betting Against Beta"

## 🤝 Contributing

1. **Issues**: Report bugs or suggest features
2. **Pull Requests**: Follow existing code style
3. **Testing**: Add unit tests for new functionality
4. **Documentation**: Update docstrings and README

## 📄 License

MIT License - see LICENSE file for details.

## 📞 Support

For questions or issues:
- Check `julia main_analysis.jl help`
- Review troubleshooting section
- Open GitHub issue with:
  - Julia version
  - Error messages  
  - System details

---

**Disclaimer**: This tool is for academic research purposes. Results should be validated independently before making investment decisions.