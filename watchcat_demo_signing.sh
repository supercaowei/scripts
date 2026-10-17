#!/usr/bin/env bash

set -euo pipefail

# 备份根目录基准路径，按仓库名和路径哈希再细分子目录。
BACKUP_ROOT_BASE="${HOME}/.rtclive_local_signing"
# 当前仓库对应的签名备份根目录。
BACKUP_ROOT=""
# iOS 签名备份 JSON 文件路径。
IOS_BACKUP=""
# iOS WatchCat scheme 备份文件路径。
IOS_SCHEME_BACKUP=""
# 是否使用个人账号的 Automatically Manage Signing 备份。
PERSONAL_SIGNING=0
# Harmony 签名备份文件路径。
HARMONY_BACKUP=""
# 当前仓库备份目录中的说明文件路径。
BACKUP_README=""

# 当前 RTCLive 仓库绝对路径。
REPO_ROOT=""
# 当前仓库对应的备份目录 key，由可读目录名和路径哈希组成。
REPO_BACKUP_KEY=""
# iOS project.pbxproj 路径，用于提取和回放签名配置。
IOS_PBXPROJ=""
# iOS WatchCat 共享 scheme 路径。
IOS_SCHEME_PATH=""
# Harmony build-profile.json5 路径，用于提取和回放签名配置。
HARMONY_BUILD_PROFILE=""

# 打印脚本用法说明。
usage() {
  cat <<'USAGE'
Usage:
  watchcat_demo_signing.sh <backup|recover|print-paths> [--dir <RTCLive directory>] [--os <ios|harmony|all>]
      [--personal]

Examples:
  watchcat_demo_signing.sh backup --dir ./ --os harmony
  watchcat_demo_signing.sh recover --dir ~/Work/RTCLiveDev --os ios
  watchcat_demo_signing.sh backup --dir ~/Work/RTCLiveDev --os ios --personal
  watchcat_demo_signing.sh print-paths --dir ~/Work/RTCLiveDev
  watchcat_demo_signing.sh recover
USAGE
}

# 打印普通日志。
log() {
  echo "[watchcat_demo_signing] $*"
}

# 打印警告日志。
warn() {
  echo "[watchcat_demo_signing] warning: $*" >&2
}

# 确保当前仓库对应的备份目录存在，并刷新 README 说明文件。
ensure_backup_root() {
  [[ -n "${BACKUP_ROOT}" ]] || {
    echo "Backup root is not initialized" >&2
    exit 1
  }

  mkdir -p "${BACKUP_ROOT}"
  chmod 700 "${BACKUP_ROOT}"
  write_backup_readme
  chmod 600 "${BACKUP_README}"
}

# 基于仓库绝对路径生成当前仓库的各类备份文件路径。
set_backup_paths() {
  # 仓库备份目录 key，格式为“可读目录名_路径哈希前缀”。
  REPO_BACKUP_KEY="$(
    ruby -rdigest -e '
      repo_root = File.expand_path(ARGV[0])
      name = File.basename(repo_root)
      readable = name.gsub(/[^0-9A-Za-z._-]+/, "_")
      readable = "repo" if readable.empty?
      hash = Digest::SHA256.hexdigest(repo_root)[0, 12]
      puts "#{readable}_#{hash}"
    ' "${REPO_ROOT}"
  )"

  # 当前仓库的备份根目录。
  BACKUP_ROOT="${BACKUP_ROOT_BASE}/${REPO_BACKUP_KEY}"
  # iOS 签名备份 JSON。
  if [[ ${PERSONAL_SIGNING} -eq 1 ]]; then
    IOS_BACKUP="${BACKUP_ROOT}/watchcat_ios_personal_signing.json"
  else
    IOS_BACKUP="${BACKUP_ROOT}/watchcat_ios_signing.json"
  fi
  # iOS WatchCat scheme 备份文件。
  IOS_SCHEME_BACKUP="${BACKUP_ROOT}/WatchCat.xcscheme"
  # Harmony build-profile 备份文件。
  HARMONY_BACKUP="${BACKUP_ROOT}/watchcat_harmony_build-profile.json5"
  # 当前仓库备份目录 README。
  BACKUP_README="${BACKUP_ROOT}/README.txt"
}

# 生成备份目录说明文件，注明备份来源仓库和对应工程文件位置。
write_backup_readme() {
  [[ -n "${BACKUP_README}" ]] || {
    echo "Backup README path is not initialized" >&2
    exit 1
  }

  cat > "${BACKUP_README}" <<EOF
This directory contains the iOS and Harmony signing backup for:
${REPO_ROOT}

Backup directory key:
${REPO_BACKUP_KEY}

Files written here are used by:
build_system/scripts/watchcat_demo_signing.sh

Source files in the RTCLive project:
- iOS scheme: ${IOS_SCHEME_PATH}
- iOS signing: ${IOS_PBXPROJ}
- Harmony signing: ${HARMONY_BUILD_PROFILE}
EOF
}

# 根据用户传入的仓库目录解析当前仓库所有工程文件路径。
set_repo_paths() {
  # 用户传入的 RTCLive 仓库目录。
  local work_dir="$1"

  [[ -n "${work_dir}" ]] || {
    usage >&2
    exit 1
  }

  if [[ ! -d "${work_dir}" ]]; then
    echo "Invalid work_dir: ${work_dir}" >&2
    exit 1
  fi

  # 当前 RTCLive 仓库绝对路径。
  REPO_ROOT="$(cd "${work_dir}" && pwd)"
  set_backup_paths
  # iOS project.pbxproj 主路径。
  IOS_PBXPROJ="${REPO_ROOT}/build/ios/RTCLive.xcodeproj/project.pbxproj"
  # iOS WatchCat 共享 scheme 主路径。
  IOS_SCHEME_PATH="${REPO_ROOT}/build/ios/RTCLive.xcodeproj/xcshareddata/xcschemes/WatchCat.xcscheme"
  # Harmony build-profile.json5 主路径。
  HARMONY_BUILD_PROFILE="${REPO_ROOT}/app/WatchCat/harmony/build-profile.json5"
}

# 提取 Harmony 签名摘要，统一用于“是否存在签名”和“是否与备份一致”的比较。
harmony_extract_signing_summary() {
  # 需要提取签名摘要的 build-profile.json5 路径。
  local file_path="$1"

  ruby - "${file_path}" <<'RUBY'
file_path = ARGV[0]
raw = File.read(file_path)

signing_configs = raw[/"signingConfigs"\s*:\s*\[(.*?)\]\s*,/m, 1]
product_signing_refs = raw.scan(/"signingConfig"\s*:\s*"([^"]+)"/).flatten.sort

normalized_signing_configs =
  if signing_configs
    signing_configs.gsub(/\s+/, "")
  else
    ""
  end

has_material = normalized_signing_configs.match?(/"material":\{.*?"certpath":"[^"]+".*?"profile":"[^"]+".*?"storeFile":"[^"]+"/)
has_signing_config_ref = !product_signing_refs.empty?

puts(has_material && has_signing_config_ref ? "present" : "missing")
puts(normalized_signing_configs)
puts(product_signing_refs.join(","))
RUBY
}

# 判断当前 Harmony 工程文件里是否已经存在有效签名配置。
harmony_project_has_signing() {
  # 当前 Harmony 工程签名摘要。
  local summary

  [[ -f "${HARMONY_BUILD_PROFILE}" ]] || return 1
  summary="$(harmony_extract_signing_summary "${HARMONY_BUILD_PROFILE}")"
  [[ "$(printf '%s\n' "${summary}" | sed -n '1p')" == "present" ]]
}

# 判断 Harmony 工程签名与备份签名是否一致。
harmony_signing_matches_backup() {
  # 当前工程的 Harmony 签名摘要。
  local project_summary
  # 备份文件中的 Harmony 签名摘要。
  local backup_summary

  [[ -f "${HARMONY_BUILD_PROFILE}" && -f "${HARMONY_BACKUP}" ]] || return 1

  project_summary="$(harmony_extract_signing_summary "${HARMONY_BUILD_PROFILE}")"
  backup_summary="$(harmony_extract_signing_summary "${HARMONY_BACKUP}")"

  [[ "${project_summary}" == "${backup_summary}" ]]
}

# 检查 iOS 备份是否完整，要求 scheme 和两组 target 的 Debug/Release 签名信息都存在。
ios_backup_complete() {
  [[ -f "${IOS_BACKUP}" && -f "${IOS_SCHEME_BACKUP}" ]] || return 1

  ruby - "${IOS_BACKUP}" "${PERSONAL_SIGNING}" <<'RUBY'
require "json"

backup = JSON.parse(File.read(ARGV[0]))
personal_signing = ARGV[1] == "1"
targets = backup.fetch("targets")
required_targets = {
  "WatchCat" => %w[Debug Release],
  "WatchCatScreenShare" => %w[Debug Release]
}
required_keys = %w[
  CODE_SIGN_ENTITLEMENTS
  CODE_SIGN_STYLE
  DEVELOPMENT_TEAM
  PRODUCT_BUNDLE_IDENTIFIER
  PRODUCT_NAME
  PROVISIONING_PROFILE_SPECIFIER
]
unless personal_signing
  required_keys += [
    "CODE_SIGN_IDENTITY",
    "CODE_SIGN_IDENTITY[sdk=iphoneos*]",
    "DEVELOPMENT_TEAM[sdk=iphoneos*]",
    "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]"
  ]
end

required_targets.each do |target, configs|
  target_hash = targets.fetch(target)
  configs.each do |config|
    config_hash = target_hash.fetch(config)
    settings = config_hash.fetch("settings")
    required_keys.each do |key|
      abort("missing #{target} #{config} #{key}") unless settings.key?(key)
    end
    if personal_signing && settings["CODE_SIGN_STYLE"] != "Automatic"
      abort("expected Automatic signing for #{target} #{config}")
    end

    entitlements = config_hash.fetch("entitlements")
    abort("missing entitlements content for #{target} #{config}") unless entitlements.key?("content")

    has_path = entitlements.key?("relative_path") || entitlements.key?("path")
    abort("missing entitlements path for #{target} #{config}") unless has_path
  end
end
RUBY
}

# 判断当前 iOS 工程中的 scheme 和签名是否已经与备份完全一致。
ios_project_matches_backup() {
  ios_backup_complete || return 1
  [[ -f "${IOS_SCHEME_PATH}" ]] || return 1
  cmp -s "${IOS_SCHEME_PATH}" "${IOS_SCHEME_BACKUP}" || return 1

  ruby - "${IOS_PBXPROJ}" "${IOS_BACKUP}" "${REPO_ROOT}" "${PERSONAL_SIGNING}" <<'RUBY' || return $?
require "json"

pbxproj_path = ARGV[0]
backup_path = ARGV[1]
repo_root = ARGV[2]
personal_signing = ARGV[3] == "1"
required_targets = {
  "WatchCat" => %w[Debug Release],
  "WatchCatScreenShare" => %w[Debug Release]
}
required_keys = %w[
  CODE_SIGN_ENTITLEMENTS
  CODE_SIGN_STYLE
  DEVELOPMENT_TEAM
  PRODUCT_BUNDLE_IDENTIFIER
  PRODUCT_NAME
  PROVISIONING_PROFILE_SPECIFIER
]
unless personal_signing
  required_keys += [
    "CODE_SIGN_IDENTITY",
    "CODE_SIGN_IDENTITY[sdk=iphoneos*]",
    "DEVELOPMENT_TEAM[sdk=iphoneos*]",
    "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]"
  ]
end

def normalize_value(value)
  value.to_s.gsub(/\A"(.*)"\z/, '\1')
end

def extract_setting(block, key)
  block[/^\s*"?#{Regexp.escape(key)}"? = (.+?);$/m, 1]
end

def canonicalize_entitlements(value, repo_root)
  normalized = normalize_value(value)
  actual_path =
    if normalized.start_with?("/")
      normalized
    else
      File.expand_path(normalized, repo_root)
    end

  repo_prefix = "#{repo_root}/"
  if actual_path.start_with?(repo_prefix)
    relative_path = actual_path.delete_prefix(repo_prefix)
    ["__REPO_ROOT__/#{relative_path}", actual_path, relative_path]
  else
    [normalized, actual_path, nil]
  end
end

def extract_ios_signing(pbxproj_path, repo_root, required_targets, required_keys, personal_signing)
  lines = File.readlines(pbxproj_path)
  blocks = []
  i = 0
  while i < lines.length
    if lines[i] =~ /^[ \t]*[A-F0-9]+ \/\* (Debug|Release) \*\/ = \{$/
      start = i
      depth = lines[i].count("{") - lines[i].count("}")
      i += 1
      while i < lines.length && depth > 0
        depth += lines[i].count("{") - lines[i].count("}")
        i += 1
      end
      blocks << lines[start...i].join
    else
      i += 1
    end
  end

  result = { "targets" => {} }
  blocks.each do |block|
    product_name = normalize_value(block[/^\s*PRODUCT_NAME = (.+?);$/m, 1])
    config = block[/^\s*name = (Debug|Release);$/m, 1]
    next unless required_targets.key?(product_name)
    next unless required_targets[product_name].include?(config)

    settings = {}
    required_keys.each do |key|
      value = extract_setting(block, key)
      next if value.nil?
      settings[key] = normalize_value(value)
    end
    if personal_signing
      conflicting_keys = [
        "CODE_SIGN_IDENTITY",
        "CODE_SIGN_IDENTITY[sdk=iphoneos*]",
        "DEVELOPMENT_TEAM[sdk=iphoneos*]",
        "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]"
      ]
      has_conflict = conflicting_keys.any? { |key| !extract_setting(block, key).nil? }
      settings["__CONFLICTING_MANUAL_SIGNING__"] = true if has_conflict
    end

    entitlements_value = settings.fetch("CODE_SIGN_ENTITLEMENTS")
    canonical_entitlements, entitlements_path, relative_path =
      canonicalize_entitlements(entitlements_value, repo_root)
    settings["CODE_SIGN_ENTITLEMENTS"] = canonical_entitlements

    entitlements = { "content" => File.read(entitlements_path) }
    if relative_path
      entitlements["relative_path"] = relative_path
    else
      entitlements["path"] = entitlements_value
    end

    result["targets"][product_name] ||= {}
    result["targets"][product_name][config] = {
      "settings" => settings,
      "entitlements" => entitlements
    }
  end

  result
end

backup = JSON.parse(File.read(backup_path))
current = extract_ios_signing(pbxproj_path, repo_root, required_targets, required_keys, personal_signing)

abort("iOS project signing does not match backup") unless current == backup
RUBY
}

# 从当前 iOS 工程提取签名并写入备份，仅在备份缺失或不一致时执行。
capture_ios() {
  local capture_status=0
  local ios_backup_temp=""
  local ios_scheme_backup_temp=""

  if ios_backup_complete; then
    log "skip iOS backup: existing backup is already complete"
    return 0
  fi

  if [[ ! -f "${IOS_PBXPROJ}" ]]; then
    log "skip iOS capture: missing ${IOS_PBXPROJ}"
    return 1
  fi

  if [[ ! -f "${IOS_SCHEME_PATH}" ]]; then
    log "skip iOS capture: missing ${IOS_SCHEME_PATH}"
    return 1
  fi

  ensure_backup_root

  ios_backup_temp="$(mktemp "${BACKUP_ROOT}/.watchcat_ios_signing.XXXXXX")" || return $?
  ios_scheme_backup_temp="$(mktemp "${BACKUP_ROOT}/.WatchCat.xcscheme.XXXXXX")" || {
    rm -f "${ios_backup_temp}"
    return 1
  }
  if ! cp "${IOS_SCHEME_PATH}" "${ios_scheme_backup_temp}"; then
    rm -f "${ios_backup_temp}" "${ios_scheme_backup_temp}"
    return 1
  fi

  ruby - "${IOS_PBXPROJ}" "${ios_backup_temp}" "${REPO_ROOT}" "${PERSONAL_SIGNING}" <<'RUBY' || capture_status=$?
require "json"

pbxproj_path = ARGV[0]
backup_path = ARGV[1]
repo_root = ARGV[2]
personal_signing = ARGV[3] == "1"
required_targets = {
  "WatchCat" => %w[Debug Release],
  "WatchCatScreenShare" => %w[Debug Release]
}
required_keys = %w[
  CODE_SIGN_ENTITLEMENTS
  CODE_SIGN_STYLE
  DEVELOPMENT_TEAM
  PRODUCT_BUNDLE_IDENTIFIER
  PRODUCT_NAME
  PROVISIONING_PROFILE_SPECIFIER
]
unless personal_signing
  required_keys += [
    "CODE_SIGN_IDENTITY",
    "CODE_SIGN_IDENTITY[sdk=iphoneos*]",
    "DEVELOPMENT_TEAM[sdk=iphoneos*]",
    "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]"
  ]
end

def normalize_value(value)
  value.to_s.gsub(/\A"(.*)"\z/, '\1')
end

def extract_setting(block, key)
  block[/^\s*"?#{Regexp.escape(key)}"? = (.+?);$/m, 1]
end

def canonicalize_entitlements(value, repo_root)
  normalized = normalize_value(value)
  actual_path =
    if normalized.start_with?("/")
      normalized
    else
      File.expand_path(normalized, repo_root)
    end

  repo_prefix = "#{repo_root}/"
  if actual_path.start_with?(repo_prefix)
    relative_path = actual_path.delete_prefix(repo_prefix)
    ["__REPO_ROOT__/#{relative_path}", actual_path, relative_path]
  else
    [normalized, actual_path, nil]
  end
end

lines = File.readlines(pbxproj_path)
blocks = []
i = 0
while i < lines.length
  if lines[i] =~ /^[ \t]*[A-F0-9]+ \/\* (Debug|Release) \*\/ = \{$/
    start = i
    depth = lines[i].count("{") - lines[i].count("}")
    i += 1
    while i < lines.length && depth > 0
      depth += lines[i].count("{") - lines[i].count("}")
      i += 1
    end
    blocks << lines[start...i].join
  else
    i += 1
  end
end

result = { "targets" => {} }
blocks.each do |block|
  product_name = normalize_value(block[/^\s*PRODUCT_NAME = (.+?);$/m, 1])
  config = block[/^\s*name = (Debug|Release);$/m, 1]
  next unless required_targets.key?(product_name)
  next unless required_targets[product_name].include?(config)

  settings = {}
  required_keys.each do |key|
    value = extract_setting(block, key)
    next if value.nil?
    settings[key] = normalize_value(value)
  end

  missing_keys = required_keys.reject { |key| settings.key?(key) }
  abort("missing #{product_name} #{config} signing keys: #{missing_keys.join(', ')}") unless missing_keys.empty?
  if personal_signing && settings["CODE_SIGN_STYLE"] != "Automatic"
    abort("expected Automatic signing for #{product_name} #{config}")
  end

  entitlements_value = settings.fetch("CODE_SIGN_ENTITLEMENTS")
  canonical_entitlements, entitlements_path, relative_path =
    canonicalize_entitlements(entitlements_value, repo_root)
  abort("missing entitlements file: #{entitlements_path}") unless File.file?(entitlements_path)

  settings["CODE_SIGN_ENTITLEMENTS"] = canonical_entitlements

  entitlements = { "content" => File.read(entitlements_path) }
  if relative_path
    entitlements["relative_path"] = relative_path
  else
    entitlements["path"] = entitlements_value
  end

  result["targets"][product_name] ||= {}
  result["targets"][product_name][config] = {
    "settings" => settings,
    "entitlements" => entitlements
  }
end

required_targets.each do |target, configs|
  configs.each do |config|
    abort("failed to capture #{target} #{config} signing from #{pbxproj_path}") unless result.dig("targets", target, config)
  end
end

File.write(backup_path, JSON.pretty_generate(result) + "\n")
RUBY

  if [[ ${capture_status} -ne 0 ]]; then
    rm -f "${ios_backup_temp}" "${ios_scheme_backup_temp}"
    return ${capture_status}
  fi
  if ! chmod 600 "${ios_backup_temp}" "${ios_scheme_backup_temp}"; then
    rm -f "${ios_backup_temp}" "${ios_scheme_backup_temp}"
    return 1
  fi
  if ! mv -f "${ios_scheme_backup_temp}" "${IOS_SCHEME_BACKUP}"; then
    rm -f "${ios_backup_temp}" "${ios_scheme_backup_temp}"
    return 1
  fi
  if ! mv -f "${ios_backup_temp}" "${IOS_BACKUP}"; then
    rm -f "${ios_backup_temp}"
    return 1
  fi
  log "captured iOS signing to ${IOS_BACKUP}"
  log "captured WatchCat scheme to ${IOS_SCHEME_BACKUP}"
}

# 将备份中的 iOS scheme、签名和 entitlements 恢复到当前工程。
apply_ios() {
  local apply_status=0
  local ios_scheme_dir=""
  local ios_scheme_temp=""

  if ! ios_backup_complete; then
    log "iOS backup is incomplete, run backup from a fully configured project first"
    return 1
  fi

  if ios_project_matches_backup; then
    log "skip iOS recover: WatchCat scheme and signing already match backup"
    return 0
  fi

  ios_scheme_dir="$(dirname "${IOS_SCHEME_PATH}")"
  mkdir -p "${ios_scheme_dir}" || return $?
  ios_scheme_temp="$(mktemp "${ios_scheme_dir}/.WatchCat.xcscheme.XXXXXX")" || return $?
  if ! cp "${IOS_SCHEME_BACKUP}" "${ios_scheme_temp}"; then
    rm -f "${ios_scheme_temp}"
    return 1
  fi

  ruby - "${IOS_PBXPROJ}" "${IOS_BACKUP}" "${REPO_ROOT}" "${PERSONAL_SIGNING}" <<'RUBY' || apply_status=$?
require "fileutils"
require "json"

pbxproj_path = ARGV[0]
backup_path = ARGV[1]
repo_root = ARGV[2]
personal_signing = ARGV[3] == "1"
backup = JSON.parse(File.read(backup_path)).fetch("targets")
lines = File.readlines(pbxproj_path)
output = []
match_counts = Hash.new(0)

def expand_setting_value(value, repo_root)
  return value unless value.start_with?("__REPO_ROOT__/")

  "#{repo_root}/#{value.delete_prefix('__REPO_ROOT__/')}"
end

def format_setting_value(key, value, repo_root)
  actual_value = key == "CODE_SIGN_ENTITLEMENTS" ? expand_setting_value(value, repo_root) : value
  return "\"\"" if actual_value.empty?
  return actual_value if actual_value.match?(/\A[A-Za-z0-9_.$()\/+-]+\z/)

  actual_value.dump
end

def format_setting_key(key)
  key.include?("[") ? key.dump : key
end

def setting_pattern(key)
  /^\s*"?#{Regexp.escape(key)}"? = .*;$/
end

def patch_block(block, backup_values, repo_root, personal_signing)
  patched = block.dup
  indent = patched[/^(\s*)PRODUCT_NAME = /, 1] || "                                "

  backup_values.each do |key, value|
    actual_value = format_setting_value(key, value, repo_root)
    line = "#{indent}#{format_setting_key(key)} = #{actual_value};\n"
    pattern = setting_pattern(key)
    product_name_pattern = /^#{Regexp.escape(indent)}PRODUCT_NAME = .*;$/
    if patched.match?(pattern)
      patched.sub!(pattern, line.chomp)
    elsif patched.match?(product_name_pattern)
      patched.sub!(product_name_pattern) { |product_name_line| line + product_name_line }
    else
      patched << line
    end
  end

  if personal_signing
    conflicting_keys = [
      "CODE_SIGN_IDENTITY",
      "CODE_SIGN_IDENTITY[sdk=iphoneos*]",
      "DEVELOPMENT_TEAM[sdk=iphoneos*]",
      "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]"
    ]
    conflicting_keys.each do |key|
      patched.gsub!(/^\s*"?#{Regexp.escape(key)}"? = .*;\n/, "")
    end
  end

  patched
end

i = 0
while i < lines.length
  if lines[i] =~ /^[ \t]*[A-F0-9]+ \/\* (Debug|Release) \*\/ = \{$/
    start = i
    depth = lines[i].count("{") - lines[i].count("}")
    i += 1
    while i < lines.length && depth > 0
      depth += lines[i].count("{") - lines[i].count("}")
      i += 1
    end

    block = lines[start...i].join
    product_name = block[/^\s*PRODUCT_NAME = (.+?);$/m, 1]&.gsub(/\A"(.*)"\z/, '\1')
    config = block[/^\s*name = (Debug|Release);$/m, 1]
    if backup.dig(product_name, config, "settings")
      match_counts[[product_name, config]] += 1
      output << patch_block(block, backup.dig(product_name, config, "settings"), repo_root, personal_signing)
    else
      output << block
    end
  else
    output << lines[i]
    i += 1
  end
end

invalid_configs = []
backup.each do |target, configs|
  configs.each_key do |config|
    count = match_counts[[target, config]]
    invalid_configs << "#{target} #{config} matched #{count} blocks" unless count == 1
  end
end
abort("failed to match iOS target configurations: #{invalid_configs.join(', ')}") unless invalid_configs.empty?

backup.each_value do |target_configs|
  target_configs.each_value do |config_hash|
    entitlements = config_hash.fetch("entitlements")
    entitlements_path =
      if entitlements.key?("relative_path")
        File.join(repo_root, entitlements.fetch("relative_path"))
      else
        entitlements.fetch("path")
      end

    FileUtils.mkdir_p(File.dirname(entitlements_path))
    File.write(entitlements_path, entitlements.fetch("content"))
  end
end

File.write(pbxproj_path, output.join)
RUBY

  if [[ ${apply_status} -ne 0 ]]; then
    rm -f "${ios_scheme_temp}"
    return ${apply_status}
  fi
  if ! mv -f "${ios_scheme_temp}" "${IOS_SCHEME_PATH}"; then
    rm -f "${ios_scheme_temp}"
    return 1
  fi

  log "applied iOS signing to ${IOS_PBXPROJ}"
  log "applied WatchCat scheme to ${IOS_SCHEME_PATH}"
}

# 从当前 Harmony 工程提取签名并写入备份，仅在工程有签名且与备份不一致时执行。
capture_harmony() {
  if [[ ! -f "${HARMONY_BUILD_PROFILE}" ]]; then
    log "skip Harmony capture: missing ${HARMONY_BUILD_PROFILE}"
    return 1
  fi

  if ! harmony_project_has_signing; then
    log "skip Harmony backup: project has no signing"
    return 0
  fi

  if [[ -f "${HARMONY_BACKUP}" ]] && harmony_signing_matches_backup; then
    log "skip Harmony backup: project signing already matches backup"
    return 0
  fi

  ensure_backup_root
  cp "${HARMONY_BUILD_PROFILE}" "${HARMONY_BACKUP}"
  chmod 600 "${HARMONY_BACKUP}"
  log "captured Harmony signing to ${HARMONY_BACKUP}"
}

# 将备份中的 Harmony 签名恢复到当前工程，仅在工程尚未配置签名时执行。
apply_harmony() {
  if [[ ! -f "${HARMONY_BACKUP}" ]]; then
    log "Harmony backup not found, run backup from a signed project first"
    return 1
  fi

  if [[ ! -f "${HARMONY_BUILD_PROFILE}" ]]; then
    log "skip Harmony apply: missing ${HARMONY_BUILD_PROFILE}"
    return 1
  fi

  if harmony_project_has_signing; then
    if harmony_signing_matches_backup; then
      log "skip Harmony recover: project signing already matches backup"
    else
      log "skip Harmony recover: project already has signing and differs from backup"
    fi
    return 0
  fi

  cp "${HARMONY_BACKUP}" "${HARMONY_BUILD_PROFILE}"
  log "applied Harmony signing to ${HARMONY_BUILD_PROFILE}"
}

# 打印当前仓库对应的签名备份目录。
report_backup_root() {
  log "signing backup directory: ${BACKUP_ROOT}"
}

# 以机器可读格式输出当前仓库的签名备份路径。
print_backup_paths() {
  printf 'REPO_BACKUP_KEY=%q\n' "${REPO_BACKUP_KEY}"
  printf 'BACKUP_ROOT=%q\n' "${BACKUP_ROOT}"
  printf 'IOS_BACKUP=%q\n' "${IOS_BACKUP}"
  printf 'IOS_SCHEME_BACKUP=%q\n' "${IOS_SCHEME_BACKUP}"
  printf 'HARMONY_BACKUP=%q\n' "${HARMONY_BACKUP}"
  printf 'BACKUP_README=%q\n' "${BACKUP_README}"
}

# 按平台和动作分发 backup/recover 逻辑，并允许 all 模式跳过不存在的平台工程。
run_platform_action() {
  # 当前处理的平台：ios 或 harmony。
  local platform="$1"
  # 当前动作：backup 或 recover。
  local action="$2"
  # 是否使用严格模式；严格模式下失败直接返回错误码。
  local strict="$3"
  # 平台处理返回码。
  local rc=0
  # 当前平台对应的主工程文件路径。
  local target_path=""

  case "${platform}" in
    ios)
      target_path="${IOS_PBXPROJ}"
      ;;
    harmony)
      target_path="${HARMONY_BUILD_PROFILE}"
      ;;
    *)
      echo "Unsupported platform: ${platform}" >&2
      exit 1
      ;;
  esac

  if [[ ! -f "${target_path}" ]]; then
    if [[ "${strict}" == "1" ]]; then
      echo "Missing ${platform} project file: ${target_path}" >&2
      return 1
    fi

    warn "skip ${platform}: missing ${target_path}"
    return 0
  fi

  case "${platform}:${action}" in
    ios:backup)
      capture_ios || rc=$?
      ;;
    ios:recover)
      apply_ios || rc=$?
      ;;
    harmony:backup)
      capture_harmony || rc=$?
      ;;
    harmony:recover)
      apply_harmony || rc=$?
      ;;
    *)
      echo "Unsupported action: ${action} for ${platform}" >&2
      return 1
      ;;
  esac

  if [[ ${rc} -ne 0 ]]; then
    warn "${action} failed for ${platform}"
    return ${rc}
  fi

  return 0
}

# 用户请求的动作：backup、recover 或 print-paths。
action=""
# 用户选择的平台，默认 all。
selected_os="all"
# 用户传入的仓库目录，默认当前目录。
work_dir="."

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    backup|recover|print-paths)
      if [[ -n "${action}" ]]; then
        echo "Action already specified: ${action}" >&2
        usage >&2
        exit 1
      fi
      action="$1"
      shift
      ;;
    --dir)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --dir" >&2
        usage >&2
        exit 1
      fi
      work_dir="$2"
      shift 2
      ;;
    --os)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --os" >&2
        usage >&2
        exit 1
      fi
      case "$2" in
        ios)
          selected_os="ios"
          shift 2
          ;;
        harmony)
          selected_os="harmony"
          shift 2
          ;;
        all)
          selected_os="all"
          shift 2
          ;;
        *)
          echo "Unsupported --os value: $2" >&2
          usage >&2
          exit 1
          ;;
      esac
      ;;
    --personal)
      PERSONAL_SIGNING=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${action}" ]]; then
  echo "Missing action: backup, recover or print-paths" >&2
  usage >&2
  exit 1
fi

set_repo_paths "${work_dir}"

if [[ "${action}" == "print-paths" ]]; then
  print_backup_paths
  exit 0
fi

report_backup_root

status=0

case "${selected_os}" in
  ios)
    run_platform_action "ios" "${action}" "1" || status=$?
    ;;
  harmony)
    run_platform_action "harmony" "${action}" "1" || status=$?
    ;;
  all)
    run_platform_action "ios" "${action}" "0" || status=$?
    run_platform_action "harmony" "${action}" "0" || status=$?
    ;;
esac

exit "${status}"
