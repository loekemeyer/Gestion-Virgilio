@echo off
REM ============================================================
REM  Arranca el imprimidor de etiquetas de lio (idea 5290).
REM  DOBLE CLIC a este archivo.
REM  Tiene que estar en la MISMA carpeta que imprimir-etiquetas-lio.ps1
REM ============================================================
title Imprimidor de etiquetas de lio
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0imprimir-etiquetas-lio.ps1"
echo.
echo El imprimidor se cerro. Mira el mensaje de arriba por si hubo un error.
pause
