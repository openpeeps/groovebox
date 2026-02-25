# Groovebox - A CLI application for live streaming pre-recorded media
# to Icecast servers and RTMP platforms like Twitch and YouTube. 
#
# (c) 2026 George Lemon | AGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/groovebox

## This module defines the CLI commands for Groovebox using the kapsis package
## Each command corresponds to a specific functionality of Groovebox, such as initializing
## a configuration file, streaming to an Icecast server, running a local RTMP server,
## streaming to an RTMP server, and converting media files to formats suitable for streaming.

import std/[os, osproc, unidecode, strutils, posix]
from std/net import Port, `$`

import pkg/[malebolgia, nyml]
import pkg/kapsis/[runtime, cli]
import pkg/kapsis/interactive/spinny

import ./ice, ./config
export icecastCommand


proc initCommand*(v: Values) =
  ## Initialize a new Groovebox Configuration file
  echo "todo"

proc slugify*(str: string, sep: static char = '-', allowSlash: bool = false): string =
  ## Convert `input` string to a ascii slug. Taken from Supranim package
  var x = unidecode(str.strip())
  result = newStringOfCap(x.len)
  var i = 0
  while i < x.len:
    case x[i]
    of Whitespace:
      inc i
      try:
        while x[i] notin IdentChars:
          inc i
        add result, sep
      except IndexDefect: discard
    of PunctuationChars:
      inc i
      if result.len == 0: continue
      if allowSlash and x[i - 1] == '/':
        add result, '/'
        continue
      try:
        while x[i] notin IdentChars:
          inc i
        add result, sep
      except IndexDefect:
        discard
    else:
      add result, x[i].toLowerAscii
      inc i

import pkg/rtmp

proc serverCommand*(v: Values) =
  ## Kapsis command for running RTMP server
  display(cliHeading)
  let configPath = v.get("config").getPath
  var rtmpServer = newRTMPServer()
  display("Starting RTMP server on port " & $rtmpServer.settings.rtmpPort)
  rtmpServer.startServer()

proc streamCommand*(v: Values) =
  ## Kapsis command for runningg RTMP client with playlist support
  display(cliHeading)
  let configPath = normalizedPath(getCurrentDir() / $(v.get("config").getPath))
  if configPath.endsWith(".yml") or configPath.endsWith(".yaml"):
    GConfig = fromYaml(readFile(configPath), GrooveboxConfig)
  elif configPath.endsWith(".json"):
    GConfig = fromJson(readFile(configPath), GrooveboxConfig)
  else:
    display("No Groovebox Config found in the current directory (.yml/.yaml/.json)")
    QuitFailure.quit
  display("Streaming to RTMP server: " & GConfig.stream.url)
  let client = newRtmpClient(GConfig.stream.url)
  # Load and shuffle playlists
  client.ps = PlaylistState(
    videoFiles: loadPlaylist("videoplaylist.txt"),
    audioFiles: loadPlaylist("audioplaylist.txt"),
    videoIdx: 0,
    audioIdx: 0
  )
  proc startNextVideo(client: RtmpClient, ps: PlaylistState) =
    # Start next video in playlist, or loop back to start if at
    # end and audio is still playing
    let videoPath = nextVideo(ps)
    if videoPath.len == 0 or (ps.currentAudioPath.len == 0 and ps.audioFiles.len > 0):
      ## debugEcho "[rtmp] No video or audio to play"
      return
    ## debugEcho "[rtmp] Streaming next video: ", videoPath, " with audio: ", ps.currentAudioPath
    startStreamFlvZeroCopy(client, videoPath, client.msgStreamId, startTs = ps.globalTs)

  proc startNextAudioAndVideo(client: RtmpClient, ps: PlaylistState) =
    # Start both audio and video
    client.ps.currentAudioPath = nextAudio(ps)
    client.ps.currentAudioDone = ps.currentAudioPath.len == 0
    if client.ps.audioFiles.len > 0 and client.ps.currentAudioDone:
      ## debugEcho "[rtmp] All audio files sent"
      return
    # client.ps.videoIdx = 0 # Optionally reset video playlist for each new audio
    let videoPath = client.ps.nextVideo()
    ## debugEcho "[rtmp] Streaming video: ", videoPath, " audio: ", client.ps.currentAudioPath
    startStreamFlvZeroCopy(client, videoPath, client.msgStreamId, startTs = client.ps.globalTs)
    startStreamAacAdtsZeroCopy(client, client.ps.currentAudioPath,
              client.msgStreamId, 4'u8, startTs = client.ps.globalTs)

  proc startNextAudioOnly(client: RtmpClient, ps: PlaylistState) =
    # Start only audio when video ended
    ps.currentAudioPath = nextAudio(ps)
    ps.currentAudioDone = ps.currentAudioPath.len == 0
    if ps.currentAudioDone: return # no more audio
    # Clear previous AAC state before starting new audio
    if client.aac != nil:
      if client.aac.fd >= 0:
        # close previous AAC file descriptor
        discard posix.close(client.aac.fd)
      client.aac = nil
    startStreamAacAdtsZeroCopy(client, ps.currentAudioPath,
          client.msgStreamId, 4'u8, startTs = ps.globalTs)

  client.onPublishOk = proc(c: RtmpClient) =
    # call startPacer and immediately start audio+video via the callback
    startPacer(c, proc(c2: RtmpClient) = startNextAudioAndVideo(c2, c2.ps))

  client.onStreamEnd =
    proc(c: RtmpClient, st: StreamState, sent: int) =
      ## debugEcho "[rtmp] Stream end, bytes=", sent
      ## debugEcho st.msgType
      if st.msgType == 0x09'u8: # Video ended
        if c.ps.videoIdx < c.ps.videoFiles.len:
          # check if there is more video to play
          startNextVideo(c, client.ps)
        elif c.ps.videoIdx == c.ps.videoFiles.len:
          # we are at the end of the video playlist
          # restart the video playlist if audio is still playing
          if not c.ps.currentAudioDone:
            c.ps.videoIdx = 0
            startNextVideo(c, client.ps)
      elif st.msgType == 0x08'u8: # Audio ended
        # c.ps.currentAudioDone = true
        startNextAudioOnly(c, c.ps)

  client.onStreamProgress =
    proc(c: RtmpClient, st: StreamState, sent: int) =
      ## debugEcho "[rtmp] Progress: ", st.offset, " / ", st.totalSize

  client.onStreamError =
    proc(c: RtmpClient, st: StreamState, err: cstring) =
      ## debugEcho "[rtmp] Stream error: ", err

  ## debugEcho "[rtmp] Starting event loop"
  discard event_base_dispatch(client.base)

  # Cleanup after loop exits
  if client.bev != nil: bufferevent_free(client.bev)
  if client.base != nil: event_base_free(client.base)

proc flvCommand*(v: Values) =
  ## Convert video files to FLV format for streaming
  let input = v.get("in").getPath
  let output = v.get("out").getFilepath()
  let kbs =
    if v.has("--kbs"):
      v.get("--kbs").getInt
    else: 11_021 # default to 10 Mbps

  let fps =
    if v.has("--fps"):
      v.get("--fps").getFloat
    else: 29.97 # default to 29.97 fps
  
  # checking if output file exists
  if output.fileExists:
    if not promptConfirm("Output file already exists. Overwrite? (y/n): "): return

  let cmd =
    "ffmpeg -y -i " & $input &
    " -c:v libx264 -preset veryslow -profile:v main -level:v 4.1 -pix_fmt yuv420p" &
    " -b:v " & $kbs & "k -minrate " & $kbs & "k -maxrate " & $kbs & "k -bufsize " & $(kbs * 2) & "k" &
    " -r " & $fps &
    " -g 60 -keyint_min 60 -sc_threshold 0" &
    " -bf 1 -x264-params \"repeat-headers=1\"" &
    " -force_key_frames \"expr:gte(t,0)\"" &
    " -vsync cfr -an -f flv " & output
  let res = execCmdEx(cmd)
  display(res.output) # always display ffmpeg output
  if not res.exitCode != 0: displaySuccess("Done!")

type
  ConvertAudioType* = enum
    ## Enum to specify audio conversion type for the aac and ogg commands
    ctOgg = "ogg", ctAac = "aac"

proc convertAudio*(audioType: ConvertAudioType, i, o: string, kbs: int) =
  ## Convert audio file to specified format using ffmpeg. This is a helper function used by the aac and ogg commands.
  let cmd = case audioType
    of ctOgg:
      "ffmpeg -y -i \"" & i & "\" -c:a libvorbis " & " -b:a " & $kbs & "k \"" & o & "\""
    of ctAac:
      "ffmpeg -y -i \"" & i & "\" -c:a aac -b:a " & $kbs & "k \"" & o & "\""
  let res = execCmdEx(cmd)

proc convertAudioProcess*(audioType: ConvertAudioType, input, output: string, kbs: int) =
  ## This is a helper function that handles both single file and batch conversion
  ## for the aac and ogg commands.
  let inputPath = absolutePath(input)
  let outputDir = absolutePath(output)
  if inputPath.dirExists():
    # passing a directory will walk through all files in 
    # the directory and convert them to OGG format in the same directory
    discard existsOrCreateDir(outputDir)
    var m = createMaster()
    var sp = newSpinny("Converting audio to $1 format..." % $audioType, skDots)
    sp.start()
    m.awaitAll:
      for entry in walkFiles(inputPath / "*"):
        if not entry.isHidden and entry.splitFile()[2] in [".mp3", ".wav", ".flac"]:
          let outFile = outputDir / slugify(entry.splitFile()[1], sep = '_') & "." & $audioType
          m.spawn(convertAudio(audioType, absolutePath(entry), outFile, kbs))
    sp.success("Conversion completed!")
    displayInfo("Output directory: " & outputDir)
  elif inputPath.fileExists():
    # single file conversion
    var sp = newSpinny("Converting audio to OGG format...", skDots)
    sp.start()
    let outputSplit = outputDir.splitFile()
    let outFile =
      if outputSplit.ext != "": outputSplit.dir / slugify(outputSplit.name, sep = '_') & "." & $audioType
      else: outputSplit.dir / slugify(inputPath.splitFile().name, sep = '_') & "." & $audioType
    convertAudio(audioType, inputPath.normalizedPath, outFile, kbs)
    sp.success("Conversion completed!")

proc aacCommand*(v: Values) =
  ## Convert audio files to AAC format
  let input = v.get("in").getPath
  let output = v.get("out").getFilepath()
  let kbs =
    if v.has("--kbs"):
      v.get("--kbs").getInt
    else: 128
  # checking if output file exists
  if output.fileExists:
    if not promptConfirm("Output file already exists. Overwrite? (y/n): "): return
  convertAudioProcess(ConvertAudioType.ctAac, input.path, output, kbs)

proc oggCommand*(v: Values) =
  ## Convert audio files to OGG format
  let input = v.get("in").getPath
  let output = v.get("out").getFilepath()
  let kbs =
    if v.has("--kbs"):
      v.get("--kbs").getInt
    else: 128
  # checking if output file exists
  if output.fileExists:
    if not promptConfirm("Output file already exists. Overwrite? (y/n): "): return
  convertAudioProcess(ConvertAudioType.ctOgg, input.path, output, kbs)