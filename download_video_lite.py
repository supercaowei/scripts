import os
import sys
import csv
import time
#import utils
import argparse
import subprocess
import traceback
from os.path import basename
import datetime
from const_tool import set_ffmpeg_dir,get_ffmpeg_version, get_ffprobe_version
from utils import run_command
from parse_video_info import parse_media_info_basic
import requests 
import json
if sys.version_info >= (3,):
    import pandas as pd
    #import libsvm.python.libsvm.svm
    import csv
else:
    import csv

if sys.version_info >= (3,):
    import urllib.request as urllib2
    from urllib import parse
else:
    import urllib2
    import urlparse as parse

def ffmpeg_download(url, video_filename, duration=120, starttime=0):
    ffmpeg = get_ffmpeg_version()
    ff_cmd = "%s -y -hide_banner -ss %d -i \'%s\' -t %d -an -vcodec copy -f mp4 %s" % (ffmpeg, starttime, url, duration, video_filename)
    print(ff_cmd)
    output, return_code = run_command(ff_cmd)
    
    audio_info, video_info, meta_info = parse_media_info_basic(video_filename, get_ffprobe_version())
    return int(video_info['duration'])
    
def urllib2_download(url, video_filename, duration = 120):
    response = urllib2.urlopen(url, timeout=3)
    CHUNK = 64 * 1024
    with open(video_filename, 'wb') as f:
        oldtime=datetime.datetime.now()
        newtime=datetime.datetime.now()
        while (newtime-oldtime).seconds < duration:
            chunk = response.read(CHUNK)
            if not chunk:
                break
            f.write(chunk)
            newtime=datetime.datetime.now()
    
    return (newtime-oldtime).seconds


def download_one_video_from_link(url, video_filename, duration=120, force=False, method='urllib', starttime=0):
    retries = 3
    status = 0
    if len(str(url)) < 10:
        print("Invalid url link: %s" % url)
    elif not os.path.exists(video_filename) or force:
        if method == 'urllib':
            with open(video_filename, "wb") as f:
                for i in range(retries):
                    try:
                        seconds = urllib2_download(url, video_filename, duration)
                        print("urllib Downloaded video: %s duration: %d" % (video_filename.split('/')[-1], seconds))
                        status = 1
                        break
                    except Exception as err:
                        print("Retry to download video %s: %s" % (video_filename.split('/')[-1], err))
                        #time.sleep(5)
        elif method == 'ffmpeg':
            try:
                seconds = ffmpeg_download(url, video_filename, duration,starttime)
                print("ffmpeg Downloaded video: %s duration: %d" % (video_filename.split('/')[-1], seconds))
                status = 1
            except Exception as err:
                print("Retry to download video %s: %s" % (video_filename.split('/')[-1], err))
                time.sleep(5)
        else:
            cmd = 'wget --timeout 7200 -O %s %s' % (video_filename, url)
            print('Download: %s' % cmd)
            os.system(cmd)
    else:
        status = 1
        print("Video exists: %s" % video_filename.split('/')[-1])

    if status == 0:
        os.remove(video_filename)
        return None

    return video_filename, seconds

roomid_headers = {
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9',
    'Accept-Encoding': 'gzip, deflate',
    'Accept-Language': 'zh-CN,zh;q=0.9', 
    'Cache-Control': 'max-age=0',   
    'Connection': 'keep-alive',
    'Host': 'neptune-sg.byted.org',
    'Upgrade-Insecure-Requests': '1',
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.60 Safari/537.36'
}

def get_roomid_record_info(room_id):
    query_url = "http://neptune-sg.byted.org/neptune/platform/v2/stream/detail?Stream=&RoomID=%s" % (room_id)
    payload_info = "Stream=&RoomID=%s" % (room_id)
    stream_name = ''
    account_id = ''
    # query Stream and AccountID
    try:
        print(query_url)
        #print(payload_info)
        response = requests.get(query_url, headers=roomid_headers, data=payload_info)
        output = json.loads(response.text)
        #print(output)
        results = output['Result']['StreamDetails']
        for i in range(len(results)):
            stream_name = results[i]['Stream']
            account_id = results[i]['AccountID']
            break;        
    except Exception as err:
        print('room info query Stream and AccountID not successful')
        print(err)
        return '','',0
    
                
    # query record url
    query_url = "http://neptune-sg.byted.org/neptune/platform/v2/stream/record?AppID=&Stream=%s&AccountID=%s&Limit=-1" % (stream_name,account_id)
    payload_info = "AppID=&Stream=%s&AccountID=%s&Limit=-1" % (stream_name,account_id)
    record_url = ''
    duration = 0
    try:
        print(query_url)
        #print(payload_info)
        response = requests.get(query_url, headers=roomid_headers, data=payload_info)
        output = json.loads(response.text)
        #print(output)
        results = output['Result']['Records']
        for i in range(len(results)):
            record_url = results[i]['URL']
            duration = float(results[i]['Duration'])
            break;        
    except Exception as err:
        print('room info query Stream and AccountID not successful')
        print(err)
        return '','',0

    return record_url, stream_name, duration

def download_batch_video_from_roomid_info(input_file, video_sum, output_folder, output_info, min_resolution=-1,  starttime=0, duration=120, force=False):
    min_file_duration = starttime + duration + 120
    if os.path.isfile(output_info):
        row_info = pd.read_csv(output_info)
    else:
        stats_row = ['room_id', 'src_url', 'dst_filename', 'duration', 'starttime']
        row_info = pd.DataFrame(index=range(0), columns=stats_row)

    if os.path.isfile(input_file):
        if video_sum > 0:
            df = pd.read_csv(input_file,nrows=video_sum)
        else:
            df = pd.read_csv(input_file) 

        room_ids = df['room_id'].values
        print('Number of image/video files to download: %d min_file_duration: %d' % (len(room_ids), min_file_duration))
        i = 0
        count = len(row_info)
        for i in range(len(room_ids)):
            print('download %d / %d complele download %d' % (i, len(room_ids), len(row_info)))
            room_id = room_ids[i]   
            media_url, stream_name, dst_duration  = get_roomid_record_info(room_id)
            if dst_duration <= min_file_duration:
                print('unvalid room_id:%s dst_duration:%f, skip' % (room_id, dst_duration))
                continue
            
            print('start download count:%d room_id:%s, media_url:%s dst_duration:%f' % (len(row_info),room_id, media_url, dst_duration))
            try:
                output_file = '%s/%s.mp4' % (output_folder, stream_name) 
                
                audio_info, video_info, meta_info = parse_media_info_basic(media_url, get_ffprobe_version())
                if int(video_info['width']) < min_resolution or int(video_info['height']) < min_resolution:    
                    print("unvalid resolution skip url=%s, width=%d, height=%d" % (media_url, int(video_info['width']), int(video_info['height'])))  
                    continue     

                # 判断 output_file 是否存在
                if os.path.exists(output_file): 
                    indexs = row_info[row_info.dst_filename == output_file].index
                    if len(indexs) > 0:
                        print("file exist skip url=%s, local file=%s" % (media_url, output_file))
                    else:
                        print("file exist skip url=%s, local file=%s add item" % (media_url, output_file))
                        audio_info, video_info, meta_info = parse_media_info_basic(output_file, get_ffprobe_version())
                        row_info.loc[count] = [room_id, media_url, output_file, int(video_info['duration']), int(video_info['duration'])]
                        count = count + 1                        
                    continue    
                else:
                    output, seconds = download_one_video_from_link(media_url, output_file, duration, force, 'ffmpeg', starttime)
                    if output == None:
                        print("failed to download url=%s" % media_url)
                        continue
                
            except Exception as err:
                print("Error on %d: %s" % (i, err))
                continue   
            row_info.loc[count] = [room_id, media_url, output_file, seconds, starttime]
            count = count + 1

    row_info.to_csv(output_info, index=False, encoding='utf-8')

def download_batch_video_from_file_info(input_file, output_folder, output_info, source='live', duration=120, force=False, method='urllib'):
    if os.path.isfile(output_info):
        row_info = pd.read_csv(output_info)
    else:
        stats_row = ['video_path', 'filename', 'duration', 'play_count']
        row_info = pd.DataFrame(index=range(0), columns=stats_row)

    if os.path.isfile(input_file):
        df = pd.read_csv(input_file)

        video_file_sum = df['url'].values
        play_counts = df['play_count'].values

        print('Number of image/video files to download: %d' % len(video_file_sum))
        i = 0
        count = len(row_info)
        for i in range(len(video_file_sum)):
            
            print('download %d / %d complele download %d' % (i, len(video_file_sum), len(row_info)))

            video_file = video_file_sum[i]
            
            print('start download count:%d play_count:%s path:%s' % (len(row_info), play_counts[i],video_file))

            try:
                url_list = parse.urlparse(video_file)
                if source == 'record':
                    head_tail = os.path.split(url_list.path)
                    output_file = '%s/%s.mp4' % (output_folder, head_tail[0].replace("/","_")) 
                else:
                    output_file = '%s/%s' % (output_folder, basename(url_list.path))

                # 判断 output_file 是否存在
                if os.path.exists(output_file): 
                    indexs = row_info[row_info.filename == output_file].index
                    if len(indexs) > 0:
                        print("file exist skip url=%s, local file=%s", video_file, output_file)
                    else:
                        print("file exist skip url=%s, local file=%s add item", video_file, output_file)
                        audio_info, video_info, meta_info = parse_media_info_basic(output_file, get_ffprobe_version())
                        row_info.loc[count] = [video_file, output_file, int(video_info['duration']), play_counts[i]]
                        count = count + 1                        
                    continue    
                else:
                    output, seconds = download_one_video_from_link(video_file, output_file, duration, force, method)
                    if output == None:
                        print("failed to download url=%s", video_file)
                        continue
                
            except Exception as err:
                print("Error on %d: %s" % (i, err))
                continue
            
            row_info.loc[count] = [video_file, output_file, seconds, play_counts[i]]
            count = count + 1

    row_info.to_csv(output_info, index=False, encoding='utf-8')

def parse_cfg():
    parser = argparse.ArgumentParser(description="Download videos based on url", formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument("-i", "--input_file", help="Txt file to store a list of vids", default=None)
    parser.add_argument("-o", "--output_folder", help="Folder to store downloaded video/log (No download if output_folder not specified)", default=None)
    parser.add_argument("-f", "--list", help="File to store path/name of downloaded video", default=None)
    parser.add_argument("-s", "--video_sum", help="download sum video", default=-1, type=int)
    parser.add_argument("-t", "--top_sum", help="sum of top play", default=50, type=int)
    parser.add_argument("-p", "--play_count", help="min play count of url to download", default=50, type=int)
    parser.add_argument("--force", help="Force to re-download the video",  action="store_true", default=False)
    parser.add_argument("--method", help="Download method", default='urllib', choices=['urllib', 'wget', 'ffmpeg'])
    parser.add_argument("--tool_dir", help="Dir of ffmpeg and ffprobe", default="example/")
    parser.add_argument("--source", help="source of stream", default="live")
    parser.add_argument("--file_duration", help="download file duration", default=120)
    parser.add_argument("--starttime", help="starttime rtc info", default=120)
    parser.add_argument("--endtime", help="endtime rtc info", default=120)
    parser.add_argument("--min_resolution", help="min resolution", default=-1)
    args = parser.parse_args()
    print(args)
    return args


if __name__ == "__main__":
    cfgs = parse_cfg()
    
    set_ffmpeg_dir(cfgs.tool_dir)
    download_batch_video_from_roomid_info(cfgs.input_file, cfgs.video_sum, cfgs.output_folder, cfgs.list, int(cfgs.min_resolution), int(cfgs.starttime), int(cfgs.file_duration), False)
 