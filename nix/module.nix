{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.duckwm;
  hasX11 = lib.elem "x11" cfg.platforms;
  hasRiver = lib.elem "river" cfg.platforms;
  packages = lib.optional hasX11 cfg.package ++ lib.optional hasRiver cfg.riverPackage;
  # config.lua, docs and stubs are identical in both; take them from either.
  shared = if hasX11 then cfg.package else cfg.riverPackage;
in
{
  options.programs.duckwm = {
    enable = lib.mkEnableOption "duckwm, a graph-based tiling window manager";

    platforms = lib.mkOption {
      type = lib.types.nonEmptyListOf (
        lib.types.enum [
          "x11"
          "river"
        ]
      );
      default = [ "x11" ];
      example = [
        "x11"
        "river"
      ];
      description = "Backends to install. Each one adds its own session to the display manager.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "duckwm.packages.\${system}.duckwm";
      description = "The X11 duckwm package.";
    };

    riverPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { platform = "river"; };
      defaultText = lib.literalExpression "duckwm.packages.\${system}.duckwm-river";
      description = "The river duckwm package.";
    };

    installUserFiles = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Populate ~/.config/duckwm on login. Generated files (API docs, LuaLS
        stubs) are symlinked from the store and track the installed package.
        Editable files (config.lua, .luarc.json) are copied once and left
        alone thereafter, so live config reload keeps working.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = packages;
        services.displayManager.sessionPackages = packages;

        environment.etc."duckwm/config.lua".source = "${shared}/etc/duckwm/config.lua";

        systemd.user.tmpfiles.rules = lib.mkIf cfg.installUserFiles [
          "L+ %h/.config/duckwm/meta/wm.lua   - - - - ${shared}/share/duckwm/meta/wm.lua"
          "L+ %h/.config/duckwm/docs/API.md   - - - - ${shared}/share/doc/duckwm/API.md"
          "L+ %h/.config/duckwm/docs/API.norg - - - - ${shared}/share/doc/duckwm/API.norg"
          "C  %h/.config/duckwm/.luarc.json   - - - - ${shared}/share/duckwm/luarc.json"
          "C  %h/.config/duckwm/config.lua    - - - - ${shared}/etc/duckwm/config.lua"
        ];
      }

      (lib.mkIf hasRiver {
        environment.systemPackages = [ pkgs.river ];
        hardware.graphics.enable = lib.mkDefault true;
        security.polkit.enable = lib.mkDefault true;
      })
    ]
  );
}
