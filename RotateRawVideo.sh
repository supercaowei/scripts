#!/usr/bin/env bash

function printHelp() {
    echo "先给脚本添加可执行权限（执行一次即可）：chmod +x RotateRawVideo.sh"
    echo "用法：./RotateRawVideo.sh <SRC_DIR> <DEST_DIR> <DEGREE>"
    echo "参数："
    echo "    SRC_DIR：被旋转的所有yuv|rgba|bgra|nv12|nv21文件所在目录"
    echo "    DEST_DIR：旋转后的yuv|rgba|bgra|nv12|nv21文件保存到的目录，不可与SRC_DIR相同"
    echo "    DEGREE：顺时针旋转角度（可选值0, 90, 180, 270），可为空，为空时默认旋转270（即逆时针旋转90度）"
}

srcDir=$1
dstDir=$2
degree=$3
if [[ "${degree}x" = "x" ]]; then
    degree=270
fi

if [[ $# = 0 || ! -d ${srcDir} || ${srcDir} -ef ${dstDir} || (${degree} != 0 && ${degree} != 90 && ${degree} != 180 && ${degree} != 270) ]]; then 
    printHelp
    exit
fi

echo "SRC_DIR: ${srcDir}"
echo "DEST_DIR: ${dstDir}"
echo "DEGREE: ${degree}"

transpose=""
switchWH=0
#先将degree规范到0~360再除以90
case $(( (((${degree} % 360) + 360) % 360) / 90 )) in
    0) ;; #不旋转
    1) transpose="-vf transpose=1 "; switchWH=1 ;; #顺时针旋转90度
    2) transpose="-vf hflip,vflip ";; #顺时针旋转180度（水平和垂直都翻转）
    3) transpose="-vf transpose=2 "; switchWH=1;; #顺时针旋转270度（即逆时针旋转90度）
esac
#echo ${transpose}, ${switchWH}

regex="([0-9]+)x([0-9]+)([x_])([0-9]+)(.*\.(yuv|rgba|bgra|nv12|nv21))$"
for file in $(ls ${srcDir})
do
    if [ -f "${srcDir}/${file}" ] && [[ ${file} =~ ${regex} ]]; then
        matched=${BASH_REMATCH[0]} #整个匹配到的串
        width=${BASH_REMATCH[1]}
        height=${BASH_REMATCH[2]}
        underscore=${BASH_REMATCH[3]}
        fps=${BASH_REMATCH[4]}
        suffix=${BASH_REMATCH[5]}
        extension=${BASH_REMATCH[6]}
        prefixIndex=$(x="${file%%${matched}*}"; echo ${#x}) #查找matched在file中的起始位置
        prefix=${file:0:prefixIndex} #前缀
        if [[ ${switchWH} != 0 ]]; then #交换宽高
            temp=${width}
            width=${height}
            height=${temp}
        fi
        pixFmt="unknown"
        if [[ ${extension} == "yuv" ]]; then
            pixFmt="yuv420p"
        elif [[ ${extension} == "rgba" ]]; then
            pixFmt="rgba"
        elif [[ ${extension} == "bgra" ]]; then
            pixFmt="bgra"
        elif [[ ${extension} == "nv12" ]]; then
            pixFmt="nv12"
        elif [[ ${extension} == "nv21" ]]; then
            pixFmt="nv21"
        fi
        mkdir -p ${dstDir}
        dstPath=${dstDir}/${prefix}${width}x${height}${underscore}${fps}${suffix}
        # echo `pwd`
        cmd="ffmpeg -f rawvideo -pix_fmt ${pixFmt} -s ${BASH_REMATCH[1]}x${BASH_REMATCH[2]} -i ${srcDir}/${file} ${transpose} -f rawvideo -pix_fmt ${pixFmt} -v quiet -y ${dstPath}"
        echo ${cmd}
        ${cmd}
    else
        echo "文件${file}后缀不是\"yuv|rgba|bgra|nv12|nv21\"或格式不符合\"宽x高x帧率\""
    fi
done
