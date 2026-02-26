# Groovebox - A CLI application for live streaming pre-recorded media
# to Icecast servers and platforms like Twitch and YouTube. 
#
# (c) 2026 George Lemon | AGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/groovebox

import std/[options, net]

type
  IcecastCredentials* = ref object
    ## Credentials for authenticating with an Icecast server
    username*: string
      ## The username for authentication
    password*: string
      ## The password should be kept secure and not logged or exposed

  IcecastSourceConnection* = ref object
    ## Connection configuration for the media source
    address*: Option[string]
      ## The address of the Icecast server (e.g., "localhost" or "
    port*: Port 
      ## The port number of the Icecast server (e.g., 8000)
    mountPoint*: Option[string]
      ## The mount point on the Icecast server (e.g., "/stream")
    credentials*: Option[IcecastCredentials]
      ## Optional credentials for authentication with the Icecast server

  GrooveboxPreferences* = object
    ## User preferences for Groovebox
    reconnectDelaySec*: int = 5
      ## Delay in seconds before attempting to reconnect after a disconnection
    targetKbps*: int = 128
      ## Target bitrate in kilobits per second for streaming
      ## Default is 128 kbps
    shuffleTracks*: bool = true
      ## Whether to shuffle tracks when streaming from a playlist
      ## Default is true

  IcecastConfig* = ref object
    ## Configuration for the media source
    connection*: IcecastSourceConnection
      ## Connection configuration for the source
    playlists*: seq[string]
      ## List of playlist file paths to stream from
    settings*: GrooveboxPreferences
      ## User preferences for Groovebox
  
  RtmpPlaylist* = ref object of RootObj
    ## Base playlist object for RTMP streaming
    files: seq[string]
      ## List of file paths in the playlist

  RtmpVideoPlaylist* = ref object of RtmpPlaylist

  RtmpAudioPlaylist* = ref object of RtmpPlaylist

  RtmpConfig* = ref object
    ## Configuration for the RTMP client
    url*: string
      ## The RTMP server URL (e.g., "rtmp://a.rtmp.youtube.com/live2/streamkey")
    video: seq[string]
      ## List of video playlists file paths
    audio: seq[string]
      ## List of audio playlists file paths
    settings*: GrooveboxPreferences
      ## User preferences for Groovebox

  GrooveboxType* = enum
    ## Types of Groovebox streaming protocols
    grooveboxTypeIcecast = "icecast"
    grooveboxTypeRtmpServer = "rtmpserver"
    grooveboxTypeRtmpStream = "rtmpstream"

  GrooveboxConfig* = ref object
    ## Configuration for Groovebox
    case `type`*: GrooveboxType
      ## The type of Groovebox (e.g., Icecast, RTMP)
    of grooveboxTypeIcecast:
      icecast*: IcecastConfig
        ## The Icecast client for streaming media
    of grooveboxTypeRtmpStream:
      stream*: RtmpConfig
        ## The RTMP client for streaming media
    of grooveboxTypeRtmpServer:
      discard

  GrooveboxApp* = ref object
    ## Main application object for Groovebox
    config*: GrooveboxConfig
      ## The configuration instance for Groovebox

var GConfig*: GrooveboxConfig
  ## Global configuration instance for Groovebox

const
  cliHeading* = """
    ________                               __________              
   /  _____/______  ____   _______  __ ____\______   \ _______  ___
  /   \  __\_  __ \/  _ \ /  _ \  \/ // __ \|    |  _//  _ \  \/  /
  \    \_\  \  | \(  <_> |  <_> )   /\  ___/|    |   (  <_> >    < 
   \______  /__|   \____/ \____/ \_/  \___  >______  /\____/__/\_ \
          \/                              \/       \/            \/
                  Groovebox is up & streaming!
                        * * * * * * *
  """
