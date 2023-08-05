#!/usr/bin/env bash

function printHelp() {
    echo "说明："
    echo "    1. 此脚本用于单个raw视频文件或一个目录中所有的raw视频文件进行旋转或翻转操作"
    echo "    2. 使用前，先给脚本添加可执行权限（执行一次即可）：chmod +x TransposeRawVideo.sh"
    echo "用法："
    echo "    ./TransposeRawVideo.sh <SRC_DIR/SRC_FILE> <DEST_DIR> <DEGREE/FLIP>"
    echo "参数："
    echo "    SRC_DIR：被旋转/翻转的所有yuv|rgba|bgra|nv12|nv21文件所在目录"
    echo "    SRC_FILE：被旋转/翻转的单个yuv|rgba|bgra|nv12|nv21文件路径"
    echo "    DEST_DIR：旋转/翻转后的yuv|rgba|bgra|nv12|nv21文件保存到的目录，可与SRC_DIR或SRC_FILE所在目录相同，也可不存在（会自动创建）"
    echo "    DEGREE：顺时针旋转角度（可选值0, 90, 180, 270），可为空，为空时默认原始拷贝"
    echo "    FLIP：翻转类型（可选值vflip, hflip）"
}

srcDir=$1
dstDir=$2
degree=$3

if [[ "${degree}x" = "x" ]]; then
    degree=0
fi

if [[ -f ${srcDir} ]]; then #${srcDir}是文件
    slashIndex=`echo "${srcDir}" | awk -F "/" '{printf "%d", length($0)-length($NF)-1}'`
    srcfiles=(${srcDir:${slashIndex}+1}) #单一文件
    srcDir=`dirname ${srcDir}`
elif [[ -d ${srcDir} ]]; then #${srcDir}是目录
    srcfiles=$(ls ${srcDir})
fi

if [[ $# = 0 || ! -d ${srcDir} || (${degree} != 0 && ${degree} != 90 && ${degree} != 180 \
        && ${degree} != 270 && ${degree} != "vflip" && ${degree} != "hflip") ]]; then 
    printHelp
    exit
fi

echo "SRC_DIR: ${srcDir}"
echo "DEST_DIR: ${dstDir}"
echo "DEGREE/FLIP: ${degree}"

transpose=""
switchWH=0
suffix2=""
if [[ ${degree} = "vflip" || ${degree} = "hflip" ]]; then
    transpose="-vf ${degree} "; suffix2="${degree}" #水平翻转/垂直翻转
else
    #先将degree规范到0~360再除以90
    case $(( (((${degree} % 360) + 360) % 360) / 90 )) in
        0) suffix2="copy";; #不旋转
        1) transpose="-vf transpose=1 "; switchWH=1; suffix2="rotate90";; #顺时针旋转90度
        2) transpose="-vf hflip,vflip "; suffix2="rotate180";; #顺时针旋转180度（水平和垂直都翻转）
        3) transpose="-vf transpose=2 "; switchWH=1; suffix2="rotate270";; #顺时针旋转270度（即逆时针旋转90度）
    esac
fi
#echo ${transpose}, ${switchWH}

regex="([0-9]+)x([0-9]+)([x_])([0-9]+)(.*)\.(yuv|rgba|bgra|nv12|nv21)$"
for file in ${srcfiles[@]}
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
        dstPath="${dstDir}/${prefix}${width}x${height}${underscore}${fps}${suffix}_${suffix2}.${extension}"
        cmd="ffmpeg -f rawvideo -pix_fmt ${pixFmt} -s ${BASH_REMATCH[1]}x${BASH_REMATCH[2]} -i ${srcDir}/${file} ${transpose} -f rawvideo -pix_fmt ${pixFmt} -v quiet -y ${dstPath}"
        echo ${cmd}
        ${cmd}
    else
        echo "文件${file}后缀不是\"yuv|rgba|bgra|nv12|nv21\"，或格式不符合\"宽x高x帧率\""
    fi
done
