{
  lib,
  stdenv,
  runCommand,
  zig,
  pkg-config,
  libx11,
  libxft,
  libxcursor,
}:

let
  src = ../.;

  depsTarballs = stdenv.mkDerivation {
    name = "duckwm-deps-tarballs";
    inherit src;
    nativeBuildInputs = [ zig ];
    dontConfigure = true;
    buildPhase = ''
      export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
      zig build --fetch=all
    '';
    installPhase = "cp -r $TMPDIR/zig-cache/p $out";
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-j6TpiEZlcuUXPHLN1K0TRhRIxdEb5qy05nOCCk8KBzo=";
  };

  deps = runCommand "duckwm-deps" { } ''
    mkdir -p $out
    for f in ${depsTarballs}/*.tar.gz; do
      name=$(basename "$f" .tar.gz)
      mkdir -p "$out/$name"
      top=$(tar -tzf "$f" | cut -d/ -f1 | sort -u | wc -l)
      if [ "$top" -eq 1 ]; then
        tar -xzf "$f" -C "$out/$name" --strip-components=1
      else
        tar -xzf "$f" -C "$out/$name"
      fi
    done
  '';
in
stdenv.mkDerivation {
  pname = "duckwm";
  version = "0.1.0";
  inherit src;

  nativeBuildInputs = [
    zig
    pkg-config
  ];
  buildInputs = [
    libx11
    libxft
    libxcursor
    stdenv.cc.libc.dev
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
    make install PREFIX=$out SYSCONFDIR=$out/etc \
      BUILD_FLAGS="--system ${deps} -Doptimize=ReleaseFast"
    runHook postInstall
  '';

  postInstall = ''
    install -Dm644 dist/luarc.json $out/share/duckwm/luarc.json
    substituteInPlace $out/share/xsessions/duckwm.desktop \
      --replace-fail "Exec=duckwm" "Exec=$out/bin/duckwm"
  '';

  passthru.providedSessions = [ "duckwm" ];

  meta = {
    description = "Graph-based X11 tiling window manager with a Lua configuration API";
    homepage = "https://github.com/DuckTapeMan35/duckwm";
    license = lib.licenses.gpl3Plus;
    mainProgram = "duckwm";
    platforms = lib.platforms.linux;
  };
}
