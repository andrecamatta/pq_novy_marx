"""
Interface abstrata para provedores de dados (SOLID - Open/Closed Principle)
"""
module DataProviders

using DataFrames, Dates

export DataProvider, StooqProvider, TiingoProvider, fetch_prices, provider_name

# Interface abstrata
abstract type DataProvider end

# Implementação Stooq
struct StooqProvider <: DataProvider
    cache_dir::String
    use_bulk::Bool

    StooqProvider(; cache_dir="data/cache/stooq_bulk", use_bulk=true) = new(cache_dir, use_bulk)
end

# Implementação Tiingo
struct TiingoProvider <: DataProvider
    api_key::String
    rate_limit::Int
    cache_dir::String

    function TiingoProvider(; api_key="", rate_limit=50, cache_dir="data/cache/tiingo")
        if isempty(api_key)
            # Tentar carregar do .env
            if isfile(".env")
                for line in readlines(".env")
                    if startswith(line, "TIINGO_API_KEY=")
                        api_key = strip(split(line, "=")[2])
                        break
                    end
                end
            end
        end
        new(api_key, rate_limit, cache_dir)
    end
end

# Interface comum - deve ser implementada por cada provider
function fetch_prices(provider::DataProvider, ticker::String, start_date::Date, end_date::Date)::DataFrame
    error("fetch_prices não implementado para $(typeof(provider))")
end

# Método auxiliar para nome do provider
provider_name(::StooqProvider) = "Stooq"
provider_name(::TiingoProvider) = "Tiingo"

end # module