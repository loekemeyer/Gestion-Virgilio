@echo off
REM Compila "Impresion Virgilio.exe" con el csc.exe que ya viene en Windows (.NET Framework 4).
REM No necesita instalar nada ni permisos de administrador.
REM Uso: doble clic, o ejecutar desde esta carpeta.

setlocal
set CSC=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe
if not exist "%CSC%" set CSC=C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe
if not exist "%CSC%" (
  echo No se encontro csc.exe de .NET Framework 4. Instalar/activar .NET Framework 4.
  pause
  exit /b 1
)

"%CSC%" /nologo /codepage:65001 /target:winexe "/out:Impresion Virgilio.exe" ^
  /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll ^
  "src\ImpresionVirgilio.cs"

if errorlevel 1 (
  echo.
  echo FALLO la compilacion.
) else (
  echo.
  echo OK: se genero "Impresion Virgilio.exe".
  echo Copialo junto a SumatraPDF.exe para distribuir (ver README.md).
)
pause
