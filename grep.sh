#!/usr/bin/env bash

grepGroup() {
    content=$1 #被grep查找的内容
    echo $content
    # if [[ "$content" =~ "\"real_video_framerate\":[0-9]+" ]]; then 
    if [[ "$content" =~ "real_video_framerate" ]]; then 
        echo ${BASH_REMATCH[0]}
    else
        echo "not match"
    fi
}

adb logcat | xargs echo
