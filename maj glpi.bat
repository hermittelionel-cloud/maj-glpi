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
REM VERSION ACTUELLE
REM ==========================================================

if exist "%AGENT_BAT%" (
    echo Version actuelle :
    call "%AGENT_BAT%" --version
    echo.

    "%AGENT_BAT%" --version 2>nul | findstr /C:"(%TARGET_VERSION%)" >nul
    if "!ERRORLEVEL!"=="0" (
        echo GLPI Agent %TARGET_VERSION% est deja installe.
        goto CONFIGURE_AND_INVENTORY
    )

    echo Une autre version est installee.
    echo Tentative de mise a jour vers %TARGET_VERSION%...
) else (
    echo GLPI Agent absent ou incomplet.
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

msiexec.exe /i "%MSI_FILE%" /qn /norestart SERVER="%GLPI_URL%" ADDLOCAL=feat_DEPLOY TASKS=Inventory,Deploy ADD_FIREWALL_EXCEPTION=1 /L*v "%MSI_LOG%"
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
REM TACHE PLANIFIEE DEPLOY FORCE TOUTES LES 5 MINUTES
REM ==========================================================

echo.
echo Creation / mise a jour de la tache planifiee GLPI Deploy Check...
echo Compte : SYSTEM
echo Frequence : toutes les 5 minutes
echo Commande : glpi-agent.bat --tasks deploy --force
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$taskName='GLPI Deploy Check';" ^
  "Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue;" ^
  "$action=New-ScheduledTaskAction -Execute 'C:\Program Files\GLPI-Agent\glpi-agent.bat' -Argument '--tasks deploy --force';" ^
  "$trigger=New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5);" ^
  "$principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest;" ^
  "$settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries;" ^
  "Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null;" ^
  "$t=Get-ScheduledTask -TaskName $taskName;" ^
  "if(-not $t){exit 10};" ^
  "Start-ScheduledTask -TaskName $taskName;" ^
  "Start-Sleep -Seconds 3;" ^
  "$i=Get-ScheduledTaskInfo -TaskName $taskName;" ^
  "Write-Host ('Tache creee : '+$taskName);" ^
  "Write-Host ('Derniere execution : '+$i.LastRunTime);" ^
  "Write-Host ('Prochaine execution : '+$i.NextRunTime);" ^
  "Write-Host ('Dernier resultat : '+$i.LastTaskResult);" ^
  "exit 0"

set "TASK_RESULT=!ERRORLEVEL!"

if not "!TASK_RESULT!"=="0" (
    echo.
    echo ATTENTION : impossible de creer ou tester la tache GLPI Deploy Check.
    echo Code : !TASK_RESULT!
) else (
    echo.
    echo Tache GLPI Deploy Check creee sous SYSTEM.
    echo Elle forcera Deploy toutes les 5 minutes.
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
