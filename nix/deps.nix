# duckwm's Zig dependencies (build.zig.zon), fetched once and unpacked the way
# `zig build --system` wants them. Shared by package.nix and libduckwm.nix.
{
  stdenv,
  runCommand,
  zig,
}:

let
  depsTarballs = stdenv.mkDerivation {
    name = "duckwm-deps-tarballs";
    src = ../.;
    nativeBuildInputs = [ zig ];
    dontConfigure = true;
    buildPhase = ''
      export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
      zig build -l > /dev/null
    '';
    installPhase = "cp -r $TMPDIR/zig-cache/p $out";
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-T3J0P+qrmK/yxzowAuBgMcKWZn93UYyQHvSACUDGZgM=";
  };
in
runCommand "duckwm-deps" { } ''
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
''
