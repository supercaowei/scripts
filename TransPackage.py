#!/usr/bin/env python3

import argparse, sys, os, re, urllib.parse

# 2:15转为2m15s，1:30:00转为1h30m00s
def convert_time(time):
    ret = ''
    c = 'smh'
    i = 0
    r = len(time) #right
    while r > 0 and i < len(c):
        l = time.rfind(r':', 0, r) #left
        ret = time[(0 if (l < 0) else (l + 1)):r] + c[i] + ret
        r = l
        i += 1
    return ret

ff_formats = {'flv': 'flv', 'mp4': 'mp4', 'mkv': 'matroska'}

def transpackage(input, start_time, duration, end_time, format, output):
    if not input:
        sys.exit("请在 -i 选项后指定被转封装的url或文件路径")
    if duration and end_time:
        sys.exit("不能同时指定截取时长和截取结束时间点")

    probe_cmd = 'ffprobe_v265 -v error -hide_banner -print_format flat -select_streams v:0 '\
            '-show_entries stream=codec_name "' + input + '"'
    # print(probe_cmd)
    fd = os.popen(probe_cmd)
    codec_name_str = fd.read()
    fd.close()
    codec_name = None
    match = re.search('codec_name="(.+)"', codec_name_str)
    if match:
        codec_name = match.group(1)
    if not codec_name:
        sys.exit("解析视频编码格式失败")
    is_hevc = 'hevc' in codec_name.lower() or '265' in codec_name.lower()

    if not output:
        url = urllib.parse.unquote(input) #url解码，%2F转/
        parsed_url = urllib.parse.urlparse(url) #parsed_url.path形如/obj/dir1/dir2/filename.ext
        output = os.path.basename(parsed_url.path) #filename形如filename.ext
        output = os.path.splitext(output)[0]
    output = output + (('_from' + convert_time(start_time)) if start_time else '')\
        + (('_duration' + convert_time(duration)) if duration else '')\
        + (('_to' + convert_time(end_time)) if end_time else '')\
        + '.' + format
    # print('output: ' + output)

    transpackage_cmd = 'ffmpeg_v265 ' \
            + (('-ss ' + start_time + ' ') if start_time else '')\
            + (('-t ' + duration + ' ') if duration else '')\
            + (('-to ' + end_time + ' ') if end_time else '')\
            + '-i "' + input + '" -c copy '\
            + ('-tag:v hvc1 ' if (is_hevc and not format == 'flv') else '')\
            + '-f ' + ff_formats[format] + ' "' + output + '"'
    print(transpackage_cmd)
    fd = os.popen(transpackage_cmd)
    fd.close()

def parseArgs():
    parser = argparse.ArgumentParser()
    parser.add_argument("-i", help="要被转封装的url或文件路径")
    parser.add_argument("-ss", help="要截取的起始时间点")
    parser.add_argument("-t", help="要截取的时长")
    parser.add_argument("-to", help="要截取的结束时间点")
    parser.add_argument("-f", help="要转封装的目标格式，未指定则为mp4", default='mp4', choices=['flv', 'mp4', 'mkv'])
    parser.add_argument("-o", help="被转封装后的文件名")
    args = parser.parse_args()
    print(args)
    return args

def main():
    args = parseArgs()
    input = args.i
    start_time = args.ss
    duration = args.t
    end_time = args.to
    format = args.f
    output = args.o
    transpackage(input, start_time, duration, end_time, format, output)

if __name__ == "__main__":
    main()
