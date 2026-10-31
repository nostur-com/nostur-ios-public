# Video posting improvements

Privacy requirement: never upload an original video as a fallback. Build a fresh
MP4 containing only newly encoded video/audio, with no source metadata or metadata
tracks. Any future compressed-sample bypass needs its own privacy verification.

- [x] Verify metadata removal, including location, dates, device and author data.
- [x] Keep attachments on failure; add preparation/upload progress, cancel and retry.
- [x] Reuse prepared files on retry; encode short-video edits only once.
- [x] Automatically size large videos; retain the existing bitrate formula at 1080p and below.
- [x] Offer higher quality and an explicit smaller-file retry.
- [x] Avoid unnecessary Photos transcoding.
- [x] Use file-backed public video uploads; keep file reads/hashing off the UI executor.
- [x] Explicitly convert HDR to SDR and preserve orientation/audio synchronization.
- [x] Report oversized uploads separately from network/authentication failures.
- [x] Run focused privacy/encoding/upload tests, build, install and launch.
- [ ] Physical-iPhone checks: HDR colors, screen-recording text, motion, cancellation,
  retry after network loss, and responsiveness during active imports.

Existing unrelated feed/localization/cloud-build edits must be preserved.

## Verification so far

- Initial build installed/launched successfully on iPhone 17 Pro / iOS 26.5.
- First focused suite passed: source privacy markers removed at all three quality
  settings; portrait orientation, exact trimming, audio/mute, cache reuse, multipart
  body hashing, HTTP error classification and partial-preparation refusal checked.
- Final focused suite passed: 38 tests (8 XCTest + 30 Swift Testing), including
  real 10-bit HLG -> SDR conversion, actual downscaling, active encode/file-upload
  cancellation, NIP-96 response validation and delayed processing without a repeated
  processing URL, plus existing Blossom/preview metadata coverage.
- Tests used the existing iPhone 17 Pro / iOS 26.5 simulator with parallel testing
  disabled. The test device set stayed at its original 44 devices: no new clones.
  Existing test-device storage is 492 GB; pre-existing devices were left untouched.
- Final app built, installed and launched with `./scripts/run-sim.sh --no-ui` on
  iPhone 17 Pro / iOS 26.5. Sidebar TEST_BUILD_ID: `f32b7500`.
- `git diff --check` passed. No live-server uploads or public posts were made.
- No compressed-sample/original-file bypass: deliberately retain fresh encoding
  until an alternative has equivalent privacy evidence. Low-bitrate H.264 sources are
  no longer raised to the usual bitrate floor.
- Physical-device visual quality and active-import responsiveness remain unverified.

## Physical-device installation (2026-10-31)

- Device build succeeded and installed on Fabian’s iPhone 18 Pro Max.
- Device TEST_BUILD_ID: `bc555855`.
- Launched successfully after the phone was unlocked.
- Installation alone does not verify the physical-device checklist above.

## Normal-post camera recording (2026-10-31)

- [x] Offer Take Photo / Record Video from the normal composer camera action.
- [x] Use the system full-screen camera with review/retake (default ten-minute
  recording limit), separate from the six-second short-video recorder.
- [x] Copy the reviewed recording into the draft off the UI executor, before
  dismissing the camera. Keep the recording available for Retry on copy failure.
- [x] Route the attachment through the existing metadata-checked preparation.
- [x] Update camera/microphone purpose descriptions to include video recording.
- [x] Run focused recording/privacy and composer toolbar tests.
- [x] Build and launch the final app in the simulator (`9a1aa27f`, iPhone 17 Pro).
- [x] Build/install/launch the new recording flow on the physical phone (`fb739dbe`, iPhone 18 Pro Max).
- [ ] Physical-device check: record with audio, retake/cancel, attach to a normal
  post and confirm preview/orientation before posting.

Recording validation: 15 video preparation/privacy tests passed on iOS 26.5.
The iOS-27-only composer toolbar rendering test passed on iOS 27.0. Its first
run on iOS 26.5 failed because that runtime uses a different toolbar; no toolbar
code was changed to accommodate the test. No new test clones were created.

The new recording build was installed and launched on the phone successfully.
Final simulator build: `9a1aa27f`. Test-device storage remains 492 GB with no new
clones. No camera recordings or live posts were made by the agent; the hardware
record/review/retake flow remains a manual check.

## Camera UX refinement (2026-10-31)

- [x] Remove the Take Photo / Record Video confirmation popup.
- [x] Open normal-post camera directly in Photo mode, with the native Photo / Video switch.
- [x] Retain system review/retake, metadata-safe uploads, and retry on attachment failure.
- [x] Keep picture-only posts on their existing camera flow.
- [x] Build/launch the revised camera in the simulator (`5153616d`).
- [x] Install/launch the revised camera on the phone (`f4cc5076`).
- [ ] Manual camera check on the phone (the simulator has no camera).
