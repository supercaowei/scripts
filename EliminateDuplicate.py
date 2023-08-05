#!/usr/bin/env python3

import argparse

def eliminateDuplicate(filePath, caseInsensitive):
    file = open(filePath, "r+")
    stringList = file.read().split("\n")
    stringList2 = []
    string = ""

    for str in stringList:
        strCmp = str.lower() if caseInsensitive else str
        if not strCmp in stringList2:
            stringList2.append(strCmp)
            string += ("" if (string == "") else "\n") + str
        else:
            print ("Find duplicate string: " + str)

    file.seek(0)
    file.truncate()
    file.write(string)
    file.close()

def minusSameLine(filePath1, filePath2, caseInsensitive):
    file = open(filePath1, "r+")
    stringList = file.read().split("\n")
    string = ""
    file2 = open(filePath2, "r")
    minusContent = file2.read().lower() if caseInsensitive else file2.read()
    stringList2 = minusContent.split("\n")
    file2.close()

    for str in stringList:
        strCmp = str.lower() if caseInsensitive else str
        if not strCmp in stringList2:
            string += ("" if (string == "") else "\n") + str
        else:
            print ("Eliminate string: " + str)

    file.seek(0)
    file.truncate()
    file.write(string)
    file.close()

def parseArgs():
    parser = argparse.ArgumentParser()
    parser.add_argument("-i", "--input_file", help="输入的要被去重的文本文件")
    parser.add_argument("-m", "--minus_file", help="输入要从被去重文件中删除的内容组成的文本文件")
    parser.add_argument("-c", "--case_insensitive", action='store_true', help="字符串比较时，是否忽略大小写")
    args = parser.parse_args()
    print(args)
    return args

def printUsage():
    print("usage:")
    print("① 对单个文件以行(hang)为单位进行去重：")
    print("  EliminateDuplicate.py -i <file_path>")
    print("② 从file_path1文件中删除存在于file_path2的行：")
    print("  EliminateDuplicate.py -i <file_path1> -m <file_path2>")

def main():
    args = parseArgs()
    if args.input_file is not None:
        if args.minus_file is None:
            eliminateDuplicate(args.input_file, args.case_insensitive)
        else:
            minusSameLine(args.input_file, args.minus_file, args.case_insensitive)
    else:
        printUsage()

if __name__ == "__main__":
    main()
