"""
Sistema de Configuração Centralizada para Resolução de Tickers

Substitui mapeamentos hardcoded por configuração YAML flexível e auditável.
Implementa caching inteligente e API unificada para resolução de símbolos.
"""

module TickerConfig

using YAML
using Dates

export load_ticker_config, resolve_ticker_with_config, TickerResolution, fast_ticker_lookup, resolve_ticker_with_temporal_info

# Cache global UNIFICADO da configuração para performance máxima
# Usado por todos os módulos para evitar recarregamentos excessivos
const GLOBAL_CONFIG_CACHE = Ref{Union{Dict, Nothing}}(nothing)
const GLOBAL_CONFIG_TIMESTAMP = Ref{Float64}(0.0)
const GLOBAL_CONFIG_LOCK = ReentrantLock()

# Cache de lookups rápidos para evitar processamento repetitivo
const FAST_LOOKUP_CACHE = Dict{String, String}()

# Estrutura de resultado da resolução
struct TickerResolution
    original_ticker::String
    resolved_ticker::String
    method::String
    confidence::String
    metadata::Dict{String, Any}
    timestamp::DateTime
end

"""
    load_ticker_config(;force_reload::Bool = false)::Dict

Carrega configuração YAML com caching inteligente.
Recarrega automaticamente se arquivo foi modificado.
"""
function load_ticker_config(;force_reload::Bool = false)::Dict
    # Usar cache unificado com thread safety
    lock(GLOBAL_CONFIG_LOCK) do
        config_path = joinpath(dirname(@__DIR__), "config", "ticker_config.yaml")
        
        if !isfile(config_path)
            error("Arquivo de configuração não encontrado: $config_path")
        end
        
        # Verificar se precisa recarregar
        file_mtime = mtime(config_path)
        
        if GLOBAL_CONFIG_CACHE[] !== nothing && !force_reload && file_mtime <= GLOBAL_CONFIG_TIMESTAMP[]
            return GLOBAL_CONFIG_CACHE[]
        end
        
        try
            # Log apenas na primeira carga ou reload forçado
            if GLOBAL_CONFIG_CACHE[] === nothing || force_reload
                @info "Carregando configuração de tickers: $config_path"
            end
            
            config = YAML.load_file(config_path)
            GLOBAL_CONFIG_CACHE[] = config
            GLOBAL_CONFIG_TIMESTAMP[] = file_mtime
            # YAML foi (re)carregado: invalidar cache de lookups rápidos
            empty!(FAST_LOOKUP_CACHE)
            return config
        catch e
            error("Erro ao carregar configuração YAML: $e")
        end
    end
end

"""
    resolve_ticker_with_config(ticker::String, config::Dict)::TickerResolution

Resolve ticker usando estratégias configuradas em YAML.
Retorna estrutura completa com metadados de auditoria.
"""
function resolve_ticker_with_config(ticker::String, config::Dict)::TickerResolution
    original_ticker = uppercase(strip(ticker))
    
    # Tentar cada estratégia na ordem configurada (exceto direct_lookup)
    for strategy in get(config, "resolution_strategies", [])
        if strategy["name"] == "direct_lookup"
            continue  # Pular direct_lookup, será usado como fallback
        end
        
        result = apply_strategy(original_ticker, strategy["name"], config)
        if result !== nothing
            return TickerResolution(
                original_ticker,
                result["ticker"], 
                result["method"],
                result["confidence"],
                result["metadata"],
                now()
            )
        end
    end
    
    # Fallback: retornar original se nada funcionou
    return TickerResolution(
        original_ticker,
        original_ticker,
        "no_resolution",
        "low", 
        Dict("note" => "Nenhuma estratégia teve sucesso"),
        now()
    )
end

"""
    apply_strategy(ticker::String, strategy_name::String, config::Dict)

Aplica estratégia específica de resolução.
"""
function apply_strategy(ticker::String, strategy_name::String, config::Dict)
    if strategy_name == "direct_lookup"
        return apply_direct_lookup(ticker, config)
    elseif strategy_name == "apply_renames"
        return apply_renames(ticker, config)
    elseif strategy_name == "normalize_symbol"
        return apply_normalization(ticker, config)
    elseif strategy_name == "check_preferences"
        return apply_preferences(ticker, config)
    elseif strategy_name == "corporate_actions"
        return apply_corporate_actions(ticker, config)
    elseif strategy_name == "alternative_formats"
        return apply_alternative_formats(ticker, config)
    elseif strategy_name == "tiingo_search"
        return apply_tiingo_search(ticker, config)
    else
        @warn "Estratégia desconhecida: $strategy_name"
        return nothing
    end
end

"""
    apply_direct_lookup(ticker::String, config::Dict)

Tenta usar ticker original sem modificação.
"""
function apply_direct_lookup(ticker::String, ::Dict)
    # Por enquanto assumimos que o ticker original pode funcionar
    # Em implementação completa, testaria conectividade com fonte
    return Dict(
        "ticker" => ticker,
        "method" => "direct_lookup",
        "confidence" => "medium",
        "metadata" => Dict("original" => ticker)
    )
end

"""
    apply_renames(ticker::String, config::Dict)

Verifica mapeamentos de renomeação corporativa.
"""
function apply_renames(ticker::String, config::Dict)
    renames = get(config, "corporate_renames", Dict())
    
    if haskey(renames, ticker)
        new_ticker = renames[ticker]
        return Dict(
            "ticker" => new_ticker,
            "method" => "corporate_rename",
            "confidence" => "high",
            "metadata" => Dict(
                "original" => ticker,
                "reason" => "corporate_rename",
                "renamed_to" => new_ticker,
                "type" => "rename"
            )
        )
    end
    
    return nothing
end

"""
    apply_normalization(ticker::String, config::Dict)

Aplica regras de normalização de símbolos.
"""
function apply_normalization(ticker::String, config::Dict)
    rules = get(config, "normalization_rules", Dict())
    
    # Verificar correções específicas primeiro
    corrections = get(rules, "symbol_corrections", Dict())
    if haskey(corrections, ticker)
        corrected = corrections[ticker]
        # Preferir sempre o formato com hífen para classes de ações.
        # Ignorar mapeamentos reversos (ex.: "BRK-B" -> "BRK.B") que afastam do formato Stooq.
        if contains(ticker, "-") && contains(corrected, ".")
            # Ignora correção reversa; segue para outras regras (ex.: dot_to_hyphen)
        else
            return Dict(
                "ticker" => corrected,
                "method" => "symbol_correction",
                "confidence" => "high",
                "metadata" => Dict(
                    "original" => ticker,
                    "corrected_to" => corrected
                )
            )
        end
    end
    
    # Aplicar regra dot_to_hyphen se habilitada
    dot_to_hyphen = get(rules, "dot_to_hyphen", Dict())
    if get(dot_to_hyphen, "enabled", false) && contains(ticker, ".")
        pattern = get(dot_to_hyphen, "pattern", "\\.")
        replacement = get(dot_to_hyphen, "replacement", "-")
        normalized = replace(ticker, Regex(pattern) => replacement)
        
        if normalized != ticker
            return Dict(
                "ticker" => normalized,
                "method" => "normalization_dot_to_hyphen", 
                "confidence" => "high",
                "metadata" => Dict(
                    "original" => ticker,
                    "normalized_to" => normalized,
                    "rule" => "dot_to_hyphen"
                )
            )
        end
    end
    
    return nothing
end

"""
    apply_preferences(ticker::String, config::Dict)

Aplica preferências de classe de ações.
"""
function apply_preferences(ticker::String, config::Dict)
    preferences = get(config, "share_class_preferences", Dict())
    
    if haskey(preferences, ticker)
        preferred = preferences[ticker]
        if preferred != ticker
            return Dict(
                "ticker" => preferred,
                "method" => "share_class_preference",
                "confidence" => "medium",
                "metadata" => Dict(
                    "original" => ticker,
                    "preferred_class" => preferred
                )
            )
        end
    end
    
    return nothing
end

"""
    apply_corporate_actions(ticker::String, config::Dict)

Verifica ações corporativas (aquisições, fusões, etc.).
IMPORTANTE: Aquisições resultam em forced sales - série para na data da aquisição.
"""
function apply_corporate_actions(ticker::String, config::Dict)
    actions = get(config, "corporate_actions", Dict())
    policy = get(config, "policy", Dict())
    forced_mode = get(policy, "forced_sale_mode", "default")

    # Verificar aquisições - ESTAS SÃO FORCED SALES
    acquisitions = get(actions, "acquisitions", Dict())
    if haskey(acquisitions, ticker)
        action_info = acquisitions[ticker]
        action_type = get(action_info, "type", "acquisition")
        action_date = get(action_info, "date", "")

        # Para merger_equals, continuar série com sucessor
        if action_type == "merger_equals"
            # Política: em modo strict, mergers também são forced sale
            if forced_mode == "strict"
                return Dict(
                    "ticker" => ticker,
                    "method" => "forced_sale_merger",
                    "confidence" => "high",
                    "metadata" => Dict(
                        "original" => ticker,
                        "successor" => get(action_info, "acquirer", ""),
                        "date" => action_date,
                        "type" => "merger_equals",
                        "forced_sale" => true,
                        "cutoff_date" => action_date,
                        "note" => get(action_info, "note", "")
                    )
                )
            else
                acquirer = get(action_info, "acquirer", "")
                if !isempty(acquirer)
                    return Dict(
                        "ticker" => acquirer,
                        "method" => "merger_equals",
                        "confidence" => "high",
                        "metadata" => Dict(
                            "original" => ticker,
                            "successor" => acquirer,
                            "date" => action_date,
                            "type" => "merger_equals",
                            "forced_sale" => false,
                            "note" => get(action_info, "note", "")
                        )
                    )
                end
            end
        else
            # Para aquisições normais: FORCED SALE
            tiingo_coverage = get(action_info, "tiingo_coverage", true)

            return Dict(
                "ticker" => ticker,  # Manter ticker original
                "method" => "forced_sale_acquisition",
                "confidence" => "high",
                "metadata" => Dict(
                    "original" => ticker,
                    "acquirer" => get(action_info, "acquirer", ""),
                    "date" => action_date,
                    "type" => action_type,
                    "forced_sale" => true,
                    "cutoff_date" => action_date,
                    "tiingo_coverage" => tiingo_coverage,
                    "note" => get(action_info, "note", "")
                )
            )
        end
    end

    # Verificar falências - ESTAS SÃO FORCED SALES
    bankruptcies = get(actions, "bankruptcies", Dict())
    if haskey(bankruptcies, ticker)
        bankruptcy_info = bankruptcies[ticker]
        bankruptcy_date = get(bankruptcy_info, "date", "")

        # Verificar se tem ticker OTC disponível
        otc_ticker = get(bankruptcy_info, "otc_ticker", nothing)
        tiingo_coverage = get(bankruptcy_info, "tiingo_coverage", true)

        # Se tem ticker OTC e cobertura Tiingo, tentar OTC
        if otc_ticker !== nothing && tiingo_coverage
            return Dict(
                "ticker" => otc_ticker,
                "method" => "bankruptcy_otc_ticker",
                "confidence" => "high",
                "metadata" => Dict(
                    "original" => ticker,
                    "otc_ticker" => otc_ticker,
                    "date" => bankruptcy_date,
                    "status" => get(bankruptcy_info, "status", ""),
                    "forced_sale" => true,
                    "cutoff_date" => bankruptcy_date,
                    "note" => get(bankruptcy_info, "note", "")
                )
            )
        else
            # Forced sale normal (sem dados após falência)
            return Dict(
                "ticker" => ticker,  # Manter ticker original
                "method" => "forced_sale_bankruptcy",
                "confidence" => "high",
                "metadata" => Dict(
                    "original" => ticker,
                    "date" => bankruptcy_date,
                    "status" => get(bankruptcy_info, "status", ""),
                    "successor" => get(bankruptcy_info, "successor", nothing),
                    "forced_sale" => true,
                    "cutoff_date" => bankruptcy_date,
                    "tiingo_coverage" => tiingo_coverage,
                    "note" => get(bankruptcy_info, "note", "")
                )
            )
        end
    end

    # Verificar fusões - merger of equals (continua série)
    mergers = get(config, "mergers", Dict())
    for (merger_name, merger_info) in mergers
        tickers_in_merger = get(merger_info, "tickers", [])
        if ticker in tickers_in_merger
            successor = get(merger_info, "successor", "")
            if !isempty(successor)
                if forced_mode == "strict"
                    return Dict(
                        "ticker" => ticker,
                        "method" => "forced_sale_merger",
                        "confidence" => "high",
                        "metadata" => Dict(
                            "original" => ticker,
                            "successor" => successor,
                            "merger_name" => merger_name,
                            "date" => get(merger_info, "date", ""),
                            "forced_sale" => true,
                            "cutoff_date" => get(merger_info, "date", ""),
                            "description" => get(merger_info, "description", "")
                        )
                    )
                else
                    return Dict(
                        "ticker" => successor,
                        "method" => "corporate_merger",
                        "confidence" => "high",
                        "metadata" => Dict(
                            "original" => ticker,
                            "successor" => successor,
                            "merger_name" => merger_name,
                            "date" => get(merger_info, "date", ""),
                            "forced_sale" => false,
                            "description" => get(merger_info, "description", "")
                        )
                    )
                end
            end
        end
    end

    return nothing
end

"""
    apply_alternative_formats(ticker::String, config::Dict)

Tenta formatos alternativos (hífen ↔ ponto).
"""
function apply_alternative_formats(ticker::String, ::Dict)
    # Tentar hífen → ponto
    if contains(ticker, "-")
        dot_version = replace(ticker, "-" => ".")
        return Dict(
            "ticker" => dot_version,
            "method" => "format_alternative_dot",
            "confidence" => "medium",
            "metadata" => Dict(
                "original" => ticker,
                "alternative_format" => dot_version
            )
        )
    end
    
    # Tentar ponto → hífen  
    if contains(ticker, ".")
        hyphen_version = replace(ticker, "." => "-")
        return Dict(
            "ticker" => hyphen_version,
            "method" => "format_alternative_hyphen",
            "confidence" => "medium",
            "metadata" => Dict(
                "original" => ticker,
                "alternative_format" => hyphen_version
            )
        )
    end
    
    return nothing
end

"""
    apply_tiingo_search(ticker::String, config::Dict)

Usa Tiingo Search API para encontrar ticker alternativo baseado no nome da empresa.
"""
function apply_tiingo_search(ticker::String, ::Dict)
    try
        # Importar TiingoData se disponível
        if @isdefined TiingoData
            # Usar search API para encontrar alternativas
            search_results = TiingoData.search_ticker(ticker, verbose=false)

            if !isempty(search_results)
                # Procurar por match exato primeiro
                for result in search_results
                    result_ticker = get(result, "ticker", "")
                    if uppercase(result_ticker) == uppercase(ticker)
                        # Match exato encontrado
                        return Dict(
                            "ticker" => result_ticker,
                            "method" => "tiingo_search_exact",
                            "confidence" => "high",
                            "metadata" => Dict(
                                "original" => ticker,
                                "search_result" => result,
                                "company_name" => get(result, "name", "")
                            )
                        )
                    end
                end

                # Se não achou match exato, usar primeiro resultado se confiável
                first_result = search_results[1]
                first_ticker = get(first_result, "ticker", "")
                asset_type = get(first_result, "assetType", "")

                # Só aceitar resultados de equity
                if uppercase(asset_type) in ["STOCK", "EQUITY"]
                    return Dict(
                        "ticker" => first_ticker,
                        "method" => "tiingo_search_best_match",
                        "confidence" => "medium",
                        "metadata" => Dict(
                            "original" => ticker,
                            "search_result" => first_result,
                            "company_name" => get(first_result, "name", ""),
                            "asset_type" => asset_type
                        )
                    )
                end
            end
        end
    catch e
        @warn "Erro no Tiingo Search para $ticker: $e"
    end

    return nothing
end

"""
    get_config_version()::String

Retorna versão da configuração carregada.
"""
function get_config_version()::String
    config = load_ticker_config()
    return get(config, "version", "unknown")
end

"""
    validate_config(config::Dict)::Vector{String}

Valida estrutura da configuração, retorna lista de problemas.
"""
function validate_config(config::Dict)::Vector{String}
    issues = String[]
    
    # Verificar campos obrigatórios
    required_fields = ["version", "corporate_renames", "normalization_rules", "resolution_strategies"]
    for field in required_fields
        if !haskey(config, field)
            push!(issues, "Campo obrigatório faltando: $field")
        end
    end
    
    # Verificar estrutura de estratégias
    strategies = get(config, "resolution_strategies", [])
    if !isa(strategies, Vector)
        push!(issues, "resolution_strategies deve ser uma lista")
    else
        for (i, strategy) in enumerate(strategies)
            if !haskey(strategy, "name")
                push!(issues, "Estratégia #$i não tem campo 'name'")
            end
        end
    end
    
    return issues
end

"""
    fast_ticker_lookup(ticker::String)::String

Lookup rápido com cache em memória para casos comuns.
Aplica apenas mapeamentos diretos mais importantes sem criar objetos.
"""
function fast_ticker_lookup(ticker::String)::String
    clean_ticker = uppercase(strip(ticker))
    
    # Verificar cache de lookup rápido primeiro
    if haskey(FAST_LOOKUP_CACHE, clean_ticker)
        return FAST_LOOKUP_CACHE[clean_ticker]
    end
    
    # Se não está no cache, fazer lookup direto apenas dos mapeamentos críticos
    config = load_ticker_config()
    
    # Verificar renomeações corporativas (mais frequente)
    renames = get(config, "corporate_renames", Dict())
    if haskey(renames, clean_ticker)
        resolved = renames[clean_ticker]
        FAST_LOOKUP_CACHE[clean_ticker] = resolved
        return resolved
    end
    
    # Verificar normalizações de símbolos
    rules = get(config, "normalization_rules", Dict())
    corrections = get(rules, "symbol_corrections", Dict())
    if haskey(corrections, clean_ticker)
        resolved = corrections[clean_ticker]
        # Evitar mapeamento reverso hífen → ponto (ex.: "BRK-B" -> "BRK.B")
        if contains(clean_ticker, "-") && contains(resolved, ".")
            # Ignora e continua para dot_to_hyphen
        else
            FAST_LOOKUP_CACHE[clean_ticker] = resolved
            return resolved
        end
    end
    
    # Aplicar regra dot_to_hyphen se habilitada
    dot_to_hyphen = get(rules, "dot_to_hyphen", Dict())
    if get(dot_to_hyphen, "enabled", false) && contains(clean_ticker, ".")
        pattern = get(dot_to_hyphen, "pattern", "\\.")
        replacement = get(dot_to_hyphen, "replacement", "-")
        normalized = replace(clean_ticker, Regex(pattern) => replacement)
        if normalized != clean_ticker
            FAST_LOOKUP_CACHE[clean_ticker] = normalized
            return normalized
        end
    end
    
    # Verificar preferências de classe de ações
    preferences = get(config, "share_class_preferences", Dict())
    if haskey(preferences, clean_ticker)
        preferred = preferences[clean_ticker]
        if preferred != clean_ticker
            FAST_LOOKUP_CACHE[clean_ticker] = preferred
            return preferred
        end
    end
    
    # Cachear o ticker original
    FAST_LOOKUP_CACHE[clean_ticker] = clean_ticker
    return clean_ticker
end

"""
    resolve_ticker_with_temporal_info(ticker::String)::NamedTuple

Resolve ticker e retorna informações temporais sobre forced sales.
Retorna: (ticker=String, forced_sale=Bool, cutoff_date=Union{String,Nothing}, metadata=Dict)
"""
function resolve_ticker_with_temporal_info(ticker::String)
    config = load_ticker_config()
    resolution = resolve_ticker_with_config(ticker, config)

    metadata = resolution.metadata
    forced_sale = get(metadata, "forced_sale", false)
    cutoff_date = get(metadata, "cutoff_date", nothing)

    return (
        ticker = resolution.resolved_ticker,
        forced_sale = forced_sale,
        cutoff_date = cutoff_date,
        metadata = metadata,
        resolution_method = resolution.method
    )
end

end # module
