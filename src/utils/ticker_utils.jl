"""
Utilitários para manipulação de tickers
"""
module TickerUtils

using DataFrames, Dates

export clean_ticker_for_stooq, create_validity_metadata, get_ticker_validity_period

"""
    clean_ticker_for_stooq(ticker)

Limpa ticker para compatibilidade com Stooq
"""
function clean_ticker_for_stooq(ticker::String)::String
    # Remove sufixos comuns
    cleaned = replace(ticker, r"\.(US|NYSE|NASDAQ)$" => "")

    # Converte pontos em hífens (para classes de ações)
    cleaned = replace(cleaned, "." => "-")

    return uppercase(cleaned)
end

"""
    get_ticker_validity_period(price_data, ticker)

Obtém período de validade dos dados de um ticker
"""
function get_ticker_validity_period(
    price_data::Dict{String, DataFrame},
    ticker::String
)::Union{Tuple{Date, Date}, Nothing}

    if !haskey(price_data, ticker) || isempty(price_data[ticker])
        return nothing
    end

    df = price_data[ticker]
    return (minimum(df.Date), maximum(df.Date))
end

"""
    create_validity_metadata(price_data)

Cria metadata sobre validade dos dados
"""
function create_validity_metadata(price_data::Dict{String, DataFrame})::DataFrame
    metadata = DataFrame(
        Ticker = String[],
        StartDate = Date[],
        EndDate = Date[],
        TotalDays = Int[],
        HasRecent = Bool[]
    )

    recent_threshold = today() - Day(30)

    for (ticker, df) in price_data
        if !isempty(df)
            start_date = minimum(df.Date)
            end_date = maximum(df.Date)
            total_days = nrow(df)
            has_recent = end_date >= recent_threshold

            push!(metadata, (ticker, start_date, end_date, total_days, has_recent))
        end
    end

    # Ordenar por ticker
    sort!(metadata, :Ticker)

    return metadata
end

"""
    validate_ticker_data(df, ticker)

Valida qualidade dos dados de um ticker
"""
function validate_ticker_data(df::DataFrame, ticker::String)::Dict{String, Any}
    validation = Dict{String, Any}(
        "ticker" => ticker,
        "is_valid" => false,
        "issues" => String[],
        "stats" => Dict()
    )

    if isempty(df)
        push!(validation["issues"], "DataFrame vazio")
        return validation
    end

    # Verificar colunas obrigatórias
    required_cols = ["Date", "Close", "Open", "High", "Low"]
    missing_cols = setdiff(required_cols, names(df))

    if !isempty(missing_cols)
        push!(validation["issues"], "Colunas faltando: $(join(missing_cols, ", "))")
        return validation
    end

    # Verificar preços válidos
    invalid_prices = sum(df.Close .<= 0)
    if invalid_prices > 0
        push!(validation["issues"], "$invalid_prices preços inválidos (≤ 0)")
    end

    # Verificar datas duplicadas
    if length(unique(df.Date)) != nrow(df)
        push!(validation["issues"], "Datas duplicadas encontradas")
    end

    # Verificar ordem temporal
    if !issorted(df.Date)
        push!(validation["issues"], "Datas não estão ordenadas")
    end

    # Estatísticas
    validation["stats"] = Dict(
        "rows" => nrow(df),
        "date_range" => (minimum(df.Date), maximum(df.Date)),
        "avg_price" => mean(df.Close),
        "price_range" => (minimum(df.Close), maximum(df.Close))
    )

    # Determinar se é válido
    validation["is_valid"] = isempty(validation["issues"])

    return validation
end

"""
    clean_ticker_symbol(symbol)

Limpeza geral de símbolos de ticker
"""
function clean_ticker_symbol(symbol::String)::String
    # Remove espaços
    cleaned = strip(symbol)

    # Remove caracteres especiais extras
    cleaned = replace(cleaned, r"[^\w\.-]" => "")

    # Converte para maiúsculas
    cleaned = uppercase(cleaned)

    return cleaned
end

"""
    normalize_ticker_format(ticker, target_format=:stooq)

Normaliza ticker para diferentes formatos
"""
function normalize_ticker_format(ticker::String, target_format::Symbol = :stooq)::String
    cleaned = clean_ticker_symbol(ticker)

    if target_format == :stooq
        return clean_ticker_for_stooq(cleaned)
    elseif target_format == :tiingo
        # Tiingo geralmente aceita formato padrão
        return cleaned
    elseif target_format == :yahoo
        # Yahoo usa pontos para classes
        return replace(cleaned, "-" => ".")
    else
        return cleaned
    end
end

end # module