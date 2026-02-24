# Groovebox - A CLI application for live streaming pre-recorded media
# to Icecast servers and platforms like Twitch and YouTube. 
#
# (c) 2026 George Lemon | AGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/groovebox

import pkg/kapsis
import ./groovebox/commands

commands do:
  ##__________                              ___________              
  ## /  _____/______  ____   _______  __ ____\______   \ _______  ___
  ##/   \  __\_  __ \/  _ \ /  _ \  \/ // __ \|    |  _//  _ \  \/  /
  ##\    \_\  \  | \(  <_> |  <_> )   /\  ___/|    |   (  <_> >    < 
  ## \______  /__|   \____/ \____/ \_/  \___  >______  /\____/__/\_ \
  ##        \/                              \/       \/            \/
  init path(`config`):
    ## Initialize a new Groovebox Configuration file

  -- "Streaming"
  icecast path(`config`):
    ## Stream media to a Icecast server

  rtmp:
    server path(`config`):
      ## Start a local RTMP server to receive streams

    stream path(`config`):
      ## Stream media to a RTMP server
  
  -- "Media Tools"
  # Commands for converting media files to formats suitable for streaming.
  # These commands use ffmpeg under the hood to perform the necessary conversions.
  flv path(`in`), filepath(`out`):
    ## Convert media to FLV format for RTMP streaming

  aac path(`in`), filepath(`out`), ?int(--kbs):
    ## Convert audio to AAC format for RTMP streaming
  
  ogg path(`in`), filepath(`out`), ?int(--kbs):
    ## Convert audio to OGG format for Icecast streaming