#!/usr/bin/env python3

'''
说明：本脚本用于检验抖音和MT Android/iOS双端秀场直播流的视频参数是否正确
'''

import os, sys, re, subprocess, time, urllib.parse, json, cmath, math, traceback

tool_dir = ''
work_dir = ''
overseas = False
infos = []
errors = []

class MyException(Exception):
    def __init__(self, msg):
         self.message = msg
    def __str__(self):
        return self.message

def download_flv_stream(pull_url):
    pull_url = urllib.parse.unquote(pull_url) #url解码
    pull_url = re.sub(r"(\\)*\/", r'/', pull_url) #去除转义
    if overseas:
        pull_url = pull_url.replace('http://', 'https://')
    pos1 = pull_url.rfind('/')
    if pos1 == -1:
        raise MyException("拉流地址中没有找到/，请检查是否正确。")
    pos2 = pull_url.find('.flv', pos1 + 1)
    if pos2 == -1:
        raise MyException("拉流地址中没有找到.flv，请检查是否正确。")
    file_name = pull_url[pos1 + 1:pos2 + 4]
    file_path = work_dir + '/' + file_name

    if not os.path.exists(file_path):
        cmd = 'curl -s \"' + pull_url + '\" -o ' + file_path
        print('后台下载60s，请耐心等待：' + cmd)
        pipe = subprocess.Popen(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(60)
        pipe.kill() #停止下载

        if not os.path.exists(file_path) or os.path.getsize(file_path) == 0:
            if os.path.exists(file_path):
                os.remove(file_path)
            raise MyException('文件下载失败，请确认拉流地址正确且正在直播。')
        else:
            print('文件下载成功：' + file_path)
    else:
        print('文件已存在：' + file_path)

    return file_path

encoders = [
    {'name': '未知编码器', "max_b_frames": 0, "profile": "unknown"},           #0
    {'name': 'Android H.264硬编', "max_b_frames": 0, "profile": "high"},      #1
    {'name': 'Android H.265硬编', "max_b_frames": 0, "profile": "main"},      #2
    {'name': 'x264软编', "max_b_frames": 2, "profile": "high"},               #3
    {'name': '自研ByteVC0软编', "max_b_frames": 0, "profile": "main"},         #4
    {'name': '自研ByteVC1软编', "max_b_frames": 3, "profile": "main"},         #5
    {'name': 'iOS H.264硬编', "max_b_frames": 0, "profile": "high"},          #6
    {'name': 'iOS H.265硬编', "max_b_frames": 0, "profile": "main"}           #7
]

def checkEncoder(platform, codec_id, hardware):
    if platform == 'android':
        if codec_id == 12: #H.265编码
            if hardware == 1:
                return 2
            else:
                return 5
        else: #H.264编码
            if hardware == 1:
                return 1
            elif overseas:
                return 4
            else:
                return 3
    else: #iOS
        if codec_id == 12: #H.265编码
            return 7
        else: #H.264编码
            return 6
    return 0

def parseMetadata(file_path):
    metadata = os.popen(tool_dir + '/SimpleFlvParser -i ' + file_path + ' -print_metadata').read()
    start_pos = metadata.find('metadata:')
    if start_pos == -1:
        raise MyException('flv中未发现metadata。')
    end_pos = metadata.find('metadata:', start_pos + 9) #找下一个"metadata:"
    if end_pos == -1:
        end_pos = len(metadata)
    metadata = metadata[metadata.find('[', start_pos, end_pos) : metadata.rfind(']', start_pos, end_pos) + 1]
    json_metadata = json.loads(metadata)[1]
    print('\nmetadata: ' + json.dumps(json_metadata))

    infos.append('地区：' + ('海外' if overseas else '国内'))
    infos.append('系统：' + json_metadata['platform'])
    infos.append('机型：' + json_metadata['model'])
    infos.append('系统版本：' + json_metadata['os_version'])
    infos.append('SDK版本：' + json_metadata['sdk_version'])

    platform = json_metadata['platform'].lower()
    codec_id = int(json_metadata['videocodecid'])
    hardware = int(json_metadata['is_hardware_encode'])
    encoder_index = checkEncoder(platform, codec_id, hardware)
    infos.append('编码器：' + encoders[encoder_index]['name'])
    json_metadata['encoder_index'] = encoder_index

    width = int(json_metadata['width'])
    height = int(json_metadata['height'])
    infos.append('分辨率：' + str(width) + 'x' + str(height))

    min_bitrate = int(json_metadata['min_bitrate'])
    default_bitrate = int(json_metadata['default_bitrate'])
    max_bitrate = int(json_metadata['max_bitrate'])
    infos.append('码率：' + str(min_bitrate) + 'kbps, ' + str(default_bitrate) + 'kbps, ' + str(max_bitrate) + 'kbps')
    resolution_sqrt = cmath.sqrt(width * height).real #看起来码率和分辨率的平方根更接近正比关系
    if not (min_bitrate < default_bitrate and default_bitrate < max_bitrate):
        errors.append('metadata中的min_bitrate ' + str(min_bitrate) + ', default_bitrate ' + str(default_bitrate) + '和max_bitrate ' + str(max_bitrate) + '大小关系不对。')
    if max_bitrate < resolution_sqrt:
        errors.append('metadata中的max_bitrate ' + str(max_bitrate) + 'kbps用于' + str(width) + 'x' + str(height) + '可能过低。')
    if min_bitrate > resolution_sqrt * 5:
        errors.append('metadata中的min_bitrate ' + str(min_bitrate) + 'kbps用于' + str(width) + 'x' + str(height) + '可能过高。')

    if 'framerate' in json_metadata.keys():
        framerate = int(json_metadata['framerate'])
        infos.append('帧率：' + str(framerate) + 'fps')
        if framerate < 15 or framerate > 100:
            errors.append('metadata中的framerate ' + str(framerate) + 'fps可能不对。')

    gop = json_metadata['interval']
    infos.append('GOP：' + str(gop) + '秒')
    if int(gop) != 2:
        errors.append('metadata中的GOP预期为2秒，实际为' + str(gop) + '秒')

    if 'Encoder' in json_metadata.keys():
        auth_string = json_metadata['Encoder']
        if not auth_string.startswith('bytedmediasdk'):
            infos.append('校验串（Encoder）：' + auth_string + '，不符合预期。')
    else:
        infos.append('校验串（Encoder）：无')

    return json_metadata

def collect_count(dic, key):
    if key in dic.keys():
        dic[key] += 1
    else:
        dic[key] = 1

def parseVideoFrames(file_path, metadata):
    frame_num = 0 #帧数
    max_b_frames = 0 #最大连续B帧数
    b_frame_num = 0
    pix_fmt = {} #像素格式
    pix_fmt_yuv420p = True
    color_range = {} #颜色空间
    first_frame_pts = 0 #首帧pts
    final_frame_pts = 0 #最后一帧pts
    last_i_frame_pts = 0 #上一个I帧的pts
    i_frame_intervals = {} #I帧间隔
    real_bitrates = {} #实际码率
    real_framerates = {} #实际帧率
    
    #解析视频流信息
    encoder_index = metadata['encoder_index']
    stream_info = json.loads(os.popen(tool_dir + '/ffprobe_v265 -v quiet -show_streams -select_streams v \"' \
        + file_path + '\" -print_format json').read())['streams'][0]
    print('\nstream_info: ' + json.dumps(stream_info))
    
    profile = stream_info['profile']
    infos.append('profile：' + profile)
    expected_profile = encoders[encoder_index]['profile']
    if profile.lower() != expected_profile.lower():
        errors.append('profile不符合预期：预期是' + str(expected_profile) + '，实际是' + str(profile))

    if 'framerate' not in metadata.keys():
        avg_framerate_str = stream_info['avg_frame_rate'] #平均帧率
        real_framerate_str = stream_info['r_frame_rate'] #真实帧率
        framerate = 0
        for framerate_str in [avg_framerate_str, real_framerate_str]:
            try:
                if '/' in framerate_str:
                    fractions = framerate_str.split('/')
                    framerate = round(float(fractions[0]) / float(fractions[1]), 2)
                else:
                    framerate = round(float(framerate_str), 2)
                break
            except BaseException as e:
                continue
        if framerate == 0:
            errors.append('metadata和流信息中都没有有效的帧率字段。')
        metadata['framerate'] = framerate
        infos.append('帧率：' + str(framerate) + 'fps')

    #解析每一帧
    frames = json.loads(os.popen(tool_dir + '/ffprobe_v265 -v quiet -show_frames -select_streams v \"' \
        + file_path + '\" -print_format json').read())['frames']
    frame_num = len(frames)
    for frame in frames:
        if frame['pict_type'] == 'B':
            b_frame_num += 1
        else:
            max_b_frames = b_frame_num if b_frame_num > max_b_frames else max_b_frames
            b_frame_num = 0
        
        pts = float(frame['pkt_pts_time'])
        if first_frame_pts == 0:
            first_frame_pts = pts
        final_frame_pts = pts

        if frame['pict_type'] == 'I':
            if last_i_frame_pts != 0:
                interval = pts - last_i_frame_pts
                interval = round(interval, 1)
                collect_count(i_frame_intervals, interval)
            last_i_frame_pts = pts
        
        collect_count(pix_fmt, frame['pix_fmt'])
        if frame['pix_fmt'] != 'yuv420p':
            pix_fmt_yuv420p = False

        collect_count(color_range, frame['color_range'] if 'color_range' in frame.keys() else 'unknown')

    #解析SEI
    expected_min_bitrate = int(metadata['min_bitrate'])
    expected_max_bitrate = int(metadata['max_bitrate'])
    bitrate_total_count = 0
    bitrate_too_low_count = 0
    bitrate_too_high_count = 0
    seis = os.popen(tool_dir + '/SimpleFlvParser -i ' + file_path + ' -print_sei').readlines()
    for sei in seis:
        try:
            json_sei = json.loads(sei[sei.find('{') : sei.rfind('}') + 1])
            if 'real_bitrate' in json_sei.keys():
                bitrate = json_sei['real_bitrate']
                bitrate_too_low_count += (1 if bitrate < expected_min_bitrate - 100 else 0)
                bitrate_too_high_count += (1 if bitrate > expected_max_bitrate + 200 else 0)
                bitrate_total_count += 1
                collect_count(real_bitrates, round(bitrate, -2))

                framerate = int(json_sei['real_video_framerate'])
                collect_count(real_framerates, framerate)
        except BaseException as e:
            pass
    
    infos.append('帧数：' + str(frame_num))

    real_framerates = dict(sorted(real_framerates.items(), key=lambda item:item[1], reverse=True)) #按值从大到小排序
    real_framerate = round((frame_num - 1) / (final_frame_pts - first_frame_pts), 2)
    expected_framerate = metadata['framerate']
    infos.append('实际帧率：平均' + str(real_framerate) + ', ' + str(real_framerates))
    if math.fabs(real_framerate - expected_framerate) > 1.0:
        errors.append('实际帧率' + str(real_framerate) + 'fps与metadata中的帧率' + str(expected_framerate) + 'fps相差太大')
    
    i_frame_intervals = dict(sorted(i_frame_intervals.items(), key=lambda item:item[1], reverse=True)) #按值从大到小排序
    infos.append('实际I帧间隔：' + str(i_frame_intervals))
    most_count_interval = list(i_frame_intervals.keys())[0]
    expected_i_frame_interval = float(metadata['interval'])
    if math.fabs(most_count_interval - expected_i_frame_interval) > 0.11:
        errors.append('最多次出现的I帧间隔' + str(most_count_interval) + '秒与metadata中的GOP ' + str(expected_i_frame_interval) + '秒相差太大')

    infos.append('最大连续B帧数：' + str(max_b_frames))
    expected_max_b_frames = encoders[encoder_index]['max_b_frames']
    if max_b_frames != expected_max_b_frames:
        errors.append('最大连续B帧数不符合预期：预期是' + str(expected_max_b_frames) + '，实际是' + str(max_b_frames))

    real_bitrates = dict(sorted(real_bitrates.items(), key=lambda item:item[1], reverse=True)) #按出现次数从多到少排序
    infos.append('实际码率：' + str(real_bitrates))
    most_count_bitrate = list(real_bitrates.keys())[0]
    if most_count_bitrate < expected_min_bitrate - 100 or most_count_bitrate > expected_max_bitrate + 100:
        errors.append('最多次出现的码率' + str(most_count_bitrate) + 'kbps与metadata中的min_bitrate ' \
            + str(expected_min_bitrate) + 'kbps或max_bitrate' + str(expected_max_bitrate) + 'kbps不符。')
    if bitrate_total_count >= 10: #基数太少了没有意义
        if bitrate_too_low_count * 100 / bitrate_total_count > 60:
            errors.append('出现较多过低的码率，请检查推流端的网络情况，或者编码码率配置是否异常。')
        if bitrate_too_high_count * 100 / bitrate_total_count > 60:
            errors.append('出现较多过高的码率，请检查推流端编码器的码率控制是否有问题。')

    infos.append('像素格式：' + str(pix_fmt))
    if not pix_fmt_yuv420p:
        errors.append('存在非yuv420p的像素格式：' + str(pix_fmt))

    infos.append('颜色空间：' + str(color_range))

def print_usage():
    print('\n用法：')
    print('\t./checkVideoCodec.py \"<拉流地址>\"')
    print('参数说明：')
    print('\t1. 只接受一个参数。')
    print('\t2. 该参数必须是http或https开头且以.flv结尾的拉流地址，不要带上.flv后面的参数。')

def main():
    global tool_dir, work_dir, overseas, infos, errors
    tool_dir = sys.path[0]
    work_dir = tool_dir + '/temp'
    os.system('mkdir -p ' + work_dir)
    print('脚本目录：' + tool_dir)
    print('工作目录：' + work_dir)
    os.system('chmod +x ' + tool_dir + '/ff*')
    os.system('chmod +x ' + tool_dir + '/SimpleFlvParser')

    clear = input('是否删除工作目录中的所有文件？输入\"Y\"删除，输入其他任意键跳过：')
    if clear == 'Y':
        if work_dir.endswith('/temp') and len(work_dir) > 5:
            os.system('rm -f ' + work_dir + '/*')
            print('工作目录已清空')
        else:
            print('工作目录路径不正确，已跳过删除')

    if len(sys.argv) != 2:
        raise MyException('请用一个参数指定一个正在直播的拉流地址。')
    else:
        print('拉流地址：' + sys.argv[1])

    pull_url = sys.argv[1]
    overseas = pull_url.find('tiktok') != -1
    file_path = download_flv_stream(pull_url)
    metadata = parseMetadata(file_path)
    parseVideoFrames(file_path, metadata)

    print('\n信息：')
    for info in infos:
        print('\t' + info)

    if len(errors) == 0:
        print('\n无错误')
    else:
        print('\n错误：')
        for error in errors:
            print('\t' + error)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        if isinstance(e, MyException):
            print(e.message)
        else:
            traceback.print_exc() #打印异常堆栈
        print_usage() #打印用法
