#!/usr/bin/env bash

playUrl=$1
if [[ ${playUrl} =~ ^(rtmp.*|http.*\.sdp.*) ]]; then
    playUrl=`PushUrl2PullUrl.py $1`
fi

CMD=ffprobe
if [[ ${playUrl} =~ ".flv" ]]; then
    CMD=ffprobe_v265
fi

# echo "${CMD} -select_streams v -print_format xml -show_entries frame=pict_type,pts,pkt_pos -i \"${playUrl}\" | grep \"pict_type\""
${CMD} -select_streams v -print_format xml -show_entries frame=pict_type,pts,pkt_pos -i "${playUrl}" | grep "pict_type"
