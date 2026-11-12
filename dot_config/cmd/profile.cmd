@echo off

if exist "%USERPROFILE%\.local\bin" set "PATH=%USERPROFILE%\.local\bin;%PATH%"
if exist "%USERPROFILE%\scoop\shims" set "PATH=%USERPROFILE%\scoop\shims;%PATH%"
if exist "%LOCALAPPDATA%\agy\bin" set "PATH=%LOCALAPPDATA%\agy\bin;%PATH%"

doskey reload=call "%USERPROFILE%\.config\cmd\profile.cmd"
doskey refresh=call "%USERPROFILE%\.config\cmd\profile.cmd"
doskey rr=call "%USERPROFILE%\.config\cmd\profile.cmd"
doskey ll=dir /a $*
doskey la=dir /a $*
doskey which=where $*
doskey pbcopy=clip
doskey pbpaste=powershell.exe -NoProfile -Command Get-Clipboard
doskey uid=powershell.exe -NoProfile -Command "[guid]::NewGuid().ToString().ToLowerInvariant()"

rem %%~$PATH:I searches PATH inside cmd itself; where.exe would start one process per tool
for %%I in (bat.exe) do if not "%%~$PATH:I"=="" doskey cat=bat $*
for %%I in (rg.exe) do if not "%%~$PATH:I"=="" doskey grep=rg $*
for %%I in (nvim.exe) do if not "%%~$PATH:I"=="" doskey vi=nvim $*
for %%I in (kubectl.exe) do if not "%%~$PATH:I"=="" doskey k=kubectl $*
for %%I in (lazygit.exe) do if not "%%~$PATH:I"=="" doskey lg=lazygit $*
for %%I in (fastfetch.exe) do if not "%%~$PATH:I"=="" (doskey ff=fastfetch $* & doskey nf=fastfetch $*)
for %%I in (winfetch.ps1) do if not "%%~$PATH:I"=="" doskey nf=powershell.exe -NoProfile -File "%USERPROFILE%\scoop\shims\winfetch.ps1" $*
for %%I in (pwsh.exe) do if not "%%~$PATH:I"=="" (doskey ua=pwsh.exe -NoLogo -Command Update-All $* & doskey ca=pwsh.exe -NoLogo -Command Clean-All $*)
