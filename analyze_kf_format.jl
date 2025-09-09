# Script para analisar formato real dos dados Kenneth French

using HTTP, Dates

println("🔍 ANÁLISE DO FORMATO KENNETH FRENCH")
println("=" ^ 60)

try
    println("📥 Baixando arquivo real da biblioteca Kenneth French...")
    
    # URL do arquivo 5-factor model
    url = "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp/F-F_Research_Data_5_Factors_2x3_CSV.zip"
    
    # Download
    response = HTTP.get(url, timeout=30)
    
    if response.status == 200
        println("✅ Download realizado com sucesso ($(length(response.body)) bytes)")
        
        # Salvar ZIP temporário
        temp_zip = "kf_sample.zip"
        open(temp_zip, "w") do f
            write(f, response.body)
        end
        
        println("📁 Arquivo ZIP salvo como: $temp_zip")
        
        # Vamos usar um método simples para extrair e examinar
        # (assumindo que o sistema tem unzip disponível)
        try
            println("\n📂 Tentando extrair o conteúdo do ZIP...")
            
            # Usar comando do sistema para extrair
            run(`unzip -o $temp_zip`)
            
            println("✅ ZIP extraído com sucesso")
            
            # Listar arquivos extraídos
            println("\n📋 Arquivos extraídos:")
            for file in readdir(".")
                if endswith(file, ".CSV") || endswith(file, ".csv")
                    println("   📄 $file")
                    
                    # Ler e analisar primeiras linhas
                    println("\n🔍 Analisando estrutura de $file:")
                    println("   Primeiras 20 linhas:")
                    println("   " * "-" ^ 50)
                    
                    content = read(file, String)
                    lines = split(content, "\n")
                    
                    for (i, line) in enumerate(lines[1:min(20, length(lines))])
                        println("   $(lpad(i, 2)): $line")
                    end
                    
                    println("\n   " * "-" ^ 50)
                    println("   Total de linhas: $(length(lines))")
                    
                    # Procurar por padrões
                    println("\n🎯 Identificando padrões:")
                    
                    # Procurar início dos dados mensais
                    for (i, line) in enumerate(lines)
                        # Procurar por linhas que parecem datas (6 dígitos)
                        if match(r"^\s*\d{6}", line) !== nothing
                            println("   📅 Possível linha de dados mensais (linha $i): $line")
                            if i <= 10  # Mostrar apenas primeiras ocorrências
                                break
                            end
                        end
                        
                        # Procurar cabeçalhos
                        if contains(lowercase(line), "mkt") && contains(lowercase(line), "smb")
                            println("   📊 Possível cabeçalho (linha $i): $line")
                        end
                    end
                    
                    # Salvar análise em arquivo
                    analysis_file = "kf_format_analysis.txt"
                    open(analysis_file, "w") do f
                        write(f, "ANÁLISE DO FORMATO KENNETH FRENCH\n")
                        write(f, "=" ^ 40 * "\n\n")
                        write(f, "Arquivo: $file\n")
                        write(f, "Total de linhas: $(length(lines))\n\n")
                        write(f, "Primeiras 30 linhas:\n")
                        write(f, "-" ^ 40 * "\n")
                        for (i, line) in enumerate(lines[1:min(30, length(lines))])
                            write(f, "$(lpad(i, 3)): $line\n")
                        end
                        
                        write(f, "\nÚltimas 10 linhas:\n")
                        write(f, "-" ^ 40 * "\n")
                        start_idx = max(1, length(lines) - 9)
                        for (i, line) in enumerate(lines[start_idx:end])
                            write(f, "$(lpad(start_idx + i - 1, 3)): $line\n")
                        end
                    end
                    
                    println("💾 Análise detalhada salva em: $analysis_file")
                    break # Analisar apenas o primeiro arquivo CSV
                end
            end
            
        catch e
            println("⚠️  Não foi possível extrair com 'unzip'. Tentando método alternativo...")
            
            # Método alternativo: ler ZIP binário e procurar padrões
            println("📊 Analisando conteúdo ZIP diretamente...")
            
            zip_content = String(response.body[1:min(2000, end)])  # Primeiros 2KB
            
            if contains(zip_content, "Mkt-RF") || contains(zip_content, "SMB")
                println("✅ Encontrados indicadores de fatores Fama-French no ZIP")
            else
                println("⚠️  Não encontrados indicadores esperados")
            end
            
            println("💡 Para análise completa, instale 'unzip' ou use ZipFile.jl")
        end
        
    else
        println("❌ Falha no download: HTTP $(response.status)")
    end
    
catch e
    println("❌ Erro durante análise: $e")
    
    println("\n💡 Informações conhecidas sobre formato Kenneth French:")
    println("   📋 Formato típico:")
    println("   - Arquivo ZIP contém CSV")
    println("   - Cabeçalho com nome dos fatores")
    println("   - Datas no formato YYYYMM (ex: 202401)")
    println("   - Valores separados por espaços/vírgulas")
    println("   - Seções diferentes (mensal, anual)")
    println("   - Linhas de comentário/notas no final")
    
    println("\n🎯 Próximos passos:")
    println("   1. Implementar parser baseado em formato conhecido") 
    println("   2. Testar com diferentes arquivos")
    println("   3. Validar com dados de referência")
end

println("\n🏁 Análise concluída!")