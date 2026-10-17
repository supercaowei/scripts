#!/usr/bin/env bash

set -euo pipefail

# 当前脚本所在目录。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 用户指定的 RTCLive 仓库绝对路径。
REPO_ROOT=""

# 用户请求的构建目标，默认编译 watchcat。
REQUEST_TARGET="watchcat"
# 是否请求构建 Android。
REQUEST_ANDROID=0
# 是否请求构建 iOS。
REQUEST_IOS=0
# 是否请求构建 Harmony。
REQUEST_HARMONY=0
# 是否在构建前清理目标平台输出目录。
REQUEST_CLEAN=0
# 是否在未清理时跳过 CMake preset 步骤。
NO_PRESET=0
# 是否禁用 iOS/Harmony 签名，并跳过安装启动。
NO_SIGN=0

# Android demo 包名。
ANDROID_PACKAGE_NAME=""
# Android demo apk 产物路径。
ANDROID_APK_PATH=""
# Android 构建目录。
ANDROID_BUILD_DIR=""
# Android JNI 生成代码目录。
ANDROID_JNI_GEN_DIR=""
# Android rtcengine aar 产物路径。
ANDROID_RTCENGINE_AAR_PATH=""

# Harmony demo bundle 名称。
HARMONY_BUNDLE_NAME=""
# Harmony demo 启动 ability 名称。
HARMONY_ABILITY_NAME="EntryAbility"
# Harmony demo hap 产物路径。
HARMONY_HAP_PATH=""
# Harmony hap 输出目录。
HARMONY_HAP_DIR=""
# Harmony CMake 构建目录。
HARMONY_BUILD_DIR=""
# Harmony entry 模块构建目录。
HARMONY_ENTRY_BUILD_DIR=""
# Harmony rtcengine har 产物路径。
HARMONY_RTCENGINE_HAR_PATH=""
# Harmony DevEco SDK 根目录，可由环境变量覆盖。
HARMONY_DEVECO_SDK_HOME="${HARMONY_DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
# Harmony 构建所需工具链 PATH 前缀。
HARMONY_TOOL_PATH_PREFIX="/Applications/DevEco-Studio.app/Contents/tools:/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin:/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin"
# Harmony 安装超时时间，单位秒。
HARMONY_INSTALL_TIMEOUT_SEC="${HARMONY_INSTALL_TIMEOUT_SEC:-30}"
# Harmony 已安装包状态检测的宽限时间，单位秒。
HARMONY_INSTALL_DETECT_GRACE_SEC="${HARMONY_INSTALL_DETECT_GRACE_SEC:-3}"

# iOS demo scheme 名称。
IOS_SCHEME_NAME="WatchCat"
# iOS rtcengine scheme 名称。
IOS_RTCENGINE_SCHEME_NAME="RTCLive"
# iOS/Harmony 签名脚本路径。
IOS_SIGNING_SCRIPT=""
# iOS 签名备份 JSON 路径，按仓库目录映射到独立备份子目录。
IOS_SIGNING_BACKUP=""
# iOS 构建目录。
IOS_BUILD_DIR=""
# iOS xcarchive 输出路径。
IOS_ARCHIVE_PATH=""
# iOS ipa 导出目录。
IOS_EXPORT_DIR=""
# iOS exportOptions plist 路径。
IOS_EXPORT_PLIST_PATH=""
# iOS ipa 组包中转目录，内部会生成 Payload。
IOS_EXTRACT_DIR=""
# iOS rtcengine framework 产物路径。
IOS_RTCENGINE_FRAMEWORK_PATH=""

# 打印普通日志。
log() {
  echo "[build_rtclive] $*"
}

# 判断 warning/highlight 日志是否启用终端颜色。
warning_color_enabled() {
  if [[ -n "${NO_COLOR:-}" ]]; then
    return 1
  fi

  if [[ -n "${FORCE_COLOR:-}" && "${FORCE_COLOR}" != "0" ]]; then
    return 0
  fi

  [[ -t 2 ]]
}

# 打印高亮但非 warning 语义的信息。
highlight_info() {
  if warning_color_enabled; then
    printf '\033[33m[build_rtclive] %s\033[0m\n' "$*" >&2
    return 0
  fi

  echo "[build_rtclive] $*" >&2
}

# 打印 warning 日志。
warn() {
  if warning_color_enabled; then
    printf '\033[33m[build_rtclive] warning: %s\033[0m\n' "$*" >&2
    return 0
  fi

  echo "[build_rtclive] warning: $*" >&2
}

# 打印错误并退出。
die() {
  echo "[build_rtclive] error: $*" >&2
  exit 1
}

# 打印脚本用法说明。
usage() {
  cat <<'USAGE'
Usage:
  build_rtclive.sh [--clean] [--no_preset] [--no_sign] [--target <rtcengine|watchcat>]
      [--dir <RTCLive directory>]
      [--os <android|ios|harmony|android,ios|android,harmony|ios,harmony|all>]

Examples:
  build_rtclive.sh
  build_rtclive.sh --no_preset --os all
  build_rtclive.sh --no_sign --os ios,harmony
  build_rtclive.sh --clean --os harmony
  build_rtclive.sh --target watchcat --dir ./ --os android,ios
  build_rtclive.sh --dir ~/Work/RTCLiveDev --os harmony
USAGE
}

# 判断命令是否存在于 PATH 中。
have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# 校验指定文件或目录是否存在。
require_file() {
  # 需要存在的文件或目录路径。
  local path="$1"
  [[ -e "${path}" ]] || die "missing required file: ${path}"
}

# 删除并重建目录，保证目标目录是干净的。
ensure_dir_clean() {
  # 需要清空并重建的目录路径。
  local path="$1"
  rm -rf "${path}"
  mkdir -p "${path}"
}

# 如果目录存在则删除，否则仅打印跳过日志。
remove_dir_if_exists() {
  # 待删除目录路径。
  local path="$1"
  if [[ -e "${path}" ]]; then
    log "removing ${path}"
    rm -rf "${path}"
  else
    log "skip removing missing path ${path}"
  fi
}

# 通过签名脚本的 print-paths 子命令解析当前仓库对应的签名备份路径。
resolve_signing_backup_paths() {
  require_file "${IOS_SIGNING_SCRIPT}"

  eval "$(
    "${IOS_SIGNING_SCRIPT}" print-paths --dir "${REPO_ROOT}"
  )"

  IOS_SIGNING_BACKUP="${IOS_BACKUP}"
}

# 根据用户传入的仓库目录，解析所有平台的主路径和产物路径。
resolve_repo_root() {
  # 用户传入的 RTCLive 仓库目录。
  local repo_dir="$1"

  [[ -d "${repo_dir}" ]] || die "invalid --dir: ${repo_dir}"
  # 当前 RTCLive 仓库绝对路径。
  REPO_ROOT="$(cd "${repo_dir}" && pwd)"

  # Android Gradle/CMake 构建目录。
  ANDROID_BUILD_DIR="${REPO_ROOT}/build/android"
  # Android JNI 生成代码目录。
  ANDROID_JNI_GEN_DIR="${REPO_ROOT}/livecorepro/sdk/native/jni/gen"
  # Android apk 主产物路径。
  ANDROID_APK_PATH="${REPO_ROOT}/build/android/output/Android-Debug/Android-debug.apk"
  # Android rtcengine aar 主产物路径。
  ANDROID_RTCENGINE_AAR_PATH="${REPO_ROOT}/build/android/output/RtcEngine-Debug/RtcEngine-release.aar"
  # Harmony CMake 构建目录。
  HARMONY_BUILD_DIR="${REPO_ROOT}/build/harmony"
  # Harmony entry 模块构建目录。
  HARMONY_ENTRY_BUILD_DIR="${REPO_ROOT}/app/WatchCat/harmony/entry/build"
  # Harmony hap 输出目录。
  HARMONY_HAP_DIR="${HARMONY_ENTRY_BUILD_DIR}/default/outputs/default"
  # Harmony hap 主产物路径。
  HARMONY_HAP_PATH="${HARMONY_HAP_DIR}/entry-default-signed.hap"
  # Harmony rtcengine har 主产物路径。
  HARMONY_RTCENGINE_HAR_PATH="${REPO_ROOT}/sdk/arkts/RtcEngine/build/default/outputs/default/RtcEngine.har"
  # iOS/Harmony 公用签名脚本路径，从 build_rtclive.sh 同级目录查找。
  IOS_SIGNING_SCRIPT="${SCRIPT_DIR}/watchcat_demo_signing.sh"
  # iOS repo-scoped 签名备份 JSON 路径，由签名脚本统一计算。
  resolve_signing_backup_paths
  # iOS 构建目录。
  IOS_BUILD_DIR="${REPO_ROOT}/build/ios"
  # iOS xcarchive 输出路径。
  IOS_ARCHIVE_PATH="${IOS_BUILD_DIR}/output/WatchCat-Debug.xcarchive"
  # iOS ipa 导出目录。
  IOS_EXPORT_DIR="${IOS_BUILD_DIR}/output/WatchCat-debug-export"
  # iOS exportOptions plist 主路径。
  IOS_EXPORT_PLIST_PATH="${IOS_BUILD_DIR}/exportOptions.debug.plist"
  # iOS ipa 解压目录。
  IOS_EXTRACT_DIR="${IOS_EXPORT_DIR}/extracted"
  # iOS RTCLive.framework 主产物路径。
  IOS_RTCENGINE_FRAMEWORK_PATH="${IOS_BUILD_DIR}/Debug/RTCLive.framework"
}

# 统一设置 rtcpod 依赖的 Gemfile 环境变量。
normalize_rtc_bundle_gemfile() {
  export RTC_BUNDLE_GEMFILE="${RTC_BUNDLE_GEMFILE:-${REPO_ROOT}/build_system/env/gemfile}"
  export BUNDLE_GEMFILE="${RTC_BUNDLE_GEMFILE}"
}

# 去掉空白并转成小写，用于解析用户输入。
trim_and_lower() {
  # 待归一化的字符串。
  local value="$1"
  value="${value//[[:space:]]/}"
  printf '%s\n' "${value}" | tr '[:upper:]' '[:lower:]'
}

# 去掉外围双引号，统一字符串比较行为。
normalize_string() {
  # 待归一化的字符串。
  local value="$1"
  ruby -e 'value = ARGV[0].to_s; value = value.gsub(/\A"(.*)"\z/, "\1"); puts value' "${value}"
}

# 解析路径的真实落盘位置，用于处理 Xcode 产出的符号链接 .app。
resolve_real_path() {
  # 待解析的路径。
  local path="$1"

  have_cmd ruby || die "ruby not found in PATH"
  require_file "${path}"

  ruby -e 'puts File.realpath(ARGV[0])' "${path}"
}

# 将 Debug .app 直接封装为本地 ipa，兼容 signed/unsigned 两种产物。
package_ios_debug_ipa() {
  # Xcode 产出的 .app 路径，允许是符号链接。
  local app_link="$1"
  # 最终 ipa 输出路径。
  local ipa_path="$2"
  # 打包过程中使用的中转目录。
  local staging_dir="$3"
  # 解析后的 .app 真实路径。
  local app_real
  # Payload 目录路径。
  local payload_dir
  # 拷贝到 Payload 中的 .app 路径。
  local packaged_app_path

  have_cmd ditto || die "ditto not found in PATH"

  app_real="$(resolve_real_path "${app_link}")"
  require_file "${app_real}"

  ensure_dir_clean "${staging_dir}"
  payload_dir="${staging_dir}/Payload"
  mkdir -p "${payload_dir}"

  packaged_app_path="${payload_dir}/$(basename "${app_real}")"
  ditto "${app_real}" "${packaged_app_path}"

  rm -f "${ipa_path}"
  ditto -c -k --sequesterRsrc --keepParent "${payload_dir}" "${ipa_path}"
}

# 解析 Harmony 实际生成的 hap 产物，兼容 signed/unsigned 命名。
resolve_harmony_hap_path() {
  require_file "${HARMONY_HAP_DIR}"

  local candidate
  local preferred=(
    "${HARMONY_HAP_DIR}/entry-default-signed.hap"
    "${HARMONY_HAP_DIR}/entry-default-unsigned.hap"
    "${HARMONY_HAP_DIR}/entry-default.hap"
  )

  for candidate in "${preferred[@]}"; do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  candidate="$(
    find "${HARMONY_HAP_DIR}" -maxdepth 1 -type f -name '*.hap' | head -n 1
  )"
  [[ -n "${candidate}" ]] || die "failed to find Harmony hap artifact in ${HARMONY_HAP_DIR}"
  printf '%s\n' "${candidate}"
}

# 以普通日志打印产物路径。
log_artifact_path() {
  # 产物标签。
  local label="$1"
  # 产物实际路径。
  local path="$2"

  log "${label}: ${path}"
}

# 以高亮信息打印产物路径。
highlight_artifact_path() {
  # 产物标签。
  local label="$1"
  # 产物实际路径。
  local path="$2"

  highlight_info "${label}: ${path}"
}

# 获取第一台已连接的 Android 真机/设备 ID。
detect_android_device() {
  adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }'
}

# 获取第一台已连接的 Harmony 真机/设备 ID。
detect_harmony_device() {
  hdc list targets 2>/dev/null | tr -d "\r" | awk '
    NF == 0 { next }
    $1 == "[Empty]" { next }
    $1 ~ /^\[.*\]$/ { next }
    { print $1; exit }
  '
}

# 判断 Harmony 包是否已经安装到指定设备上。
harmony_package_installed() {
  # Harmony 设备 ID。
  local device_id="$1"

  hdc -t "${device_id}" shell bm dump -n "${HARMONY_BUNDLE_NAME}" 2>/dev/null \
    | grep -Eq "^${HARMONY_BUNDLE_NAME}:$"
}

# 按用户选择的平台删除构建输出目录。
clean_requested_platforms() {
  if [[ ${REQUEST_ANDROID} -eq 1 ]]; then
    remove_dir_if_exists "${ANDROID_BUILD_DIR}"
    remove_dir_if_exists "${ANDROID_JNI_GEN_DIR}"
  fi
  if [[ ${REQUEST_IOS} -eq 1 ]]; then
    remove_dir_if_exists "${IOS_BUILD_DIR}"
  fi
  if [[ ${REQUEST_HARMONY} -eq 1 ]]; then
    remove_dir_if_exists "${HARMONY_BUILD_DIR}"
    remove_dir_if_exists "${HARMONY_ENTRY_BUILD_DIR}"
  fi
}

# 安装 Harmony hap，并在已安装/超时等特殊情况下避免长时间挂起。
install_harmony_hap() {
  # Harmony 设备 ID。
  local device_id="$1"
  # 后台 hdc install 进程 ID。
  local install_pid=""
  # 当前安装轮询已消耗的秒数。
  local elapsed=0
  # 安装开始前该包是否已经存在于设备上。
  local package_was_installed=0

  if harmony_package_installed "${device_id}"; then
    package_was_installed=1
    log "Harmony package already present on ${device_id}, monitor install and exit once package state is confirmed"
  fi

  hdc -t "${device_id}" install -r "${HARMONY_HAP_PATH}" &
  install_pid=$!

  while kill -0 "${install_pid}" 2>/dev/null; do
    if [[ ${package_was_installed} -eq 0 ]]; then
      if harmony_package_installed "${device_id}"; then
        warn "Harmony package detected on device during install, stop waiting for hdc install"
        kill "${install_pid}" 2>/dev/null || true
        wait "${install_pid}" 2>/dev/null || true
        return 0
      fi
    elif (( elapsed >= HARMONY_INSTALL_DETECT_GRACE_SEC )); then
      if harmony_package_installed "${device_id}"; then
        warn "Harmony package remained installed after install grace period, stop waiting for hdc install"
        kill "${install_pid}" 2>/dev/null || true
        wait "${install_pid}" 2>/dev/null || true
        return 0
      fi
    fi

    if (( elapsed >= HARMONY_INSTALL_TIMEOUT_SEC )); then
      warn "Harmony install timed out after ${HARMONY_INSTALL_TIMEOUT_SEC}s"
      kill "${install_pid}" 2>/dev/null || true
      wait "${install_pid}" 2>/dev/null || true
      if harmony_package_installed "${device_id}"; then
        warn "Harmony package is present on device after timeout, continue"
        return 0
      fi
      return 124
    fi

    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "${install_pid}"
}

# 获取第一台已连接的 iOS 真机设备 ID。
detect_ios_device() {
  xcrun devicectl list devices | awk '
    NR <= 2 { next }
    $4 == "available" { print $3; exit }
  '
}

# 解析 iOS workspace 路径，兼容 xcworkspace 和 xcodeproj/project.xcworkspace 两种布局。
resolve_ios_workspace() {
  if [[ -d "${IOS_BUILD_DIR}/RTCLive.xcworkspace" ]]; then
    echo "${IOS_BUILD_DIR}/RTCLive.xcworkspace"
    return 0
  fi
  if [[ -d "${IOS_BUILD_DIR}/RTCLive.xcodeproj/project.xcworkspace" ]]; then
    echo "${IOS_BUILD_DIR}/RTCLive.xcodeproj/project.xcworkspace"
    return 0
  fi

  die "failed to locate iOS workspace under ${IOS_BUILD_DIR}"
}

# 在 build/ios 目录执行 rtcpod install，优先使用 PATH 中已有的 rtcpod。
run_rtcpod_install() {
  normalize_rtc_bundle_gemfile
  require_file "${RTC_BUNDLE_GEMFILE}"

  if have_cmd rtcpod; then
    log "running rtcpod install"
    (
      cd "${IOS_BUILD_DIR}"
      rtcpod install
    )
    return 0
  fi

  require_file "${REPO_ROOT}/build_system/scripts/rtcpod"
  log "running bundled rtcpod install"
  (
    cd "${IOS_BUILD_DIR}"
    /bin/bash "${REPO_ROOT}/build_system/scripts/rtcpod" install
  )
}

# 校验指定 workspace 中是否存在目标 scheme。
ensure_ios_scheme() {
  # iOS workspace 路径。
  local workspace="$1"
  # 期望存在的 scheme 名称。
  local scheme_name="$2"
  # xcodebuild -list 输出内容。
  local list_output

  list_output="$(xcodebuild -list -workspace "${workspace}" 2>/dev/null || true)"
  echo "${list_output}" | grep -Eq "(^|[[:space:]])${scheme_name}($|[[:space:]])" \
    || die "scheme ${scheme_name} not found in ${workspace}"
}

# 通过签名脚本回放 iOS 签名配置。
apply_ios_signing() {
  require_file "${IOS_SIGNING_SCRIPT}"
  log "applying iOS signing"
  "${IOS_SIGNING_SCRIPT}" recover --dir "${REPO_ROOT}" --os ios
}

# 通过签名脚本回放 Harmony 签名配置。
apply_harmony_signing() {
  require_file "${IOS_SIGNING_SCRIPT}"
  log "applying Harmony signing"
  "${IOS_SIGNING_SCRIPT}" recover --dir "${REPO_ROOT}" --os harmony
}

# 从 iOS 签名备份中提取 Debug 导出 ipa 所需的关键签名字段。
load_ios_debug_signing() {
  require_file "${IOS_SIGNING_BACKUP}"

  eval "$(
    ruby -rjson -rshellwords -e '
      data = JSON.parse(File.read(ARGV[0]))
      targets = data.fetch("targets")
      watchcat = targets.fetch("WatchCat").fetch("Debug").fetch("settings")
      screen = targets.fetch("WatchCatScreenShare").fetch("Debug").fetch("settings")
      mapping = {
        "IOS_DEBUG_SIGN_STYLE" => watchcat.fetch("CODE_SIGN_STYLE", ""),
        "IOS_DEBUG_TEAM_ID" => watchcat.fetch("DEVELOPMENT_TEAM", ""),
        "IOS_DEBUG_APP_BUNDLE_ID" => watchcat.fetch("PRODUCT_BUNDLE_IDENTIFIER", ""),
        "IOS_DEBUG_APP_PROFILE" => watchcat.fetch("PROVISIONING_PROFILE_SPECIFIER", ""),
        "IOS_DEBUG_SCREEN_BUNDLE_ID" => screen.fetch("PRODUCT_BUNDLE_IDENTIFIER", ""),
        "IOS_DEBUG_SCREEN_PROFILE" => screen.fetch("PROVISIONING_PROFILE_SPECIFIER", "")
      }

      mapping.each do |key, value|
        normalized = value.to_s.gsub(/\A"(.*)"\z/, "\1")
        puts "#{key}=#{Shellwords.escape(normalized)}"
      end
    ' "${IOS_SIGNING_BACKUP}"
  )"
}

# 根据当前 Debug 签名模式生成 exportOptions.debug.plist。
generate_ios_debug_export_plist() {
  # 当前 Debug 签名模式：Automatic 或 Manual。
  local sign_style

  load_ios_debug_signing
  sign_style="$(normalize_string "${IOS_DEBUG_SIGN_STYLE}")"

  mkdir -p "$(dirname "${IOS_EXPORT_PLIST_PATH}")"

  if [[ "${sign_style}" == "Automatic" ]]; then
    cat > "${IOS_EXPORT_PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>compileBitcode</key>
  <false/>
  <key>method</key>
  <string>debugging</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${IOS_DEBUG_TEAM_ID}</string>
</dict>
</plist>
EOF
    return 0
  fi

  [[ -n "${IOS_DEBUG_APP_PROFILE}" ]] || die "manual debug signing requires WatchCat provisioning profile"

  local screen_profile_section=""
  if [[ -n "${IOS_DEBUG_SCREEN_PROFILE}" ]]; then
    screen_profile_section="    <key>${IOS_DEBUG_SCREEN_BUNDLE_ID}</key>
    <string>${IOS_DEBUG_SCREEN_PROFILE}</string>"
  fi

  cat > "${IOS_EXPORT_PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>compileBitcode</key>
  <false/>
  <key>method</key>
  <string>debugging</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>teamID</key>
  <string>${IOS_DEBUG_TEAM_ID}</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>${IOS_DEBUG_APP_BUNDLE_ID}</key>
    <string>${IOS_DEBUG_APP_PROFILE}</string>
${screen_profile_section}
  </dict>
</dict>
</plist>
EOF
}

# 根据请求参数决定是否执行指定平台的 CMake preset。
run_cmake_preset() {
  # CMake preset 名称。
  local platform="$1"
  # 用于日志输出的平台名称。
  local platform_name="$2"
  shift 2

  if [[ ${NO_PRESET} -eq 1 && ${REQUEST_CLEAN} -eq 0 ]]; then
    log "skip configuring ${platform_name} due to --no_preset"
    return 0
  fi

  log "configuring ${platform_name}"
  cmake --preset "${platform}" "$@"
}

# 构建 Android WatchCat debug apk，并在有设备时自动安装和启动。
build_android() {
  # 已连接 Android 设备 ID。
  local device_id

  have_cmd adb || die "adb not found in PATH"

  run_cmake_preset android Android -DCMAKE_BUILD_TYPE=Debug

  log "building Android WatchCat debug apk"
  cmake --build "${REPO_ROOT}/build/android" --target apkarchive

  require_file "${ANDROID_APK_PATH}"
  highlight_artifact_path "Android apk artifact" "${ANDROID_APK_PATH}"

  device_id="$(detect_android_device)"
  if [[ -z "${device_id}" ]]; then
    warn "no connected Android device found, skip install and launch"
    return 0
  fi

  log "installing Android apk to ${device_id}"
  adb -s "${device_id}" install -r "${ANDROID_APK_PATH}"

  log "launching Android app"
  adb -s "${device_id}" shell monkey -p "${ANDROID_PACKAGE_NAME}" -c android.intent.category.LAUNCHER 1
}

# 构建 iOS WatchCat debug ipa，并在有设备时自动安装和启动。
build_ios() {
  # iOS workspace 路径。
  local workspace
  # 已连接 iOS 设备 ID。
  local device_id
  # 导出的 ipa 文件路径。
  local ipa_path
  # 组包后 Payload 内部的 .app 路径。
  local app_path
  # Xcode 产出的 WatchCat.app 链接路径。
  local app_link
  # 应用 bundle identifier。
  local bundle_id
  # 当前构建出的 app 签名状态标签。
  local sign_label

  have_cmd xcodebuild || die "xcodebuild not found in PATH"
  have_cmd xcrun || die "xcrun not found in PATH"

  run_cmake_preset ios iOS

  run_rtcpod_install

  workspace="$(resolve_ios_workspace)"
  ensure_ios_scheme "${workspace}" "${IOS_SCHEME_NAME}"
  if [[ ${NO_SIGN} -eq 1 ]]; then
    log "skip applying iOS signing due to --no_sign"
    sign_label="unsigned"
  else
    apply_ios_signing
    sign_label="signed"
  fi

  ensure_dir_clean "${IOS_EXPORT_DIR}"
  rm -rf "${IOS_ARCHIVE_PATH}" "${IOS_EXTRACT_DIR}"

  if [[ ${NO_SIGN} -eq 1 ]]; then
    log "archiving iOS WatchCat debug app without code signing"
    xcodebuild archive \
      -workspace "${workspace}" \
      -scheme "${IOS_SCHEME_NAME}" \
      -configuration Debug \
      -destination "generic/platform=iOS" \
      -archivePath "${IOS_ARCHIVE_PATH}" \
      SKIP_INSTALL=NO \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGN_IDENTITY="" \
      DEVELOPMENT_TEAM="" \
      PROVISIONING_PROFILE_SPECIFIER=""
  else
    log "archiving iOS WatchCat debug app with code signing"
    xcodebuild archive \
      -workspace "${workspace}" \
      -scheme "${IOS_SCHEME_NAME}" \
      -configuration Debug \
      -destination "generic/platform=iOS" \
      -archivePath "${IOS_ARCHIVE_PATH}" \
      SKIP_INSTALL=NO
  fi

  app_link="${IOS_BUILD_DIR}/Debug/WatchCat.app"
  require_file "${app_link}"

  ipa_path="${IOS_EXPORT_DIR}/WatchCat-Debug.ipa"
  log "packaging iOS debug ipa from ${sign_label} WatchCat.app"
  package_ios_debug_ipa "${app_link}" "${ipa_path}" "${IOS_EXTRACT_DIR}"

  require_file "${ipa_path}"
  highlight_artifact_path "iOS ipa artifact" "${ipa_path}"

  app_path="${IOS_EXTRACT_DIR}/Payload/WatchCat.app"
  require_file "${app_path}"

  if [[ ${NO_SIGN} -eq 1 ]]; then
    warn "skip iOS install and launch because --no_sign produces an unsigned app"
    return 0
  fi

  device_id="$(detect_ios_device)"
  if [[ -z "${device_id}" ]]; then
    warn "no connected iOS device found, skip install and launch"
    return 0
  fi

  log "installing iOS app to ${device_id}"
  xcrun devicectl device install app --device "${device_id}" "${app_path}"

  bundle_id="$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app_path}/Info.plist"
  )"
  [[ -n "${bundle_id}" ]] || die "failed to read iOS bundle identifier from ${app_path}"

  log "launching iOS app ${bundle_id}"
  xcrun devicectl device process launch --device "${device_id}" --terminate-existing "${bundle_id}"
}

# 构建 Harmony WatchCat debug hap，并在有设备时自动安装和启动。
build_harmony() {
  # 已连接 Harmony 设备 ID。
  local device_id
  # Harmony 构建并行度，默认串行。
  local harmony_parallel_level
  # 当前实际生成的 hap 产物路径。
  local hap_path

  have_cmd hdc || die "hdc not found in PATH"

  run_cmake_preset harmony Harmony

  if [[ ${NO_SIGN} -eq 1 ]]; then
    log "skip applying Harmony signing due to --no_sign"
  else
    apply_harmony_signing
  fi

  if [[ -d "${HARMONY_HAP_DIR}" ]]; then
    find "${HARMONY_HAP_DIR}" -maxdepth 1 -type f -name '*.hap' -delete
  fi

  harmony_parallel_level="${CMAKE_BUILD_PARALLEL_LEVEL:-1}"
  log "building Harmony WatchCat debug hap"
  env \
    CMAKE_BUILD_PARALLEL_LEVEL="${harmony_parallel_level}" \
    DEVECO_SDK_HOME="${HARMONY_DEVECO_SDK_HOME}" \
    PATH="${HARMONY_TOOL_PATH_PREFIX}:${PATH}" \
    cmake --build "${REPO_ROOT}/build/harmony" --target hap_archive --config Debug

  hap_path="$(resolve_harmony_hap_path)"
  HARMONY_HAP_PATH="${hap_path}"
  highlight_artifact_path "Harmony hap artifact" "${HARMONY_HAP_PATH}"

  if [[ ${NO_SIGN} -eq 1 ]]; then
    warn "skip Harmony install and launch because --no_sign produces an unsigned hap"
    return 0
  fi

  device_id="$(detect_harmony_device)"
  if [[ -z "${device_id}" ]]; then
    warn "no connected Harmony device found, skip install and launch"
    return 0
  fi

  log "installing Harmony hap to ${device_id}"
  install_harmony_hap "${device_id}" || die "failed to install Harmony hap to ${device_id}"

  log "launching Harmony app"
  hdc -t "${device_id}" shell aa start -a "${HARMONY_ABILITY_NAME}" -b "${HARMONY_BUNDLE_NAME}"
}

# 构建 Android rtcengine aar。
build_android_rtcengine() {
  run_cmake_preset android Android -DCMAKE_BUILD_TYPE=Debug

  log "building Android RTCLive aar"
  cmake --build "${REPO_ROOT}/build/android" --target archive

  require_file "${ANDROID_RTCENGINE_AAR_PATH}"
  highlight_artifact_path "Android rtcengine artifact" "${ANDROID_RTCENGINE_AAR_PATH}"
}

# 构建 iOS rtcengine framework。
build_ios_rtcengine() {
  # iOS workspace 路径。
  local workspace

  have_cmd xcodebuild || die "xcodebuild not found in PATH"

  run_cmake_preset ios iOS

  run_rtcpod_install

  workspace="$(resolve_ios_workspace)"
  ensure_ios_scheme "${workspace}" "${IOS_RTCENGINE_SCHEME_NAME}"

  log "building iOS RTCLive framework"
  xcodebuild build \
    -workspace "${workspace}" \
    -scheme "${IOS_RTCENGINE_SCHEME_NAME}" \
    -configuration Debug \
    -destination "generic/platform=iOS"

  require_file "${IOS_RTCENGINE_FRAMEWORK_PATH}"
  highlight_artifact_path "iOS rtcengine artifact" "${IOS_RTCENGINE_FRAMEWORK_PATH}"
}

# 构建 Harmony rtcengine har。
build_harmony_rtcengine() {
  # Harmony 构建并行度，默认串行。
  local harmony_parallel_level

  run_cmake_preset harmony Harmony

  harmony_parallel_level="${CMAKE_BUILD_PARALLEL_LEVEL:-1}"
  log "building Harmony RTCLive har"
  env \
    CMAKE_BUILD_PARALLEL_LEVEL="${harmony_parallel_level}" \
    DEVECO_SDK_HOME="${HARMONY_DEVECO_SDK_HOME}" \
    PATH="${HARMONY_TOOL_PATH_PREFIX}:${PATH}" \
    cmake --build "${REPO_ROOT}/build/harmony" --target archive --config Debug

  require_file "${HARMONY_RTCENGINE_HAR_PATH}"
  highlight_artifact_path "Harmony rtcengine artifact" "${HARMONY_RTCENGINE_HAR_PATH}"
}

# 根据 target 分发 Android 构建入口。
build_requested_android() {
  case "${REQUEST_TARGET}" in
    watchcat)
      build_android
      ;;
    rtcengine)
      build_android_rtcengine
      ;;
  esac
}

# 根据 target 分发 iOS 构建入口。
build_requested_ios() {
  case "${REQUEST_TARGET}" in
    watchcat)
      build_ios
      ;;
    rtcengine)
      build_ios_rtcengine
      ;;
  esac
}

# 根据 target 分发 Harmony 构建入口。
build_requested_harmony() {
  case "${REQUEST_TARGET}" in
    watchcat)
      build_harmony
      ;;
    rtcengine)
      build_harmony_rtcengine
      ;;
  esac
}

# 将单个平台选择结果写入请求标记。
add_platform() {
  # 用户传入的平台字符串。
  local platform="$1"
  case "${platform}" in
    android)
      REQUEST_ANDROID=1
      ;;
    ios)
      REQUEST_IOS=1
      ;;
    harmony)
      REQUEST_HARMONY=1
      ;;
    *)
      die "unsupported platform: ${platform}"
      ;;
  esac
}

# 校验 target 仅允许 watchcat 或 rtcengine。
validate_target() {
  case "${REQUEST_TARGET}" in
    watchcat|rtcengine)
      return 0
      ;;
    *)
      die "unknown target: ${REQUEST_TARGET}"
      ;;
  esac
}

# 解析 --os 参数，支持逗号分隔和 all。
parse_os_selector() {
  # 用户传入的原始平台选择字符串。
  local raw_value="$1"
  # 当前循环处理的单个平台 token。
  local token
  # 逗号拆分后的平台数组。
  local parts=()

  IFS=',' read -r -a parts <<< "${raw_value}"
  for token in "${parts[@]}"; do
    token="$(trim_and_lower "${token}")"
    [[ -n "${token}" ]] || continue
    case "${token}" in
      all)
        REQUEST_ANDROID=1
        REQUEST_IOS=1
        REQUEST_HARMONY=1
        return 0
        ;;
      android)
        add_platform "android"
        ;;
      ios)
        add_platform "ios"
        ;;
      harmony)
        add_platform "harmony"
        ;;
      *)
        die "unknown os selector: ${token}"
        ;;
    esac
  done
}

# 解析命令行参数并初始化构建上下文。
parse_args() {
  # 默认仓库目录为当前目录。
  local repo_dir="."
  # 默认平台选择为 all。
  local os_selector="all"

  while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)
          REQUEST_CLEAN=1
          shift
          ;;
        --no_preset)
          NO_PRESET=1
          shift
          ;;
        --no_sign)
          NO_SIGN=1
          shift
          ;;
      --target)
        [[ $# -ge 2 ]] || die "missing value for --target"
        REQUEST_TARGET="$(trim_and_lower "$2")"
        shift 2
        ;;
      --dir)
        [[ $# -ge 2 ]] || die "missing value for --dir"
        repo_dir="$2"
        shift 2
        ;;
      --os)
        [[ $# -ge 2 ]] || die "missing value for --os"
        os_selector="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done

  validate_target
  parse_os_selector "${os_selector}"

  if [[ ${REQUEST_ANDROID} -eq 0 && ${REQUEST_IOS} -eq 0 && ${REQUEST_HARMONY} -eq 0 ]]; then
    die "no valid os selected"
  fi

  resolve_repo_root "${repo_dir}"
}

# 主流程：解析参数、按需清理，再按平台分发构建任务。
main() {
  parse_args "$@"

  log "target: ${REQUEST_TARGET}"
  log "repo: ${REPO_ROOT}"
  if [[ ${NO_SIGN} -eq 1 ]]; then
    log "signing: disabled for iOS and Harmony"
  else
    log "signing: enabled for iOS and Harmony"
  fi
  if [[ ${NO_PRESET} -eq 1 && ${REQUEST_CLEAN} -eq 1 ]]; then
    log "preset: enabled because --clean overrides --no_preset"
  elif [[ ${NO_PRESET} -eq 1 ]]; then
    log "preset: disabled"
  else
    log "preset: enabled"
  fi
  if [[ ${REQUEST_CLEAN} -eq 1 ]]; then
    clean_requested_platforms
  fi

  if [[ ${REQUEST_ANDROID} -eq 1 ]]; then
    build_requested_android
  fi
  if [[ ${REQUEST_IOS} -eq 1 ]]; then
    build_requested_ios
  fi
  if [[ ${REQUEST_HARMONY} -eq 1 ]]; then
    build_requested_harmony
  fi
}

main "$@"
