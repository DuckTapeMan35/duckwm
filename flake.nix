{
  description = "duckwm — a graph-based X11 tiling window manager";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system} = {
        duckwm = pkgs.callPackage ./nix/package.nix { };
        default = self.packages.${system}.duckwm;
      };

      nixosModules.duckwm = import ./nix/module.nix;
      nixosModules.default = self.nixosModules.duckwm;

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          zig
          zls
          pkg-config
        ];
        buildInputs = with pkgs; [
          libx11
          libxft
          libxcursor
          stdenv.cc.libc.dev
        ];
      };
    };
}
