{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.duckwm;
in
{
  options.programs.duckwm = {
    enable = lib.mkEnableOption "duckwm, a graph-based X11 tiling window manager";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "duckwm.packages.\${system}.duckwm";
      description = "The duckwm package to use.";
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

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    services.displayManager.sessionPackages = [ cfg.package ];

    environment.etc."duckwm/config.lua".source = "${cfg.package}/etc/duckwm/config.lua";

    systemd.user.tmpfiles.rules = lib.mkIf cfg.installUserFiles [
      "L+ %h/.config/duckwm/meta/wm.lua   - - - - ${cfg.package}/share/duckwm/meta/wm.lua"
      "L+ %h/.config/duckwm/docs/API.md   - - - - ${cfg.package}/share/doc/duckwm/API.md"
      "L+ %h/.config/duckwm/docs/API.norg - - - - ${cfg.package}/share/doc/duckwm/API.norg"
      "C  %h/.config/duckwm/.luarc.json   - - - - ${cfg.package}/share/duckwm/luarc.json"
      "C  %h/.config/duckwm/config.lua    - - - - ${cfg.package}/etc/duckwm/config.lua"
    ];
  };
}
