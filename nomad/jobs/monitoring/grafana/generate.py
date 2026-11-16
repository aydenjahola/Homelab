#!/usr/bin/env python3
"""Generate the provisioned Grafana dashboards and alert rules for the homelab.

Usage: python3 jobs/monitoring/grafana/generate.py

Writes dashboards/<Folder>/*.json and alerting/rules.yaml next to this file.
The grafana job loads both. Commit the generated files with the script.
"""
import json
import os
import re

OUT = os.path.dirname(os.path.abspath(__file__))
PROM = {"type": "prometheus", "uid": "PBFA97CFB590B2093"}
LOKI = {"type": "loki", "uid": "P8E80F9AEF21F6940"}

GREEN, YELLOW, ORANGE, RED, BLUE, PURPLE = "green", "#EAB839", "orange", "red", "blue", "purple"


def thr(*steps):
    return {"mode": "absolute", "steps": [{"value": v, "color": c} for v, c in steps]}


PCT_THR = thr((None, GREEN), (70, YELLOW), (85, ORANGE), (95, RED))
TEMP_THR = thr((None, GREEN), (70, YELLOW), (85, RED))


class Dash:
    def __init__(self, uid, title, tags, desc="", refresh="30s", time_from="now-6h", variables=None):
        self.uid, self.title, self.tags, self.desc = uid, title, tags, desc
        self.refresh, self.time_from = refresh, time_from
        self.variables = variables or []
        self.panels, self.next_id, self.y, self.cx, self.rowh = [], 1, 0, 0, 0

    def add(self, p, w, h, newrow=False):
        if newrow or self.cx + w > 24:
            self.y += self.rowh
            self.cx, self.rowh = 0, 0
        p["id"] = self.next_id
        self.next_id += 1
        p["gridPos"] = {"x": self.cx, "y": self.y, "w": w, "h": h}
        self.cx += w
        self.rowh = max(self.rowh, h)
        self.panels.append(p)
        return p

    def row(self, title, repeat=None):
        self.y += self.rowh
        self.cx, self.rowh = 0, 0
        p = {"type": "row", "title": title, "collapsed": False, "panels": [], "id": self.next_id,
             "gridPos": {"x": 0, "y": self.y, "w": 24, "h": 1}}
        if repeat:
            p["repeat"] = repeat
        self.next_id += 1
        self.panels.append(p)
        self.y += 1

    def json(self):
        return {
            "uid": self.uid, "title": self.title, "description": self.desc, "tags": self.tags,
            "editable": False, "graphTooltip": 1, "timezone": "browser", "refresh": self.refresh,
            "schemaVersion": 41, "time": {"from": self.time_from, "to": "now"},
            "templating": {"list": self.variables},
            "annotations": {"list": [{
                "builtIn": 1, "datasource": {"type": "grafana", "uid": "-- Grafana --"},
                "enable": True, "hide": True, "iconColor": "rgba(0, 211, 255, 1)",
                "name": "Annotations & Alerts", "type": "dashboard"}]},
            "links": [{"title": "Dashboards", "type": "dashboards", "tags": ["homelab"],
                       "asDropdown": True, "includeVars": False, "keepTime": True}],
            "panels": self.panels,
        }


def prom(expr, legend="", ref="A", instant=False, fmt="time_series"):
    return {"datasource": PROM, "expr": expr, "legendFormat": legend or "__auto", "refId": ref,
            "range": not instant, "instant": instant, "format": fmt, "editorMode": "code"}


def loki(expr, legend="", ref="A"):
    return {"datasource": LOKI, "expr": expr, "legendFormat": legend, "refId": ref,
            "queryType": "range", "editorMode": "code"}


def defaults(unit=None, mn=None, mx=None, thresholds=None, decimals=None, color=None, mappings=None, custom=None):
    d = {"color": color or {"mode": "palette-classic"}, "custom": custom or {},
         "thresholds": thresholds or thr((None, GREEN))}
    for k, v in (("unit", unit), ("min", mn), ("max", mx), ("decimals", decimals), ("mappings", mappings)):
        if v is not None:
            d[k] = v
    return d


def timeseries(title, targets, unit=None, mn=None, mx=None, stack=False, desc="", fill=15,
               overrides=None, legend_calcs=("mean", "max", "lastNotNull"), thresholds=None,
               thresh_style=None, ds=PROM, draw="line", legend_mode="table", color=None,
               gradient="opacity", transparent=False, width=1):
    custom = {"drawStyle": draw, "lineWidth": width, "fillOpacity": fill, "gradientMode": gradient,
              "showPoints": "never", "spanNulls": True, "lineInterpolation": "smooth", "barAlignment": 0,
              "stacking": {"mode": "normal" if stack else "none", "group": "A"}}
    if mn is None and not stack:
        custom["axisSoftMin"] = 0
    if thresh_style:
        custom["thresholdsStyle"] = {"mode": thresh_style}
    return {
        "type": "timeseries", "title": title, "description": desc, "datasource": ds, "targets": targets,
        "transparent": transparent,
        "fieldConfig": {"defaults": defaults(unit, mn, mx, thresholds, color=color, custom=custom),
                        "overrides": overrides or []},
        "options": {"legend": {"displayMode": legend_mode, "placement": "bottom", "calcs": list(legend_calcs),
                               "showLegend": True},
                    "tooltip": {"mode": "multi", "sort": "desc"}},
    }


def stat(title, targets, unit=None, thresholds=None, desc="", color_mode="background_solid", graph=True,
         mappings=None, decimals=None, text_mode="auto", calc="lastNotNull", ds=PROM, color=None,
         orientation="auto"):
    return {
        "type": "stat", "title": title, "description": desc, "datasource": ds, "targets": targets,
        "fieldConfig": {"defaults": defaults(unit, None, None, thresholds or thr((None, GREEN)), decimals,
                                             color=color or {"mode": "thresholds"}, mappings=mappings),
                        "overrides": []},
        "options": {"colorMode": color_mode, "graphMode": "area" if graph else "none", "justifyMode": "center",
                    "textMode": text_mode, "wideLayout": True, "orientation": orientation,
                    "reduceOptions": {"calcs": [calc], "fields": "", "values": False},
                    "showPercentChange": False},
    }


def gauge(title, targets, unit="percent", thresholds=PCT_THR, mn=0, mx=100, desc=""):
    return {
        "type": "gauge", "title": title, "description": desc, "datasource": PROM, "targets": targets,
        "fieldConfig": {"defaults": defaults(unit, mn, mx, thresholds, decimals=1, color={"mode": "thresholds"}),
                        "overrides": []},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                    "showThresholdLabels": False, "showThresholdMarkers": True, "minVizHeight": 75,
                    "minVizWidth": 75, "sizing": "auto"},
    }


def bargauge(title, targets, unit="percent", thresholds=PCT_THR, mn=0, mx=None, desc="", mode="gradient",
             orientation="horizontal", color=None, decimals=None):
    return {
        "type": "bargauge", "title": title, "description": desc, "datasource": PROM, "targets": targets,
        "fieldConfig": {"defaults": defaults(unit, mn, mx, thresholds, decimals,
                                             color=color or {"mode": "thresholds"}),
                        "overrides": []},
        "options": {"displayMode": mode, "orientation": orientation, "showUnfilled": True,
                    "valueMode": "color", "namePlacement": "auto", "sizing": "auto",
                    "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                    "minVizHeight": 16, "maxVizHeight": 28},
    }


def table(title, targets, transformations=None, overrides=None, desc="", sort=None):
    return {
        "type": "table", "title": title, "description": desc, "datasource": PROM, "targets": targets,
        "transformations": transformations or [],
        "fieldConfig": {"defaults": {**defaults(color={"mode": "thresholds"}),
                                     "custom": {"align": "auto", "cellOptions": {"type": "auto"},
                                                "filterable": True}},
                        "overrides": overrides or []},
        "options": {"showHeader": True, "cellHeight": "sm", "footer": {"show": False},
                    "sortBy": sort or []},
    }


def col(name, unit=None, cell=None, thresholds=None, width=None, decimals=None, mx=None, mappings=None):
    props = []
    if unit:
        props.append({"id": "unit", "value": unit})
    if cell:
        props.append({"id": "custom.cellOptions", "value": cell})
    if thresholds:
        props += [{"id": "thresholds", "value": thresholds}, {"id": "color", "value": {"mode": "thresholds"}}]
    if width:
        props.append({"id": "custom.width", "value": width})
    if decimals is not None:
        props.append({"id": "decimals", "value": decimals})
    if mx is not None:
        props += [{"id": "max", "value": mx}, {"id": "min", "value": 0}]
    if mappings:
        props.append({"id": "mappings", "value": mappings})
    return {"matcher": {"id": "byName", "options": name}, "properties": props}


def series_color(name, color, regex=False, dashed=False, fill=None):
    props = [{"id": "color", "value": {"mode": "fixed", "fixedColor": color}}]
    if dashed:
        props.append({"id": "custom.lineStyle", "value": {"fill": "dash", "dash": [10, 10]}})
    if fill is not None:
        props.append({"id": "custom.fillOpacity", "value": fill})
    return {"matcher": {"id": "byRegexp" if regex else "byName", "options": name}, "properties": props}


STATUS_COLORS = [series_color("2..|2xx", GREEN, regex=True), series_color("3..|3xx", BLUE, regex=True),
                 series_color("4..|4xx", YELLOW, regex=True), series_color("5..|5xx", RED, regex=True)]
GAUGE_BAR = {"type": "gauge", "mode": "gradient", "valueDisplayMode": "text"}
COLOR_BG = {"type": "color-background", "mode": "basic"}
COLOR_TXT = {"type": "color-text"}
VALUE_MAP_UP = [{"type": "value", "options": {"0": {"text": "DOWN", "color": RED},
                                              "1": {"text": "UP", "color": GREEN}}}]
SCHEME = lambda s: {"mode": f"continuous-{s}"}  # noqa: E731


def logs(title, targets, desc=""):
    return {"type": "logs", "title": title, "description": desc, "datasource": LOKI, "targets": targets,
            "options": {"showTime": True, "showLabels": False, "showCommonLabels": False, "wrapLogMessage": True,
                        "prettifyLogMessage": False, "enableLogDetails": True, "dedupStrategy": "none",
                        "sortOrder": "Descending", "enableInfiniteScrolling": True}}


def alertlist(title="Alerts"):
    return {"type": "alertlist", "title": title,
            "options": {"viewMode": "list", "groupMode": "default", "groupBy": [], "maxItems": 20,
                        "sortOrder": 3, "dashboardAlerts": False, "alertName": "", "alertInstanceLabelFilter": "",
                        "stateFilter": {"firing": True, "pending": True, "noData": True, "normal": False,
                                        "error": True},
                        "showInactiveAlerts": False}}


def state_timeline(title, targets, mappings=None, desc="", thresholds=None, show_value="never"):
    return {"type": "state-timeline", "title": title, "description": desc, "datasource": PROM,
            "targets": targets,
            "fieldConfig": {"defaults": defaults(thresholds=thresholds, color={"mode": "thresholds"},
                                                 mappings=mappings, custom={"fillOpacity": 85, "lineWidth": 0}),
                            "overrides": []},
            "options": {"mergeValues": True, "showValue": show_value, "alignValue": "left", "rowHeight": 0.85,
                        "legend": {"showLegend": False}, "tooltip": {"mode": "single"}}}


def text(content):
    return {"type": "text", "title": "", "transparent": True,
            "options": {"mode": "html", "content": content}}


def var_query(name, query, label, multi=True, include_all=True, hide=0):
    return {"name": name, "label": label, "type": "query", "datasource": PROM,
            "query": {"query": query, "refId": f"{name}-var", "qryType": 1},
            "definition": query, "refresh": 2, "multi": multi, "includeAll": include_all, "allValue": ".*",
            "current": {"selected": True, "text": ["All"], "value": ["$__all"]}, "sort": 1, "hide": hide,
            "options": []}


def var_loki_label(name, label, title):
    return {"name": name, "label": title, "type": "query", "datasource": LOKI,
            "query": {"type": 1, "label": label, "stream": "", "refId": f"{name}-var"},
            "definition": "", "refresh": 2, "multi": True, "includeAll": True, "allValue": ".+",
            "current": {"selected": True, "text": ["All"], "value": ["$__all"]}, "sort": 1, "options": []}


def var_text(name, label, default=""):
    return {"name": name, "label": label, "type": "textbox", "query": default,
            "current": {"text": default, "value": default}, "options": []}


NODE_SEL = 'node=~"$node"'
NET_DEV = 'device!~"lo|veth.*|docker.*|br-.*|cni.*|nomad|virbr.*|tun.*|vnet.*"'
FS_SEL = 'fstype!~"tmpfs|ramfs|overlay|squashfs|nsfs|vfat|autofs|nfs4?"'
ERR_RE = '(?i)(error|fatal|panic|oom|failed)'
CPU_PCT = '100 * (1 - avg by (node) (rate(node_cpu_seconds_total{mode="idle"}[$__rate_interval])))'
MEM_PCT = '100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)'
ROOT_PCT = '100 * (1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})'
STORAGE_PCT = '100 * (1 - node_filesystem_avail_bytes{mountpoint="/storage"} / node_filesystem_size_bytes{mountpoint="/storage"})'
HTTP_5XX = ('100 * sum(rate(traefik_service_requests_total{code=~"5.."}[5m])) '
            '/ clamp_min(sum(rate(traefik_service_requests_total[5m])), 1e-9)')

HEADER = """
<div style="display:flex;align-items:center;justify-content:space-between;padding:6px 18px;height:100%;
  border-radius:14px;background:linear-gradient(110deg,#0f172a 0%,#1e1b4b 45%,#312e81 75%,#0e7490 100%);
  color:#e2e8f0;font-family:Inter,system-ui,sans-serif;box-shadow:0 8px 30px rgba(49,46,129,.35)">
  <div>
    <div style="font-size:26px;font-weight:700;letter-spacing:.5px">Homelab Command Center</div>
    <div style="font-size:13px;opacity:.75">odin &middot; thor &middot; loki &mdash; Nomad + Consul cluster,
      TrueNAS storage, Traefik ingress, Authentik SSO</div>
  </div>
  <div style="text-align:right;font-size:12px;opacity:.8;line-height:1.6">
    <a style="color:#a5b4fc" href="/d/homelab-nodes">Nodes</a> &middot;
    <a style="color:#a5b4fc" href="/d/homelab-nomad-cluster">Nomad</a> &middot;
    <a style="color:#a5b4fc" href="/d/homelab-nomad-workloads">Workloads</a> &middot;
    <a style="color:#a5b4fc" href="/d/homelab-traefik">Traefik</a> &middot;
    <a style="color:#a5b4fc" href="/d/homelab-authentik">Authentik</a> &middot;
    <a style="color:#a5b4fc" href="/d/homelab-logs">Logs</a> &middot;
    <a style="color:#a5b4fc" href="/a/grafana-lokiexplore-app/explore">Host logs</a> &middot;
    <a style="color:#a5b4fc" href="/d/homelab-monitoring-stack">Monitoring</a> &middot;
    <a style="color:#a5b4fc" href="/alerting/list">Alerts</a>
  </div>
</div>
"""


# ---------------------------------------------------------------- command center (master)
def command_center():
    d = Dash("homelab-command-center", "Homelab Command Center", ["homelab"],
             "Master dashboard: every signal from the homelab on one screen. Drill into the linked dashboards for detail.",
             time_from="now-6h")
    d.add(text(HEADER), 24, 3)

    # --- vitals strip
    d.row("Vitals")
    d.add(stat("Nodes up", [prom('count(up{job="node-exporters"} == 1)')],
               thresholds=thr((None, RED), (2, ORANGE), (3, GREEN)), graph=False), 3, 4)
    d.add(stat("Jobs running", [prom('max(nomad_nomad_job_status_running)')],
               thresholds=thr((None, "#3b82f6")), graph=False), 3, 4)
    d.add(stat("Allocations", [prom('count(count by (alloc_id) (nomad_client_allocs_memory_rss))')],
               thresholds=thr((None, "#6366f1")), graph=False), 3, 4)
    d.add(stat("Targets down", [prom('count(up == 0) or vector(0)')],
               thresholds=thr((None, GREEN), (1, RED)), graph=False), 3, 4)
    d.add(stat("Cluster CPU", [prom('100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[$__rate_interval])))')],
               unit="percent", thresholds=PCT_THR, decimals=1), 3, 4)
    d.add(stat("Cluster memory", [prom('100 * (1 - sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes))')],
               unit="percent", thresholds=PCT_THR, decimals=1), 3, 4)
    d.add(stat("NAS /storage", [prom(f'max({STORAGE_PCT})')], unit="percent", thresholds=PCT_THR, decimals=1), 3, 4)
    d.add(stat("Hottest sensor", [prom('max(node_hwmon_temp_celsius)')], unit="celsius", thresholds=TEMP_THR,
               decimals=0), 3, 4)

    d.add(stat("Requests/s", [prom('sum(rate(traefik_service_requests_total[$__rate_interval]))')],
               unit="reqps", thresholds=thr((None, "#0ea5e9")), decimals=2), 3, 4, newrow=True)
    d.add(stat("HTTP 5xx", [prom(f'{HTTP_5XX} or vector(0)')], unit="percent",
               thresholds=thr((None, GREEN), (1, YELLOW), (5, RED)), decimals=2), 3, 4)
    d.add(stat("Cert expiry", [prom('min(traefik_tls_certs_not_after - time())')], unit="s",
               thresholds=thr((None, RED), (7 * 86400, ORANGE), (14 * 86400, GREEN)), graph=False, decimals=0), 3, 4)
    d.add(stat("SSO outposts", [prom('sum(authentik_outposts_connected)')],
               thresholds=thr((None, RED), (1, GREEN)), graph=False,
               mappings=[{"type": "value", "options": {"0": {"text": "DISCONNECTED"}}}]), 3, 4)
    d.add(stat("OOM kills 24h", [prom('sum(increase(node_vmstat_oom_kill[24h]))')], decimals=0,
               thresholds=thr((None, GREEN), (1, ORANGE), (10, RED)), graph=False,
               desc="Kernel OOM kills across all nodes in the last 24h."), 3, 4)
    d.add(stat("Restarts 24h", [prom('sum(increase(nomad_client_allocs_restart[24h])) or vector(0)')], decimals=0,
               thresholds=thr((None, GREEN), (1, YELLOW), (10, ORANGE)), graph=False), 3, 4)
    d.add(stat("Error log lines 1h", [loki(f'sum(count_over_time({{node=~".+"}} |~ "{ERR_RE}" [1h]))')],
               ds=LOKI, decimals=0, thresholds=thr((None, GREEN), (500, YELLOW), (5000, ORANGE)), graph=False,
               calc="lastNotNull"), 3, 4)
    d.add(stat("Min uptime", [prom('min(node_time_seconds - node_boot_time_seconds)')], unit="s", decimals=0,
               thresholds=thr((None, ORANGE), (3600, "#14b8a6")), graph=False,
               desc="Most recently rebooted node."), 3, 4)

    # --- nodes
    d.row("Nodes")
    d.add(gauge("CPU", [prom(CPU_PCT, "{{node}}")]), 6, 6)
    d.add(gauge("Memory", [prom(MEM_PCT, "{{node}}")]), 6, 6)
    d.add(gauge("Root disk", [prom(ROOT_PCT, "{{node}}")]), 6, 6)
    d.add(bargauge("Temperature", [prom('max by (node) (node_hwmon_temp_celsius)', "{{node}}")], unit="celsius",
                   mx=100, thresholds=TEMP_THR, mode="lcd", decimals=0), 6, 6)

    d.add(timeseries("CPU", [prom(CPU_PCT, "{{node}}")], unit="percent", mn=0, mx=100, gradient="hue", fill=20,
                     width=2), 8, 8, newrow=True)
    d.add(timeseries("Memory", [prom(MEM_PCT, "{{node}}")], unit="percent", mn=0, mx=100, gradient="hue",
                     fill=20, width=2), 8, 8)
    d.add(timeseries("Load (5m) per core", [prom('node_load5 / on (instance) group_left count by (instance) (node_cpu_seconds_total{mode="idle"})', "{{node}}")],
                     unit="percentunit", gradient="hue", fill=20, width=2,
                     thresholds=thr((None, "transparent"), (1, RED)), thresh_style="dashed"), 8, 8)
    d.add(timeseries("Network (rx +, tx -)", [
        prom(f'sum by (node) (rate(node_network_receive_bytes_total{{{NET_DEV}}}[$__rate_interval]))', "{{node}} rx"),
        prom(f'-sum by (node) (rate(node_network_transmit_bytes_total{{{NET_DEV}}}[$__rate_interval]))', "{{node}} tx", "B")],
        unit="Bps", mn=None, fill=25), 8, 8, newrow=True)
    d.add(timeseries("Disk I/O (read +, write -)", [
        prom('sum by (node) (rate(node_disk_read_bytes_total{device!~"dm-.*|loop.*"}[$__rate_interval]))', "{{node}} read"),
        prom('-sum by (node) (rate(node_disk_written_bytes_total{device!~"dm-.*|loop.*"}[$__rate_interval]))', "{{node}} write", "B")],
        unit="Bps", mn=None, fill=25), 8, 8)
    d.add(timeseries("Pressure stall (memory / io)", [
        prom('rate(node_pressure_memory_waiting_seconds_total[$__rate_interval]) * 100', "{{node}} mem"),
        prom('rate(node_pressure_io_waiting_seconds_total[$__rate_interval]) * 100', "{{node}} io", "B")],
        unit="percent", fill=10,
        desc="Share of time tasks were stalled waiting on memory or disk. Rising memory stall precedes OOM kills."), 8, 8)

    # --- nomad
    d.row("Workloads")
    d.add(bargauge("Top memory: RSS / memory_max", [prom(
        'topk(12, max by (exported_job, task) (nomad_client_allocs_memory_rss / (nomad_client_allocs_memory_max_allocated > 0)) * 100)',
        "{{exported_job}} · {{task}}", instant=True)], mx=100, mode="lcd",
        desc="How close each task is to its hard memory limit."), 8, 11)
    d.add(bargauge("Top memory (RSS)", [prom(
        'topk(12, max by (exported_job, task) (nomad_client_allocs_memory_rss))', "{{exported_job}} · {{task}}",
        instant=True)], unit="bytes", thresholds=thr((None, "#8b5cf6")), color=SCHEME("BlPu")), 8, 11)
    d.add(bargauge("Top CPU (MHz)", [prom(
        'topk(12, max by (exported_job, task) (rate(nomad_client_allocs_cpu_total_ticks[5m])))',
        "{{exported_job}} · {{task}}", instant=True)], unit="none", thresholds=thr((None, "#06b6d4")),
        color=SCHEME("GrYlRd"), decimals=0), 8, 11)
    d.add(timeseries("Memory reserved vs used per node", [
        prom('sum by (host) (nomad_client_allocated_memory) * 1048576', "{{host}} reserved"),
        prom('sum by (host) (nomad_client_allocs_memory_rss)', "{{host}} used (RSS)", "B")],
        unit="bytes", fill=10, overrides=[series_color(".*reserved", "#64748b", regex=True, dashed=True, fill=0)]),
        12, 8, newrow=True)
    d.add(state_timeline("Periodic runs (backups, scans)", [prom(
        'count by (parent_id) (nomad_client_allocs_memory_rss{parent_id!=""})', "{{parent_id}}")],
        thresholds=thr((None, "#22c55e")), desc="Bars show when each periodic job was running."), 12, 8)

    # --- ingress + sso
    d.row("Traffic & SSO")
    d.add(timeseries("Requests by status class", [prom(
        'sum by (class) (label_replace(rate(traefik_service_requests_total[$__rate_interval]), "class", "${1}xx", "code", "(.).."))', "{{class}}")],
        unit="reqps", stack=True, fill=50, overrides=STATUS_COLORS, draw="bars", legend_calcs=("sum",)), 8, 8)
    d.add(bargauge("Busiest services (req/s)", [prom(
        'topk(10, sum by (service) (rate(traefik_service_requests_total[5m])))', "{{service}}", instant=True)],
        unit="reqps", thresholds=thr((None, "#0ea5e9")), color=SCHEME("BlYlRd"), decimals=2), 8, 8)
    d.add(timeseries("p95 latency: Traefik vs Authentik", [
        prom('histogram_quantile(0.95, sum by (le) (rate(traefik_service_request_duration_seconds_bucket[$__rate_interval])))', "Traefik p95"),
        prom('max(authentik_main_request_duration_seconds{quantile="0.95"})', "Authentik p95", "B")],
        unit="s", fill=10, gradient="hue", width=2), 8, 8)

    # --- storage
    d.row("Storage")
    d.add(bargauge("Filesystems", [prom(
        f'100 * (1 - node_filesystem_avail_bytes{{{FS_SEL}}} / node_filesystem_size_bytes{{{FS_SEL}}})',
        "{{node}} {{mountpoint}}", instant=True)], mx=100, mode="lcd"), 8, 8)
    d.add(timeseries("NAS /storage free (and 7 day trend)", [
        prom('max(node_filesystem_avail_bytes{mountpoint="/storage"})', "free"),
        prom('max(predict_linear(node_filesystem_avail_bytes{mountpoint="/storage"}[7d], 7 * 86400))', "projected in 7d", "B")],
        unit="bytes", fill=20, overrides=[series_color("projected in 7d", ORANGE, dashed=True, fill=0)]), 8, 8)
    d.add(timeseries("NFS client ops by node", [prom(
        'sum by (node) (rate(node_nfs_requests_total[$__rate_interval]))', "{{node}}")], unit="ops", fill=15), 8, 8)

    # --- logs
    d.row("Logs")
    d.add(timeseries("Log volume by source", [loki(
        'sum by (source) (count_over_time({node=~".+"} [$__auto]))', "{{source}}")],
        ds=LOKI, draw="bars", fill=70, stack=True, legend_calcs=("sum",)), 8, 8)
    d.add(timeseries("Error lines by node", [loki(
        f'sum by (node) (count_over_time({{node=~".+"}} |~ "{ERR_RE}" [$__auto]))', "{{node}}")],
        ds=LOKI, draw="bars", fill=70, stack=True, legend_calcs=("sum",),
        overrides=[series_color("odin", "#f97316"), series_color("thor", "#ef4444"), series_color("loki", "#eab308")]),
        8, 8)
    d.add(logs("Latest errors", [loki(f'{{node=~".+"}} |~ "{ERR_RE}"')]), 8, 8)

    # --- monitoring + alerts
    d.row("Health")
    d.add(state_timeline("Scrape targets", [prom('up', "{{job}} {{node}}")], mappings=VALUE_MAP_UP,
                         thresholds=thr((None, RED), (1, GREEN))), 16, 10)
    d.add(alertlist("Firing and pending alerts"), 8, 10)
    return d


# ---------------------------------------------------------------- nodes
def nodes():
    v = [var_query("node", "label_values(node_uname_info, node)", "Node")]
    d = Dash("homelab-nodes", "Nodes", ["homelab", "infrastructure"],
             "Host metrics from node-exporter, one row per node.", variables=v)
    d.add(table("Node summary", [
        prom(f'node_time_seconds{{{NODE_SEL}}} - node_boot_time_seconds{{{NODE_SEL}}}', ref="uptime", instant=True, fmt="table"),
        prom(f'count by (node) (node_cpu_seconds_total{{mode="idle",{NODE_SEL}}})', ref="cores", instant=True, fmt="table"),
        prom(f'node_memory_MemTotal_bytes{{{NODE_SEL}}}', ref="ram", instant=True, fmt="table"),
        prom(f'100 * (1 - avg by (node) (rate(node_cpu_seconds_total{{mode="idle",{NODE_SEL}}}[5m])))', ref="cpu", instant=True, fmt="table"),
        prom(f'100 * (1 - node_memory_MemAvailable_bytes{{{NODE_SEL}}} / node_memory_MemTotal_bytes{{{NODE_SEL}}})', ref="mem", instant=True, fmt="table"),
        prom(f'100 * (1 - node_filesystem_avail_bytes{{mountpoint="/",{NODE_SEL}}} / node_filesystem_size_bytes{{mountpoint="/",{NODE_SEL}}})', ref="root", instant=True, fmt="table"),
        prom(f'node_load5{{{NODE_SEL}}}', ref="load", instant=True, fmt="table"),
        prom(f'max by (node) (node_hwmon_temp_celsius{{{NODE_SEL}}})', ref="temp", instant=True, fmt="table"),
        prom(f'increase(node_vmstat_oom_kill{{{NODE_SEL}}}[24h])', ref="oom", instant=True, fmt="table"),
        prom(f'max by (node, release) (node_uname_info{{{NODE_SEL}}})', ref="kernel", instant=True, fmt="table"),
    ], transformations=[
        {"id": "merge", "options": {}},
        {"id": "organize", "options": {
            "excludeByName": {"Time": True, "instance": True, "job": True, "Value #kernel": True},
            "indexByName": {"node": 0, "Value #uptime": 1, "Value #cores": 2, "Value #ram": 3, "Value #cpu": 4,
                            "Value #mem": 5, "Value #root": 6, "Value #load": 7, "Value #temp": 8,
                            "Value #oom": 9, "release": 10},
            "renameByName": {"node": "Node", "Value #uptime": "Uptime", "Value #cores": "Cores",
                             "Value #ram": "RAM", "Value #cpu": "CPU", "Value #mem": "Memory",
                             "Value #root": "Root disk", "Value #load": "Load 5m", "Value #temp": "Max temp",
                             "Value #oom": "OOM kills 24h", "release": "Kernel"}}}],
        overrides=[col("Uptime", "s", decimals=0), col("RAM", "bytes"),
                   col("CPU", "percent", cell=GAUGE_BAR, thresholds=PCT_THR, mx=100),
                   col("Memory", "percent", cell=GAUGE_BAR, thresholds=PCT_THR, mx=100),
                   col("Root disk", "percent", cell=GAUGE_BAR, thresholds=PCT_THR, mx=100),
                   col("Max temp", "celsius", cell=COLOR_TXT, thresholds=TEMP_THR),
                   col("OOM kills 24h", cell=COLOR_BG, decimals=0,
                       thresholds=thr((None, "transparent"), (1, ORANGE)))]),
        24, 6)

    d.row("$node", repeat="node")
    n = 'node="$node"'
    d.add(timeseries("CPU by mode", [prom(
        f'sum by (mode) (rate(node_cpu_seconds_total{{{n},mode!="idle"}}[$__rate_interval])) / scalar(count(node_cpu_seconds_total{{{n},mode="idle"}})) * 100', "{{mode}}")],
        unit="percent", stack=True, mn=0, mx=100, fill=40), 8, 8)
    d.add(timeseries("Memory", [
        prom(f'node_memory_MemTotal_bytes{{{n}}} - node_memory_MemAvailable_bytes{{{n}}}', "used"),
        prom(f'node_memory_Buffers_bytes{{{n}}} + node_memory_Cached_bytes{{{n}}}', "buffers + cache", "B"),
        prom(f'node_memory_SwapTotal_bytes{{{n}}} - node_memory_SwapFree_bytes{{{n}}}', "swap used", "D"),
        prom(f'node_memory_MemTotal_bytes{{{n}}}', "total", "E")],
        unit="bytes", fill=25, overrides=[series_color("total", "#808080", dashed=True, fill=0),
                                          series_color("used", ORANGE), series_color("buffers + cache", BLUE),
                                          series_color("swap used", RED)]), 8, 8)
    d.add(timeseries("Load average", [
        prom(f'node_load1{{{n}}}', "1m"), prom(f'node_load5{{{n}}}', "5m", "B"), prom(f'node_load15{{{n}}}', "15m", "C"),
        prom(f'count(node_cpu_seconds_total{{{n},mode="idle"}})', "cores", "D")],
        overrides=[series_color("cores", RED, dashed=True, fill=0)], fill=0), 8, 8)
    d.add(timeseries("Disk throughput (read +, write -)", [
        prom(f'sum by (device) (rate(node_disk_read_bytes_total{{{n},device!~"dm-.*|loop.*"}}[$__rate_interval]))', "{{device}} read"),
        prom(f'-sum by (device) (rate(node_disk_written_bytes_total{{{n},device!~"dm-.*|loop.*"}}[$__rate_interval]))', "{{device}} write", "B")],
        unit="Bps", mn=None), 8, 8)
    d.add(timeseries("Disk busy", [prom(
        f'rate(node_disk_io_time_seconds_total{{{n},device!~"dm-.*|loop.*"}}[$__rate_interval]) * 100', "{{device}}")],
        unit="percent", mn=0, mx=100, fill=10), 8, 8)
    d.add(timeseries("Network (rx +, tx -)", [
        prom(f'rate(node_network_receive_bytes_total{{{n},{NET_DEV}}}[$__rate_interval])', "{{device}} rx"),
        prom(f'-rate(node_network_transmit_bytes_total{{{n},{NET_DEV}}}[$__rate_interval])', "{{device}} tx", "B")],
        unit="Bps", mn=None), 8, 8)
    d.add(bargauge("Filesystems", [prom(
        f'100 * (1 - node_filesystem_avail_bytes{{{n},fstype!~"tmpfs|ramfs|overlay|squashfs|nsfs|autofs"}} / node_filesystem_size_bytes{{{n},fstype!~"tmpfs|ramfs|overlay|squashfs|nsfs|autofs"}})',
        "{{mountpoint}}", instant=True)], mx=100), 8, 8)
    d.add(timeseries("Pressure stall (PSI)", [
        prom(f'rate(node_pressure_cpu_waiting_seconds_total{{{n}}}[$__rate_interval]) * 100', "cpu waiting"),
        prom(f'rate(node_pressure_memory_waiting_seconds_total{{{n}}}[$__rate_interval]) * 100', "memory waiting", "B"),
        prom(f'rate(node_pressure_io_waiting_seconds_total{{{n}}}[$__rate_interval]) * 100', "io waiting", "C"),
        prom(f'rate(node_pressure_memory_stalled_seconds_total{{{n}}}[$__rate_interval]) * 100', "memory stalled", "D")],
        unit="percent", fill=0, desc="Share of time tasks waited on a resource."), 8, 8)
    d.add(timeseries("Temperatures", [prom(
        f'max by (chip) (node_hwmon_temp_celsius{{{n}}})', "{{chip}}")], unit="celsius", fill=0,
        thresholds=thr((None, "transparent"), (85, RED)), thresh_style="line"), 8, 8)
    return d


# ---------------------------------------------------------------- nomad cluster
def nomad_cluster():
    d = Dash("homelab-nomad-cluster", "Nomad Cluster", ["homelab", "nomad"],
             "Nomad servers, scheduler and per-job allocation state.")
    d.add(stat("Nomad agents up", [prom('count(up{job="nomad_metrics"} == 1)')],
               thresholds=thr((None, RED), (2, ORANGE), (3, GREEN)), graph=False), 4, 4)
    d.add(stat("Raft peers", [prom('max(max_over_time(nomad_raft_peers[1h]))')],
               thresholds=thr((None, RED), (2, ORANGE), (3, GREEN)), graph=False), 4, 4)
    d.add(stat("Leader", [prom('max by (host) (nomad_nomad_job_status_running)', "{{host}}", instant=True)],
               text_mode="name", thresholds=thr((None, "#6366f1")), graph=False,
               desc="Job summary metrics come only from the leader, so the reporting host is the leader."), 4, 4)
    d.add(stat("Jobs running", [prom('max(nomad_nomad_job_status_running)')], thresholds=thr((None, GREEN))), 4, 4)
    d.add(stat("Jobs pending", [prom('max(nomad_nomad_job_status_pending)')],
               thresholds=thr((None, GREEN), (1, ORANGE))), 4, 4)
    d.add(stat("Blocked evals", [prom('max(nomad_nomad_blocked_evals_total_blocked)')],
               thresholds=thr((None, GREEN), (1, RED)),
               desc="Evaluations that could not be placed, usually for lack of CPU or memory."), 4, 4)

    cap = '(sum by (host) (nomad_client_allocated_memory) + sum by (host) (nomad_client_unallocated_memory))'
    d.add(bargauge("Memory reserved per node", [prom(
        f'sum by (host) (nomad_client_allocated_memory) / {cap} * 100', "{{host}}", instant=True)], mx=100), 8, 6, newrow=True)
    d.add(bargauge("CPU reserved per node", [prom(
        'sum by (host) (nomad_client_allocated_cpu) / (sum by (host) (nomad_client_allocated_cpu) + sum by (host) (nomad_client_unallocated_cpu)) * 100',
        "{{host}}", instant=True)], mx=100), 8, 6)
    d.add(bargauge("memory_max vs capacity per node", [prom(
        f'sum by (host) (nomad_client_allocated_max_memory) / {cap} * 100', "{{host}}", instant=True)],
        thresholds=thr((None, GREEN), (100, YELLOW), (150, RED)),
        desc="Sum of memory_max against capacity. Over 100% is allowed by oversubscription but tasks can't all burst at once."),
        8, 6)

    nop = 'exported_job!~".*/periodic-.*"'
    d.add(table("Jobs", [
        prom(f'max by (exported_job, task_group) (nomad_nomad_job_summary_running{{{nop}}})', ref="running", instant=True, fmt="table"),
        prom(f'max by (exported_job, task_group) (nomad_nomad_job_summary_starting{{{nop}}})', ref="starting", instant=True, fmt="table"),
        prom(f'max by (exported_job, task_group) (nomad_nomad_job_summary_queued{{{nop}}})', ref="queued", instant=True, fmt="table"),
        prom(f'max by (exported_job, task_group) (delta(nomad_nomad_job_summary_failed{{{nop}}}[24h]))', ref="failed24", instant=True, fmt="table"),
        prom(f'max by (exported_job, task_group) (nomad_nomad_job_summary_failed{{{nop}}})', ref="failed", instant=True, fmt="table"),
        prom(f'max by (exported_job, task_group) (nomad_nomad_job_summary_lost{{{nop}}})', ref="lost", instant=True, fmt="table"),
    ], transformations=[
        {"id": "merge", "options": {}},
        {"id": "organize", "options": {
            "excludeByName": {"Time": True},
            "indexByName": {"exported_job": 0, "task_group": 1, "Value #running": 2, "Value #starting": 3,
                            "Value #queued": 4, "Value #failed24": 5, "Value #failed": 6, "Value #lost": 7},
            "renameByName": {"exported_job": "Job", "task_group": "Group", "Value #running": "Running",
                             "Value #starting": "Starting", "Value #queued": "Queued",
                             "Value #failed": "Failed (all time)", "Value #lost": "Lost",
                             "Value #failed24": "Failed (24h)"}}}],
        overrides=[col("Running", cell=COLOR_BG, thresholds=thr((None, RED), (1, "transparent"))),
                   col("Queued", cell=COLOR_BG, thresholds=thr((None, "transparent"), (1, ORANGE))),
                   col("Failed (24h)", cell=COLOR_BG, decimals=0, thresholds=thr((None, "transparent"), (1, RED))),
                   col("Lost", cell=COLOR_BG, thresholds=thr((None, "transparent"), (1, ORANGE)))],
        sort=[{"displayName": "Failed (24h)", "desc": True}],
        desc="Service and system jobs. Batch jobs that finished show Running 0, which is fine."), 24, 12, newrow=True)

    d.add(state_timeline("Periodic job runs (backups, scans)", [prom(
        'count by (parent_id) (nomad_client_allocs_memory_rss{parent_id!=""})', "{{parent_id}}")],
        thresholds=thr((None, "#22c55e")), desc="When each periodic job had an allocation running."), 24, 10, newrow=True)
    d.add(timeseries("Raft last contact p99", [prom('max by (host) (nomad_raft_leader_lastContact{quantile="0.99"})', "{{host}}")],
                     unit="ms", fill=0), 12, 7, newrow=True)
    d.add(timeseries("Allocation failures (cumulative)", [prom(
        'sum(max by (exported_job, task_group) (nomad_nomad_job_summary_failed))', "failed allocations")],
        fill=0, desc="Steps up whenever an allocation fails."), 12, 7)
    return d


# ---------------------------------------------------------------- nomad workloads
def nomad_workloads():
    v = [var_query("job", 'label_values(nomad_client_allocs_memory_rss{parent_id=""}, exported_job)', "Job"),
         var_query("task", 'label_values(nomad_client_allocs_memory_rss{exported_job=~"$job"}, task)', "Task")]
    d = Dash("homelab-nomad-workloads", "Nomad Workloads", ["homelab", "nomad"],
             "Per-task CPU and memory against reservations and limits, restarts and OOM kills.", variables=v)
    sel = 'exported_job=~"$job",task=~"$task"'
    by = "max by (exported_job, task, host)"
    d.add(table("Tasks", [
        prom(f'{by} (nomad_client_allocs_memory_rss{{{sel}}})', ref="rss", instant=True, fmt="table"),
        prom(f'{by} (nomad_client_allocs_memory_allocated{{{sel}}})', ref="mem", instant=True, fmt="table"),
        prom(f'{by} (nomad_client_allocs_memory_max_allocated{{{sel}}})', ref="max", instant=True, fmt="table"),
        prom(f'{by} (nomad_client_allocs_memory_rss{{{sel}}} / (nomad_client_allocs_memory_max_allocated{{{sel}}} > 0)) * 100', ref="pct", instant=True, fmt="table"),
        prom(f'{by} (rate(nomad_client_allocs_cpu_total_ticks{{{sel}}}[5m]))', ref="cpu", instant=True, fmt="table"),
        prom(f'{by} (nomad_client_allocs_cpu_allocated{{{sel}}})', ref="cpures", instant=True, fmt="table"),
    ], transformations=[
        {"id": "merge", "options": {}},
        {"id": "organize", "options": {
            "excludeByName": {"Time": True},
            "indexByName": {"exported_job": 0, "task": 1, "host": 2, "Value #rss": 3, "Value #mem": 4,
                            "Value #max": 5, "Value #pct": 6, "Value #cpu": 7, "Value #cpures": 8},
            "renameByName": {"exported_job": "Job", "task": "Task", "host": "Node", "Value #rss": "RSS",
                             "Value #mem": "memory", "Value #max": "memory_max",
                             "Value #pct": "RSS / memory_max", "Value #cpu": "CPU MHz",
                             "Value #cpures": "cpu reserved"}}}],
        overrides=[col("RSS", "bytes"), col("memory", "bytes"), col("memory_max", "bytes"),
                   col("RSS / memory_max", "percent", cell=GAUGE_BAR, thresholds=PCT_THR, mx=100),
                   col("CPU MHz", "none", decimals=0), col("cpu reserved", "none")],
        sort=[{"displayName": "RSS / memory_max", "desc": True}]), 24, 12)
    d.add(timeseries("Memory RSS", [prom(f'max by (exported_job, task) (nomad_client_allocs_memory_rss{{{sel}}})', "{{exported_job}}/{{task}}")],
                     unit="bytes", fill=0), 12, 9, newrow=True)
    d.add(timeseries("CPU (MHz)", [prom(f'max by (exported_job, task) (rate(nomad_client_allocs_cpu_total_ticks{{{sel}}}[$__rate_interval]))', "{{exported_job}}/{{task}}")],
                     fill=0), 12, 9)
    d.add(timeseries("Memory vs limits (pick one job)", [
        prom(f'max by (task) (nomad_client_allocs_memory_rss{{{sel}}})', "{{task}} RSS"),
        prom(f'max by (task) (nomad_client_allocs_memory_usage{{{sel}}})', "{{task}} usage incl. cache", "B"),
        prom(f'max by (task) (nomad_client_allocs_memory_allocated{{{sel}}})', "{{task}} memory", "C"),
        prom(f'max by (task) (nomad_client_allocs_memory_max_allocated{{{sel}}})', "{{task}} memory_max", "D")],
        unit="bytes", fill=0, overrides=[series_color(".*memory_max", RED, regex=True, dashed=True),
                                         series_color(".* memory$", YELLOW, regex=True, dashed=True)],
        desc="Dashed lines are the reservation (memory) and the hard limit (memory_max)."), 12, 9, newrow=True)
    d.add(timeseries("CPU throttled time", [prom(
        f'max by (exported_job, task) (rate(nomad_client_allocs_cpu_throttled_time{{{sel}}}[$__rate_interval]))', "{{exported_job}}/{{task}}")],
        unit="ns", fill=0), 12, 9)
    d.add(timeseries("Restarts", [prom(
        f'sum by (exported_job, task) (increase(nomad_client_allocs_restart{{{sel}}}[$__rate_interval]))', "{{exported_job}}/{{task}}")],
        draw="bars", fill=80, legend_calcs=("sum",)), 12, 8, newrow=True)
    d.add(timeseries("OOM kills", [
        prom(f'sum by (exported_job, task) (increase(nomad_client_allocs_oom_killed{{{sel}}}[$__rate_interval]))', "{{exported_job}}/{{task}}"),
        prom('increase(node_vmstat_oom_kill[$__rate_interval])', "kernel OOM kills on {{node}}", "B")],
        draw="bars", fill=80, legend_calcs=("sum",),
        desc="Task OOM kills reported by Nomad plus the kernel OOM-kill counter per node."), 12, 8)
    return d


# ---------------------------------------------------------------- traefik
def traefik():
    v = [var_query("service", 'label_values(traefik_service_requests_total, service)', "Service")]
    d = Dash("homelab-traefik", "Traefik", ["homelab", "ingress"],
             "Ingress traffic, errors, latency and certificates.", variables=v)
    s = 'service=~"$service"'
    d.add(stat("Requests/s", [prom(f'sum(rate(traefik_service_requests_total{{{s}}}[$__rate_interval]))')],
               unit="reqps", thresholds=thr((None, "#0ea5e9")), decimals=2), 6, 4)
    d.add(stat("5xx rate", [prom(f'100 * sum(rate(traefik_service_requests_total{{{s},code=~"5.."}}[5m])) / clamp_min(sum(rate(traefik_service_requests_total{{{s}}}[5m])), 1e-9)')],
               unit="percent", thresholds=thr((None, GREEN), (1, YELLOW), (5, RED)), decimals=2), 6, 4)
    d.add(stat("p95 latency", [prom(f'histogram_quantile(0.95, sum by (le) (rate(traefik_service_request_duration_seconds_bucket{{{s}}}[5m])))')],
               unit="s", thresholds=thr((None, GREEN), (0.5, YELLOW), (2, RED)), decimals=3), 6, 4)
    d.add(stat("Soonest cert expiry", [prom('min(traefik_tls_certs_not_after - time())')],
               unit="s", thresholds=thr((None, RED), (7 * 86400, ORANGE), (14 * 86400, GREEN)), graph=False), 6, 4)
    d.add(timeseries("Requests by service", [prom(f'sum by (service) (rate(traefik_service_requests_total{{{s}}}[$__rate_interval]))', "{{service}}")],
                     unit="reqps", stack=True, fill=40), 12, 9, newrow=True)
    d.add(timeseries("Responses by code", [prom(f'sum by (code) (rate(traefik_service_requests_total{{{s}}}[$__rate_interval]))', "{{code}}")],
                     unit="reqps", stack=True, fill=40, overrides=STATUS_COLORS), 12, 9)
    d.add(timeseries("p95 latency by service", [prom(
        f'histogram_quantile(0.95, sum by (service, le) (rate(traefik_service_request_duration_seconds_bucket{{{s}}}[$__rate_interval])))', "{{service}}")],
        unit="s", fill=0), 12, 9, newrow=True)
    d.add(timeseries("4xx / 5xx by service", [prom(
        f'sum by (service, code) (rate(traefik_service_requests_total{{{s},code=~"[45].."}}[$__rate_interval]))', "{{service}} {{code}}")],
        unit="reqps", fill=0), 12, 9)
    d.add(timeseries("Open connections by entrypoint", [prom('sum by (entrypoint) (traefik_open_connections)', "{{entrypoint}}")],
                     fill=10), 12, 8, newrow=True)
    d.add(table("TLS certificates", [prom('min by (cn, sans) (traefik_tls_certs_not_after - time())', instant=True, fmt="table")],
                transformations=[{"id": "organize", "options": {"excludeByName": {"Time": True},
                                                               "renameByName": {"cn": "Common name", "sans": "SANs",
                                                                                "Value": "Expires in"}}}],
                overrides=[col("Expires in", "s", cell=COLOR_BG, decimals=0,
                               thresholds=thr((None, RED), (7 * 86400, ORANGE), (14 * 86400, "transparent")))]),
          12, 8)
    return d


# ---------------------------------------------------------------- authentik
def authentik():
    d = Dash("homelab-authentik", "Authentik", ["homelab", "services"],
             "SSO health: outposts, request latency, flows and workers.")
    d.add(stat("Outposts connected", [prom('sum(authentik_outposts_connected)')],
               thresholds=thr((None, RED), (1, GREEN)),
               desc="The embedded outpost backs Traefik forward-auth. 0 means forward-auth apps are broken."), 6, 4)
    d.add(stat("Workers", [prom('max(authentik_tasks_workers) or max(authentik_admin_workers)')],
               thresholds=thr((None, RED), (1, GREEN))), 6, 4)
    d.add(stat("Tasks queued", [prom('sum(authentik_tasks_queued)')],
               thresholds=thr((None, GREEN), (20, YELLOW), (100, RED))), 6, 4)
    d.add(stat("Request p95", [prom('max(authentik_main_request_duration_seconds{quantile="0.95"})')],
               unit="s", thresholds=thr((None, GREEN), (0.5, YELLOW), (2, RED)), decimals=3), 6, 4)
    d.add(timeseries("Request latency", [prom('max by (dest, quantile) (authentik_main_request_duration_seconds{quantile=~"0.5|0.95|0.99"})', "{{dest}} p{{quantile}}")],
                     unit="s", fill=0), 12, 8, newrow=True)
    d.add(timeseries("HTTP responses by status", [prom('sum by (status) (rate(django_http_responses_total_by_status_total[$__rate_interval]))', "{{status}}")],
                     unit="reqps", stack=True, fill=40, overrides=STATUS_COLORS), 12, 8)
    d.add(timeseries("Flow stage time p95", [prom(
        'histogram_quantile(0.95, sum by (stage_type, le) (rate(authentik_flows_stage_time_bucket[$__rate_interval])))', "{{stage_type}}")],
        unit="s", fill=0), 12, 8, newrow=True)
    d.add(timeseries("Policy execution p95", [prom(
        'histogram_quantile(0.95, sum by (le) (rate(authentik_policies_execution_time_bucket[$__rate_interval])))', "policies")],
        unit="s", fill=0), 12, 8)
    d.add(timeseries("DB queries/s", [prom('sum by (vendor) (rate(django_db_execute_total[$__rate_interval]))', "{{vendor}}")],
                     unit="ops", fill=10), 12, 8, newrow=True)
    d.add(timeseries("Exceptions", [prom('sum by (type) (increase(django_http_exceptions_total_by_type_total[$__rate_interval]))', "{{type}}")],
                     draw="bars", fill=80, legend_calcs=("sum",)), 12, 8)
    return d


# ---------------------------------------------------------------- logs
def logs_dash():
    v = [var_loki_label("node", "node", "Node"), var_loki_label("source", "source", "Source"),
         var_loki_label("unit", "unit", "Systemd unit"), var_loki_label("level", "level", "Level"),
         var_text("search", "Search (regex)", "")]
    # unit and level only exist on journald lines, so their "All" must also match no label.
    for x in v[2:4]:
        x["allValue"] = ".*"
    d = Dash("homelab-logs", "Logs", ["homelab", "observability"],
             "Everything Alloy ships to Loki: journald, host log files and Nomad task stdout/stderr.",
             variables=v, time_from="now-1h")
    sel = '{node=~"$node", source=~"$source"}'
    d.add(timeseries("Log volume by source", [loki(f'sum by (source) (count_over_time({sel} |~ "(?i)$search" [$__auto]))', "{{source}}")],
                     ds=LOKI, draw="bars", fill=70, stack=True, legend_calcs=("sum",)), 12, 7)
    d.add(timeseries("Errors by node", [loki(f'sum by (node) (count_over_time({sel} |~ "{ERR_RE}" |~ "(?i)$search" [$__auto]))', "{{node}}")],
                     ds=LOKI, draw="bars", fill=70, stack=True, legend_calcs=("sum",)), 12, 7)
    d.add(timeseries("Nomad tasks by log volume", [loki(
        'topk(10, sum by (task) (count_over_time({source="nomad", node=~"$node"} |~ "(?i)$search" [$__auto])))', "{{task}}")],
        ds=LOKI, draw="bars", fill=70, stack=True, legend_calcs=("sum",)), 12, 7, newrow=True)
    d.add(timeseries("SSH logins and failures", [
        loki('sum by (node) (count_over_time({unit="ssh.service", node=~"$node"} |~ "Accepted (password|publickey)" [$__auto]))', "{{node}} accepted"),
        loki('sum by (node) (count_over_time({unit="ssh.service", node=~"$node"} |~ "(Failed password|Invalid user|authentication failure)" [$__auto]))', "{{node}} failed", "B")],
        ds=LOKI, draw="bars", fill=70, legend_calcs=("sum",)), 12, 7)
    d.add(logs("All logs (node + source filters)", [loki(f'{sel} |~ "(?i)$search"')]), 24, 14, newrow=True)

    d.row("Host systems (journald)")
    host = '{source="journal", node=~"$node", unit=~"$unit", level=~"$level"}'
    d.add(timeseries("Host log volume by unit", [loki(
        f'topk(12, sum by (unit) (count_over_time({host} |~ "(?i)$search" [$__auto])))', "{{unit}}")],
        ds=LOKI, draw="bars", fill=70, stack=True, legend_calcs=("sum",)), 12, 7)
    d.add(timeseries("Host log volume by level", [loki(
        f'sum by (level) (count_over_time({host} |~ "(?i)$search" [$__auto]))', "{{level}}")],
        ds=LOKI, draw="bars", fill=70, stack=True, legend_calcs=("sum",),
        overrides=[series_color("error|crit|alert|emerg", RED, regex=True), series_color("warning", YELLOW),
                   series_color("notice", BLUE), series_color("info", GREEN)]), 12, 7)
    d.add(logs("Host system logs (journald: systemd units, kernel, sshd, nomad, consul, docker)",
               [loki(f'{host} |~ "(?i)$search"')]), 24, 16, newrow=True)
    d.add(logs("Host log files (/var/log/*.log)",
               [loki('{source="file", node=~"$node"} |~ "(?i)$search"')]), 24, 10, newrow=True)

    d.row("Errors")
    d.add(logs("Errors only", [loki(f'{sel} |~ "{ERR_RE}" |~ "(?i)$search"')]), 24, 12)
    return d


# ---------------------------------------------------------------- monitoring stack
def monitoring_stack():
    d = Dash("homelab-monitoring-stack", "Monitoring Stack", ["homelab", "observability"],
             "Is the monitoring itself healthy? Scrape targets, Prometheus, Loki and Alloy.")
    d.add(table("Scrape targets", [prom('up', instant=True, fmt="table")],
                transformations=[{"id": "organize", "options": {
                    "excludeByName": {"Time": True, "__name__": True},
                    "indexByName": {"job": 0, "node": 1, "instance": 2, "Value": 3},
                    "renameByName": {"job": "Job", "node": "Node", "instance": "Instance", "Value": "State"}}}],
                overrides=[col("State", cell=COLOR_BG, mappings=VALUE_MAP_UP,
                               thresholds=thr((None, RED), (1, GREEN)), width=90)],
                sort=[{"displayName": "State", "desc": False}]), 12, 10)
    d.add(timeseries("Scrape duration", [prom('max by (job) (scrape_duration_seconds)', "{{job}}")],
                     unit="s", fill=0), 12, 10)
    d.add(timeseries("Prometheus head series", [prom('prometheus_tsdb_head_series', "series")], fill=10), 8, 7, newrow=True)
    d.add(timeseries("Prometheus samples/s", [prom('rate(prometheus_tsdb_head_samples_appended_total[$__rate_interval])', "samples/s")],
                     fill=10), 8, 7)
    d.add(timeseries("Prometheus storage", [prom('prometheus_tsdb_storage_blocks_bytes + prometheus_tsdb_wal_storage_size_bytes', "TSDB + WAL")],
                     unit="bytes", fill=10), 8, 7)
    d.add(timeseries("Loki lines received/s", [prom('sum(rate(loki_distributor_lines_received_total[$__rate_interval]))', "lines/s")],
                     fill=10), 8, 7, newrow=True)
    d.add(timeseries("Loki bytes received/s", [prom('sum(rate(loki_distributor_bytes_received_total[$__rate_interval]))', "bytes/s")],
                     unit="Bps", fill=10), 8, 7)
    d.add(timeseries("Loki request p95 by route", [prom(
        'histogram_quantile(0.95, sum by (route, le) (rate(loki_request_duration_seconds_bucket{route!~"metrics|ready"}[$__rate_interval])))', "{{route}}")],
        unit="s", fill=0, legend_calcs=("max",)), 8, 7)
    d.add(stat("Alloy config loaded", [prom('min(alloy_config_last_load_successful)')],
               mappings=[{"type": "value", "options": {"0": {"text": "FAILED", "color": RED},
                                                        "1": {"text": "OK", "color": GREEN}}}],
               thresholds=thr((None, RED), (1, GREEN)), graph=False), 8, 7, newrow=True)
    d.add(timeseries("Alloy memory", [prom('alloy_resources_process_resident_memory_bytes', "{{node}}")],
                     unit="bytes", fill=0), 8, 7)
    d.add(timeseries("Loki active streams", [prom('sum(loki_ingester_memory_streams)', "streams")], fill=10), 8, 7)
    return d


DASHES = {
    "Homelab/command-center.json": command_center,
    "Infrastructure/nodes.json": nodes,
    "Infrastructure/nomad-cluster.json": nomad_cluster,
    "Infrastructure/nomad-workloads.json": nomad_workloads,
    "Infrastructure/traefik.json": traefik,
    "Services/authentik.json": authentik,
    "Observability/logs.json": logs_dash,
    "Observability/monitoring-stack.json": monitoring_stack,
}


def clean(o):
    if isinstance(o, dict):
        return {k: clean(v) for k, v in o.items() if v is not None}
    if isinstance(o, list):
        return [clean(v) for v in o]
    return o


# ================================================================ alert rules
# Each rule: instant query A plus threshold C on A. Labels on A become alert labels.
# severity=critical repeats hourly, warning every 4h (see alerting/policies.yaml).

def rule(uid, title, expr, op, value, for_, severity, summary, description, ds="prom",
         no_data="OK", exec_err="Error", lookback=600):
    a = {"refId": "A", "relativeTimeRange": {"from": lookback, "to": 0},
         "datasourceUid": (PROM if ds == "prom" else LOKI)["uid"],
         "model": {"refId": "A", "expr": expr, "intervalMs": 15000, "maxDataPoints": 43200}}
    if ds == "prom":
        a["model"].update({"instant": True, "range": False})
    else:
        a["model"]["queryType"] = "instant"
    c = {"refId": "C", "relativeTimeRange": {"from": 0, "to": 0}, "datasourceUid": "__expr__",
         "model": {"refId": "C", "type": "threshold", "expression": "A",
                   "conditions": [{"evaluator": {"type": op, "params": [value]}}]}}
    def guard(text):
        # $values.A is nil when the query returns no series, which breaks template expansion.
        return re.sub(r"\{\{ (humanize |printf \"[^\"]+\" )?\$values\.A\.Value \}\}",
                      lambda m: "{{ with $values.A }}{{ " + (m.group(1) or "") + ".Value }}{{ end }}", text)
    summary, description = guard(summary), guard(description)
    return {"uid": uid, "title": title, "condition": "C", "data": [a, c], "for": for_,
            "noDataState": no_data, "execErrState": exec_err, "isPaused": False,
            "labels": {"severity": severity},
            "annotations": {"summary": summary, "description": description}}


V = "{{ humanize $values.A.Value }}"
VP = '{{ printf "%.1f" $values.A.Value }}'
N = "{{ $labels.node }}"
J = "{{ $labels.exported_job }}"
T = "{{ $labels.task }}"
TG = "{{ $labels.task_group }}"
BACKUP_RSS = 'nomad_client_allocs_memory_rss{parent_id=~".+-backup"}'

ALERT_GROUPS = [
    ("hosts", "1m", [
        rule("host-down", "Host down", 'up{job="node-exporters"}', "lt", 1, "2m", "critical",
             f"{N} is down",
             f"node-exporter on {N} has not answered for 2 minutes. The node is off, hung or off the network."),
        rule("host-cpu-high", "Host CPU high", CPU_PCT.replace("$__rate_interval", "5m"), "gt", 90, "15m", "warning",
             f"{N} CPU at {VP}%", f"CPU on {N} has been above 90% for 15 minutes."),
        rule("host-memory-high", "Host memory high", MEM_PCT, "gt", 90, "10m", "warning",
             f"{N} memory at {VP}%",
             f"Available memory on {N} has been under 10% for 10 minutes. OOM kills are likely next."),
        rule("host-oom-kill", "Kernel OOM kill", 'increase(node_vmstat_oom_kill[10m])', "gt", 0, "0s", "warning",
             f"OOM killer fired on {N}",
             f"The kernel killed {V} process(es) on {N} in the last 10 minutes for lack of memory. "
             "Nomad Workloads shows which task is near its memory_max."),
        rule("host-root-disk", "Root disk filling", ROOT_PCT, "gt", 85, "10m", "warning",
             f"{N} root disk at {VP}%", f"/ on {N} is over 85% full."),
        rule("host-disk-fill-24h", "Disk full within 24h",
             'predict_linear(node_filesystem_avail_bytes{mountpoint=~"/|/storage"}[6h], 86400) '
             'and on (instance, mountpoint) (node_filesystem_avail_bytes{mountpoint=~"/|/storage"} '
             '/ node_filesystem_size_bytes{mountpoint=~"/|/storage"} < 0.25)',
             "lt", 0, "30m", "warning",
             f"{{{{ $labels.mountpoint }}}} on {N} fills within 24h",
             "At the 6h trend this filesystem runs out of space within a day."),
        rule("nas-storage-full", "NAS storage filling", f'max by (mountpoint) ({STORAGE_PCT})', "gt", 85, "15m",
             "warning", f"TrueNAS /storage at {VP}%", "The NFS share used by every job and backup is over 85% full."),
        rule("nas-storage-unmounted", "NAS storage not mounted",
             'up{job="node-exporters"} == 1 unless on (instance) node_filesystem_size_bytes{mountpoint="/storage"}',
             "gt", 0, "2m", "critical",
             f"/storage is not mounted on {N}",
             f"{N} is up but the TrueNAS NFS mount is missing. Jobs with state on that node will fail."),
        rule("nas-nfs-slow", "NFS slow", 'max by (node) ('
             'rate(node_mountstats_nfs_operations_request_time_seconds_total{operation=~"READ|WRITE|GETATTR|LOOKUP"}[5m]) '
             '/ rate(node_mountstats_nfs_operations_requests_total{operation=~"READ|WRITE|GETATTR|LOOKUP"}[5m]))',
             "gt", 0.25, "10m", "warning",
             f"NFS on {N} averaging {V}s per request",
             "NFS requests to TrueNAS have averaged over 250ms for 10 minutes (normal is about 20ms). "
             "The NAS is overloaded, scrubbing, or a disk is failing."),
        rule("host-temp-high", "Host temperature high", 'max by (node) (node_hwmon_temp_celsius)', "gt", 85, "5m",
             "warning", f"{N} at {VP}°C", f"A sensor on {N} has been above 85°C for 5 minutes."),
        rule("host-clock-skew", "Host clock skew", 'abs(node_timex_offset_seconds)', "gt", 0.05, "10m", "warning",
             f"{N} clock off by {V}s", "Clock offset above 50ms. Raft, TLS and log ordering depend on time sync."),
    ]),
    ("nomad", "1m", [
        rule("nomad-agent-down", "Nomad agent down", 'up{job="nomad_metrics"}', "lt", 1, "2m", "critical",
             f"Nomad agent on {N} is down", "The Nomad agent is not answering its metrics endpoint."),
        rule("nomad-raft-peers", "Nomad raft peers missing", 'max(max_over_time(nomad_raft_peers[1h]))', "lt", 3,
             "5m", "critical", "Nomad has {{ $values.A.Value }} raft peers",
             "Fewer than 3 Nomad servers in the raft quorum. Losing one more loses the cluster."),
        rule("nomad-no-leader", "Nomad has no leader", 'absent(nomad_nomad_job_status_running)', "gt", 0, "5m",
             "critical", "Nomad has no leader",
             "No server is publishing leader-only job metrics. Scheduling is stopped."),
        rule("nomad-alloc-failed", "Allocation failed",
             'delta(max by (exported_job, task_group) (nomad_nomad_job_summary_failed{exported_job!~".*/periodic-.*"})[15m:1m])',
             "gt", 0, "0s", "warning",
             f"{J}/{TG} had {V} failed allocation(s)",
             "An allocation failed in the last 15 minutes. Check `nomad job status` and the task logs.",
             lookback=1200),
        rule("nomad-alloc-queued", "Allocation cannot be placed",
             'max by (exported_job, task_group) (nomad_nomad_job_summary_queued)', "gt", 0, "10m", "warning",
             f"{J}/{TG} has {V} queued allocation(s)",
             "Allocations have waited 10 minutes for placement. Usually no node has the CPU or memory to reserve."),
        rule("nomad-task-restarts", "Task restarting",
             'sum by (exported_job, task) (increase(nomad_client_allocs_restart[30m]))', "gt", 2, "0s", "warning",
             f"{J}/{T} restarted {V} times in 30m", "The task is crash looping or failing health checks.",
             lookback=1800),
        rule("nomad-task-oom", "Task OOM killed",
             'sum by (exported_job, task) (increase(nomad_client_allocs_oom_killed[10m]))', "gt", 0, "0s", "warning",
             f"{J}/{T} was OOM killed", "The task hit memory_max. Raise memory_max or find the leak."),
        rule("nomad-task-memory-limit", "Task near memory limit",
             'max by (exported_job, task) (nomad_client_allocs_memory_rss / (nomad_client_allocs_memory_max_allocated > 0)) * 100',
             "gt", 90, "15m", "warning",
             f"{J}/{T} at {VP}% of memory_max", "RSS has been above 90% of the hard limit for 15 minutes."),
        rule("nomad-blocked-evals", "Blocked evaluations", 'max(nomad_nomad_blocked_evals_total_blocked)', "gt", 0,
             "10m", "warning", "{{ $values.A.Value }} blocked Nomad evaluation(s)",
             "The scheduler cannot place work. The cluster is out of reservable CPU or memory."),
        rule("backup-stale", "Backup has not run",
             f'count by (parent_id) (count_over_time({BACKUP_RSS}[7d])) '
             f'unless count by (parent_id) (count_over_time({BACKUP_RSS}[26h])) '
             # only jobs still registered, so a removed backup job doesn't alert for a week
             'and on (parent_id) label_replace(max by (exported_job) (nomad_nomad_job_summary_running), '
             '"parent_id", "$1", "exported_job", "(.+)")',
             "gt", 0, "0s", "warning",
             "{{ $labels.parent_id }} has not run for 26h",
             "This periodic backup ran in the last week but not in the last 26 hours. "
             "Check the job is not stopped and can be placed. Failed runs are reported by the backup job itself."),
    ]),
    ("ingress-and-sso", "1m", [
        rule("traefik-down", "Traefik down", 'up{job="traefik"}', "lt", 1, "2m", "critical",
             f"Traefik on {N} is down",
             "Ingress on this node is down. keepalived only moves the VIP if the whole node goes away."),
        rule("traefik-5xx", "High 5xx rate",
             '100 * sum by (service) (rate(traefik_service_requests_total{code=~"5.."}[5m])) '
             '/ sum by (service) (rate(traefik_service_requests_total[5m])) '
             'and sum by (service) (rate(traefik_service_requests_total[5m])) > 0.05',
             "gt", 5, "10m", "warning",
             '{{ $labels.service }} returns {{ printf "%.1f" $values.A.Value }}% 5xx',
             "More than 5% of responses from this service have been server errors for 10 minutes."),
        rule("tls-cert-expiry", "TLS certificate expiring",
             'min by (cn) (traefik_tls_certs_not_after - time()) / 86400', "lt", 14, "1h", "warning",
             'Certificate {{ $labels.cn }} expires in {{ printf "%.0f" $values.A.Value }} days',
             "Let's Encrypt renews at 30 days left, so under 14 means renewal is failing. "
             "Check Traefik logs for ACME or Cloudflare errors."),
        rule("authentik-outpost-down", "Authentik outpost disconnected",
             'min by (outpost) (authentik_outposts_connected)', "lt", 1, "5m", "critical",
             "Authentik outpost {{ $labels.outpost }} disconnected",
             "Forward-auth apps behind Traefik fail to log in until the outpost reconnects."),
    ]),
    ("observability", "1m", [
        rule("prometheus-unreachable", "Prometheus unreachable", 'up{job="prometheus"}', "lt", 1, "5m",
             "critical", "Prometheus is down or unreachable from Grafana",
             "Metric alerts are blind until Prometheus is back.",
             no_data="Alerting", exec_err="Alerting"),
        rule("scrape-target-down", "Scrape target down",
             'up{job!~"node-exporters|nomad_metrics|traefik|prometheus"}', "lt", 1, "5m", "warning",
             "{{ $labels.job }} target {{ $labels.instance }} is down",
             "Prometheus has failed to scrape this target for 5 minutes."),
        rule("alloy-config-failed", "Alloy config failed to load",
             'min by (node) (alloy_config_last_load_successful)', "lt", 1, "5m", "warning",
             f"Grafana Alloy on {N} failed to load its config", "Log shipping from this node has likely stopped."),
        rule("loki-errors", "Loki request errors",
             'sum(rate(loki_request_duration_seconds_count{status_code=~"5.."}[5m]))', "gt", 0.1, "10m", "warning",
             'Loki is returning 5xx ({{ printf "%.2f" $values.A.Value }}/s)', "Log pushes or queries are failing."),
    ]),
    ("logs", "2m", [
        rule("log-nfs-not-responding", "NFS server not responding",
             'sum by (node) (count_over_time({source="journal"} |~ "(?i)nfs: server .* not responding" [10m]))',
             "gt", 0, "0s", "critical",
             f"{N} lost contact with the NFS server",
             "The kernel reports TrueNAS is not responding. Jobs with state on /storage will hang.", ds="loki"),
        rule("log-disk-errors", "Disk or filesystem errors",
             'sum by (node) (count_over_time({source="journal"} |~ "(?i)(I/O error|EXT4-fs error|nvme.*(timeout|reset))" [10m]))',
             "gt", 0, "0s", "critical",
             f"Disk errors in the kernel log on {N}",
             "{{ $values.A.Value }} I/O or filesystem error lines in 10 minutes. Check SMART and dmesg.", ds="loki"),
        rule("log-ssh-failures", "SSH login failures",
             'sum by (node) (count_over_time({unit="ssh.service"} |~ "(Failed password|Invalid user|authentication failure)" [10m]))',
             "gt", 10, "0s", "warning",
             f"{V} failed SSH logins on {N} in 10m",
             "Repeated SSH authentication failures. Something is guessing passwords.", ds="loki"),
    ]),
]

# Rules made in the UI before provisioning. Grafana deletes them on start.
OLD_RULE_UIDS = ["cfo2pml3k8ikgc", "ffo2pv7c9qgowb", "cfo2q31v7sikgd", "ffo2qdi8aj30gd", "cfo2qi1n8e41sc",
                 "afo2qm91tbugwd"]


def to_yaml(o, indent=0):
    """Tiny YAML emitter. Scalars are JSON-encoded, which is valid YAML."""
    pad = "  " * indent
    if isinstance(o, dict):
        out = []
        for k, v in o.items():
            if isinstance(v, (dict, list)) and v:
                out.append(f"{pad}{k}:\n{to_yaml(v, indent + 1)}")
            elif isinstance(v, (dict, list)):
                out.append(f"{pad}{k}: {'{}' if isinstance(v, dict) else '[]'}")
            else:
                out.append(f"{pad}{k}: {to_yaml(v)}")
        return "\n".join(out)
    if isinstance(o, list):
        out = []
        for v in o:
            if isinstance(v, (dict, list)):
                out.append(f"{pad}- " + to_yaml(v, indent + 1).lstrip())
            else:
                out.append(f"{pad}- {to_yaml(v)}")
        return "\n".join(out)
    return json.dumps(o, ensure_ascii=False)


def alert_rules():
    doc = {"apiVersion": 1,
           "deleteRules": [{"orgId": 1, "uid": u} for u in OLD_RULE_UIDS],
           "groups": [{"orgId": 1, "name": name, "folder": "Homelab Alerts", "interval": interval, "rules": rules}
                      for name, interval, rules in ALERT_GROUPS]}
    return "# Generated by generate.py. Edit that, then re-run it.\n" + to_yaml(doc) + "\n"


def write(path, content):
    full = os.path.join(OUT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    # Nomad renders these files with [[ ]] delimiters so {{ }} reaches Grafana untouched.
    assert "[[" not in content and "]]" not in content, path
    with open(full, "w") as f:
        f.write(content)
    print("wrote", full)


for path, fn in DASHES.items():
    write(os.path.join("dashboards", path), json.dumps(clean(fn().json()), indent=2, ensure_ascii=False) + "\n")
write("alerting/rules.yaml", alert_rules())
