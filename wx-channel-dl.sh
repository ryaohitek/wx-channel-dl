#!/bin/bash
# wx-channel-dl — Download WeChat Channels (微信视频号) audio as MP3
# Usage: ./wx-channel-dl.sh <SHARE_LINK>
# Repo:  https://github.com/<user>/wx-channel-dl

set -euo pipefail

SHARE_LINK="${1:?Usage: $0 <weixin.qq.com/sph/xxx>}"

# ── Step 1: Resolve via public API ──────────────────────────────────
echo "🔍 Resolving video info…"
RESPONSE=$(curl -s -X POST "https://sph.litao.workers.dev/api/fetch_video_profile" \
  -H "Content-Type: application/json" \
  -d "{\"url\":\"$SHARE_LINK\"}")

ERRCODE=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('errCode',-1))" 2>/dev/null || echo "-1")
if [[ "$ERRCODE" != "0" ]]; then
  ERRMSG=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('errMsg','unknown error'))" 2>/dev/null || echo "unknown")
  echo "❌ API error: $ERRMSG"
  exit 1
fi

TITLE=$(echo "$RESPONSE" | python3 -c "
import sys, json, re
d = json.load(sys.stdin)
desc = d.get('feedInfo', {}).get('description', 'untitled')
# Strip hashtags for filename, keep first 80 chars
desc = re.sub(r'#[^\s#]+', '', desc).strip()
desc = re.sub(r'[^a-zA-Z0-9\u4e00-\u9fff_\-. ]', '', desc)
print(desc[:80] or 'untitled')
" 2>/dev/null || echo "untitled")

VIDEO_URL=$(echo "$RESPONSE" | python3 -c "
import sys,json
d=json.load(sys.stdin)
fi=d.get('feedInfo',{})
# Prefer h264 (wider compat), fallback to h265
url=fi.get('h264VideoInfo',{}).get('videoUrl','') or fi.get('h265VideoInfo',{}).get('videoUrl','') or fi.get('videoUrl','')
print(url)
" 2>/dev/null)

if [[ -z "$VIDEO_URL" ]]; then
  echo "❌ Failed to extract video URL from API response"
  exit 1
fi

echo "📹 Title: $TITLE"
echo "⬇️  Downloading video…"

# ── Step 2: Download video ──────────────────────────────────────────
curl -# -o /tmp/wx_input.mp4 "$VIDEO_URL"
SIZE=$(stat -f%z /tmp/wx_input.mp4 2>/dev/null || stat -c%s /tmp/wx_input.mp4 2>/dev/null)
if [[ "${SIZE:-0}" -lt 100000 ]]; then
  echo "❌ Downloaded file too small (${SIZE:-0} bytes) — URL may have expired"
  rm -f /tmp/wx_input.mp4
  exit 1
fi

# ── Step 3: Ensure ffmpeg (ARM64 native) ─────────────────────────────
FFMPEG="/tmp/ffmpeg"
if [[ ! -x "$FFMPEG" ]] || ! file "$FFMPEG" 2>/dev/null | grep -q arm64; then
  echo "🔧 Downloading ffmpeg ARM64…"
  curl -sL "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip" -o /tmp/ffmpeg.zip
  unzip -oq /tmp/ffmpeg.zip -d /tmp/
  chmod +x "$FFMPEG"
fi

# ── Step 4: Convert to MP3 ──────────────────────────────────────────
OUTPUT="$HOME/Music/${TITLE}.mp3"
echo "🎵 Converting to MP3…"
"$FFMPEG" -i /tmp/wx_input.mp4 -vn -acodec libmp3lame -ab 320k \
  -id3v2_version 3 "$OUTPUT" -y -loglevel warning

# ── Step 5: Clean up ────────────────────────────────────────────────
rm -f /tmp/wx_input.mp4

echo "✅ Saved: $OUTPUT"
ls -lh "$OUTPUT"
