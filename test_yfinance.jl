# Teste simples de conectividade do YFinance

using YFinance
using Dates
using HTTP

println("=" ^ 60)
println("TESTE DE CONECTIVIDADE YFINANCE")
println("=" ^ 60)

# Teste 1: Verificar conectividade HTTP básica
println("\n1. Testando conectividade HTTP com Yahoo Finance...")
try
    response = HTTP.get("https://finance.yahoo.com")
    println("   ✓ Conexão com finance.yahoo.com OK (status: $(response.status))")
catch e
    println("   ✗ Erro ao conectar: $e")
end

# Teste 2: Tentar baixar dados de apenas 1 ação
println("\n2. Testando download de dados de AAPL...")
try
    # Período curto para teste
    start_date = Date(2024, 1, 1)
    end_date = Date(2024, 1, 31)
    
    println("   Período: $start_date a $end_date")
    
    data = get_prices("AAPL", startdt=start_date, enddt=end_date)
    
    if !isempty(data)
        println("   ✓ Download bem-sucedido!")
        println("   Registros obtidos: $(nrow(data))")
        println("   Primeiras linhas:")
        println(first(data, 3))
    else
        println("   ✗ Dados vazios retornados")
    end
catch e
    println("   ✗ Erro ao baixar dados: $e")
    println("\n   Stack trace:")
    for (exc, bt) in Base.catch_stack()
        showerror(stdout, exc, bt)
        println()
    end
end

# Teste 3: Verificar configurações de proxy
println("\n3. Verificando configurações de ambiente...")
proxy_vars = ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "NO_PROXY", "no_proxy"]

for var in proxy_vars
    val = get(ENV, var, nothing)
    if val !== nothing
        println("   $var = $val")
    end
end

if all(var -> get(ENV, var, nothing) === nothing, proxy_vars)
    println("   Nenhuma variável de proxy configurada")
end

# Teste 4: Testar URL direta da API
println("\n4. Testando URL direta da API do Yahoo Finance...")
test_url = "https://query2.finance.yahoo.com/v8/finance/chart/AAPL?interval=1d&period1=1704067200&period2=1706659200"

try
    response = HTTP.get(test_url)
    println("   ✓ Conexão com API OK (status: $(response.status))")
    
    # Verificar se retornou JSON válido
    body_str = String(response.body)
    if occursin("\"result\"", body_str)
        println("   ✓ Resposta parece ser válida (contém 'result')")
    else
        println("   ? Resposta pode estar em formato inesperado")
        println("   Primeiros 200 caracteres: $(first(body_str, min(200, length(body_str))))")
    end
catch e
    println("   ✗ Erro ao acessar API: $e")
end

# Teste 5: Verificar versão do YFinance
println("\n5. Informações do pacote YFinance...")
using Pkg
try
    pkg_info = Pkg.status("YFinance"; mode=PKGMODE_MANIFEST)
    println("   Versão instalada do YFinance")
catch e
    println("   Não foi possível obter informações do pacote")
end

# Teste 6: Tentar com timeout maior
println("\n6. Testando com configurações HTTP customizadas...")
try
    # Configurar timeout maior
    HTTP.set_default_connection_limit!(10)
    
    # Tentar novamente
    data = get_prices("MSFT", startdt=Date(2024, 1, 1), enddt=Date(2024, 1, 10))
    
    if !isempty(data)
        println("   ✓ Download com timeout customizado funcionou!")
        println("   Registros: $(nrow(data))")
    else
        println("   ✗ Ainda retornando dados vazios")
    end
catch e
    println("   ✗ Erro mesmo com configurações customizadas: $e")
end

println("\n" * ("=" ^ 60))
println("TESTE CONCLUÍDO")
println("=" ^ 60)