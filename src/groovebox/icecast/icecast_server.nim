# Groovebox - A CLI application for live streaming pre-recorded media
# to Icecast servers and RTMP platforms like Twitch and YouTube. 
#
# (c) 2026 George Lemon | AGPLv3 License
#          Made by Humans from OpenPeeps
#          https://github.com/openpeeps/groovebox

## This module implements a simple Icecast-compatible streaming server using Libevent.
## 
## It listens for incoming source connections on a single port, accepts audio streams,
## and fans them out to multiple listeners. It supports basic source authentication,
## live-edge bursting for new listeners, and a simple JSON status endpoint.
##
## There are plans to add support for HTTP-based metadata updates (e.g. song titles) and more detailed
## status reporting in the future. The server is designed to be simple and efficient, suitable for
## streaming Ogg/Vorbis/Opus audio, but it can be extended to support other formats and features as needed.

import std/[tables, times, strutils, strformat, uri,
            base64, posix, sequtils, os, macros]

import pkg/openparser/json
import pkg/libevent/bindings/[event, http, buffer, listener, bufferevent]

type
  SessionMode = enum
    SmUnknown, SmSource, SmListener

  SourceSession* = ref object
    bev*: ptr bufferevent
    server*: pointer
    mountPath*: string
    handshakeDone*: bool
    closeAfterWrite*: bool
    mode*: SessionMode
    dead*: bool

  SourceAuth* = object
    username*: string
    password*: string

  MountpointConfig* = object
    path*: string
    contentType*: string
    sourceAuth*: SourceAuth
    maxListeners*: int

  IcecastServerConfig* = object
    address*: string
    port*: uint16
    mountpoints*: seq[MountpointConfig]

  Listener* = ref object
    id*: int
    bev*: ptr bufferevent   # was: req*: ptr evhttp_request
    connectedAt*: times.Time
    bytesSent*: uint64
    wantsMetadata*: bool
    bytesSinceMeta*: int

  Mountpoint* = ref object
    path*: string
      ## normalized mount path, always starting with a slash, e.g. "/stream"
    contentType*: string
      ## MIME type to send in the Content-Type header for this mount, e.g. "audio/ogg"
    sourceAuth*: SourceAuth
      ## credentials required for a source to connect to this mount.
      ## If both username and password are empty, no authentication is required.
    maxListeners*: int
      ## maximum number of concurrent listeners allowed on this mount.
      ## New connections will be rejected with 503 if the limit is reached.
    sourceActive*: bool
      ## true if a source is currently connected and streaming to this mount
    sourceReq*: ptr evhttp_request
      ## the original HTTP request from the source connection,
      ## used for sending final responses when the source disconnects
    sourceSession*: SourceSession
      ## the active source session for this mount, if any
    listeners*: Table[int, Listener]
      ## active listener sessions keyed by a unique listener ID
    bytesIn*: uint64
      ## total bytes received from the source on this mount since the server started
    bytesOut*: uint64
      ## total bytes sent to listeners on this mount since the server started
    lastMetadata*: string
      ## the most recent metadata string received from the source, e.g. current song title.
    burst*: string
      ## a rolling cache of the most recent stream data
      ## (up to BURST_BYTES) for new listeners to receive immediately on connect,
      ## before the live stream catches up.
    headerCache*: string   # first HEADER_CACHE_BYTES of stream (Ogg BOS pages)
      ## a cache of the initial bytes of the stream containing codec headers (e.g. Ogg BOS pages).
    headerFull*: bool      # true once headerCache is filled
      ## whether the headerCache is fully populated. We only start sending the burst cache to listeners

  IcecastServer* = ref object
    ## the main server object containing configuration, state, and libevent structures.
    cfg*: IcecastServerConfig
      ## server configuration provided at initialization
    base*: ptr event_base
      ## the libevent event base for managing all events and connections
    httpd*: ptr evhttp
      ## the libevent HTTP server instance, used for handling
      ## listener requests and status endpoint
    sourceListener*: ptr evconnlistener
      ## the libevent connection listener for accepting new
      ## source connections on the configured port
    mounts*: Table[string, Mountpoint]
      ## configured mountpoints keyed by their normalized path, e.g. "/stream"
    sourceSessions*: Table[uint, SourceSession]
      ## active source sessions keyed by the pointer value
      ## of their bufferevent, used for cleanup on disconnect
    startedAt*: times.Time
      ## timestamp of when the server was started,
      ## used for uptime reporting
    nextListenerId*: int
      ## a simple incrementing ID generator for assigning
      ## unique IDs to listener sessions

const
  BURST_BYTES = 16 * 1024
    # how much recent stream data to keep in memory for new listeners
    # to "burst" out immediately on connect, before the live data starts flowing in.
    # This can help prevent dropouts for listeners that connect mid-stream,
    # at the cost of higher memory usage and latency.
  HEADER_CACHE_BYTES = 8 * 1024
    # number of bytes to cache from the very start of a new source connection.
    # For Ogg/Vorbis/Opus these bytes contain codec BOS (beginning-of-stream)
    # header pages. New listeners receive these first so the decoder can
    # initialise immediately instead of waiting for the next BOS in the live edge.
  MAX_LISTENER_BACKLOG = 512 * 1024
    # if a listener's outgoing buffer exceeds this size, we assume it's stalled
    # and disconnect it to prevent memory bloat and cascading failures
  ICY_METAINT = 16 * 1024

const
  logo = staticRead(getProjectPath().parentDir / ".github" / "groovebox_logo.png")
  splashScreen = staticRead(getProjectPath() / "assets" / "splash.html").replace("{logo}", base64.encode(logo))


proc splitPathAndQuery(url: string): tuple[path: string, query: string] =
  let q = url.find('?')
  if q < 0: return (url, "")
  (url[0 ..< q], url[q + 1 .. ^1])

proc getQueryParam(query, key: string): string =
  for part in query.split('&'):
    if part.len == 0: continue
    let eq = part.find('=')
    let k = if eq < 0: part else: part[0 ..< eq]
    if decodeUrl(k) == key:
      let v = if eq < 0: "" else: part[eq + 1 .. ^1]
      return decodeUrl(v)
  ""

proc buildIcyMetadataBlock(title: string): string =
  # builds an ICY metadata block for the given title string
  if title.len == 0: return "\x00" # no metadata
  
  let maxLen = 255 * 16
  let safeTitle = title.replace("\\", "\\\\").replace("'", "\\'")
  var payload = "StreamTitle='" & safeTitle & "';StreamUrl='';"

  if payload.len > maxLen:
    payload = payload[0 ..< maxLen]

  let blocks = (payload.len + 15) div 16
  result = newString(1)
  result[0] = char(blocks)
  result.add(payload)
  
  let pad = blocks * 16 - payload.len
  if pad > 0: result.add(repeat('\0', pad))

proc writeAudioToListener(mount: Mountpoint, l: Listener, data: string): bool =
  if l == nil or l.bev == nil:
    return false
  if data.len == 0:
    return true

  if not l.wantsMetadata:
    if bufferevent_write(l.bev, cast[pointer](data.cstring), csize_t(data.len)) != 0:
      return false
    l.bytesSent += uint64(data.len)
    mount.bytesOut += uint64(data.len)
    return true

  var off = 0
  while off < data.len:
    let remain = data.len - off
    let toMeta = ICY_METAINT - l.bytesSinceMeta
    let take = min(remain, toMeta)

    if take > 0:
      let part = data[off ..< off + take]
      if bufferevent_write(l.bev, cast[pointer](part.cstring), csize_t(part.len)) != 0:
        return false
      off += take
      l.bytesSinceMeta += take
      l.bytesSent += uint64(take)
      mount.bytesOut += uint64(take)

    if l.bytesSinceMeta == ICY_METAINT:
      let meta = buildIcyMetadataBlock(mount.lastMetadata)
      if bufferevent_write(l.bev, cast[pointer](meta.cstring), csize_t(meta.len)) != 0:
        return false
      l.bytesSinceMeta = 0

  true

proc sendReply(req: ptr evhttp_request, code: cint, reason, contentType, body: string) =
  let headers = evhttp_request_get_output_headers(req)
  discard evhttp_add_header(headers, "Content-Type", contentType)
  discard evhttp_add_header(headers, "Cache-Control", "no-cache, no-store")
  let outbuf = evhttp_request_get_output_buffer(req)
  if body.len > 0:
    discard evbuffer_add(outbuf, cast[pointer](body.cstring), csize_t(body.len))
  evhttp_send_reply(req, code, reason, outbuf)

proc logServer(msg: string) =
  echo "[icecast-server] ", msg

proc bevKey(bev: ptr bufferevent): uint {.inline.} =
  cast[uint](bev)

proc normalizeMountPath(path: string): string =
  if path.len == 0:
    return "/stream"
  if path[0] == '/':
    return path
  "/" & path

proc writeRawHttpResponse(
  bev: ptr bufferevent,
  statusLine: string,
  body = "",
  contentType = "text/plain",
  keepAlive = false,
  chunked = false,
  extraHeaders: openArray[(string, string)] = [],
  httpVersion = "HTTP/1.0"
) =
  var headers = ""
  if contentType.len > 0:
    headers.add("Content-Type: " & contentType & "\r\n")
  for (k, v) in extraHeaders:
    headers.add(k & ": " & v & "\r\n")

  if chunked:
    headers.add("Transfer-Encoding: chunked\r\n")
  elif body.len > 0:
    headers.add("Content-Length: " & $body.len & "\r\n")

  headers.add("Connection: " & (if keepAlive: "keep-alive" else: "close") & "\r\n")
  let payload = httpVersion & " " & statusLine & "\r\n" & headers & "\r\n" & body
  discard bufferevent_write(bev, cast[pointer](payload.cstring), csize_t(payload.len))

type
  ParsedHandshake = tuple[
    ok: bool,
    httpMethod: string,
    path: string,
    auth: string,
    contentType: string,
    transferEncoding: string,
    expect: string,
    icyMetadata: string
  ]

proc parseSourceHandshake(headerBlock: string): ParsedHandshake =
  # parses the initial HTTP request from a source connection
  # to extract the method, path, and relevant headers.
  let lines = headerBlock.split("\r\n")
  if lines.len == 0: return (false, "", "", "", "", "", "", "")
  let reqLine = lines[0].strip()
  let parts = reqLine.splitWhitespace()
  if parts.len < 2: return (false, "", "", "", "", "", "", "")

  var auth = ""
  var contentType = ""
  var transferEncoding = ""
  var expect = ""
  var icyMetadata = ""

  for i in 1 ..< lines.len:
    let line = lines[i]
    let sep = line.find(':')
    if sep <= 0: continue
    let key = line[0 ..< sep].strip().toLowerAscii()
    let value = line[sep + 1 .. ^1].strip()
    case key
    of "authorization": auth = value
    of "content-type": contentType = value
    of "transfer-encoding": transferEncoding = value
    of "expect": expect = value
    of "icy-metadata": icyMetadata = value
    else: discard
  (true, parts[0].toUpperAscii(), parts[1], auth,
        contentType, transferEncoding, expect, icyMetadata)

proc isSourceAuthorized(mount: Mountpoint, authHeader: string): bool =
  if mount.sourceAuth.username.len == 0 and mount.sourceAuth.password.len == 0:
    return true
  if not authHeader.startsWith("Basic "):
    return false
  try:
    let decoded = decode(authHeader[6 .. ^1].strip())
    decoded == mount.sourceAuth.username & ":" & mount.sourceAuth.password
  except CatchableError:
    false

proc detachSessionByBev(server: IcecastServer, bev: ptr bufferevent) =
  if server == nil or bev == nil: return
  let key = bevKey(bev)
  if server.sourceSessions.hasKey(key):
    let s = server.sourceSessions[key]
    s.dead = true
    s.bev = nil
    s.mountPath = ""
    server.sourceSessions.del(key)

proc removeListenerFromMount(server: IcecastServer, session: SourceSession) =
  if session.mountPath.len == 0: return
  if not server.mounts.hasKey(session.mountPath): return
  let mount = server.mounts[session.mountPath]
  let ids = toSeq(mount.listeners.keys)
  for id in ids:
    let l = mount.listeners[id]
    if l != nil and l.bev == session.bev:
      mount.listeners.del(id)
      logServer(fmt"listener disconnected on {session.mountPath} id={id}")
      break

proc closeSourceSession(session: SourceSession, reason: string) =
  if session == nil or session.dead: return
  session.dead = true

  let server = cast[IcecastServer](session.server)

  if server != nil and session.mountPath.len > 0 and server.mounts.hasKey(session.mountPath):
    let mount = server.mounts[session.mountPath]

    if session.mode == SmSource and mount.sourceSession == session:
      mount.sourceActive = false
      mount.sourceReq = nil
      mount.sourceSession = nil
      logServer(fmt"source disconnected on {mount.path}: {reason}")

      # drop all listeners cleanly
      let ids = toSeq(mount.listeners.keys)
      for id in ids:
        let l = mount.listeners[id]
        if l != nil and l.bev != nil:
          detachSessionByBev(server, l.bev)
          bufferevent_free(l.bev)
          l.bev = nil
        mount.listeners.del(id)

    elif session.mode == SmListener:
      removeListenerFromMount(server, session)

  if server != nil and session.bev != nil:
    detachSessionByBev(server, session.bev)

  if session.bev != nil:
    bufferevent_free(session.bev)
    session.bev = nil

proc buildStatusJson(server: IcecastServer): string =
  let uptimeSec =
    if server.startedAt == default(times.Time):
      0
    else:
      int((now().toTime - server.startedAt).inSeconds)

  var mountItems = newJArray()
  for path, mount in server.mounts.pairs:
    mountItems.add(%*{
      "path": path,
      "listeners": mount.listeners.len,
      "sourceActive": mount.sourceActive,
      "bytesIn": mount.bytesIn,
      "bytesOut": mount.bytesOut
    })

  result = (%*{
    "uptimeSeconds": newJInt(uptimeSec),
    "mounts": mountItems
  }).toJson()

proc onConnWrite(bev: ptr bufferevent, ctx: pointer) {.cdecl.} =
  let session = cast[SourceSession](ctx)
  if session == nil or session.dead or not session.closeAfterWrite: return
  let outbuf = bufferevent_get_output(bev)
  if outbuf == nil or evbuffer_get_length(outbuf) == 0:
    closeSourceSession(session, "response sent")

proc onSourceRead(bev: ptr bufferevent, ctx: pointer) {.cdecl.} =
  let session = cast[SourceSession](ctx)
  if session == nil: return
  let server = cast[IcecastServer](session.server)
  if server == nil:
    closeSourceSession(session, "invalid server context")
    return

  let inbuf = bufferevent_get_input(bev)
  if inbuf == nil: return

  if not session.handshakeDone:
    let available = int(evbuffer_get_length(inbuf))
    if available == 0: return

    let peekLen = min(available, 32768)
    var head = newString(peekLen)
    discard evbuffer_copyout(inbuf, cast[pointer](head.cstring), csize_t(peekLen))
    let headerEnd = head.find("\r\n\r\n")
    if headerEnd < 0:
      if available >= 32768:
        writeRawHttpResponse(bev, "413 Payload Too Large", "request headers too large")
        session.closeAfterWrite = true
      return

    discard evbuffer_drain(inbuf, csize_t(headerEnd + 4))
    let parsed = parseSourceHandshake(head[0 ..< headerEnd])
    if not parsed.ok:
      writeRawHttpResponse(bev, "400 Bad Request", "invalid request line")
      session.closeAfterWrite = true
      return

    let httpMethod = parsed.httpMethod
    let (reqPath, reqQuery) = splitPathAndQuery(parsed.path)
    let path = normalizeMountPath(reqPath)

    if httpMethod == "GET" and path == "/":
      writeRawHttpResponse(bev, "200 OK", splashScreen, "text/html")
      session.closeAfterWrite = true
      return

    # support both /status and /stream/status
    if httpMethod == "GET" and (path == "/status" or path.endsWith("/status")):
      writeRawHttpResponse(bev, "200 OK", buildStatusJson(server), "application/json")
      session.closeAfterWrite = true
      return
    
    # simple HTTP endpoint for sources to update the
    # current metadata (e.g. song title) for their mount.
    # if (httpMethod == "GET" or httpMethod == "POST") and path == "/admin/metadata":
    #   let mountArg = normalizeMountPath(getQueryParam(reqQuery, "mount"))
    #   let song = getQueryParam(reqQuery, "song")
    #   if mountArg.len == 0 or song.len == 0:
    #     writeRawHttpResponse(bev, "400 Bad Request", "expected mount and song query params")
    #     session.closeAfterWrite = true
    #     return
    #   if not server.mounts.hasKey(mountArg):
    #     writeRawHttpResponse(bev, "404 Not Found", "mountpoint not found")
    #     session.closeAfterWrite = true
    #     return
    #   server.mounts[mountArg].lastMetadata = song
    #   writeRawHttpResponse(bev, "200 OK", "OK")
    #   session.closeAfterWrite = true
    #   return

    if httpMethod == "GET":
      if not server.mounts.hasKey(path):
        writeRawHttpResponse(bev, "404 Not Found", "mountpoint not found")
        session.closeAfterWrite = true
        return
      
      let mount = server.mounts[path]
      let wantsMeta = parsed.icyMetadata.strip() == "1"
      
      if not mount.sourceActive:
        writeRawHttpResponse(bev, "503 Service Unavailable", "source is not connected")
        session.closeAfterWrite = true
        return

      session.mode = SmListener
      session.mountPath = path
      session.handshakeDone = true
      # session.mode = SmSource

      let id = server.nextListenerId
      inc server.nextListenerId

      mount.listeners[id] = Listener(
        id: id,
        bev: bev,
        connectedAt: now().toTime,
        bytesSent: 0,
        wantsMetadata: wantsMeta,
        bytesSinceMeta: 0
      )

      var headers = @[
        ("Cache-Control", "no-cache, no-store"),
        ("Pragma", "no-cache"),
        ("icy-name", "groovebox"),
        ("icy-genre", "various"),
        ("icy-url", "https://example.com"),
        ("icy-pub", "1")
      ]
      if wantsMeta:
        headers.add(("icy-metaint", $ICY_METAINT))

      writeRawHttpResponse(
        bev,
        "200 OK",
        "",
        mount.contentType,
        keepAlive = true,
        chunked = false,
        extraHeaders = headers
      )

      var bootstrapFailed = false
      if mount.headerCache.len > 0:
        if not writeAudioToListener(mount, mount.listeners[id], mount.headerCache):
          bootstrapFailed = true
      if not bootstrapFailed and mount.burst.len > 0:
        if not writeAudioToListener(mount, mount.listeners[id], mount.burst):
          bootstrapFailed = true

      if bootstrapFailed:
        mount.listeners.del(id)
        closeSourceSession(session, "listener bootstrap write failed")
        return

      discard bufferevent_flush(bev, EV_WRITE, BEV_FLUSH)
      logServer(fmt"listener connected on {path} id={id}")
      return

    if httpMethod notin ["PUT", "POST", "SOURCE"]:
      writeRawHttpResponse(bev, "405 Method Not Allowed", "use GET, PUT, POST or SOURCE")
      session.closeAfterWrite = true
      return

    if parsed.contentType.len == 0:
      writeRawHttpResponse(bev, "403 No Content-type given", "No Content-type given")
      session.closeAfterWrite = true
      return

    if parsed.transferEncoding.toLowerAscii().contains("chunked"):
      writeRawHttpResponse(bev, "501 Not Implemented", "chunked transfer encoding not supported")
      session.closeAfterWrite = true
      return

    if not server.mounts.hasKey(path):
      writeRawHttpResponse(bev, "404 Not Found", "mountpoint not found")
      session.closeAfterWrite = true
      return

    let mount = server.mounts[path]
    if mount.sourceActive:
      writeRawHttpResponse(bev, "403 Mountpoint in use", "Mountpoint in use")
      session.closeAfterWrite = true
      return

    if not isSourceAuthorized(mount, parsed.auth):
      writeRawHttpResponse(bev, "401 You need to authenticate", "You need to authenticate")
      session.closeAfterWrite = true
      return

    if httpMethod == "PUT" and parsed.expect.toLowerAscii() == "100-continue":
      writeRawHttpResponse(
        bev,
        "100 Continue",
        "",
        contentType = "",
        keepAlive = true,
        httpVersion = "HTTP/1.1"
      )

    mount.sourceActive = true
    mount.sourceReq = nil
    mount.sourceSession = session
    mount.contentType = parsed.contentType
    mount.burst.setLen(0)        # reset live-edge tail for new source
    mount.headerCache.setLen(0)  # reset codec header cache for new source
    mount.headerFull = false
    session.mountPath = path
    session.handshakeDone = true
    session.mode = SmSource

    writeRawHttpResponse(
      bev,
      "200 OK",
      "",
      contentType = "",
      keepAlive = true,
      extraHeaders = [
        ("Allow", "GET, SOURCE, PUT, POST"),
        ("Cache-Control", "no-cache"),
        ("Pragma", "no-cache")
      ]
    )
    logServer(fmt"source connected on {path} httpMethod={httpMethod}")

  if session.handshakeDone and session.mode == SmSource and session.mountPath.len > 0 and server.mounts.hasKey(session.mountPath):
    let mount = server.mounts[session.mountPath]
    let n = int(evbuffer_get_length(inbuf))
    if n > 0:
      mount.bytesIn += uint64(n)
      var chunk = newString(n)
      discard evbuffer_copyout(inbuf, cast[pointer](chunk.cstring), csize_t(n))
      discard evbuffer_drain(inbuf, csize_t(n))

      # fill codec header cache from the very first bytes of each source session
      if not mount.headerFull:
        mount.headerCache.add(chunk)
        if mount.headerCache.len >= HEADER_CACHE_BYTES:
          mount.headerCache = mount.headerCache[0 ..< HEADER_CACHE_BYTES]
          mount.headerFull = true

      # rolling live-edge burst (only after header cache is complete)
      if mount.headerFull and chunk.len > 0:
        mount.burst.add(chunk)
        if mount.burst.len > BURST_BYTES:
          let trim = mount.burst.len - BURST_BYTES
          mount.burst = mount.burst[trim .. ^1]

      # fanout with backlog pruning
      if mount.listeners.len > 0:
        let ids = toSeq(mount.listeners.keys)
        for id in ids:
          if not mount.listeners.hasKey(id): continue
          let l = mount.listeners[id]
          if l == nil or l.bev == nil:
            mount.listeners.del(id)
            continue

          let outq = bufferevent_get_output(l.bev)
          if outq != nil and evbuffer_get_length(outq) > csize_t(MAX_LISTENER_BACKLOG):
            let key = bevKey(l.bev)
            if server.sourceSessions.hasKey(key):
              server.sourceSessions[key].dead = true
            bufferevent_free(l.bev)
            l.bev = nil
            mount.listeners.del(id)
            logServer(fmt"listener pruned (stalled) on {mount.path} id={id}")
            continue

          if not writeAudioToListener(mount, l, chunk):
            let key = bevKey(l.bev)
            if server.sourceSessions.hasKey(key):
              server.sourceSessions[key].dead = true
            bufferevent_free(l.bev)
            l.bev = nil
            mount.listeners.del(id)

proc onSourceEvent(bev: ptr bufferevent, what: cshort, ctx: pointer) {.cdecl.} =
  let session = cast[SourceSession](ctx)
  if session == nil or session.dead: return   # guard double-free

  if (what and BEV_EVENT_EOF) != 0:
    closeSourceSession(session, "eof")
  elif (what and BEV_EVENT_ERROR) != 0:
    closeSourceSession(session, "io error")
  elif (what and BEV_EVENT_TIMEOUT) != 0:
    closeSourceSession(session, "timeout")

proc onSourceAccept(listener: ptr evconnlistener, fd: evutil_socket_t, sa: ptr SockAddr, socklen: cint, arg: pointer) {.cdecl.} =
  let server = cast[IcecastServer](arg)
  if server == nil or server.base == nil:
    discard close(fd)
    return

  let bev = bufferevent_socket_new(server.base, fd, BEV_OPT_CLOSE_ON_FREE or BEV_OPT_DEFER_CALLBACKS)
  if bev == nil:
    discard close(fd)
    return

  let session = SourceSession(
    bev: bev,
    server: cast[pointer](server),
    mountPath: "",
    handshakeDone: false,
    closeAfterWrite: false,
    mode: SmUnknown
  )
  server.sourceSessions[bevKey(bev)] = session

  bufferevent_setcb(bev, onSourceRead, onConnWrite, onSourceEvent, cast[pointer](session))
  discard bufferevent_enable(bev, EV_READ or EV_WRITE)

proc onSourceAcceptError(listener: ptr evconnlistener, arg: pointer) {.cdecl.} =
  let server = cast[IcecastServer](arg)
  if server == nil:
    return
  logServer("source accept listener reported an error")

proc sendReply(req: ptr evhttp_request, code: cint, reason, contentType: string, body: JsonNode) {.inline.} =
  sendReply(req, code, reason, contentType, body.toJson())

proc sendStatus(server: IcecastServer, req: ptr evhttp_request) =
  let uptimeSec =
    if server.startedAt == default(times.Time):
      0
    else:
      int((now().toTime - server.startedAt).inSeconds)

  var mountItems = newJArray()
  for path, mount in server.mounts.pairs:
    mountItems.add(
      %*{
        "path": path,
        "listeners": mount.listeners.len,
        "sourceActive": mount.sourceActive,
        "bytesIn": mount.bytesIn,
        "bytesOut": mount.bytesOut
      }
    )
  let payload = %*{
    "uptimeSeconds": newJInt(uptimeSec),
    "mounts": mountItems
  }.toJson()
  
  sendReply(req, HTTP_OK, "OK", "application/json", payload)

proc toMountpoint(config: MountpointConfig): Mountpoint =
  Mountpoint(
    path: normalizeMountPath(config.path),
    contentType: (if config.contentType.len > 0: config.contentType else: "audio/ogg"),
    sourceAuth: config.sourceAuth,
    maxListeners: (if config.maxListeners > 0: config.maxListeners else: 1000),
    sourceActive: false,
    sourceReq: nil,
    sourceSession: nil,
    listeners: initTable[int, Listener](),
    bytesIn: 0,
    bytesOut: 0,
    lastMetadata: "",
    burst: "",
    headerCache: "",
    headerFull: false
  )

proc onSourceRequestComplete(req: ptr evhttp_request, arg: pointer) {.cdecl.} =
  let mount = cast[Mountpoint](arg)
  if mount == nil:
    return
  mount.sourceActive = false
  mount.sourceReq = nil
  mount.sourceSession = nil
  logServer(fmt"source disconnected on {mount.path}")

proc newIcecastServer*(cfg: IcecastServerConfig): IcecastServer =
  result = IcecastServer(
    cfg: cfg,
    base: nil,
    httpd: nil,
    sourceListener: nil,
    mounts: initTable[string, Mountpoint](),
    sourceSessions: initTable[uint, SourceSession](),
    startedAt: default(times.Time),
    nextListenerId: 1
  )

  for config in cfg.mountpoints:
    let mount = toMountpoint(config)
    result.mounts[mount.path] = mount

proc addMountpoint*(server: IcecastServer, config: MountpointConfig) =
  ## Adds a new mountpoint to the server at runtime. This can be used to
  ## dynamically create new streaming endpoints without restarting the server.
  ## 
  ## The new mountpoint will be available immediately for sources and listeners.
  let mount = toMountpoint(config)
  server.mounts[mount.path] = mount

proc handleListenerRequest(server: IcecastServer, mount: Mountpoint, req: ptr evhttp_request) =
  # This is a placeholder for handling incoming listener requests. It checks if the mount
  # has an active source and if the listener limit has been reached.
  if mount.listeners.len >= mount.maxListeners:
    logServer(fmt"listener rejected at {mount.path}: max listeners reached")
    sendReply(req, HTTP_SERVUNAVAIL, "Too Many Listeners", "text/plain", "listener limit reached")
    return

  if not mount.sourceActive:
    logServer(fmt"listener rejected at {mount.path}: no source connected")
    sendReply(req, HTTP_SERVUNAVAIL, "No Source", "text/plain", "source is not connected")
    return

  sendReply(req, HTTP_NOTIMPLEMENTED, "Not Implemented", "text/plain", "listener streaming fanout will be enabled in next step")

proc start*(server: IcecastServer): bool =
  ## Starts the server by initializing the event base, setting up the source listener,
  ## and preparing to accept incoming connections. Returns true on success, false on failure.
  if server.base != nil:
    return false

  server.base = event_base_new()
  if server.base == nil:
    return false

  var sin: Sockaddr_in
  zeroMem(addr sin, sizeof(sin))
  sin.sin_family = AF_INET.TSa_Family
  sin.sin_port = htons(server.cfg.port)
  if server.cfg.address == "0.0.0.0":
    sin.sin_addr.s_addr = htonl(INADDR_ANY)
  else:
    sin.sin_addr.s_addr = inet_addr(server.cfg.address)

  let flags = LEV_OPT_REUSEABLE or LEV_OPT_CLOSE_ON_FREE
  server.sourceListener = evconnlistener_new_bind(
    server.base,
    onSourceAccept,
    cast[pointer](server),
    flags.cuint,
    -1,
    cast[ptr SockAddr](addr sin),
    sizeof(sin).cint
  )
  if server.sourceListener == nil:
    event_base_free(server.base)
    server.base = nil
    return false

  evconnlistener_set_error_cb(server.sourceListener, onSourceAcceptError)
  server.startedAt = now().toTime
  logServer(fmt"listening on {server.cfg.address}:{server.cfg.port} (single port)")
  result = true

proc run*(server: IcecastServer): bool =
  ## Starts the server event loop. This will block until
  ## the server is stopped or encounters a fatal error.
  if not server.start():
    return false
  discard event_base_dispatch(server.base)
  result = true

proc stop*(server: IcecastServer) =
  if server.sourceListener != nil:
    evconnlistener_free(server.sourceListener)
    server.sourceListener = nil

  if server.sourceSessions.len > 0:
    let sessions = toSeq(server.sourceSessions.values)
    for session in sessions:
      closeSourceSession(session, "server stop")

  if server.httpd != nil:
    evhttp_free(server.httpd)
    server.httpd = nil

  if server.base != nil:
    event_base_free(server.base)
    server.base = nil

proc defaultIcecastServerConfig*(): IcecastServerConfig =
  IcecastServerConfig(
    address: "127.0.0.1",
    port: 8000'u16,
    mountpoints: @[
      MountpointConfig(
        path: "/stream",
        contentType: "audio/ogg",
        sourceAuth: SourceAuth(username: "source", password: "hackme"),
        maxListeners: 1000
      )
    ]
  )

when isMainModule:
  let server = newIcecastServer(defaultIcecastServerConfig())
  if not server.run():
    echo "Failed to start Icecast server"
  else:
    echo "Icecast server stopped"