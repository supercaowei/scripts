#!/usr/bin/env python3

import sys

def sort_file(filename):
    # 读取所有行
    with open(filename, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    # 按字符串升序排序（区分大小写）
    lines.sort()
    
    # 写回原文件
    with open(filename, 'w', encoding='utf-8') as f:
        f.writelines(lines)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("错误：请指定文本文件路径作为参数")
        print("示例：python script.py your_file.txt")
        sys.exit(1)
    
    input_file = sys.argv[1]
    sort_file(input_file)
    print(f"文件 {input_file} 已按字典序排序并覆盖保存")
    