#!/usr/bin/env python3

import sys, os, re

def parseRawVideoParams(fileName):
    ret = []
    regex = r'(\d+)x(\d+)[x_](\d+)'
    matchObj = re.search(regex, fileName)
    if matchObj:
        ret.append(matchObj.group(1))
        ret.append(matchObj.group(2))
        ret.append(matchObj.group(3))
    else:
        sys.exit("请在文件名中指明视频的分辨率和帧率，形如\"宽x高x帧率\"或\"宽x高_帧率\"。例如\"1280x720x30\"、\"720x1280_60\"。")
    return ret

def parsePcmAudioParams(fileName):
    '''
    f32be           PCM 32-bit floating-point big-endian
    f32le           PCM 32-bit floating-point little-endian
    f64be           PCM 64-bit floating-point big-endian
    f64le           PCM 64-bit floating-point little-endian
    s16be           PCM signed 16-bit big-endian
    s16le           PCM signed 16-bit little-endian
    s24be           PCM signed 24-bit big-endian
    s24le           PCM signed 24-bit little-endian
    s32be           PCM signed 32-bit big-endian
    s32le           PCM signed 32-bit little-endian
    s8              PCM signed 8-bit
    u16be           PCM unsigned 16-bit big-endian
    u16le           PCM unsigned 16-bit little-endian
    u24be           PCM unsigned 24-bit big-endian
    u24le           PCM unsigned 24-bit little-endian
    u32be           PCM unsigned 32-bit big-endian
    u32le           PCM unsigned 32-bit little-endian
    u8              PCM unsigned 8-bit
    '''

    ret = []
    regex = r'[fsu](16|24|32|64)([lb]e)?|s8|u8'
    matchObj = re.search(regex, fileName)
    if matchObj:
        ret.append(matchObj.group(0))
        endian = matchObj.group(2)
        if endian is None and ret[0] != 'u8' and ret[0] != 's8': #没有指明大小端，就默认为小端
            ret[0] = ret[0] + 'le'
    else: #没有指明格式，就默认为s16le
        ret.append('s16le')
    regex = r'(\d{5,6})(hz)?_(\d{1,2})'
    matchObj = re.search(regex, fileName)
    if matchObj:
        ret.append(matchObj.group(1))
        ret.append(matchObj.group(3))
    else:
        sys.exit("请在文件名中指明PCM的格式、采样率和通道数，形如\"格式_采样率_通道数\"。例如\"s16le_44100hz_1ch\"。")
    return ret

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("请指定一个raw音视频文件路径")
    rawFilePath = sys.argv[1]
    (dir1, name) = os.path.split(rawFilePath)
    (nameNoExt, ext) = os.path.splitext(name)
    supportExt = ['.yuv', '.rgba', '.argb', '.nv12', '.pcm']
    if ext not in supportExt:
        sys.exit("仅支持以下文件类型: " + str(supportExt))
    
    if ext == '.yuv' or ext == '.rgba' or ext == '.argb' or ext == '.nv12':
        ret = parseRawVideoParams(nameNoExt)
        pixFmt = {'.yuv': 'yuv420p', '.rgba': 'rgba', '.argb': 'argb', '.nv12': 'nv12'}
        cmd = 'ffplay -f rawvideo -pixel_format ' + pixFmt[ext] + ' -video_size ' + ret[0] + 'x' + ret[1] + ' -framerate ' + ret[2] + ' -i \"' + rawFilePath + '\"'
        print(cmd)
        os.system(cmd)
    elif ext == '.pcm':
        ret = parsePcmAudioParams(nameNoExt)
        cmd = 'ffplay -f ' + ret[0] + ' -ar ' + ret[1] + ' -ac ' + ret[2] + ' -i \"' + rawFilePath + '\"'
        print(cmd)
        os.system(cmd)
        