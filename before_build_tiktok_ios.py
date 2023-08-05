#!/usr/bin/env python3

import io, os, re, sys

print('''说明：使用此脚本的前提是TikTok、TTLiveStreamer、TTLiveStreamerCore都是源码，且都位于脚本当前工作目录。
由于要修改CocoaPods目录中的TTFFmpeg头文件，请用超级用户身份运行此脚本，即：sudo before_build_tiktok_ios.py。''')

# 从tiktok的Podfile.seer中读取它当前依赖的ttffmpeg版本号
def read_ttffmpeg_version():
    f = open('TikTok/Aweme/Podfile.seer', 'r')
    lines = f.readlines()
    f.close()
    for line in lines:
        matchObj = re.search('TTFFmpeg *\((.*), *from', line)
        if matchObj:
            return matchObj.group(1)
    return None

ttffmpeg_version = read_ttffmpeg_version()
print('TTFFmpeg version: ' + str(ttffmpeg_version))

def get_ttffmpeg_header_dir():
    home_dir = os.getenv('HOME')
    dir = home_dir + '/Library/Caches/CocoaPods/v1/Pods/Release/TTFFmpeg/'
    for item in os.listdir(dir):
        path = os.path.join(dir, item)
        if (ttffmpeg_version in item) and os.path.isdir(path):
            return path + '/TTFFmpeg.framework/Headers/'
    return None

ttffmpeg_header_dir = get_ttffmpeg_header_dir()
print('TTFFmpeg header dir: ' + str(ttffmpeg_header_dir))

file_map = {
    'TTLiveStreamerCore/TTLiveStreamerCore.podspec': {
        "# (sub\.dependency 'BMFMods)": '\g<1>'
    },
    'TTLiveStreamerCore/avframework/src/cpp/base/include/PlatformUtils.h': {
        '(?<!//)static const TEBundle': '//\g<0>'
    },
    'TTLiveStreamerCore/avframework/src/cpp/engine/source/siti/siti.cc': {
        r'#include "libavutil': r'#include "TTFFmpeg/libavutil'
    },
    ttffmpeg_header_dir + 'libavutil/common.h': {
        r'#include "libavutil': r'#include "TTFFmpeg/libavutil'
    },
    ttffmpeg_header_dir + 'libavutil/pixfmt.h': {
        r'#include "libavutil': r'#include "TTFFmpeg/libavutil'
    },
    ttffmpeg_header_dir + 'libswresample/swresample.h': {
        r'#include "libavutil': r'#include "TTFFmpeg/libavutil',
        r'#include "libswresample': r'#include "TTFFmpeg/libswresample'
    },
    ttffmpeg_header_dir + 'libswresample/version.h': {
        r'#include "libavutil': r'#include "TTFFmpeg/libavutil'
    }
}

if __name__ == '__main__':
    if (not ttffmpeg_version) or (not ttffmpeg_header_dir):
        sys.exit('fail to get TTFFmpeg.')
    for file_name, items in file_map.items():
        try:
            f = io.open(file_name,'r+', newline='')
            content = f.read()
            for pattern, replace in items.items():
                content = re.sub(pattern, replace, content)
            f.seek(0)
            f.truncate()
            f.write(content)
            f.close()
        except FileNotFoundError as e:
            print(e)

