{ config, lib, pkgs, ... }:

{
  imports = [ ./alerts.nix ];

  # --- Exporters -----------------------------------------------------------
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    listenAddress = "127.0.0.1";
    enabledCollectors = [
      "systemd"   # per-unit state -> catches failed services/containers
      "textfile"  # lets other scripts (e.g. backup checks) publish metrics
      "filesystem"
      "diskstats"
      "meminfo"
      "cpu"
      "loadavg"
      "netdev"
    ];
    extraFlags = [
      "--collector.textfile.directory=/var/lib/node_exporter/textfile"
    ];
  };

  services.prometheus.exporters.smartctl = {
    enable = true;
    port = 9633;
    listenAddress = "127.0.0.1";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/node_exporter/textfile 0755 node-exporter node-exporter -"
  ];

  # Traditional SMART daemon as a second, independent line of detection
  # (syslogs + wall messages on failure) alongside the Prometheus metric —
  # belt and suspenders for something as important as "a disk is dying".
  services.smartd = {
    enable = true;
    autodetect = true;
    notifications.wall.enable = true;
  };

  # --- Prometheus ------------------------------------------------------------
  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9090;
    retentionTime = "30d";

    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{ targets = [ "127.0.0.1:9100" ]; }];
      }
      {
        job_name = "smartctl";
        static_configs = [{ targets = [ "127.0.0.1:9633" ]; }];
      }
    ];

    alertmanagers = [{
      static_configs = [{ targets = [ "127.0.0.1:9093" ]; }];
    }];
  };

  # --- Grafana --------------------------------------------------------------
  services.grafana = {
    enable = true;
    settings.server = {
      http_addr = "127.0.0.1";
      http_port = 3000;
      domain = "grafana.srv.home";
      root_url = "https://grafana.srv.home/";
    };

    provision.datasources.settings.datasources = [
      {
        name = "Prometheus";
        type = "prometheus";
        url = "http://127.0.0.1:9090";
        isDefault = true;
      }
    ];
  };
  # Deliberately no dashboards provisioned here: import "Node Exporter
  # Full" (dashboard ID 1860) once through the Grafana UI after first
  # boot — one useful, well-maintained community dashboard beats several
  # half-finished Nix-embedded ones. See docs/architecture.md.

  # This box being down doesn't take the apps down: monitoring runs as
  # ordinary systemd services on the same host (there's only one host),
  # but each app service has no hard `requires=` dependency on Prometheus/
  # Grafana, so a monitoring-stack failure never cascades into an outage
  # of Nextcloud, Jellyfin, etc.
  systemd.services.prometheus.serviceConfig.Restart = lib.mkDefault "on-failure";
  systemd.services.grafana.serviceConfig.Restart = lib.mkDefault "on-failure";
}
