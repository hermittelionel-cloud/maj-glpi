@echo off
setlocal EnableExtensions

title Installation / Mise a jour GLPI Agent 1.17

set "GLPI_URL=http://gie2bbalbi.ddns.net:62354/glpi/plugins/glpiinventory/"
set "MSI_URL=https://github.com/glpi-project/glpi-agent/releases/download/1.17/GLPI-Agent-1.17-x64.msi"
set "MSI_FILE=%TEMP%\GLPI-Agent-1.17-x64.msi"
set "AGENT_BAT=C:\Program Files\GLPI-Agent\glpi-agent.bat"
set "MSI_LOG=%TEMP%\GLPI-Agent-1.17-install.log"

REM ==========================================================
REM DROITS ADMIN
REM ==========================================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Demande des droits administrateur...
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo ==========================================================
echo              MAINTENANCE GLPI AGENT
echo ==========================================================
echo.

REM ==========================================================
REM AGENT ABSENT ?
REM ==========================================================

if not exist "%AGENT_BAT%" (
    echo GLPI Agent non installe.
    goto INSTALL
)

REM ==========================================================
REM VERSION ACTUELLE
REM ==========================================================

echo Version actuelle :
call "%AGENT_BAT%" --version

echo.
echo Verification si la version 1.17 est deja installee...

"%AGENT_BAT%" --version 2>nul | findstr /C:"(1.17)" >nul

if %errorlevel%==0 (
    echo.
    echo GLPI Agent 1.17 est deja installe.
    goto CONFIGURE
)

echo.
echo Une autre version est installee.
echo Mise a jour vers 1.17...
goto INSTALL


REM ==========================================================
REM TELECHARGEMENT / INSTALLATION
REM ==========================================================

:INSTALL

echo.
echo Telechargement GLPI Agent 1.17...
echo.

if exist "%MSI_FILE%" del /q "%MSI_FILE%" >nul 2>&1

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%MSI_URL%' -OutFile '%MSI_FILE%'"

if not exist "%MSI_FILE%" (
    echo.
    echo ERREUR : le MSI n'a pas ete telecharge.
    pause
    exit /b 1
)

echo.
echo Installation / mise a jour en cours...
echo.

net stop glpi-agent >nul 2>&1

start /wait "" msiexec.exe /i "%MSI_FILE%" /qn /norestart SERVER="%GLPI_URL%" ADDLOCAL=feat_DEPLOY TASKS=Inventory,Deploy ADD_FIREWALL_EXCEPTION=1 /L*v "%MSI_LOG%"

set "RESULT=%ERRORLEVEL%"

if "%RESULT%"=="0" goto INSTALL_OK
if "%RESULT%"=="3010" goto INSTALL_OK

echo.
echo ERREUR installation MSI.
echo Code : %RESULT%
echo Log : %MSI_LOG%
echo.
pause
exit /b %RESULT%

:INSTALL_OK

echo.
echo Installation terminee.
timeout /t 5 /nobreak >nul


REM ==========================================================
REM CONFIGURATION URL
REM ==========================================================

:CONFIGURE

echo.
echo Configuration de l'URL GLPI...

reg add "HKLM\SOFTWARE\GLPI-Agent" /v server /t REG_SZ /d "%GLPI_URL%" /f >nul

echo URL configuree :
echo %GLPI_URL%


REM ==========================================================
REM SERVICE
REM ==========================================================

echo.
echo Redemarrage du service GLPI Agent...

net stop glpi-agent >nul 2>&1
timeout /t 2 /nobreak >nul
net start glpi-agent >nul 2>&1

timeout /t 5 /nobreak >nul


REM ==========================================================
REM VERIFICATION AGENT
REM ==========================================================

if not exist "%AGENT_BAT%" (
    echo.
    echo ERREUR : glpi-agent.bat introuvable.
    pause
    exit /b 1
)


REM ==========================================================
REM INVENTAIRE
REM ==========================================================

echo.
echo ==========================================================
echo LANCEMENT INVENTAIRE
echo ==========================================================
echo.

call "%AGENT_BAT%" --tasks Inventory --force


REM ==========================================================
REM DEPLOY
REM ==========================================================

echo.
echo ==========================================================
echo VERIFICATION DEPLOY
echo ==========================================================
echo.

call "%AGENT_BAT%" --tasks Deploy --force


REM ==========================================================
REM VERSION FINALE
REM ==========================================================

echo.
echo ==========================================================
echo VERSION FINALE
echo ==========================================================
echo.

call "%AGENT_BAT%" --version

echo.
echo Operation terminee.
echo.

if exist "%MSI_FILE%" del /q "%MSI_FILE%" >nul 2>&1

pause
endlocal