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
ECHARTS = "volkovlabs-echarts-panel"

# ---------------------------------------------------------------- design system
# Semantic colors: good / warn / high / bad, plus neutral accents for plain metrics.
GOOD, WARN, HIGH, BAD = "#3ecf8e", "#f5b73b", "#ff8a3d", "#f2495c"
INFO, ACCENT, TEAL, PINK, SLATE = "#5794f2", "#8b7cf6", "#2dd4bf", "#f472b6", "#8e9aaf"
GREEN, YELLOW, ORANGE, RED, BLUE, PURPLE = GOOD, WARN, HIGH, BAD, INFO, ACCENT
CLEAR = "transparent"
NODE_COLORS = {"odin": "#7c8cf8", "thor": TEAL, "loki": PINK}
HEAT = ["#14161f", "#26215c", "#4c3fa8", "#8b7cf6", "#f472b6", "#ffb86b"]


def thr(*steps):
    return {"mode": "absolute", "steps": [{"value": v, "color": c} for v, c in steps]}


PCT_THR = thr((None, GOOD), (70, WARN), (85, HIGH), (95, BAD))
TEMP_THR = thr((None, GOOD), (70, WARN), (85, BAD))
COUNT_THR = lambda warn, crit: thr((None, GOOD), (warn, HIGH), (crit, BAD))  # noqa: E731
ZERO_GOOD = thr((None, GOOD), (1, BAD))
FIXED = lambda c: thr((None, c))  # noqa: E731
SCHEME = lambda s: {"mode": f"continuous-{s}"}  # noqa: E731
BY_NAME = {"mode": "palette-classic-by-name"}
CALC_NAMES = {"mean": "Mean", "max": "Max", "min": "Min", "lastNotNull": "Last *", "sum": "Total"}


class Dash:
    def __init__(self, uid, title, tags, desc="", refresh="30s", time_from="now-6h", variables=None):
        self.uid, self.title, self.tags, self.desc = uid, title, tags, desc
        self.refresh, self.time_from = refresh, time_from
        self.variables = variables or []
        self.panels, self.next_id, self.y, self.cx, self.rowh = [], 1, 0, 0, 0
        self.links, self.target = [], self.panels

    def add(self, p, w, h, newrow=False):
        if newrow or self.cx + w > 24:
            self.y += self.rowh
            self.cx, self.rowh = 0, 0
        p["id"] = self.next_id
        self.next_id += 1
        p["gridPos"] = {"x": self.cx, "y": self.y, "w": w, "h": h}
        self.cx += w
        self.rowh = max(self.rowh, h)
        self.target.append(p)
        return p

    def row(self, title, repeat=None, collapsed=False):
        self.y += self.rowh
        self.cx, self.rowh = 0, 0
        p = {"type": "row", "title": title, "collapsed": collapsed, "panels": [], "id": self.next_id,
             "gridPos": {"x": 0, "y": self.y, "w": 24, "h": 1}}
        if repeat:
            p["repeat"] = repeat
        self.next_id += 1
        self.panels.append(p)
        self.target = p["panels"] if collapsed else self.panels
        self.y += 1

    def json(self):
        return {
            "uid": self.uid, "title": self.title, "description": self.desc, "tags": self.tags,
            "editable": False, "graphTooltip": 1, "timezone": "browser", "refresh": self.refresh,
            "schemaVersion": 41, "time": {"from": self.time_from, "to": "now"}, "fiscalYearStartMonth": 0,
            "liveNow": False, "templating": {"list": self.variables},
            "annotations": {"list": [{
                "builtIn": 1, "datasource": {"type": "grafana", "uid": "-- Grafana --"},
                "enable": True, "hide": True, "iconColor": "rgba(0, 211, 255, 1)",
                "name": "Annotations & Alerts", "type": "dashboard"}]},
            "links": [{"title": "Dashboards", "type": "dashboards", "tags": ["homelab"],
                       "asDropdown": True, "includeVars": False, "keepTime": True}] + self.links,
            "panels": self.panels,
        }


def prom(expr, legend="", ref="A", instant=False, fmt="time_series"):
    return {"datasource": PROM, "expr": expr, "legendFormat": legend or "__auto", "refId": ref,
            "range": not instant, "instant": instant, "format": fmt, "editorMode": "code"}


def loki(expr, legend="", ref="A", instant=False):
    return {"datasource": LOKI, "expr": expr, "legendFormat": legend, "refId": ref,
            "queryType": "instant" if instant else "range", "editorMode": "code"}


def defaults(unit=None, mn=None, mx=None, thresholds=None, decimals=None, color=None, mappings=None, custom=None):
    d = {"color": color or BY_NAME, "custom": custom or {}, "thresholds": thresholds or FIXED(GOOD)}
    for k, v in (("unit", unit), ("min", mn), ("max", mx), ("decimals", decimals), ("mappings", mappings)):
        if v is not None:
            d[k] = v
    return d


def panel(kind, title, targets, desc, ds, field_defaults, options, overrides=None, transparent=False, **extra):
    p = {"type": kind, "title": title, "description": desc, "datasource": ds, "targets": targets,
         "transparent": transparent,
         "fieldConfig": {"defaults": field_defaults, "overrides": overrides or []}, "options": options}
    p.update({k: v for k, v in extra.items() if v is not None})
    return p


def timeseries(title, targets, unit=None, mn=None, mx=None, stack=False, desc="", fill=18,
               overrides=None, legend_calcs=("mean", "max", "lastNotNull"), thresholds=None,
               thresh_style=None, ds=PROM, draw="line", legend_mode="table", color=None,
               gradient="opacity", transparent=False, width=2, legend_place="bottom", nodes=False,
               decimals=None, centered=False, percent_stack=False, **extra):
    bars = draw == "bars"
    custom = {"drawStyle": draw, "lineWidth": 1 if bars else width, "fillOpacity": 80 if bars else fill,
              "gradientMode": "none" if bars else gradient, "showPoints": "never", "pointSize": 4,
              "spanNulls": not bars, "lineInterpolation": "smooth", "barAlignment": 0, "barWidthFactor": 0.75,
              "axisBorderShow": False, "axisPlacement": "auto", "axisLabel": "",
              "stacking": {"mode": "percent" if percent_stack else ("normal" if stack else "none"),
                           "group": "A"},
              "insertNulls": False, "hideFrom": {"legend": False, "tooltip": False, "viz": False}}
    if mn is None and not stack and not centered:
        custom["axisSoftMin"] = 0
    if centered:
        custom["axisCenteredZero"] = True
    if thresh_style:
        custom["thresholdsStyle"] = {"mode": thresh_style}
    ovr = list(overrides or [])
    if nodes:
        ovr = [series_color(n, c) for n, c in NODE_COLORS.items()] + ovr
    if bars and legend_calcs == ("mean", "max", "lastNotNull"):
        legend_calcs = ("sum",)
    return panel("timeseries", title, targets, desc, ds,
                 defaults(unit, mn, mx, thresholds or FIXED(GOOD), decimals, color=color, custom=custom),
                 {"legend": {"displayMode": legend_mode, "placement": legend_place, "calcs": list(legend_calcs),
                             "showLegend": True, "sortBy": CALC_NAMES.get(legend_calcs[0]) if legend_calcs else None,
                             "sortDesc": True if legend_calcs else None},
                  "tooltip": {"mode": "multi", "sort": "desc", "hideZeros": True}},
                 ovr, transparent, **extra)


def bars(title, targets, **kw):
    kw.setdefault("stack", True)
    return timeseries(title, targets, draw="bars", **kw)


def stat(title, targets, unit=None, thresholds=None, desc="", color_mode="value", graph=True,
         mappings=None, decimals=None, text_mode="auto", calc="lastNotNull", ds=PROM, color=None,
         orientation="auto", delta=False, **extra):
    return panel("stat", title, targets, desc, ds,
                 defaults(unit, None, None, thresholds or FIXED(INFO), decimals,
                          color=color or {"mode": "thresholds"}, mappings=mappings),
                 {"colorMode": color_mode, "graphMode": "area" if graph else "none", "justifyMode": "auto",
                  "textMode": text_mode, "wideLayout": True, "orientation": orientation,
                  "reduceOptions": {"calcs": [calc], "fields": "", "values": False},
                  "showPercentChange": delta, "percentChangeColorMode": "standard"}, **extra)


def health(title, targets, thresholds, desc="", mappings=None, unit=None, decimals=None, graph=False, **kw):
    """A status tile: the whole tile takes the threshold color."""
    return stat(title, targets, unit, thresholds, desc, color_mode="background", graph=graph,
                mappings=mappings, decimals=decimals, **kw)


def gauge(title, targets, unit="percent", thresholds=PCT_THR, mn=0, mx=100, desc=""):
    return panel("gauge", title, targets, desc, PROM,
                 defaults(unit, mn, mx, thresholds, 1, color={"mode": "thresholds"}),
                 {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                  "showThresholdLabels": False, "showThresholdMarkers": True, "minVizHeight": 75,
                  "minVizWidth": 75, "sizing": "auto"})


def bargauge(title, targets, unit="percent", thresholds=PCT_THR, mn=0, mx=None, desc="", mode="gradient",
             orientation="horizontal", color=None, decimals=None, ds=PROM, overrides=None):
    return panel("bargauge", title, targets, desc, ds,
                 defaults(unit, mn, mx, thresholds, decimals, color=color or {"mode": "thresholds"}),
                 {"displayMode": mode, "orientation": orientation, "showUnfilled": True,
                  "valueMode": "color", "namePlacement": "left" if orientation == "horizontal" else "auto",
                  "sizing": "manual", "minVizHeight": 18, "maxVizHeight": 22, "minVizWidth": 8,
                  "legend": {"showLegend": False},
                  "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}}, overrides)


def topn(title, targets, unit="short", color=ACCENT, desc="", decimals=0, ds=PROM, scheme=None):
    """Ranked horizontal bars for top-N lists, colored on a continuous scale."""
    return bargauge(title, targets, unit=unit, thresholds=FIXED(color), desc=desc, decimals=decimals, ds=ds,
                    color=SCHEME(scheme) if scheme else {"mode": "fixed", "fixedColor": color})


def donut(title, targets, unit="short", desc="", ds=PROM, overrides=None, decimals=0, calc="lastNotNull"):
    return panel("piechart", title, targets, desc, ds,
                 defaults(unit, decimals=decimals, color=BY_NAME),
                 {"pieType": "donut", "displayLabels": ["percent"], "sort": "desc",
                  "legend": {"displayMode": "table", "placement": "right", "values": ["value", "percent"],
                             "showLegend": True},
                  "reduceOptions": {"calcs": [calc], "fields": "", "values": False},
                  "tooltip": {"mode": "single", "sort": "none"}}, overrides)


def barchart(title, targets, x_field, rename, unit="short", desc="", ds=LOKI, color=ACCENT):
    return panel("barchart", title, targets, desc, ds,
                 defaults(unit, decimals=0, color={"mode": "fixed", "fixedColor": color},
                          custom={"fillOpacity": 70, "gradientMode": "hue", "lineWidth": 0,
                                  "axisBorderShow": False, "axisPlacement": "auto"}),
                 {"orientation": "horizontal", "xField": x_field, "barWidth": 0.7, "groupWidth": 0.7,
                  "showValue": "always", "stacking": "none", "barRadius": 0.1, "fullHighlight": False,
                  "xTickLabelRotation": 0, "xTickLabelSpacing": 0, "legend": {"showLegend": False},
                  "tooltip": {"mode": "single", "sort": "none"}},
                 transformations=[
                     {"id": "reduce", "options": {"reducers": ["lastNotNull"], "mode": "seriesToRows",
                                                  "labelsToFields": True}},
                     {"id": "organize", "options": {"excludeByName": {"Field": True},
                                                    "renameByName": {**rename, "Last *": "Count"}}},
                     {"id": "sortBy", "options": {"sort": [{"field": "Count", "desc": True}]}}])


def table(title, targets, transformations=None, overrides=None, desc="", sort=None, ds=PROM, footer=False):
    return panel("table", title, targets, desc, ds,
                 {**defaults(color={"mode": "thresholds"}),
                  "custom": {"align": "auto", "cellOptions": {"type": "auto"}, "filterable": True,
                             "inspect": False}},
                 {"showHeader": True, "cellHeight": "sm", "sortBy": sort or [],
                  "footer": {"show": footer, "reducer": ["sum"], "countRows": False, "fields": ""}},
                 overrides, transformations=transformations or [])


def col(name, unit=None, cell=None, thresholds=None, width=None, decimals=None, mx=None, mappings=None, color=None):
    props = []
    if unit:
        props.append({"id": "unit", "value": unit})
    if cell:
        props.append({"id": "custom.cellOptions", "value": cell})
    if thresholds:
        props += [{"id": "thresholds", "value": thresholds}, {"id": "color", "value": {"mode": "thresholds"}}]
    if color:
        props.append({"id": "color", "value": color})
    if width:
        props.append({"id": "custom.width", "value": width})
    if decimals is not None:
        props.append({"id": "decimals", "value": decimals})
    if mx is not None:
        props += [{"id": "max", "value": mx}, {"id": "min", "value": 0}]
    if mappings:
        props.append({"id": "mappings", "value": mappings})
    return {"matcher": {"id": "byName", "options": name}, "properties": props}


def series_color(name, color, regex=False, dashed=False, fill=None, width=None):
    props = [{"id": "color", "value": {"mode": "fixed", "fixedColor": color}}]
    if dashed:
        props.append({"id": "custom.lineStyle", "value": {"fill": "dash", "dash": [8, 6]}})
    if fill is not None:
        props.append({"id": "custom.fillOpacity", "value": fill})
    if width is not None:
        props.append({"id": "custom.lineWidth", "value": width})
    return {"matcher": {"id": "byRegexp" if regex else "byName", "options": name}, "properties": props}


def right_axis(regex, unit, dashed=False):
    props = [{"id": "unit", "value": unit}, {"id": "custom.axisPlacement", "value": "right"}]
    if dashed:
        props.append({"id": "custom.lineStyle", "value": {"fill": "dash", "dash": [6, 4]}})
    return {"matcher": {"id": "byRegexp", "options": regex}, "properties": props}


STATUS_COLORS = [series_color("2..|2xx", GOOD, regex=True), series_color("3..|3xx", INFO, regex=True),
                 series_color("4..|4xx", WARN, regex=True), series_color("5..|5xx", BAD, regex=True)]
GAUGE_BAR = {"type": "gauge", "mode": "gradient", "valueDisplayMode": "text"}
COLOR_BG = {"type": "color-background", "mode": "gradient"}
COLOR_TXT = {"type": "color-text"}
VALUE_MAP_UP = [{"type": "value", "options": {"0": {"text": "DOWN", "color": BAD},
                                              "1": {"text": "UP", "color": GOOD}}}]
OK_MAP = lambda ok, bad: [{"type": "value", "options": {"0": {"text": bad, "color": BAD},  # noqa: E731
                                                         "1": {"text": ok, "color": GOOD}}}]


def logs(title, targets, desc=""):
    return {"type": "logs", "title": title, "description": desc, "datasource": LOKI, "targets": targets,
            "options": {"showTime": True, "showLabels": False, "showCommonLabels": False, "wrapLogMessage": True,
                        "prettifyLogMessage": False, "enableLogDetails": True, "dedupStrategy": "none",
                        "sortOrder": "Descending", "enableInfiniteScrolling": True, "syntaxHighlighting": True}}


def alertlist(title="Alerts", label_filter=""):
    return {"type": "alertlist", "title": title,
            "description": "Firing and pending Grafana alerts, newest first.",
            "options": {"viewMode": "list", "groupMode": "default", "groupBy": [], "maxItems": 20,
                        "sortOrder": 3, "dashboardAlerts": False, "alertName": "",
                        "alertInstanceLabelFilter": label_filter,
                        "stateFilter": {"firing": True, "pending": True, "noData": True, "normal": False,
                                        "error": True},
                        "showInactiveAlerts": False}}


def state_timeline(title, targets, mappings=None, desc="", thresholds=None, show_value="never", row_height=0.8):
    return panel("state-timeline", title, targets, desc, PROM,
                 defaults(thresholds=thresholds, color={"mode": "thresholds"}, mappings=mappings,
                          custom={"fillOpacity": 80, "lineWidth": 0}),
                 {"mergeValues": True, "showValue": show_value, "alignValue": "left", "rowHeight": row_height,
                  "legend": {"showLegend": False}, "tooltip": {"mode": "single", "sort": "none"}})


def heatmap(title, targets, unit, desc="", scheme="Plasma", ds=PROM):
    """One row per series. Series must be plain time series, not histogram buckets."""
    return panel("heatmap", title, targets, desc, ds, {"custom": {"hideFrom": {"legend": False, "tooltip": False,
                                                                               "viz": False},
                                                                  "scaleDistribution": {"type": "linear"}}},
                 {"calculate": False, "cellGap": 2, "cellRadius": 2, "cellValues": {"unit": unit, "decimals": 0},
                  "color": {"mode": "scheme", "scheme": scheme, "fill": ACCENT, "scale": "exponential",
                            "exponent": 0.5, "steps": 64, "reverse": False},
                  "filterValues": {"le": 1e-9}, "legend": {"show": True},
                  "rowsFrame": {"layout": "auto"}, "showValue": "never",
                  "tooltip": {"mode": "single", "yHistogram": False, "showColorScale": True},
                  "yAxis": {"axisPlacement": "left", "reverse": False, "unit": "", "axisWidth": 150},
                  "exemplars": {"color": "rgba(255,0,255,0.7)"}},
                 transformations=[{"id": "joinByField", "options": {"byField": "Time", "mode": "outer"}}])


def echarts(title, targets, code, desc="", ds=PROM, **extra):
    return {"type": ECHARTS, "title": title, "description": desc, "datasource": ds, "targets": targets,
            "options": {"renderer": "canvas", "editorMode": "code", "getOption": code.strip() + "\n",
                        "map": "none", "editor": {"format": "auto"},
                        "themeEditor": {"name": "default", "config": "{}"},
                        "visualEditor": {"dataset": [], "series": [], "code": ""}}, **extra}


def text(content, transparent=True):
    return {"type": "text", "title": "", "transparent": transparent,
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


# ---------------------------------------------------------------- banners and ECharts code
def banner(title, subtitle, links, tint=("#111827", "#1e1b4b", "#312e81", "#0e7490"), link_color="#c7d2fe"):
    pills = "".join(
        f'<a href="{u}" style="color:{link_color};text-decoration:none;padding:3px 10px;border-radius:999px;'
        f'background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.12);white-space:nowrap">{t}</a>'
        for t, u in links)
    return text(f"""
<div style="display:flex;align-items:center;justify-content:space-between;gap:16px;padding:8px 20px;height:100%;
  box-sizing:border-box;border-radius:12px;color:#e5e7eb;font-family:Inter,system-ui,sans-serif;
  background:linear-gradient(115deg,{tint[0]} 0%,{tint[1]} 40%,{tint[2]} 75%,{tint[3]} 100%)">
  <div style="min-width:0">
    <div style="font-size:22px;font-weight:650;letter-spacing:.2px">{title}</div>
    <div style="font-size:12.5px;opacity:.72;margin-top:2px">{subtitle}</div>
  </div>
  <div style="display:flex;flex-wrap:wrap;justify-content:flex-end;gap:6px;font-size:12px">{pills}</div>
</div>""")


JS_HELPERS = """
const t = context.grafana.theme;
const series = context.panel.data.series;
const num = (s) => s.fields.find((f) => f.type === 'number');
const last = (ref) => {
  const s = series.find((x) => x.refId === ref);
  const f = s && num(s);
  return f && f.values.length ? f.values[f.values.length - 1] : null;
};
"""


def punchcard_js(unit_label):
    """Days x hours heatmap of the summed series. Each point must cover the hour before it."""
    return JS_HELPERS + f"""
const cells = {{}};
const now = new Date();
const days = [];
for (let i = 6; i >= 0; i--) {{
  days.push(new Date(now.getFullYear(), now.getMonth(), now.getDate() - i).toDateString());
}}
series.forEach((s) => {{
  const tf = s.fields.find((f) => f.type === 'time');
  const vf = num(s);
  if (!tf || !vf) return;
  tf.values.forEach((ts, i) => {{
    const d = new Date(ts - 1);
    const k = d.toDateString() + '|' + d.getHours();
    cells[k] = (cells[k] || 0) + (vf.values[i] || 0);
  }});
}});
const data = [];
let max = 1;
days.forEach((day, y) => {{
  for (let h = 0; h < 24; h++) {{
    const v = Math.round(cells[day + '|' + h] || 0);
    max = Math.max(max, v);
    data.push([h, y, v]);
  }}
}});
const hours = Array.from({{ length: 24 }}, (_, h) => String(h).padStart(2, '0'));
return {{
  backgroundColor: 'transparent',
  textStyle: {{ fontFamily: t.typography.fontFamily }},
  tooltip: {{
    position: 'top',
    formatter: (p) => {{
      const [h, y, v] = p.value;
      return days[y].slice(0, 10) + ', ' + hours[h] + ':00  ' + v.toLocaleString() + ' {unit_label}';
    }},
  }},
  grid: {{ left: 82, right: 12, top: 6, bottom: 48 }},
  xAxis: {{ type: 'category', data: hours, axisLine: {{ show: false }}, axisTick: {{ show: false }},
    axisLabel: {{ color: t.colors.text.secondary }} }},
  yAxis: {{ type: 'category', data: days.map((d) => d.slice(0, 10)), axisLine: {{ show: false }},
    axisTick: {{ show: false }}, axisLabel: {{ color: t.colors.text.secondary }} }},
  visualMap: {{ min: 0, max: max, orient: 'horizontal', left: 'center', bottom: 0, itemHeight: 160,
    itemWidth: 10, textStyle: {{ color: t.colors.text.secondary }}, inRange: {{ color: {json.dumps(HEAT)} }} }},
  series: [{{ type: 'heatmap', data: data,
    itemStyle: {{ borderRadius: 4, borderColor: t.colors.background.primary, borderWidth: 2 }},
    emphasis: {{ itemStyle: {{ shadowBlur: 10, shadowColor: 'rgba(0,0,0,0.45)' }} }} }}],
}};
"""


POWER_GAUGE_JS = JS_HELPERS + f"""
const w = last('A') || 0;
const eur = last('B') || 0;
const max = Math.max(150, Math.ceil((w * 1.6) / 50) * 50);
const grad = w < 150 ? '{TEAL}' : w < 250 ? '{WARN}' : '{BAD}';
return {{
  backgroundColor: 'transparent',
  textStyle: {{ fontFamily: t.typography.fontFamily }},
  series: [{{
    type: 'gauge', startAngle: 215, endAngle: -35, min: 0, max: max, splitNumber: 5,
    radius: '95%', center: ['50%', '58%'],
    progress: {{ show: true, roundCap: true, width: 14, itemStyle: {{ color: grad }} }},
    axisLine: {{ roundCap: true, lineStyle: {{ width: 14, color: [ [1, 'rgba(142,154,175,0.16)'] ] }} }},
    pointer: {{ show: false }},
    axisTick: {{ show: false }},
    splitLine: {{ length: 6, distance: 4, lineStyle: {{ width: 1, color: t.colors.border.medium }} }},
    axisLabel: {{ distance: 14, color: t.colors.text.secondary, fontSize: 10 }},
    anchor: {{ show: false }},
    title: {{ offsetCenter: [0, '36%'], color: t.colors.text.secondary, fontSize: 12 }},
    detail: {{ valueAnimation: true, offsetCenter: [0, '2%'], fontSize: 30, fontWeight: 600,
      color: t.colors.text.primary, formatter: (v) => Math.round(v) + ' W' }},
    data: [{{ value: w, name: '\\u20ac' + eur.toFixed(2) + ' per month' }}],
  }}],
}};
"""


SANKEY_JS = JS_HELPERS + f"""
const colors = {{ '2xx': '{GOOD}', '3xx': '{INFO}', '4xx': '{WARN}', '5xx': '{BAD}' }};
const totals = {{}};
const rows = [];
series.forEach((s) => {{
  const f = num(s);
  if (!f || !f.labels) return;
  const svc = (f.labels.service || '?').replace(/@.*$/, '');
  const cls = f.labels.class;
  const v = f.values[f.values.length - 1] || 0;
  if (!cls || v < 1) return;
  totals[svc] = (totals[svc] || 0) + v;
  rows.push([svc, cls, v]);
}});
const top = Object.keys(totals).sort((a, b) => totals[b] - totals[a]).slice(0, 14);
const links = [];
const agg = {{}};
rows.forEach(([svc, cls, v]) => {{
  const src = top.includes(svc) ? svc : 'other';
  const k = src + '|' + cls;
  agg[k] = (agg[k] || 0) + v;
}});
Object.keys(agg).forEach((k) => {{
  const [src, cls] = k.split('|');
  links.push({{ source: src, target: cls, value: Math.round(agg[k]) }});
}});
const names = new Set();
links.forEach((l) => {{ names.add(l.source); names.add(l.target); }});
const palette = {json.dumps([ACCENT, TEAL, INFO, PINK, "#7c8cf8", "#22d3ee", "#a3e635", "#fb7185", "#c084fc", "#fbbf24"])};
let i = 0;
const nodes = Array.from(names).map((n) => ({{
  name: n,
  itemStyle: {{ color: colors[n] || palette[i++ % palette.length], borderWidth: 0 }},
  label: colors[n] ? {{ position: 'left', fontWeight: 600 }} : undefined,
}}));
return {{
  backgroundColor: 'transparent',
  textStyle: {{ fontFamily: t.typography.fontFamily }},
  tooltip: {{ trigger: 'item', valueFormatter: (v) => v.toLocaleString() + ' requests' }},
  series: [{{
    type: 'sankey', left: 8, right: 8, top: 8, bottom: 8, nodeWidth: 12, nodeGap: 9, draggable: false,
    emphasis: {{ focus: 'adjacency' }},
    label: {{ color: t.colors.text.primary, fontSize: 11 }},
    lineStyle: {{ color: 'gradient', opacity: 0.35, curveness: 0.5 }},
    data: nodes, links: links,
  }}],
}};
"""


# ---------------------------------------------------------------- shared queries
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
CLASS = 'label_replace({0}, "class", "${{1}}xx", "code", "(.)..")'
LOAD_PER_CORE = 'node_load5 / on (instance) group_left count by (instance) (node_cpu_seconds_total{mode="idle"})'
BACKUP_RSS = 'nomad_client_allocs_memory_rss{parent_id=~".+-backup"}'
BACKUP_STALE = (f'count(count by (parent_id) (count_over_time({BACKUP_RSS}[7d])) '
                f'unless count by (parent_id) (count_over_time({BACKUP_RSS}[26h])) '
                'and on (parent_id) label_replace(max by (exported_job) (nomad_nomad_job_summary_running), '
                '"parent_id", "$1", "exported_job", "(.+)")) or vector(0)')
PKG_W = 'sum by (node) (rate(node_rapl_package_joules_total[5m]))'
DRAM_W = 'sum by (node) (rate(node_rapl_dram_joules_total[5m]))'
WALL_W = (f'(sum({PKG_W}) + sum({DRAM_W}) + count(node_uname_info) * $node_overhead_w + $nas_w)')
WALL_W_DEFAULT = WALL_W.replace("$node_overhead_w", "12").replace("$nas_w", "35")

DASH_LINKS = [("Nodes", "/d/homelab-nodes"), ("Nomad", "/d/homelab-nomad-cluster"),
              ("Workloads", "/d/homelab-nomad-workloads"), ("Traefik", "/d/homelab-traefik"),
              ("Power", "/d/homelab-power"), ("Authentik", "/d/homelab-authentik"),
              ("Security", "/d/homelab-security-overview"), ("Logs", "/d/homelab-logs"),
              ("Host logs", "/a/grafana-lokiexplore-app/explore"), ("Monitoring", "/d/homelab-monitoring-stack"),
              ("Alerts", "/alerting/list")]


# ---------------------------------------------------------------- homelab map (canvas)
def _el(kind, name, place, config=None, bg=None, border=None, connections=None):
    e = {"type": kind, "name": name, "constraint": {"horizontal": "scale", "vertical": "scale"},
         "placement": {"left": place[0], "top": place[1], "right": 100 - place[0] - place[2],
                       "bottom": 100 - place[1] - place[3]},
         "config": config or {}, "background": bg or {"color": {"fixed": CLEAR}},
         "border": border or {"color": {"fixed": CLEAR}, "width": 0}}
    if connections:
        e["connections"] = connections
    return e


def _txt(name, place, value, size=12, color="#9ca3af", field=False, align="left", weight_field=None):
    cfg = {"text": {"mode": "field", "field": value, "fixed": ""} if field else {"mode": "fixed", "fixed": value},
           "color": {"field": weight_field, "fixed": color} if weight_field else {"fixed": color},
           "size": size, "align": align, "valign": "middle"}
    return _el("metric-value" if field else "text", name, place, cfg)


def _card(key, title, subtitle, x, y, w, h, status_field, metrics, links_to=()):
    tint = NODE_COLORS.get(key, ACCENT)
    conns = [{"source": {"x": 0, "y": -1}, "target": {"x": 0, "y": 1}, "targetName": t, "path": "straight",
              "color": {"fixed": "rgba(142,154,175,0.45)"}, "size": {"fixed": 2, "min": 1, "max": 4},
              "direction": "forward"} for t in links_to]
    els = [_el("rectangle", f"{key}-card", (x, y, w, h), {"text": {"mode": "fixed", "fixed": ""}},
               bg={"color": {"fixed": "rgba(31,41,55,0.55)"}},
               border={"color": {"field": status_field, "fixed": tint} if status_field else {"fixed": tint},
                       "width": 2, "radius": 12}, connections=conns),
           _txt(f"{key}-title", (x + 2, y + 3, w * 0.6, 14), title, 17, "#f3f4f6"),
           _txt(f"{key}-sub", (x + 2, y + 16, w * 0.9, 10), subtitle, 11, "#9ca3af")]
    if status_field:
        els.append(_txt(f"{key}-status", (x + w * 0.62, y + 3, w * 0.34, 14), status_field, 13, GOOD, True,
                        "right", status_field))
    mw = (w - 4) / len(metrics)
    for i, (label, field) in enumerate(metrics):
        mx = x + 2 + i * mw
        els.append(_txt(f"{key}-{label}-v", (mx, y + h - 26, mw, 14), field, 20, "#f3f4f6", True, "left", field))
        els.append(_txt(f"{key}-{label}-l", (mx, y + h - 12, mw, 9), label, 10, "#9ca3af"))
    return els


def homelab_map():
    ips = {"odin": "192.168.1.100", "thor": "192.168.1.101", "loki": "192.168.1.102"}
    elements = _card("traefik", "Traefik ingress", "keepalived VIP, TLS via Let's Encrypt", 31, 2, 38, 30, None,
                     [("req/s", "req/s"), ("5xx", "5xx"), ("p95", "p95")])
    for i, n in enumerate(ips):
        elements += _card(n, n, f"{ips[n]}  Nomad + Consul", 2 + i * 33, 38, 30, 34, f"{n} up",
                          [("cpu", f"{n} cpu"), ("mem", f"{n} mem"), ("temp", f"{n} temp")],
                          links_to=["traefik-card"])
    elements += _card("nas", "TrueNAS", "NFS /storage for every job and backup", 31, 78, 38, 20, None,
                      [("used", "nas used"), ("nfs ops/s", "nfs ops")])
    by_name = {e["name"]: e for e in elements}
    for n in ips:
        by_name[f"{n}-card"].setdefault("connections", []).append(
            {"source": {"x": 0, "y": 1}, "target": {"x": 0, "y": -1}, "targetName": "nas-card",
             "path": "straight", "color": {"fixed": "rgba(142,154,175,0.25)"},
             "size": {"fixed": 1, "min": 1, "max": 4}, "direction": "none"})
    targets = [
        prom('up{job="node-exporters"}', "{{node}} up", "A", instant=True),
        prom(CPU_PCT.replace("$__rate_interval", "2m"), "{{node}} cpu", "B", instant=True),
        prom(MEM_PCT, "{{node}} mem", "C", instant=True),
        prom('max by (node) (node_hwmon_temp_celsius)', "{{node}} temp", "D", instant=True),
        prom('sum(rate(traefik_service_requests_total[5m]))', "req/s", "E", instant=True),
        prom(f'{HTTP_5XX} or vector(0)', "5xx", "F", instant=True),
        prom('histogram_quantile(0.95, sum by (le) (rate(traefik_service_request_duration_seconds_bucket[5m])))',
             "p95", "G", instant=True),
        prom(f'max({STORAGE_PCT})', "nas used", "H", instant=True),
        prom('sum(rate(node_nfs_requests_total[5m]))', "nfs ops", "I", instant=True),
    ]
    ovr = [{"matcher": {"id": "byRegexp", "options": r}, "properties": p} for r, p in [
        (".* up", [{"id": "mappings", "value": VALUE_MAP_UP}, {"id": "thresholds", "value": thr((None, BAD), (1, GOOD))},
                   {"id": "color", "value": {"mode": "thresholds"}}]),
        (".* (cpu|mem)|nas used", [{"id": "unit", "value": "percent"}, {"id": "decimals", "value": 0},
                                   {"id": "thresholds", "value": thr((None, "#f3f4f6"), (70, WARN), (85, HIGH), (95, BAD))},
                                   {"id": "color", "value": {"mode": "thresholds"}}]),
        (".* temp", [{"id": "unit", "value": "celsius"}, {"id": "decimals", "value": 0},
                     {"id": "thresholds", "value": thr((None, "#f3f4f6"), (70, WARN), (85, BAD))},
                     {"id": "color", "value": {"mode": "thresholds"}}]),
        ("req/s", [{"id": "unit", "value": "reqps"}, {"id": "decimals", "value": 1}]),
        ("nfs ops", [{"id": "unit", "value": "short"}, {"id": "decimals", "value": 0}]),
        ("5xx", [{"id": "unit", "value": "percent"}, {"id": "decimals", "value": 1},
                 {"id": "thresholds", "value": thr((None, "#f3f4f6"), (1, WARN), (5, BAD))},
                 {"id": "color", "value": {"mode": "thresholds"}}]),
        ("p95", [{"id": "unit", "value": "s"}, {"id": "decimals", "value": 2},
                 {"id": "thresholds", "value": thr((None, "#f3f4f6"), (0.5, WARN), (2, BAD))},
                 {"id": "color", "value": {"mode": "thresholds"}}]),
    ]]
    root = {"type": "frame", "name": "Element root", "elements": elements,
            "background": {"color": {"fixed": CLEAR}}, "border": {"color": {"fixed": CLEAR}},
            "constraint": {"horizontal": "left", "vertical": "top"}, "placement": {}}
    return panel("canvas", "Homelab map", targets,
                 "Live state of the three Nomad nodes, ingress and the NAS. Card borders turn red when a node is down.",
                 PROM, {**defaults(color={"mode": "thresholds"}, thresholds=FIXED("#f3f4f6"))},
                 {"inlineEditing": False, "showAdvancedTypes": True, "panZoom": False, "infinitePan": False,
                  "root": root}, ovr)


# ---------------------------------------------------------------- command center (master)
def command_center():
    d = Dash("homelab-command-center", "Homelab Command Center", ["homelab"],
             "Master dashboard: every signal from the homelab on one screen. Drill into the linked dashboards for detail.",
             time_from="now-6h")
    d.add(banner("Homelab Command Center",
                 "odin &middot; thor &middot; loki &mdash; Nomad + Consul, TrueNAS storage, Traefik ingress, Authentik SSO",
                 DASH_LINKS), 24, 3)

    healthy = ('(count(up{job="node-exporters"} == 1) >= bool 3) * (count(up{job="nomad_metrics"} == 1) >= bool 3) '
               '* ((count(up == 0) or vector(0)) == bool 0)')
    d.add(health("Cluster health", [prom(healthy)], thr((None, BAD), (1, GOOD)),
                 "Healthy when all node exporters and Nomad agents are up and no scrape target is down.",
                 OK_MAP("HEALTHY", "DEGRADED")), 3, 4)
    d.add(health("Nodes up", [prom('count(up{job="node-exporters"} == 1) or vector(0)')],
                 thr((None, BAD), (2, HIGH), (3, GOOD)), "node-exporter targets answering, out of 3.",
                 unit="suffix: / 3"), 3, 4)
    d.add(stat("Jobs running", [prom('max(nomad_nomad_job_status_running)')], thresholds=FIXED(INFO),
               desc="Nomad jobs in the running state (reported by the leader)."), 3, 4)
    d.add(health("Targets down", [prom('count(up == 0) or vector(0)')], ZERO_GOOD,
                 "Prometheus scrape targets that are not answering.", decimals=0), 3, 4)
    d.add(stat("Security events 24h", [prom('sum(increase(falcosecurity_falco_rules_matches_total[24h])) or vector(0)')],
               "short", thr((None, GOOD), (50, WARN), (500, HIGH)), graph=False, decimals=0,
               desc="Falco rule matches across all nodes in the last 24 hours. Open Security for the breakdown."), 3, 4)
    d.add(health("Backups", [prom(BACKUP_STALE)], ZERO_GOOD,
                 "Backup jobs that ran this week but not in the last 26 hours (same check as the backup-stale alert).",
                 [{"type": "value", "options": {"0": {"text": "ALL FRESH", "color": GOOD}}}], decimals=0), 3, 4)
    d.add(stat("Power", [prom(WALL_W_DEFAULT)], "watt", thr((None, TEAL), (150, WARN), (250, HIGH)), decimals=0,
               desc="Estimated wall power: RAPL CPU + DRAM, plus 12 W per node and 35 W for the NAS."), 3, 4)
    d.add(stat("NAS used", [prom(f'max({STORAGE_PCT})')], "percent", PCT_THR, decimals=1,
               desc="TrueNAS /storage NFS share."), 3, 4)

    d.add(stat("Requests/s", [prom('sum(rate(traefik_service_requests_total[$__rate_interval]))')], "reqps",
               FIXED(INFO), decimals=2, desc="All Traefik services."), 3, 3, newrow=True)
    d.add(stat("HTTP 5xx", [prom(f'{HTTP_5XX} or vector(0)')], "percent", thr((None, GOOD), (1, WARN), (5, BAD)),
               decimals=2), 3, 3)
    d.add(stat("Cert expiry", [prom('min(traefik_tls_certs_not_after - time())')], "dtdurations",
               thr((None, BAD), (7 * 86400, HIGH), (14 * 86400, GOOD)), graph=False,
               desc="Soonest TLS certificate expiry. Let's Encrypt renews at 30 days."), 3, 3)
    d.add(stat("SSO outposts", [prom('sum(authentik_outposts_connected)')], thresholds=thr((None, BAD), (1, GOOD)),
               graph=False, mappings=[{"type": "value", "options": {"0": {"text": "DISCONNECTED"}}}],
               desc="Authentik outposts connected. 0 breaks forward-auth."), 3, 3)
    d.add(stat("OOM kills 24h", [prom('sum(increase(node_vmstat_oom_kill[24h]))')], "short",
               thr((None, GOOD), (1, HIGH), (10, BAD)), graph=False, decimals=0,
               desc="Kernel OOM kills across all nodes in the last 24h."), 3, 3)
    d.add(stat("Restarts 24h", [prom('sum(increase(nomad_client_allocs_restart[24h])) or vector(0)')], "short",
               thr((None, GOOD), (1, WARN), (10, HIGH)), graph=False, decimals=0,
               desc="Nomad task restarts in the last 24h."), 3, 3)
    d.add(stat("Error log lines 1h", [loki(f'sum(count_over_time({{node=~".+"}} |~ "{ERR_RE}" [1h]))')], "short",
               thr((None, GOOD), (500, WARN), (5000, HIGH)), ds=LOKI, graph=False, decimals=0,
               desc="Log lines matching error, fatal, panic, oom or failed in the last hour."), 3, 3)
    d.add(stat("Min uptime", [prom('min(node_time_seconds - node_boot_time_seconds)')], "dtdurations",
               thr((None, HIGH), (3600, TEAL)), graph=False, desc="Most recently rebooted node."), 3, 3)

    d.add(homelab_map(), 16, 12, newrow=True)
    d.add(alertlist("Firing and pending alerts"), 8, 12)

    d.row("Resources")
    for title, expr, unit, th, mx in (("CPU", CPU_PCT, "percent", PCT_THR, 100),
                                      ("Memory", MEM_PCT, "percent", PCT_THR, 100),
                                      ("Root disk", ROOT_PCT, "percent", PCT_THR, 100),
                                      ("Hottest sensor", 'max by (node) (node_hwmon_temp_celsius)', "celsius",
                                       TEMP_THR, 100)):
        d.add(bargauge(f"{title} by node", [prom(expr, "{{node}}", instant=True)], unit, th, mx=mx, decimals=0), 6, 5)
    d.add(timeseries("CPU", [prom(CPU_PCT, "{{node}}")], "percent", 0, 100, nodes=True, fill=12,
                     thresholds=thr((None, CLEAR), (90, BAD)), thresh_style="dashed"), 8, 8, newrow=True)
    d.add(timeseries("Memory", [prom(MEM_PCT, "{{node}}")], "percent", 0, 100, nodes=True, fill=12,
                     thresholds=thr((None, CLEAR), (90, BAD)), thresh_style="dashed"), 8, 8)
    d.add(timeseries("Load (5m) per core", [prom(LOAD_PER_CORE, "{{node}}")], "percentunit", nodes=True, fill=12,
                     thresholds=thr((None, CLEAR), (1, BAD)), thresh_style="dashed",
                     desc="Above 100% means more runnable work than cores."), 8, 8)

    d.row("Traffic & SSO")
    d.add(bars("Requests by status class", [prom(
        f'sum by (class) ({CLASS.format("rate(traefik_service_requests_total[$__rate_interval])")})', "{{class}}")],
        unit="reqps", overrides=STATUS_COLORS), 8, 8)
    d.add(topn("Busiest services", [prom(
        'topk(10, sum by (service) (rate(traefik_service_requests_total[5m])))', "{{service}}", instant=True)],
        "reqps", INFO, decimals=2, scheme="BlPu"), 8, 8)
    d.add(timeseries("p95 latency: Traefik vs Authentik", [
        prom('histogram_quantile(0.95, sum by (le) (rate(traefik_service_request_duration_seconds_bucket[$__rate_interval])))', "Traefik p95"),
        prom('max(authentik_main_request_duration_seconds{quantile="0.95"})', "Authentik p95", "B")],
        "s", fill=10, overrides=[series_color("Traefik p95", INFO), series_color("Authentik p95", ACCENT)]), 8, 8)

    d.row("Workloads")
    d.add(bargauge("Closest to memory_max", [prom(
        'topk(12, max by (exported_job, task) (nomad_client_allocs_memory_rss / (nomad_client_allocs_memory_max_allocated > 0)) * 100)',
        "{{exported_job}} · {{task}}", instant=True)], mx=100, decimals=0,
        desc="RSS as a share of each task's hard memory limit."), 8, 10)
    d.add(topn("Top memory (RSS)", [prom(
        'topk(12, max by (exported_job, task) (nomad_client_allocs_memory_rss))', "{{exported_job}} · {{task}}",
        instant=True)], "bytes", ACCENT, decimals=None, scheme="BlPu"), 8, 10)
    d.add(topn("Top CPU (MHz)", [prom(
        'topk(12, max by (exported_job, task) (rate(nomad_client_allocs_cpu_total_ticks[5m])))',
        "{{exported_job}} · {{task}}", instant=True)], "none", TEAL, scheme="GrYlRd"), 8, 10)
    d.add(timeseries("Memory reserved vs used per node", [
        prom('sum by (host) (nomad_client_allocated_memory) * 1048576', "{{host}} reserved"),
        prom('sum by (host) (nomad_client_allocs_memory_rss)', "{{host}}", "B")],
        "bytes", fill=10, overrides=[series_color(n, c) for n, c in NODE_COLORS.items()] +
        [series_color(".*reserved", SLATE, regex=True, dashed=True, fill=0, width=1)],
        desc="Solid: RSS in use. Dashed: memory reserved by allocations."), 12, 8, newrow=True)
    d.add(state_timeline("Periodic runs (backups, scans)", [prom(
        'count by (parent_id) (nomad_client_allocs_memory_rss{parent_id!=""})', "{{parent_id}}")],
        thresholds=FIXED(TEAL), desc="Bars show when each periodic job was running."), 12, 8)

    d.row("Storage & I/O", collapsed=True)
    d.add(bargauge("Filesystems", [prom(
        f'100 * (1 - node_filesystem_avail_bytes{{{FS_SEL}}} / node_filesystem_size_bytes{{{FS_SEL}}})',
        "{{node}} {{mountpoint}}", instant=True)], mx=100, decimals=0), 8, 8)
    d.add(timeseries("NAS free and 7 day projection", [
        prom('max(node_filesystem_avail_bytes{mountpoint="/storage"})', "free"),
        prom('max(predict_linear(node_filesystem_avail_bytes{mountpoint="/storage"}[7d], 7 * 86400))', "projected in 7d", "B")],
        "bytes", fill=20, overrides=[series_color("free", TEAL), series_color("projected in 7d", HIGH, dashed=True, fill=0)]), 8, 8)
    d.add(timeseries("NFS client ops by node", [prom(
        'sum by (node) (rate(node_nfs_requests_total[$__rate_interval]))', "{{node}}")], "ops", nodes=True), 8, 8)
    d.add(timeseries("Network (rx up, tx down)", [
        prom(f'sum by (node) (rate(node_network_receive_bytes_total{{{NET_DEV}}}[$__rate_interval]))', "{{node}} rx"),
        prom(f'-sum by (node) (rate(node_network_transmit_bytes_total{{{NET_DEV}}}[$__rate_interval]))', "{{node}} tx", "B")],
        "Bps", centered=True, fill=20), 8, 8)
    d.add(timeseries("Disk I/O (read up, write down)", [
        prom('sum by (node) (rate(node_disk_read_bytes_total{device!~"dm-.*|loop.*"}[$__rate_interval]))', "{{node}} read"),
        prom('-sum by (node) (rate(node_disk_written_bytes_total{device!~"dm-.*|loop.*"}[$__rate_interval]))', "{{node}} write", "B")],
        "Bps", centered=True, fill=20), 8, 8)
    d.add(timeseries("Pressure stall (memory / io)", [
        prom('rate(node_pressure_memory_waiting_seconds_total[$__rate_interval]) * 100', "{{node}} mem"),
        prom('rate(node_pressure_io_waiting_seconds_total[$__rate_interval]) * 100', "{{node}} io", "B")],
        "percent", fill=8,
        desc="Share of time tasks were stalled waiting on memory or disk. Rising memory stall precedes OOM kills."), 8, 8)

    d.row("Logs & scrape health", collapsed=True)
    d.add(bars("Log volume by source", [loki(
        'sum by (source) (count_over_time({node=~".+"} [$__auto]))', "{{source}}")], ds=LOKI, unit="short"), 8, 8)
    d.add(bars("Error lines by node", [loki(
        f'sum by (node) (count_over_time({{node=~".+"}} |~ "{ERR_RE}" [$__auto]))', "{{node}}")], ds=LOKI,
        unit="short", nodes=True), 8, 8)
    d.add(logs("Latest errors", [loki(f'{{node=~".+"}} |~ "{ERR_RE}"')]), 8, 8)
    d.add(state_timeline("Scrape targets", [prom('up', "{{job}} {{node}}")], mappings=VALUE_MAP_UP,
                         thresholds=thr((None, BAD), (1, GOOD))), 24, 10, newrow=True)
    return d


# ---------------------------------------------------------------- nodes
def nodes():
    v = [var_query("node", "label_values(node_uname_info, node)", "Node")]
    d = Dash("homelab-nodes", "Nodes", ["homelab", "infrastructure"],
             "Host metrics from node-exporter: a fleet summary, then one card per node.", variables=v)
    d.add(table("Fleet", [
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
        overrides=[col("Node", width=90), col("Uptime", "dtdurations", width=150), col("RAM", "bytes", width=90),
                   col("Cores", width=70),
                   col("CPU", "percent", cell=GAUGE_BAR, thresholds=PCT_THR, mx=100, decimals=1),
                   col("Memory", "percent", cell=GAUGE_BAR, thresholds=PCT_THR, mx=100, decimals=1),
                   col("Root disk", "percent", cell=GAUGE_BAR, thresholds=PCT_THR, mx=100, decimals=1),
                   col("Load 5m", decimals=2, width=80),
                   col("Max temp", "celsius", cell=COLOR_TXT, thresholds=TEMP_THR, width=90),
                   col("OOM kills 24h", cell=COLOR_BG, decimals=0, width=120,
                       thresholds=thr((None, CLEAR), (1, HIGH)))],
        desc="One line per node. Bars show CPU, memory and root disk against 100%."), 24, 6)

    d.row("$node", repeat="node")
    n = 'node="$node"'
    d.add(stat("CPU", [prom(f'100 * (1 - avg(rate(node_cpu_seconds_total{{{n},mode="idle"}}[$__rate_interval])))')],
               "percent", PCT_THR, decimals=1), 4, 4)
    d.add(stat("Memory", [prom(f'100 * (1 - node_memory_MemAvailable_bytes{{{n}}} / node_memory_MemTotal_bytes{{{n}}})')],
               "percent", PCT_THR, decimals=1), 4, 4)
    d.add(stat("Root disk", [prom(f'100 * (1 - node_filesystem_avail_bytes{{{n},mountpoint="/"}} / node_filesystem_size_bytes{{{n},mountpoint="/"}})')],
               "percent", PCT_THR, decimals=1), 4, 4)
    d.add(stat("Load per core", [prom(f'node_load5{{{n}}} / scalar(count(node_cpu_seconds_total{{{n},mode="idle"}}))')],
               "percentunit", thr((None, GOOD), (0.8, WARN), (1, BAD)), decimals=0,
               desc="5 minute load average divided by core count."), 4, 4)
    d.add(stat("Hottest sensor", [prom(f'max(node_hwmon_temp_celsius{{{n}}})')], "celsius", TEMP_THR, decimals=0), 4, 4)
    d.add(stat("Uptime", [prom(f'node_time_seconds{{{n}}} - node_boot_time_seconds{{{n}}}')], "dtdurations",
               thr((None, HIGH), (3600, TEAL)), graph=False), 4, 4)
    d.add(timeseries("CPU by mode", [prom(
        f'sum by (mode) (rate(node_cpu_seconds_total{{{n},mode!="idle"}}[$__rate_interval])) / scalar(count(node_cpu_seconds_total{{{n},mode="idle"}})) * 100', "{{mode}}")],
        "percent", 0, 100, stack=True, fill=35, legend_place="right", legend_calcs=("mean", "max")), 8, 8)
    d.add(timeseries("Memory", [
        prom(f'node_memory_MemTotal_bytes{{{n}}} - node_memory_MemAvailable_bytes{{{n}}}', "used"),
        prom(f'node_memory_Buffers_bytes{{{n}}} + node_memory_Cached_bytes{{{n}}}', "buffers + cache", "B"),
        prom(f'node_memory_SwapTotal_bytes{{{n}}} - node_memory_SwapFree_bytes{{{n}}}', "swap used", "D"),
        prom(f'node_memory_MemTotal_bytes{{{n}}}', "total", "E")],
        "bytes", fill=20, overrides=[series_color("total", SLATE, dashed=True, fill=0, width=1),
                                     series_color("used", ACCENT), series_color("buffers + cache", INFO),
                                     series_color("swap used", BAD)]), 8, 8)
    d.add(timeseries("Load average", [
        prom(f'node_load1{{{n}}}', "1m"), prom(f'node_load5{{{n}}}', "5m", "B"), prom(f'node_load15{{{n}}}', "15m", "C"),
        prom(f'count(node_cpu_seconds_total{{{n},mode="idle"}})', "cores", "D")],
        overrides=[series_color("cores", BAD, dashed=True, fill=0, width=1), series_color("1m", "#c4b5fd"),
                   series_color("5m", ACCENT), series_color("15m", "#4c3fa8")], fill=0,
        desc="The dashed line is the core count."), 8, 8)
    d.add(timeseries("Disk throughput (read up, write down)", [
        prom(f'sum by (device) (rate(node_disk_read_bytes_total{{{n},device!~"dm-.*|loop.*"}}[$__rate_interval]))', "{{device}} read"),
        prom(f'-sum by (device) (rate(node_disk_written_bytes_total{{{n},device!~"dm-.*|loop.*"}}[$__rate_interval]))', "{{device}} write", "B")],
        "Bps", centered=True), 8, 8)
    d.add(timeseries("Disk busy", [prom(
        f'rate(node_disk_io_time_seconds_total{{{n},device!~"dm-.*|loop.*"}}[$__rate_interval]) * 100', "{{device}}")],
        "percent", 0, 100, fill=10), 8, 8)
    d.add(timeseries("Network (rx up, tx down)", [
        prom(f'rate(node_network_receive_bytes_total{{{n},{NET_DEV}}}[$__rate_interval])', "{{device}} rx"),
        prom(f'-rate(node_network_transmit_bytes_total{{{n},{NET_DEV}}}[$__rate_interval])', "{{device}} tx", "B")],
        "Bps", centered=True), 8, 8)
    d.add(bargauge("Filesystems", [prom(
        f'100 * (1 - node_filesystem_avail_bytes{{{n},fstype!~"tmpfs|ramfs|overlay|squashfs|nsfs|autofs"}} / node_filesystem_size_bytes{{{n},fstype!~"tmpfs|ramfs|overlay|squashfs|nsfs|autofs"}})',
        "{{mountpoint}}", instant=True)], mx=100, decimals=0), 8, 8)
    d.add(timeseries("Pressure stall (PSI)", [
        prom(f'rate(node_pressure_cpu_waiting_seconds_total{{{n}}}[$__rate_interval]) * 100', "cpu waiting"),
        prom(f'rate(node_pressure_memory_waiting_seconds_total{{{n}}}[$__rate_interval]) * 100', "memory waiting", "B"),
        prom(f'rate(node_pressure_io_waiting_seconds_total{{{n}}}[$__rate_interval]) * 100', "io waiting", "C"),
        prom(f'rate(node_pressure_memory_stalled_seconds_total{{{n}}}[$__rate_interval]) * 100', "memory stalled", "D")],
        "percent", fill=0, desc="Share of time tasks waited on a resource.",
        overrides=[series_color("cpu waiting", INFO), series_color("memory waiting", ACCENT),
                   series_color("io waiting", WARN), series_color("memory stalled", BAD)]), 8, 8)
    d.add(timeseries("Temperatures", [prom(
        f'max by (chip) (node_hwmon_temp_celsius{{{n}}})', "{{chip}}")], "celsius", fill=0,
        thresholds=thr((None, CLEAR), (85, BAD)), thresh_style="dashed"), 8, 8)
    return d


# ---------------------------------------------------------------- nomad cluster
def nomad_cluster():
    d = Dash("homelab-nomad-cluster", "Nomad Cluster", ["homelab", "nomad"],
             "Nomad servers, scheduler and per-job allocation state.")
    d.add(health("Nomad agents up", [prom('count(up{job="nomad_metrics"} == 1) or vector(0)')],
                 thr((None, BAD), (2, HIGH), (3, GOOD)), unit="suffix: / 3"), 4, 4)
    d.add(health("Raft peers", [prom('max(last_over_time(nomad_raft_peers[1d]))')],
                 thr((None, BAD), (2, HIGH), (3, GOOD)),
                 "Servers in the raft quorum. Nomad only emits this gauge occasionally, so it shows the last value."), 4, 4)
    d.add(stat("Leader", [prom('max by (host) (nomad_nomad_job_status_running)', "{{host}}", instant=True)],
               text_mode="name", thresholds=FIXED(ACCENT), graph=False,
               desc="Job summary metrics come only from the leader, so the reporting host is the leader."), 4, 4)
    d.add(stat("Jobs running", [prom('max(nomad_nomad_job_status_running)')], thresholds=FIXED(INFO)), 4, 4)
    d.add(health("Jobs pending", [prom('max(nomad_nomad_job_status_pending)')], thr((None, GOOD), (1, HIGH)),
                 graph=True), 4, 4)
    d.add(health("Blocked evals", [prom('max(nomad_nomad_blocked_evals_total_blocked)')], ZERO_GOOD,
                 "Evaluations that could not be placed, usually for lack of CPU or memory."), 4, 4)

    cap = '(sum by (host) (nomad_client_allocated_memory) + sum by (host) (nomad_client_unallocated_memory))'
    d.add(bargauge("Memory reserved per node", [prom(
        f'sum by (host) (nomad_client_allocated_memory) / {cap} * 100', "{{host}}", instant=True)], mx=100,
        decimals=0), 6, 6, newrow=True)
    d.add(bargauge("CPU reserved per node", [prom(
        'sum by (host) (nomad_client_allocated_cpu) / (sum by (host) (nomad_client_allocated_cpu) + sum by (host) (nomad_client_unallocated_cpu)) * 100',
        "{{host}}", instant=True)], mx=100, decimals=0), 6, 6)
    d.add(bargauge("memory_max vs capacity per node", [prom(
        f'sum by (host) (nomad_client_allocated_max_memory) / {cap} * 100', "{{host}}", instant=True)],
        thresholds=thr((None, GOOD), (100, WARN), (150, BAD)), mx=200, decimals=0,
        desc="Sum of memory_max against capacity. Over 100% is allowed by oversubscription but tasks can't all burst at once."),
        6, 6)
    d.add(donut("Allocations per node", [prom(
        'count by (host) (count by (alloc_id, host) (nomad_client_allocs_memory_rss))', "{{host}}", instant=True)],
        overrides=[series_color(n, c) for n, c in NODE_COLORS.items()],
        desc="Running allocations on each node. The scheduler spreads, so these should be close."), 6, 6)

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
        overrides=[col("Running", cell=COLOR_BG, thresholds=thr((None, BAD), (1, CLEAR))),
                   col("Queued", cell=COLOR_BG, thresholds=thr((None, CLEAR), (1, HIGH))),
                   col("Failed (24h)", cell=COLOR_BG, decimals=0, thresholds=thr((None, CLEAR), (1, BAD))),
                   col("Failed (all time)", cell=COLOR_TXT, thresholds=thr((None, SLATE), (1, WARN))),
                   col("Lost", cell=COLOR_BG, thresholds=thr((None, CLEAR), (1, HIGH)))],
        sort=[{"displayName": "Failed (24h)", "desc": True}],
        desc="Service and system jobs. Batch jobs that finished show Running 0, which is fine."), 24, 12, newrow=True)

    d.add(state_timeline("Periodic job runs (backups, scans)", [prom(
        'count by (parent_id) (nomad_client_allocs_memory_rss{parent_id!=""})', "{{parent_id}}")],
        thresholds=FIXED(TEAL), desc="When each periodic job had an allocation running."), 24, 10, newrow=True)
    d.add(timeseries("Raft last contact p99", [prom('max by (host) (nomad_raft_leader_lastContact{quantile="0.99"})', "{{host}}")],
                     "ms", fill=8, overrides=[series_color(n, c) for n, c in NODE_COLORS.items()]), 12, 8, newrow=True)
    d.add(timeseries("Allocation failures (cumulative)", [prom(
        'sum(max by (exported_job, task_group) (nomad_nomad_job_summary_failed))', "failed allocations")],
        fill=10, desc="Steps up whenever an allocation fails.", overrides=[series_color("failed allocations", HIGH)]),
        12, 8)
    return d


# ---------------------------------------------------------------- nomad workloads
def nomad_workloads():
    v = [var_query("job", 'label_values(nomad_client_allocs_memory_rss{parent_id=""}, exported_job)', "Job"),
         var_query("task", 'label_values(nomad_client_allocs_memory_rss{exported_job=~"$job"}, task)', "Task")]
    d = Dash("homelab-nomad-workloads", "Nomad Workloads", ["homelab", "nomad"],
             "Per-task CPU and memory against reservations and limits, restarts and OOM kills.", variables=v)
    sel = 'exported_job=~"$job",task=~"$task"'
    by = "max by (exported_job, task, host)"
    d.add(stat("Tasks", [prom(f'count(count by (exported_job, task) (nomad_client_allocs_memory_rss{{{sel}}}))')],
               thresholds=FIXED(INFO)), 4, 4)
    d.add(stat("RSS in use", [prom(f'sum(nomad_client_allocs_memory_rss{{{sel}}})')], "bytes", FIXED(ACCENT)), 4, 4)
    d.add(stat("Memory reserved", [prom(f'sum(nomad_client_allocs_memory_allocated{{{sel}}})')], "bytes",
               FIXED(SLATE), desc="Sum of memory reservations."), 4, 4)
    d.add(stat("CPU used (MHz)", [prom(f'sum(rate(nomad_client_allocs_cpu_total_ticks{{{sel}}}[$__rate_interval]))')],
               "none", FIXED(TEAL), decimals=0), 4, 4)
    d.add(health("Restarts 24h", [prom(f'sum(increase(nomad_client_allocs_restart{{{sel}}}[24h])) or vector(0)')],
                 thr((None, GOOD), (1, WARN), (10, HIGH)), decimals=0), 4, 4)
    d.add(health("OOM kills 24h", [prom(f'sum(increase(nomad_client_allocs_oom_killed{{{sel}}}[24h])) or vector(0)')],
                 ZERO_GOOD, decimals=0), 4, 4)

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
        overrides=[col("Node", width=80), col("RSS", "bytes", width=100), col("memory", "bytes", width=100),
                   col("memory_max", "bytes", width=110),
                   col("RSS / memory_max", "percent", cell=GAUGE_BAR, thresholds=PCT_THR, mx=100, decimals=0),
                   col("CPU MHz", "none", decimals=0, width=90, cell={"type": "gauge", "mode": "basic",
                                                                       "valueDisplayMode": "text"},
                       color={"mode": "continuous-GrYlRd"}),
                   col("cpu reserved", "none", width=110)],
        sort=[{"displayName": "RSS / memory_max", "desc": True}]), 24, 12, newrow=True)

    d.add(heatmap("Memory pressure: RSS / memory_max per task", [prom(
        f'max by (exported_job, task) (nomad_client_allocs_memory_rss{{{sel}}} / (nomad_client_allocs_memory_max_allocated{{{sel}}} > 0)) * 100',
        "{{exported_job}}/{{task}}")], "percent",
        "Each row is a task; brighter means closer to its hard memory limit.", scheme="Plasma"), 12, 16, newrow=True)
    d.add(heatmap("CPU per task (MHz)", [prom(
        f'max by (exported_job, task) (rate(nomad_client_allocs_cpu_total_ticks{{{sel}}}[$__rate_interval]))',
        "{{exported_job}}/{{task}}")], "none", "Each row is a task; brighter means more CPU.", scheme="Viridis"),
        12, 16)

    d.row("Trends", collapsed=True)
    d.add(timeseries("Memory RSS", [prom(f'max by (exported_job, task) (nomad_client_allocs_memory_rss{{{sel}}})', "{{exported_job}}/{{task}}")],
                     "bytes", fill=0, width=1, legend_place="right", legend_calcs=("max", "lastNotNull")), 12, 9)
    d.add(timeseries("CPU (MHz)", [prom(f'max by (exported_job, task) (rate(nomad_client_allocs_cpu_total_ticks{{{sel}}}[$__rate_interval]))', "{{exported_job}}/{{task}}")],
                     fill=0, width=1, legend_place="right", legend_calcs=("mean", "max")), 12, 9)
    d.add(timeseries("Memory vs limits (pick one job)", [
        prom(f'max by (task) (nomad_client_allocs_memory_rss{{{sel}}})', "{{task}} RSS"),
        prom(f'max by (task) (nomad_client_allocs_memory_usage{{{sel}}})', "{{task}} usage incl. cache", "B"),
        prom(f'max by (task) (nomad_client_allocs_memory_allocated{{{sel}}})', "{{task}} memory", "C"),
        prom(f'max by (task) (nomad_client_allocs_memory_max_allocated{{{sel}}})', "{{task}} memory_max", "D")],
        "bytes", fill=0, overrides=[series_color(".*memory_max", BAD, regex=True, dashed=True, width=1),
                                    series_color(".* memory$", WARN, regex=True, dashed=True, width=1)],
        desc="Dashed lines are the reservation (memory) and the hard limit (memory_max)."), 12, 9, newrow=True)
    d.add(timeseries("CPU throttled time", [prom(
        f'max by (exported_job, task) (rate(nomad_client_allocs_cpu_throttled_time{{{sel}}}[$__rate_interval]))', "{{exported_job}}/{{task}}")],
        "ns", fill=0, width=1), 12, 9)

    d.row("Restarts and OOM kills")
    d.add(bars("Restarts", [prom(
        f'sum by (exported_job, task) (increase(nomad_client_allocs_restart{{{sel}}}[$__rate_interval]))', "{{exported_job}}/{{task}}")],
        unit="short"), 12, 8)
    d.add(bars("OOM kills", [
        prom(f'sum by (exported_job, task) (increase(nomad_client_allocs_oom_killed{{{sel}}}[$__rate_interval]))', "{{exported_job}}/{{task}}"),
        prom('increase(node_vmstat_oom_kill[$__rate_interval])', "kernel OOM kills on {{node}}", "B")],
        unit="short", desc="Task OOM kills reported by Nomad plus the kernel OOM-kill counter per node."), 12, 8)
    return d


# ---------------------------------------------------------------- traefik
def traefik():
    v = [var_query("service", 'label_values(traefik_service_requests_total, service)', "Service")]
    d = Dash("homelab-traefik", "Traefik", ["homelab", "ingress"],
             "Ingress traffic, errors, latency and certificates.", variables=v)
    s = 'service=~"$service"'
    d.add(stat("Requests/s", [prom(f'sum(rate(traefik_service_requests_total{{{s}}}[$__rate_interval]))')],
               "reqps", FIXED(INFO), decimals=2, delta=True), 4, 4)
    d.add(stat("5xx rate", [prom(f'100 * sum(rate(traefik_service_requests_total{{{s},code=~"5.."}}[5m])) / clamp_min(sum(rate(traefik_service_requests_total{{{s}}}[5m])), 1e-9)')],
               "percent", thr((None, GOOD), (1, WARN), (5, BAD)), decimals=2), 4, 4)
    d.add(stat("4xx rate", [prom(f'100 * sum(rate(traefik_service_requests_total{{{s},code=~"4.."}}[5m])) / clamp_min(sum(rate(traefik_service_requests_total{{{s}}}[5m])), 1e-9)')],
               "percent", thr((None, GOOD), (10, WARN), (30, HIGH)), decimals=1,
               desc="Client errors: scanners, auth redirects and missing paths."), 4, 4)
    d.add(stat("p95 latency", [prom(f'histogram_quantile(0.95, sum by (le) (rate(traefik_service_request_duration_seconds_bucket{{{s}}}[5m])))')],
               "s", thr((None, GOOD), (0.5, WARN), (2, BAD)), decimals=3), 4, 4)
    d.add(stat("Traffic out", [prom('sum(rate(traefik_entrypoint_responses_bytes_total[$__rate_interval]))')],
               "Bps", FIXED(TEAL), desc="Response bytes across all entrypoints."), 4, 4)
    d.add(stat("Soonest cert expiry", [prom('min(traefik_tls_certs_not_after - time())')], "dtdurations",
               thr((None, BAD), (7 * 86400, HIGH), (14 * 86400, GOOD)), graph=False), 4, 4)

    d.add(timeseries("Requests by service", [prom(f'sum by (service) (rate(traefik_service_requests_total{{{s}}}[$__rate_interval]))', "{{service}}")],
                     "reqps", stack=True, fill=35, legend_place="right", legend_calcs=("mean", "max")), 16, 9, newrow=True)
    d.add(topn("Top hosts", [prom(
        f'topk(12, sum by (service) (rate(traefik_service_requests_total{{{s}}}[5m])))', "{{service}}", instant=True)],
        "reqps", INFO, decimals=2, scheme="BlPu"), 8, 9)
    d.add(bars("Responses by status class", [prom(
        f'sum by (class) ({CLASS.format(f"rate(traefik_service_requests_total{{{s}}}[$__rate_interval])")})', "{{class}}")],
        unit="reqps", overrides=STATUS_COLORS), 12, 9, newrow=True)
    d.add(echarts("Traffic flow: service to status", [prom(
        f'sum by (service, class) ({CLASS.format(f"increase(traefik_service_requests_total{{{s}}}[$__range])")})',
        instant=True)], SANKEY_JS,
        "Requests in the selected range, from each service (top 14, rest grouped as other) to its status class."),
        12, 9)

    d.add(timeseries("Latency percentiles (all services)", [
        prom(f'histogram_quantile({q}, sum by (le) (rate(traefik_service_request_duration_seconds_bucket{{{s}}}[$__rate_interval])))', f"p{int(q * 100)}", r)
        for q, r in ((0.5, "A"), (0.95, "B"), (0.99, "C"))], "s", fill=8,
        overrides=[series_color("p50", TEAL), series_color("p95", WARN), series_color("p99", BAD, fill=0)]), 12, 9, newrow=True)
    d.add(timeseries("p95 latency by service", [prom(
        f'histogram_quantile(0.95, sum by (service, le) (rate(traefik_service_request_duration_seconds_bucket{{{s}}}[$__rate_interval])))', "{{service}}")],
        "s", fill=0, width=1, legend_place="right", legend_calcs=("mean", "max")), 12, 9)

    d.add(echarts("Traffic punch card (7 days)", [prom(
        f'sum(increase(traefik_service_requests_total{{{s}}}[1h]))')], punchcard_js("requests"),
        "Requests per hour over the last week. Brighter cells are busier hours.",
        interval="1h", maxDataPoints=200, timeFrom="7d", hideTimeOverride=False), 12, 9, newrow=True)
    d.add(timeseries("4xx / 5xx by service", [prom(
        f'sum by (service, code) (rate(traefik_service_requests_total{{{s},code=~"[45].."}}[$__rate_interval]))', "{{service}} {{code}}")],
        "reqps", fill=0, width=1, legend_place="right", legend_calcs=("mean", "max")), 12, 9)

    d.row("Connections and certificates", collapsed=True)
    d.add(timeseries("Open connections by entrypoint", [prom('sum by (entrypoint) (traefik_open_connections)', "{{entrypoint}}")],
                     fill=15), 8, 8)
    d.add(timeseries("Bandwidth by entrypoint (in up, out down)", [
        prom('sum by (entrypoint) (rate(traefik_entrypoint_requests_bytes_total[$__rate_interval]))', "{{entrypoint}} in"),
        prom('-sum by (entrypoint) (rate(traefik_entrypoint_responses_bytes_total[$__rate_interval]))', "{{entrypoint}} out", "B")],
        "Bps", centered=True), 8, 8)
    d.add(table("TLS certificates", [prom('min by (cn, sans) (traefik_tls_certs_not_after - time())', instant=True, fmt="table")],
                transformations=[{"id": "organize", "options": {"excludeByName": {"Time": True},
                                                               "renameByName": {"cn": "Common name", "sans": "SANs",
                                                                                "Value": "Expires in"}}}],
                overrides=[col("Expires in", "dtdurations", cell=COLOR_BG, width=150,
                               thresholds=thr((None, BAD), (7 * 86400, HIGH), (14 * 86400, CLEAR)))],
                sort=[{"displayName": "Expires in", "desc": False}]), 8, 8)
    return d


# ---------------------------------------------------------------- authentik
def authentik():
    d = Dash("homelab-authentik", "Authentik", ["homelab", "services"],
             "SSO health: outposts, request latency, flows and workers.")
    d.add(health("Outposts connected", [prom('sum(authentik_outposts_connected)')], thr((None, BAD), (1, GOOD)),
                 "The embedded outpost backs Traefik forward-auth. 0 means forward-auth apps are broken."), 4, 4)
    d.add(health("Workers", [prom('max(authentik_tasks_workers) or max(authentik_admin_workers)')],
                 thr((None, BAD), (1, GOOD))), 4, 4)
    d.add(stat("Tasks queued", [prom('sum(authentik_tasks_queued)')], "short",
               thr((None, GOOD), (20, WARN), (100, BAD))), 4, 4)
    d.add(stat("Request p95", [prom('max(authentik_main_request_duration_seconds{quantile="0.95"})')],
               "s", thr((None, GOOD), (0.5, WARN), (2, BAD)), decimals=3), 4, 4)
    d.add(stat("Responses/s", [prom('sum(rate(django_http_responses_total_by_status_total[$__rate_interval]))')],
               "reqps", FIXED(INFO), decimals=2), 4, 4)
    d.add(stat("5xx (range)", [prom('sum(increase(django_http_responses_total_by_status_total{status=~"5.."}[$__range])) or vector(0)', instant=True)],
               "short", COUNT_THR(1, 20), graph=False, decimals=0), 4, 4)
    d.add(timeseries("Request latency", [prom('max by (dest, quantile) (authentik_main_request_duration_seconds{quantile=~"0.5|0.95|0.99"})', "{{dest}} p{{quantile}}")],
                     "s", fill=6), 12, 8, newrow=True)
    d.add(bars("HTTP responses by status", [prom('sum by (status) (rate(django_http_responses_total_by_status_total[$__rate_interval]))', "{{status}}")],
               unit="reqps", overrides=STATUS_COLORS), 12, 8)
    d.add(timeseries("Flow stage time p95", [prom(
        'histogram_quantile(0.95, sum by (stage_type, le) (rate(authentik_flows_stage_time_bucket[$__rate_interval])))', "{{stage_type}}")],
        "s", fill=0, legend_place="right", legend_calcs=("mean", "max")), 12, 8, newrow=True)
    d.add(timeseries("Policy execution p95", [prom(
        'histogram_quantile(0.95, sum by (le) (rate(authentik_policies_execution_time_bucket[$__rate_interval])))', "policies")],
        "s", fill=15, overrides=[series_color("policies", ACCENT)]), 12, 8)
    d.add(timeseries("DB queries/s", [prom('sum by (vendor) (rate(django_db_execute_total[$__rate_interval]))', "{{vendor}}")],
                     "ops", fill=15), 12, 8, newrow=True)
    d.add(bars("Exceptions", [prom('sum by (type) (increase(django_http_exceptions_total_by_type_total[$__rate_interval]))', "{{type}}")],
               unit="short"), 12, 8)
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
    d.add(stat("Lines", [loki(f'sum(count_over_time({sel} |~ "(?i)$search" [$__range]))', instant=True)], "short",
               FIXED(INFO), ds=LOKI, graph=False, decimals=0, desc="Log lines in the selected range."), 6, 4)
    d.add(stat("Error lines", [loki(f'sum(count_over_time({sel} |~ "{ERR_RE}" |~ "(?i)$search" [$__range]))', instant=True)],
               "short", thr((None, GOOD), (100, WARN), (1000, HIGH)), ds=LOKI, graph=False, decimals=0), 6, 4)
    d.add(stat("SSH logins", [loki('sum(count_over_time({unit="ssh.service", node=~"$node"} |~ "Accepted (password|publickey)" [$__range])) or vector(0)', instant=True)],
               "short", FIXED(TEAL), ds=LOKI, graph=False, decimals=0), 6, 4)
    d.add(stat("SSH failures", [loki('sum(count_over_time({unit="ssh.service", node=~"$node"} |~ "(Failed password|Invalid user|authentication failure)" [$__range])) or vector(0)', instant=True)],
               "short", COUNT_THR(1, 10), ds=LOKI, graph=False, decimals=0), 6, 4)
    d.add(bars("Log volume by source", [loki(f'sum by (source) (count_over_time({sel} |~ "(?i)$search" [$__auto]))', "{{source}}")],
               ds=LOKI, unit="short"), 12, 7, newrow=True)
    d.add(bars("Errors by node", [loki(f'sum by (node) (count_over_time({sel} |~ "{ERR_RE}" |~ "(?i)$search" [$__auto]))', "{{node}}")],
               ds=LOKI, unit="short", nodes=True), 12, 7)
    d.add(bars("Nomad tasks by log volume", [loki(
        'topk(10, sum by (task) (count_over_time({source="nomad", node=~"$node"} |~ "(?i)$search" [$__auto])))', "{{task}}")],
        ds=LOKI, unit="short", legend_place="right"), 12, 7, newrow=True)
    d.add(bars("SSH logins and failures", [
        loki('sum by (node) (count_over_time({unit="ssh.service", node=~"$node"} |~ "Accepted (password|publickey)" [$__auto]))', "{{node}} accepted"),
        loki('sum by (node) (count_over_time({unit="ssh.service", node=~"$node"} |~ "(Failed password|Invalid user|authentication failure)" [$__auto]))', "{{node}} failed", "B")],
        ds=LOKI, unit="short", stack=False, overrides=[series_color(".*failed", BAD, regex=True)]), 12, 7)
    d.add(logs("All logs (node + source filters)", [loki(f'{sel} |~ "(?i)$search"')]), 24, 14, newrow=True)

    d.row("Host systems (journald)", collapsed=True)
    host = '{source="journal", node=~"$node", unit=~"$unit", level=~"$level"}'
    d.add(bars("Host log volume by unit", [loki(
        f'topk(12, sum by (unit) (count_over_time({host} |~ "(?i)$search" [$__auto])))', "{{unit}}")],
        ds=LOKI, unit="short", legend_place="right"), 12, 7)
    d.add(bars("Host log volume by level", [loki(
        f'sum by (level) (count_over_time({host} |~ "(?i)$search" [$__auto]))', "{{level}}")],
        ds=LOKI, unit="short",
        overrides=[series_color("error|crit|alert|emerg", BAD, regex=True), series_color("warning", WARN),
                   series_color("notice", INFO), series_color("info", GOOD)]), 12, 7)
    d.add(logs("Host system logs (journald: systemd units, kernel, sshd, nomad, consul, docker)",
               [loki(f'{host} |~ "(?i)$search"')]), 24, 16, newrow=True)
    d.add(logs("Host log files (/var/log/*.log)",
               [loki('{source="file", node=~"$node"} |~ "(?i)$search"')]), 24, 10, newrow=True)

    d.row("Errors", collapsed=True)
    d.add(logs("Errors only", [loki(f'{sel} |~ "{ERR_RE}" |~ "(?i)$search"')]), 24, 12)
    return d


# ---------------------------------------------------------------- monitoring stack
def monitoring_stack():
    d = Dash("homelab-monitoring-stack", "Monitoring Stack", ["homelab", "observability"],
             "Is the monitoring itself healthy? Scrape targets, Prometheus, Loki and Alloy.")
    d.add(health("Targets up", [prom('100 * count(up == 1) / count(up)')], thr((None, BAD), (90, WARN), (100, GOOD)),
                 "Share of Prometheus scrape targets answering.", unit="percent", decimals=0), 4, 4)
    d.add(stat("Head series", [prom('prometheus_tsdb_head_series')], "short", FIXED(INFO)), 4, 4)
    d.add(stat("Samples/s", [prom('rate(prometheus_tsdb_head_samples_appended_total[$__rate_interval])')], "short",
               FIXED(ACCENT)), 4, 4)
    d.add(stat("TSDB size", [prom('prometheus_tsdb_storage_blocks_bytes + prometheus_tsdb_wal_storage_size_bytes')],
               "bytes", FIXED(SLATE), desc="Prometheus blocks plus WAL. Retention is 15 days."), 4, 4)
    d.add(stat("Loki lines/s", [prom('sum(rate(loki_distributor_lines_received_total[$__rate_interval]))')], "short",
               FIXED(TEAL)), 4, 4)
    d.add(health("Alloy config", [prom('min(alloy_config_last_load_successful)')], thr((None, BAD), (1, GOOD)),
                 "Lowest config-load result across the Alloy agents.", OK_MAP("LOADED", "FAILED")), 4, 4)

    d.add(table("Scrape targets", [prom('up', instant=True, fmt="table")],
                transformations=[{"id": "organize", "options": {
                    "excludeByName": {"Time": True, "__name__": True},
                    "indexByName": {"job": 0, "node": 1, "instance": 2, "Value": 3},
                    "renameByName": {"job": "Job", "node": "Node", "instance": "Instance", "Value": "State"}}}],
                overrides=[col("State", cell=COLOR_BG, mappings=VALUE_MAP_UP,
                               thresholds=thr((None, BAD), (1, GOOD)), width=90)],
                sort=[{"displayName": "State", "desc": False}]), 12, 10, newrow=True)
    d.add(timeseries("Scrape duration", [prom('max by (job) (scrape_duration_seconds)', "{{job}}")],
                     "s", fill=0, legend_place="right", legend_calcs=("mean", "max")), 12, 10)
    d.add(timeseries("Prometheus head series", [prom('prometheus_tsdb_head_series', "series")], fill=15,
                     overrides=[series_color("series", INFO)]), 8, 7, newrow=True)
    d.add(timeseries("Prometheus samples/s", [prom('rate(prometheus_tsdb_head_samples_appended_total[$__rate_interval])', "samples/s")],
                     fill=15, overrides=[series_color("samples/s", ACCENT)]), 8, 7)
    d.add(timeseries("Prometheus storage", [prom('prometheus_tsdb_storage_blocks_bytes + prometheus_tsdb_wal_storage_size_bytes', "TSDB + WAL")],
                     "bytes", fill=15, overrides=[series_color("TSDB + WAL", SLATE)]), 8, 7)
    d.add(timeseries("Loki lines received/s", [prom('sum(rate(loki_distributor_lines_received_total[$__rate_interval]))', "lines/s")],
                     fill=15, overrides=[series_color("lines/s", TEAL)]), 8, 7, newrow=True)
    d.add(timeseries("Loki bytes received/s", [prom('sum(rate(loki_distributor_bytes_received_total[$__rate_interval]))', "bytes/s")],
                     "Bps", fill=15, overrides=[series_color("bytes/s", INFO)]), 8, 7)
    d.add(timeseries("Loki request p95 by route", [prom(
        'histogram_quantile(0.95, sum by (route, le) (rate(loki_request_duration_seconds_bucket{route!~"metrics|ready"}[$__rate_interval])))', "{{route}}")],
        "s", fill=0, width=1, legend_calcs=("max",), legend_place="right"), 8, 7)
    d.add(timeseries("Loki active streams", [prom('sum(loki_ingester_memory_streams)', "streams")], fill=15,
                     overrides=[series_color("streams", ACCENT)]), 12, 7, newrow=True)
    d.add(timeseries("Alloy memory", [prom('alloy_resources_process_resident_memory_bytes', "{{node}}")],
                     "bytes", fill=8, nodes=True), 12, 7)
    return d


# ---------------------------------------------------------------- power
def power():
    v = [var_text("price", "€ per kWh", "0.35"),
         var_text("node_overhead_w", "Per-node overhead (W)", "12"),
         var_text("nas_w", "NAS (W)", "35")]
    d = Dash("homelab-power", "Power & cost", ["homelab", "infrastructure"],
             "CPU power is measured with RAPL on each node. Wall power adds the per-node overhead "
             "(PSU loss, board, SSD, fans) and the NAS, which are estimates: adjust them at the top, "
             "or replace them with a smart plug reading.",
             time_from="now-7d", refresh="1m", variables=v)
    d.add(echarts("Estimated wall power", [prom(WALL_W, instant=True),
                                            prom(f'{WALL_W} * 24 * 30.44 / 1000 * $price', ref="B", instant=True)],
                  POWER_GAUGE_JS, "Measured CPU and memory power plus the overhead and NAS estimates. "
                                  "The scale grows with the reading."), 6, 10)
    kw = dict(color_mode="value", graph=False)
    d.add(stat("Per day", [prom(f'{WALL_W} * 24 / 1000', instant=True)], "kwatth", FIXED(TEAL), decimals=2,
               desc="Energy per day at the current draw.", **kw), 6, 5)
    d.add(stat("Per month", [prom(f'{WALL_W} * 24 * 30.44 / 1000 * $price', instant=True)],
               "currencyEUR", FIXED(WARN), decimals=2, desc="At the current draw, 30.44 days.", **kw), 6, 5)
    d.add(stat("Per year", [prom(f'{WALL_W} * 24 * 365 / 1000 * $price', instant=True)],
               "currencyEUR", FIXED(HIGH), decimals=0, **kw), 6, 5)
    d.add(stat("Measured CPU power", [prom(f'sum({PKG_W})')], "watt", FIXED(ACCENT), decimals=1,
               color_mode="value", desc="Sum of RAPL package power on all nodes."), 6, 5)
    d.add(stat("Measured DRAM power", [prom(f'sum({DRAM_W})')], "watt", FIXED(INFO), decimals=1,
               color_mode="value", desc="Sum of RAPL DRAM power on all nodes."), 6, 5)
    d.add(stat("Cost of selected range", [
        prom(f'avg_over_time(({WALL_W})[$__range:5m]) * ($__range_s / 3600) / 1000 * $price', instant=True)],
        "currencyEUR", FIXED(PINK), decimals=2, desc="Average estimated wall power over the time picker range, priced at € per kWh.",
        **kw), 6, 5)

    d.add(timeseries("Estimated wall power", [prom(WALL_W, "total")], "watt", fill=25, gradient="scheme",
                     legend_calcs=("min", "mean", "max"),
                     color={"mode": "continuous-GrYlRd"}, thresholds=thr((None, GOOD), (150, WARN), (250, BAD))),
          16, 9, newrow=True)
    d.add(donut("Power share by node (CPU + DRAM)", [prom(f'{PKG_W} + {DRAM_W}', "{{node}}", instant=True)],
                "watt", overrides=[series_color(n, c) for n, c in NODE_COLORS.items()], decimals=1), 8, 9)
    d.add(timeseries("CPU package power by node", [prom(PKG_W, "{{node}}")], "watt", stack=True, fill=30,
                     nodes=True, desc="RAPL package domain: cores, iGPU and uncore."), 12, 9, newrow=True)
    d.add(timeseries("Power vs CPU load", [
        prom(PKG_W, "{{node}} watts"),
        prom('100 * (1 - avg by (node) (rate(node_cpu_seconds_total{mode="idle"}[5m])))', "{{node}} CPU %", ref="B"),
    ], "watt", fill=0, overrides=[right_axis(".*CPU %", "percent", dashed=True)] +
        [series_color(f"{n}.*", c, regex=True) for n, c in NODE_COLORS.items()]), 12, 9)
    d.add(timeseries("Memory (DRAM) power by node", [prom(DRAM_W, "{{node}}")], "watt", fill=12, nodes=True), 12, 8,
          newrow=True)
    d.add(bargauge("CPU energy in selected range", [
        prom('sum by (node) (increase(node_rapl_package_joules_total[$__range])) / 3.6e6', "{{node}}", instant=True)],
        unit="kwatth", thresholds=FIXED(INFO), mn=0, decimals=2,
        overrides=[{"matcher": {"id": "byName", "options": n},
                    "properties": [{"id": "color", "value": {"mode": "fixed", "fixedColor": c}}]}
                   for n, c in NODE_COLORS.items()]), 12, 8)
    return d


# ---------------------------------------------------------------- security
PRIVATE_IP = r"`(10|127)\..*|192\.168\..*|172\.(1[6-9]|2[0-9]|3[01])\..*|f[cde].*|::1|`"
FALCO = '{task="falco", node=~"$node"} != "Falco internal" | json | __error__="" | rule!=""'
FALCO_ALL = '{task="falco", node=~".+"} != "Falco internal" | json | __error__="" | rule!=""'
SURI = '{task="suricata", node=~"$node"} |= `"event_type":"alert"` | json | __error__="" | src_ip=~"$ip" or dest_ip=~"$ip"'
SURI_ALL = '{task="suricata"} |= `"event_type":"alert"` | json | __error__=""'
SURI_STATS = '{task="suricata", node=~"$node"} |= `"event_type":"stats"` | json'
SURI_STATS_ALL = '{task="suricata"} |= `"event_type":"stats"` | json'
BANS = '{task="crowdsec"} |~ "ban on [Ii]p" | regexp `\\) (?P<scenario>.+?) by ip (?P<ip>[0-9a-fA-F.:]+)`'
WAZUH = '{task=~"$wazuh_task"} | json | __error__="" | rule_level!=""'
WAZUH_ALL = '{task=~"wazuh-alerts"} | json | __error__="" | rule_level!=""'
TRAEFIK = '{task="traefik", node=~"$node"} |= "RequestHost" | json | __error__="" | RequestHost=~"$host"'
TRAEFIK_ALL = '{task="traefik"} |= "RequestHost" | json | __error__=""'
SUSPICIOUS = (r"`(?i).*(wp-admin|wp-login|xmlrpc\.php|/\.env|/\.git|/\.aws|phpmyadmin|/cgi-bin|/vendor/phpunit"
              r"|/actuator|/boaform|/HNAP1|/server-status|/\.well-known/security|\.php$|/shell|/admin\.).*`")
PRIO_COLORS = [series_color("Emergency|Alert|Critical", BAD, regex=True), series_color("Error", HIGH),
               series_color("Warning", WARN), series_color("Notice", INFO),
               series_color("Informational|Debug", SLATE, regex=True)]
SEV_COLORS = [series_color("1|sev 1|high", BAD, regex=True), series_color("2|sev 2|medium", HIGH, regex=True),
              series_color("3|sev 3|low", WARN, regex=True)]
LEVEL_COLORS = [series_color("level (1[2-9])", BAD, regex=True), series_color("level ([7-9]|1[01])", HIGH, regex=True),
                series_color("level [3-6]", WARN, regex=True), series_color("level [0-2]", SLATE, regex=True)]
SEC_DASHES = [("Overview", "homelab-security-overview"), ("Falco", "homelab-falco"),
              ("Suricata", "homelab-suricata"), ("CrowdSec", "homelab-crowdsec"), ("Wazuh", "homelab-wazuh"),
              ("AdGuard", "homelab-adguard"), ("Traefik access", "homelab-traefik-access")]
SEC_TINT = ("#140f12", "#3b0d16", "#7f1d1d", "#9a3412")


def sec_dash(uid, title, desc, variables=None, time_from="now-24h"):
    d = Dash(uid, title, ["homelab", "security"], desc, refresh="1m", time_from=time_from, variables=variables)
    d.links = [{"title": t, "type": "link", "url": f"/d/{u}", "keepTime": True, "includeVars": False,
                "targetBlank": False} for t, u in SEC_DASHES if u != uid]
    return d


def lstat(title, expr, thresholds=None, desc="", unit="short", decimals=0):
    return stat(title, [loki(expr, instant=True)], unit, thresholds or FIXED(INFO), desc, ds=LOKI, graph=False,
                decimals=decimals)


def lbars(title, targets, overrides=None, desc="", stack=True, **kw):
    return bars(title, targets, ds=LOKI, unit="short", overrides=overrides, desc=desc, stack=stack, **kw)


def ltable(title, expr, rename, value="Count", overrides=None, desc="", unit=None, color=ACCENT):
    """Top-N table from an instant Loki metric query; each label becomes a column."""
    return table(title, [loki(expr, instant=True)], ds=LOKI, desc=desc, transformations=[
        {"id": "reduce", "options": {"reducers": ["lastNotNull"], "mode": "seriesToRows",
                                     "labelsToFields": True}},
        {"id": "organize", "options": {"excludeByName": {"Field": True},
                                       "renameByName": {**rename, "Last *": value}}}],
        overrides=[col(value, unit or "short", decimals=None if unit else 0, width=110,
                       cell={"type": "gauge", "mode": "basic", "valueDisplayMode": "text"},
                       color={"mode": "fixed", "fixedColor": color})] + (overrides or []),
        sort=[{"displayName": value, "desc": True}])


SEC_PUNCH = [
    loki(f'sum(count_over_time({FALCO_ALL} | priority=~"Emergency|Alert|Critical|Error|Warning" [1h]))', "falco"),
    loki(f'sum(count_over_time({SURI_ALL} | alert_severity=~"1|2" [1h]))', "suricata", "B"),
    loki(f'sum(count_over_time({BANS} [1h]))', "crowdsec", "C"),
    loki(f'sum(count_over_time({WAZUH_ALL} | rule_level >= 7 [1h]))', "wazuh", "D"),
]


def security_overview():
    d = sec_dash("homelab-security-overview", "Security Overview",
                 "One-glance security posture: host runtime (Falco), network IDS (Suricata), "
                 "IP reputation and bans (CrowdSec), HIDS (Wazuh), DNS filtering (AdGuard) and ingress probes. "
                 "Counts are the last 24 hours.",
                 variables=[var_text("wazuh_task", "Wazuh alerts task (regex)", "wazuh-alerts")])
    d.add(banner("Security Overview", "Falco &middot; Suricata &middot; CrowdSec &middot; Wazuh &middot; AdGuard &middot; Traefik",
                 [(t, f"/d/{u}") for t, u in SEC_DASHES[1:]] + [("Alerts", "/alerting/list?search=label:category=security")],
                 SEC_TINT, "#fecaca"), 24, 3)

    fa = FALCO_ALL
    d.add(health("Falco critical+", [loki(f'sum(count_over_time({fa} | priority=~"Emergency|Alert|Critical" [24h])) or vector(0)', instant=True)],
                 COUNT_THR(1, 1), "Falco events at Critical, Alert or Emergency priority.", ds=LOKI, unit="short", decimals=0), 4, 4)
    d.add(lstat("Falco warning/error", f'sum(count_over_time({fa} | priority=~"Error|Warning" [24h])) or vector(0)',
                COUNT_THR(10, 50)), 4, 4)
    d.add(health("Suricata severity 1", [loki(f'sum(count_over_time({SURI_ALL} | alert_severity="1" [24h])) or vector(0)', instant=True)],
                 COUNT_THR(1, 1), "All severity 1 alerts. The alert rule ignores ET P2P (Transmission) and ET INFO signatures.",
                 ds=LOKI, unit="short", decimals=0), 4, 4)
    d.add(lstat("Suricata severity 2", f'sum(count_over_time({SURI_ALL} | alert_severity="2" [24h])) or vector(0)',
                COUNT_THR(20, 100)), 4, 4)
    d.add(stat("CrowdSec active decisions", [prom('sum(cs_active_decisions) or vector(0)')], "short", FIXED(INFO),
               decimals=0, desc="Decisions (bans) currently enforced, local and community blocklist."), 4, 4)
    d.add(lstat("CrowdSec bans", f'sum(count_over_time({BANS} [24h])) or vector(0)', FIXED(ACCENT),
                "New local ban decisions in the CrowdSec log."), 4, 4)

    d.add(health("Wazuh level 12+", [loki(f'sum(count_over_time({WAZUH} | rule_level >= 12 [24h])) or vector(0)', instant=True)],
                 COUNT_THR(1, 1), ds=LOKI, unit="short", decimals=0), 4, 4, newrow=True)
    d.add(lstat("Wazuh level 7-11", f'sum(count_over_time({WAZUH} | rule_level >= 7 | rule_level < 12 [24h])) or vector(0)',
                COUNT_THR(20, 100)), 4, 4)
    d.add(stat("AdGuard blocked", [prom('100 * sum(adguard_queries_blocked) / sum(adguard_queries)')],
               "percent", FIXED(TEAL), decimals=1, desc="Share of DNS queries blocked by filtering (AdGuard's own window)."), 4, 4)
    d.add(lstat("Traefik path probes", f'sum(count_over_time({TRAEFIK_ALL} | RequestPath=~{SUSPICIOUS} [24h])) or vector(0)',
                COUNT_THR(50, 500), "Requests for /wp-admin, /.env, /.git, phpMyAdmin and similar scanner paths."), 4, 4)
    d.add(health("Sensors up", [prom('count(up{job=~"falco|crowdsec|adguard"} == 1) or vector(0)')],
                 thr((None, BAD), (7, GOOD)), "Prometheus targets for Falco (one per node), CrowdSec and AdGuard (one per node).",
                 unit="suffix: / 7", decimals=0), 4, 4)
    d.add(stat("Suricata capture drops", [loki(
        f'100 * sum(sum_over_time({SURI_STATS_ALL} d="stats.capture.kernel_drops_delta" | unwrap d | __error__="" [1h])) '
        f'/ sum(sum_over_time({SURI_STATS_ALL} p="stats.capture.kernel_packets_delta" | unwrap p | __error__="" [1h]))',
        instant=True)], "percent", thr((None, GOOD), (1, WARN), (5, BAD)), ds=LOKI, decimals=2, graph=False,
        desc="Kernel packet drops over the last hour."), 4, 4)

    d.row("Timelines")
    d.add(lbars("Falco events by priority", [loki(f'sum by (priority) (count_over_time({fa} [$__auto]))', "{{priority}}")],
                PRIO_COLORS), 8, 8)
    d.add(lbars("Suricata alerts by severity", [loki(
        f'sum by (alert_severity) (count_over_time({SURI_ALL} [$__auto]))', "sev {{alert_severity}}")], SEV_COLORS), 8, 8)
    d.add(lbars("Wazuh alerts by level", [loki(
        f'sum by (rule_level) (count_over_time({WAZUH} | rule_level >= 3 [$__auto]))', "level {{rule_level}}")],
        LEVEL_COLORS), 8, 8)
    d.add(echarts("When things happen (7 days)", SEC_PUNCH, punchcard_js("events"),
                  "Falco warning+, Suricata severity 1-2, CrowdSec bans and Wazuh level 7+ per hour over the last week.",
                  ds=LOKI, interval="1h", maxDataPoints=200, timeFrom="7d"), 12, 9, newrow=True)
    d.add(timeseries("CrowdSec active decisions", [prom('sum by (origin, action) (cs_active_decisions)', "{{origin}} {{action}}")],
                     "short", fill=20), 6, 9)
    d.add(lbars("Traefik 4xx / 5xx and probes", [
        loki(f'sum(count_over_time({TRAEFIK_ALL} | DownstreamStatus >= 400 | DownstreamStatus < 500 [$__auto]))', "4xx"),
        loki(f'sum(count_over_time({TRAEFIK_ALL} | DownstreamStatus >= 500 [$__auto]))', "5xx", "B"),
        loki(f'sum(count_over_time({TRAEFIK_ALL} | RequestPath=~{SUSPICIOUS} [$__auto]))', "probes", "C")],
        [series_color("4xx", WARN), series_color("5xx", BAD), series_color("probes", ACCENT)], stack=False), 6, 9)
    d.add(lbars("CrowdSec bans by scenario", [loki(f'sum by (scenario) (count_over_time({BANS} [$__auto]))', "{{scenario}}")]),
          24, 7, newrow=True)

    d.row("Top attackers (24h)")
    d.add(topn("Suricata alert sources (external)", [loki(
        f'topk(15, sum by (src_ip) (count_over_time({SURI_ALL} | src_ip!~{PRIVATE_IP} [24h])))', "{{src_ip}}", instant=True)],
        ds=LOKI, color=HIGH, scheme="YlRd"), 8, 10)
    d.add(topn("CrowdSec banned IPs", [loki(
        f'topk(15, sum by (ip) (count_over_time({BANS} [24h])))', "{{ip}}", instant=True)], ds=LOKI, color=BAD,
        scheme="YlRd"), 8, 10)
    d.add(topn("Traefik clients hitting 4xx", [loki(
        f'topk(15, sum by (ClientHost) (count_over_time({TRAEFIK_ALL} | DownstreamStatus >= 400 [24h])))',
        "{{ClientHost}}", instant=True)], ds=LOKI, color=WARN, scheme="YlRd"), 8, 10)

    d.row("What fired")
    d.add(ltable("Top Falco rules", f'topk(15, sum by (rule, priority) (count_over_time({fa} [24h])))',
                 {"rule": "Rule", "priority": "Priority"}, color=HIGH), 8, 10)
    d.add(ltable("Top Suricata signatures", f'topk(15, sum by (alert_signature, alert_severity) (count_over_time({SURI_ALL} [24h])))',
                 {"alert_signature": "Signature", "alert_severity": "Sev"},
                 overrides=[col("Sev", cell=COLOR_TXT, width=50, thresholds=thr((None, BAD), (2, HIGH), (3, WARN)))],
                 color=WARN), 8, 10)
    d.add(alertlist("Security alerts", '{category="security"}'), 8, 10)

    d.row("Latest high-priority events", collapsed=True)
    d.add(logs("Falco Critical / Error / Warning", [loki(
        f'{fa} | priority=~"Emergency|Alert|Critical|Error|Warning" | line_format "{{{{.priority}}}} {{{{.rule}}}} | {{{{.output}}}}"')]), 12, 12)
    d.add(logs("Suricata severity 1-2 alerts", [loki(
        f'{SURI_ALL} | alert_severity=~"1|2" | line_format "sev{{{{.alert_severity}}}} {{{{.alert_signature}}}} | {{{{.src_ip}}}}:{{{{.src_port}}}} -> {{{{.dest_ip}}}}:{{{{.dest_port}}}} {{{{.proto}}}}"')]), 12, 12)
    return d


def falco_dash():
    v = [var_loki_label("node", "node", "Node"), var_text("search", "Search (regex)", "")]
    d = sec_dash("homelab-falco", "Falco", "Runtime security: syscall rules matched on every node and container.",
                 variables=v)
    f = f'{FALCO} |~ "(?i)$search"'
    d.add(lstat("Events", f'sum(count_over_time({f} [$__range])) or vector(0)'), 4, 4)
    d.add(health("Critical+", [loki(f'sum(count_over_time({f} | priority=~"Emergency|Alert|Critical" [$__range])) or vector(0)', instant=True)],
                 COUNT_THR(1, 1), ds=LOKI, unit="short", decimals=0), 4, 4)
    d.add(lstat("Error", f'sum(count_over_time({f} | priority="Error" [$__range])) or vector(0)', COUNT_THR(1, 10)), 4, 4)
    d.add(lstat("Warning", f'sum(count_over_time({f} | priority="Warning" [$__range])) or vector(0)', COUNT_THR(10, 50)), 4, 4)
    d.add(health("Agents up", [prom('count(up{job="falco"} == 1) or vector(0)')], thr((None, BAD), (3, GOOD)),
                 unit="suffix: / 3", decimals=0), 4, 4)
    d.add(stat("Kernel drops", [prom(
        '100 * sum(rate(falcosecurity_scap_n_drops_total{node=~"$node"}[5m])) / clamp_min(sum(rate(falcosecurity_scap_n_evts_total{node=~"$node"}[5m])), 1)')],
        "percent", thr((None, GOOD), (0.5, WARN), (2, BAD)), decimals=2,
        desc="Syscall events dropped by the driver. Drops mean Falco may miss events."), 4, 4)

    d.add(lbars("Events by priority", [loki(f'sum by (priority) (count_over_time({f} [$__auto]))', "{{priority}}")],
                PRIO_COLORS), 12, 8, newrow=True)
    d.add(lbars("Events by rule", [loki(f'sum by (rule) (count_over_time({f} [$__auto]))', "{{rule}}")],
                legend_place="right"), 12, 8)
    d.add(barchart("MITRE ATT&CK tactics", [loki(
        f'sum by (tactic) (count_over_time({{task="falco", node=~"$node"}} != "Falco internal" |~ "(?i)$search" | regexp `"(?P<tactic>mitre_[a-z_]+)"` | tactic!="" [$__range]))',
        "{{tactic}}", instant=True)], "tactic", {"tactic": "Tactic"}, desc="First MITRE tactic tag on each event.",
        color=ACCENT), 8, 8, newrow=True)
    d.add(lbars("Events by node", [loki(f'sum by (node) (count_over_time({f} [$__auto]))', "{{node}}")], nodes=True), 8, 8)
    d.add(bars("Rule matches (Prometheus counter)", [prom(
        'sum by (rule_name) (increase(falcosecurity_falco_rules_matches_total{node=~"$node"}[$__rate_interval]))', "{{rule_name}}")],
        unit="short", desc="Same events from the metrics endpoint; survives Loki retention."), 8, 8)

    d.row("Who and what")
    d.add(ltable("Top rules", f'topk(20, sum by (rule, priority) (count_over_time({f} [$__range])))',
                 {"rule": "Rule", "priority": "Priority"}, color=HIGH), 8, 10)
    d.add(ltable("Top containers", f'topk(20, sum by (output_fields_container_name, output_fields_container_image_repository) (count_over_time({f} [$__range])))',
                 {"output_fields_container_name": "Container", "output_fields_container_image_repository": "Image"},
                 desc="host means the event came from the host, outside any container."), 8, 10)
    d.add(ltable("Top processes", f'topk(20, sum by (output_fields_proc_name, output_fields_user_name) (count_over_time({f} [$__range])))',
                 {"output_fields_proc_name": "Process", "output_fields_user_name": "User"}, color=TEAL), 8, 10)
    d.add(ltable("Files touched (fd.name)", f'topk(20, sum by (output_fields_fd_name, rule) (count_over_time({f} | output_fields_fd_name!="" [$__range])))',
                 {"output_fields_fd_name": "File", "rule": "Rule"}, color=INFO), 24, 8, newrow=True)

    d.row("Falco health", collapsed=True)
    d.add(timeseries("Syscall events/s", [prom('sum by (node) (rate(falcosecurity_scap_n_evts_total{node=~"$node"}[$__rate_interval]))', "{{node}}")],
                     "ops", fill=10, nodes=True), 8, 7)
    d.add(timeseries("Dropped events/s", [prom('sum by (node) (rate(falcosecurity_scap_n_drops_total{node=~"$node"}[$__rate_interval]))', "{{node}}")],
                     "ops", fill=10, nodes=True), 8, 7)
    d.add(timeseries("Falco CPU / memory", [
        prom('falcosecurity_falco_cpu_usage_ratio{node=~"$node"} * 100', "{{node}} CPU %"),
        prom('falcosecurity_falco_memory_rss_bytes{node=~"$node"}', "{{node}} RSS", "B")],
        "percent", fill=0, overrides=[right_axis(".*RSS", "bytes", dashed=True)]), 8, 7)

    d.row("Events", collapsed=True)
    d.add(logs("Falco events", [loki(f'{f} | line_format "{{{{.priority}}}} {{{{.rule}}}} | {{{{.output}}}}"')],
               desc="Expand a line for container, process, user and file fields."), 24, 14)
    return d


def suricata_dash():
    v = [var_loki_label("node", "node", "Node"), var_text("ip", "IP filter (regex)", ".*")]
    d = sec_dash("homelab-suricata", "Suricata", "Network IDS on each node's uplink: alerts, DNS, TLS and capture health.",
                 variables=v)
    s = SURI
    d.add(lstat("Alerts", f'sum(count_over_time({s} [$__range])) or vector(0)'), 3, 4)
    d.add(health("Severity 1", [loki(f'sum(count_over_time({s} | alert_severity="1" [$__range])) or vector(0)', instant=True)],
                 COUNT_THR(1, 1), ds=LOKI, unit="short", decimals=0), 3, 4)
    d.add(lstat("Severity 2", f'sum(count_over_time({s} | alert_severity="2" [$__range])) or vector(0)', COUNT_THR(20, 100)), 3, 4)
    d.add(lstat("Severity 3", f'sum(count_over_time({s} | alert_severity="3" [$__range])) or vector(0)', FIXED(WARN)), 3, 4)
    d.add(lstat("Unique external sources", f'count(sum by (src_ip) (count_over_time({s} | src_ip!~{PRIVATE_IP} [$__range]))) or vector(0)',
                FIXED(ACCENT)), 3, 4)
    st = SURI_STATS
    d.add(lstat("DNS events", f'sum(count_over_time({{task="suricata", node=~"$node"}} |= `"event_type":"dns"` [$__range])) or vector(0)',
                FIXED(TEAL)), 3, 4)
    d.add(stat("Capture drops", [loki(
        f'100 * sum(sum_over_time({st} d="stats.capture.kernel_drops_delta" | unwrap d | __error__="" [$__range])) '
        f'/ sum(sum_over_time({st} p="stats.capture.kernel_packets_delta" | unwrap p | __error__="" [$__range]))', instant=True)],
        "percent", thr((None, GOOD), (1, WARN), (5, BAD)), ds=LOKI, decimals=2, graph=False), 3, 4)
    d.add(lstat("Anomalies", f'sum(count_over_time({{task="suricata", node=~"$node"}} |= `"event_type":"anomaly"` [$__range])) or vector(0)',
                FIXED(SLATE)), 3, 4)

    d.add(lbars("Alerts by severity", [loki(f'sum by (alert_severity) (count_over_time({s} [$__auto]))', "sev {{alert_severity}}")],
                SEV_COLORS), 12, 8, newrow=True)
    d.add(lbars("Alerts by category", [loki(f'sum by (alert_category) (count_over_time({s} [$__auto]))', "{{alert_category}}")],
                legend_place="right"), 12, 8)
    d.add(donut("EVE events by type", [loki(
        f'sum by (event_type) (count_over_time({{task="suricata", node=~"$node"}} | json event_type | __error__="" | event_type!="" [$__range]))',
        "{{event_type}}", instant=True)], ds=LOKI, desc="Everything Suricata logged in the range, by EVE type."), 8, 8,
        newrow=True)
    d.add(timeseries("Capture: packets vs kernel drops", [
        loki(f'sum by (node) (sum_over_time({st} p="stats.capture.kernel_packets_delta" | unwrap p | __error__="" [$__auto]))', "{{node}} packets"),
        loki(f'sum by (node) (sum_over_time({st} d="stats.capture.kernel_drops_delta" | unwrap d | __error__="" [$__auto]))', "{{node}} drops", "B")],
        "short", ds=LOKI, fill=10, overrides=[{"matcher": {"id": "byRegexp", "options": ".*drops"},
                                               "properties": [{"id": "custom.axisPlacement", "value": "right"},
                                                              {"id": "color", "value": {"mode": "fixed", "fixedColor": BAD}}]}]),
        16, 8)

    d.row("Top talkers")
    d.add(ltable("Top signatures", f'topk(25, sum by (alert_signature, alert_category, alert_severity) (count_over_time({s} [$__range])))',
                 {"alert_signature": "Signature", "alert_category": "Category", "alert_severity": "Sev"},
                 overrides=[col("Sev", cell=COLOR_TXT, width=50, thresholds=thr((None, BAD), (2, HIGH), (3, WARN)))],
                 color=WARN), 12, 10)
    d.add(ltable("Top alert sources", f'topk(25, sum by (src_ip, dest_ip, dest_port) (count_over_time({s} [$__range])))',
                 {"src_ip": "Source", "dest_ip": "Destination", "dest_port": "Port"}, color=HIGH), 12, 10)
    d.add(ltable("Top DNS domains (last 30 min)",
                 'topk(25, sum by (domain) (count_over_time({task="suricata", node=~"$node"} |= `"event_type":"dns"` |= `"type":"request"` '
                 '| regexp `"rrname":"(?:[^"]*\\.)?(?P<domain>[^".]+\\.[^".]+)"` | keep domain [30m])))',
                 {"domain": "Domain"}, color=TEAL,
                 desc="Grouped by the last two labels. Fixed at 30 minutes: longer windows exceed Loki's 500-series limit."),
          8, 10, newrow=True)
    d.add(ltable("Top TLS destinations", f'topk(25, sum by (dest_ip, dest_port) (count_over_time({{task="suricata", node=~"$node"}} |= `"event_type":"tls"` | json dest_ip, dest_port, src_ip | __error__="" | src_ip=~"$ip" [$__range])))',
                 {"dest_ip": "Destination", "dest_port": "Port"}, color=INFO,
                 desc="Suricata's TLS log here carries no SNI, so destinations are shown by address."), 8, 10)
    d.add(ltable("Top destination ports (alerts)", f'topk(25, sum by (dest_port, proto, app_proto) (count_over_time({s} [$__range])))',
                 {"dest_port": "Port", "proto": "Proto", "app_proto": "App"}), 8, 10)

    d.row("Events", collapsed=True)
    d.add(logs("Alerts", [loki(
        f'{s} | line_format "sev{{{{.alert_severity}}}} [{{{{.alert_category}}}}] {{{{.alert_signature}}}} | {{{{.src_ip}}}}:{{{{.src_port}}}} -> {{{{.dest_ip}}}}:{{{{.dest_port}}}} {{{{.proto}}}} {{{{.alert_action}}}}"')]), 24, 12)
    d.add(logs("Anomalies and engine messages", [loki(
        '{task="suricata", node=~"$node"} != `"event_type":"alert"` != `"event_type":"dns"` != `"event_type":"tls"` != `"event_type":"stats"` != `"event_type":"ssh"`')]),
        24, 8, newrow=True)
    return d


def crowdsec_dash():
    d = sec_dash("homelab-crowdsec", "CrowdSec", "Log-based IP reputation: what CrowdSec reads, which scenarios fire and what it bans.")
    d.add(health("LAPI", [prom('max(up{job="crowdsec"}) or vector(0)')], thr((None, BAD), (1, GOOD)),
                 mappings=VALUE_MAP_UP), 4, 4)
    d.add(stat("Active decisions", [prom('sum(cs_active_decisions) or vector(0)')], "short", FIXED(INFO), decimals=0), 4, 4)
    d.add(stat("Alerts", [prom('sum(cs_alerts) or vector(0)')], "short", FIXED(ACCENT), decimals=0,
               desc="Alerts recorded by the LAPI, by reason."), 4, 4)
    d.add(lstat("Bans in range", f'sum(count_over_time({BANS} [$__range])) or vector(0)', FIXED(BAD)), 4, 4)
    d.add(stat("Lines parsed/s", [prom('sum(rate(cs_parser_hits_ok_total[5m])) or vector(0)')], "short", FIXED(TEAL),
               decimals=2), 4, 4)
    d.add(stat("Scenario overflows", [prom('sum(increase(cs_bucket_overflowed_total[$__range])) or vector(0)', instant=True)],
               "short", FIXED(WARN), graph=False, decimals=0), 4, 4)

    d.add(timeseries("Active decisions", [prom('sum by (reason, origin, action) (cs_active_decisions)', "{{origin}} {{reason}} {{action}}")],
                     "short", fill=25, stack=True, legend_place="right", legend_calcs=("lastNotNull",)), 12, 8, newrow=True)
    d.add(lbars("Bans by scenario (log)", [loki(f'sum by (scenario) (count_over_time({BANS} [$__auto]))', "{{scenario}}")]), 12, 8)
    d.add(timeseries("Acquisition: lines read by source", [prom(
        'sum by (source, type) (rate({__name__=~"cs_.*source_hits_total"}[$__rate_interval]))', "{{type}} {{source}}")],
        "ops", fill=10, legend_place="right", legend_calcs=("mean",)), 12, 8, newrow=True)
    d.add(timeseries("Parser hits (ok vs ko)", [
        prom('sum(rate(cs_parser_hits_ok_total[$__rate_interval]))', "ok"),
        prom('sum(rate(cs_parser_hits_ko_total[$__rate_interval])) or vector(0)', "ko", "B")],
        "ops", fill=12, overrides=[series_color("ok", GOOD), series_color("ko", HIGH)]), 12, 8)
    d.add(bars("Scenario overflows", [prom('sum by (name) (increase(cs_bucket_overflowed_total[$__rate_interval]))', "{{name}}")],
               unit="short"), 12, 8, newrow=True)
    d.add(timeseries("LAPI requests", [
        prom('sum by (route) (rate(cs_lapi_route_requests_total[$__rate_interval]))', "{{route}}"),
        prom('sum by (bouncer) (rate(cs_lapi_bouncer_requests_total[$__rate_interval]))', "bouncer {{bouncer}}", "B")],
        "reqps", fill=0, legend_place="right", legend_calcs=("mean",)), 12, 8)

    d.row("Bans")
    d.add(ltable("Banned IPs", f'topk(50, sum by (ip, scenario) (count_over_time({BANS} [$__range])))',
                 {"ip": "IP", "scenario": "Scenario"}, value="Bans", color=BAD), 12, 10)
    d.add(table("Active decisions by reason", [prom('sum by (reason, origin, action) (cs_active_decisions)', instant=True, fmt="table")],
                transformations=[{"id": "organize", "options": {"excludeByName": {"Time": True},
                                                               "renameByName": {"reason": "Reason", "origin": "Origin",
                                                                                "action": "Action", "Value": "Decisions"}}}],
                overrides=[col("Decisions", "short", width=120,
                               cell={"type": "gauge", "mode": "basic", "valueDisplayMode": "text"},
                               color={"mode": "fixed", "fixedColor": INFO})],
                sort=[{"displayName": "Decisions", "desc": True}]), 12, 10)
    d.row("Logs", collapsed=True)
    d.add(logs("Decisions and alerts", [loki('{task="crowdsec"} |~ "(?i)performed|ban on ip|decision|alert"')]), 24, 10)
    d.add(logs("CrowdSec log (health checks hidden)", [loki('{task="crowdsec"} != "GET /health" != "/v1/heartbeat"')]), 24, 10, newrow=True)
    return d


def wazuh_dash():
    v = [var_text("wazuh_task", "Wazuh alerts task (regex)", "wazuh-alerts"),
         var_text("search", "Search (regex)", "")]
    d = sec_dash("homelab-wazuh", "Wazuh", "Host intrusion detection: Wazuh manager alerts by level, rule and agent.",
                 variables=v)
    w = f'{WAZUH} |~ "(?i)$search"'
    d.add(lstat("Alerts", f'sum(count_over_time({w} [$__range])) or vector(0)'), 4, 4)
    d.add(health("Level 12+", [loki(f'sum(count_over_time({w} | rule_level >= 12 [$__range])) or vector(0)', instant=True)],
                 COUNT_THR(1, 1), ds=LOKI, unit="short", decimals=0), 4, 4)
    d.add(lstat("Level 7-11", f'sum(count_over_time({w} | rule_level >= 7 | rule_level < 12 [$__range])) or vector(0)',
                COUNT_THR(20, 100)), 4, 4)
    d.add(lstat("Agents reporting", f'count(sum by (agent_name) (count_over_time({w} [$__range]))) or vector(0)', FIXED(TEAL)), 4, 4)
    d.add(lstat("Auth failures", f'sum(count_over_time({w} |~ "authentication_failed|authentication_failures" [$__range])) or vector(0)',
                COUNT_THR(10, 100)), 4, 4)
    d.add(lstat("Integrity changes", f'sum(count_over_time({w} |~ "\\"syscheck\\"" [$__range])) or vector(0)',
                FIXED(ACCENT), "File integrity monitoring (syscheck) events."), 4, 4)

    d.add(lbars("Alerts by level", [loki(f'sum by (rule_level) (count_over_time({w} [$__auto]))', "level {{rule_level}}")],
                LEVEL_COLORS), 12, 8, newrow=True)
    d.add(lbars("Alerts by agent", [loki(f'sum by (agent_name) (count_over_time({w} [$__auto]))', "{{agent_name}}")],
                nodes=True), 12, 8)

    d.row("Top")
    d.add(ltable("Top rules", f'topk(25, sum by (rule_id, rule_level, rule_description) (count_over_time({w} [$__range])))',
                 {"rule_id": "Rule", "rule_level": "Level", "rule_description": "Description"},
                 overrides=[col("Level", cell=COLOR_TXT, width=60, thresholds=thr((None, GOOD), (7, HIGH), (12, BAD))),
                            col("Rule", width=70)], color=HIGH), 14, 10)
    d.add(ltable("Top agents", f'topk(25, sum by (agent_name) (count_over_time({w} | rule_level >= 7 [$__range])))',
                 {"agent_name": "Agent"}, desc="Alerts at level 7 or higher.", color=TEAL), 5, 10)
    d.add(ltable("Top source IPs", f'topk(25, sum by (data_srcip) (count_over_time({w} | data_srcip!="" [$__range])))',
                 {"data_srcip": "Source IP"}, color=BAD), 5, 10)

    d.row("Events", collapsed=True)
    d.add(logs("Level 7+ alerts", [loki(
        f'{w} | rule_level >= 7 | line_format "[{{{{.rule_level}}}}] {{{{.agent_name}}}}: {{{{.rule_description}}}} (rule {{{{.rule_id}}}})"')]), 24, 12)
    d.add(logs("All alerts (raw)", [loki(w)]), 24, 10, newrow=True)
    return d


def adguard_dash():
    d = sec_dash("homelab-adguard", "AdGuard",
                 "DNS filtering from the AdGuard exporter, one AdGuard instance per node.")
    q = 'sum(adguard_queries)'
    b = 'sum(adguard_queries_blocked)'
    d.add(health("Exporters", [prom('count(up{job="adguard"} == 1) or vector(0)')], thr((None, BAD), (3, GOOD)),
                 unit="suffix: / 3", decimals=0), 4, 4)
    d.add(health("Protection", [prom('min(adguard_protection_enabled)')], thr((None, BAD), (1, GOOD)),
                 "OFF if any instance has filtering disabled.", OK_MAP("ON", "OFF")), 4, 4)
    d.add(stat("Queries", [prom(q)], "short", FIXED(INFO), decimals=0, desc="AdGuard's own rolling window."), 4, 4)
    d.add(stat("Blocked", [prom(b)], "short", FIXED(HIGH), decimals=0), 4, 4)
    d.add(stat("Blocked %", [prom(f'100 * {b} / {q}')], "percent", FIXED(TEAL), decimals=1), 4, 4)
    d.add(stat("Avg processing", [prom('max(adguard_avg_processing_time_seconds)')], "s",
               thr((None, GOOD), (0.05, WARN), (0.2, BAD)), decimals=3), 4, 4)

    d.add(timeseries("Queries vs blocked", [prom(q, "queries"), prom(b, "blocked", "B")], "short", fill=18,
                     overrides=[series_color("queries", INFO), series_color("blocked", HIGH)]), 12, 8, newrow=True)
    d.add(timeseries("Blocked %", [prom(f'100 * {b} / {q}', "blocked %")], "percent", fill=25,
                     overrides=[series_color("blocked %", TEAL)]), 6, 8)
    d.add(donut("Queries per instance", [prom('sum by (node) (adguard_queries)', "{{node}}", instant=True)],
                overrides=[series_color(n, c) for n, c in NODE_COLORS.items()]), 6, 8)

    d.add(topn("Top blocked domains", [prom('topk(15, max by (domain) (adguard_top_blocked_domains))', "{{domain}}", instant=True)],
               color=HIGH, scheme="YlRd"), 8, 10, newrow=True)
    d.add(topn("Top queried domains", [prom('topk(15, max by (domain) (adguard_top_queried_domains))', "{{domain}}", instant=True)],
               color=INFO, scheme="BlPu"), 8, 10)
    d.add(topn("Top clients", [prom('topk(15, max by (client) (adguard_top_clients))', "{{client}}", instant=True)],
               color=TEAL, scheme="BlYlRd"), 8, 10)
    d.add(timeseries("Query types", [prom('sum by (type) (adguard_query_types)', "{{type}}")], "short", fill=25,
                     stack=True, legend_place="right", legend_calcs=("lastNotNull",)), 12, 8, newrow=True)
    d.add(timeseries("Upstream response time", [prom('max by (upstream) (adguard_top_upstreams_avg_response_time_seconds)', "{{upstream}}")],
                     "s", fill=8, legend_place="right", legend_calcs=("mean",)), 12, 8)
    d.row("Logs", collapsed=True)
    d.add(logs("AdGuard logs", [loki('{task=~"adguard.*"}')]), 24, 10)
    return d


def traefik_access():
    v = [var_loki_label("node", "node", "Node"), var_text("host", "Host (regex)", ".*")]
    d = sec_dash("homelab-traefik-access", "Traefik Access",
                 "Per-request access logs: who is hitting which host, status codes and scanner probes.", variables=v)
    t = TRAEFIK
    d.add(lstat("Requests", f'sum(count_over_time({t} [$__range])) or vector(0)'), 4, 4)
    d.add(lstat("4xx", f'sum(count_over_time({t} | DownstreamStatus >= 400 | DownstreamStatus < 500 [$__range])) or vector(0)',
                FIXED(WARN)), 4, 4)
    d.add(lstat("5xx", f'sum(count_over_time({t} | DownstreamStatus >= 500 [$__range])) or vector(0)', COUNT_THR(1, 50)), 4, 4)
    d.add(lstat("Unique clients", f'count(sum by (ClientHost) (count_over_time({t} [$__range]))) or vector(0)', FIXED(TEAL)), 4, 4)
    d.add(lstat("Suspicious path probes", f'sum(count_over_time({t} | RequestPath=~{SUSPICIOUS} [$__range])) or vector(0)',
                COUNT_THR(50, 500)), 4, 4)
    d.add(stat("p95 duration", [loki(
        f'quantile_over_time(0.95, {t} | unwrap Duration | __error__="" [$__range]) by ()', instant=True)],
        "ns", thr((None, GOOD), (5e8, WARN), (2e9, BAD)), ds=LOKI, decimals=0, graph=False), 4, 4)

    d.add(lbars("Requests by status", [loki(f'sum by (DownstreamStatus) (count_over_time({t} [$__auto]))', "{{DownstreamStatus}}")],
                STATUS_COLORS), 12, 8, newrow=True)
    d.add(lbars("Requests by host", [loki(f'topk(10, sum by (RequestHost) (count_over_time({t} [$__auto])))', "{{RequestHost}}")],
                legend_place="right"), 12, 8)
    d.add(lbars("4xx / 5xx by host", [loki(
        f'sum by (RequestHost, DownstreamStatus) (count_over_time({t} | DownstreamStatus >= 400 [$__auto]))',
        "{{RequestHost}} {{DownstreamStatus}}")], legend_place="right"), 12, 8, newrow=True)
    d.add(lbars("Suspicious path probes by client", [loki(
        f'topk(10, sum by (ClientHost) (count_over_time({t} | RequestPath=~{SUSPICIOUS} [$__auto])))', "{{ClientHost}}")],
        legend_place="right"), 12, 8)

    d.row("Top")
    d.add(ltable("Top client IPs", f'topk(25, sum by (ClientHost) (count_over_time({t} [$__range])))',
                 {"ClientHost": "Client"}, value="Requests", color=INFO), 6, 10)
    d.add(ltable("Clients with most 4xx/5xx", f'topk(25, sum by (ClientHost, RequestHost) (count_over_time({t} | DownstreamStatus >= 400 [$__range])))',
                 {"ClientHost": "Client", "RequestHost": "Host"}, value="Errors", color=WARN), 9, 10)
    d.add(ltable("Suspicious paths", f'topk(25, sum by (ClientHost, RequestPath) (count_over_time({t} | RequestPath=~{SUSPICIOUS} [$__range])))',
                 {"ClientHost": "Client", "RequestPath": "Path"}, value="Hits", color=BAD), 9, 10)
    d.add(ltable("Top 404 paths (last 15 min)", f'topk(25, sum by (RequestHost, RequestPath) (count_over_time({t} | DownstreamStatus = 404 | keep RequestHost, RequestPath [15m])))',
                 {"RequestHost": "Host", "RequestPath": "Path"}, value="404s", color=WARN,
                 desc="Fixed at 15 minutes: scanners request hundreds of unique paths, and longer windows exceed Loki's 500-series limit."),
          12, 10, newrow=True)
    d.add(barchart("Methods", [loki(f'sum by (RequestMethod) (count_over_time({t} [$__range]))', instant=True)],
                   "RequestMethod", {"RequestMethod": "Method"}, color=INFO), 12, 10)

    d.row("Requests", collapsed=True)
    fmt = ' | line_format "{{.DownstreamStatus}} {{.RequestMethod}} {{.RequestHost}}{{.RequestPath}} from {{.ClientHost}}"'
    d.add(logs("Errors (4xx / 5xx)", [loki(f'{t} | DownstreamStatus >= 400{fmt}')]), 12, 12)
    d.add(logs("Suspicious path probes", [loki(f'{t} | RequestPath=~{SUSPICIOUS}{fmt}')]), 12, 12)
    return d


DASHES = {
    "Homelab/command-center.json": command_center,
    "Infrastructure/nodes.json": nodes,
    "Infrastructure/nomad-cluster.json": nomad_cluster,
    "Infrastructure/nomad-workloads.json": nomad_workloads,
    "Infrastructure/traefik.json": traefik,
    "Infrastructure/power.json": power,
    "Services/authentik.json": authentik,
    "Observability/logs.json": logs_dash,
    "Observability/monitoring-stack.json": monitoring_stack,
    "Security/security-overview.json": security_overview,
    "Security/falco.json": falco_dash,
    "Security/suricata.json": suricata_dash,
    "Security/crowdsec.json": crowdsec_dash,
    "Security/wazuh.json": wazuh_dash,
    "Security/adguard.json": adguard_dash,
    "Security/traefik-access.json": traefik_access,
}


def clean(o):
    if isinstance(o, dict):
        return {k: clean(v) for k, v in o.items() if v is not None}
    if isinstance(o, list):
        return [clean(v) for v in o]
    return o


# ================================================================ alert rules
# Each rule: instant query A plus threshold C on A. Labels on A become alert labels.
# severity=critical pushes to the phone (repeats every 6h); warnings go to the homelab-info
# ntfy topic only. See alerting/policies.yaml.

def rule(uid, title, expr, op, value, for_, severity, summary, description, ds="prom",
         no_data="OK", exec_err="Error", lookback=600, labels=None):
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
            "labels": {"severity": severity, **(labels or {})},
            "annotations": {"summary": summary, "description": description}}


V = "{{ humanize $values.A.Value }}"
VP = '{{ printf "%.1f" $values.A.Value }}'
N = "{{ $labels.node }}"
J = "{{ $labels.exported_job }}"
T = "{{ $labels.task }}"
TG = "{{ $labels.task_group }}"
BACKUP_RSS = 'nomad_client_allocs_memory_rss{parent_id=~".+-backup"}'
SEC = {"category": "security"}
# Known benign: truenas-alerts and the backup jobs install jq/curl/rclone at runtime,
# flaresolverr unpacks chromedriver, dockerd opens the hosts' package manager logs.
FALCO_NOISE = ('(rule!="Drop and execute new binary in container" '
               'or output_fields_container_name!~"forward-.*|flaresolverr-.*|.*-backup-.*") '
               '| (rule!="Clear Log Activities" or output_fields_proc_name!="dockerd")')

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
        rule("nomad-raft-peers", "Nomad raft peers missing", 'max(last_over_time(nomad_raft_peers[1d]))', "lt", 3,
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
        rule("cloudflared-down", "Cloudflare Tunnel down",
             'sum(cloudflared_tunnel_ha_connections) or vector(0)', "lt", 1, "2m", "critical",
             "Cloudflare Tunnel has no connections",
             "No cloudflared connector is connected to Cloudflare, so every public site is unreachable. "
             "Check the cloudflared job and the cloudflare/tunnel/token key."),
        rule("cloudflared-degraded", "Cloudflare Tunnel degraded",
             'count(cloudflared_tunnel_ha_connections > 0) or vector(0)', "lt", 2, "5m", "warning",
             "Only {{ printf \"%.0f\" $values.A.Value }} cloudflared connector(s) connected",
             "Fewer than 2 of the 3 nodes have a working tunnel connector. Public sites still work, "
             "but one more failure takes them down."),
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
             'up{job!~"node-exporters|nomad_metrics|traefik|prometheus|crowdsec|adguard"}', "lt", 1, "5m", "warning",
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
    ]),    ("security", "1m", [
        rule("falco-critical", "Falco critical event", 'sum by (rule, node, container) (count_over_time('
             f'{FALCO_ALL} | priority=~"Emergency|Alert|Critical" | {FALCO_NOISE} '
             '| label_format container="{{ .output_fields_container_name }}" [5m]))',
             "gt", 0, "0s", "critical",
             "Falco: {{ $labels.rule }} on {{ $labels.node }} ({{ $labels.container }})",
             f"{V} event(s) in 5 minutes. Open the Falco dashboard for the process, user and command line.",
             ds="loki", lookback=300, labels=SEC),
        rule("falco-warning-burst", "Falco warning burst", 'sum by (rule, node) (count_over_time('
             f'{FALCO_ALL} | priority=~"Error|Warning" | {FALCO_NOISE} [10m]))',
             "gt", 5, "0s", "warning",
             "Falco: {{ $labels.rule }} fired " + V + " times on {{ $labels.node }}",
             "More than 5 Error or Warning events from one rule in 10 minutes.", ds="loki", labels=SEC),
        rule("suricata-severity-1", "Suricata high severity alert", 'sum by (alert_signature, src_ip, dest_ip) (count_over_time('
             f'{SURI_ALL} | alert_severity="1" | alert_signature!~"ET (P2P|INFO) .*" [5m]))',
             "gt", 0, "0s", "critical",
             "Suricata: {{ $labels.alert_signature }}",
             "{{ $labels.src_ip }} -> {{ $labels.dest_ip }}, " + V + " time(s) in 5 minutes. "
             "ET P2P (Transmission) and ET INFO (cleartext internal traffic) signatures are ignored.", ds="loki", lookback=300, labels=SEC),
        rule("suricata-severity-2-burst", "Suricata medium severity burst", 'sum by (alert_category) (count_over_time('
             f'{SURI_ALL} | alert_severity="2" [10m]))',
             "gt", 5, "0s", "warning",
             "Suricata: " + V + " {{ $labels.alert_category }} alerts in 10m",
             "Severity 2 alerts above 5 in 10 minutes. The Suricata dashboard lists the sources.", ds="loki", labels=SEC),
        rule("suricata-capture-drops", "Suricata dropping packets",
             f'100 * sum by (node) (sum_over_time({SURI_STATS_ALL} d="stats.capture.kernel_drops_delta" | unwrap d | __error__="" [30m])) '
             f'/ sum by (node) (sum_over_time({SURI_STATS_ALL} p="stats.capture.kernel_packets_delta" | unwrap p | __error__="" [30m]))',
             "gt", 5, "15m", "warning",
             f"Suricata on {N} dropping {VP}% of packets",
             "Kernel capture drops above 5% over 30 minutes. The IDS is missing traffic; it needs more CPU or threads.",
             ds="loki", lookback=1800, labels=SEC),
        rule("crowdsec-ban", "CrowdSec banned an IP", f'sum by (ip, scenario) (count_over_time({BANS} [5m]))',
             "gt", 0, "0s", "warning",
             "CrowdSec banned {{ $labels.ip }}",
             "Reason: {{ $labels.scenario }}. Informational: the ban is already enforced by the bouncers.",
             ds="loki", lookback=300, labels=SEC),
        rule("crowdsec-down", "CrowdSec down", 'max(up{job="crowdsec"}) or vector(0)', "lt", 1, "5m", "warning",
             "CrowdSec metrics are missing",
             "Prometheus cannot scrape CrowdSec (or it is not registered in Consul). Logs are not being analysed "
             "and no new bans are issued.", labels=SEC),
        rule("wazuh-critical", "Wazuh critical alert", 'sum by (rule_id, rule_description, agent_name) (count_over_time('
             f'{WAZUH_ALL} | rule_level >= 12 [5m]))',
             "gt", 0, "0s", "critical",
             "Wazuh: {{ $labels.rule_description }} on {{ $labels.agent_name }}",
             "Rule {{ $labels.rule_id }} (level 12+) fired " + V + " time(s) in 5 minutes.",
             ds="loki", lookback=300, labels=SEC),
        rule("wazuh-burst", "Wazuh alert burst", 'sum by (agent_name) (count_over_time('
             f'{WAZUH_ALL} | rule_level >= 7 | rule_level < 12 [10m]))',
             "gt", 5, "0s", "warning",
             "Wazuh: " + V + " level 7+ alerts on {{ $labels.agent_name }} in 10m",
             "Open the Wazuh dashboard for the rules involved.", ds="loki", labels=SEC),
        rule("adguard-down", "AdGuard down", 'min(up{job="adguard"})', "lt", 1, "5m", "warning",
             "AdGuard exporter is down",
             "Prometheus cannot scrape the AdGuard exporter, so AdGuard itself is likely down and DNS filtering may be off.",
             labels=SEC),
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
