#!/bin/bash
set -euo pipefail

# Synthetic fixture for the legacy XIA video publisher; no external media.
# Keep a SegmentTemplate directly inside Representation, with numbered files
# under <representation>/dash/, as required by manifest.c and video_publisher.c.
fixture_root=$(mktemp -d /tmp/xia-video-fixture.XXXXXX)
video_dir="$fixture_root/synthetic12"
mkdir -p "$video_dir/video/dash"

ffmpeg -hide_banner -loglevel warning -nostdin -n \
  -f lavfi -i 'testsrc2=size=320x180:rate=25' -t 12 -an \
  -c:v libx264 -preset veryfast -profile:v baseline -level:v 3.0 \
  -pix_fmt yuv420p -b:v 250k -maxrate 300k -bufsize 600k \
  -g 50 -keyint_min 50 -sc_threshold 0 \
  -f dash -seg_duration 2 -use_template 1 -use_timeline 0 \
  -init_seg_name 'video/dash/init.mp4' \
  -media_seg_name 'video/dash/segment_$Number$.m4s' \
  "$video_dir/synthetic12.mpd"

# Validate XML and decode all six fragments in order. This Homebrew FFmpeg
# build can create DASH, but does not include the DASH input demuxer.
xmllint --noout "$video_dir/synthetic12.mpd"
media_input="concat:$video_dir/video/dash/init.mp4"
for segment in 1 2 3 4 5 6; do
  media_input="$media_input|$video_dir/video/dash/segment_${segment}.m4s"
done
ffmpeg -hide_banner -loglevel error -nostdin \
  -i "$media_input" -f null -
ffprobe -v error -count_frames -select_streams v:0 \
  -show_entries stream=codec_name,width,height,r_frame_rate,nb_read_frames \
  -of default=noprint_wrappers=1 "$media_input"

printf 'Verified synthetic video directory: %s\n' "$video_dir"
