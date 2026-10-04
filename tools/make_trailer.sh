#!/usr/bin/env bash
# Records the trailer from the game and encodes it:  tools/make_trailer.sh [out.mp4]
# Frames come from tools/trailer.gd (software rendering, ~0.2 s per frame), music from the game's own tracks.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/StormIsland-trailer.mp4}"
FR=/tmp/trailer
FONT=assets/fonts/DejaVuSans-Bold.ttf
mkdir -p "$(dirname "$OUT")"
if [ -z "${SKIP_RECORD:-}" ]; then
  rm -rf "$FR"
  xvfb-run -a -s "-screen 0 1280x720x24" godot3 --path . --resolution 1280x720 --fixed-fps 30 --audio-driver Dummy \
    -s res://tools/trailer.gd -- "$FR" --skip-menu --no-bus --no-capture > /tmp/trailer_record.log 2>&1
fi
# soundtrack: the bus theme into the combat theme, faded out at the end
ffmpeg -y -loglevel error -i assets/audio/music_bus.wav -i assets/audio/music_combat.wav -filter_complex \
  "[0:a]atrim=0:25,aresample=44100,aformat=channel_layouts=stereo[a];[1:a]atrim=0:28,aresample=44100,aformat=channel_layouts=stereo[b];[a][b]acrossfade=d=2,afade=t=out:st=48:d=2,volume=0.9[m]" \
  -map "[m]" -t 50 /tmp/trailer_music.wav
cap() { # text size start end y
  echo "drawtext=fontfile=$FONT:text='$1':fontsize=$2:fontcolor=white:borderw=4:bordercolor=black@0.8:x=(w-text_w)/2:y=$5:enable='between(t,$3,$4)':alpha='if(lt(t,$3+0.3),(t-$3)/0.3,if(gt(t,$4-0.3),($4-t)/0.3,1))'"
}
VF="$(cap 'STORM ISLAND' 110 0.3 4.6 250),$(cap 'A BATTLE ROYALE FOR YOUR PC AND PHONE' 34 1.6 4.8 400),\
$(cap '50 FIGHTERS. ONE ISLAND.' 64 5.2 8.8 80),\
$(cap 'DROP IN. LOOT UP.' 64 9.3 13.8 80),\
$(cap 'FIGHT.' 64 14.3 19.8 80),\
$(cap 'BUILD.' 64 20.3 24.8 80),\
$(cap 'BREAK EVERYTHING.' 64 25.3 30.8 80),\
$(cap 'LLAMAS. BOOGIE BOMBS. CHAOS.' 58 31.3 35.8 80),\
$(cap 'DRIVE. EXPLORE.' 64 36.3 39.8 80),\
$(cap 'SOLO - DUOS - TRIOS - SQUADS' 50 40.3 44.8 80),\
$(cap 'WINDOWS - LINUX - ANDROID' 46 46.2 49.2 560),\
fade=t=in:st=0:d=0.8,fade=t=out:st=49:d=1"
# the end card: the game's logo fades in over the pulled-back island
ffmpeg -y -loglevel error -framerate 30 -i "$FR/f%05d.png" -loop 1 -t 50 -i assets/ui/logo.png -i /tmp/trailer_music.wav \
  -filter_complex "[1:v]scale=620:-1,format=rgba,fade=t=in:st=45.3:d=0.8:alpha=1[logo];[0:v][logo]overlay=(W-w)/2:140:enable='gte(t,45.3)',$VF[v]" -map "[v]" -map 2:a \
  -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -c:a aac -b:a 160k -shortest "$OUT"
ls -la "$OUT"
