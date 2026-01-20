{ self }:
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.arxiv-mcp-server;
  storageArgList = lib.optionals (cfg.storagePath != null) [
    "--storage-path"
    (toString cfg.storagePath)
  ];
  serverArgList = storageArgList ++ cfg.extraServerArgs;
  serverExe = "${cfg.package}/bin/arxiv-mcp-server";
  proxyExe = "${cfg.proxyPackage}/bin/mcp-proxy";
  wrapper = pkgs.writeShellScriptBin "arxiv-mcp-server" ''
    exec ${lib.escapeShellArg serverExe} ${lib.concatStringsSep " " (map lib.escapeShellArg serverArgList)} "$@"
  '';
  proxyArgs =
    [
      proxyExe
      "--host"
      cfg.host
      "--port"
      (toString cfg.port)
    ]
    ++ lib.optionals cfg.stateless [ "--stateless" ]
    ++ lib.optionals cfg.passEnvironment [ "--pass-environment" ]
    ++ lib.optionals (!cfg.passEnvironment) [ "--no-pass-environment" ]
    ++ lib.concatMap (origin: [ "--allow-origin" origin ]) cfg.allowOrigins
    ++ cfg.extraProxyArgs
    ++ [
      "--"
      "${wrapper}/bin/arxiv-mcp-server"
    ];
  proxyExecStart = lib.escapeShellArgs proxyArgs;
in
{
  options.programs.arxiv-mcp-server = {
    enable = lib.mkEnableOption "ArXiv MCP server with SSE proxy";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.system}.default;
      defaultText = "arxiv-mcp-server package from this flake";
      description = "Package to use for the arxiv-mcp-server executable.";
    };

    proxyPackage = lib.mkOption {
      type = lib.types.package;
      default =
        if pkgs ? mcp-proxy then
          pkgs.mcp-proxy
        else
          pkgs.python3Packages.mcp-proxy;
      defaultText = "pkgs.mcp-proxy or pkgs.python3Packages.mcp-proxy";
      description = "Package providing the mcp-proxy executable.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "arxiv-mcp-server";
      description = "System user to run the MCP proxy service.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "arxiv-mcp-server";
      description = "System group to run the MCP proxy service.";
    };

    stateDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/var/lib/arxiv-mcp-server";
      description = "Base directory for server state and storage.";
    };

    storagePath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/var/lib/arxiv-mcp-server/papers";
      description = "Storage path passed to --storage-path.";
    };

    extraServerArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--log-level" "debug" ];
      description = "Extra arguments passed to arxiv-mcp-server.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      example = "0.0.0.0";
      description = "Host address for the SSE server exposed by mcp-proxy.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port for the SSE server exposed by mcp-proxy.";
    };

    allowOrigins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "*" ];
      description = "CORS allow origins for the SSE server.";
    };

    stateless = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable stateless mode for streamable HTTP transports.";
    };

    passEnvironment = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Pass all environment variables through to the stdio server.";
    };

    extraProxyArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "--log-level" "debug" ];
      description = "Extra arguments passed to mcp-proxy.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variables set for the proxy service.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.arxiv-mcp-server.stateDir = lib.mkDefault "/var/lib/${cfg.user}";
    programs.arxiv-mcp-server.storagePath = lib.mkDefault "${cfg.stateDir}/papers";

    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.stateDir;
      createHome = true;
    };

    systemd.tmpfiles.rules = lib.optionals (cfg.storagePath != null) [
      "d ${cfg.storagePath} 0750 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.arxiv-mcp-server = {
      description = "ArXiv MCP server SSE proxy";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDir;
        ExecStart = proxyExecStart;
        Restart = "on-failure";
        RestartSec = 3;
      };
      environment = cfg.environment;
    };

    environment.systemPackages = [
      wrapper
      cfg.proxyPackage
    ];
  };
}
