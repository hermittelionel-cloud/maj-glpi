@echo off
setlocal EnableExtensions EnableDelayedExpansion

title Installation / Mise a jour GLPI Agent 1.17 + Deploy 5 min

REM ==========================================================
REM CONFIGURATION
REM ==========================================================

set "TARGET_VERSION=1.17"
set "GLPI_URL=http://gie2bbalbi.ddns.net:62354/glpi/plugins/glpiinventory/"
set "MSI_URL=https://github.com/glpi-project/glpi-agent/releases/download/1.17/GLPI-Agent-1.17-x64.msi"

set "AGENT_DIR=C:\Program Files\GLPI-Agent"
set "AGENT_BAT=%AGENT_DIR%\glpi-agent.bat"
set "AGENT_CFG=%AGENT_DIR%\etc\agent.cfg"

set "MSI_FILE=%TEMP%\GLPI-Agent-1.17-x64.msi"
set "MSI_LOG=C:\Windows\Temp\GLPI-Agent-1.17-install.log"
set "UNINSTALL_LOG=C:\Windows\Temp\GLPI-Agent-uninstall.log"
set "CFG_BACKUP=C:\Windows\Temp\GLPI-Agent-agent.cfg.bak"
set "TASK_FIX_DIR=C:\ProgramData\GLPI"
set "TASK_FIX_PS1=%TASK_FIX_DIR%\Correctif_GLPI_Taches_PT4M_Auto.ps1"
set "TASK_FIX_B64=%TEMP%\Correctif_GLPI_Taches_PT4M_Auto.b64"
set "REG_VERSION_FILE=%TEMP%\GLPI-Agent-installed-version.txt"
set "FORCE_REPAIR=0"

REM ==========================================================
REM DROITS ADMINISTRATEUR
REM ==========================================================

net session >nul 2>&1
if not "%ERRORLEVEL%"=="0" (
    echo Demande des droits administrateur...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cls
echo ==========================================================
echo              MAINTENANCE GLPI AGENT
echo ==========================================================
echo.

REM ==========================================================
REM SAUVEGARDE CONFIGURATION EXISTANTE
REM ==========================================================

echo [1/8] Sauvegarde de la configuration...

if exist "%AGENT_CFG%" (
    copy /y "%AGENT_CFG%" "%CFG_BACKUP%" >nul 2>&1
    if exist "%CFG_BACKUP%" (
        echo Configuration sauvegardee :
        echo %CFG_BACKUP%
    )
) else (
    echo Aucun agent.cfg a sauvegarder.
)

echo.

REM ==========================================================
REM VERSION ACTUELLE - LECTURE REGISTRE SANS LANCER L'AGENT
REM ==========================================================

if exist "%REG_VERSION_FILE%" del /q "%REG_VERSION_FILE%" >nul 2>&1

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$roots=@('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall');" ^
  "$version='';" ^
  "foreach($root in $roots){if(Test-Path $root){foreach($k in Get-ChildItem $root -ErrorAction SilentlyContinue){$p=Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue;if($p.DisplayName -like 'GLPI Agent*' -and $p.DisplayVersion){$version=[string]$p.DisplayVersion;break}}};if($version){break}};" ^
  "if($version){Set-Content -LiteralPath '%REG_VERSION_FILE%' -Value $version -Encoding ASCII}"

set "INSTALLED_VERSION="
if exist "%REG_VERSION_FILE%" set /p "INSTALLED_VERSION="<"%REG_VERSION_FILE%"

if defined INSTALLED_VERSION (
    echo Version enregistree : !INSTALLED_VERSION!
    if /I "!INSTALLED_VERSION!"=="%TARGET_VERSION%" (
        echo GLPI Agent %TARGET_VERSION% est deja enregistre.
        echo Reparation complete forcee pour remplacer toute DLL incompatible.
        set "FORCE_REPAIR=1"
    ) else (
        echo Mise a jour de !INSTALLED_VERSION! vers %TARGET_VERSION%...
    )
) else if exist "%AGENT_DIR%" (
    echo Installation GLPI Agent presente mais version registre introuvable.
    echo Reinstallation propre vers %TARGET_VERSION%...
) else (
    echo Installation propre de la version %TARGET_VERSION%...
)

echo.

REM ==========================================================
REM TELECHARGEMENT MSI
REM ==========================================================

echo [2/8] Telechargement GLPI Agent %TARGET_VERSION%...

if exist "%MSI_FILE%" del /q "%MSI_FILE%" >nul 2>&1
if exist "%MSI_LOG%" del /q "%MSI_LOG%" >nul 2>&1

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%MSI_URL%' -OutFile '%MSI_FILE%'"

if not exist "%MSI_FILE%" (
    echo.
    echo ERREUR : le MSI n'a pas ete telecharge.
    goto ERROR_END
)

for %%F in ("%MSI_FILE%") do set "MSI_SIZE=%%~zF"
if "!MSI_SIZE!"=="0" (
    echo.
    echo ERREUR : le MSI telecharge est vide.
    goto ERROR_END
)

echo MSI telecharge : !MSI_SIZE! octets
echo.

REM ==========================================================
REM TENTATIVE D'UPGRADE NORMAL
REM ==========================================================

echo [3/8] Installation / mise a jour en cours...

net stop glpi-agent >nul 2>&1
taskkill.exe /IM glpi-agent.exe /T /F >nul 2>&1
timeout /t 2 /nobreak >nul

if "!FORCE_REPAIR!"=="1" (
    echo Arret et suppression temporaire des anciennes taches GLPI...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
      "$names=@('GLPI Deploy Check','GLPI Deploy Every 5 Minutes','GLPI Deploy At Startup','GLPI Inventory At Startup','GLPI Inventory Every 24 Hours');" ^
      "foreach($name in $names){Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue;Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue}"

    net stop glpi-agent >nul 2>&1
    sc.exe config glpi-agent start= disabled >nul 2>&1
    taskkill.exe /IM glpi-agent.exe /T /F >nul 2>&1

    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
      "$prefix='%AGENT_DIR%\';" ^
      "Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {[string]$_.ExecutablePath -like ($prefix+'*')} | ForEach-Object {Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue}"

    timeout /t 3 /nobreak >nul

    echo Desinstallation silencieuse de la copie 1.17 endommagee...
    if exist "%UNINSTALL_LOG%" del /q "%UNINSTALL_LOG%" >nul 2>&1
    msiexec.exe /x "%MSI_FILE%" /qn /norestart /L*v "%UNINSTALL_LOG%"
    set "REPAIR_UNINSTALL_RESULT=!ERRORLEVEL!"
    if "!REPAIR_UNINSTALL_RESULT!"=="3010" set "REPAIR_UNINSTALL_RESULT=0"
    if "!REPAIR_UNINSTALL_RESULT!"=="1605" set "REPAIR_UNINSTALL_RESULT=0"

    net stop glpi-agent >nul 2>&1
    taskkill.exe /IM glpi-agent.exe /T /F >nul 2>&1
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
      "$prefix='%AGENT_DIR%\';" ^
      "Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {[string]$_.ExecutablePath -like ($prefix+'*')} | ForEach-Object {Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue}"
    sc.exe delete glpi-agent >nul 2>&1
    timeout /t 3 /nobreak >nul

    echo Mise a l'ecart du dossier contenant les DLL incompatibles...
    set "BROKEN_DIR=C:\Program Files\GLPI-Agent.broken"
    if exist "!BROKEN_DIR!" set "BROKEN_DIR=C:\Program Files\GLPI-Agent.broken-%RANDOM%"

    if exist "%AGENT_DIR%" (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
          "$src='%AGENT_DIR%';$dst=[IO.Path]::GetFileName('!BROKEN_DIR!');" ^
          "for($i=1;$i -le 5;$i++){try{if(Test-Path -LiteralPath $src){Rename-Item -LiteralPath $src -NewName $dst -Force -ErrorAction Stop};exit 0}catch{Start-Sleep -Seconds 2}};exit 13"
    )

    if exist "%AGENT_DIR%" (
        echo ERREUR : impossible de liberer l'ancien dossier GLPI-Agent.
        goto ERROR_END
    )

    echo Reinstallation propre GLPI Agent %TARGET_VERSION%...
    if "!REPAIR_UNINSTALL_RESULT!"=="0" (
        msiexec.exe /i "%MSI_FILE%" /qn /norestart SERVER="%GLPI_URL%" ADDLOCAL=feat_DEPLOY TASKS=Inventory,Deploy ADD_FIREWALL_EXCEPTION=1 /L*v "%MSI_LOG%"
    ) else (
        echo Desinstallation retournee avec le code !REPAIR_UNINSTALL_RESULT!.
        echo Tentative de reparation MSI forcee apres liberation du dossier...
        msiexec.exe /i "%MSI_FILE%" /qn /norestart REINSTALL=ALL REINSTALLMODE=amus SERVER="%GLPI_URL%" ADDLOCAL=feat_DEPLOY TASKS=Inventory,Deploy ADD_FIREWALL_EXCEPTION=1 /L*v "%MSI_LOG%"
    )
) else (
    msiexec.exe /i "%MSI_FILE%" /qn /norestart SERVER="%GLPI_URL%" ADDLOCAL=feat_DEPLOY TASKS=Inventory,Deploy ADD_FIREWALL_EXCEPTION=1 /L*v "%MSI_LOG%"
)
set "INSTALL_RESULT=!ERRORLEVEL!"

if "!INSTALL_RESULT!"=="0" goto INSTALL_OK
if "!INSTALL_RESULT!"=="3010" goto INSTALL_OK

if not "!INSTALL_RESULT!"=="1603" (
    echo.
    echo ERREUR installation MSI.
    echo Code : !INSTALL_RESULT!
    echo Log  : %MSI_LOG%
    goto ERROR_END
)

REM ==========================================================
REM FALLBACK ERREUR 1603
REM ==========================================================

echo.
echo ==========================================================
echo ERREUR 1603 DETECTEE
echo ==========================================================
echo.
echo L'upgrade direct a echoue.
echo Passage en mode reparation / installation propre.
echo.

REM ==========================================================
REM TENTE D'ABORD UNE DESINSTALLATION MSI SI WINDOWS LA CONNAIT
REM ==========================================================

echo [4/8] Recherche d'une installation MSI enregistree...

set "PRODUCT_CODE="
set "PRODUCT_CODE_FILE=%TEMP%\GLPI-Agent-productcode.txt"

if exist "%PRODUCT_CODE_FILE%" del /q "%PRODUCT_CODE_FILE%" >nul 2>&1

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$roots=@('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall');" ^
  "$guid=$null;" ^
  "foreach($root in $roots){" ^
    "if(Test-Path $root){" ^
      "foreach($k in Get-ChildItem -Path $root -ErrorAction SilentlyContinue){" ^
        "$p=Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue;" ^
        "if($p.DisplayName -like 'GLPI Agent*'){" ^
          "$candidate=[string]$k.PSChildName;" ^
          "if($candidate -match '^\{[0-9A-Fa-f-]{36}\}$'){$guid=$candidate;break}" ^
          "$m=[regex]::Match([string]$p.UninstallString,'\{[0-9A-Fa-f-]{36}\}');" ^
          "if($m.Success){$guid=$m.Value;break}" ^
        "}" ^
      "}" ^
    "}" ^
    "if($guid){break}" ^
  "};" ^
  "if($guid){Set-Content -LiteralPath '%PRODUCT_CODE_FILE%' -Value $guid -Encoding ASCII; exit 0}else{exit 12}"

if exist "%PRODUCT_CODE_FILE%" (
    set /p "PRODUCT_CODE="<"%PRODUCT_CODE_FILE%"
)

if defined PRODUCT_CODE (
    echo Installation MSI trouvee : !PRODUCT_CODE!
    echo Tentative de desinstallation silencieuse...

    if exist "%UNINSTALL_LOG%" del /q "%UNINSTALL_LOG%" >nul 2>&1

    net stop glpi-agent >nul 2>&1
    timeout /t 2 /nobreak >nul

    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
      "$a=@('/x','!PRODUCT_CODE!','/qn','/norestart','/L*v','%UNINSTALL_LOG%');" ^
      "$p=Start-Process -FilePath 'msiexec.exe' -ArgumentList $a -Wait -PassThru;" ^
      "exit $p.ExitCode"

    set "UNINSTALL_RESULT=!ERRORLEVEL!"
    if "!UNINSTALL_RESULT!"=="3010" set "UNINSTALL_RESULT=0"

    if "!UNINSTALL_RESULT!"=="0" (
        echo Ancienne version desinstallee proprement.
        goto CLEAN_FOLDER_AND_INSTALL
    )

    if "!UNINSTALL_RESULT!"=="1605" (
        echo Windows Installer ne considere plus ce produit comme installe.
        echo Passage au nettoyage de l'installation orpheline.
        goto ORPHAN_CLEANUP
    )

    if "!UNINSTALL_RESULT!"=="1612" (
        echo Source MSI ancienne introuvable.
        echo Passage au nettoyage de l'installation orpheline.
        goto ORPHAN_CLEANUP
    )

    echo.
    echo Desinstallation MSI impossible. Code : !UNINSTALL_RESULT!
    echo Passage au nettoyage de l'installation orpheline.
    goto ORPHAN_CLEANUP
) else (
    echo Aucun GLPI Agent MSI enregistre dans Windows.
    echo L'installation actuelle est probablement orpheline.
    goto ORPHAN_CLEANUP
)

REM ==========================================================
REM NETTOYAGE INSTALLATION ORPHELINE
REM ==========================================================

:ORPHAN_CLEANUP

echo.
echo [5/8] Nettoyage de l'ancienne installation orpheline...

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "Stop-Service glpi-agent -Force -ErrorAction SilentlyContinue"

sc.exe delete glpi-agent >nul 2>&1

timeout /t 2 /nobreak >nul

if exist "%AGENT_DIR%" (
    set "OLD_DIR=C:\Program Files\GLPI-Agent.old"
    if exist "!OLD_DIR!" (
        set "OLD_DIR=C:\Program Files\GLPI-Agent.old-%RANDOM%"
    )

    echo Renommage de l'ancien dossier en :
    echo !OLD_DIR!

    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
      "if(Test-Path -LiteralPath '%AGENT_DIR%'){Rename-Item -LiteralPath '%AGENT_DIR%' -NewName ([IO.Path]::GetFileName('!OLD_DIR!')) -Force}"

    if exist "%AGENT_DIR%" (
        echo.
        echo ERREUR : impossible de renommer l'ancien dossier GLPI-Agent.
        goto ERROR_END
    )
)

goto FRESH_INSTALL

REM ==========================================================
REM APRES DESINSTALLATION MSI PROPRE
REM ==========================================================

:CLEAN_FOLDER_AND_INSTALL

echo.
echo Nettoyage des restes de l'ancienne installation...

if exist "%AGENT_DIR%" (
    set "OLD_DIR=C:\Program Files\GLPI-Agent.old"
    if exist "!OLD_DIR!" (
        set "OLD_DIR=C:\Program Files\GLPI-Agent.old-%RANDOM%"
    )

    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
      "if(Test-Path -LiteralPath '%AGENT_DIR%'){Rename-Item -LiteralPath '%AGENT_DIR%' -NewName ([IO.Path]::GetFileName('!OLD_DIR!')) -Force}"
)

REM ==========================================================
REM INSTALLATION PROPRE 1.17
REM ==========================================================

:FRESH_INSTALL

echo.
echo [6/8] Installation propre GLPI Agent %TARGET_VERSION%...

if exist "%MSI_LOG%" del /q "%MSI_LOG%" >nul 2>&1

msiexec.exe /i "%MSI_FILE%" /qn /norestart SERVER="%GLPI_URL%" ADDLOCAL=feat_DEPLOY TASKS=Inventory,Deploy ADD_FIREWALL_EXCEPTION=1 /L*v "%MSI_LOG%"
set "INSTALL_RESULT=!ERRORLEVEL!"

if "!INSTALL_RESULT!"=="0" goto INSTALL_OK
if "!INSTALL_RESULT!"=="3010" goto INSTALL_OK

echo.
echo ERREUR installation propre GLPI Agent.
echo Code : !INSTALL_RESULT!
echo Log  : %MSI_LOG%
goto ERROR_END

REM ==========================================================
REM INSTALLATION OK
REM ==========================================================

:INSTALL_OK

echo.
echo [7/8] Installation terminee.
timeout /t 5 /nobreak >nul

REM Restaure agent.cfg seulement si la nouvelle installation n'en a pas cree.
if exist "%CFG_BACKUP%" (
    if not exist "%AGENT_CFG%" (
        if not exist "%AGENT_DIR%\etc" mkdir "%AGENT_DIR%\etc" >nul 2>&1
        copy /y "%CFG_BACKUP%" "%AGENT_CFG%" >nul 2>&1
        echo Ancienne configuration agent.cfg restauree.
    )
)

REM ==========================================================
REM CONFIGURATION SERVEUR + SERVICE
REM ==========================================================

:CONFIGURE_AND_INVENTORY

echo.
echo Configuration de l'URL GLPI :
echo %GLPI_URL%

reg add "HKLM\SOFTWARE\GLPI-Agent" /v server /t REG_SZ /d "%GLPI_URL%" /f >nul 2>&1

echo.
echo Redemarrage du service GLPI Agent...

net stop glpi-agent >nul 2>&1
timeout /t 2 /nobreak >nul
net start glpi-agent >nul 2>&1
timeout /t 5 /nobreak >nul

if not exist "%AGENT_BAT%" (
    echo.
    echo ERREUR : glpi-agent.bat introuvable apres installation.
    goto ERROR_END
)

echo.
echo ==========================================================
echo VERSION FINALE
echo ==========================================================
call "%AGENT_BAT%" --version
echo.

"%AGENT_BAT%" --version 2>nul | findstr /C:"(%TARGET_VERSION%)" >nul
if not "!ERRORLEVEL!"=="0" (
    echo ERREUR : la version %TARGET_VERSION% n'est pas detectee.
    goto ERROR_END
)

REM ==========================================================
REM INVENTAIRE FORCE A LA FIN
REM ==========================================================

echo.
echo [8/8] INVENTAIRE FORCE
echo ==========================================================
echo.

call "%AGENT_BAT%" --tasks Inventory --force
set "INV_RESULT=!ERRORLEVEL!"

echo.
echo Code retour inventaire : !INV_RESULT!
echo.

if not "!INV_RESULT!"=="0" (
    echo ATTENTION : l'agent est installe mais l'inventaire force a retourne !INV_RESULT!.
)

REM ==========================================================
REM TACHES PLANIFIEES + GARDE ANTI-BLOCAGE PT4M
REM ==========================================================

echo.
echo Creation / correction des taches planifiees GLPI...
echo Deploy : demarrage + toutes les 5 minutes
echo Inventory : demarrage + toutes les 24 heures
echo Limite tache Deploy : PT4M
echo Kill de l'arbre Deploy par le garde apres 3 minutes
echo.

if not exist "%TASK_FIX_DIR%" (
    mkdir "%TASK_FIX_DIR%" >nul 2>&1
)

REM BEGIN EMBEDDED TASK FIX BASE64
    echo 77u/JEVycm9yQWN0aW9uUHJlZmVyZW5jZSA9ICJTdG9wIgoKJEJhc2VEaXIgPSAiQzpcUHJvZ3JhbURhdGFcR0xQSSIKJExvZ0RpciAgPSAiQzpcV2luZG93c1xUZW1wIgokQWdlbnRCYXQgPSAiQzpcUHJvZ3JhbSBGaWxlc1xHTFBJLUFnZW50XGdscGktYWdlbnQuYmF0IgoKTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtRm9yY2UgLVBhdGggJEJhc2VEaXIgfCBPdXQtTnVsbAoKZnVuY3Rpb24gV3JpdGUtR3VhcmRTY3JpcHQgewogICAgcGFyYW0oCiAgICAgICAgW3N0cmluZ10kUGF0aCwKICAgICAgICBbVmFsaWRhdGVTZXQoIkRlcGxveSIsIkludmVudG9yeSIpXQogICAgICAgIFtzdHJpbmddJFRhc2ssCiAgICAgICAgW2ludF0kVGltZW91dFNlY29uZHMsCiAgICAgICAgW3N0cmluZ10kTG9nRmlsZQogICAgKQoKICAgICRjb250ZW50ID0gQCIKYCRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAiU3RvcCIKYCRBZ2VudEJhdCA9ICIkQWdlbnRCYXQiCmAkTG9nRmlsZSA9ICIkTG9nRmlsZSIKYCRUaW1lb3V0U2Vjb25kcyA9ICRUaW1lb3V0U2Vjb25kcwpgJFRhc2sgPSAiJFRhc2siCgpmdW5jdGlvbiBMb2coW3N0cmluZ11gJE1lc3NhZ2UpIHsKICAgIEFkZC1Db250ZW50IC1QYXRoIGAkTG9nRmlsZSAtVmFsdWUgKCJbezB9XSB7MX0iIC1mIChHZXQtRGF0ZSAtRm9ybWF0ICJ5eXl5LU1NLWRkIEhIOm1tOnNzIiksIGAkTWVzc2FnZSkgLUVuY29kaW5nIFVURjgKfQoKZnVuY3Rpb24gVXBkYXRlLURJNEludmVudG9yeU1hcmtlciB7CiAgICAjIENlIG1hcnF1ZXVyIGVzdCBsdSBwYXIgbCdpbnZlbnRhaXJlIGxvZ2ljaWVsIG5hdGlmIGRlIEdMUEkgQWdlbnQuCiAgICAjIElsIG5lIGNvbnRpZW50IGF1Y3VuIGpldG9uIG5pIHNlY3JldC4KICAgIGAkcmVxdWlyZWRUYXNrcyA9IEAoCiAgICAgICAgIkdMUEkgRGVwbG95IENoZWNrIiwKICAgICAgICAiR0xQSSBEZXBsb3kgQXQgU3RhcnR1cCIsCiAgICAgICAgIkdMUEkgSW52ZW50b3J5IEF0IFN0YXJ0dXAiLAogICAgICAgICJHTFBJIEludmVudG9yeSBFdmVyeSAyNCBIb3VycyIKICAgICkKICAgIGAkbWlzc2luZyA9IEAoKQogICAgZm9yZWFjaCAoYCR0YXNrTmFtZSBpbiBgJHJlcXVpcmVkVGFza3MpIHsKICAgICAgICBpZiAoLW5vdCAoR2V0LVNjaGVkdWxlZFRhc2sgLVRhc2tOYW1lIGAkdGFza05hbWUgLUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUpKSB7CiAgICAgICAgICAgIGAkbWlzc2luZyArPSBgJHRhc2tOYW1lCiAgICAgICAgfQogICAgfQoKICAgIGAkZGVwbG95WG1sID0gIiIKICAgIGAkZGVwbG95U3RhcnR1cFhtbCA9ICIiCiAgICBgJGludmVudG9yeVN0YXJ0dXBYbWwgPSAiIgogICAgYCRpbnZlbnRvcnlEYWlseVhtbCA9ICIiCiAgICB0cnkgeyBgJGRlcGxveVhtbCA9IEV4cG9ydC1TY2hlZHVsZWRUYXNrIC1UYXNrTmFtZSAiR0xQSSBEZXBsb3kgQ2hlY2siIH0gY2F0Y2gge30KICAgIHRyeSB7IGAkZGVwbG95U3RhcnR1cFhtbCA9IEV4cG9ydC1TY2hlZHVsZWRUYXNrIC1UYXNrTmFtZSAiR0xQSSBEZXBsb3kgQXQgU3RhcnR1cCIgfSBjYXRjaCB7fQogICAgdHJ5IHsgYCRpbnZlbnRvcnlTdGFydHVwWG1sID0gRXhwb3J0LVNjaGVkdWxlZFRhc2sgLVRhc2tOYW1lICJHTFBJIEludmVudG9yeSBBdCBTdGFydHVwIiB9IGNhdGNoIHt9CiAgICB0cnkgeyBgJGludmVudG9yeURhaWx5WG1sID0gRXhwb3J0LVNjaGVkdWxlZFRhc2sgLVRhc2tOYW1lICJHTFBJIEludmVudG9yeSBFdmVyeSAyNCBIb3VycyIgfSBjYXRjaCB7fQoKICAgIGAkZGVwbG95T2sgPSAoYCRkZXBsb3lYbWwgLW1hdGNoICc8RXhlY3V0aW9uVGltZUxpbWl0PlBUNE08L0V4ZWN1dGlvblRpbWVMaW1pdD4nKSAtYW5kCiAgICAgICAgKGAkZGVwbG95WG1sIC1tYXRjaCAnPEludGVydmFsPlBUNU08L0ludGVydmFsPicpIC1hbmQKICAgICAgICAoYCRkZXBsb3lYbWwgLW1hdGNoICdHTFBJLURlcGxveS1HdWFyZFwucHMxJykgLWFuZAogICAgICAgIChgJGRlcGxveVN0YXJ0dXBYbWwgLW1hdGNoICc8RXhlY3V0aW9uVGltZUxpbWl0PlBUNE08L0V4ZWN1dGlvblRpbWVMaW1pdD4nKSAtYW5kCiAgICAgICAgKGAkZGVwbG95U3RhcnR1cFhtbCAtbWF0Y2ggJ0dMUEktRGVwbG95LUd1YXJkXC5wczEnKQogICAgYCRpbnZlbnRvcnlPayA9IChgJGludmVudG9yeVN0YXJ0dXBYbWwgLW1hdGNoICdHTFBJLUludmVudG9yeS1HdWFyZFwucHMxJykgLWFuZAogICAgICAgIChgJGludmVudG9yeURhaWx5WG1sIC1tYXRjaCAnR0xQSS1J
    echo bnZlbnRvcnktR3VhcmRcLnBzMScpCgogICAgYCRkZXBsb3lHdWFyZFBhdGggPSAiQzpcUHJvZ3JhbURhdGFcR0xQSVxHTFBJLURlcGxveS1HdWFyZC5wczEiCiAgICBgJGd1YXJkVGV4dCA9IGlmIChUZXN0LVBhdGggYCRkZXBsb3lHdWFyZFBhdGgpIHsgR2V0LUNvbnRlbnQgLUxpdGVyYWxQYXRoIGAkZGVwbG95R3VhcmRQYXRoIC1SYXcgfSBlbHNlIHsgIiIgfQogICAgYCRraWxsNE9rID0gKGAkZ3VhcmRUZXh0IC1tYXRjaCAnXGAkVGltZW91dFNlY29uZHNccyo9XHMqMTgwJykgLWFuZAogICAgICAgIChgJGd1YXJkVGV4dCAtbWF0Y2ggJ3Rhc2traWxsXC5leGVccysvUElEXHMrXGAkcFwuSWRccysvVFxzKy9GJykKCiAgICBgJHN0YXR1cyA9IGlmIChgJG1pc3NpbmcuQ291bnQgLWVxIDAgLWFuZCBgJGRlcGxveU9rIC1hbmQgYCRpbnZlbnRvcnlPayAtYW5kIGAka2lsbDRPaykgeyAiT0siIH0gZWxzZSB7ICJLTyIgfQogICAgYCRkZXRhaWxzID0gIkQ9ezB9O0k9ezF9OzQ9ezJ9O01pc3Npbmc9ezN9O0NoZWNrZWQ9ezR9IiAtZgogICAgICAgIChbaW50XWAkZGVwbG95T2spLCAoW2ludF1gJGludmVudG9yeU9rKSwgKFtpbnRdYCRraWxsNE9rKSwgKGAkbWlzc2luZyAtam9pbiAnLCcpLCAoR2V0LURhdGUgLUZvcm1hdCAieXl5eS1NTS1kZCBISDptbTpzcyIpCgogICAgYCRtYXJrZXIgPSAiSEtMTTpcU09GVFdBUkVcTWljcm9zb2Z0XFdpbmRvd3NcQ3VycmVudFZlcnNpb25cVW5pbnN0YWxsXEJhbGJpR0xQSVRhc2tzREk0IgogICAgTmV3LUl0ZW0gLVBhdGggYCRtYXJrZXIgLUZvcmNlIHwgT3V0LU51bGwKICAgIE5ldy1JdGVtUHJvcGVydHkgLVBhdGggYCRtYXJrZXIgLU5hbWUgIkRpc3BsYXlOYW1lIiAtVmFsdWUgIkJhbGJpIEdMUEkgVGFza3MgRC5JLjQiIC1Qcm9wZXJ0eVR5cGUgU3RyaW5nIC1Gb3JjZSB8IE91dC1OdWxsCiAgICBOZXctSXRlbVByb3BlcnR5IC1QYXRoIGAkbWFya2VyIC1OYW1lICJEaXNwbGF5VmVyc2lvbiIgLVZhbHVlIGAkc3RhdHVzIC1Qcm9wZXJ0eVR5cGUgU3RyaW5nIC1Gb3JjZSB8IE91dC1OdWxsCiAgICBOZXctSXRlbVByb3BlcnR5IC1QYXRoIGAkbWFya2VyIC1OYW1lICJQdWJsaXNoZXIiIC1WYWx1ZSAiR3JvdXBlIEJhbGJpIiAtUHJvcGVydHlUeXBlIFN0cmluZyAtRm9yY2UgfCBPdXQtTnVsbAogICAgTmV3LUl0ZW1Qcm9wZXJ0eSAtUGF0aCBgJG1hcmtlciAtTmFtZSAiQ29tbWVudHMiIC1WYWx1ZSBgJGRldGFpbHMgLVByb3BlcnR5VHlwZSBTdHJpbmcgLUZvcmNlIHwgT3V0LU51bGwKICAgIE5ldy1JdGVtUHJvcGVydHkgLVBhdGggYCRtYXJrZXIgLU5hbWUgIkluc3RhbGxEYXRlIiAtVmFsdWUgKEdldC1EYXRlIC1Gb3JtYXQgInl5eXlNTWRkIikgLVByb3BlcnR5VHlwZSBTdHJpbmcgLUZvcmNlIHwgT3V0LU51bGwKICAgIE5ldy1JdGVtUHJvcGVydHkgLVBhdGggYCRtYXJrZXIgLU5hbWUgIk5vTW9kaWZ5IiAtVmFsdWUgMSAtUHJvcGVydHlUeXBlIERXb3JkIC1Gb3JjZSB8IE91dC1OdWxsCiAgICBOZXctSXRlbVByb3BlcnR5IC1QYXRoIGAkbWFya2VyIC1OYW1lICJOb1JlcGFpciIgLVZhbHVlIDEgLVByb3BlcnR5VHlwZSBEV29yZCAtRm9yY2UgfCBPdXQtTnVsbAogICAgTG9nICJNYXJxdWV1ciBELkkuNCA9IGAkc3RhdHVzIChgJGRldGFpbHMpIgp9Cgp0cnkgewogICAgaWYgKC1ub3QgKFRlc3QtUGF0aCBgJEFnZW50QmF0KSkgewogICAgICAgIExvZyAiRVJSRVVSIDogR0xQSSBBZ2VudCBpbnRyb3V2YWJsZSA6IGAkQWdlbnRCYXQiCiAgICAgICAgZXhpdCAxMAogICAgfQoKICAgIExvZyAiRGVidXQgYCRUYXNrIgoKICAgICMgQXZhbnQgQ0hBUVVFIGludmVudGFpcmUsIGNvbnRyw7RsZXIgbGVzIHTDomNoZXMgZXQgcmVuZHJlIGxlIHLDqXN1bHRhdAogICAgIyB2aXNpYmxlIGRhbnMgbCdpbnZlbnRhaXJlIGxvZ2ljaWVsIEdMUEkuCiAgICBpZiAoYCRUYXNrIC1lcSAiSW52ZW50b3J5IikgewogICAgICAgIFVwZGF0ZS1ESTRJbnZlbnRvcnlNYXJrZXIKICAgIH0KCiAgICAjIGNtZC5leGUgZXN0IGxhbmPDqSBjb21tZSBwcm9jZXNzdXMgcGFyZW50IGFmaW4gcXVlIHRhc2traWxsIC9UIHB1aXNzZQogICAgIyB0ZXJtaW5lciBhdXNzaSBsZXMgw6l2ZW50dWVscyBwcm9jZXNzdXMgZW5mYW50cyBkdSBHTFBJIEFnZW50LgogICAgYCRhcmdzID0gIi9jIGAiYCJgJEFnZW50QmF0YCIgLS10YXNrcyBgJFRhc2sgLS1mb3JjZWAiIgogICAgYCRwID0gU3RhcnQtUHJvY2VzcyAtRmlsZVBhdGggImNtZC5leGUiIC1B
    echo cmd1bWVudExpc3QgYCRhcmdzIC1QYXNzVGhydSAtV2luZG93U3R5bGUgSGlkZGVuCgogICAgaWYgKC1ub3QgYCRwLldhaXRGb3JFeGl0KGAkVGltZW91dFNlY29uZHMgKiAxMDAwKSkgewogICAgICAgIExvZyAiVElNRU9VVCA6IGAkVGFzayBkZXBhc3NlIGAkVGltZW91dFNlY29uZHMgc2Vjb25kZXMuIEFycmV0IGRlIGwnYXJicmUgZGUgcHJvY2Vzc3VzIFBJRCBgJChgJHAuSWQpLiIKICAgICAgICAmIHRhc2traWxsLmV4ZSAvUElEIGAkcC5JZCAvVCAvRiB8IE91dC1OdWxsCiAgICAgICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgMgogICAgICAgIGV4aXQgMTI0CiAgICB9CgogICAgYCRjb2RlID0gYCRwLkV4aXRDb2RlCiAgICBMb2cgIkZpbiBgJFRhc2sgLSBjb2RlIGAkY29kZSIKICAgIGV4aXQgYCRjb2RlCn0KY2F0Y2ggewogICAgTG9nICJFUlJFVVIgYCRUYXNrIDogYCQoYCRfLkV4Y2VwdGlvbi5NZXNzYWdlKSIKICAgIGV4aXQgOTkKfQoiQAogICAgU2V0LUNvbnRlbnQgLVBhdGggJFBhdGggLVZhbHVlICRjb250ZW50IC1FbmNvZGluZyBVVEY4Cn0KCiREZXBsb3lHdWFyZCA9IEpvaW4tUGF0aCAkQmFzZURpciAiR0xQSS1EZXBsb3ktR3VhcmQucHMxIgokSW52ZW50b3J5R3VhcmQgPSBKb2luLVBhdGggJEJhc2VEaXIgIkdMUEktSW52ZW50b3J5LUd1YXJkLnBzMSIKCiMgRGVwbG95IDogb24gbmUgbGFpc3NlIGphbWFpcyB1bmUgZXjDqWN1dGlvbiBibG9xdcOpZSBwbHVzIGRlIDMgbWludXRlcy4KV3JpdGUtR3VhcmRTY3JpcHQgYAogICAgLVBhdGggJERlcGxveUd1YXJkIGAKICAgIC1UYXNrICJEZXBsb3kiIGAKICAgIC1UaW1lb3V0U2Vjb25kcyAxODAgYAogICAgLUxvZ0ZpbGUgKEpvaW4tUGF0aCAkTG9nRGlyICJHTFBJLURlcGxveS1HdWFyZC5sb2ciKQoKIyBJbnZlbnRvcnkgOiBkw6lsYWkgcGx1cyBsYXJnZSBjYXIgdW4gaW52ZW50YWlyZSBwZXV0IMOqdHJlIHBsdXMgbG9uZy4KV3JpdGUtR3VhcmRTY3JpcHQgYAogICAgLVBhdGggJEludmVudG9yeUd1YXJkIGAKICAgIC1UYXNrICJJbnZlbnRvcnkiIGAKICAgIC1UaW1lb3V0U2Vjb25kcyA5MDAgYAogICAgLUxvZ0ZpbGUgKEpvaW4tUGF0aCAkTG9nRGlyICJHTFBJLUludmVudG9yeS1HdWFyZC5sb2ciKQoKJERlcGxveUFjdGlvbiA9IE5ldy1TY2hlZHVsZWRUYXNrQWN0aW9uIGAKICAgIC1FeGVjdXRlICJwb3dlcnNoZWxsLmV4ZSIgYAogICAgLUFyZ3VtZW50ICItTm9Qcm9maWxlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1GaWxlIGAiJERlcGxveUd1YXJkYCIiCgokSW52ZW50b3J5QWN0aW9uID0gTmV3LVNjaGVkdWxlZFRhc2tBY3Rpb24gYAogICAgLUV4ZWN1dGUgInBvd2Vyc2hlbGwuZXhlIiBgCiAgICAtQXJndW1lbnQgIi1Ob1Byb2ZpbGUgLUV4ZWN1dGlvblBvbGljeSBCeXBhc3MgLUZpbGUgYCIkSW52ZW50b3J5R3VhcmRgIiIKCiREZXBsb3lTZXR0aW5ncyA9IE5ldy1TY2hlZHVsZWRUYXNrU2V0dGluZ3NTZXQgYAogICAgLVN0YXJ0V2hlbkF2YWlsYWJsZSBgCiAgICAtRXhlY3V0aW9uVGltZUxpbWl0IChOZXctVGltZVNwYW4gLU1pbnV0ZXMgNCkgYAogICAgLU11bHRpcGxlSW5zdGFuY2VzIElnbm9yZU5ldwoKJEludmVudG9yeVNldHRpbmdzID0gTmV3LVNjaGVkdWxlZFRhc2tTZXR0aW5nc1NldCBgCiAgICAtU3RhcnRXaGVuQXZhaWxhYmxlIGAKICAgIC1FeGVjdXRpb25UaW1lTGltaXQgKE5ldy1UaW1lU3BhbiAtTWludXRlcyAxNikgYAogICAgLU11bHRpcGxlSW5zdGFuY2VzIElnbm9yZU5ldwoKIyBOZXR0b3lhZ2UgZGVzIGFuY2llbnMgbm9tcyB2dXMgc3VyIGxlIHBhcmMuCiMgTmV0dG95YWdlIHVuaXF1ZW1lbnQgZGVzIGFuY2llbnMgbm9tcyBhbHRlcm5hdGlmcy4KIyBJTVBPUlRBTlQgOiBvbiBuZSBzdXBwcmltZSBwbHVzICJHTFBJIERlcGxveSBDaGVjayIuCiMgQydlc3QgcHLDqWNpc8OpbWVudCBjZXR0ZSB0w6JjaGUgaGlzdG9yaXF1ZSBxdWUgbCdvbiBjb3JyaWdlIGVuIHBsYWNlLgokT2xkVGFza05hbWVzID0gQCgKICAgICJHTFBJIERlcGxveSBFdmVyeSA1IE1pbnV0ZXMiLAogICAgIkdMUEkgRGVwbG95IEF0IFN0YXJ0dXAiLAogICAgIkdMUEkgSW52ZW50b3J5IEF0IFN0YXJ0dXAiLAogICAgIkdMUEkgSW52ZW50b3J5IEV2ZXJ5IDI0IEhvdXJzIgopCgpmb3JlYWNoICgkbmFtZSBpbiAkT2xkVGFza05hbWVzKSB7CiAgICB0cnkgeyBTdG9wLVNjaGVkdWxlZFRhc2sgLVRhc2tOYW1lICRuYW1lIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIH0gY2F0
    echo Y2gge30KICAgIHRyeSB7IFVucmVnaXN0ZXItU2NoZWR1bGVkVGFzayAtVGFza05hbWUgJG5hbWUgLUNvbmZpcm06JGZhbHNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlIH0gY2F0Y2gge30KfQoKIyBERVBMT1kgQVUgREVNQVJSQUdFCiREZXBsb3lTdGFydHVwVHJpZ2dlciA9IE5ldy1TY2hlZHVsZWRUYXNrVHJpZ2dlciAtQXRTdGFydHVwClJlZ2lzdGVyLVNjaGVkdWxlZFRhc2sgYAogICAgLVRhc2tOYW1lICJHTFBJIERlcGxveSBBdCBTdGFydHVwIiBgCiAgICAtQWN0aW9uICREZXBsb3lBY3Rpb24gYAogICAgLVRyaWdnZXIgJERlcGxveVN0YXJ0dXBUcmlnZ2VyIGAKICAgIC1TZXR0aW5ncyAkRGVwbG95U2V0dGluZ3MgYAogICAgLVVzZXIgIlNZU1RFTSIgYAogICAgLVJ1bkxldmVsIEhpZ2hlc3QgYAogICAgLUZvcmNlIHwgT3V0LU51bGwKCiMgREVQTE9ZIFRPVVRFUyBMRVMgNSBNSU5VVEVTCiMgT24gcsOpdXRpbGlzZSBsZSBub20gaGlzdG9yaXF1ZSBkdSBwYXJjIDogIkdMUEkgRGVwbG95IENoZWNrIi4KJERlcGxveTVNaW5UcmlnZ2VyID0gTmV3LVNjaGVkdWxlZFRhc2tUcmlnZ2VyIGAKICAgIC1PbmNlIGAKICAgIC1BdCAoR2V0LURhdGUpLkFkZE1pbnV0ZXMoMSkgYAogICAgLVJlcGV0aXRpb25JbnRlcnZhbCAoTmV3LVRpbWVTcGFuIC1NaW51dGVzIDUpCgpSZWdpc3Rlci1TY2hlZHVsZWRUYXNrIGAKICAgIC1UYXNrTmFtZSAiR0xQSSBEZXBsb3kgQ2hlY2siIGAKICAgIC1BY3Rpb24gJERlcGxveUFjdGlvbiBgCiAgICAtVHJpZ2dlciAkRGVwbG95NU1pblRyaWdnZXIgYAogICAgLVNldHRpbmdzICREZXBsb3lTZXR0aW5ncyBgCiAgICAtVXNlciAiU1lTVEVNIiBgCiAgICAtUnVuTGV2ZWwgSGlnaGVzdCBgCiAgICAtRm9yY2UgfCBPdXQtTnVsbAoKIyBDT1JSRUNUSU9OIEVYUExJQ0lURSBEVSBQQVJBTcOIVFJFIFFVSSBSRVNUQUlUIMOAIFBUNzJIIFNVUiBDRVJUQUlOUyBQT1NURVMuCiMgQ2V0dGUgY29tbWFuZGUgZm9yY2UgcsOpZWxsZW1lbnQgRXhlY3V0aW9uVGltZUxpbWl0IMOgIDQgbWludXRlcyAoPSBQVDRNKS4KJFRhc2sgPSBHZXQtU2NoZWR1bGVkVGFzayAtVGFza05hbWUgIkdMUEkgRGVwbG95IENoZWNrIgokRXhhY3REZXBsb3lTZXR0aW5ncyA9IE5ldy1TY2hlZHVsZWRUYXNrU2V0dGluZ3NTZXQgYAogICAgLUV4ZWN1dGlvblRpbWVMaW1pdCAoTmV3LVRpbWVTcGFuIC1NaW51dGVzIDQpIGAKICAgIC1NdWx0aXBsZUluc3RhbmNlcyBJZ25vcmVOZXcgYAogICAgLVN0YXJ0V2hlbkF2YWlsYWJsZQoKU2V0LVNjaGVkdWxlZFRhc2sgYAogICAgLVRhc2tOYW1lICJHTFBJIERlcGxveSBDaGVjayIgYAogICAgLVNldHRpbmdzICRFeGFjdERlcGxveVNldHRpbmdzIHwgT3V0LU51bGwKCiMgSU5WRU5UQUlSRSBBVSBERU1BUlJBR0UKJEludmVudG9yeVN0YXJ0dXBUcmlnZ2VyID0gTmV3LVNjaGVkdWxlZFRhc2tUcmlnZ2VyIC1BdFN0YXJ0dXAKUmVnaXN0ZXItU2NoZWR1bGVkVGFzayBgCiAgICAtVGFza05hbWUgIkdMUEkgSW52ZW50b3J5IEF0IFN0YXJ0dXAiIGAKICAgIC1BY3Rpb24gJEludmVudG9yeUFjdGlvbiBgCiAgICAtVHJpZ2dlciAkSW52ZW50b3J5U3RhcnR1cFRyaWdnZXIgYAogICAgLVNldHRpbmdzICRJbnZlbnRvcnlTZXR0aW5ncyBgCiAgICAtVXNlciAiU1lTVEVNIiBgCiAgICAtUnVuTGV2ZWwgSGlnaGVzdCBgCiAgICAtRm9yY2UgfCBPdXQtTnVsbAoKIyBJTlZFTlRBSVJFIFRPVVRFUyBMRVMgMjQgSEVVUkVTCiMgRMOpcGFydCAyIG1pbnV0ZXMgYXByw6hzIGwnaW5zdGFsbGF0aW9uIGR1IGNvcnJlY3RpZiwgcHVpcyBjaGFxdWUgam91ciDDoCBjZXR0ZSBoZXVyZS4KJEludmVudG9yeURhaWx5VHJpZ2dlciA9IE5ldy1TY2hlZHVsZWRUYXNrVHJpZ2dlciBgCiAgICAtRGFpbHkgYAogICAgLUF0IChHZXQtRGF0ZSkuQWRkTWludXRlcygyKQoKUmVnaXN0ZXItU2NoZWR1bGVkVGFzayBgCiAgICAtVGFza05hbWUgIkdMUEkgSW52ZW50b3J5IEV2ZXJ5IDI0IEhvdXJzIiBgCiAgICAtQWN0aW9uICRJbnZlbnRvcnlBY3Rpb24gYAogICAgLVRyaWdnZXIgJEludmVudG9yeURhaWx5VHJpZ2dlciBgCiAgICAtU2V0dGluZ3MgJEludmVudG9yeVNldHRpbmdzIGAKICAgIC1Vc2VyICJTWVNURU0iIGAKICAgIC1SdW5MZXZlbCBIaWdoZXN0IGAKICAgIC1Gb3JjZSB8IE91dC1OdWxsCgojIFRlc3QgaW1tw6lkaWF0IGR1IERlcGxveSBzYW5zIGF0dGVuZHJlIGxlIHByb2NoYWluIHBhc3NhZ2UuClN0YXJ0LVNjaGVkdWxl
    echo ZFRhc2sgLVRhc2tOYW1lICJHTFBJIERlcGxveSBDaGVjayIKCldyaXRlLUhvc3QgIiIKV3JpdGUtSG9zdCAiPT09IFRBQ0hFUyBHTFBJIENPUlJJR0VFUyA9PT0iCkdldC1TY2hlZHVsZWRUYXNrIHwKICAgIFdoZXJlLU9iamVjdCB7ICRfLlRhc2tOYW1lIC1pbiBAKAogICAgICAgICJHTFBJIERlcGxveSBDaGVjayIsCiAgICAgICAgIkdMUEkgRGVwbG95IEF0IFN0YXJ0dXAiLAogICAgICAgICJHTFBJIEludmVudG9yeSBBdCBTdGFydHVwIiwKICAgICAgICAiR0xQSSBJbnZlbnRvcnkgRXZlcnkgMjQgSG91cnMiCiAgICApIH0gfAogICAgU2VsZWN0LU9iamVjdCBUYXNrTmFtZSxTdGF0ZSwKICAgICAgICBAe049IkV4ZWN1dGlvblRpbWVMaW1pdCI7RT17JF8uU2V0dGluZ3MuRXhlY3V0aW9uVGltZUxpbWl0fX0sCiAgICAgICAgQHtOPSJNdWx0aXBsZUluc3RhbmNlcyI7RT17JF8uU2V0dGluZ3MuTXVsdGlwbGVJbnN0YW5jZXN9fQoKV3JpdGUtSG9zdCAiIgpXcml0ZS1Ib3N0ICJWZXJpZmljYXRpb24gR0xQSSBEZXBsb3kgQ2hlY2sgOiIKJENoZWNrID0gR2V0LVNjaGVkdWxlZFRhc2sgLVRhc2tOYW1lICJHTFBJIERlcGxveSBDaGVjayIKV3JpdGUtSG9zdCAoIkV4ZWN1dGlvblRpbWVMaW1pdCA9ICIgKyAkQ2hlY2suU2V0dGluZ3MuRXhlY3V0aW9uVGltZUxpbWl0KQppZiAoJENoZWNrLlNldHRpbmdzLkV4ZWN1dGlvblRpbWVMaW1pdCAtbmUgIlBUNE0iKSB7CiAgICBXcml0ZS1Ib3N0ICJFUlJFVVIgOiBsYSBsaW1pdGUgbidlc3QgcGFzIFBUNE0iIC1Gb3JlZ3JvdW5kQ29sb3IgUmVkCiAgICBleGl0IDIwCn0KV3JpdGUtSG9zdCAiT0sgOiBsaW1pdGUgRGVwbG95ID0gUFQ0TSAoNCBtaW51dGVzKSIgLUZvcmVncm91bmRDb2xvciBHcmVlbgoKV3JpdGUtSG9zdCAiIgpXcml0ZS1Ib3N0ICJJbnZlbnRhaXJlIGZpbmFsIGF2ZWMgY29udHJvbGUgRC5JLjQuLi4iCiRJbnZlbnRvcnlQcm9jZXNzID0gU3RhcnQtUHJvY2VzcyBgCiAgICAtRmlsZVBhdGggInBvd2Vyc2hlbGwuZXhlIiBgCiAgICAtQXJndW1lbnRMaXN0IEAoIi1Ob1Byb2ZpbGUiLCAiLUV4ZWN1dGlvblBvbGljeSIsICJCeXBhc3MiLCAiLUZpbGUiLCAkSW52ZW50b3J5R3VhcmQpIGAKICAgIC1XYWl0IGAKICAgIC1QYXNzVGhydSBgCiAgICAtV2luZG93U3R5bGUgSGlkZGVuCmlmICgkSW52ZW50b3J5UHJvY2Vzcy5FeGl0Q29kZSAtZXEgMCkgewogICAgV3JpdGUtSG9zdCAiT0sgOiBzdGF0dXQgRC5JLjQgY29udHJvbGUgZXQgaW52ZW50YWlyZSByZW1vbnRlIGEgR0xQSS4iIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4KfSBlbHNlIHsKICAgIFdyaXRlLUhvc3QgKCJBVFRFTlRJT04gOiBsZSBjb250cm9sZSBELkkuNCBhIGV0ZSBlY3JpdCwgbWFpcyBsJ2ludmVudGFpcmUgYSByZXRvdXJuZSAiICsgJEludmVudG9yeVByb2Nlc3MuRXhpdENvZGUpIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93Cn0KCmV4aXQgMAo=
REM END EMBEDDED TASK FIX BASE64



powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$b64=(Get-Content -LiteralPath '%TASK_FIX_B64%' -Raw) -replace '\s','';" ^
  "[IO.File]::WriteAllBytes('%TASK_FIX_PS1%',[Convert]::FromBase64String($b64))"

set "TASK_BUILD_RESULT=!ERRORLEVEL!"
del /q "%TASK_FIX_B64%" >nul 2>&1

if not "!TASK_BUILD_RESULT!"=="0" (
    echo ATTENTION : impossible de reconstruire le correctif PowerShell integre.
    set "TASK_RESULT=!TASK_BUILD_RESULT!"
    goto TASK_FIX_RESULT
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TASK_FIX_PS1%"

set "TASK_RESULT=!ERRORLEVEL!"

:TASK_FIX_RESULT

if not "!TASK_RESULT!"=="0" (
    echo.
    echo ATTENTION : impossible de creer ou verifier les taches GLPI protegees.
    echo Code : !TASK_RESULT!
) else (
    echo.
    echo Taches GLPI creees / corrigees sous SYSTEM.
    echo GLPI Deploy Check force Deploy toutes les 5 minutes.
    echo La limite PT4M et le kill anti-blocage sont actifs.
)

echo ==========================================================
echo OPERATION TERMINEE AVEC SUCCES
echo GLPI Agent %TARGET_VERSION% installe / configure.
echo Inventaire force lance.
echo ==========================================================
echo.

if exist "%MSI_FILE%" del /q "%MSI_FILE%" >nul 2>&1

Read-Host >nul 2>&1
pause
endlocal
exit /b 0

REM ==========================================================
REM ERREUR
REM ==========================================================

:ERROR_END

echo.
echo ==========================================================
echo ERREUR - OPERATION NON TERMINEE
echo ==========================================================
echo.
echo Log installation :
echo %MSI_LOG%
echo.
echo La fenetre reste ouverte pour diagnostic.
echo.
pause
endlocal
exit /b 1
