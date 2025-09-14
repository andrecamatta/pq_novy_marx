"""
Sistema de download com fallback seguro
NUNCA usa dados simulados - apenas dados financeiros reais
"""
module DownloadFallback

using DataFrames, Dates
using ..StooqData, ..TiingoData

export download_with_fallback

"""
    download_with_fallback(tickers, start_date, end_date; verbose=true)

Download seguro com fallback: Stooq bulk → Tiingo → falha explícita
NUNCA usa dados simulados para garantir integridade da análise.
"""
function download_with_fallback(
    tickers::Vector{String},
    start_date::Date,
    end_date::Date;
    verbose::Bool = true
)::Dict{String, DataFrame}

    if verbose
        println("🌐 DOWNLOAD COM FALLBACK SEGURO")
        println("-"^50)
        println("📊 Tickers solicitados: $(length(tickers))")
    end

    # Verificação de universo muito grande - download inteligente
    if length(tickers) > 500
        if verbose
            println("⚠️  Universo grande ($(length(tickers)) tickers), usando estratégia híbrida...")
            println("🔄 1. Stooq bulk primeiro, depois Tiingo para faltantes críticos")
        end
    end

    price_data = Dict{String, DataFrame}()

    # FASE 1: Stooq bulk (fonte primária)
    if verbose
        println("📦 1. Tentando Stooq bulk...")
    end

    try
        stooq_data = StooqData.download_stooq_bulk_us_selective(
            tickers,
            cache_dir="data/cache/stooq_bulk",
            verbose=verbose
        )

        merge!(price_data, stooq_data)

        if verbose
            println("✅ Stooq: $(length(stooq_data)) tickers encontrados")
        end

    catch e
        if verbose
            println("⚠️  Stooq falhou: $e")
        end
    end

    # FASE 2: Tiingo para tickers faltantes
    missing_tickers = setdiff(tickers, keys(price_data))

    if !isempty(missing_tickers) && length(missing_tickers) <= 200  # Limite Tiingo expandido
        if verbose
            println("🔄 2. Tentando Tiingo API para $(length(missing_tickers)) tickers faltantes...")
            println("⏱️  Estimativa: $(length(missing_tickers) * 2) segundos (rate limiting)")
        end

        tiingo_success = 0
        tiingo_cache_hits = 0
        tiingo_api_calls = 0

        for (i, ticker) in enumerate(missing_tickers)
            try
                # Verificar se vai vir de cache ou API
                cache_file = "data/cache/tiingo/$(ticker)_$(start_date)_$(end_date).jld2"
                from_cache = isfile(cache_file)

                df = TiingoData.download_tiingo_eod(
                    ticker,
                    start_date,
                    end_date,
                    use_cache=true,
                    verbose=false
                )

                if !isempty(df) && nrow(df) > 20
                    price_data[ticker] = df
                    tiingo_success += 1

                    if from_cache
                        tiingo_cache_hits += 1
                        if verbose && i <= 10
                            println("   📂 $ticker: cache JLD2 ✅")
                        end
                    else
                        tiingo_api_calls += 1
                        if verbose
                            println("   🌐 $ticker: API call ✅ → salvando cache")
                        end
                    end

                    if verbose && i % 20 == 0
                        println("   📊 Progresso: $i/$(length(missing_tickers)) (Cache:$tiingo_cache_hits API:$tiingo_api_calls)")
                    end
                end

            catch e
                if verbose && (i <= 5 || i % 50 == 0)  # Mostrar apenas alguns erros
                    println("⚠️  Tiingo falhou para $ticker: $e")
                end
            end

            # Rate limiting: pausa entre requests (apenas se for API call)
            if i < length(missing_tickers) && !isfile("data/cache/tiingo/$(missing_tickers[i+1])_$(start_date)_$(end_date).jld2")
                sleep(0.1)  # 100ms entre requests
            end
        end

        if verbose
            println("✅ Tiingo RESULTADOS:")
            println("   📂 Cache hits: $tiingo_cache_hits")
            println("   🌐 API calls: $tiingo_api_calls")
            println("   ✅ Total sucessos: $tiingo_success")
        end
    end

    # VERIFICAÇÃO FINAL
    final_count = length(price_data)
    coverage_rate = final_count / length(tickers) * 100
    min_required = max(400, length(tickers) * 0.6)  # Mínimo 400 tickers para análise robusta

    if verbose
        println("\n📊 RESULTADO FINAL:")
        println("✅ Sucesso: $final_count tickers")
        println("📈 Taxa de sucesso: $(round(coverage_rate, digits=1))%")
        println("🎯 Mínimo requerido: $min_required tickers")
    end

    # Falha explícita se dados insuficientes
    if final_count < min_required
        error("""
        ❌ DADOS INSUFICIENTES: $final_count tickers encontrados de $(length(tickers)) solicitados

        📊 Taxa de sucesso: $(round(coverage_rate, digits=1))%
        🎯 Mínimo requerido: $min_required tickers

        ⚠️  IMPORTANTE: Este sistema NUNCA usa dados simulados para garantir integridade da análise.

        💡 Sugestões:
        1. Verificar conectividade de rede
        2. Confirmar disponibilidade do arquivo bulk Stooq
        3. Validar API key do Tiingo
        4. Considerar período menor para análise
        """)
    end

    return price_data
end

end # module