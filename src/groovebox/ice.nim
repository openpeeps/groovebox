# Groovebox - A CLI application for live streaming pre-recorded media
# to Icecast servers and platforms like Twitch and YouTube. 
#
# (c) 2026 George Lemon | AGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/groovebox

## This module implements the icecast streaming protocol using
## libevent for efficient non-blocking I/O. It connects to an Icecast server
## as a source client, reads media files from a playlist, and streams them
## to the server with proper pacing to maintain a target bitrate.
## 
## It also handles reconnections, buffering, and basic error handling to ensure a
## stable streaming experience.

import std/[os, strutils, sequtils, base64, options,
          times, posix, strformat, random, net]

import pkg/nyml
import pkg/kapsis/[runtime, cli]
import pkg/libevent/bindings/[http, event, buffer,
                    bufferevent, threaded, listener]
import ./config

const
  READ_BUF_SIZE = 65536 # 64 KB
  RECONNECT_DELAY_SEC = 5 # seconds before reconnecting TODO make configurable
  SEND_HIGH_WATER = 64 * 1024 # 64 KB
  SEND_LOW_WATER = 64 * 1024
  TARGET_KBPS = 128 # Target bitrate in kbps
  TARGET_BYTES_PER_SEC = (TARGET_KBPS * 1000) div 8
  TICK_INTERVAL_MS = 50 # TODO make configurable
  BYTES_PER_TICK = (TARGET_BYTES_PER_SEC * TICK_INTERVAL_MS) div 1000

type
  App = ref object
    base: ptr event_base
    bev: ptr bufferevent
    tickEv: ptr event
    currentOffset: int
    bufferFullTicks: int

    messages: seq[string]
    messageIdx: int
    ticksSinceMessage: int
    showingMessage: bool
    lastSongTitle: string

    host, port, mount, username, password: string
    playlist: seq[string]
    current: int
    currentFd: cint = -1
      # File descriptor of the currently playing file
    plistFp: string
    shuttingDown: bool

proc freeApp(a: App) =
  if a == nil: return
  if a.bev != nil: bufferevent_free(a.bev)
  if a.base != nil: event_base_free(a.base)
  if a.currentFd >= 0:
    discard close(a.currentFd)
  # Strings and seqs are GC-managed

randomize()

proc buildSourceRequest(a: App): string =
  let httpMethod = "SOURCE" # or PUT?
  let b64 = base64.encode(a.username & ":" & a.password)
  result = fmt"""{httpMethod} {a.mount} HTTP/1.0
Host: {a.host}
Authorization: Basic {b64}
Content-Type: audio/ogg
Icy-MetaData: 0
User-Agent: libevent-icecast-source/1.0
Connection: Keep-Alive

"""

proc loadPlaylist(a: App, plistPath: string; shuffle: bool = false): int =
  # Load playlist from a file. Each line is a file path.
  var lines = readFile(plistPath).splitLines()
  a.playlist = @[]
  for line in lines:
    let l = line.strip()
    if l.len > 0: a.playlist.add(l)
  if shuffle:
    a.playlist.shuffle()
  if a.playlist.len == 0:
    stderr.writeLine("Playlist empty")
    return -1
  return 0

proc openNextFile(a: App): int =
  # Open the next file in the playlist
  if a.currentFd >= 0:
    discard close(a.currentFd)
    a.currentFd = -1
  if a.playlist.len == 0:
    if loadPlaylist(a, a.plistFp) != 0 or a.playlist.len == 0:
      stderr.writeLine("Playlist empty, waiting for new tracks...")
      sleep(1)
      return -1
  var tries = 0
  while tries < a.playlist.len:
    let path = a.playlist[a.current mod a.playlist.len]
    let fd = open(path, O_RDONLY)
    if fd >= 0:
      a.currentFd = fd
      if a.currentOffset > 0:
        if lseek(fd, a.currentOffset, SEEK_SET) < 0:
          stderr.writeLine("Failed to seek")
          a.currentOffset = 0
          discard lseek(fd, 0, SEEK_SET)
      stderr.writeLine("Opened file: " & path & " (offset " & $a.currentOffset & ")")
      return 0
    else:
      stderr.writeLine("Failed to open " & path)
      a.current = (a.current + 1) mod a.playlist.len
      a.currentOffset = 0
      tries.inc
  stderr.writeLine("All files failed to open. Waiting before retry...")
  sleep(1)
  return -1

proc tickCb(fd: cint, what: cshort, ctx: pointer) {.cdecl.} =
  let a = cast[App](ctx)
  if a.bev == nil: return
  let outbuf = bufferevent_get_output(a.bev)
  block reschedule:
    if evbuffer_get_length(outbuf) > SEND_HIGH_WATER:
      if a.bufferFullTicks < 5:
        displayInfo("Output buffer full, throttling... (" & $a.bufferFullTicks & ")")
        break reschedule
      elif a.bufferFullTicks == 5:
        displayInfo("Buffer still full, skipping ahead to reduce latency")
        # Drop some data: skip ahead 1 second in the file
        let skipBytes = TARGET_BYTES_PER_SEC
        if a.currentFd >= 0:
          let newOffset = a.currentOffset + skipBytes
          if lseek(a.currentFd, newOffset, SEEK_SET) >= 0:
            a.currentOffset = newOffset
            displayInfo("Skipped ahead " & $skipBytes & " bytes to reduce latency")
          else:
            displayInfo("Failed to skip ahead, closing file")
            discard close(a.currentFd)
            a.currentFd = -1
            a.currentOffset = 0
        # Reset throttle after skip
        a.bufferFullTicks = 0
        break reschedule
      else:
        break reschedule
    else:
      a.bufferFullTicks = 0 # reset throttle when buffer drains

    if a.currentFd < 0:
      if openNextFile(a) != 0:
        break reschedule

    var toSend = BYTES_PER_TICK
    var buf: array[READ_BUF_SIZE, char]
    
    while toSend > 0:
      let r = read(a.currentFd, addr buf[0], min(toSend, READ_BUF_SIZE))
      if r > 0:
        discard bufferevent_write(a.bev, addr buf[0], r.csize_t)
        a.currentOffset += r
        toSend -= r
      elif r == 0:
        discard close(a.currentFd)
        a.currentFd = -1
        a.currentOffset = 0
        a.current = (a.current + 1) mod a.playlist.len
        break
      else:
        stderr.writeLine("Read error")
        discard close(a.currentFd)
        a.currentFd = -1
        a.currentOffset = 0
        break

  var tv = event.Timeval(tv_sec: 0, tv_usec: TICK_INTERVAL_MS * 1000)
  discard evtimer_add(a.tickEv, addr tv)

proc bevWriteCb(bev: ptr bufferevent, ctx: pointer) {.cdecl.} =
  # No-op, handled by tickCb pacing
  discard

proc bevReadCb(bev: ptr bufferevent, ctx: pointer) {.cdecl.} =
  # Read callback for bufferevent
  let a = cast[App](ctx)
  let inp = bufferevent_get_input(bev)
  let len = evbuffer_get_length(inp)
  if len == 0: return
  let toCopy = min(len, 4096)
  var tmp = newString(toCopy)
  discard evbuffer_copyout(inp, tmp.cstring, toCopy)
  tmp.add('\0')
  if "\r\n\r\n" in tmp:
    let headerLen = tmp.find("\r\n\r\n") + 4
    discard evbuffer_drain(inp, headerLen.csize_t)
    if tmp.startsWith("HTTP/1.0 200") or tmp.startsWith("HTTP/1.0 201") or
       tmp.startsWith("HTTP/1.1 200") or tmp.startsWith("HTTP/1.1 201"):
      if a.tickEv == nil:
        a.tickEv = evtimer_new(a.base, tickCb, cast[pointer](a))
      var tv = event.Timeval(tv_sec: 0, tv_usec: 50 * 1000)
      discard evtimer_add(a.tickEv, addr tv)
    else:
      displayError("Server rejected source connection " & tmp)
      if a.tickEv != nil:
        discard evtimer_del(a.tickEv)
        event_free(a.tickEv)
        a.tickEv = nil
      bufferevent_free(a.bev)
      a.bev = nil

proc bevEventCb(bev: ptr bufferevent, what: cshort, ctx: pointer) {.cdecl.} =
  # Event callback for bufferevent
  let a = cast[App](ctx)
  if (what and BEV_EVENT_CONNECTED) != 0:
    let req = buildSourceRequest(a)
    if req.len == 0:
      stderr.writeLine("Failed to build request")
      bufferevent_free(a.bev)
      a.bev = nil
      return
    discard bufferevent_write(a.bev, req.cstring, csize_t(req.len))
  elif (what and (BEV_EVENT_EOF or BEV_EVENT_ERROR or BEV_EVENT_TIMEOUT)) != 0:
    if (what and BEV_EVENT_EOF) != 0:
      displayError("Connection closed by server.")
    if (what and BEV_EVENT_ERROR) != 0:
      displayError("Connection error")
    if (what and BEV_EVENT_TIMEOUT) != 0:
      displayError("Connection timed out.")
    if a.tickEv != nil:
      discard evtimer_del(a.tickEv)
      event_free(a.tickEv); a.tickEv = nil
    if a.bev != nil: bufferevent_free(a.bev); a.bev = nil
    if not a.shuttingDown:
      var tv = event.Timeval(tv_sec: RECONNECT_DELAY_SEC, tv_usec: 0)
      discard event_base_loopexit(a.base, addr tv)

proc connectToServer(a: App): int =
  # Connect to the Icecast server
  var hints: AddrInfo
  zeroMem(addr hints, sizeof(hints))
  hints.ai_family = AF_UNSPEC
  hints.ai_socktype = SOCK_STREAM
  
  var res: ptr AddrInfo
  let gai = getaddrinfo(a.host, a.port, addr hints, res)
  
  if gai != 0:
    displayError("getaddrinfo failed")
    return -1
  
  # Create bufferevent and connect
  a.bev = bufferevent_socket_new(a.base, -1, BEV_OPT_CLOSE_ON_FREE or BEV_OPT_DEFER_CALLBACKS)
  
  if a.bev == nil:
    displayError("bufferevent_socket_new failed")
    freeaddrinfo(res)
    return -1

  bufferevent_setwatermark(a.bev, EV_WRITE, SEND_LOW_WATER, SEND_HIGH_WATER)
  bufferevent_setcb(a.bev, bevReadCb, bevWriteCb, bevEventCb, cast[pointer](a))
  assert bufferevent_enable(a.bev, EV_READ or EV_WRITE) == 0
  if bufferevent_socket_connect(a.bev, res.ai_addr, res.ai_addrlen.cint) < 0:
    displayError("bufferevent_socket_connect failed")
    bufferevent_free(a.bev)
    a.bev = nil
    freeaddrinfo(res)
    return -1
  freeaddrinfo(res)
  return 0

proc icecastCommand*(v: Values) =
  ## Stream media from a source via CLI
  display(cliHeading)
  let configPath = normalizedPath(getCurrentDir() / $(v.get("config").getPath))
  if configPath.endsWith(".yml") or configPath.endsWith(".yaml"):
    GConfig = fromYaml(readFile(configPath), GrooveboxConfig)
  elif configPath.endsWith(".json"):
    GConfig = fromJson(readFile(configPath), GrooveboxConfig)
  else:
    display("No Groovebox Config found in the current directory (.yml/.yaml/.json)")
    QuitFailure.quit

  var app = App(
    base: event_base_new(),
    host: GConfig.icecast.connection.address.get("localhost"),
    port: $GConfig.icecast.connection.port,
    mount: GConfig.icecast.connection.mountPoint.get("/stream"),
    username:
      if GConfig.icecast.connection.credentials.isSome:
        GConfig.icecast.connection.credentials.get().username
      else: "source",
    password:
      if GConfig.icecast.connection.credentials.isSome:
        GConfig.icecast.connection.credentials.get().password
      else: "hackme"
  )

  # TODO support multiple playlists
  app.plistFp =
    absolutePath(
      if GConfig.icecast.playlists.len > 0: GConfig.icecast.playlists[0]
      else: "playlist.txt"
    )

  if loadPlaylist(app, app.plistFp) != 0:
    freeApp(app)
    quit(1)

  if GConfig.icecast.settings.shuffleTracks:
    app.playlist.shuffle()

  while true:
    displaySuccess("Connecting to " & app.host & ":" & app.port & app.mount)
    
    if connectToServer(app) != 0:
      # When connection fails, wait and retry
      displayError("Failed to connect, retrying in " & $RECONNECT_DELAY_SEC & " seconds...")
      sleep(RECONNECT_DELAY_SEC)
      continue

    assert event_base_dispatch(app.base) == 0
    if app.tickEv != nil:
      assert evtimer_del(app.tickEv) == 0
      event_free(app.tickEv)
      app.tickEv = nil

    displayError("Disconnected, reconnecting in " & $RECONNECT_DELAY_SEC & " seconds...")
    sleep(RECONNECT_DELAY_SEC)

    if app.bev != nil: 
      bufferevent_free(app.bev)
      app.bev = nil

    if app.shuttingDown: break
    displayInfo("Reconnecting in " & $RECONNECT_DELAY_SEC & " seconds...")
    sleep(RECONNECT_DELAY_SEC)