{
  description = "duckwm — a graph-based tiling window manager";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  # Zig 0.17 isn't in 26.05; only zig and zls come from here.
  inputs.nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      unstable = nixpkgs-unstable.legacyPackages.${system};
      zig = unstable.zig_0_17;
      zls = unstable.zls_0_17;
    in
    {
      packages.${system} = {
        duckwm = pkgs.callPackage ./nix/package.nix { inherit zig; };
        duckwm-river = pkgs.callPackage ./nix/package.nix {
          inherit zig;
          platform = "river";
        };
        default = self.packages.${system}.duckwm;
      };

      nixosModules.duckwm = {
        imports = [ ./nix/module.nix ];
        programs.duckwm.package = nixpkgs.lib.mkDefault self.packages.${system}.duckwm;
        programs.duckwm.riverPackage = nixpkgs.lib.mkDefault self.packages.${system}.duckwm-river;
      };
      nixosModules.default = self.nixosModules.duckwm;

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          zig
          zls
          pkgs.pkg-config
          pkgs.river
          pkgs.foot
          pkgs.protobuf
        ];
        buildInputs = with pkgs; [
          # x11 backend
          libx11
          libxft
          libxcursor
          libxrandr
          stdenv.cc.libc.dev

          # river backend
          wayland
          wayland-scanner
          wayland-protocols
          libxkbcommon
          fcft
          pixman
        ];
      };
    };
}
