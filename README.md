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

### How it works?
It streams files (one-by-one) from playlists; it does not capture live camera or microphone input. Also, **Groovebox does not require any GPU acceleration as it does not perform any video encoding or decoding itself.** Still, you can use the predefined CLI commands to convert media files to formats suitable for streaming using ffmpeg.

Groovebox media streams are sourced from local audio files (MP3, OGG Vorbis, OGG Opus, AAC, and more) from a specific `txt` playlist file and streamed directly to an **Icecast2-compatible** server or **RTMP servers** with **zero-copy audio/video streaming**, allowing for efficient streaming of large media files without consuming excessive system resources.

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

__________                              ___________              
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

## Prepare media for streaming
Use the built-in Groovebox commands to prepare your media files for streaming. For RTMP streaming you can use the `flv` command to convert your video files to FLV format, and the `aac` command to convert your audio files to AAC format. For Icecast streaming, you can use the `ogg` command to convert your audio files to OGG format.

Note: Groovebox is using the `ffmpeg` under the hood to convert audio/video files, so you need to have `ffmpeg` installed on your system and available in your PATH for these commands to work.

## Groovebox Configuration
Groovebox uses a YAML configuration file to specify the streaming settings, including the RTMP server URL, Stream Key, and playlist paths. You can create a new configuration file using the `groovebox init` command, or you can create it manually. The configuration file should be named `groovebox.config.yaml` and placed in the root of streaming project.

## Icecast Streaming
To stream to an Icecast-compatible server, you will need to provide the server address, port, mount point, and the playlist file in the `groovebox.config.yaml` file:
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

## RTMP Streaming
Groovebox can stream to any RTMP server, including YouTube and Twitch. To stream to an RTMP server, you will need the RTMP URL and Stream Key from your streaming platform.

### RTMP Stream Server
Use the high-performance built-in RTMP server to receive and redistribute streams to other clients. To start the RTMP server, run:

Currently there is no specific config for the Groovebox RTMP server, you can use `.` to skip cli validation and run the server directly:

```
groovebox rtmp.server .
```

The server will listen on rtmp://127.0.0.1:1935 by default.

### RTMP Stream Client
Use the `rtmp.stream` command to stream media to a RTMP server. The `groovebox.config.yaml` file should specify the RTMP server url and the playlists for video and audio:

```yaml
# stream media to an RTMP server
type: rtmp
stream:
  url: "rtmp://127.0.0.1/live/livestream"
  video:
    - "./videoplaylist.txt"
  audio:
    - "./audioplaylist.txt"
```

### Why use Groovebox instead of ffmpeg/OBS Studio for streaming to RTMP servers?
- 👌 **Simplicity**: Groovebox provides a simple and intuitive interface for streaming pre-recorded media to RTMP servers, without the need to write complex ffmpeg command lines.
- 🎧 **Playlist Management**: Groovebox has built-in support for managing playlists, allowing you to easily organize and shuffle your media files for streaming sessions.
- 📁 **Zero-Copy Streaming**: Groovebox is designed to stream media directly from the source file to the network without fully loading it into memory, which makes it more efficient for streaming large media files without consuming excessive system resources.
- 🕊 **Lightweight**: Groovebox is a lightweight application that is optimized for streaming, while ffmpeg is a powerful multimedia framework that can be used for a wide range of media processing tasks, which may be overkill for simple streaming use cases.
- 💪 **No GPU required**: OBS Studio is a popular streaming software that provides advanced features for live streaming, but it requires GPU acceleration for video encoding and processing, which may not be available on all systems. Groovebox, on the other hand, does not require any GPU acceleration as it does not perform any video encoding or decoding itself.
- 💫 **Ideal for VPS streaming**: Groovebox is designed to be fast and efficient, making it ideal for streaming sessions from a basic VPS (Virtual Private Server) without the need for a GPU, or too much CPU/RAM resources.


### FAQs
Here are some questions and answers about Groovebox, so you can better understand its capabilities and limitations:

#### Can I use Groovebox for live streaming from a webcam or microphone?
No, Groovebox is designed for streaming pre-recorded media files from playlists. It does not capture live input from webcams or microphones. For live streaming from a webcam or microphone, you may want to use software like OBS Studio or Streamlabs.

#### Can I use Groovebox for streaming video content?
Yes, Groovebox can be used for streaming video content to RTMP servers. However, it does not perform any video encoding or decoding itself, so you will need to ensure that your video files are in a format that is compatible with your streaming platform and that they are properly encoded for streaming. You can use the built-in CLI commands to convert media files to formats suitable for streaming using ffmpeg.

#### Can I use Groovebox for streaming to platforms other than YouTube and Twitch?
Yes, Groovebox can stream to any RTMP server, including platforms other than YouTube and Twitch. You will need to obtain the RTMP URL and Stream Key from your streaming platform and configure Groovebox accordingly.


#### Is Groovebox just a client for streaming to external RTMP servers, or does it also include a server implementation?
Groovebox includes both a client for streaming to external RTMP servers and a built-in RTMP server implementation that can be used to receive and redistribute streams to other clients. You can use the built-in RTMP server to set up your own streaming server or to receive streams from other sources.

#### Can I use Groovebox for streaming to Icecast-compatible servers?
Yes, Groovebox is designed to be compatible with Icecast2 servers, allowing you to stream audio content to Icecast-compatible servers. You can configure Groovebox to stream your media files to an Icecast-compatible server by providing the necessary server details in the configuration file.

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
- [ ] Implement a Icecast-compatible based on Libevent
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
