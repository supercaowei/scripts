@echo off
setlocal enabledelayedexpansion

:: If you see garbled characters, please reopen this file with GB2312 encoding and CRLF line breaks.
:: ����㿴�����룬���� GB2312 ����� CRLF ���з����´򿪴��ļ��� 

:: ����Ƿ��ѻ�ȡ����ԱȨ��
net session >nul 2>&1
if '%errorlevel%' == '0' (
    goto :ADMIN_SUCCESS
) else (
    goto :UAC_PROMPT
)

:UAC_PROMPT
echo �ű�δ�Թ���ԱȨ�����У����ڳ����Թ���ԱȨ����������...
if "%*"=="" (
    powershell -Command "Start-Process '%0' -Verb RunAs"
) else (
    powershell -Command "Start-Process '%0' -ArgumentList '%*' -Verb RunAs"
)
exit /b

:ADMIN_SUCCESS

:: MediaSdkOld
set "sdk1=MediaSdkOld"
set "source_dir1=C:\Users\Admin\Work\LiveMediaSDK\bins\exec64"
set "file_names1=MediaSDK_Server.exe MediaSDK_Client.node PipeSDK_Server.node"
::MediaSdkNew
set "sdk2=MediaSdkNew"
set "source_dir2=C:\Users\Admin\Work\MediaSDK_CN\x64\bin"
set "file_names2=AVFoundation.dll IPC.dll"
::LiveCore
set "sdk3=LiveCore"
set "source_dir3=C:\Users\Admin\Work\livecore\business_modules\LiveCore\build\output\Release\Windows\AMD64\x64\Release"
set "file_names3=livecore.dll app_windows.dll bytevcx_plugin.dll flv_plugin.dll rtmp_plugin.dll mbedtls_plugin.dll"

:: ����������
set "sdk=%~1"
if "!sdk!"=="" (
    echo ��ѡ��Ҫ���Ƶ�SDK��
    echo 1. %sdk1%
    echo 2. %sdk2%
    echo 3. %sdk3%
    :: ��������
    set /p "choice=��������ţ�"
    if "!choice!"=="1" (
        set "sdk=%sdk1%"
    ) else if "!choice!"=="2" (
        set "sdk=%sdk2%"
    ) else if "!choice!"=="3" (
        set "sdk=%sdk3%"
    ) else (
        echo �����ѡ����Ч
        pause
        exit /b 2001
    )
    echo.
)

:: ���ݲ���ѡ���ļ���
set "source_dir="
set "file_names="
if /i "%sdk%"=="%sdk1%" set "source_dir=!source_dir1!" & set "file_names=!file_names1!"
if /i "%sdk%"=="%sdk2%" set "source_dir=!source_dir2!" & set "file_names=!file_names2!"
if /i "%sdk%"=="%sdk3%" set "source_dir=!source_dir3!" & set "file_names=!file_names3!"

if not defined file_names (
    echo ������Ч���� %1
    echo ��ѡֵ��MediaSdkOld / MediaSdkNew / LiveCore
    pause
    exit /b 2002
)

:: ֱ�����µ�Ŀ��·��
set "dest_dir_prefix=C:\Program Files (x86)\webcast_mate\"
:: �汾�ţ�3����ָ������Ķ�����
set "version_reg=^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*"
set "dest_dir_suffix=\resources\app\app.content\node_modules\@byted\mediasdk-client\lib"

:: ���Ұ汾Ŀ¼����
set "dest_dir_with_version="
for /d %%d in ("%dest_dir_prefix%*") do (
    set "current_dir=%%~nxd"
    echo !current_dir! | findstr /r "%version_reg%" >nul
    if !errorlevel! equ 0 (
        if defined dest_dir_with_version (
            echo ������ֱ�����µİ�װĿ¼ !dest_dir_prefix! ���ҵ�����汾Ŀ¼��
            echo ֮ǰ�ҵ���!dest_dir_with_version!����ǰ�ҵ���%%d��
            pause
            exit /b 1002
        )
        set "dest_dir_with_version=%%d"
    )
)

:: ��֤�汾Ŀ¼
if not defined dest_dir_with_version (
    echo ������ֱ�����µİ�װĿ¼ !dest_dir_prefix! ��δ�ҵ��������� %version_reg% �İ汾Ŀ¼
    pause
    exit /b 1001
)

:: ����Ŀ��·���������Ŀ��Ŀ¼�Ƿ����
set "dest_dir=%dest_dir_with_version%%dest_dir_suffix%"
if not exist "%dest_dir%" (
    echo ����Ҫ����SDK����Ŀ��Ŀ¼ !dest_dir! ������
    pause
    exit /b 1003
)

:: �ļ���������
echo ԴĿ¼��%source_dir%
echo Ŀ��Ŀ¼��%dest_dir%
set "error_flag=0"
for %%f in (%file_names%) do (
    if not exist "%source_dir%\%%f" (
        echo ����Դ�ļ� %%f ������
        set "error_flag=1"
    ) else (
        echo ���ڸ��ƣ�%%f
        xcopy /y "%source_dir%\%%f" "%dest_dir%\" >nul
        if !errorlevel! neq 0 (
            echo ���󣺸���ʧ�� - %%f
            set "error_flag=1"
        )
    )
)

:: ����״̬���
if %error_flag% neq 0 (
    echo ���󣺲����ļ�����ʧ��
    pause
    exit /b 1004
)

echo ������ɣ�
echo.
pause

endlocal
