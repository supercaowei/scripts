#!/usr/bin/env python3

import json, argparse, copy

def merge_json(json1, json2):
    if json1 is None:
        return json2
    if json2 is None:
        return json1
    json_dest = copy.deepcopy(json1)
    for key in json2.keys():
        value1 = json1[key] if (key in json1.keys()) else None
        value2 = json2[key]
        if value1 is not None:
            if isinstance(value1, dict) and isinstance(value2, dict):
                json_dest[key] = merge_json(value1, value2)
            elif isinstance(value1, list) and value2 is not None:
                dest_list = copy.deepcopy(value1)
                if (isinstance(value2, list)):
                    dest_list.extend(value2)
                else:
                    dest_list.append(value2)
                json_dest[key] = dest_list
            else:
                json_dest[key] = value2
        else:
            json_dest[key] = value2
    return json_dest

def parseArgs():
    parser = argparse.ArgumentParser()
    parser.add_argument("--json_content1", help="要合并的第1个json内容")
    parser.add_argument("--json_content2", help="要合并的第2个json内容")
    parser.add_argument("--json_file1", help="要合并的第1个json文件路径")
    parser.add_argument("--json_file2", help="要合并的第2个json文件路径")
    parser.add_argument("--json_file_dest", help="合并后要写入的json文件路径")
    args = parser.parse_args()
    # print(args)
    return args

def main():
    args = parseArgs()
    json_content1 = args.json_content1
    json_content2 = args.json_content2
    if json_content1 is None and args.json_file1 is not None:
        f = open(args.json_file1, "r")
        json_content1 = f.read()
        f.close()
    if json_content2 is None and args.json_file2 is not None:
        f = open(args.json_file2, "r")
        json_content2 = f.read()
        f.close()
    json1 = json.loads(json_content1)
    json2 = json.loads(json_content2)
    json_dest = merge_json(json1, json2)
    if args.json_file_dest is not None:
        f = open(args.json_file_dest, "w")
        f.write(json.dumps(json_dest, indent=4))
        f.close()
    else:
        print(json.dumps(json_dest, indent=4))

def tests():
    json1 = json.loads('''
    {
        "json1Only1": "a",
        "both1": {
            "both1both1": {
                "both1both1both1": 4
            },
            "both1both2": 6789,
            "both1json1Only1": 46,
            "both1both3": [
                4356,
                "ccc"
            ],
            "both1both4": [
                69,
                "ddd"
            ]
        },
        "both2": {
            "both2json1Only1": 56
        },
        "both3": ["sss"]
    }''')

    json2 = json.loads('''
    {
        "json2Only1": "b",
        "both1": {
            "both1both1": {
                "both1both1both1": 88
            },
            "both1both2": "heihei",
            "both1json2Only1": 345,
            "both1both3": [
                578,
                "eee"
            ],
            "both1both4": {
                "both1both4json2Only1": "fff"
            }
        },
        "both2": [
            "ggg",
            76
        ],
        "both3": null
    }''')
    print(json.dumps(merge_json(json1, json2), indent=4))

if __name__ == "__main__":
    # tests()
    main()
