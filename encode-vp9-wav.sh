#!/bin/sh -e
#
# Copyright 2017 Mike Radford <Mike.Radford@fox.com>, Alex Koren <alex@actiview.co>
# Copyright 2017 Matthew Sheby <matthew.sheby@eikongroup.co.uk>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. The name of the author may not be used to endorse or promote products
#    derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

int2bin() {
  i=$1
  local f
  printf -v f '\\x%02x' $((i >> 24 & 255)) $((i >> 16 & 255)) $((i >> 8 & 255)) $((i & 255))
  printf "$f"
}

if [ $# -eq 0 ]; then
  echo "usage: $0 <MovieFile>"
  exit 1
fi

input=$1
final_wav=${input%%.*}.wav
final_raw=${input%%.*}.raw
final_webm=${input%%.*}.webm

if [ ! -e "$input" ]; then
   echo "$input: No such file";
   exit 1
fi

if [ -e "$final_wav" ]; then
    read -p "$final_wav already exists. Delete it? [y/N]" -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting...";
        exit;
    fi
    rm -f "$final_wav";
fi

audio_sample_rate=48000
audio_bits_per_sample=24
bits_per_byte=8
bitrate=$((audio_sample_rate * audio_bits_per_sample / 2))

chunk_len_s=2 # might want to play with other values
fps=$(( $(ffprobe -loglevel error -of default=nw=1:nk=1 -i "$input" -select_streams v:0 -show_entries stream=r_frame_rate) ))
chunk_len_frames=$(( chunk_len_s * fps ))
chunk_len_bytes=$(( audio_sample_rate * audio_bits_per_sample / bits_per_byte * chunk_len_s ))
build_dir=$(mktemp -d)

echo "Looking to see if resizing is necessary..."
resizing_flags=""
input_width=$(ffprobe -loglevel error -of default=nw=1:nk=1 -i "$input" -select_streams v:0 -show_entries stream=width)
input_height=$(ffprobe -loglevel error -of default=nw=1:nk=1 -i "$input" -select_streams v:0 -show_entries stream=height)
if [ "X${input_width}" != "X" ] && [ "X${input_height}" != "X" ]; then
    if [ "${input_width}" -gt 480 ] || [ "${input_height}" -gt 640 ]; then
	resizing_flags="-filter:v scale=w=480:h=640:force_original_aspect_ratio=decrease"
    fi
fi
echo

echo "Encoding with.."
echo "Frame Rate: $fps fps"
echo "Chunk Length: $chunk_len_frames frames"
echo "Max Chunk Size: $chunk_len_bytes bytes"
echo "Bitrate: $bitrate"
echo

# segfaults, but works
ffmpeg \
   -loglevel quiet \
   -hide_banner \
   -i "$input"  \
   -map 0:0 \
   -pix_fmt yuv420p \
   ${resizing_flags} \
   -c:v libvpx-vp9 \
     -keyint_min $chunk_len_frames -g $chunk_len_frames \
     -speed 6 -tile-columns 4 -frame-parallel 1 -threads 8 \
     -static-thresh 0 -max-intra-rate 300 -deadline realtime \
     -lag-in-frames 0 -error-resilient 1 \
     -b:v $bitrate -minrate $bitrate -maxrate $bitrate \
   -an \
   -sn \
   -f webm_chunk \
     -header "$build_dir/chunk.hdr" \
     -chunk_start_index 1 \
   $build_dir/chunk_%05d.chk || true
echo "Success! Encoded all chunks to vp9"
echo

vp9_hdr="$build_dir/chunk.hdr";
vp9_hdr_size=$(wc -c < "$build_dir/chunk.hdr");

vp9_pcm_file=$(mktemp)

echo "Adding headers and padding each chunk to $chunk_len_bytes bytes.";
for file in $build_dir/chunk_*; do
  size=$(wc -c < "$file") # find the size of the file

  printf "\xff\xff\xff\xff" >  tmp.bin # create chunk header starting with 4 bytes of FF
  int2bin $size             >> tmp.bin # add 32bit encoded integer of length of valid data in chunk to chunk header
  int2bin $chunk_len_bytes  >> tmp.bin # add 32bit encoded integer of length of padded chunk including chunk header
  int2bin $vp9_hdr_size     >> tmp.bin # add 32bit encoded integer of length of vp9 header
  printf "\xff\xff\xff\xff" >> tmp.bin # finish chunk header with another 4 bytes of FF
  cat "$vp9_hdr"            >> tmp.bin # add the vp9 header
  cat "$file"               >> tmp.bin # add the chunk data after the chunk header
  mv tmp.bin "$file"                   # move the temporary chunk header and chunk data back to file

  if [ $size -gt $chunk_len_bytes ]; then #assert the size of the file isn't larger than $chunk_len_bytes
      echo "$file too big: $size > $chunk_len_bytes. Aborting...";
      exit 1;
  fi

  dd of="$file" bs=1 count=0 seek=$chunk_len_bytes 2>/dev/null #pad to chunk_len_bytes
  cat "$file" >> "$vp9_pcm_file"; # aggregate chunks into tmp file
done

echo "Generating WAV from raw pcm"

ffmpeg -ac 1 \
       -ar $audio_sample_rate \
       -y \
       -f s24le \
       -acodec pcm_s24le \
       -i "$vp9_pcm_file" \
       -codec:a copy "$final_wav" \
       2>/dev/null
echo "Success! Wrote to: $final_wav (Use this file for the DCP)"
echo

rm -f "$vp9_pcm_file";
