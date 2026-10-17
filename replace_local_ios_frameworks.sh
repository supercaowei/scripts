#!/bin/bash
set -euo pipefail

SRC_DIR="${SRC_DIR:-${PWD}/build/ios/Debug}"
RTCLIVE_DST_DIR="${RTCLIVE_DST_DIR:-/Users/CaoWei/Work/Aweme_iOS_bak/Aweme/Aweme/Pods/RTCLiveSDK}"
BYTEAUDIO_DST_DIR="${BYTEAUDIO_DST_DIR:-/Users/CaoWei/Work/Aweme_iOS_bak/Aweme/Aweme/Pods/ByteAudio}"

replace_framework() {
  local src="$1"
  local dst_dir="$2"
  local name="$3"
  local src_framework_dir="$src/$name"
  local dst_framework_dir="$dst_dir/$name"

  [ -d "$src_framework_dir" ] || { echo "missing dir: $src_framework_dir"; exit 1; }
  [ -d "$dst_dir" ] || { echo "missing dir: $dst_dir"; exit 1; }

  mkdir -p "$dst_framework_dir"
  rm -rf "$dst_framework_dir"/*
  cp -R "$src_framework_dir"/* "$dst_framework_dir/"
  echo "replaced: $src_framework_dir/* -> $dst_framework_dir/"
}

[ -d "$SRC_DIR" ] || { echo "missing dir: $SRC_DIR"; exit 1; }
[ -d "$RTCLIVE_DST_DIR" ] || { echo "missing dir: $RTCLIVE_DST_DIR"; exit 1; }
[ -d "$BYTEAUDIO_DST_DIR" ] || { echo "missing dir: $BYTEAUDIO_DST_DIR"; exit 1; }

replace_framework "$SRC_DIR" "$RTCLIVE_DST_DIR" "RTCLive.framework"
replace_framework "$SRC_DIR" "$RTCLIVE_DST_DIR" "RTCLiveExtensions.framework"
replace_framework "$SRC_DIR" "$RTCLIVE_DST_DIR" "RTCLiveScreenCapturer.framework"

replace_framework "$SRC_DIR" "$BYTEAUDIO_DST_DIR" "ByteAudio.framework"
replace_framework "$SRC_DIR" "$BYTEAUDIO_DST_DIR" "RTCLiveAudioExtensions.framework"
replace_framework "$SRC_DIR" "$BYTEAUDIO_DST_DIR" "StreamCore.framework"

echo "all done"
