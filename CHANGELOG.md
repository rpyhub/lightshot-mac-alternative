# Changelog

## 1.0.1
- **Much smoother selection.** The screenshot is now uploaded to the GPU once and the dimming, selection border and handles are vector layers, so dragging, moving and resizing no longer repaints the (up to 9000 px wide) image. Per-event CPU time on a dual 2560×1440 + 1920×1080 setup dropped from about 2.7 ms to 0.3 ms, and leftover patches of un-dimmed screen cannot happen by construction.
- Blur tool shows a light preview while dragging and pixelates when you release the mouse.
- Magnifier no longer gets clipped at the right screen edge.
- Fixed a memory leak that kept every capture in memory (about 100 MB each on a dual-monitor setup).
- Only `http(s)` links returned by upload hosts are opened or copied.
- Capture runs on all screens in parallel (about 2.5× faster), encoding and disk writes moved off the main thread.
- Scroll capture keeps only new rows instead of every frame (large pages no longer use hundreds of MB); GIF export is capped at 240 frames.
- Double-pressing the hotkey no longer opens two capture screens; a host that just failed is tried last for 10 minutes.
- New: app icon, `tests/run.sh`, `ADHOC=1` / `NO_INSTALL=1` build options.

## 1.0.0
- Initial release: multi-monitor capture, annotation tools, upload hosts (freeimage.host, pixhost.to, uguu.se, ImgBB, Imgur, S3/R2), OCR, pin to screen, scroll capture, screen recording (MOV/GIF), link formats and QR code.
