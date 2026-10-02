@echo off
rem GV - programa de impresion (v26.12). Dejar esta ventana abierta (se puede minimizar).
rem Imprime en ESTA PC las hojas que GV le asigna en Configuracion -> Impresoras.
title GV Impresion
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0GV-Impresion.ps1" %*
echo.
echo El programa de impresion se cerro. Mientras este cerrado, en esta PC no sale ninguna hoja de GV.
pause
