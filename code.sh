#!/bin/bash

# Make sure this file is encoded in UTF-8 and its line endings are LF instead of CRLF.

# 说明：本脚本专用于 cygwin 终端下运行 vscode。
# 将传入的所有 - 或 -- 开头的参数选项保持不变，其他参数都认为是路径，转换为 Windows 格式路径，然后传给VS Code程序。

# 初始化 Windows 格式参数数组
win_args=()

# 遍历所有输入参数
for arg in "$@"; do
    if [[ "$arg" == -* || "$arg" == --* ]]; then
        # 保留以 - 或 -- 开头的选项参数
        win_args+=("$arg")
    else
        # 转换路径参数为 Windows 格式
        win_args+=("$(cygpath -w "$arg" 2>/dev/null || echo "$arg")")
    fi
done

# 执行 VS Code 并传递处理后的参数
if [ ${#win_args[@]} -eq 0 ]; then
    # 无参数时直接启动
    "/cygdrive/c/Program Files/Microsoft VS Code/bin/code"
else
    # 带参数启动（保持参数顺序）
    "/cygdrive/c/Program Files/Microsoft VS Code/bin/code" "${win_args[@]}"
fi
