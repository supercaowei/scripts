#!/usr/bin/env bash

grepGroup() {
    content=$1 #被grep查找的内容
    if [[ "$content" =~ "\"real_video_framerate\":[0-9]+"; then 
        echo ${BASH_REMATCH[0]}; 
    else
        echo "not match"
    fi
}

echo -e "a\nb"
regex="\n"
if [[ "\n" =~ $regex ]]; then
    echo match
else
    echo not match
fi
