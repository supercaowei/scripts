#!/usr/bin/env python3

import re
import subprocess


ADDR2LINE = "aarch64-linux-android-addr2line"
RTCLIVE_SO = "./build/android/build/Android/intermediates/merged_native_libs/debug/out/lib/arm64-v8a/librtclive.so"


stack = '''

'''


def extract_rtclive_addresses(crash_stack):
    return re.findall(r"\bpc\s+([0-9a-fA-F]+)\s+.*\blibrtclive\.so\b", crash_stack)


def build_addr2line_command(addresses):
    return [ADDR2LINE, "-e", RTCLIVE_SO, "-f", *addresses]


def main():
    addresses = extract_rtclive_addresses(stack)
    if not addresses:
        print("No librtclive.so addresses found.")
        return 1

    return subprocess.run(build_addr2line_command(addresses), check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
