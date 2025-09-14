"""
Gerenciamento de constituintes do S&P 500
"""
module SP500Constituents

using DataFrames, Dates, CSV

export load_sp500_constituents, load_historical_sp500_constituents, get_universe_for_period

"""
    load_sp500_constituents(file_path)

Carrega constituintes atuais do S&P 500
"""
function load_sp500_constituents(
    file_path::String = "data/sp_500_historical_components.csv"
)::DataFrame

    if !isfile(file_path)
        error("Arquivo de constituintes não encontrado: $file_path")
    end

    try
        df = CSV.read(file_path, DataFrame)

        # Verificar colunas obrigatórias
        required_cols = ["date", "tickers"]
        missing_cols = setdiff(required_cols, names(df))

        if !isempty(missing_cols)
            error("Colunas faltando no arquivo: $(join(missing_cols, ", "))")
        end

        # Converter coluna de data se necessário
        if eltype(df.date) == String
            df.date = Date.(df.date, "yyyy-mm-dd")
        end

        # Ordenar por data
        sort!(df, :date)

        return df

    catch e
        error("Erro ao carregar arquivo de constituintes: $e")
    end
end

"""
    load_historical_sp500_constituents(file_path)

Alias para load_sp500_constituents (compatibilidade)
"""
function load_historical_sp500_constituents(
    file_path::String = "data/sp_500_historical_components.csv"
)::DataFrame
    return load_sp500_constituents(file_path)
end

"""
    get_universe_for_period(start_date, end_date; file_path, verbose=false)

Obtém universo de tickers para um período específico
"""
function get_universe_for_period(
    start_date::Date,
    end_date::Date;
    file_path::String = "data/sp_500_historical_components.csv",
    verbose::Bool = false
)::Vector{String}

    constituents_df = load_sp500_constituents(file_path)

    # Filtrar dados no período
    period_data = filter(row -> start_date <= row.date <= end_date, constituents_df)

    if isempty(period_data)
        if verbose
            println("⚠️ Nenhum dado de constituintes encontrado para o período")
        end
        return String[]
    end

    # Coletar todos os tickers únicos do período
    all_tickers = Set{String}()

    for row in eachrow(period_data)
        tickers_str = row.tickers
        tickers = [strip(t) for t in split(tickers_str, ",")]
        union!(all_tickers, tickers)
    end

    universe = sort(collect(all_tickers))

    if verbose
        println("📊 Universo do período $(start_date) a $(end_date):")
        println("   Total de tickers: $(length(universe))")
        println("   Registros analisados: $(nrow(period_data))")
    end

    return universe
end

"""
    get_constituents_for_date(constituents_df, date)

Obtém constituintes para uma data específica
"""
function get_constituents_for_date(
    constituents_df::DataFrame,
    date::Date
)::Vector{String}

    # Encontrar a data mais próxima (anterior ou igual)
    valid_dates = filter(d -> d <= date, constituents_df.date)

    if isempty(valid_dates)
        return String[]
    end

    closest_date = maximum(valid_dates)
    row = filter(r -> r.date == closest_date, constituents_df)[1, :]

    # Extrair tickers
    tickers_str = row.tickers
    tickers = [strip(t) for t in split(tickers_str, ",")]

    return tickers
end

"""
    validate_constituents_file(file_path)

Valida arquivo de constituintes
"""
function validate_constituents_file(file_path::String)::Dict{String, Any}
    validation = Dict{String, Any}(
        "is_valid" => false,
        "issues" => String[],
        "stats" => Dict()
    )

    if !isfile(file_path)
        push!(validation["issues"], "Arquivo não encontrado")
        return validation
    end

    try
        df = CSV.read(file_path, DataFrame)

        # Verificar colunas
        required_cols = ["date", "tickers"]
        missing_cols = setdiff(required_cols, names(df))

        if !isempty(missing_cols)
            push!(validation["issues"], "Colunas faltando: $(join(missing_cols, ", "))")
        end

        # Verificar datas
        if "date" in names(df)
            try
                if eltype(df.date) == String
                    dates = Date.(df.date, "yyyy-mm-dd")
                else
                    dates = df.date
                end

                validation["stats"]["date_range"] = (minimum(dates), maximum(dates))
                validation["stats"]["total_records"] = nrow(df)

            catch e
                push!(validation["issues"], "Erro ao parsear datas: $e")
            end
        end

        # Verificar formato dos tickers
        if "tickers" in names(df) && nrow(df) > 0
            sample_tickers = first(df.tickers)
            ticker_count = length(split(sample_tickers, ","))
            validation["stats"]["sample_ticker_count"] = ticker_count

            if ticker_count < 400 || ticker_count > 600
                push!(validation["issues"], "Contagem suspeita de tickers: $ticker_count")
            end
        end

        validation["is_valid"] = isempty(validation["issues"])

    catch e
        push!(validation["issues"], "Erro ao ler arquivo: $e")
    end

    return validation
end

"""
    create_constituents_summary(constituents_df)

Cria resumo dos dados de constituintes
"""
function create_constituents_summary(constituents_df::DataFrame)::DataFrame
    summary_df = DataFrame(
        Metric = String[],
        Value = Any[]
    )

    # Período coberto
    date_range = (minimum(constituents_df.date), maximum(constituents_df.date))
    push!(summary_df, ("Period", "$(date_range[1]) to $(date_range[2])"))

    # Total de registros
    push!(summary_df, ("Total Records", nrow(constituents_df)))

    # Análise de tickers únicos
    all_tickers = Set{String}()
    for row in eachrow(constituents_df)
        tickers = [strip(t) for t in split(row.tickers, ",")]
        union!(all_tickers, tickers)
    end

    push!(summary_df, ("Unique Tickers", length(all_tickers)))

    # Tickers mais recentes
    latest_row = constituents_df[argmax(constituents_df.date), :]
    latest_tickers = split(latest_row.tickers, ",")
    push!(summary_df, ("Current SP500 Count", length(latest_tickers)))

    return summary_df
end

end # module