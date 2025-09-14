"""
Gerenciador unificado de downloads - consolida todas funções de download
"""
module DownloadManager

using DataFrames, Dates, Statistics
using ..DataProviders

# Incluir módulos necessários
include("../stooq_data.jl")
include("../tiingo_data.jl")
include("../ticker_config.jl")
include("../cache_manager.jl")

using .StooqData
using .TiingoData
using .TickerConfig
using .CacheManager

export download_data, download_batch

"""
    download_data(tickers, start_date, end_date; provider=:auto, use_cache=true, verbose=false)

Função unificada de download que substitui as 3 funções anteriores.
Provider pode ser :auto, :stooq, :tiingo ou um objeto DataProvider
"""
function download_data(
    tickers::Vector{String},
    start_date::Date,
    end_date::Date;
    provider::Union{Symbol, DataProvider} = :auto,
    use_cache::Bool = true,
    verbose::Bool = false,
    use_tiingo::Bool = true
)::Dict{String, DataFrame}

    price_data = Dict{String, DataFrame}()
    failed_tickers = String[]

    # Determinar provider
    if isa(provider, Symbol)
        if provider == :auto
            # Tentar Stooq primeiro, Tiingo como fallback
            primary_provider = StooqProvider()
            fallback_provider = use_tiingo ? TiingoProvider() : nothing
        elseif provider == :stooq
            primary_provider = StooqProvider()
            fallback_provider = nothing
        elseif provider == :tiingo
            primary_provider = TiingoProvider()
            fallback_provider = nothing
        else
            error("Provider desconhecido: $provider")
        end
    else
        primary_provider = provider
        fallback_provider = nothing
    end

    # Download batch para melhor performance
    verbose && println("📊 Download unificado para $(length(tickers)) tickers")
    verbose && println("   Provider: $(provider_name(primary_provider))")

    # Tentar cache primeiro se habilitado
    if use_cache
        for ticker in tickers
            cache_key = CacheManager.get_cache_key("prices", ticker, start_date, end_date)
            cached_data = CacheManager.load_cache("prices", cache_key, max_age_days=7)

            if !isnothing(cached_data)
                price_data[ticker] = cached_data
                verbose && println("   ✅ $ticker (cache)")
            end
        end

        # Remover tickers já em cache
        tickers = filter(t -> !haskey(price_data, t), tickers)
    end

    # Download dos tickers restantes
    if !isempty(tickers)
        # Tentar download com provider primário
        for ticker in tickers
            try
                data = fetch_ticker_data(primary_provider, ticker, start_date, end_date, verbose)
                if !isempty(data)
                    price_data[ticker] = data

                    # Salvar em cache
                    if use_cache
                        cache_key = CacheManager.get_cache_key("prices", ticker, start_date, end_date)
                        CacheManager.save_cache("prices", cache_key, data)
                    end

                    verbose && println("   ✅ $ticker")
                else
                    push!(failed_tickers, ticker)
                end
            catch e
                push!(failed_tickers, ticker)
                verbose && println("   ⚠️ $ticker: $e")
            end
        end

        # Tentar fallback se disponível
        if !isnothing(fallback_provider) && !isempty(failed_tickers)
            verbose && println("   🔄 Tentando fallback para $(length(failed_tickers)) tickers")

            for ticker in failed_tickers
                try
                    data = fetch_ticker_data(fallback_provider, ticker, start_date, end_date, verbose)
                    if !isempty(data)
                        price_data[ticker] = data

                        # Salvar em cache
                        if use_cache
                            cache_key = CacheManager.get_cache_key("prices", ticker, start_date, end_date)
                            CacheManager.save_cache("prices", cache_key, data)
                        end

                        verbose && println("   ✅ $ticker (fallback)")
                    end
                catch e
                    verbose && println("   ❌ $ticker falhou em ambos providers")
                end
            end
        end
    end

    verbose && println("📊 Download completo: $(length(price_data))/$(length(tickers)) tickers")

    return price_data
end

"""
    fetch_ticker_data(provider, ticker, start_date, end_date, verbose)

Busca dados de um ticker usando o provider especificado
"""
function fetch_ticker_data(provider::StooqProvider, ticker::String, start_date::Date, end_date::Date, verbose::Bool)::DataFrame
    # Usar lógica existente do StooqData
    clean_ticker = StooqData.clean_stooq_ticker(ticker)

    # Tentar bulk primeiro se disponível
    if provider.use_bulk && isfile(joinpath(provider.cache_dir, "d_us_txt.zip"))
        data = StooqData.load_from_stooq_index_optimized(
            [clean_ticker],
            joinpath(provider.cache_dir, "d_us_txt.zip"),
            verbose=false
        )

        if haskey(data, clean_ticker)
            df = data[clean_ticker]
            # Filtrar por datas
            return filter(row -> start_date <= row.Date <= end_date, df)
        end
    end

    # Fallback para download direto (não implementado aqui, seria via HTTP)
    return DataFrame()
end

function fetch_ticker_data(provider::TiingoProvider, ticker::String, start_date::Date, end_date::Date, verbose::Bool)::DataFrame
    # Usar lógica existente do TiingoData
    return TiingoData.get_historical_prices(
        ticker,
        start_date=start_date,
        end_date=end_date,
        api_key=provider.api_key,
        verbose=verbose
    )
end

"""
    download_batch(tickers; chunk_size=50, kwargs...)

Download em lotes para melhor performance
"""
function download_batch(
    tickers::Vector{String};
    chunk_size::Int = 50,
    kwargs...
)::Dict{String, DataFrame}

    all_data = Dict{String, DataFrame}()
    chunks = Iterators.partition(tickers, chunk_size)

    for (i, chunk) in enumerate(chunks)
        println("📦 Processando lote $i/$(length(chunks))")
        chunk_data = download_data(collect(chunk); kwargs...)
        merge!(all_data, chunk_data)

        # Pequena pausa entre lotes para não sobrecarregar
        sleep(0.5)
    end

    return all_data
end

end # module