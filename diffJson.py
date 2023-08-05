#!/usr/bin/env python3

import json, argparse, re, sys

#请将文档中的参数内容粘贴到source_json中
source_json = r'''
{"PushBase":{"minBitrate":1000000,"expectFps":15,"enable_siti":true,"enableAudioLowLatency":true,"audioIOBufferDuration":"0.01","enable_video_adaptor":0,"timestampSynMode":1,"enableSetOpenGOP":false,"width":1088,"mixOnClient":{"enable":true,"byte":{"normal":100,"share_video":100,"video_talk_camera":100,"ktv_camera":100,"multi_anchor":100,"fm":100,"ktv":100,"share_video_pri":100,"video_talk":100,"pk":100,"equal_talk_room":100},"agora":{"pk":100,"fm":100,"normal":100,"video_talk":100,"share_video":100,"share_video_pri":100,"video_talk_camera":100}},"siti_strategy_ver":3,"live_fallback_fps":true,"adm_type":1,"defaultBitrate":2500000,"enableBFrame":false,"audioProfile":"HE","sync_start_publish":false,"sched_expr":"rts_push_anchor_config_tencent","height":1920,"enc_strategy_config":{"bitrate_ratios":"0.69|0.79|0.88|1|0.7|0.8|0.9|1|0.7|0.8|0.9|1|0.7|0.8|0.9|1","category_params":"0.042|0.084|0.114|0.045|0.091|0.124|0.045|0.091|0.124|0.045|0.091|0.124","fps_ratios":"1|1|1|1|0.9|1|1|1|0.9|1|1|1|1|1|1|1,15","qulity_mode":1,"strategy_adjust_mode":3},"enableSeiCurrentShiftDiffTime":true,"enableSimultaneousVideoInput":true,"adm_use_ios15_bugfix":true,"interact_fallback_fps":true,"enableBlackFrameOptimization":true,"vCodec":"bytevc1","frameRateMode":1,"videoProfile":"high","siti_config":{"thread_count":1,"using_gpu":false,"extract_duration":5,"frames_counts_calc_siti":25,"drop_encode_fps":true,"period_ms":20000},"adm_server_cfg":{"engine_BAC":{"agc":{"sw":false},"adm":{"play":{"sr":44100,"chn":2},"record":{"chn":2,"sr":44100}},"aec":{"sw":false,"type":3,"delay_mode":1,"headset_level":0,"hw":true,"level":2},"ans":{"headset_level":0,"hw":false,"level":1,"sw":false,"type":2},"version":"3.30-BA"}},"alog":"alog","fallback_fps_map":{"720P":15,"1080P":20,"360P":15,"540P":15},"enableNewUpdateSendCacheConfig":true,"useHardware":true,"qId":"BlackFrameOptimization","adm_use_1810_code":true,"maxBitrate":3800000,"enableAudioLoudnessToSei":1,"fps":20,"enableManualHEAACConfigPacket":true,"videoDenoise":{"denoiseLevel":75,"abStrategy":33,"bitrateRatio":0.95,"coexistWithLens":true},"useSelfDevelopedRtmp":true,"gopSec":2,"vEncImpl":2},"rtmp_cache_cfg":{"audio_send_stall_threshold":200,"video_send_stall_threshold":200,"enable_report_stall_log":1,"max_interleave_delta":1000000,"enable_refactor_report_net_info":1,"enable_report_bw_time":1,"enable_rtmp_stopPoll":1},"RtcBase":{"RtcMixBase":{"bitrate":1200000},"RtcBase":{"width":360,"height":640,"fps":15,"bitrate":800000},"ByteRtcExtInfo":{"defaultSignalingServerFirst":1}},"Switch":{"enableVideoInfoStatistic":true,"pkChangeResolution":true},"Interact":{"interactServerMixUsingBFrame":0}}
'''

#请将线上直播的开播参数内容粘贴到dest_json中
dest_json= r'''
{"Switch":{"enableVideoInfoStatistic":true,"pkChangeResolution":true,"rtmNetReport":true},"Interact":{"interactServerMixUsingBFrame":0},"Common":{"enableProtocolDegrade":true},"PushBase":{"maxBitrate":3800000,"qId":"bFrameBitrateRatio90","useSelfDevelopedRtmp":true,"gopSec":2,"fallback_fps_map":{"1080P":20,"360P":15,"540P":15,"720P":15},"enableAudioLowLatency":true,"height":1920,"audioProfile":"HE","videoDenoise":{"abStrategy":33,"bitrateRatio":0.95,"denoiseLevel":75,"coexistWithLens":true},"useHardware":true,"width":1088,"enableNewUpdateSendCacheConfig":true,"enableBlackFrameOptimization":true,"enableManualHEAACConfigPacket":true,"adm_use_ios15_bugfix":true,"adm_server_cfg":{"engine_BAC":{"ans":{"hw":false,"level":1,"sw":false,"type":2,"headset_level":0},"version":"3.30-BA","agc":{"sw":false},"adm":{"record":{"chn":2,"sr":44100},"play":{"chn":2,"sr":44100}},"aec":{"delay_mode":1,"headset_level":0,"hw":true,"level":2,"sw":false,"type":3}}},"video_adapter_enable_smooth":true,"video_bitrate_rectify_params":{"bitrate_rectify_interval":1,"low_bitrate_ratio_thresh":0.1,"bitrate_rectify_check_count":6,"bitrate_rectify_method":1},"enable_video_adaptor":0,"siti_config":{"using_gpu":false,"extract_duration":5,"frames_counts_calc_siti":25,"period_ms":20000,"drop_encode_fps":true,"thread_count":1},"videoBitrateLimitRate":1.2,"enableSimultaneousVideoInput":true,"siti_strategy_ver":3,"minBitrate":1000000,"audioIOBufferDuration":"0.01","sync_start_publish":false,"enc_strategy_config":{"strategy_adjust_mode":3,"bitrate_ratios":"0.69|0.79|0.88|1|0.7|0.8|0.9|1|0.7|0.8|0.9|1|0.7|0.8|0.9|1","category_params":"0.042|0.084|0.114|0.045|0.091|0.124|0.045|0.091|0.124|0.045|0.091|0.124","fps_ratios":"1|1|1|1|0.9|1|1|1|0.9|1|1|1|1|1|1|1,15","qulity_mode":1},"defaultBitrate":2500000,"enable_siti":true,"videoProfile":"high","mixOnClient":{"byte":{"fm":100,"multi_anchor":100,"share_video_pri":100,"normal":100,"video_talk":100,"equal_talk_room":100,"pk":100,"ktv_camera":100,"share_video":100,"video_talk_camera":100,"ktv":100},"agora":{"video_talk":100,"share_video":100,"share_video_pri":100,"video_talk_camera":100,"pk":100,"fm":100,"normal":100},"enable":true},"enableSeiCurrentShiftDiffTime":true,"alog":"alog","interact_fallback_fps":true,"enableSetOpenGOP":false,"vEncImpl":2,"expectFps":15,"fps":20,"enableAudioLoudnessToSei":1,"timestampSynMode":1,"rtsConfig":"{\"avts_check_enable\":false,\"dynamic_min_bwe\":true,\"enable_br_smooth\":true,\"enable_max_br_inc\":true,\"max_scale_factor\":1.1,\"ptsdts_check\":true,\"realx_cfg\":{\"engine_VNM\":{\"bwest\":{\"enable_audio_tcc\":true,\"enable_dec_smoothing\":true,\"enable_rtm_push_cc_opt\":true,\"gcc\":{\"enable_delaybwe\":true,\"overuse_thresh_time\":100}},\"pacer\":{\"pacer_times\":2.5},\"use_old_configure\":false}},\"rtm_rc\":true,\"sig_query\":\"tcc=true\u0026fir=0\u0026ntp_enable=false\u0026buffer_level=6\",\"sig_timeout_ms\":10000}","vCodec":"bytevc1","adm_type":1,"adm_use_1810_code":true,"live_fallback_fps":true,"bFrameBitrateRatio":0.9,"enableBFrame":true,"frameRateMode":1},"rtmp_cache_cfg":{"video_send_stall_threshold":200,"enable_report_stall_log":1,"max_interleave_delta":1000000,"enable_refactor_report_net_info":1,"enable_report_bw_time":1,"enable_rtmp_stopPoll":1,"audio_send_stall_threshold":200},"RtcBase":{"RtcMixBase":{"bitrate":1200000},"RtcBase":{"width":360,"height":640,"fps":15,"bitrate":800000},"ByteRtcExtInfo":{"defaultSignalingServerFirst":1}}}
'''

def minus_dict(dest, src):
    if (not isinstance(dest, dict)) or (not isinstance(src, dict)):
        return None if type(dest) == type(src) else dest
    diff = {}
    for k, v in dest.items():
        if k not in src.keys():
            diff[k] = v
        else:
            src_v = src[k]
            sub_diff = minus_dict(v, src_v)
            if (isinstance(sub_diff, dict) and bool(sub_diff)) or \
                    (not isinstance(sub_diff, dict) and sub_diff is not None):
                diff[k] = sub_diff
    return diff

def main():
    global source_json, dest_json
    source_json = re.sub('//.*', '', source_json)
    # print(source_json)
    # dest_json = re.sub('//.*', '', dest_json)
    # print(dest_json)
    try:
        source_dict = json.loads(source_json)
    except Exception as e :
        sys.exit("source_json删除注释后不是标准的json格式：\n" + source_json)
    try:
        dest_dict = json.loads(dest_json)
    except Exception as e :
        sys.exit("dest_json删除注释后不是标准的json格式：\n" + dest_json)
    
    diff_dict = minus_dict(dest_dict, source_dict)
    print("dest_json比source_json多出的内容：\n" + json.dumps(diff_dict, indent=4))

if __name__ == "__main__":
    main()
