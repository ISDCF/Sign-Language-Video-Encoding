# Sign Language Video Encoding For Digital Cinema

A simple encoder and decoder that conforms to the [ISDCF Document on Sign Language Video Encoding](https://files.isdcf.com/papers/ISDCF-Doc13-Sign-Language-Video-Encoding-for-Digital-Cinema.pdf).

## Requirements
[FFmpeg](https://www.ffmpeg.org) v3.2.4 is required. In particular, the executables `ffmpeg`, `ffprobe`, and `ffplay` must be in your path.

Note: later versions of FFmpeg are known to not work at this time.

Futhermore, the File::Slurp, File::Temp, and Getopt::Long Perl modules are required.


## Synopsis

### Encoding

```bash
$ encode-vp9-wav sign-language.mp4
```

This will generate a wav file suitable for inclusion on channel 15 of a DCP.

### Decoding

You can play the encoded wav track using:

```bash
$ decode-vp9-wav sign-language.wav
```

or to simply extract the vp9 from the wav file:

```bash
$ decode-vp9-wav sign-language.wav  >out.vp9
```
