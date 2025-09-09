# Data Attribution

## Historical S&P 500 Constituents Data

This project uses historical S&P 500 constituent data from:

**Repository**: [hanshof/sp500_constituents](https://github.com/hanshof/sp500_constituents)  
**License**: MIT License  
**File Used**: `sp_500_historical_components.csv`

### Why This Data is Critical

The historical constituent data is essential for:
- **Eliminating survivorship bias** - includes companies that were delisted, bankrupt, or acquired
- **Point-in-time analysis** - uses actual S&P 500 membership at each date
- **Comprehensive coverage** - tracks 1,128 unique tickers from 1996-2025

### Data Statistics
- **Time Period**: 1996-01-02 to 2025-01-10  
- **Total Records**: 3,482 daily snapshots
- **Unique Tickers**: 1,128 companies
- **Key Events Captured**:
  - Enron bankruptcy (2001)
  - Financial crisis delistings (2008-2009)
  - Tech bubble casualties (2000-2002)
  - COVID-19 market changes (2020)

### License Compliance

The original data is provided under MIT License, which permits:
- Commercial and private use
- Distribution and modification
- With requirement of license and copyright notice

We maintain the same MIT License for this project to ensure compatibility.

## Acknowledgment

Special thanks to the maintainers of [hanshof/sp500_constituents](https://github.com/hanshof/sp500_constituents) for making this critical financial data publicly available. Without this dataset, proper survivorship bias correction would not be possible.

---

If you use this project or its data in your research, please also cite the original data source:
```
@misc{sp500_constituents,
  author = {hanshof},
  title = {S&P 500 Historical Constituents},
  year = {2025},
  publisher = {GitHub},
  url = {https://github.com/hanshof/sp500_constituents}
}
```