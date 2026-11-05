#
<p align="center">
<img src="./client/Icon-72@2x.png" width="72" />
<h1 align="center">OldSend 2.0</h1>
<h3 align="center">A native LocalSend-compatible client for jailbroken iOS 6 devices</h3>
</p>

[简体中文](README_zh.md)

OldSend 2.0 is my version of [OldSend by lihaoyun6](https://github.com/lihaoyun6/OldSend), the native [LocalSend](https://localsend.org) client for old iPhones, made for iOS 6 on Retina iPhones (tested on an iPhone 4S, iOS 6.1.3). Send files, photos, videos, links and text between an old iPhone and any device running LocalSend.

## What's new in 2.0

- **Sending to LocalSend on desktop works again.** LocalSend 1.17 answers with `Transfer-Encoding: chunked`, which the client did not read, so every send to a desktop failed. The client now decodes chunked replies.
- **Live transfer screen**, like LocalSend's: every file with its own progress and state (waiting, sending, done, skipped, failed), plus overall progress, files, size, speed and time left, with Cancel while it runs. Files the receiver leaves out are skipped instead of failing the whole send.
- **OldSend in the share sheet of every app.** A small MobileSubstrate add-on (`share/`) puts an OldSend button into the iOS 6 share sheet (Safari, Photos and any app using `UIActivityViewController`); links, text, photos, videos and files shared with it open in OldSend's Send tab, ready to send. OldSend also appears under "Open in…" for any file.
- **Run in Background** (Settings, off by default): a background service (the same binary, started by launchd at boot, `client/OSDaemon.m`) keeps the phone discoverable and able to receive with OldSend closed. Incoming requests show a notification; tapping it opens OldSend with the Accept / Decline prompt and the live transfer screen. The app and the service hand the port to each other automatically, the service follows Wi-Fi network changes, and it keeps the phone awake only while files are coming in. While the phone sleeps, iOS pauses it like any app, so it costs no battery while waiting.
- **Save to Photos switch** in Settings: turn it off to keep received photos and videos in History only.
- **Keeps working after switching apps.** iOS reclaims the sockets of a suspended app, which used to stop OldSend from receiving until it was restarted. It now reopens them when it returns to the foreground, asks iOS for a few minutes of background time so transfers can finish, and posts a notification for incoming requests while in the background.
- **More robust receiving:** waits out Wi-Fi stalls of up to 20 seconds instead of 5, and no longer stays "busy" forever when a sender disappears after you accept.
- **Sharp on Retina screens.** Every interface image has an @2x version, the app icon is redrawn at all sizes, the file-type icons are a new vector-drawn set (`tools/make_file_icons.py`), since the originals only existed at 32 px, and there are launch images instead of a black screen at start.

## Features

- Native Objective-C / UIKit app, with no dependency on Flutter, Electron, or web runtimes.
- Compatible with LocalSend protocol v2.2: multicast discovery, register, prepare-upload, upload, and cancel.
- TLS 1.2 with bundled mbedTLS 2.28.8.
- Sends photos, videos, text, links and any file (with a built-in filesystem browser), and receives into History, with photos and videos copied to Photos.
- Simplified Chinese and English interfaces.

> Requires a jailbroken device with iOS 6 or later (armv7) and MobileSubstrate. OldSend is installed as a system app under `/Applications`.

## Installation

Add the **ios-legacy** source to Cydia, `https://itsallexb.github.io/ios-legacy/`, and install OldSend. Or download the `.deb` from this repository's releases and install it with `dpkg -i`.

Install the `.deb`, not an IPA: OldSend keeps its TLS identity in `/var/mobile/Library/OldSend`, which a sandboxed IPA install cannot create.

## Build

GitHub Actions builds the `.deb` on every push (`.github/workflows/build-ios6.yml`), with `ci/build-ios6.sh`: Theos' iOS toolchain for Linux, the iOS 9.3 SDK (the newest with armv7) and Procursus `ldid`. The script compiles the app, `MediaPicker.dylib`, the share add-on and packages them with the launchd job, using `dpkg-deb` so that iOS 6's dpkg accepts the archive.

Upstream's `build.sh` (macOS, iPhoneOS 3.1.3 SDK, armv6) is still in the repository but doesn't build 2.0, which uses iOS 6 APIs throughout.

## Credits

- **[lihaoyun6](https://github.com/lihaoyun6)** made [OldSend](https://github.com/lihaoyun6/OldSend), which this is built on: the native UI, the LocalSend implementation on mbedTLS, the media picker and the file browser. Thank you!
- **The [LocalSend](https://localsend.org) team** created LocalSend and its open protocol, which is what lets an iPhone from 2011 talk to today's phones and computers. Thank you!
- OldSend 2.0 changes by [itsAllexB](https://github.com/itsAllexB). The credits are in the app too, under Settings > About.

## Third-party

- [mbedTLS](https://github.com/Mbed-TLS/mbedtls) — Apache-2.0
- [cJSON](https://github.com/DaveGamble/cJSON) — MIT
- Icons drawn from [Material Icons](https://github.com/google/material-design-icons) — Apache-2.0
- Upstream notes that some of its code was generated using DeepSeek v4.1 Flash under human supervision.

OldSend is licensed under Apache-2.0, like the original; files changed from upstream are listed in the git history.

> OldSend is an independent project and is not affiliated with the LocalSend project.
