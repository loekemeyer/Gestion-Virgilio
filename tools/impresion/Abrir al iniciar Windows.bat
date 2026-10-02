@echo off
rem Deja un acceso directo en Inicio de Windows: el programa de impresion se abre solo (minimizado) al prender la PC.
rem Para sacarlo: borrar "GV Impresion" de la carpeta shell:startup.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Startup') + '\GV Impresion.lnk'); $s.TargetPath='%~dp0Iniciar GV-Impresion.bat'; $s.WorkingDirectory='%~dp0'; $s.WindowStyle=7; $s.Save(); Write-Host 'Listo: el programa de impresion se abre solo al iniciar Windows (minimizado).'"
pause
