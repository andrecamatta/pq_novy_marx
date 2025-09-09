# Atribuição de Dados

## Dados Históricos de Constituintes do S&P 500

Este projeto utiliza dados históricos de constituintes do S&P 500 de:

**Repositório**: [hanshof/sp500_constituents](https://github.com/hanshof/sp500_constituents)  
**Licença**: Licença MIT  
**Arquivo Utilizado**: `sp_500_historical_components.csv`

### Por Que Estes Dados São Fundamentais

Os dados históricos de constituintes são essenciais para:
- **Eliminar viés de sobrevivência** - inclui empresas que foram removidas da lista, faliram ou foram adquiridas
- **Análise point-in-time** - usa participação real no S&P 500 em cada data
- **Cobertura abrangente** - rastreia 1.128 tickers únicos de 1996-2025

### Estatísticas dos Dados
- **Período**: 1996-01-02 a 2025-01-10  
- **Total de Registros**: 3.482 snapshots diários
- **Tickers Únicos**: 1.128 empresas
- **Eventos Principais Capturados**:
  - Falência da Enron (2001)
  - Remoções da crise financeira (2008-2009)
  - Vítimas da bolha tecnológica (2000-2002)
  - Mudanças no mercado por COVID-19 (2020)

### Conformidade com Licença

Os dados originais são fornecidos sob Licença MIT, que permite:
- Uso comercial e privado
- Distribuição e modificação
- Com exigência de aviso de licença e direitos autorais

Mantemos a mesma Licença MIT para este projeto para garantir compatibilidade.

## Dados de Fatores Fama-French

### Kenneth French Data Library
Este projeto baixa automaticamente dados reais de fatores Fama-French de:

**Fonte**: [Kenneth French Data Library](https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/data_library.html)  
**Instituição**: Tuck School of Business, Dartmouth College  
**Arquivo Utilizado**: F-F Research Data 5 Factors (2x3)  

### Fatores Incluídos
- **MKT-RF**: Prêmio de risco de mercado (Retorno de Mercado - Taxa Livre de Risco)
- **SMB**: Small Minus Big (Fator Tamanho)
- **HML**: High Minus Low (Fator Valor - Book-to-Market)
- **RMW**: Robust Minus Weak (Fator Profitabilidade)
- **CMA**: Conservative Minus Aggressive (Fator Investimento)
- **RF**: Taxa Livre de Risco

### Período e Cobertura
- **Disponibilidade**: 1963 a presente (atualizado mensalmente)
- **Observações**: 744+ observações mensais
- **Formato**: Percentual mensal
- **Metodologia**: Seguindo Fama & French (2015)

## Reconhecimentos

### Dados Históricos S&P 500
Agradecimentos especiais aos mantenedores do [hanshof/sp500_constituents](https://github.com/hanshof/sp500_constituents) por disponibilizar publicamente estes dados financeiros críticos. Sem este dataset, a correção adequada do viés de sobrevivência não seria possível.

### Kenneth French Data Library
Reconhecimento ao Professor Kenneth French e à Tuck School of Business por manter a Kenneth French Data Library, fornecendo dados de fatores de alta qualidade essenciais para pesquisa acadêmica em finanças.

### Implementação Novy-Marx
Este projeto implementa a metodologia descrita em:
**Novy-Marx, R.** (2013). The other side of value: The gross profitability premium. *Journal of Financial Economics*, 108(1), 1-28.

---

## Citação Acadêmica

Se você usar este projeto ou seus dados em sua pesquisa, por favor cite também as fontes originais de dados:

### Para Dados S&P 500:
```bibtex
@misc{sp500_constituents,
  author = {hanshof},
  title = {S&P 500 Historical Constituents},
  year = {2025},
  publisher = {GitHub},
  url = {https://github.com/hanshof/sp500_constituents}
}
```

### Para Dados Fama-French:
```bibtex
@misc{french_data_library,
  author = {Kenneth R. French},
  title = {Data Library},
  year = {2025},
  publisher = {Tuck School of Business, Dartmouth College},
  url = {https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/data_library.html}
}
```

### Para a Metodologia Novy-Marx:
```bibtex
@article{novy_marx_2013,
  title = {The other side of value: The gross profitability premium},
  author = {Novy-Marx, Robert},
  journal = {Journal of Financial Economics},
  volume = {108},
  number = {1},
  pages = {1--28},
  year = {2013},
  publisher = {Elsevier}
}
```

### Para Este Projeto:
```bibtex
@software{novomarx_analysis,
  author = {André Camatta},
  title = {NovoMarxAnalysis.jl: Academic Implementation of Novy-Marx Methodology},
  year = {2025},
  publisher = {GitHub},
  url = {https://github.com/andrecamatta/pq_novy_marx}
}
```

---

## Responsabilidade e Disclaimer

- **Uso dos Dados**: Os dados são fornecidos "como estão" para fins de pesquisa e educação
- **Verificação**: Usuários devem verificar independentemente a precisão dos dados para suas aplicações específicas
- **Responsabilidade**: Nem este projeto nem as fontes de dados originais assumem responsabilidade por decisões baseadas nestes dados
- **Atualização**: Os dados podem estar desatualizados; sempre verifique fontes originais para dados mais recentes

## Transparência de Processo

### Processamento de Dados S&P 500
1. Dados baixados diretamente do repositório GitHub
2. Processamento point-in-time para evitar viés de look-ahead
3. Validação de integridade de dados com verificações cruzadas
4. Preservação de eventos históricos (falências, aquisições, etc.)

### Processamento de Dados Fama-French
1. Download automático de arquivos ZIP da Kenneth French Data Library
2. Parsing de formato CSV específico com tratamento de headers
3. Conversão de datas de formato YYYYMM para objetos Date Julia
4. Validação de intervalos e consistência de dados
5. Cache local para otimização de performance

---

**📊 Compromisso com Transparência de Dados e Reprodutibilidade de Pesquisa**