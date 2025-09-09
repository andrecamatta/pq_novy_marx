@echo off
echo === Enviando codigo para GitHub ===
echo.
echo IMPORTANTE: Quando solicitado:
echo   Username: andrecamatta
echo   Password: Use seu Personal Access Token (NAO a senha da conta!)
echo.
echo Para criar um token:
echo   1. Acesse: https://github.com/settings/tokens/new
echo   2. Marque o escopo "repo"
echo   3. Gere o token e copie
echo.
pause
echo.
echo Iniciando push para GitHub...
git push -u origin main
echo.
if %ERRORLEVEL% EQU 0 (
    echo === SUCESSO! ===
    echo Repositorio disponivel em: https://github.com/andrecamatta/pq_novy_marx
) else (
    echo === ERRO no push ===
    echo Verifique suas credenciais e tente novamente
)
echo.
pause