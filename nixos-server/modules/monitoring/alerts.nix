{ config, lib, pkgs, ... }:

{
  sops.secrets."alertmanager/smtp-password" = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = "alertmanager";
    mode = "0400";
  };

  services.prometheus.alertmanager = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9093;
    configuration = {
      route = {
        receiver = "email";
        group_wait = "30s";
        group_interval = "5m";
        repeat_interval = "12h";
      };
      receivers = [
        {
          name = "email";
          email_configs = [
            {
              to = "YOUR_ALERT_EMAIL";
              from = "YOUR_ALERT_EMAIL";
              smarthost = "YOUR_SMTP_HOST:587"; # e.g. "smtp.fastmail.com:587"
              auth_username = "YOUR_ALERT_EMAIL";
              auth_password_file = config.sops.secrets."alertmanager/smtp-password".path;
              require_tls = true;
            }
          ];
        }
      ];
    };
  };

  services.prometheus.rules = [
    (builtins.toJSON {
      groups = [
        {
          name = "server-health";
          rules = [
            {
              alert = "ServerDown";
              expr = "up{job=\"node\"} == 0";
              for = "5m";
              labels.severity = "critical";
              annotations.summary = "The node exporter is unreachable — server may be down.";
            }
            {
              alert = "DiskSpaceLow";
              expr = "(node_filesystem_avail_bytes{mountpoint=~\"/|/data\"} / node_filesystem_size_bytes{mountpoint=~\"/|/data\"}) < 0.10";
              for = "30m";
              labels.severity = "warning";
              annotations.summary = "Less than 10% free space on {{ $labels.mountpoint }}.";
            }
            {
              alert = "DiskSpaceCritical";
              expr = "(node_filesystem_avail_bytes{mountpoint=~\"/|/data\"} / node_filesystem_size_bytes{mountpoint=~\"/|/data\"}) < 0.05";
              for = "10m";
              labels.severity = "critical";
              annotations.summary = "Less than 5% free space on {{ $labels.mountpoint }}.";
            }
            {
              alert = "HighMemoryPressure";
              expr = "node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.10";
              for = "15m";
              labels.severity = "warning";
              annotations.summary = "Less than 10% memory available.";
            }
            {
              alert = "HighCPULoad";
              expr = "node_load5 / count(node_cpu_seconds_total{mode=\"idle\"}) without (cpu, mode) > 1.5";
              for = "15m";
              labels.severity = "warning";
              annotations.summary = "5-minute load average is well above CPU core count.";
            }
            {
              alert = "SmartFailure";
              expr = "smartctl_device_smart_status == 0";
              for = "5m";
              labels.severity = "critical";
              annotations.summary = "SMART reports {{ $labels.device }} is failing — replace it.";
            }
            {
              alert = "SystemdUnitFailed";
              expr = "node_systemd_unit_state{state=\"failed\"} == 1";
              for = "10m";
              labels.severity = "warning";
              annotations.summary = "systemd unit {{ $labels.name }} is in a failed state.";
            }
            {
              alert = "BackupStale";
              expr = "(time() - backup_last_success_timestamp_seconds) > (8 * 86400)";
              for = "1h";
              labels.severity = "warning";
              annotations.summary = "No successful backup in over 8 days — check whether the USB drive needs rotating.";
            }
            {
              alert = "BackupFailed";
              expr = "backup_last_run_success == 0";
              for = "1h";
              labels.severity = "critical";
              annotations.summary = "The last backup run exited with a failure — check `journalctl -u restic-backup.service`.";
            }
          ];
        }
      ];
    })
  ];

  systemd.services.alertmanager.serviceConfig.Restart = lib.mkDefault "on-failure";
}
