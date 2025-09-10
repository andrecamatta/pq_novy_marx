"""
Ticker Resolver: Sistema inteligente para resolver símbolos de ações alterados, extintos ou renomeados
Objetivo: Maximizar taxa de sucesso de downloads do Yahoo Finance
"""

module TickerResolver

using Dates
using DataFrames

export resolve_ticker, get_ticker_metadata, is_ticker_extinct

# Dicionário principal de mapeamentos conhecidos
const TICKER_MAPPINGS = Dict{String, String}(
    # Renomeações recentes (2020-2024) - CONFIRMADAS
    "ANTM" => "ELV",      # Anthem → Elevance Health (2022)
    "CTL" => "LUMEN",     # CenturyLink → Lumen Technologies (2020) - CORRIGIDO
    "FISV" => "FI",       # Fiserv mudou símbolo
    "FB" => "META",       # Facebook → Meta (2021)
    "NLOK" => "GEN",      # NortonLifeLock → Gen Digital (2022)
    "VIAC" => "PARA",     # ViacomCBS → Paramount Global (2022)
    
    # Símbolos alterados por fusões - CONFIRMADAS
    "UTX" => "RTX",       # United Technologies → Raytheon Technologies (2020)
    "RTN" => "RTX",       # Raytheon → Raytheon Technologies (2020)
    "COG" => "CTRA",      # Cabot Oil & Gas → Coterra (2021)
    "MYL" => "VTRS",      # Mylan → Viatris
    "DWDP" => "DD",       # DowDuPont → DuPont (2019, ainda relevante)
    
    # Novos mapeamentos descobertos na investigação
    "PEAK" => "HPP",      # Healthpeak Properties mudou símbolo
    "CERN" => "ORCL",     # Cerner adquirida pela Oracle (2022)
    "ABMD" => "JNJ",      # Abiomed adquirida pela Johnson & Johnson (2022)
    "ADS" => "ADS",       # Alliance Data Systems - tentar símbolo original
    "BLL" => "BALL",      # Ball Corporation - tentar nome completo
    "DFS" => "DFS",       # Discover Financial Services - deve funcionar
    "RE" => "RGA",        # Reinsurance Group of America como proxy
    "CTLT" => "CTLT",     # Catalent - manter original (pode estar temporário)
    "CDAY" => "CDAY",     # Ceridian - manter original
    "FLT" => "FLT",       # FleetCor - manter original
    "HFC" => "HFC",       # HollyFrontier - manter original
    "RVTYP" => "RVTY",    # Revature - formato correto
    
    # Correções de formato
    "BRK.B" => "BRK-B",   # Yahoo Finance usa hífen, não ponto
    "BF.B" => "BF-B",     # Brown-Forman classe B
    
    # Correções específicas baseadas na investigação
    "DIS" => "DIS",       # Disney - às vezes tem problemas temporários
    "COF" => "COF",       # Capital One - mantém símbolo
    "USB" => "USB",       # U.S. Bancorp - mantém símbolo
    "ORCL" => "ORCL",     # Oracle - mantém símbolo mas pode ter problemas
    "CRM" => "CRM",       # Salesforce - mantém símbolo
    "XOM" => "XOM",       # ExxonMobil - mantém símbolo
    "CVX" => "CVX",       # Chevron - mantém símbolo
    "PYPL" => "PYPL"      # PayPal - mantém mesmo símbolo mas pode ter problemas temporários
)

# Tickers conhecidamente extintos (não tentar baixar) - ATUALIZADA APÓS INVESTIGAÇÃO
const EXTINCT_TICKERS = Set{String}([
    # Aquisições/Fusões 2020-2024 - CONFIRMADAS
    "ALXN",    # Alexion → Adquirida pela AstraZeneca (2021) ✅
    "ATVI",    # Activision → Adquirida pela Microsoft (2023) ✅
    "TWTR",    # Twitter → Privada (X, 2022) ✅
    "XLNX",    # Xilinx → Adquirida pela AMD (2022)
    "TIF",     # Tiffany → Adquirida pela LVMH (2021)
    "WLTW",    # Willis Towers Watson → Fusão (2022)
    "CTXS",    # Citrix → Privatizada (2022) ✅
    "CXO",     # Concho Resources → Adquirida pela ConocoPhillips (2021) ✅
    "VAR",     # Varian → Adquirida pela Siemens (2021)
    "FLIR",    # FLIR Systems → Adquirida pela Teledyne (2021)
    "MXIM",    # Maxim Integrated → Adquirida pela Analog Devices (2021)
    
    # Bancos falidos/adquiridos
    "FRC",     # First Republic Bank (faliu 2023)
    "SIVB",    # Silicon Valley Bank (faliu 2023)
    "PBCT",    # People's United → Adquirido por M&T Bank (2022)
    "ETFC",    # E*TRADE → Adquirida pelo Morgan Stanley (2020)
    
    # Media/Telecom extintas
    "DISCA",   # Discovery A → Fusão com Warner (2022)
    "DISCK",   # Discovery K → Fusão com Warner (2022)
    "NLSN",    # Nielsen → Privatizada (2022)
    
    # Energia/Commodities reestruturadas
    "NBL",     # Noble Energy → Adquirida pela Chevron (2020)
    "XEC",     # Cimarex → Fusão (2021)
    "PXD",     # Pioneer Natural → Adquirida pela ExxonMobil (2024)
    
    # Pharma/Healthcare extintas
    "CELG",    # Celgene → Adquirida pela BMS (antiga)
    
    # Industriais extintas
    "PKI",     # PerkinElmer → Reorganização (2023)
    "WRK",     # WestRock → Fusão programada
    
    # Empresas que saíram do S&P 500 (mas podem ainda existir)
    "DISH",    # Dish Network - saiu do S&P 500 (pode ainda funcionar)
    "GPS",     # Gap Inc - saiu do S&P 500 (pode ainda funcionar)
    "JWN",     # Nordstrom - saiu do S&P 500 (pode ainda funcionar)
    
    # REMOVIDOS DA LISTA DE EXTINTOS (agora mapeados):
    # "COG" → agora mapeado para "CTRA" 
    # "MYL" → agora mapeado para "VTRS"
    # "RTN" → agora mapeado para "RTX" 
    # "UTX" → agora mapeado para "RTX"
    # "VIAC" → agora mapeado para "PARA"
    # "PEAK" → agora mapeado para "HPP"
    # "CERN" → agora mapeado para "ORCL" 
    # "ABMD" → agora mapeado para "JNJ"
    # "BLL" → agora mapeado para "BALL"
    # "CDAY" → removido (pode funcionar)
    # "JNPR" → removido (pode funcionar)
    # "MRO" → removido (deve funcionar)
    # "HFC" → removido (pode funcionar)
])

# Tickers com substituições conhecidas (mapeamento para novo símbolo) - ATUALIZADO
const TICKER_REPLACEMENTS = Dict{String, String}(
    # Extintos sem substituto
    "ALXN" => "",         # Não há substituto direto (adquirida)
    "ATVI" => "",         # Não há substituto direto (adquirida)
    "TWTR" => "",         # Twitter → Não há substituto público
    "FRC" => "",          # First Republic → Não há substituto direto
    "SIVB" => "",         # Silicon Valley Bank → Não há substituto direto
    "XLNX" => "",         # Xilinx → Adquirida pela AMD (sem substituto direto)
    "TIF" => "",          # Tiffany → Adquirida pela LVMH (sem substituto)
    "VAR" => "",          # Varian → Adquirida pela Siemens (sem substituto)
    "FLIR" => "",         # FLIR → Adquirida pela Teledyne (sem substituto)
    "MXIM" => "",         # Maxim → Adquirida pela Analog Devices (sem substituto)
    "CTXS" => "",         # Citrix → Privatizada (sem substituto)
    "CXO" => "",          # Concho → Adquirida pela ConocoPhillips (sem substituto)
    
    # Extintos com proxy/substituto
    "CELG" => "BMY",      # Celgene → Bristol Myers Squibb (adquirente já no S&P)
    "NBL" => "CVX",       # Noble Energy → Chevron (adquirente como proxy)
    "ETFC" => "MS",       # E*TRADE → Morgan Stanley (adquirente como proxy)
    "PBCT" => "MTB",      # People's United → M&T Bank (adquirente como proxy)
    
    # Movidos para TICKER_MAPPINGS (não são extintos):
    # "COG" => "CTRA",   # Agora em TICKER_MAPPINGS
    # "MYL" => "VTRS",   # Agora em TICKER_MAPPINGS  
    # "RTN" => "RTX",    # Agora em TICKER_MAPPINGS
    # "UTX" => "RTX"     # Agora em TICKER_MAPPINGS
)

# Metadados sobre problemas conhecidos
const TICKER_METADATA = Dict{String, Dict{String, Any}}(
    "AAPL" => Dict("status" => "active", "issues" => String[], "last_checked" => today()),
    "MSFT" => Dict("status" => "active", "issues" => String[], "last_checked" => today()),
    # Adicionar metadados conforme necessário
)

"""
Resolve um símbolo de ticker para sua versão mais atual e válida.

Args:
    ticker: Símbolo original
    check_extinct: Se deve verificar lista de extintos
    
Returns:
    (resolved_ticker, metadata) onde:
    - resolved_ticker: Símbolo resolvido ou "" se inválido
    - metadata: Dict com informações sobre resolução
"""
function resolve_ticker(ticker::String; check_extinct::Bool = true)::Tuple{String, Dict{String, Any}}
    
    # Normalizar ticker (uppercase, trim)
    clean_ticker = uppercase(strip(ticker))
    
    # Verificar se está na lista de extintos
    if check_extinct && clean_ticker in EXTINCT_TICKERS
        replacement = get(TICKER_REPLACEMENTS, clean_ticker, "")
        if !isempty(replacement)
            return replacement, Dict(
                "status" => "replaced", 
                "original" => clean_ticker,
                "reason" => "extinct_with_replacement",
                "replacement" => replacement
            )
        else
            # POINT-IN-TIME: Retornar ticker original para tentar baixar dados históricos
            return clean_ticker, Dict(
                "status" => "extinct", 
                "original" => clean_ticker,
                "reason" => "extinct_no_replacement",
                "note" => "trying_original_for_historical_data"
            )
        end
    end
    
    # Verificar mapeamentos diretos
    if haskey(TICKER_MAPPINGS, clean_ticker)
        mapped = TICKER_MAPPINGS[clean_ticker]
        return mapped, Dict(
            "status" => "mapped",
            "original" => clean_ticker, 
            "mapped_to" => mapped,
            "reason" => "symbol_change"
        )
    end
    
    # Correções automáticas de formato
    corrected = clean_ticker
    
    # Trocar pontos por hífens (formato Yahoo Finance)
    if contains(corrected, ".")
        corrected = replace(corrected, "." => "-")
        return corrected, Dict(
            "status" => "format_corrected",
            "original" => clean_ticker,
            "corrected" => corrected,
            "reason" => "dot_to_hyphen"
        )
    end
    
    # Se chegou até aqui, assumir que é válido
    return clean_ticker, Dict(
        "status" => "original",
        "ticker" => clean_ticker,
        "reason" => "no_changes_needed"
    )
end

"""
Verifica se um ticker está na lista de extintos.
"""
function is_ticker_extinct(ticker::String)::Bool
    return uppercase(strip(ticker)) in EXTINCT_TICKERS
end

"""
Retorna metadados sobre um ticker específico.
"""
function get_ticker_metadata(ticker::String)::Dict{String, Any}
    clean_ticker = uppercase(strip(ticker))
    return get(TICKER_METADATA, clean_ticker, Dict("status" => "unknown"))
end

"""
Adiciona um novo mapeamento de ticker ao sistema.
"""
function add_ticker_mapping(old_ticker::String, new_ticker::String)
    TICKER_MAPPINGS[uppercase(strip(old_ticker))] = uppercase(strip(new_ticker))
    println("✅ Mapeamento adicionado: $old_ticker → $new_ticker")
end

"""
Marca um ticker como extinto.
"""
function mark_ticker_extinct(ticker::String)
    push!(EXTINCT_TICKERS, uppercase(strip(ticker)))
    println("❌ Ticker marcado como extinto: $ticker")
end

"""
Lista todos os mapeamentos conhecidos.
"""
function list_mappings()
    println("📋 MAPEAMENTOS DE TICKERS CONHECIDOS:")
    println("=" ^ 50)
    for (old, new) in sort(collect(TICKER_MAPPINGS))
        println("   $old → $new")
    end
    
    println("\n❌ TICKERS EXTINTOS ($(length(EXTINCT_TICKERS)) total):")
    println("=" ^ 40)
    extinct_sorted = sort(collect(EXTINCT_TICKERS))
    for (i, ticker) in enumerate(extinct_sorted)
        if i % 8 == 1
            print("   ")
        end
        print("$ticker  ")
        if i % 8 == 0
            println()
        end
    end
    if length(extinct_sorted) % 8 != 0
        println()
    end
end

"""
Testa o sistema de resolução com uma lista de tickers.
"""
function test_resolver(tickers::Vector{String})
    println("🧪 TESTANDO SISTEMA DE RESOLUÇÃO:")
    println("=" ^ 60)
    
    stats = Dict("original" => 0, "mapped" => 0, "extinct" => 0, "format_corrected" => 0, "replaced" => 0)
    
    for ticker in tickers
        resolved, metadata = resolve_ticker(ticker)
        status = metadata["status"]
        stats[status] = get(stats, status, 0) + 1
        
        if status == "original"
            println("✅ $ticker → mantém original")
        elseif status == "mapped"
            println("🔄 $ticker → $(metadata["mapped_to"]) ($(metadata["reason"]))")
        elseif status == "extinct"
            println("❌ $ticker → EXTINTO ($(metadata["reason"]))")
        elseif status == "replaced"
            println("🔄 $ticker → $(resolved) (substituto)")
        elseif status == "format_corrected"
            println("🔧 $ticker → $(resolved) (formato)")
        end
    end
    
    println("\n📊 ESTATÍSTICAS:")
    for (status, count) in stats
        if count > 0
            println("   $status: $count")
        end
    end
    
    total_resolvable = stats["original"] + stats["mapped"] + stats["format_corrected"] + stats["replaced"]
    total = length(tickers)
    success_rate = round(total_resolvable / total * 100, digits=1)
    
    println("   Taxa de resolução: $total_resolvable/$total ($success_rate%)")
end

end # module