@echo off
REM ============================================================
REM  Arranca el imprimidor de etiquetas de lio (idea 5290).
REM  DOBLE CLIC a este archivo.
REM  Tiene que estar en la MISMA carpeta que imprimir-etiquetas-lio.ps1
REM
REM  Las 2 lineas COMPLUS_ fuerzan a PowerShell a usar .NET 4 (necesario
REM  para TLS 1.2 en Windows 7). Si Windows 7 no tiene .NET 4 instalado,
REM  PowerShell no va a abrir: en ese caso hay que instalar .NET 4.8.
REM ============================================================
title Imprimidor de etiquetas de lio
set COMPLUS_OnlyUseLatestCLR=1
set COMPLUS_Version=v4.0.30319
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0imprimir-etiquetas-lio.ps1"
echo.
echo El imprimidor se cerro. Mira el mensaje de arriba por si hubo un error.
pause
