@echo off
call :Main
exit /b

:: VCBuild (2016-01-06)
:: Visual Studio and Klocwork Build Manager
::
:: Copyright (c) 2015-2016 David Ruhmann
::
:: Permission is hereby granted, free of charge, to any person obtaining a copy
:: of this software and associated documentation files (the "Software"), to deal
:: in the Software without restriction, including without limitation the rights
:: to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
:: copies of the Software, and to permit persons to whom the Software is
:: furnished to do so, subject to the following conditions:
::
:: The above copyright notice and this permission notice shall be included in
:: all copies or substantial portions of the Software.
::
:: THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
:: IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
:: FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
:: AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
:: LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
:: OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
:: THE SOFTWARE.

:::::::::::::::::::::::::::::::::IMPLEMENTATION::::::::::::EDIT:AT:YOUR:OWN:RISK

rem Requires Klocwork and an SVN client be in the PATH environment variable.
rem TODO VCRegister for C# CAS might require reading the csproj for dependencies
rem TODO Finish Windows Mobile support
rem TODO Add Comments to Scripts and more Logging
rem TODO Add Branch Isolation Option


:Main
setlocal
call :Init
call :GitAdjust
call :LoadProject || goto _MainEnd
call :ParseLabels
call :DetectBranch
call :DefaultValues
call :Execute || goto _MainEnd
:_MainEnd
call :LogDeferredErrors
@echo on & @endlocal & @exit /b %LastError%


:Build <Configuration> <Version> <Verbosity> <Code Analysis> <Rule Set> [Klocwork|HPFortify] {HPFORTIFY} {KLOCWORK} {PROJECT}
setlocal
call :Define VCBIN %1
set "Debug=" & if /i "%~1"=="Debug" set "Debug=YES"
:: If Klocwork enabled, but just building Debug regular without code analysis, exit to prevent building Debug twice.
call :IsTrue Debug && call :IsTrue Klocwork && call :Not :IsSharp %PROJECT% && call :Not :Defined %6 && call :Not :EqualsTrue %4 && (endlocal & exit /b 0)
:: If HPFortify enabled, but just building Debug regular without code analysis, exit to prevent building Debug twice.
call :IsTrue Debug && call :IsTrue HPFortify && call :Not :IsSharp %PROJECT% && call :Not :Defined %6 && call :Not :EqualsTrue %4 && (endlocal & exit /b 0)
call :BuildEnvironment %Debug%
call :TidyEnvironment
call :VCClean %1
call :Registration
if "%~2"=="90" call :VCBuild %1 %6
if "%~2"=="100" call :MSBuild %1 %2 %3 %4 %5 %6
if "%~2"=="110" call :MSBuild %1 %2 %3 %4 %5 %6
if "%~2"=="120" call :MSBuild %1 %2 %3 %4 %5 %6
endlocal & exit /b %ErrorLevel%


:: setup the build environment list variables from the system
:BuildEnvironment [Debug Flag] {INCLUDE} {LIB} {LIBPATH} {PATH} {DPATH} {VCINCLUDE} {VCINCLUDED} {VCLIB} {VCLIBD} {VCREFERENCE} {VCREFERENCED} {VCPATH} {VCPATHD}
:: Update the Environment Variables
call :Define INCLUDE "%VCINCLUDE:"=%;%INCLUDE:"=%;"
call :Define LIB "%VCLIB:"=%;%LIB:"=%;"
call :Define LIBPATH "%VCREFERENCE:"=%;%LIBPATH:"=%;"
call :Define PATH "%VCPATH:"=%;%PATH:"=%;"
call :Define DPATH "%PATH:"=%;"
call :Defined %1 || exit /b 0
:: Using Debug Environment Variables
::call :Define INCLUDE "%INCLUDE:"=%;"
call :Define LIB "%VCLIBD:"=%;%LIB:"=%;"
call :Define LIBPATH "%VCREFERENCED:"=%;%LIBPATH:"=%;"
call :Define PATH "%VCPATHD:"=%;%PATH:"=%;"
call :Define DPATH "%PATH:"=%;"
exit /b 0 : {INCLUDE} {LIB} {LIBPATH} {PATH} {DPATH}


:DefaultValues {VCVER} {VCCAR} {VCARC} {VCLOG} {VCCAN} {VCCON} {KLOCWORK} {KWIMPORT} {INPUT} {OUTPUT} {LABEL_*} {BRANCH}
rem Adjust Defaults based on Project Type
if /i "%PROJECT_EXT%"==".vcproj" call :Define VCVER %VCVER% 90
if /i "%PROJECT_EXT%"==".csproj" call :Define VCCAR %VCCAR% MinimumRecommendedRules.ruleset
rem Default to x86, Visual Studio 2013, and no Klocwork
call :Define VCARC %VCARC% x86
call :Define VCVER %VCVER% %LABEL_VS2013% %LABEL_VS2012% %LABEL_VS2010% %LABEL_VS2008% 120
call :Define VCLOG %VCLOG% n
call :Define VCCAN %VCCAN% NO
call :Define VCCAR %VCCAR% NativeRecommendedRules.ruleset
if not defined VCCON set "VCCON=Release;Debug"
call :Define HPFORTIFY %HPFORTIFY% %LABEL_HPFORTIFY% NO
call :Define PVSSTUDIO %PVSSTUDIO% %LABEL_PVSSTUDIO% NO
call :Define KLOCWORK %KLOCWORK% %LABEL_KLOCWORK% NO
call :Define KWIMPORT %KWIMPORT%
call :Define VCCACHE %VCCACHE% YES
rem Update the INPUT and OUTPUT paths with the VCVER and PIPELINE values
call :ParseRepository
call :Define INPUT "%VCINPUT%"
call :Define OUTPUT "%VCOUTPUT%"
call :DetectMobileNet
exit /b 0 : {VCVER} {VCCAR} {VCARC} {VCLOG} {VCCAN} {VCCON} {KLOCWORK} {KWIMPORT} {INPUT} {OUTPUT}


:DetectBranch {SVN_URL}
echo %SVN_URL% |findstr /i "branches" 2>nul && call :ParseBranch "%SVN_URL:branches= %" && exit /b 0
echo %SVN_URL% |findstr /i "tags" 2>nul && call :ParseBranch "%SVN_URL:tags= %" && exit /b 0
echo %SVN_URL% |findstr /i "sandbox" 2>nul && call :ParseBranch "%SVN_URL:sandbox= %" && exit /b 0
rem echo %SVN_URL% |findstr /i "pipelines" 2>nul && call :ParseBranch "%SVN_URL:pipelines= %" && exit /b 0
exit /b 1


:DetectMobileNet {WORKSPACE} {VCINCLUDE_NET} {VCLIB_NET} {VCLIBD_NET} ~UI
if not exist "%WORKSPACE%\MOBILE_NET_CODE\" if not exist "%WORKSPACE%\MOBILE_NET_REUSABLE\" if not exist "%WORKSPACE%\LocalServerIncludes\" if not exist "%WORKSPACE%\LocalServerLibs\" if not exist "%WORKSPACE%\SpecialLibs\" exit /b 1
echo [INFO] Millennium Mobile Detected
call :Expand VCINCLUDE "%VCINCLUDE_NET%"
call :Expand VCLIB "%VCLIB_NET%"
call :Expand VCLIBD "%VCLIBD_NET%"
exit /b 0 : {VCINCLUDE} {VCLIB} {VCLIBD}


:Execute {VCCON} {VCVER} {VCARC} {VCLOG} {VCCAN} {VCCAR} {PROJECT} {KWIMPORT}
call :VCVars %VCVER% %VCARC% exit /b 1
for %%A in ("%VCCON:;=" "%") do call :DeferError :Build %%A %VCVER% %VCLOG% %VCCAN% %VCCAR%
set "HPFortifyLast=%HPFortify%"
set "HPFortify=false"
call :DeferError :Klocwork Debug %VCVER% %VCLOG% %PROJECT% %KWIMPORT%
set "HPFortify=%HPFortifyLast%"
set "KlocworkLast=%Klocwork%"
set "Klocwork=false"
call :DeferError :HPFortify Debug %VCVER% %VCLOG% %PROJECT%
set "Klocwork=%KlocworkLast%"
exit /b %LastError%


:FindProject <Filters> ~IO/UI
set "PROJECT="
set "PROJECT_EXT="
set "PROJECT_NAME="
for /f "delims=" %%A in ('dir /b /a-d %~1 2^>nul') do if not defined PROJECT set "PROJECT=%%~nxA" &set "PROJECT_EXT=%%~xA" &set "PROJECT_NAME=%%~nA"
if defined PROJECT exit /b 0
echo [ERROR] No project file found. Supported Types = %~1
exit /b 1 : {PROJECT} {PROJECT_EXT} {PROJECT_NAME}


::WIP
:FixVCXProj <File>
xcopy "%~1" "%~1.ori" /Y /Q >nul 2>&1
> "%~1" set /p "=" < nul
setlocal EnableDelayedExpansion
for /f "usebackq delims=" %%A in ("%~1.ori") do set "_=%%A" & call :_FixVCXProj >> "%~1"
endlocal & exit /b %ErrorLevel%


:_FixVCXProj {_}
echo !_!|find "</Project>" >nul && call :__FixVCXProj
rem echo !_!|find /v "OutDir"|find /v "OutputFile"|find /v "OutputPath"
echo !_!
exit /b %ErrorLevel%


:__FixVCXProj
set "__=<Import Project="$(ProjectDir)\VCBuild.targets" />"
echo !__!
exit /b %ErrorLevel%


:GitAdjust ~IO
call :GitSparse || exit /b 1
pushd "%GIT_SPARSE%" && set "WORKSPACE=%CD%\%GIT_SPARSE%"
exit /b %ErrorLevel% : {WORKSPACE} {GIT_SPARSE}


:GitSparse {GIT_BRANCH} ~IO/UI
if not defined GIT_BRANCH exit /b 0
for /f "delims=" %%A in ('type ".git\info\sparse-checkout"') do set "GIT_SPARSE=%%A"
if not defined GIT_SPARSE exit /b 1
set "GIT_SPARSE=%GIT_SPARSE:/=\%"
echo [INFO] Git sparse point found
exit /b 0 : {GIT_SPARSE}


:HPFortify <Configuration> <Version> <Verbosity> {HPFortify} {PROJECT_NAME}
sourceanalyzer -b %PROJECT_NAME% -clean --project-root .fortify
sourceanalyzer -b %PROJECT_NAME% -clean
call :IsTrue HPFortify || exit /b 0
echo [INFO] Running HPFortify Build...
call :Build %1 %2 %3 NO null "sourceanalyzer -b %PROJECT_NAME%" || exit /b 1
echo [INFO] HPFortify Build succeeded
echo [INFO] Running HPFortify Analysis...
::call cloudscan.bat -url %FORTIFY_CLOUDCONTROLLER_URL% start -b %PROJECT_NAME% -scan -block -o -f Scan.fpr
sourceanalyzer -b %PROJECT_NAME% -scan -f Scan.fpr
echo [INFO] HPFortify Analysis succeeded
sourceanalyzer -b %PROJECT_NAME% -clean --project-root .fortify
sourceanalyzer -b %PROJECT_NAME% -clean
exit /b 0


:Init
set "ERRORS="
set "LASTERROR=0"
exit /b 0 {ERRORS} {LASTERROR}


:IsSharp <Project>
setlocal
call :Define PROJECT %1 || ( endlocal & exit /b 1 )
if /i "%PROJECT:~-7%"==".csproj" ( endlocal & exit /b 0 )
endlocal & exit /b 2


:Klocwork <Configuration> <Version> <Verbosity> <Project> [Import URL] {JOB_NAME} {KLOCWORK_CACHE} ~IO/UI
rem Clean Existing Reports
del /F /Q KlocworkReport.xml 2>nul
del /F /Q KlocworkReport.txt 2>nul
del /F /Q KlocworkReport.csv 2>nul
rem Check for Klocwork Flag
call :IsTrue Klocwork || exit /b 0
call :KlocworkCacheGet
rem Create Local Klocwork Project
echo [INFO] Connecting to Klocwork Server...
kwcheck create --url http://ipklocworkdb:80/FrontEnd_VC || kwcheck sync
rem call :KlocworkImportSVN "%~5" Klocwork
rem Fix for issue caused by missing folders
md ".kwps\localconfig\ckbs" 2>nul
md ".kwps\localconfig\jkbs" 2>nul
kwcheck info
rem Run Klocwork Build Injector
echo [INFO] Running Klocwork Build Injection...
call :IsSharp %4 && ( call :KlocworkSharpInject %1 %2 %4 || exit /b 5 )
call :IsSharp %4 || ( call :Build %1 %2 %3 NO null kwinject || exit /b 1 )
rem Run Klocwork Analysis, and Report Generators
echo [INFO] Running Klocwork Analysis...
kwcheck run -y -b kwinject.out || exit /b 2
echo [INFO] Generating Klocwork Reports...
kwcheck list -y -F xml --report KlocworkReport.xml || exit /b 3
kwcheck list -y -F detailed --report KlocworkReport.txt || exit /b 4
kwcheck list -y -F scriptable --report KlocworkReport.csv || exit /b 5
echo [INFO] Klocwork Analysis succeeded
echo [INFO] Klocwork Sync...
kwcheck sync
call :KlocworkCachePut
exit /b 0


:KlocworkCacheGet {MSBUILD_CACHE} {JOB_NAME} {VCCACHE} ~UI/IO
rem Remove Existing Caches
rd /S /Q .kwps 2>nul
rd /S /Q .kwlp 2>nul
call :IsTrue VCCACHE || exit /b
echo [INFO] Retrieving Klocwork Cache...
pushd "%KLOCWORK_CACHE%" && xcopy "%JOB_NAME%\.kwps" "%CD%\.kwps\" /I /H /Q /E /Y >nul 2>&1 & xcopy "%JOB_NAME%\.kwlp" "%CD%\.kwlp\" /I /H /Q /E /Y >nul 2>&1 & popd
exit /b


:KlocworkCachePut {KLOCWORK_CACHE} {JOB_NAME} {VCCACHE} ~UI/IO
rem Remove Existing Cache
pushd "%KLOCWORK_CACHE%" && rd /S /Q "%JOB_NAME%" 2>nul & popd
call :IsTrue VCCACHE || exit /b
echo [INFO] Storing Klocwork Cache...
pushd "%KLOCWORK_CACHE%" && xcopy "%CD%\.kwps" "%JOB_NAME%\.kwps\" /I /H /Q /E /Y >nul 2>&1 & xcopy "%CD%\.kwlp" "%JOB_NAME%\.kwlp\" /I /H /Q /E /Y >nul 2>&1 & popd
rem Remove Local Caches
rd /S /Q .kwps 2>nul
rd /S /Q .kwlp 2>nul
exit /b


:KlocworkImport <Source> [Configurations] ~IO/UI
setlocal
call :Define Filters %2 "*.kb *.mconf *.pconf *.tconf"
echo [INFO] Importing Klocwork Rules...
for /f "delims=" %%A in ('"pushd %1 && dir /a-d /b %Filters% & popd"') do kwcheck import "%~1\%%~A" && echo Imported %%~nxA || Skipped %%~nxA
endlocal & exit /b 0


:KlocworkImportSVN <SVN URL> <Target> [Configurations] ~IO
call :Defined %1 || exit /b 1
svn co %1 %2 || exit /b 2
call :KlocworkImport %2 %3
rd /Q /S %2 || exit /b 4
exit /b 0


:KlocworkSharpInject <Configuration> <Version> <Project> ~IO/UI
setlocal
echo [INFO] Injecting into C# Project...
rem C# Configuration Detection
call :FindProject "*.csproj" || exit /b 2
set "CONFIG=" &for /f "delims=" %%A in ('kwcsprojparser "%~3" --list-configs^|findstr /i "^%~1|"') do if not defined CONFIG set "CONFIG=%%~A"
if not defined CONFIG endlocal & exit /b 1
:: Create C# Klocwork Build Configuration
set "TFV="
if "%~2"=="100" set "TFV=TargetFrameworkVersion=v3.5"
@echo on
kwcsprojparser "%~3" -p %TFV% -c "%CONFIG%" -o kwinject.out
@echo off
endlocal & exit /b %ErrorLevel%


:LoadProject ~UI
call :FindProject "*.csproj *.vcxproj *.vcproj" || exit /b 1
call :IsSharp %PROJECT% && echo [INFO] Project Type = C# || echo [INFO] Project Type = C++
echo [INFO] Project = %PROJECT%
exit /b 0
rem devenv /Build "%~1" /useenv


:MSBuild <Configuration> <Version> <Verbosity> <Code Analysis> <Rule Set> [Klocwork|HPFortify] ~IO/UI {INCLUDE} {LIB} {LIBPATH} {WORKSPACE} {PROJECT} {PROJECT_NAME} {JOB_NAME} {SCM} {PROJECT_EXT} {OVERRIDE} {KLOCWORK}
setlocal
call :MSBuildCacheGet %1
rem HACK: To fix the issue with deprecated regsvr32 post/custom build parameters.
md %1 2>nul
@echo off > "%~1\regsvr32.trg"
rem Specify Special Version Specific Options
set "ToolsVersion="
if "%~2"=="120" set "ToolsVersion=/m /ignore:.sln /nr:false /tv:12.0"
if "%~2"=="110" set "ToolsVersion=/m /ignore:.sln /nr:false /tv:11.0"
if defined ToolsVersion call :Defined %6 && call :IsTrue HPFORTIFY || set "ToolsVersion=%ToolsVersion% /flp:LogFile="MSBuild%~1%6.log""
if "%~2"=="100" set "ToolsVersion=/m /ignore:.sln /nr:false /tv:4.0 /p:TargetFrameworkVersion=v3.5"
if "%~2"=="100" if /i "%PROJECT_EXT%"==".csproj" set "ToolsVersion=/m /ignore:.sln /nr:false /tv:3.5 /p:TargetFrameworkVersion=v3.5"
if "%~2"=="100" if /i "%OVERRIDE%"=="NO" set "ToolsVersion=/m /ignore:.sln /nr:false"
if "%~2"=="90"  set "ToolsVersion="
rem Enable Debug Build Code Analysis but not on Klocwork Debug Builds
set "CodeAna="
if "%~2"=="120" if /i "%~1"=="Debug" set "CodeAna=/p:RunCodeAnalysis=true /p:CodeAnalysisRuleSet="%~5""
if /i not "%~4"=="YES" set "CodeAna=/p:RunCodeAnalysis=false"
call :Defined %6 && set "CodeAna=/p:RunCodeAnalysis=false"
set "PROJ=%PROJECT%"
call :Download "%SCM%jenkins/tools/VCBuild.proj" "%WORKSPACE%\%PROJECT_NAME%.proj" && set "PROJ=%PROJECT_NAME%.proj"
rem Build the Command
::set "Command=MSBuild %PROJ% %ToolsVersion% /p:PlatformToolset=v%~2 /p:Configuration=%~1 /p:OutDir=%~1\ /p:IntDir=%~1\ /p:OutputPath=%~1\ /p:IncludePath="%INCLUDE%" /p:LibraryPath="%LIB%" /p:ReferencePath="%LIBPATH%" /p:PreBuildEvent="" /p:PostBuildEvent="" /p:CustomBuildStep="" /p:ImportLibrary="$(OutDir)$(TargetName).lib" /p:OutputFile="$(OutDir)$(TargetName)$(TargetExt)" /p:TypeLibraryName="$(OutDir)$(TargetName).tlb" /p:ProgramDatabaseFile="$(OutDir)$(TargetName).pdb" %CodeAna% /v:%~3"
set "Command=MSBuild %PROJ% %ToolsVersion% /p:PlatformToolset=v%~2 /p:Configuration=%~1 /p:OutDir=%~1\ /p:IntDir=%~1\ /p:OutputPath=%~1\ %CodeAna% /v:%~3"
rem Update the Command for Klocwork
call :Defined %6 && call :IsTrue KLOCWORK && set "Command=%Command:"=\"% /t:Rebuild"
call :Defined %6 && call :IsTrue HPFORTIFY && set "Command=%Command% /t:Rebuild"
rem Execute the Command
@echo on
%~6 %Command%
@echo off
set "ErrorCode=%ErrorLevel%"
del /F /Q "%WORKSPACE%\%PROJECT_NAME%.proj" 2>nul
call :MSBuildCachePut %1
endlocal & exit /b %ErrorCode%


:MSBuildCacheGet <Configuration> {MSBUILD_CACHE} {JOB_NAME} {VCCACHE} ~UI/IO
rd /S /Q "%~1" 2>nul
call :IsTrue VCCACHE || exit /b
echo [INFO] Retrieving MSBuild Cache...
pushd "%MSBUILD_CACHE%" && xcopy "%JOB_NAME%\%~1" "%CD%\%~1\" /I /H /Q /E /Y >nul 2>&1 & popd
exit /b


:MSBuildCachePut <Configuration> {MSBUILD_CACHE} {JOB_NAME} {VCCACHE} ~UI/IO
pushd "%MSBUILD_CACHE%" && rd /S /Q "%JOB_NAME%\%~1" 2>nul & popd
call :IsTrue VCCACHE || exit /b
echo [INFO] Storing MSBuild Cache...
pushd "%MSBUILD_CACHE%" && xcopy "%CD%\%~1" "%JOB_NAME%\%~1\" /I /H /Q /E /Y >nul 2>&1 & popd
exit /b


:ParseBranch <tag branch> {BRANCH} ~UI
for /f "tokens=1,*" %%A in ("%~1") do for /f "delims=\/" %%C in ("%%~B") do if not defined BRANCH set "BRANCH=%%~C"
echo [INFO] Branch = %BRANCH%
exit /b 0


:: Requires custom Jenkins joblabel-environment plugin
:: Does not currently handle complex expressions, but just parses the labels.
:: Supported Labels: VS2013 VS2012 VS2010 VS2008 KLOCWORK
:ParseLabels {JOB_LABELS}
for /f "delims==" %%A in ('set LABEL_ 2^>nul') do set "%%~A="
set "JOB_LABELS_=%JOB_LABELS:(= %"
set "JOB_LABELS_=%JOB_LABELS_:)= %"
set "JOB_LABELS_=%JOB_LABELS_:&= %"
set "JOB_LABELS_=%JOB_LABELS_:|= %"
for %%A in ("%JOB_LABELS_: =" "%") do set "LABEL_%%~A=%%~A"
for /f "tokens=1,* delims==" %%A in ('set LABEL_ 2^>nul') do call :ReplaceLabels "%%~A"
exit /b 0 : {JOB_LABELS_} {LABEL_*}


:ParseRepository {REPOSITORY} {CACHE} {PIPELINE} ~UI
call :Assert :Expand REPOSITORY || exit /b 2
if /i "%REPOSITORY:\=%"=="%CACHE:\=%%PIPELINE:\=%" exit /b 0
setlocal EnableDelayedExpansion
set "CACHE="
for %%A in ("%REPOSITORY:\=" "%") do if not "%%~A"=="" ( set "CACHE=!CACHE!%%~A\" & set "PIPELINE=%%~A" )
endlocal & set "CACHE=%CACHE%" & set "PIPELINE=%PIPELINE%"
if not "%CACHE:~1,1%"==":" set "CACHE=\\%CACHE%"
echo [INFO] CACHE = %CACHE%
echo [INFO] PIPELINE = %PIPELINE%
if /i "%REPOSITORY:\=%"=="%CACHE:\=%%PIPELINE:\=%" exit /b 0
echo [ERROR] REPOSITORY formatting may be incorrect
exit /b 1 : {CACHE} {PIPELINE}


:Registration {REGISTER}
setlocal
call :RegistrationSetup
if not defined REGISTER goto _Registration
call :ExpandParams :Register REGISTER
:_Registration
endlocal & exit /b %ErrorLevel%


:RegistrationSetup
for %%A in ("%SystemRoot%\System32\regsvr32.exe") do if exist "%%~fA" ( set "RegSvr32=%%~fA" )
for %%A in ("%SystemRoot%\RegTLib.exe" "%SystemRoot%\SysWOW64\URTTEMP\RegTLib.exe" "%SystemRoot%\Microsoft.NET\Framework\v2.0.50727\RegTLibv12.exe" "%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\RegTLibv12.exe") do if exist "%%~fA" ( set "RegTLib=%%~fA" )
for %%A in ("%ProgramFiles%\Microsoft SDKs\Windows" "%ProgramFiles(x86)%\Microsoft SDKs\Windows") do if exist "%%~A\" for %%B in ("v7.0A\Bin" "v7.1\Bin" "v7.0A\Bin\NETFX 4.0 Tools" "v7.1\Bin\NETFX 4.0 Tools" "v8.0A\bin\NETFX 4.0 Tools" "v8.1A\bin\NETFX 4.5.1 Tools") do if exist "%%~A\%%~B\TlbImp.exe" ( set "TlbImp=%%~A\%%~B\TlbImp.exe" & set "TlbExp=%%~A\%%~B\TlbExp.exe" )
for %%A in ("%SystemRoot%\Microsoft.NET\Framework\v1.1.4322" "%SystemRoot%\Microsoft.NET\Framework\v2.0.50727" "%SystemRoot%\Microsoft.NET\Framework\v4.0.30319") do if exist "%%~fA\" ( set "RegAsm=%%~fA\RegAsm.exe" & set "RegSvcs=%%~dpA\RegSvcs.exe" )
if not defined RegSvr32 echo [WARNING] Unable to find RegSvr32
if not defined RegTLib echo [WARNING] Unable to find RegTLib
if not defined TlbImp echo [WARNING] Unable to find TlbImp
if not defined TlbExp echo [WARNING] Unable to find TlbExp
if not defined RegAsm echo [WARNING] Unable to find RegAsm
if not defined RegSvcs echo [WARNING] Unable to find RegSvcs
exit /b 0 : {RegTLib} {TlbImp} {RegAsm} {RegSvcs} {RegSvr32}


:ReplaceLabels {LABEL_*}
call :Define %~1 %%%~1:VS2013=120%%
call :Define %~1 %%%~1:VS2012=110%%
call :Define %~1 %%%~1:VS2010=100%%
call :Define %~1 %%%~1:VS2008=90%%
call :Define %~1 %%%~1:KLOCWORK=YES%%
call :Define %~1 %%%~1:PVSSTUDIO=YES%%
call :Define %~1 %%%~1:HPFORTIFY=YES%%
exit /b 0


:: tidy the build environment list variables
:TidyEnvironment {INCLUDE} {LIB} {LIBPATH} {PATH} {DPATH}
call :TidyList INCLUDE
call :TidyList LIB
call :TidyList LIBPATH
call :TidyList PATH
call :TidyList DPATH
exit /b 0 : {INCLUDE} {LIB} {LIBPATH} {PATH} {DPATH}


rem devenv /Build "%~1" /useenv
:VCBuild <Configuration> [Klocwork] ~IO/UI
setlocal
echo [INFO] INCLUDE = %INCLUDE%
echo [INFO] LIB = %LIB%
set "Command=VCBuild /logfile:"MSBuild%~1.log" /M /time /u "%~1""
call :Defined %3 && set "Command=%Command:"=\"% /rebuild"
@echo on
%~3 %Command%
@echo off
endlocal & exit /b %ErrorLevel%


::"Debug" "Release" "ReleaseWithDebug" "Release With Debug"
:VCClean <Configuration> {PROJECT}
echo [INFO] Removing Generated Files...
for %%A in ("%~1" "Bin" "Obj" "TestResult" "BuildLog" "Build" "x64" "ipch" "Express" "publish" "AppPackages" "StyleCop" "Generated_Code" "_UpgradeReport_Files" "$RECYCLE.BIN") do if exist "%%~A" 2>nul rd /Q "%%~A"
for %%A in ("*.exe" "*.dll" "*.ocx" "*.lib" "*.suo" "*.user" "*.sln.docstates" "*_i.h" "*_i.c" "*_p.c" "*.ilk" "*.meta" "*.obj" "*.pch" "*.pdb" "*.pgc" "*.pgd" "*.rsp" "*.sbr" "*.tlb" "*.tli" "*.tlh" "*.tmp" "*.tmp_proj" "*.vspscc" "*.vssscc" ".builds" "*.pidb" "*.scc" "*.aps" "*.ncb" "*.opensdf" "*.sdf" "*.cachefile" "*.psess" "*.vsp" "*.vspx" "*.gpState" "*.ReSharper" "*.dotCover" "*.Publish.xml" "*.pubxml" "*.cache" "*.dbmdl" "*.Publish.xml" "*.pfx" "*.publishsettings" "Thumbs.db" "ehthumbs.db" "Desktop.ini" ".DS_Store") do 2>nul del /F /Q /S "%%~A"
exit /b 0


:: initialize the visual studio environment
:VCVars <Version> <Architecture> ~IO/UI
call :Defined "%~1" || exit /b 1
call :Defined "%~2" || exit /b 2
call :ProgramFiles32
if "%~1"=="90" call "%ProgramFiles32%\Microsoft Visual Studio 9.0\VC\vcvarsall.bat" %~2 && exit /b 0
if "%~1"=="100" call "%ProgramFiles32%\Microsoft Visual Studio 10.0\VC\vcvarsall.bat" %~2 && exit /b 0
if "%~1"=="110" call "%ProgramFiles32%\Microsoft Visual Studio 11.0\VC\vcvarsall.bat" %~2 && exit /b 0
if "%~1"=="120" call "%ProgramFiles32%\Microsoft Visual Studio 12.0\VC\vcvarsall.bat" %~2 && exit /b 0
echo [ERROR] Not found or unknown version of Visual Studio specified. Version=%~1
echo [INFO] Supported versions include 90, 100, 110, and 120, but not all nodes support all versions.
exit /b 3 : {ProgramFiles32}


:::::::::::::::::::::::::::::::::::FRAMEWORK:::::::::::::::::::::::::DO:NOT:EDIT
:Assert <Routine> [Options...] ~UI
call %* && exit /b 0
echo [INFO] call %*
echo [ERROR] Assert on %~1 failed with code %ErrorLevel%
exit /b %ErrorLevel%


:: check list for non-existent paths
:CheckList <ListVar> ~UI
setlocal
call :Define List "%%%~1%%" || ( endlocal & exit /b 1 )
for %%A in ("%List:;=" "%") do if not exist "%%~fA\" echo [INFO] "%%~A" not found.
endlocal & exit /b 0


:CopyFirst <File> <Destination> {PATH} {LIBPATH} {LIB}
setlocal
set "_=%~dp1;%LIBPATH%;%LIB%;%PATH%"
call :TidyList _ >nul
call :CopyFirst_ %1 %2
endlocal & exit /b %ErrorLevel%


:CopyFirst_ <File> <Destination> {_}
md "%~2" 2>nul || exit /b 1
if defined _ for %%A in ("%_:;=" "%") do if exist "%%~A\%~nx1" ( echo f|xcopy /y /r "%%~A\%~nx1" "%~2\%~nx1" >nul 2>&1 & exit /b )
exit /b 2


:DeferError <Command> [Params]
call %*
if %ErrorLevel% neq 0 ( set "ERRORS=%ERRORS%%ErrorLevel%;" & set "LASTERROR=%ErrorLevel%" )
exit /b 0 {ERRORS} {LASTERROR}


:: variable definition and validation
:Define <Var> [Value] [Default]
2>nul set "%~1=%~2"
if defined %~1 = exit /b 0
exit /b 1


:: check for existence of variable
:Defined <Input>
setlocal
set "Input=%~1"
if defined Input endlocal & exit /b 0
endlocal & exit /b 1


:Download <URL> <Destination> ~UI/IO
echo [DOWNLOADING] %~nx2...
PowerShell -NoProfile -ExecutionPolicy RemoteSigned -Command "(New-Object System.Net.WebClient).DownloadFile('%~1', '%~2');"
exit /b


:EqualsTrue <Value>
setlocal
call :Define Var %1 || exit /b 1
if /i "%Var:~0,1%"=="y" exit /b 0
if /i "%Var:~0,3%"=="yes" exit /b 0
if /i "%Var:~0,4%"=="true" exit /b 0
endlocal & exit /b 2


:: variable expansion and validation
:Expand <Var> [Default]
call :Define %1 "%%%1%%" || call :Define %* || exit /b 1
exit /b 0


:: TODO support all parameters
:ExpandParams <Command> <Var>
call :Defined %1 || exit /b 1
setlocal
if defined %2 = call :Define Var "%%%~2:"=%%"
call %1 "%Var%"
endlocal & exit /b %ErrorLevel%


:IsTrue <Var>
call :EqualsTrue "%%%~1%%" || exit /b
exit /b 0


:LogDeferredErrors {Errors} {LastError} ~UI
echo.
if not defined Errors echo [INFO] No Errors Detected
if defined Errors echo [ERROR] Errors Encountered = %Errors%
exit /b %LastError%


:!
:Not <Routine> [Options...]
call %* || exit /b 0
exit /b 1


:Register [Directory;File;List=%CD%]
setlocal
call :Define List "%~1" "%CD%"
for %%A in ("%List:;=" "%") do ( call :RegisterDirectory "%%~fA" || call :RegisterFile "%%~A" || call :RegisterFirstFile "%%~A" || echo [INVALID] %%~nA )
endlocal & exit /b %ErrorLevel%


:Registered <File> <Message> ~UI
echo [REGISTERED %~2] "%~f1"
exit /b


:RegisterDirectory [Directory=%CD%] ~UI/IO
if not exist "%~1\" exit /b 1
setlocal & echo.
call :Define Location %1 "%CD%"
pushd %Location% 2>nul && for /f "delims=" %%A in ('dir a-d /b *.dll *.ocx *.tlb') do call :RegisterFile "%%~fA"
call :Registered %1 DIRECTORY
popd & endlocal & exit /b %ErrorLevel%


:RegisterFile <File>
if not exist "%~1" exit /b 1
call :UnRegisterFile %1 >nul
if /i "%~x1"==".tlb" call :RegisterTLB %1
if /i not "%~x1"==".tlb" call :RegisterDLL %1
exit /b


:RegisterFirstFile <File> {PATH} {LIBPATH} {LIB}
setlocal
set "_=%LIBPATH%;%LIB%;%PATH%"
call :TidyList _ >nul
call :RegisterFirstFile_ %1
endlocal & exit /b %ErrorLevel%


:RegisterFirstFile_ <File> {_}
if defined _ for %%A in ("%_:;=" "%") do if exist "%%~A\%~nx1" ( call :RegisterFile "%%~A\%~nx1" && exit /b 0 )
exit /b 1


:RegisterASM <File> {RegAsm} ~UI/IO
::call :RegisterASMTLB %1 && exit /b
"%RegAsm%" /nologo /silent "%~f1" /codebase 2>nul && call :Registered %1 ASM
exit /b


:RegisterASMTLB <File> {RegAsm} ~UI/IO
if exist "WinIntel\Lib\%~n1.tlb" exit /b 1
md WinIntel\Lib 2>nul
"%RegAsm%" /nologo /silent "%~f1" /tlb:"WinIntel\Lib\%~n1.tlb" /codebase 2>nul && call :Registered %1 "REGISTERED ASM + GENERATED TLB"
exit /b
::&& call :RegisterTLB "WinIntel\Lib\%~n1.tlb"


:RegisterSVR <File> {RegSvr32} ~UI/IO
"%RegSvr32%" /s "%~f1" && call :Registered %1 SVR
exit /b


:RegisterSVCS <File> {RegSvcs} ~UI/IO
"%RegSvcs%" /quiet "%~f1" 2>nul && call :Registered %1 SVCS
exit /b


:RegisterDLL <File> {RegAsm} {RegSvcs} {RegSvr32} {TlbExp} ~UI/IO
call :RegisterSVR %1 || call :RegisterASM %1 || call :RegisterSVCS %1 || call :Registered %1 SKIPPED
exit /b


:RegisterTLB <File> {RegTLib} ~UI/IO
call :RegisterTLBImport %1
"%RegTLib%" "%~1" 2>nul && call :Registered %1 TLB || call :Registered %1 SKIPPED
exit /b


:RegisterTLBExport <File> {TlbExp} ~UI/IO
if exist "WinIntel\Lib\%~n1.tlb" exit /b 1
md WinIntel\Lib 2>nul
"%TlbExp%" "%~f1" /out:"WinIntel\Lib\%~n1.tlb" /silent 2>nul && echo [EXPORTED TLB] "%~f1"
exit /b


:RegisterTLBImport <File> {TlbImp} ~UI/IO
::call :RegisterTLBImportDLL %1 && exit /b
"%TlbImp%" "%~1" /silent 2>nul && echo [IMPORTED TLB] "%~f1"
exit /b


:RegisterTLBImportDLL <File> {TlbImp} ~UI/IO
if exist "WinIntel\%~n1.dll" exit /b 1
md WinIntel 2>nul
"%TlbImp%" "%~1" /out:"WinIntel\%~n1.dll" /silent 2>nul && echo [IMPORTED TLB + GENERATED DLL] "%~f1"
exit /b


:: remove duplicate entries from list
:RemoveDuplicates <ListVar>
setlocal EnableDelayedExpansion
call :Define List "%%%~1%%" || ( endlocal & exit /b 1 )
set "Tsil="
for %%A in ("%List:;=" "%") do if not "%%~A"=="" set "Tsil=%%~A;!Tsil!"
for %%A in ("%Tsil:;=" "%") do if not "%%~A"=="" set "List=%%~A;!List:%%~A;=!"
endlocal & set "%~1=%List%"
exit /b 0


:ProgramFiles32
set "ProgramFiles32=%ProgramFiles%"
if defined ProgramFiles(x86) set "ProgramFiles32=%ProgramFiles(x86)%"
exit /b 0


:: remove excess backslashes, semicolons, and duplicate entries
:TidyList <ListVar>
if not defined %~1 = exit /b 1
call :Define "%~1" "%%%~1:;;=;%%"
call :Define "%~1" "%%%~1:\\=\%%"
call :Define "%~1" "%%%~1:\\=\%%"
call :Define "%~1" "%%%~1:\;=;%%"
call :RemoveDuplicates %1
:: remove any new excess and fix network paths
call :Define "%~1" ";%%%~1:\\=\%%"
call :Define "%~1" "%%%~1:;;=;%%"
call :Define "%~1" "%%%~1:;\=;\\%%"
call :Define "%~1" "%%%~1:~1%%"
::call :CheckList %1
exit /b


:UnRegisterDirectory [Directory=%CD%] ~UI/IO
if not exist "%~1\" exit /b 1
setlocal & echo.
call :Define Location %1 "%CD%"
pushd %Location% 2>nul && for /f "delims=" %%A in ('dir a-d /b *.dll *.ocx *.tlb') do call :UnRegisterFile "%%~fA"
echo [DEREGISTERED DIRECTORY] "%~f1"
popd & endlocal & exit /b %ErrorLevel%


:UnRegisterFile <File> ~UI/IO
if not exist "%~1" exit /b 1
if /i "%~x1"==".tlb" call :UnRegisterTLB %1
if /i not "%~x1"==".tlb" call :UnRegisterDLL %1
exit /b


:UnRegisterDLL <File> {RegAsm} {RegSvcs} {RegSvr32} ~UI/IO
"%RegSvr32%" /u /s "%~f1" && echo [DEREGISTERED SVR] "%~f1" || "%RegAsm%" /unregister /nologo /silent "%~f1" 2>nul && echo [DEREGISTERED ASM] "%~f1" || "%RegSvcs%" /u /quiet "%~f1" 2>nul && echo [DEREGISTERED SVCS] "%~f1" || echo [DEREGISTERED SKIPPED] "%~f1"
if exist "WinIntel\Lib\%~n1.tlb" call :UnRegisterTLB "WinIntel\Lib\%~n1.tlb"
exit /b


:UnRegisterTLB <File> {RegTLib} ~UI/IO
"%RegTLib%" -u "%~1" 2>nul && echo [DEREGISTERED TLB] "%~f1" || echo [DEREGISTERED SKIPPED] "%~f1"
exit /b
