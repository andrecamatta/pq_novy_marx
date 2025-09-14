"""
Cache Manager unificado para todas as operações de cache do projeto
"""
module CacheManager

using DataFrames, Dates, CSV, JSON

export cache_exists, save_cache, load_cache, clear_cache, get_cache_key

# Configuração central de cache
const CACHE_CONFIG = Dict(
    "prices" => "data/cache/prices",
    "factors" => "data/cache/factors",
    "tiingo" => "data/cache/tiingo",
    "stooq" => "data/cache/stooq_bulk",
    "results" => "data/cache/results"
)

"""
    get_cache_key(type::String, identifier::String, params...)::String

Gera uma chave única para cache baseada no tipo e parâmetros
"""
function get_cache_key(type::String, identifier::String, params...)::String
    param_str = join([string(p) for p in params], "_")
    return "$(type)_$(identifier)_$(param_str)"
end

"""
    cache_exists(type::String, key::String)::Bool

Verifica se existe cache para uma determinada chave
"""
function cache_exists(type::String, key::String)::Bool
    cache_dir = get(CACHE_CONFIG, type, "data/cache/$(type)")
    cache_file = joinpath(cache_dir, "$(key).csv")
    return isfile(cache_file)
end

"""
    save_cache(type::String, key::String, data::DataFrame)::Nothing

Salva dados em cache
"""
function save_cache(type::String, key::String, data::DataFrame)::Nothing
    cache_dir = get(CACHE_CONFIG, type, "data/cache/$(type)")
    mkpath(cache_dir)

    cache_file = joinpath(cache_dir, "$(key).csv")
    CSV.write(cache_file, data)

    # Salvar metadata
    metadata_file = joinpath(cache_dir, "$(key)_metadata.json")
    metadata = Dict(
        "created_at" => string(now()),
        "rows" => nrow(data),
        "cols" => ncol(data)
    )
    open(metadata_file, "w") do io
        JSON.print(io, metadata)
    end
end

"""
    load_cache(type::String, key::String; max_age_days::Int=30)::Union{DataFrame, Nothing}

Carrega dados do cache, retornando nothing se não existir ou estiver expirado
"""
function load_cache(type::String, key::String; max_age_days::Int=30)::Union{DataFrame, Nothing}
    cache_dir = get(CACHE_CONFIG, type, "data/cache/$(type)")
    cache_file = joinpath(cache_dir, "$(key).csv")
    metadata_file = joinpath(cache_dir, "$(key)_metadata.json")

    if !isfile(cache_file)
        return nothing
    end

    # Verificar idade do cache
    if isfile(metadata_file)
        metadata = JSON.parsefile(metadata_file)
        created_at = DateTime(metadata["created_at"])
        age_days = (now() - created_at).value / (24 * 60 * 60 * 1000)

        if age_days > max_age_days
            return nothing  # Cache expirado
        end
    end

    try
        return CSV.read(cache_file, DataFrame)
    catch e
        @warn "Erro ao ler cache: $e"
        return nothing
    end
end

"""
    clear_cache(type::String="all")::Nothing

Limpa o cache de um tipo específico ou todo o cache
"""
function clear_cache(type::String="all")::Nothing
    if type == "all"
        for (cache_type, cache_dir) in CACHE_CONFIG
            if isdir(cache_dir)
                for file in readdir(cache_dir)
                    rm(joinpath(cache_dir, file), force=true)
                end
            end
        end
        println("✅ Todo cache limpo")
    else
        cache_dir = get(CACHE_CONFIG, type, "data/cache/$(type)")
        if isdir(cache_dir)
            for file in readdir(cache_dir)
                rm(joinpath(cache_dir, file), force=true)
            end
        end
        println("✅ Cache '$type' limpo")
    end
end

"""
    get_cache_status()::Dict

Retorna estatísticas sobre o uso de cache
"""
function get_cache_status()::Dict
    status = Dict()

    for (cache_type, cache_dir) in CACHE_CONFIG
        if isdir(cache_dir)
            files = readdir(cache_dir)
            csv_files = filter(f -> endswith(f, ".csv"), files)

            total_size = 0
            for file in files
                total_size += filesize(joinpath(cache_dir, file))
            end

            status[cache_type] = Dict(
                "files" => length(csv_files),
                "size_mb" => round(total_size / 1_048_576, digits=2)
            )
        else
            status[cache_type] = Dict("files" => 0, "size_mb" => 0.0)
        end
    end

    return status
end

end # module