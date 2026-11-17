#!/usr/bin/env python3
"""Generate the homelab Wazuh dashboards as OpenSearch Dashboards saved objects.

Usage: python3 jobs/security/wazuh/dashboards/generate.py

Writes *.ndjson next to this file. The wazuh job's dashboard group imports
them on every start (00-* without overwrite, so the Wazuh app keeps ownership
of its index patterns). Commit the generated files with the script.
"""
import json
import os

OUT = os.path.dirname(os.path.abspath(__file__))
ALERTS = "wazuh-alerts-*"
VULNS = "wazuh-states-vulnerabilities-*"
VERSION = "2.19.6"

RED, ORANGE, YELLOW, GREEN, BLUE, TEAL, GREY = (
    "#E7664C", "#F5A35C", "#D6BF57", "#54B399", "#6092C0", "#209280", "#98A2B3")
SEVERITY = {"Critical": RED, "High": ORANGE, "Medium": YELLOW, "Low": BLUE, "-": GREY}
LEVELS = [("Level 0-6", "rule.level < 7", BLUE), ("Level 7-9", "rule.level >= 7 and rule.level < 10", YELLOW),
          ("Level 10-11", "rule.level >= 10 and rule.level < 12", ORANGE), ("Level 12+", "rule.level >= 12", RED)]
AUTH_OK = "rule.groups:authentication_success"
AUTH_FAIL = "rule.groups:(authentication_failed or authentication_failures)"
SSH, SUDO, FIM, SCA = "rule.groups:sshd", "rule.groups:sudo", "rule.groups:syscheck", "rule.groups:sca"

DASHBOARDS = [
    ("homelab-security-overview", "Homelab Security Overview"),
    ("homelab-hosts-integrity", "Hosts & Integrity"),
    ("homelab-vulnerabilities", "Vulnerabilities"),
    ("homelab-compliance", "Compliance"),
    ("homelab-ssh-sudo", "SSH & Sudo Activity"),
]


def kql(q):
    return {"query": q, "language": "kuery"}


def source(index, query="", ref=True):
    s = {"query": kql(query), "filter": []}
    if ref:
        s["indexRefName"] = "kibanaSavedObjectMeta.searchSourceJSON.index"
    return json.dumps(s)


def count(id_="1", label=None):
    return {"id": id_, "enabled": True, "type": "count", "schema": "metric",
            "params": {"customLabel": label} if label else {}}


def metric(id_, type_, field, label, schema="metric", **extra):
    return {"id": id_, "enabled": True, "type": type_, "schema": schema,
            "params": {"field": field, "customLabel": label, **extra}}


def terms(id_, field, schema, size=10, label=None, order_by="1"):
    return {"id": id_, "enabled": True, "type": "terms", "schema": schema,
            "params": {"field": field, "size": size, "order": "desc", "orderBy": order_by,
                       "otherBucket": False, "missingBucket": False, "customLabel": label}}


def filters(id_, schema, items):
    return {"id": id_, "enabled": True, "type": "filters", "schema": schema,
            "params": {"filters": [{"input": kql(q), "label": l} for l, q in items]}}


def vis(id_, title, vtype, params, aggs, index=ALERTS, query="", colors=None):
    ui = {"vis": {"colors": colors}} if colors else {}
    return {"type": "visualization", "id": id_,
            "attributes": {"title": title, "description": "", "version": 1,
                           "visState": json.dumps({"title": title, "type": vtype, "params": params, "aggs": aggs}),
                           "uiStateJSON": json.dumps(ui),
                           "kibanaSavedObjectMeta": {"searchSourceJSON": source(index, query)}},
            "references": [{"name": "kibanaSavedObjectMeta.searchSourceJSON.index",
                            "type": "index-pattern", "id": index}]}


def markdown(id_, text):
    params = {"fontSize": 12, "openLinksInNewTab": False, "markdown": text}
    return {"type": "visualization", "id": id_,
            "attributes": {"title": "Navigation", "description": "", "version": 1,
                           "visState": json.dumps({"title": "Navigation", "type": "markdown",
                                                   "params": params, "aggs": []}),
                           "uiStateJSON": "{}",
                           "kibanaSavedObjectMeta": {"searchSourceJSON": json.dumps({"query": kql(""), "filter": []})}},
            "references": []}


def metric_vis(id_, title, items, index=ALERTS, query=""):
    params = {"addTooltip": True, "addLegend": False, "type": "metric",
              "metric": {"percentageMode": False, "useRanges": False, "colorSchema": "Green to Red",
                         "metricColorMode": "None", "colorsRange": [{"from": 0, "to": 10000}],
                         "labels": {"show": True}, "invertColors": False,
                         "style": {"bgFill": "#000", "bgColor": False, "labelColor": False,
                                   "subText": "", "fontSize": 32}}}
    return vis(id_, title, "metric", params, [count(), filters("2", "group", items)], index, query)


def xy(id_, title, kind, aggs, horizontal=False, mode="stacked", index=ALERTS, query="",
       colors=None, legend="right", y_title="Count"):
    cat_pos, val_pos = ("left", "bottom") if horizontal else ("bottom", "left")
    params = {
        "type": kind, "grid": {"categoryLines": False, "valueAxis": "ValueAxis-1"},
        "categoryAxes": [{"id": "CategoryAxis-1", "type": "category", "position": cat_pos, "show": True,
                          "style": {}, "scale": {"type": "linear"},
                          "labels": {"show": True, "filter": not horizontal, "truncate": 60, "rotate": 0},
                          "title": {}}],
        "valueAxes": [{"id": "ValueAxis-1", "name": "LeftAxis-1" if not horizontal else "BottomAxis-1",
                       "type": "value", "position": val_pos, "show": True, "style": {},
                       "scale": {"type": "linear", "mode": "normal"},
                       "labels": {"show": True, "rotate": 0, "filter": not horizontal, "truncate": 100},
                       "title": {"text": y_title}}],
        "seriesParams": [{"show": True, "type": "line" if kind == "line" else "histogram", "mode": mode,
                          "data": {"label": y_title, "id": "1"}, "valueAxis": "ValueAxis-1",
                          "drawLinesBetweenPoints": True, "lineWidth": 2, "showCircles": True,
                          "interpolate": "linear"}],
        "addTooltip": True, "addLegend": True, "legendPosition": legend, "times": [],
        "addTimeMarker": False, "labels": {"show": False},
        "thresholdLine": {"show": False, "value": 10, "width": 1, "style": "full", "color": RED},
    }
    return vis(id_, title, kind, params, aggs, index, query, colors)


def table(id_, title, aggs, index=ALERTS, query="", per_page=10):
    params = {"perPage": per_page, "showPartialRows": False, "showMetricsAtAllLevels": False,
              "showTotal": False, "totalFunc": "sum", "percentageCol": ""}
    return vis(id_, title, "table", params, aggs, index, query)


def donut(id_, title, field, index=ALERTS, query="", colors=None, size=10):
    params = {"type": "pie", "addTooltip": True, "addLegend": True, "legendPosition": "right",
              "isDonut": True, "labels": {"show": False, "values": True, "last_level": True, "truncate": 100}}
    return vis(id_, title, "pie", params, [count(), terms("2", field, "segment", size)], index, query, colors)


def heatmap(id_, title, x_field, y_field, query="", scheme="Reds"):
    params = {"type": "heatmap", "addTooltip": True, "addLegend": True, "enableHover": False,
              "legendPosition": "right", "times": [], "colorsNumber": 5, "colorSchema": scheme,
              "setColorRange": False, "colorsRange": [], "invertColors": False, "percentageMode": False,
              "valueAxes": [{"show": False, "id": "ValueAxis-1", "type": "value",
                             "scale": {"type": "linear", "defaultYExtents": False},
                             "labels": {"show": False, "rotate": 0, "overwriteColor": False, "color": "black"}}]}
    aggs = [count(), terms("2", x_field, "segment", 15, "Tactic"), terms("3", y_field, "group", 20, "Technique")]
    return vis(id_, title, "heatmap", params, aggs, ALERTS, query)


def geo_map(id_, title):
    params = {"colorSchema": "Yellow to Red", "mapType": "Scaled Circle Markers", "isDesaturated": True,
              "addTooltip": True, "heatClusterSize": 1.5, "legendPosition": "bottomright",
              "mapZoom": 2, "mapCenter": [30, 0], "wms": {"enabled": False, "options": {"format": "image/png", "transparent": True}}}
    aggs = [count(), {"id": "2", "enabled": True, "type": "geohash_grid", "schema": "segment",
                      "params": {"field": "GeoLocation.location", "autoPrecision": True, "precision": 2,
                                 "useGeocentroid": True, "isFilteredByCollar": True,
                                 "mapZoom": 2, "mapCenter": [30, 0]}}]
    return vis(id_, title, "tile_map", params, aggs, ALERTS, "data.srcip:*")


def tsvb(id_, title, series, chart="bar", stacked="stacked", interval="auto"):
    def one(i, label, query, color):
        return {"id": f"{id_}-s{i}", "color": color, "split_mode": "everything", "label": label,
                "metrics": [{"id": f"{id_}-m{i}", "type": "count"}],
                "filter": kql(query), "separate_axis": 0, "axis_position": "right",
                "formatter": "number", "chart_type": chart, "line_width": 2 if chart == "line" else 0,
                "point_size": 0 if chart == "bar" else 1, "fill": 0.6 if chart == "bar" else 0.15,
                "stacked": stacked, "split_color_mode": "opensearchDashboards",
                "override_index_pattern": 0, "series_drop_last_bucket": 0}
    params = {"id": id_, "type": "timeseries", "series": [one(i, *s) for i, s in enumerate(series)],
              "time_field": "timestamp", "index_pattern": ALERTS, "interval": interval,
              "axis_position": "left", "axis_formatter": "number", "axis_scale": "normal",
              "show_legend": 1, "legend_position": "bottom", "show_grid": 1, "tooltip_mode": "show_all",
              "default_index_pattern": ALERTS, "default_timefield": "timestamp",
              "drop_last_bucket": 0, "isModelInvalid": False, "background_color_rules": [],
              "annotations": []}
    return {"type": "visualization", "id": id_,
            "attributes": {"title": title, "description": "", "version": 1,
                           "visState": json.dumps({"title": title, "type": "metrics", "params": params, "aggs": []}),
                           "uiStateJSON": "{}",
                           "kibanaSavedObjectMeta": {"searchSourceJSON": json.dumps({"query": kql(""), "filter": []})}},
            "references": []}


def search(id_, title, columns, query, index=ALERTS, sort=("timestamp", "desc")):
    return {"type": "search", "id": id_,
            "attributes": {"title": title, "description": "", "hits": 0, "version": 1,
                           "columns": columns, "sort": [list(sort)],
                           "kibanaSavedObjectMeta": {"searchSourceJSON": source(index, query)}},
            "references": [{"name": "kibanaSavedObjectMeta.searchSourceJSON.index",
                            "type": "index-pattern", "id": index}]}


def nav(dash_id):
    links = " · ".join(f"**{t}**" if i == dash_id else f"[{t}](#/view/{i})" for i, t in DASHBOARDS)
    return markdown(f"{dash_id}-nav", links)


def dashboard(id_, title, desc, panels, time_from="now-24h"):
    """panels: list of (saved object, w, h). Laid out left to right on a 48-column grid."""
    rows, refs, x, y, row_h = [], [], 0, 0, 0
    for n, (obj, w, h) in enumerate([(nav(id_), 48, 3)] + panels):
        if x + w > 48:
            x, y, row_h = 0, y + row_h, 0
        rows.append({"version": VERSION, "gridData": {"x": x, "y": y, "w": w, "h": h, "i": str(n)},
                     "panelIndex": str(n), "embeddableConfig": {}, "panelRefName": f"panel_{n}"})
        refs.append({"name": f"panel_{n}", "type": obj["type"], "id": obj["id"]})
        x, row_h = x + w, max(row_h, h)
    dash = {"type": "dashboard", "id": id_,
            "attributes": {"title": title, "description": desc, "version": 1, "hits": 0,
                           "panelsJSON": json.dumps(rows),
                           "optionsJSON": json.dumps({"hidePanelTitles": False, "useMargins": True}),
                           "timeRestore": True, "timeFrom": time_from, "timeTo": "now",
                           "refreshInterval": {"pause": False, "value": 60000},
                           "kibanaSavedObjectMeta": {"searchSourceJSON": json.dumps({"query": kql(""), "filter": []})}},
            "references": refs}
    objects = {o["id"]: o for o, _, _ in [(nav(id_), 0, 0)] + panels}
    return list(objects.values()) + [dash]


def index_patterns():
    return [
        {"type": "index-pattern", "id": ALERTS,
         "attributes": {"title": ALERTS, "timeFieldName": "timestamp"}, "references": []},
        {"type": "index-pattern", "id": VULNS, "attributes": {"title": VULNS}, "references": []},
    ]


def overview():
    d = "homelab-security-overview"
    return dashboard(d, "Homelab Security Overview", "Alerts, MITRE ATT&CK and authentication across all agents.", [
        (metric_vis(f"{d}-kpi", "Alert summary", [
            ("Alerts", "*"), ("Level 10+", "rule.level >= 10"),
            ("Auth failures", AUTH_FAIL), ("FIM changes", FIM)]), 48, 6),
        (tsvb(f"{d}-timeline", "Alerts over time by level", LEVELS), 32, 14),
        (donut(f"{d}-agents", "Alerts by agent", "agent.name"), 16, 14),
        (heatmap(f"{d}-mitre", "MITRE ATT&CK: tactic × technique", "rule.mitre.tactic", "rule.mitre.technique",
                 "rule.mitre.id:*"), 30, 18),
        (table(f"{d}-rules", "Top rules", [count(), terms("2", "rule.id", "bucket", 15, "Rule"),
                                            terms("3", "rule.description", "bucket", 1, "Description"),
                                            terms("4", "rule.level", "bucket", 1, "Level")]), 18, 18),
        (tsvb(f"{d}-auth", "Authentication: success vs failure", [
            ("Success", AUTH_OK, GREEN), ("Failure", AUTH_FAIL, RED)], chart="line", stacked="none"), 24, 13),
        (geo_map(f"{d}-geo", "Source IPs (GeoIP)"), 24, 13),
        (search(f"{d}-high", "Level 10+ alerts",
                ["agent.name", "rule.level", "rule.id", "rule.description", "data.srcip"], "rule.level >= 10"), 48, 14),
    ])


def hosts():
    d = "homelab-hosts-integrity"
    events = {"added": GREEN, "modified": YELLOW, "deleted": RED}
    return dashboard(d, "Hosts & Integrity", "File integrity monitoring (syscheck) and rootcheck.", [
        (metric_vis(f"{d}-kpi", "FIM summary", [
            ("Changes", "*"), ("Added", "syscheck.event:added"),
            ("Modified", "syscheck.event:modified"), ("Deleted", "syscheck.event:deleted")], query=FIM), 48, 6),
        (tsvb(f"{d}-timeline", "FIM changes over time", [
            (e.capitalize(), f"{FIM} and syscheck.event:{e}", c) for e, c in events.items()]), 32, 14),
        (xy(f"{d}-agents", "Changes by agent", "horizontal_bar",
            [count(), terms("2", "agent.name", "segment", 10, "Agent"), terms("3", "syscheck.event", "group", 3, "Event")],
            horizontal=True, query=FIM, colors={k.capitalize(): v for k, v in events.items()} | events), 16, 14),
        (table(f"{d}-files", "Top changed files", [
            count(), terms("2", "syscheck.path", "bucket", 20, "Path"),
            metric("3", "cardinality", "agent.name", "Agents")], query=FIM), 24, 16),
        (table(f"{d}-rootcheck", "Rootcheck findings", [
            count(), terms("2", "rule.description", "bucket", 15, "Finding"),
            metric("3", "cardinality", "agent.name", "Agents")], query="rule.groups:rootcheck"), 24, 16),
        (search(f"{d}-recent", "Recent file changes",
                ["agent.name", "syscheck.path", "syscheck.event", "syscheck.uname_after", "syscheck.audit.login_user.name",
                 "rule.description"], FIM), 48, 16),
    ], time_from="now-7d")


def vulnerabilities():
    d = "homelab-vulnerabilities"
    return dashboard(d, "Vulnerabilities", "Open CVEs from the vulnerability detector state index (current state, "
                     "not time-filtered).", [
        (metric_vis(f"{d}-kpi", "Open CVEs by severity", [
            ("Critical", "vulnerability.severity:Critical"), ("High", "vulnerability.severity:High"),
            ("Medium", "vulnerability.severity:Medium"), ("Low", "vulnerability.severity:Low"),
            ("Untriaged", "vulnerability.severity:\"-\"")], index=VULNS), 48, 6),
        (xy(f"{d}-agents", "Open CVEs by agent and severity", "histogram",
            [count(), terms("2", "agent.name", "segment", 10, "Agent"),
             terms("3", "vulnerability.severity", "group", 5, "Severity")],
            index=VULNS, colors=SEVERITY), 24, 15),
        (donut(f"{d}-severity", "Severity mix", "vulnerability.severity", index=VULNS, colors=SEVERITY), 24, 15),
        (table(f"{d}-packages", "Top vulnerable packages", [
            count("1", "CVE findings"), terms("2", "package.name", "bucket", 20, "Package", order_by="1"),
            metric("3", "cardinality", "vulnerability.id", "Unique CVEs"),
            metric("4", "max", "vulnerability.score.base", "Max CVSS"),
            metric("5", "cardinality", "agent.name", "Agents")], index=VULNS), 24, 18),
        (table(f"{d}-cves", "Most widespread Critical/High CVEs", [
            metric("1", "cardinality", "agent.name", "Agents"),
            terms("2", "vulnerability.id", "bucket", 20, "CVE"),
            terms("3", "vulnerability.severity", "bucket", 1, "Severity"),
            metric("4", "max", "vulnerability.score.base", "CVSS")],
            index=VULNS, query="vulnerability.severity:(Critical or High)"), 24, 18),
        (search(f"{d}-critical", "Critical CVEs",
                ["agent.name", "vulnerability.id", "package.name", "package.version", "vulnerability.score.base",
                 "vulnerability.published_at"],
                "vulnerability.severity:Critical", index=VULNS, sort=("vulnerability.score.base", "desc")), 48, 16),
    ])


def compliance():
    d = "homelab-compliance"
    gauge = {"type": "gauge", "addTooltip": True, "addLegend": False, "isDisplayWarning": False,
             "gauge": {"alignment": "automatic", "extendRange": False, "percentageMode": False,
                       "gaugeType": "Arc", "gaugeStyle": "Full", "backStyle": "Full", "orientation": "vertical",
                       "colorSchema": "Green to Red", "gaugeColorMode": "Labels",
                       "colorsRange": [{"from": 0, "to": 50}, {"from": 50, "to": 80}, {"from": 80, "to": 100}],
                       "invertColors": True, "labels": {"show": True, "color": "black"},
                       "scale": {"show": True, "labels": False, "color": "rgba(105,112,125,0.2)"},
                       "type": "meter",
                       "style": {"bgWidth": 0.9, "width": 0.9, "mask": False, "bgMask": False, "maskBars": 50,
                                 "bgFill": "rgba(105,112,125,0.2)", "bgColor": True, "subText": "", "fontSize": 60}}}
    score = {"id": "1", "enabled": True, "type": "top_hits", "schema": "metric",
             "params": {"field": "data.sca.score", "aggregate": "max", "size": 1, "sortField": "timestamp",
                        "sortOrder": "desc", "customLabel": "SCA score %"}}
    return dashboard(d, "Compliance", "Security Configuration Assessment (CIS Debian 13 benchmark). SCA only "
                     "reports changes after the first scan, so this defaults to 30 days.", [
        (vis(f"{d}-score", "SCA score per agent (latest scan)", "gauge", gauge,
             [score, terms("2", "agent.name", "group", 10, "Agent", order_by="_key")],
             query="data.sca.type:summary"), 30, 14),
        (donut(f"{d}-results", "Check results", "data.sca.check.result", query=SCA,
               colors={"passed": GREEN, "failed": RED, "not applicable": GREY}), 18, 14),
        (table(f"{d}-failed", "Failed checks", [
            metric("1", "cardinality", "agent.name", "Agents failing"),
            terms("2", "data.sca.check.title", "bucket", 50, "Check"),
            terms("3", "data.sca.check.id", "bucket", 1, "ID")],
            query="data.sca.check.result:failed", per_page=15), 48, 22),
    ], time_from="now-30d")


def auth():
    d = "homelab-ssh-sudo"
    return dashboard(d, "SSH & Sudo Activity", "SSH logins, failures and sudo commands from journald.", [
        (metric_vis(f"{d}-kpi", "Auth summary", [
            ("SSH logins", f"{SSH} and {AUTH_OK}"), ("SSH failures", f"{SSH} and {AUTH_FAIL}"),
            ("Sudo commands", SUDO), ("Sudo failures", f"{SUDO} and {AUTH_FAIL}")]), 48, 6),
        (tsvb(f"{d}-timeline", "SSH and sudo over time", [
            ("SSH success", f"{SSH} and {AUTH_OK}", GREEN), ("SSH failure", f"{SSH} and {AUTH_FAIL}", RED),
            ("Sudo", SUDO, BLUE)], chart="bar", stacked="none"), 48, 13),
        (table(f"{d}-ssh-ok", "SSH logins by source and user", [
            count(), terms("2", "data.srcip", "bucket", 15, "Source IP"),
            terms("3", "data.dstuser", "bucket", 5, "User")], query=f"{SSH} and {AUTH_OK}"), 24, 15),
        (table(f"{d}-ssh-fail", "SSH failures by source and user", [
            count(), terms("2", "data.srcip", "bucket", 15, "Source IP"),
            terms("3", "data.srcuser", "bucket", 5, "User"), terms("4", "agent.name", "bucket", 3, "Host")],
            query=f"{SSH} and {AUTH_FAIL}"), 24, 15),
        (table(f"{d}-sudo", "Sudo commands", [
            count(), terms("2", "data.srcuser", "bucket", 5, "User"), terms("3", "data.dstuser", "bucket", 3, "As"),
            terms("4", "data.command", "bucket", 25, "Command")], query=SUDO, per_page=15), 48, 18),
        (search(f"{d}-events", "Authentication events",
                ["agent.name", "rule.description", "data.srcip", "data.srcuser", "data.dstuser", "data.command"],
                f"{SSH} or {SUDO} or rule.groups:pam"), 48, 16),
    ], time_from="now-7d")


def write(name, objects):
    text = "".join(json.dumps(o, ensure_ascii=False, sort_keys=True) + "\n" for o in objects)
    assert "{{" not in text, f"{name}: Nomad templates would parse '{{{{'"
    with open(os.path.join(OUT, name), "w") as f:
        f.write(text)


if __name__ == "__main__":
    write("00-index-patterns.ndjson", index_patterns())
    write("10-overview.ndjson", overview())
    write("20-hosts-integrity.ndjson", hosts())
    write("30-vulnerabilities.ndjson", vulnerabilities())
    write("40-compliance.ndjson", compliance())
    write("50-ssh-sudo.ndjson", auth())
