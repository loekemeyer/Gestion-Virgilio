@echo off
rem Imprime una hoja de prueba en la impresora PREDETERMINADA de Windows, sin pasar por GV.
rem Sirve para ver si Chrome/Edge y la impresora andan en esta PC.
title GV Impresion - prueba
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0GV-Impresion.ps1" -Prueba
pause
