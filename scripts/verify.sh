#!/usr/bin/env bash
# 安装 preview 包 → 开启 poster home（可选假密钥态）→ 采集首页/发现页截图胶卷
# 注意：本脚本不接触任何真实密钥；文本产物上传前统一做 sk_ 脱敏。
set -u
PKG=com.fongmi.android.tv.preview
OUT=artifacts
mkdir -p "$OUT" work
BRIDGE_MODE="${BRIDGE_MODE:-off}"

capture() { adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null || true; echo "captured $1"; }
key() { adb shell input keyevent "$1" >/dev/null 2>&1 || true; sleep "${2:-1}"; }
redact() { sed -i -E 's/sk_[A-Za-z0-9]{8,}/sk_<redacted>/g' "$1" 2>/dev/null || true; }
redact_all_text() { for f in "$OUT"/*.xml "$OUT"/*.txt; do [ -f "$f" ] && redact "$f"; done; }

echo "== wait boot =="
for i in $(seq 1 60); do
  [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break
  sleep 5
done
adb shell getprop ro.product.cpu.abi ro.product.cpu.abilist | tee "$OUT/abi.txt"
adb shell settings put secure immersive_mode_confirmations confirmed || true
echo "immersive confirmation suppressed"

echo "== fresh install =="
adb uninstall "$PKG" >/dev/null 2>&1 || true
adb install -r apk/preview-app-debug.apk 2>&1 | tee "$OUT/install.txt" || true

echo "== grant runtime permissions =="
for perm in POST_NOTIFICATIONS RECORD_AUDIO; do
  adb shell pm grant "$PKG" android.permission.$perm 2>/dev/null && echo "granted $perm" || true
done

echo "== first launch to create prefs =="
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep 25
capture 00-first-launch
adb shell am force-stop "$PKG" || true
sleep 2

echo "== patch prefs (poster home on, bridge mode: $BRIDGE_MODE) =="
PREFS=$(adb shell "run-as $PKG ls shared_prefs 2>/dev/null" | tr -d '\r' | head -1)
[ -n "$PREFS" ] || PREFS="${PKG}_preferences.xml"
echo "prefs file: [$PREFS]" | tee "$OUT/prefs-name.txt"
adb shell "run-as $PKG sh -c 'cat shared_prefs/$PREFS 2>/dev/null'" > "$OUT/prefs-before.xml" 2>/dev/null || true
python3 -I - "$OUT/prefs-before.xml" "work/prefs-after.xml" "$BRIDGE_MODE" <<'PY'
import io, re, sys
src, dst, mode = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    s = io.open(src, encoding='utf-8', errors='ignore').read()
except FileNotFoundError:
    s = ''
if not s.strip():
    s = "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n</map>\n"
if 'browse_poster_home' in s:
    s = s.replace('name="browse_poster_home" value="false"', 'name="browse_poster_home" value="true"')
else:
    s = s.replace('</map>', '    <boolean name="browse_poster_home" value="true" />\n</map>')
if mode == 'invalid':
    fake = 'sk_invalid_verify'
    if 'browse_bridge_sk' in s:
        s = re.sub(r'<string name="browse_bridge_sk">[^<]*</string>', '<string name="browse_bridge_sk">' + fake + '</string>', s)
    else:
        s = s.replace('</map>', '    <string name="browse_bridge_sk">' + fake + '</string>\n</map>')
io.open(dst, 'w', encoding='utf-8').write(s)
print('prefs patched; bridge_mode=%s' % mode)
PY
cp work/prefs-after.xml "$OUT/prefs-after-redacted.xml" 2>/dev/null || true
adb push work/prefs-after.xml /data/local/tmp/prefs-after.xml >/dev/null 2>&1 || true
adb shell "run-as $PKG sh -c 'cat /data/local/tmp/prefs-after.xml > shared_prefs/$PREFS'" || true

echo "== relaunch poster home =="
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep 30
capture 01-home-top
adb shell dumpsys window 2>/dev/null | grep -E "mCurrentFocus" | head -2 | tee -a "$OUT/focus.txt" || true

echo "== home filmstrip =="
for i in $(seq 1 18); do
  key KEYCODE_DPAD_DOWN 1
  capture "$(printf '02-down-%02d' "$i")"
done
key KEYCODE_DPAD_DOWN 1
key KEYCODE_DPAD_DOWN 1
capture 03-bottom

echo "== press center at bottom =="
key KEYCODE_DPAD_CENTER 6
capture 04-after-center

echo "== rex section pages (root am start) =="
adb root >/dev/null 2>&1 || true
sleep 4
adb wait-for-device || true
for spec in "08-rex-trending:trending_day" "09-rex-cn-series:cn_series" "10-rex-anime:anime"; do
  name="${spec%%:*}"; skey="${spec##*:}"
  { adb shell am start -n "$PKG/com.fongmi.android.tv.ui.activity.RexSectionActivity" --es section_key "$skey" || true; } 2>&1 | tee -a "$OUT/amstart.txt"
  sleep 18
  capture "$name"
  key KEYCODE_DPAD_RIGHT 1
  key KEYCODE_DPAD_RIGHT 1
  capture "$name-scroll"
  adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
  sleep 2
done

echo "== am start discover (shell) =="
{ adb shell am start -n "$PKG/com.fongmi.android.tv.ui.activity.DiscoverActivity" || true; } 2>&1 | tee -a "$OUT/amstart.txt"
sleep 10
capture 05-discover-direct

echo "== am start discover (root) =="
adb root >/dev/null 2>&1 || true
sleep 4
adb wait-for-device || true
{ adb shell am start -n "$PKG/com.fongmi.android.tv.ui.activity.DiscoverActivity" || true; } 2>&1 | tee -a "$OUT/amstart.txt"
sleep 15
capture 06-discover-root

echo "== discover filmstrip =="
for i in $(seq 1 16); do
  key KEYCODE_DPAD_DOWN 1
  capture "$(printf '07-discover-down-%02d' "$i")"
done

echo "== diagnostics =="
adb logcat -d -v brief 2>/dev/null | grep -E "AndroidRuntime|FATAL|ANR|com.fongmi.android.tv.preview" | tail -400 > "$OUT/logcat-relevant.txt" || true
adb shell dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp" | head -6 > "$OUT/focus.txt" || true

redact_all_text
echo "verify done"
