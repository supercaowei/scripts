#!/usr/bin/env bash

set -euo pipefail

TARGET_DIR="."

log() {
  echo "[set_gradle_jvm_11] $*"
}

die() {
  echo "[set_gradle_jvm_11] error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  set_gradle_jvm_11 [--dir <android project directory>]

Examples:
  set_gradle_jvm_11
  set_gradle_jvm_11 --dir /path/to/android/project
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir)
        [[ $# -ge 2 ]] || die "missing value for --dir"
        TARGET_DIR="$2"
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
}

is_java_11_home() {
  local java_home="$1"
  local version_output=""

  [[ -n "${java_home}" ]] || return 1
  [[ -d "${java_home}" ]] || return 1
  [[ -x "${java_home}/bin/java" ]] || return 1

  version_output="$("${java_home}/bin/java" -version 2>&1 || true)"
  echo "${version_output}" | grep -Eq 'version "11([.][0-9]+)?|openjdk 11|openjdk version "11([.][0-9]+)?' \
    || return 1
}

resolve_java_home_11() {
  local candidate=""
  local java_vm_dir=""

  if is_java_11_home "${JAVA_HOME:-}"; then
    printf '%s\n' "${JAVA_HOME}"
    return 0
  fi

  for java_vm_dir in "${HOME}/Library/Java/JavaVirtualMachines" "/Library/Java/JavaVirtualMachines"; do
    [[ -d "${java_vm_dir}" ]] || continue
    while IFS= read -r candidate; do
      candidate="${candidate}/Contents/Home"
      if is_java_11_home "${candidate}"; then
        printf '%s\n' "${candidate}"
        return 0
      fi
    done < <(find "${java_vm_dir}" -maxdepth 1 -mindepth 1 -type d -name '*11*' | sort -Vr)
  done

  die "failed to locate Java 11 under user/system JavaVirtualMachines"
}

update_gradle_xml() {
  local gradle_xml="$1"

  ruby - "${gradle_xml}" <<'RUBY'
file_path = ARGV[0]
content = File.read(file_path)
replacement = '<option name="gradleJvm" value="#JAVA_HOME" />'

updated = content.sub(/<option name="gradleJvm" value="[^"]*" \/>/, replacement)
if updated == content
  lines = content.lines(chomp: true)
  gradle_settings_start = lines.index { |line| line.match?(/^\s*<GradleProjectSettings>\s*$/) }

  if gradle_settings_start
    gradle_settings_end = ((gradle_settings_start + 1)...lines.length).find do |index|
      lines[index].match?(/^\s*<\/GradleProjectSettings>\s*$/)
    end

    if gradle_settings_end
      modules_index = ((gradle_settings_start + 1)...gradle_settings_end).find do |index|
        lines[index].match?(/^\s*<option name="modules">\s*$/)
      end

      if modules_index
        indent = lines[modules_index][/^\s*/]
        updated_lines = lines.dup
        updated_lines.insert(modules_index, "#{indent}#{replacement}")
        updated = updated_lines.join("\n")
        updated << "\n" if content.end_with?("\n")
      end
    end
  end
end

if updated == content
  abort("[set_gradle_jvm_11] error: failed to find insertion point for gradleJvm in #{file_path}")
end

File.write(file_path, updated)
RUBY
}

main() {
  local project_dir=""
  local gradle_xml=""
  local java_home=""

  parse_args "$@"
  java_home="$(resolve_java_home_11)"
  export JAVA_HOME="${java_home}"

  [[ -d "${TARGET_DIR}" ]] || die "invalid --dir: ${TARGET_DIR}"
  project_dir="$(cd "${TARGET_DIR}" && pwd)"
  gradle_xml="${project_dir}/.idea/gradle.xml"

  [[ -f "${gradle_xml}" ]] || die "missing gradle xml: ${gradle_xml}"

  update_gradle_xml "${gradle_xml}"
  log "updated ${gradle_xml}"
}

main "$@"
