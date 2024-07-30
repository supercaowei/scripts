#!/usr/bin/env python3

import sys

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("请指定一个要颠倒其内容的文件路径")
    file_path = sys.argv[1]
    # file_path = "/Users/CaoWei/temp/1.txt"
    with open(file_path, 'r') as f:
        lines = f.readlines()
    #最后一行没有换行符，就加上换行符
    if len(lines) > 0 and not lines[-1].endswith('\n'):
        lines[-1] += '\n'
    with open(file_path, 'w') as f:
        for line in reversed(lines):
            f.write(line)
