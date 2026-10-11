#!/usr/bin/env bash
# 开串口控制台：115200 8N1，接的是 0 号核。退出按 Ctrl-A Ctrl-X
# 用法：console.sh [串口设备]
exec picocom -b 115200 "${1:-/dev/ttyUSB0}"
