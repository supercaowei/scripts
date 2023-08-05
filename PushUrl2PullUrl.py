#!/usr/bin/env python3

import re, sys, urllib.parse

def PushUrlToPullUrl(pushUrl):
    #url解码
    pushUrl = urllib.parse.unquote(pushUrl)
    #去除转义
    pushUrl = re.sub(r"(\\)*\/", r'/', pushUrl)
    regex = r"(rtmp|rtmpk|rtmpq|rtmps)://push-rtmp-((l\d|f5)(.*\.com))(:\d+)?(/([^\?\n]+))(\?.*)?"
    matchObj = re.match(regex, pushUrl)
    if matchObj:
        return "http://pull-" + ("" if (matchObj.group(3) == "f5" or matchObj.group(3) == "l3") else "flv-") + matchObj.group(2) + matchObj.group(6) + ".flv"
    else:
        regex1 = r"http://push-(rtmp|lls)-(f5|l3|l11)(.*\.com)(:\d+)?(/([^\?\n]+)).sdp(\?.*)?" #rts推流
        matchObj = re.match(regex1, pushUrl)
        if matchObj:
            return "http://pull-" + ("" if matchObj.group(2) == "f5" or matchObj.group(2) == "l3" else "flv-") + matchObj.group(2) + matchObj.group(3) + matchObj.group(5) + ".flv"
        else:
            return "regular expression and string don't match: " + "\n\tRegex1: " + regex + "\n\tRegex2: " + regex1 + "\n\tstring: " + pushUrl

def main():
    argc = len(sys.argv)
    if (argc <= 1):
        sys.exit("Please input a push stream url")
    for i in range(1, argc):
        print(PushUrlToPullUrl(sys.argv[i]))

if __name__ == "__main__":
    main()
