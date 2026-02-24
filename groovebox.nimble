# Package

version       = "0.1.0"
author        = "George Lemon"
description   = "Live stream pre-recorded music to Twitch, Yotube and Icecast servers"
license       = "AGPL-3.0-or-later"
srcDir        = "src"
binDir        = "bin"
bin           = @["groovebox"]


# Dependencies

requires "nim >= 2.0.0"
requires "kapsis#head"
requires "nyml"
requires "rtmp#head"
requires "malebolgia#head"