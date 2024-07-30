#!/usr/bin/env python3

import argparse, re 

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("-i", "--input_file", help="输入的要检查sei的文本文件")
    parser.add_argument("-s", "--start_index", help="起始sei index", default=int(1))
    args = parser.parse_args()
    print(args)
    return args

def check_sei(input_file, start_index):
    index = start_index
    line_num = 1
    file = open(input_file, "r")
    line_content = file.readline()
    while line_content:
        if re.search(r'"sei_index":{0}\D'.format(index), line_content):
            index += 1
        else:
            match_obj = re.search(r'"sei_index":(\d+)', line_content)
            if (match_obj):
                new_index = int(match_obj.group(1))
                if new_index - index == 1:
                    print(r'第{0}行之前，"sei_index":{1}丢失'.format(line_num, index))
                else:
                    print(r'第{0}行之前，"sei_index":{1} ~ "sei_index":{2}丢失'.format(line_num, index, new_index - 1))
                index = new_index + 1
            else:
                print(r'第{0}行不含"sei_index"'.format(line_num))
        line_content = file.readline()
        line_num += 1
    file.close()

if __name__ == "__main__":
    args = parse_args()
    if args.input_file is not None and args.start_index is not None:
        check_sei(args.input_file, args.start_index)
