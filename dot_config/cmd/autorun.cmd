@echo off
rem AutoRun starts with every cmd.exe, also each "cmd /c" of a build tool or script, so only an interactive cmd loads the profile
setlocal EnableDelayedExpansion
set "line=!CMDCMDLINE!"
if /i "!line:/c =!"=="!line!" (endlocal & call "%USERPROFILE%\.config\cmd\profile.cmd") else endlocal
