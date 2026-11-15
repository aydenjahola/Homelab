# Grafana provisioning

Everything Grafana shows is loaded from this directory by `jobs/monitoring/grafana.hcl`.
Provisioned dashboards and alert rules are read-only in the UI.

| Path | What |
|---|---|
| `generate.py` | Source of truth for dashboards and alert rules. |
| `dashboards/<Folder>/*.json` | Generated. Each subdirectory becomes a Grafana folder. |
| `alerting/rules.yaml` | Generated alert rules (folder "Homelab Alerts"). |
| `alerting/contact-points.yaml` | Discord contact point. Webhook from Consul key `gatus/discord/webhook/url`. |
| `alerting/policies.yaml` | Notification policy: critical repeats hourly, warning every 4h. |
| `alerting/templates.yaml` | Discord message format. |

## Changing a dashboard or rule

1. Edit `generate.py` (or prototype in the UI by saving a copy, then port the panel JSON).
2. `python3 jobs/monitoring/grafana/generate.py` from `nomad/`.
3. Commit the script and the generated files, then `nomad job run jobs/monitoring/grafana.hcl`.

The job renders these files with `[[ ]]` template delimiters, so Grafana's own `{{ }}`
(legends, alert annotations) passes through. `generate.py` refuses to write `[[` or `]]`.

Datasource uids `PBFA97CFB590B2093` (Prometheus) and `P8E80F9AEF21F6940` (Loki) are fixed
in the job because everything here references them.
