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

def calculateCropScale(srcW, srcH, dstW, dstH):
    cropScaleParams = ''
    stretch = srcW < dstW or srcH < dstH #是否需要拉伸
    if stretch: #先拉伸再裁剪
        scale = 1
        if srcW * dstH < srcH * dstW:
            scale = dstW / srcW
        else:
            scale = dstH / srcH
        scaleW = int(round(srcW * scale))
        scaleH = int(round(srcH * scale))
        cropScaleParams += ' -vf scale=' + str(scaleW) + ':' + str(scaleH)
        if scaleW != dstW or scaleH != dstH:
            x = int(round((scaleW - dstW) / 2))
            y = int(round((scaleH - dstH) / 2))
            cropScaleParams += ',crop=' + str(dstW) + ':' + str(dstH) + ':' + str(x) + ':' + str(y)
    else: #srcW >= dstW and srcH >= dstH，先裁剪再压缩
        cropW = srcW
        cropH = srcH
        if srcW * dstH != srcH * dstW: #宽高比不相等，需要裁剪
            scale = 1
            if srcW * dstH < srcH * dstW:
                scale = dstW / srcW
            else:
                scale = dstH / srcH
            cropW = int(round(dstW / scale))
            cropH = int(round(dstH / scale))
            x = int(round((srcW - cropW) / 2))
            y = int(round((srcH - cropH) / 2))
            cropScaleParams += ' -vf crop=' + str(cropW) + ':' + str(cropH) + ':' + str(x) + ':' + str(y)
        if cropW != dstW or cropH != dstH: #现在宽高比相等，但大小不一样，需要缩放
            cropScaleParams += ' -vf ' if len(cropScaleParams) == 0 else ','
            cropScaleParams += 'scale=' + str(dstW) + ':' + str(dstH)

    return cropScaleParams

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
    regex = r'(\d{5,6})_(\d{1,2})'
    matchObj = re.search(regex, fileName)
    if matchObj:
        ret.append(matchObj.group(1))
        ret.append(matchObj.group(2))
    else:
        sys.exit("请在文件名中指明PCM的格式、采样率和通道数，形如\"格式_采样率_通道数\"。例如\"s16le_44100_1\"。")
    return ret

if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("请指定一个源raw音视频文件路径和一个目标raw音视频文件路径")
    srcRawFilePath = sys.argv[1]
    dstRawFilePath = sys.argv[2]
    (srcDir, srcName) = os.path.split(srcRawFilePath)
    (srcNameNoExt, srcExt) = os.path.splitext(srcName)
    (dstDir, dstName) = os.path.split(dstRawFilePath)
    (dstNameNoExt, dstExt) = os.path.splitext(dstName)
    supportRawVideoExt = ['.yuv', '.rgba', '.argb', '.nv12', '.nv21']
    supportEncodedVideoExt = ['.h264', '.h265', '.mp4']
    supportRawAudioExt = ['.pcm']
    supportExt = supportRawVideoExt + supportRawAudioExt
    if (srcExt in supportRawVideoExt) and (dstExt in supportEncodedVideoExt):
        pass#
    elif (srcExt not in supportExt) or (dstExt not in supportExt):
        sys.exit("源文件仅支持以下文件类型: " + str(supportExt) + "，目标文件仅支持以下文件类型：" + str(supportExt + supportEncodedVideoExt))
    
    if (srcExt in supportRawVideoExt) and (dstExt in supportEncodedVideoExt):
        pixFmt = {'.yuv': 'yuv420p', '.rgba': 'rgba', '.argb': 'argb', '.nv12': 'nv12', '.nv21': 'nv21'}
        encoders = {'.h264': 'libx264', '.h265' : 'libx265', '.mp4': 'libx264'}
        encodedFmt = {'.h264': 'h264', '.h265' : 'hevc', '.mp4': 'mp4'}
        srcRet = parseRawVideoParams(srcNameNoExt)
        cmd = 'ffmpeg -f rawvideo -pix_fmt ' + pixFmt[srcExt] + ' -video_size ' + srcRet[0] + 'x' + srcRet[1] + ' -framerate ' + srcRet[2] + ' -i \"' + srcRawFilePath + '\"' \
              + ' -vcodec ' + encoders[dstExt] + ' -crf 0 -f ' + encodedFmt[dstExt] + ' \"' + dstRawFilePath + '\"'
        print(cmd)
        os.system(cmd)
    elif (srcExt in supportRawVideoExt) and (dstExt in supportRawVideoExt):
        pixFmt = {'.yuv': 'yuv420p', '.rgba': 'rgba', '.argb': 'argb', '.nv12': 'nv12', '.nv21': 'nv21'}
        srcRet = parseRawVideoParams(srcNameNoExt)
        dstRet = parseRawVideoParams(dstNameNoExt)
        extraParams = sys.argv[3] if len(sys.argv) >= 4 else None
        if extraParams is None:
            extraParams = calculateCropScale(int(srcRet[0]), int(srcRet[1]), int(dstRet[0]), int(dstRet[1]))
        cmd = 'ffmpeg -f rawvideo -pix_fmt ' + pixFmt[srcExt] + ' -video_size ' + srcRet[0] + 'x' + srcRet[1] + ' -framerate ' + srcRet[2] + ' -i \"' + srcRawFilePath + '\"' \
              + extraParams + ' -f rawvideo -pix_fmt ' + pixFmt[dstExt] + ' -video_size ' + dstRet[0] + 'x' + dstRet[1] + ' -framerate ' + dstRet[2] + ' \"' + dstRawFilePath + '\"'
        print(cmd)
        os.system(cmd)
    elif srcExt == '.pcm' and dstExt == '.pcm':
        srcRet = parsePcmAudioParams(srcNameNoExt)
        dstRet = parsePcmAudioParams(dstNameNoExt)
        cmd = 'ffmpeg -f ' + srcRet[0] + ' -ar ' + srcRet[1] + ' -ac ' + srcRet[2] + ' -i \"' + srcRawFilePath + '\"' \
              + ' -f ' + dstRet[0] + ' -ar ' + dstRet[1] + ' -ac ' + dstRet[2] + ' \"' + dstRawFilePath + '\"'
        print(cmd)
        os.system(cmd)
        