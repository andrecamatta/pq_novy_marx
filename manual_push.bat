@echo off
echo === Upload Manual para GitHub ===
echo.
echo PREREQUISITO: Crie o repositorio vazio em https://github.com/andrecamatta
echo Nome do repositorio: pq_novy_marx
echo.
pause
echo.
echo Adicionando repositorio remoto...
git remote add origin https://github.com/andrecamatta/pq_novy_marx.git

echo.
echo Fazendo push do codigo...
git push -u origin main

echo.
echo === Upload completo! ===
echo.
echo Acesse: https://github.com/andrecamatta/pq_novy_marx
pause