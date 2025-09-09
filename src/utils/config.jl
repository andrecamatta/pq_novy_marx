# Configuration file for Volatility Anomaly Analysis
# Centralized constants and parameters

module Config

export VOLATILITY_CONFIG, PORTFOLIO_CONFIG, ACADEMIC_CONFIG, UNIVERSE_CONFIG

# Volatility calculation parameters
const VOLATILITY_CONFIG = Dict(
    :window => 252,                    # 1-year rolling window
    :min_data_pct => 0.8,             # Minimum 80% data availability
    :extreme_return_threshold => 3.0,  # Filter returns > log(3) = ~110%
    :annualization_factor => 252       # Trading days per year
)

# Portfolio formation parameters  
const PORTFOLIO_CONFIG = Dict(
    :n_portfolios => 5,               # Quintile portfolios
    :rebalance_freq => "monthly",     # Monthly rebalancing
    :formation_lag => 1,              # 1-month lag (academic standard)
    :min_stocks => 20,                # Minimum stocks per portfolio
    :weighting => "equal"             # Equal-weighted portfolios
)

# Academic filtering standards
const ACADEMIC_CONFIG = Dict(
    :min_price => 5.0,               # Minimum $5 price filter
    :min_market_days => 500,         # Minimum ~2 years of data
    :min_trading_volume => 0,        # No volume filter (price-based universe)
    :survivorship_bias => "point_in_time"  # Use point-in-time data
)

# Universe definitions
const UNIVERSE_CONFIG = Dict(
    :sp500_approximation => [
        # Technology
        "AAPL", "MSFT", "GOOGL", "AMZN", "META", "NVDA", "CRM", "ORCL", "ADBE", "NFLX",
        "CSCO", "INTC", "AMD", "QCOM", "IBM", "HPQ", "AMAT", "LRCX", "AVGO", "TXN",
        
        # Financial
        "JPM", "BAC", "WFC", "C", "GS", "MS", "AXP", "BLK", "SCHW", "USB",
        "PNC", "TFC", "COF", "BK", "STT", "MTB", "RF", "KEY", "CFG", "FITB",
        
        # Healthcare
        "JNJ", "UNH", "PFE", "ABT", "TMO", "MDT", "DHR", "BMY", "AMGN", "GILD",
        "MRK", "LLY", "CVS", "CI", "HUM", "CAH", "MCK", "AET", "ANTM", "WLP",
        
        # Consumer
        "PG", "KO", "PEP", "WMT", "HD", "MCD", "DIS", "NKE", "SBUX", "TGT",
        "LOW", "TJX", "COST", "F", "GM", "TSLA", "CCL", "RCL", "MAR", "HLT",
        
        # Industrial  
        "BA", "GE", "CAT", "MMM", "HON", "UPS", "FDX", "LMT", "RTX", "NOC",
        "DE", "EMR", "ETN", "ITW", "PH", "CMI", "DOV", "FLR", "JCI", "IR",
        
        # Energy & Materials
        "XOM", "CVX", "COP", "SLB", "EOG", "KMI", "OXY", "PSX", "VLO", "MPC",
        "FCX", "NEM", "AA", "X", "CLF", "NUE", "STLD", "CMC", "RS", "WOR",
        
        # Utilities & Telecom
        "T", "VZ", "CMCSA", "TMUS", "S", "CTL", "FTR", "DISH", "SIRI", "WIN",
        "NEE", "DUK", "SO", "EXC", "XEL", "WEC", "ES", "ETR", "FE", "AEP"
    ],
    
    :test_universe => [
        "AAPL", "MSFT", "GOOGL", "AMZN", "TSLA", "META", "JPM", "JNJ", "PG", "KO"
    ]
)

end