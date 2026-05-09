<p align="center">
  <img src="https://github.com/openpeeps/groovebox/blob/main/.github/groovebox_logo.png" width="90px"><br>
  Groovebox 📦 Badass CLI app for streaming to Twitch, Youtube,<br>any RTMP servers and 🧊 Icecast-compatible servers<br><br>
  Fast &bullet; Lightweight &bullet; Compiled &bullet; 👑 Written in Nim language
</p>

<p align="center">
  <code>nimble install groovebox</code>
</p>

<p align="center">
  <a href="https://github.com/">API reference</a><br>
  <img src="https://github.com/openpeeps/groovebox/workflows/test/badge.svg" alt="Github Actions">  <img src="https://github.com/openpeeps/groovebox/workflows/docs/badge.svg" alt="Github Actions">
</p>

> [!NOTE]
> Groovebox is still in active development. Expect bugs and incomplete features!

## About
**Groovebox is a lightweight CLI application for live streaming pre-recorded playlists of media to YouTube, Twitch and other RTMP (Real-Time Messaging Protocol) servers**. Comes with a built-in RTMP server implementation that can be used to receive and redistribute streams to other clients.

Also, with Groovebox you can stream music to Icecast-compatible servers! It is designed to be **fast**, **memory-efficient**, and **easy to use**, making it ideal for streaming sessions and internet radio stations.

## 😍 Key Features
- 🔥 Compiled, **extremely lightweight**, and **super fast**
- 🎵 Supports **MP3, OGG Vorbis, OGG Opus, AAC**, and more via external encoders
- 📸 RTMP (Real-Time Messaging Protocol) support for future expansion
- 👌 Icecast Client compatible with **Icecast2 servers**
- 📀 **Zero-copy Media Streaming** for maximum performance and minimal memory usage
- 🔀 Shuffle tracks in playlist
- Works on **Linux** and **macOS**
- 🎩 Open Source | AGPLv3 License
- 👑 Written in Nim language | Made by Humans from OpenPeeps

> [!NOTE]
> Groovebox does not provide an encoder/decoder (codec) implementation. It is intended to be used for streaming pre-encoded audio/video via tools such as ffmpeg.


## Install
Using [Nimble](https://nim-lang.org/install.html), the package manager for Nim:
```bash
nimble install groovebox
# or install from GitHub
nimble install https://github.com/openpeeps/groovebox
```

Otherwise, get the latest release from the [Releases](https://github.com/openpeeps/groovebox/releases) page (soon).

## Usage
After installing Groovebox, you can run the `groovebox -h` command in your terminal to see the available options and commands.

```
$ groovebox -h

  ________                              ___________              
 /  _____/______  ____   _______  __ ____\______   \ _______  ___
/   \  __\_  __ \/  _ \ /  _ \  \/ // __ \|    |  _//  _ \  \/  /
\    \_\  \  | \(  <_> |  <_> )   /\  ___/|    |   (  <_> >    < 
 \______  /__|   \____/ \____/ \_/  \___  >______  /\____/__/\_ \
        \/                              \/       \/            \/
Live stream pre-recorded music to Twitch, Yotube and Icecast servers
  (c) George Lemon | AGPL-3.0-or-later License  
  Build Version: 0.1.0
  
  init <config:path>                    Initialize a new Groovebox Configuration file
Streaming
  icecast <config:path>                 Stream media to a Icecast server
  rtmp ▲                                
    server <config:path>             Start a local RTMP server to receive streams
    stream <config:path>             Stream media to a RTMP server
Media Tools
  flv <in:path> <out:filepath>          Convert media to FLV format for RTMP streaming
  aac <in:path> <out:filepath>          Convert audio to AAC format for RTMP streaming
    --kbs
  ogg <in:path> <out:filepath>          Convert audio to OGG format for Icecast streaming
    --kbs
```

# Groovebox for Icecast

Groovebox streams directly to any Icecast server using minimal memory and CPU, as it does **not** re-encode media files. Instead, it streams pre-encoded OGG files, allowing for high-quality audio streaming with excellent performance.

> **Note:** You must pre-encode your media files to OGG format before streaming with Groovebox. Live effects and controls (like those in Liquidsoap or other live re-encoding software) are not available.

**Groovebox is ideal for:**  
- Backyard radio stations  
- Parties  
- Coffee shops  
- Small venues  

---

## Preparing Media for Streaming

Groovebox provides built-in commands to prepare your media:

- **For RTMP streaming:**  
  - `flv` – Convert video files to FLV format  
  - `aac` – Convert audio files to AAC format  
- **For Icecast streaming:**  
  - `ogg` – Convert audio files to OGG format  

> Groovebox uses `ffmpeg` under the hood. Make sure `ffmpeg` is installed and available in your system `PATH`.

---

## Configuration

Groovebox uses a YAML configuration file (`groovebox.config.yaml`) to specify streaming settings, such as server URLs, stream keys, and playlist paths.  

You can create this file with `groovebox init` or manually.

## Icecast Server
Recently added support for a built-in Icecast-compatible server implementation so you don't need to install any third-party software to for streaming. Starting the server is simple:

```bash
groovebox icecast.server groovebox.config.yaml
```
_todo showcase the config file for the server_

## Icecast Streaming
To stream to an Icecast server using the `groovebox icecast.stream` command, configure your `groovebox.config.yaml` as follows:

```yaml
type: icecast
icecast:
  connection:
    address: localhost
    port: 8000
    mountPoint: "/stream"
    playlists:
      - "playlist.txt"
```

---

# Groovebox for RTMP (Real-Time Messaging Protocol)

Groovebox can stream to any RTMP server, including YouTube and Twitch. You’ll need the RTMP URL and Stream Key from your platform.

---

## RTMP Stream Server

Start the built-in RTMP server to receive and redistribute streams:

```bash
groovebox rtmp.server .
```

- The server listens on `rtmp://127.0.0.1:1935` by default.
- No specific config is required; use `.` to skip CLI validation.

---

## RTMP Stream Client

Use the `rtmp.stream` command to stream media to an RTMP server.  
Configure your `groovebox.config.yaml` as follows:

```yaml
type: rtmp
stream:
  url: "rtmp://live.twitch.tv/app/your_stream_key"
  video:
    - "./videoplaylist.txt"
  audio:
    - "./audioplaylist.txt"
```

### Groovebox vs Other Streaming Solutions

| Feature                        | Groovebox           | ffmpeg                | AzuraCast           | OBS Studio / Others      |
|---------------------------------|---------------------|-----------------------|---------------------|--------------------------|
| **Simplicity**                  | ✅ Simple CLI, no complex commands | ❌ Complex CLI, scripting required | ✅ Web UI, but more setup | ❌ Complex UI, many options |
| **Playlist Management**         | ✅ Built-in, shuffle support       | ❌ Manual, external scripts needed | ✅ Advanced, web-based   | ❌ Manual, scene-based      |
| **Zero-Copy Streaming**         | ✅ Yes, direct file-to-network     | ❌ Loads into memory/buffers      | ❌ Not zero-copy         | ❌ Not zero-copy            |
| **Lightweight**                 | ✅ Very lightweight                | ✅ Lightweight, but less focused  | ❌ Heavy, Docker-based   | ❌ Heavy, needs GPU/CPU     |
| **No GPU Required**             | ✅ Never required                  | ✅ Not required for audio         | ✅ Not required          | ❌ Often required for video |
| **Ideal for VPS**               | ✅ Yes, low resource usage         | ✅ Yes, but needs scripting       | ❌ Needs more resources  | ❌ Not ideal, high resource |
| **Live Effects/Processing**     | ❌ Not supported                   | ✅ Supported via filters          | ✅ Supported             | ✅ Supported                |
| **Web Interface**               | ❌ CLI only                        | ❌ None                          | ✅ Yes                   | ✅ Yes                      |
| **Built-in Server**             | ✅ RTMP & Icecast compatible       | ❌ No                            | ✅ Yes                   | ❌ No                       |
| **Open Source**                 | ✅ Yes (AGPLv3)                    | ✅ Yes (LGPL/GPL)                | ✅ Yes (AGPLv3)          | ✅ Yes                      |

> **Note:** Groovebox is designed for streaming pre-encoded playlists with maximum efficiency and minimal setup, making it ideal for simple, automated streaming scenarios.

## Roadmap
Source Client
- [ ] Handle multiple playlists
- [x] Zero-copy live streaming pre-recorded media to RTMP servers
- [x] Support for streaming to Icecast-compatible servers
- [x] Support for streaming to YouTube/Twitch RTMP servers
- [x] Shuffle playlists
- [ ] Improve the shuffle algorithm (ensure no repeats until all tracks played)
- [ ] Add support for more audio formats
- [ ] Add support for video streaming
- [ ] Add web interface for monitoring and control
- [ ] Support ads insertion
- [ ] Live streaming from non non-seekable sources (e.g. stdin) via ffmpeg

Server
- [x] Implement a Icecast-compatible based on Libevent
- [ ] Middleware Authentication using JWT
- [ ] Subscriber management
- [ ] Rate Limiting and Anti-abuse
- [ ] Analytics and Reporting Dashboard

### ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeeps/groovebox/issues)
- 👋 Wanna help? [Fork it!](https://github.com/openpeeps/groovebox/fork)
- 😎 [Get €20 in cloud credits from Hetzner](https://hetzner.cloud/?ref=Hm0mYGM9NxZ4)

### 🎩 License
AGPLv3 license. [Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright OpenPeeps & Contributors &mdash; All rights reserved.
