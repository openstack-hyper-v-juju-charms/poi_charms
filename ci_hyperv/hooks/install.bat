
REM Disable Firewalls
powershell -ExecutionPolicy RemoteSigned Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

REM Disable Automatic Windows Updates
call cscript %windir%\system32\scregedit.wsf /AU 1

REM Enable iSCSI Initiator
powershell -ExecutionPolicy RemoteSigned start-service MSiSCSI 2>&1 >null

REM Set timezone and NTP
call %windir%\system32\tzutil.exe /s UTC
powershell -ExecutionPolicy RemoteSigned start-service w32time 2>&1 >null
REM call %windir%\system32\w32tm.exe /config /manualpeerlist:time.microsoft.akadns.net /syncfromflags:MANUAL
call %windir%\system32\w32tm.exe /config /manualpeerlist:time.microsoft.akadns.net /syncfromflags:ALL /update
call %windir%\system32\w32tm.exe /resync

REM Enable RDP
call reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f

mkdir \tmp

REM OpenSSL (Using 1.0.1, as that is known working in Cambridge)
REM  Magic variable for file name.
set sslfile=Win32OpenSSL-1_0_1m.exe
powershell -ExecutionPolicy RemoteSigned (new-object Net.WebClient).DownloadFile("http://slproweb.com/download/%sslfile%", "\tmp\%sslfile%")
call \tmp\%sslfile% /VERYSILENT /SUPPRESSMSGBOXES /LOG

REM  No Jenkins, skipping Java
REM  POC, skipping FreeRDP
REM  POC, skipping Sensu bits

REM msys Git
set gitfile=Git-1.8.0-preview20121022.exe
powershell -ExecutionPolicy RemoteSigned (new-object Net.WebClient).DownloadFile("http://cloud.github.com/downloads/msysgit/git/%gitfile%", "\tmp\%gitfile%")
call \tmp\%gitfile% /VERYSILENT /SUPPRESSMSGBOXES /LOG

REM Python 2.7
set pyfile=python-2.7.10.amd64.msi
powershell -ExecutionPolicy RemoteSigned (new-object Net.WebClient).DownloadFile("https://www.python.org/ftp/python/2.7.10/%pyfile%", "\tmp\%pyfile%")
call \tmp\%pyfile% /VERYSILENT /SUPPRESSMSGBOXES /LOG



REM ########
REM # Join HV to DevStack
REM ########

"bash C:\OpenStack\devstack\scripts\gerrit-git-prep.sh --zuul-site '$ZUUL_SITE' --gerrit-site '$ZUUL_SITE' --zuul-ref '$ZUUL_REF' --zuul-change '$ZUUL_CHANGE' --zuul-project '$ZUUL_PROJECT' >>\\'$FIXED_IP'\openstack\logs\create-environment-'$1'.log 2>&1"
powershell -ExecutionPolicy RemoteSigned C:\OpenStack\devstack\scripts\EnsureOpenStackServices.ps1 administrator H@rd24G3t >>\\'$FIXED_IP'\openstack\logs\create-environment-'$1'.log 2>&1
"powershell -ExecutionPolicy RemoteSigned C:\OpenStack\devstack\scripts\create-environment.ps1 -devstackIP '$FIXED_IP' -branchName '$ZUUL_BRANCH' -buildFor '$ZUUL_PROJECT' >>\\'$FIXED_IP'\openstack\logs\create-environment-'$1'.log 2>&1"
