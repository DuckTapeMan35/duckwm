{
  lib,
  stdenv,
  runCommand,
  # duckwm is written for Zig 0.16; nixpkgs' plain `zig` has moved on to 0.17.
  zig,
  pkg-config,
  # x11
  libx11,
  libxft,
  libxcursor,
  libxrandr,
  # river
  river,
  wayland,
  wayland-scanner,
  wayland-protocols,
  libxkbcommon,
  fcft,
  pixman,
  platform ? "x11",
}:

assert lib.assertOneOf "platform" platform [
  "x11"
  "river"
];

let
  src = ../.;
  isRiver = platform == "river";

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
    outputHash = "sha256-A7IhyX3yEJ7wTGU0QX5T1RAXNePStU5ngExYV3e3G2E=";
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
  pname = if isRiver then "duckwm-river" else "duckwm";
  version = "0.1.0";
  inherit src;

  nativeBuildInputs = [
    zig
    pkg-config
  ]
  ++ lib.optionals isRiver [ wayland-scanner ];

  buildInputs = [
    stdenv.cc.libc.dev
  ]
  ++ (
    if isRiver then
      [
        wayland
        wayland-protocols
        libxkbcommon
        fcft
        pixman
      ]
    else
      [
        libx11
        libxft
        libxcursor
        libxrandr
      ]
  );

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
    zig build install install-config --prefix $out -Dsysconfdir=etc \
      --system ${deps} -Doptimize=ReleaseFast -Dplatform=${platform}
    runHook postInstall
  '';

  postInstall = ''
    # The stubs live in the system profile on NixOS, not /usr/share.
    cat > $out/share/duckwm/luarc.json <<'EOF'
    {
      "runtime.version": "Lua 5.4",
      "workspace.library": ["/run/current-system/sw/share/duckwm/meta"]
    }
    EOF
  ''
  + (
    if isRiver then
      ''
        mv $out/bin/duckwm $out/bin/duckwm-river
        rm -rf $out/share/xsessions
        install -Dm644 dist/duckwm-river.desktop $out/share/wayland-sessions/duckwm-river.desktop
        substituteInPlace $out/share/wayland-sessions/duckwm-river.desktop \
          --replace-fail "Exec=river -c duckwm" "Exec=${lib.getExe river} -c $out/bin/duckwm-river"
      ''
    else
      ''
        substituteInPlace $out/share/xsessions/duckwm.desktop \
          --replace-fail "Exec=duckwm" "Exec=$out/bin/duckwm"
      ''
  );

  passthru.providedSessions = [ (if isRiver then "duckwm-river" else "duckwm") ];

  meta = {
    description =
      "Graph-based tiling window manager with a Lua configuration API ("
      + (if isRiver then "river/Wayland" else "X11")
      + ")";
    homepage = "https://github.com/DuckTapeMan35/duckwm";
    license = lib.licenses.gpl3Plus;
    mainProgram = if isRiver then "duckwm-river" else "duckwm";
    platforms = lib.platforms.linux;
  };
}
