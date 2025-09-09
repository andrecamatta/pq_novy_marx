# Solução para YFinance com proxy corporativo
# Baixa dados diretamente usando HTTP.jl com configurações de proxy

using HTTP
using JSON3
using DataFrames
using Dates
using CSV
using Statistics

println("=" ^ 60)
println("DOWNLOAD YAHOO FINANCE COM PROXY")
println("=" ^ 60)

# Função para baixar dados com proxy
function download_yahoo_data(ticker::String, start_date::Date, end_date::Date)
    # Converter datas para timestamps Unix
    period1 = Int(Dates.datetime2unix(DateTime(start_date)))
    period2 = Int(Dates.datetime2unix(DateTime(end_date)))
    
    # URL da API do Yahoo Finance
    url = "https://query2.finance.yahoo.com/v8/finance/chart/$ticker"
    
    # Parâmetros da query
    params = Dict(
        "period1" => period1,
        "period2" => period2,
        "interval" => "1d",
        "events" => "",
        "includePrePost" => "false"
    )
    
    # Configurar proxy a partir das variáveis de ambiente
    proxy_url = ENV["HTTPS_PROXY"]
    
    println("\nBaixando dados de $ticker...")
    println("  Período: $start_date a $end_date")
    println("  Usando proxy: $proxy_url")
    
    try
        # Fazer requisição com proxy
        response = HTTP.get(url, 
                          query=params,
                          proxy=proxy_url,
                          readtimeout=60,
                          retry=false)
        
        if response.status == 200
            println("  ✓ Download bem-sucedido!")
            
            # Parse JSON
            data = JSON3.read(String(response.body))
            
            # Extrair dados
            result = data["chart"]["result"][1]
            timestamps = result["timestamp"]
            quotes = result["indicators"]["quote"][1]
            
            # Criar DataFrame
            df = DataFrame(
                timestamp = [Date(Dates.unix2datetime(ts)) for ts in timestamps],
                open = Float64.(quotes["open"]),
                high = Float64.(quotes["high"]),
                low = Float64.(quotes["low"]),
                close = Float64.(quotes["close"]),
                volume = Float64.(quotes["volume"])
            )
            
            # Adicionar coluna adjclose (usar close como proxy)
            if haskey(result["indicators"], "adjclose")
                adjclose_data = result["indicators"]["adjclose"][1]["adjclose"]
                df[!, :adjclose] = Float64.(adjclose_data)
            else
                df[!, :adjclose] = df.close
            end
            
            return df
        else
            println("  ✗ Erro HTTP: status $(response.status)")
            return DataFrame()
        end
        
    catch e
        println("  ✗ Erro ao baixar: $e")
        return DataFrame()
    end
end

# Função principal para baixar múltiplos tickers
function download_multiple_tickers(tickers::Vector{String}, start_date::Date, end_date::Date)
    all_data = DataFrame()
    
    for ticker in tickers
        df = download_yahoo_data(ticker, start_date, end_date)
        
        if !isempty(df)
            df[!, :ticker] .= ticker  # Usar broadcast para atribuir o valor
            
            if isempty(all_data)
                all_data = df
            else
                all_data = vcat(all_data, df)
            end
        end
        
        # Pequena pausa entre requisições
        sleep(0.5)
    end
    
    return all_data
end

# Testar com alguns tickers
println("\nTestando download com proxy...")

test_tickers = ["AAPL", "MSFT", "GOOGL", "AMZN", "NVDA"]
start_date = Date(2024, 1, 1)
end_date = Date(2024, 2, 29)

data = download_multiple_tickers(test_tickers, start_date, end_date)

if !isempty(data)
    println("\n" * "=" ^ 60)
    println("RESULTADO DO TESTE")
    println("=" ^ 60)
    
    println("\nDados baixados com sucesso!")
    println("Total de registros: $(nrow(data))")
    println("Tickers obtidos: $(unique(data.ticker))")
    
    # Salvar em CSV
    CSV.write("yahoo_data_test.csv", data)
    println("\nDados salvos em 'yahoo_data_test.csv'")
    
    # Mostrar estatísticas por ticker
    println("\nEstatísticas por ticker:")
    for gdf in groupby(data, :ticker)
        ticker = first(gdf.ticker)
        n_days = nrow(gdf)
        first_date = minimum(gdf.timestamp)
        last_date = maximum(gdf.timestamp)
        avg_close = mean(gdf.close)
        
        println("  $ticker: $n_days dias, de $first_date a $last_date, preço médio: \$$(round(avg_close, digits=2))")
    end
else
    println("\n✗ Nenhum dado foi baixado. Verifique a conectividade.")
end

println("\n" * "=" ^ 60)
println("TESTE CONCLUÍDO")
println("=" ^ 60)