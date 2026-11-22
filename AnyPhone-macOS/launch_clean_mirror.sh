#!/bin/bash
# Clean, borderless mirroring script for AnyPhone
ADB_BIN="/Applications/QtScrcpy.app/Contents/MacOS/adb"
SERVER_BIN="/Applications/QtScrcpy.app/Contents/MacOS/scrcpy-server"

# Run clean scrcpy stream without any Chinese Qt menus
$ADB_BIN forward tcp:8888 localabstract:scrcpy
$ADB_BIN push $SERVER_BIN /data/local/tmp/scrcpy-server.jar
$ADB_BIN shell CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / com.genymobile.scrcpy.Server 2.0 max_size=1600 bit_rate=8000000 max_fps=60 stay_awake=true &
