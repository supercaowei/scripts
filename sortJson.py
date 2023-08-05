#!/usr/bin/env python3

import json, argparse

def sort_dict_recursively(d):
    for key in d.keys():
        if isinstance(d[key], dict):
            d[key] = sort_dict_recursively(d[key])
    return dict(sorted(d.items(), key=lambda x: x[0]))

def sort_json_content(json_content):
    json_dict = json.loads(json_content)
    json_dict = sort_dict_recursively(json_dict)
    return json.dumps(json_dict, indent=4)

def sort_json_file(json_file):
    f = open(json_file, "r+")
    json_content = f.read()
    json_content = sort_json_content(json_content)
    f.seek(0)
    f.truncate()
    f.write(json_content)
    f.close()

def parseArgs():
    parser = argparse.ArgumentParser()
    parser.add_argument("-j", "--json_content", help="直接输入要排序的json内容")
    parser.add_argument("-f", "--json_file", help="输入要排序的json文件")
    args = parser.parse_args()
    # print(args)
    return args

def main():
    args = parseArgs()
    if args.json_content is not None:
        print(sort_json_content(args.json_content))
    if args.json_file is not None:
        sort_json_file(args.json_file)

if __name__ == "__main__":
    main()
