when defined(macosx):
  # --passL:"/opt/local/lib/libssl.a"
  # --passL:"/opt/local/lib/libcrypto.a"
  --passL:"/opt/local/lib/libevent.a"
  --passC:"-I /opt/local/include"
  when defined(arm64) or defined(aarch64):
    --passC:"-Wno-incompatible-function-pointer-types"
elif defined(linux):
  # --passL:"/usr/lib/x86_64-linux-gnu/libssl.a"
  # --passL:"/usr/lib/x86_64-linux-gnu/libcrypto.a"
  # --passL:"/usr/local/lib/libevent.a"
  --passL:"-L/usr/local/lib/lib -L/usr/local/lib -Wl,-rpath,/usr/local/lib/lib -Wl,-rpath,/usr/local/lib -levent"
  --passC:"-I /usr/include"

when defined release:
  --passC:"-O3 -flto" # Optimize for speed
  --passL:"-flto"     # Link Time Optimization for smaller/faster binaries

switch("define", "ThreadPoolSize=2")
switch("define", "FixedChanSize=4")