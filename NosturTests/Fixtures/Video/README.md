# Synthetic HLG fixture

`hlg-10bit.mov` is one second of synthetic gray video (64x64, 30 fps),
10-bit HEVC with BT.2020 primaries and HLG transfer. It contains a synthetic
`PrivateHDRSentinel` comment, no real camera/user content.

Generated with FFmpeg/libx265:

```
ffmpeg -f lavfi -i 'color=c=gray:s=64x64:r=30:d=1' -vf format=yuv420p10le \
  -c:v libx265 -preset ultrafast \
  -x265-params 'log-level=error:pools=1:frame-threads=1:repeat-headers=1:colorprim=bt2020:transfer=arib-std-b67:colormatrix=bt2020nc' \
  -tag:v hvc1 -metadata comment=PrivateHDRSentinel hlg-10bit.mov
```
