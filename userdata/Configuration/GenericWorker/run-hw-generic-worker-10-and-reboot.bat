@echo off



:ManifestCheck 
rem https://bugzilla.mozilla.org/show_bug.cgi?id=1442472
ping -n 6 127.0.0.1 1>/nul
echo Checking for manifest completetion >> C:\generic-worker\generic-worker.log

if Not exist C:\DSC\EndOfManifest.semaphore GoTo ManifestCheck

echo Checking for key pair >> C:\generic-worker\generic-worker.log
If exist C:\generic-worker\generic-worker-gpg-signing-key.key echo Key pair present >> C:\generic-worker\generic-worker.log
If not exist C:\generic-worker\generic-worker-gpg-signing-key.key echo Generating key pair >> C:\generic-worker\generic-worker.log
If not exist C:\generic-worker\generic-worker-gpg-signing-key.key C:\generic-worker\generic-worker.exe new-openpgp-keypair --file C:\generic-worker\generic-worker-gpg-signing-key.key"
If exist C:\generic-worker\generic-worker-gpg-signing-key.key echo Key pair created >> C:\generic-worker\generic-worker.log
If not exist C:\generic-worker\generic-worker-gpg-signing-key.key shutdown /r /t 0 /f /c "Rebooting as key generation failed"


echo Running generic-worker startup script (run-generic-worker.bat) ... >> C:\generic-worker\generic-worker.log

echo Disk space stats of C:\ >> C:\generic-worker\generic-worker.log
fsutil volume diskfree c: >> C:\generic-worker\generic-worker.log

If exist C:\generic-worker\gen_worker.config GoTo PreWorker
for /F "tokens=14" %%i in ('"ipconfig | findstr IPv4"') do SET LOCAL_IP=%%i
cat C:\generic-worker\master-generic-worker.json | jq ".  | .workerId=\"%COMPUTERNAME%\"" > C:\generic-worker\gen_worker.json
cat C:\generic-worker\gen_worker.json | jq ".  | .publicIP=\"%LOCAL_IP%\"" > C:\generic-worker\gen_worker.config


:PreWorker
if exist C:\generic-worker\disable-desktop-interrupt.reg reg import C:\generic-worker\disable-desktop-interrupt.reg

:CheckForStateFlag
echo Checking for C:\dsc\task-claim-state.valid file... >> C:\generic-worker\generic-worker.log
if exist C:\dsc\task-claim-state.valid goto RunWorker
ping -n 2 127.0.0.1 1>/nul
goto CheckForStateFlag

:RunWorker

echo File C:\dsc\task-claim-state.valid found >> C:\generic-worker\generic-worker.log
echo Deleting C:\dsc\task-claim-state.valid file >> C:\generic-worker\generic-worker.log
del /Q /F C:\dsc\task-claim-state.valid >> C:\generic-worker\generic-worker.log 2>&1
del /Q /F C:\DSC\EndOfManifest.semaphore
pushd %~dp0
set errorlevel=
C:\generic-worker\generic-worker.exe run --config C:\generic-worker\gen_worker.config >> C:\generic-worker\generic-worker.log 2>&1
set GW_EXIT_CODE=%errorlevel%

if %GW_EXIT_CODE% EQU 69 goto ErrorReboot

<nul (set/p z=) >C:\dsc\task-claim-state.valid
echo Generic worker ran successfully (exit code %GW_EXIT_CODE%) rebooting
if exist C:\generic-worker\rebootcount.txt del /Q /F  C:\generic-worker\rebootcount.txt
if exist C:\DSC\in-progress.lock del /Q /F C:\DSC\in-progress.lock
shutdown /r /t 0 /f /c "Rebooting as generic worker ran successfully"
exit

:ErrorReboot
if exist C:\DSC\in-progress.lock del /Q /F C:\DSC\in-progress.lock
if exist C:\generic-worker\rebootcount.txt GoTo AdditonalReboots
echo 1 >> C:\generic-worker\rebootcount.txt
echo Generic worker exit with code %GW_EXIT_CODE%; Rebooting to recover  >> C:\generic-worker\generic-worker.log
shutdown /r /t 0 /f /c "Generic worker exit with code %GW_EXIT_CODE%; Attempting reboot to recover"
exit
:AdditonalReboots
ping -n 10 127.0.0.1 1>/nul
for /f "delims=" %%a in ('type "C:\generic-worker\rebootcount" ' ) do set num=%%a
set /a num=num + 1 > C:\generic-worker\rebootcount.txt
if %num% GTR 5 GoTo WaitReboot
echo Generic worker exit with code %GW_EXIT_CODE% more than once; Rebooting to recover  >> C:\generic-worker\generic-worker.log
shutdown /r /t 0 /f /c "Generic worker has not recovered;  Rebooting"
exit
:WaitReboot
echo Generic worker exit with code %GW_EXIT_CODE% %num% times; 1800 second delay and then rebooting  >> C:\generic-worker\generic-worker.log
ping -n 1800 127.0.0.1 1>/nul
shutdown /r /t 0 /f /c "Generic worker has not recovered;  Rebooting"
exit

:loop_reboot 
if exist C:\DSC\in-progress.lock del /Q /F C:\DSC\in-progress.lock
shutdown /r /t 0 /f /c "OCC manifest did not apply in the expected time;  Rebooting"
exit
