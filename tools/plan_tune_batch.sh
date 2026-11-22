#!/bin/bash
# Runs plan_tune.gd careers in parallel.
#   plan_tune_batch.sh <jobs file> <parallel> <out dir>
# Each line of the jobs file: age style seed seasons vote tag boost costs agecap   (the last three may be "-")
# Results go to <out dir>/<tag>_a<age>_<style>_s<seed>.jsonl; a finished job is skipped on a re-run.
G="$LOCALAPPDATA/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe"
cd "$(dirname "$0")/.."
OUT="$3"
mkdir -p "$OUT"
run_job() {
  read -r age style seed seasons vote tag boost costs agecap <<< "$1"
  out="$OUT/${tag}_a${age}_${style}_s${seed}.jsonl"
  [ -s "$out" ] && return
  extra=""
  [ "$boost" != "-" ] && [ -n "$boost" ] && extra="$extra boost=$boost"
  [ "$costs" != "-" ] && [ -n "$costs" ] && extra="$extra costs=$costs"
  [ "$agecap" != "-" ] && [ -n "$agecap" ] && extra="$extra agecap=$agecap"
  timeout 3600 "$G" --headless --path . --script res://tools/plan_tune.gd -- age=$age style=$style seed=$seed seasons=$seasons vote=$vote out="$out" $extra > "$out.log" 2>&1
}
export -f run_job
export G OUT
xargs -P "$2" -I{} bash -c 'run_job "{}"' < "$1"
