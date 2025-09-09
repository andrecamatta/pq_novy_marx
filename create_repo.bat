@echo off
echo === GitHub Repository Creation Script ===
echo.
echo Iniciando autenticacao...
echo.
echo Cole seu Personal Access Token quando solicitado:
.\tools\bin\gh.exe auth login --with-token

echo.
echo Criando repositorio no GitHub...
.\tools\bin\gh.exe repo create andrecamatta/pq_novy_marx --public --source=. --remote=origin --push --description "Testing the Low Volatility Anomaly with Survivorship Bias Correction"

echo.
echo === Processo completo! ===
echo.
echo Repositorio criado em: https://github.com/andrecamatta/pq_novy_marx
pause