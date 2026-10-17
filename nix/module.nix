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
  # config.lua, docs, stubs and the schema are identical in both; take them from either.
  shared = if hasX11 then cfg.package else cfg.riverPackage;

  # Modifier bits, as in types.mod.
  modBits = {
    shift = 1;
    lock = 2;
    ctrl = 4;
    control = 4;
    alt = 8;
    mod2 = 16;
    mod3 = 32;
    super = 64;
    mod5 = 128;
  };

  # "super+shift+h" -> { mods = 65; key = "h"; }
  parseCombo =
    combo:
    let
      parts = lib.splitString "+" combo;
    in
    {
      key = lib.last parts;
      mods = lib.foldl' (
        acc: m:
        builtins.bitOr acc (
          modBits.${lib.toLower m} or (throw "programs.duckwm.binds: unknown modifier '${m}' in '${combo}'")
        )
      ) 0 (lib.init parts);
    };

  commands =
    cfg.commands
    ++ lib.mapAttrsToList (combo: cmds: {
      bind_commands = parseCombo combo // {
        commands = cmds;
      };
    }) cfg.binds;

  # The commands file: JSON, checked by duckwm at build time.
  commandsFile =
    pkgs.runCommand "duckwm-commands.json"
      {
        json = builtins.toJSON { commands = commands; };
        passAsFile = [ "json" ];
      }
      ''
        cp "$jsonPath" $out
        ${shared}/bin/duckwm --check $out
      '';

  flags = lib.concatStringsSep " " (
    lib.optional (commands != [ ]) "--commands ${commandsFile}" ++ lib.optional (!cfg.lua) "--no-lua"
  );

  # The package's session entry, with the flags added to its Exec line.
  session =
    pkg: dir: exec:
    let
      name = lib.head pkg.passthru.providedSessions;
    in
    pkgs.runCommand "${name}-session" { passthru.providedSessions = [ name ]; } ''
      mkdir -p $out/share/${dir}
      sed 's|^Exec=.*|Exec=${exec}|' ${pkg}/share/${dir}/${name}.desktop > $out/share/${dir}/${name}.desktop
    '';

  sessions =
    if flags == "" then
      packages
    else
      lib.optional hasX11 (session cfg.package "xsessions" "${cfg.package}/bin/duckwm ${flags}")
      ++ lib.optional hasRiver (
        session cfg.riverPackage "wayland-sessions" ''river -c "${cfg.riverPackage}/bin/duckwm ${flags}"''
      );

  # A JSON-ish attribute set per command, in protobuf's JSON form.
  commandType = lib.types.attrsOf lib.types.anything;
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

    lua = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Load the Lua config (~/.config/duckwm/config.lua, or /etc/duckwm/config.lua).
        Turn off when a socket client and `commands` configure everything.
      '';
    };

    commands = lib.mkOption {
      type = lib.types.listOf commandType;
      default = [ ];
      example = lib.literalExpression ''
        [
          { set_gaps = { inner_h = 8; inner_v = 8; outer_h = 8; outer_v = 8; }; }
          { set_workspace_switch_mode.mode = "previous"; }
          { exec_once.argv = [ "dunst" ]; }
        ]
      '';
      description = ''
        Each is a duckwm command as JSON: the command name as the key, its
        fields as an attribute set, enums by name ("previous", "left").
        Optional fields can be left out. Checked by duckwm at build time.
      '';
    };

    binds = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf commandType);
      default = { };
      example = lib.literalExpression ''
        {
          "super+Return" = [ { spawn.argv = [ "ghostty" ]; } ];
          "super+shift+h" = [ { exchange_left = { }; } { focus_left = { }; } ];
        }
      '';
      description = ''
        Keybinds: "mod+mod+key" to the commands it runs, in the same form as
        `commands`. Modifiers: shift, ctrl, alt, super, mod2, mod3, mod5. They
        survive config reloads and replace a Lua bind on the same key.
      '';
    };

    installUserFiles = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Populate ~/.config/duckwm on login. Generated files (API docs, LuaLS
        stubs) are symlinked from the store and track the installed package.
        Editable files (config.lua, .luarc.json) are copied once and left
        alone thereafter, so live config reload keeps working. Lua files are
        only installed when `lua` is on.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = packages;
        services.displayManager.sessionPackages = sessions;
      }

      (lib.mkIf cfg.lua {
        environment.etc."duckwm/config.lua".source = "${shared}/etc/duckwm/config.lua";

        systemd.user.tmpfiles.rules = lib.mkIf cfg.installUserFiles [
          "L+ %h/.config/duckwm/meta/wm.lua   - - - - ${shared}/share/duckwm/meta/wm.lua"
          "L+ %h/.config/duckwm/docs/API.md   - - - - ${shared}/share/doc/duckwm/API.md"
          "L+ %h/.config/duckwm/docs/API.norg - - - - ${shared}/share/doc/duckwm/API.norg"
          "C  %h/.config/duckwm/.luarc.json   - - - - ${shared}/share/duckwm/luarc.json"
          "C  %h/.config/duckwm/config.lua    - - - - ${shared}/etc/duckwm/config.lua"
        ];
      })

      (lib.mkIf hasRiver {
        environment.systemPackages = [ pkgs.river ];
        hardware.graphics.enable = lib.mkDefault true;
        security.polkit.enable = lib.mkDefault true;
      })
    ]
  );
}
