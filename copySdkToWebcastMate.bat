@echo off
setlocal enabledelayedexpansion

:: If you see garbled characters, please reopen this file with GB2312 encoding and CRLF line breaks.
:: 如果你看到乱码，请以 GB2312 编码和 CRLF 换行符重新打开此文件。 

:: 检查是否已获取管理员权限
net session >nul 2>&1
if '%errorlevel%' == '0' (
    goto :ADMIN_SUCCESS
) else (
    goto :UAC_PROMPT
)

:UAC_PROMPT
echo 脚本未以管理员权限运行，正在尝试以管理员权限重新运行...
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

:: 检查参数输入
set "sdk=%~1"
if "!sdk!"=="" (
    echo 请选择要复制的SDK：
    echo 1. %sdk1%
    echo 2. %sdk2%
    echo 3. %sdk3%
    :: 接收输入
    set /p "choice=请输入序号："
    if "!choice!"=="1" (
        set "sdk=%sdk1%"
    ) else if "!choice!"=="2" (
        set "sdk=%sdk2%"
    ) else if "!choice!"=="3" (
        set "sdk=%sdk3%"
    ) else (
        echo 输入的选项无效
        pause
        exit /b 2001
    )
    echo.
)

:: 根据参数选择文件组
set "source_dir="
set "file_names="
if /i "%sdk%"=="%sdk1%" set "source_dir=!source_dir1!" & set "file_names=!file_names1!"
if /i "%sdk%"=="%sdk2%" set "source_dir=!source_dir2!" & set "file_names=!file_names2!"
if /i "%sdk%"=="%sdk3%" set "source_dir=!source_dir3!" & set "file_names=!file_names3!"

if not defined file_names (
    echo 错误：无效参数 %1
    echo 可选值：MediaSdkOld / MediaSdkNew / LiveCore
    pause
    exit /b 2002
)

:: 直播伴侣的目标路径
set "dest_dir_prefix=C:\Program Files (x86)\webcast_mate\"
:: 版本号：3个点分隔开的四段数字
set "version_reg=^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*"
set "dest_dir_suffix=\resources\app\app.content\node_modules\@byted\mediasdk-client\lib"

:: 查找版本目录流程
set "dest_dir_with_version="
for /d %%d in ("%dest_dir_prefix%*") do (
    set "current_dir=%%~nxd"
    echo !current_dir! | findstr /r "%version_reg%" >nul
    if !errorlevel! equ 0 (
        if defined dest_dir_with_version (
            echo 错误：在直播伴侣的安装目录 !dest_dir_prefix! 中找到多个版本目录。
            echo 之前找到：!dest_dir_with_version!，当前找到：%%d。
            pause
            exit /b 1002
        )
        set "dest_dir_with_version=%%d"
    )
)

:: 验证版本目录
if not defined dest_dir_with_version (
    echo 错误：在直播伴侣的安装目录 !dest_dir_prefix! 中未找到符合正则 %version_reg% 的版本目录
    pause
    exit /b 1001
)

:: 构建目标路径，并检查目标目录是否存在
set "dest_dir=%dest_dir_with_version%%dest_dir_suffix%"
if not exist "%dest_dir%" (
    echo 错误：要复制SDK到的目标目录 !dest_dir! 不存在
    pause
    exit /b 1003
)

:: 文件复制流程
echo 源目录：%source_dir%
echo 目标目录：%dest_dir%
set "error_flag=0"
for %%f in (%file_names%) do (
    if not exist "%source_dir%\%%f" (
        echo 错误：源文件 %%f 不存在
        set "error_flag=1"
    ) else (
        echo 正在复制：%%f
        xcopy /y "%source_dir%\%%f" "%dest_dir%\" >nul
        if !errorlevel! neq 0 (
            echo 错误：复制失败 - %%f
            set "error_flag=1"
        )
    )
)

:: 最终状态检查
if %error_flag% neq 0 (
    echo 错误：部分文件复制失败
    pause
    exit /b 1004
)

echo 复制完成！
echo.
pause

endlocal
