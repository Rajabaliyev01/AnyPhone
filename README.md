# 📱 AnyPhone

<p align="center">
  <b>Seamless Android Screen Mirroring & Calling Bridge for macOS</b><br>
  <i>Built natively with Swift (macOS) and Java (Android)</i>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0%2B-blue?logo=apple" alt="macOS" />
  <img src="https://img.shields.io/badge/Android-10.0%2B-green?logo=android" alt="Android" />
  <img src="https://img.shields.io/badge/Language-Swift%20%7C%20Java-orange" alt="Language" />
  <img src="https://img.shields.io/badge/License-Apache%202.0-brightgreen" alt="License" />
</p>

---

## 🌟 Overview
**AnyPhone** is a lightweight, ultra-fast macOS application designed to bring the magic of Apple's **iPhone Mirroring** to **any Android phone** (including Samsung Galaxy A15, Google Pixel, Xiaomi, and more).

Unlike heavy third-party emulators, AnyPhone communicates directly with Android internal hardware services to deliver:
- ⚡ **Zero-latency (60 FPS) screen mirroring** powered by Apple VideoToolbox & Metal.
- 📞 **Mac-to-Phone Calling:** Dial numbers directly from macOS, talk through your Mac's microphone, and listen through Mac speakers.
- 📴 **Screen-Off Mode:** Control your Android device with the physical phone screen turned completely off (saving battery & keeping the phone cool).
- 🖱 **Complete Touch & Keyboard Navigation:** Full swipe, click, scroll, and clipboard sync.

---

## 🏗 Architecture
- **`AnyPhone-macOS`**: Native macOS client written in **SwiftUI**. Handles video rendering, Mac audio capture/playback, and input events.
- **`AnyPhone-Server`**: Lightweight Android service written in **Java**. Streams H.264/H.265 video frames and bridges two-way audio channels.

---

## 🚀 Quick Start
### Prerequisites
1. Enable **Developer Options** and **USB Debugging** on your Android device.
2. Connect your device via USB or ensure both Mac and Android are on the same Wi-Fi network.

---

## 📄 License
This project is licensed under the [Apache 2.0 License](LICENSE).
Author: [Rajabaliyev01](https://github.com/Rajabaliyev01)
