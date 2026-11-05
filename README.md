#
<p align="center">
<img src="./client/Icon-72.png" />
<h1 align="center">OldSend</h1>
<h3 align="center">A native LocalSend-compatible client for iOS 3.1.3 and later</h3>
</p>

[简体中文](README_zh.md)

## About this fork

A fork of [lihaoyun6/OldSend](https://github.com/lihaoyun6/OldSend) for iOS 6 on Retina iPhones (tested on an iPhone 4S, iOS 6.1.3). Changes from upstream:

- **Sending to LocalSend on desktop works again.** LocalSend 1.17 answers with `Transfer-Encoding: chunked`, which the client did not read, so every send to a desktop failed. The client now decodes chunked replies.
- **Live transfer screen**, like LocalSend's: every file with its own progress and state (waiting, sending, done, skipped, failed), plus overall progress, files, size, speed and time left, with Cancel while it runs. Files the receiver leaves out are skipped instead of failing the whole send.
- **OldSend in the share sheet of every app.** A small MobileSubstrate add-on (`share/`) puts an OldSend button into the iOS 6 share sheet (Safari, Photos and any app using `UIActivityViewController`); links, text, photos, videos and files shared with it open in OldSend's Send tab, ready to send. OldSend also appears under "Open in…" for any file.
- **Save to Photos switch** in Settings: turn it off to keep received photos and videos in History only.
- **Keeps working after switching apps.** iOS reclaims the sockets of a suspended app, which used to stop OldSend from receiving until it was restarted. It now reopens them when it returns to the foreground, asks iOS for a few minutes of background time so transfers can finish, and posts a notification for incoming requests while in the background.
- **Sharp on Retina screens.** Every interface image has an @2x version, the app icon is redrawn at all sizes, the file-type icons are a new vector-drawn set (`tools/make_file_icons.py`), since the originals only existed at 32 px, and there are launch images instead of a black screen at start.
- **Built in GitHub Actions** for armv7 / iOS 6+ (`ci/build-ios6.sh`), packaged as a `.deb` that iOS 6's dpkg accepts. Install the `.deb` (not an IPA): the app keeps its certificate in `/var/mobile/Library/OldSend`, which a sandboxed install cannot create.

New artwork uses [Material Icons](https://github.com/google/material-design-icons) (Apache-2.0). Files changed from upstream are listed in the git history.

## Preview

![OldSend preview](preview.png)

## Features

- Native Objective-C / UIKit application supporting iPhone/iPod touch/iPad, with no dependency on Flutter, Electron, or web runtimes.
- Compatible with LocalSend protocol v2.2: multicast discovery, register, prepare-upload, upload, and cancel.
- Implements the TLS 1.2 protocol using bundled mbedTLS 2.28.8.
- Supports sending photos, videos, text, and device files (with a built-in jailbroken filesystem browser).
- Simplified Chinese and English interfaces.

> A jailbroken device is required. OldSend is installed as a system app under `/Applications`.

## Installation

Download the `.deb` or `.ipa` from [releases](https://github.com/lihaoyun6/OldSend/releases/latest) page.

- `.deb`: install with Cydia, iFile or `dpkg -i OldSend_v1.0.1_iphoneos-arm.deb`.
- `.ipa`: install with AppSync / `installipa` on a jailbroken device. It is not an App Store-signed IPA.

## Build

Requirements: macOS, Xcode command line tools, the iPhoneOS 3.1.3 SDK, the iPhoneOS 4.2 SDK, and `ldid`.

```bash
export SDK=/path/to/iPhoneOS3.1.3.sdk
export SDK_DYLIB=/path/to/iPhoneOS4.2.sdk

./build.sh            # universal armv6 + armv7 -> build/OldSend.app
./build.sh armv6      # armv6 only -> build/OldSend.app
./build.sh armv7      # armv7 only -> build-armv7/OldSend.app
./build.sh clean      # remove build/ and build-armv7/
```

The main app is built with the 3.1.3 SDK. The photo/video picker lives in `MediaPicker.dylib`, built separately with the 4.2 SDK for armv6 + armv7 with a minimum of iOS 4.0. On iOS 3 the dylib fails to load and the app falls back to the system picker.

`JOBS=N ./build.sh` controls parallel compilation. The SDKs default to `$TMPDIR/sdk/iPhoneOS3.1.3.sdk` and `$TMPDIR/sdk/iPhoneOS4.2.sdk`; override them with `SDK=` and `SDK_DYLIB=`.

To deploy manually:

```bash
scp -r build/OldSend.app root@<device-address>:/Applications/
ssh root@<device-address> 'killall -9 SpringBoard'
```

Launch OldSend from the home screen after SpringBoard restarts.

## Third-party

- [mbedTLS](https://github.com/Mbed-TLS/mbedtls) — Apache-2.0
- [cJSON](https://github.com/DaveGamble/cJSON) — MIT
- Some icons derived from [Material Icons](https://github.com/google/material-design-icons) — Apache-2.0
- Some code was generated using DeepSeek v4.1 Flash under human supervision.

> OldSend is an independent project and is not affiliated with the LocalSend project.
