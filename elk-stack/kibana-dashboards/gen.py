"""Generate Kibana saved objects (ndjson) for the home lab log dashboards."""
import json, sys

def count(label="Events", kql=None):
    c = {"label": label, "customLabel": True, "dataType": "number", "operationType": "count",
         "isBucketed": False, "scale": "ratio", "sourceField": "___records___",
         "params": {"emptyAsNull": False}}
    if kql:
        c["filter"] = {"query": kql, "language": "kuery"}
    return c

def date_hist():
    return {"label": "@timestamp", "dataType": "date", "operationType": "date_histogram",
            "sourceField": "@timestamp", "isBucketed": True, "scale": "interval",
            "params": {"interval": "auto", "includeEmptyRows": True, "dropPartials": False}}

def terms(field, size, order_col, label=None, other=True):
    return {"label": label or field, "customLabel": bool(label), "dataType": "string",
            "operationType": "terms", "sourceField": field, "isBucketed": True, "scale": "ordinal",
            "params": {"size": size, "orderBy": {"type": "column", "columnId": order_col},
                       "orderDirection": "desc", "otherBucket": other, "missingBucket": False,
                       "parentFormat": {"id": "terms"}}}

def filters(label, items):
    return {"label": label, "customLabel": True, "dataType": "string", "operationType": "filters",
            "isBucketed": True, "scale": "ordinal",
            "params": {"filters": [{"input": {"query": q, "language": "kuery"}, "label": l} for l, q in items]}}

def lens(oid, title, dv, vtype, columns, order, vis, kql=""):
    return {"type": "lens", "id": oid,
            "attributes": {"title": title, "description": "", "visualizationType": vtype,
                           "state": {"datasourceStates": {"formBased": {"layers": {"L1": {
                               "columns": columns, "columnOrder": order, "incompleteColumns": {}}}}},
                                     "visualization": vis,
                                     "query": {"query": kql, "language": "kuery"}, "filters": [],
                                     "adHocDataViews": {}, "internalReferences": []}},
            "references": [{"type": "index-pattern", "id": dv, "name": "indexpattern-datasource-layer-L1"}]}

def metric(oid, title, dv, label, kql=None):
    vis = {"layerId": "L1", "layerType": "data", "metricAccessor": "m"}
    return lens(oid, title, dv, "lnsMetric", {"m": count(label, kql)}, ["m"], vis)

def xy(oid, title, dv, split_col, series="bar_stacked", kql="", legend="right"):
    cols = {"t": date_hist(), "c": count(), "s": split_col}
    vis = {"legend": {"isVisible": True, "position": legend}, "valueLabels": "hide",
           "preferredSeriesType": series, "fittingFunction": "None",
           "layers": [{"layerId": "L1", "layerType": "data", "seriesType": series,
                       "xAccessor": "t", "splitAccessor": "s", "accessors": ["c"]}]}
    return lens(oid, title, dv, "lnsXY", cols, ["s", "t", "c"], vis, kql)

def table(oid, title, dv, field, size, kql="", label="Program"):
    cols = {"s": terms(field, size, "c", label=label, other=False), "c": count()}
    vis = {"layerId": "L1", "layerType": "data",
           "columns": [{"columnId": "s"}, {"columnId": "c"}]}
    return lens(oid, title, dv, "lnsDatatable", cols, ["s", "c"], vis, kql)

def search(oid, title, dv, kql, columns):
    ss = {"query": {"query": kql, "language": "kuery"}, "filter": [],
          "indexRefName": "kibanaSavedObjectMeta.searchSourceJSON.index"}
    return {"type": "search", "id": oid,
            "attributes": {"title": title, "description": "",
                           "tabs": [{"id": oid + "-tab", "label": title, "attributes": {
                               "columns": columns, "sort": [["@timestamp", "desc"]],
                               "kibanaSavedObjectMeta": {"searchSourceJSON": json.dumps(ss)}}}]},
            "references": [{"name": "kibanaSavedObjectMeta.searchSourceJSON.index",
                            "type": "index-pattern", "id": dv}]}

def dashboard(oid, title, desc, panels, kql=""):
    pj, refs = [], []
    for i, (obj, x, y, w, h) in enumerate(panels, 1):
        p = f"p{i}"
        pj.append({"type": obj["type"], "panelIndex": p, "panelRefName": f"panel_{p}",
                   "gridData": {"x": x, "y": y, "w": w, "h": h, "i": p}, "embeddableConfig": {}})
        refs.append({"name": f"{p}:panel_{p}", "type": obj["type"], "id": obj["id"]})
    ss = {"query": {"query": kql, "language": "kuery"}, "filter": []}
    return {"type": "dashboard", "id": oid,
            "attributes": {"title": title, "description": desc, "panelsJSON": json.dumps(pj),
                           "optionsJSON": json.dumps({"useMargins": True, "syncColors": True,
                                                      "syncCursor": True, "syncTooltips": True,
                                                      "hidePanelTitles": False}),
                           "timeRestore": True, "timeFrom": "now-24h", "timeTo": "now",
                           "refreshInterval": {"pause": False, "value": 60000},
                           "kibanaSavedObjectMeta": {"searchSourceJSON": json.dumps(ss)}},
            "references": refs}

SEV = [("Error or worse", "log.syslog.priority <= 3"), ("Warning", "log.syslog.priority : 4"),
       ("Notice / info", "log.syslog.priority >= 5 and log.syslog.priority <= 6"),
       ("Debug", "log.syslog.priority : 7")]

def hosts():
    dv, base = "filebeat-*", "event.module : system"
    q = lambda k: f"{base} and ({k})"
    objs = [
        metric("homelab-hosts-m-events", "Events", dv, "System log events", base),
        metric("homelab-hosts-m-errors", "Errors", dv, "Error or worse", q("log.syslog.priority <= 3")),
        metric("homelab-hosts-m-warn", "Warnings", dv, "Warnings", q("log.syslog.priority : 4")),
        metric("homelab-hosts-m-sshfail", "Failed SSH logins", dv, "Failed SSH logins",
               q("event.action : ssh_login and event.outcome : failure")),
        xy("homelab-hosts-by-host", "Events by host", dv, terms("host.name", 10, "c", "Host"), kql=base),
        xy("homelab-hosts-by-sev", "Events by severity", dv, filters("Severity", SEV), kql=base),
        table("homelab-hosts-top-apps", "Busiest programs", dv, "log.syslog.appname", 12, base),
        table("homelab-hosts-top-err-apps", "Programs logging errors", dv, "log.syslog.appname", 12,
             q("log.syslog.priority <= 3")),
        xy("homelab-hosts-ssh", "SSH logins", dv, terms("event.outcome", 3, "c", "Outcome"),
           series="bar_stacked", kql=q("event.action : ssh_login")),
        search("homelab-hosts-s-errors", "Host errors and warnings", dv, q("log.syslog.priority <= 4"),
               ["host.name", "log.syslog.appname", "log.syslog.priority", "message"]),
        search("homelab-hosts-s-auth", "Auth log", dv, "event.dataset : system.auth",
               ["host.name", "log.syslog.appname", "user.name", "source.ip", "event.outcome", "message"]),
    ]
    o = {x["id"]: x for x in objs}
    layout = [
        (o["homelab-hosts-m-events"], 0, 0, 12, 6), (o["homelab-hosts-m-errors"], 12, 0, 12, 6),
        (o["homelab-hosts-m-warn"], 24, 0, 12, 6), (o["homelab-hosts-m-sshfail"], 36, 0, 12, 6),
        (o["homelab-hosts-by-host"], 0, 6, 24, 12), (o["homelab-hosts-by-sev"], 24, 6, 24, 12),
        (o["homelab-hosts-top-apps"], 0, 18, 16, 14), (o["homelab-hosts-top-err-apps"], 16, 18, 16, 14),
        (o["homelab-hosts-ssh"], 32, 18, 16, 14),
        (o["homelab-hosts-s-errors"], 0, 32, 48, 16), (o["homelab-hosts-s-auth"], 0, 48, 48, 14),
    ]
    d = dashboard("homelab-hosts", "Home lab: host system logs",
                  "Journald system logs shipped by Filebeat (system module). Filter by host in the query bar, e.g. host.name : blackbird.",
                  layout)
    return objs + [d]

def containers():
    # message is match_only_text (case-insensitive tokens); a leading wildcard would also hit "stderr"
    ERRQ = "message : error or message : errors"
    dv = "docker-container-logs"
    err = "level : 3 or stream : stderr"
    objs = [
        metric("homelab-ctr-m-lines", "Log lines", dv, "Container log lines"),
        metric("homelab-ctr-m-stderr", "stderr lines", dv, "stderr lines", err),
        metric("homelab-ctr-m-errword", "Lines mentioning error", dv, "Lines mentioning error",
               ERRQ),
        xy("homelab-ctr-by-ctr", "Log volume by container", dv, terms("container.name", 10, "c", "Container")),
        xy("homelab-ctr-stderr-by-ctr", "stderr by container", dv, terms("container.name", 10, "c", "Container"),
           kql=err),
        table("homelab-ctr-top", "Noisiest containers", dv, "container.name", 15, label="Container"),
        table("homelab-ctr-top-err", "Containers mentioning errors", dv, "container.name", 15,
             ERRQ, label="Container"),
        search("homelab-ctr-s-stderr", "Container stderr", dv, err, ["container.name", "host.name", "message"]),
    ]
    o = {x["id"]: x for x in objs}
    layout = [
        (o["homelab-ctr-m-lines"], 0, 0, 16, 6), (o["homelab-ctr-m-stderr"], 16, 0, 16, 6),
        (o["homelab-ctr-m-errword"], 32, 0, 16, 6),
        (o["homelab-ctr-by-ctr"], 0, 6, 24, 13), (o["homelab-ctr-stderr-by-ctr"], 24, 6, 24, 13),
        (o["homelab-ctr-top"], 0, 19, 24, 15), (o["homelab-ctr-top-err"], 24, 19, 24, 15),
        (o["homelab-ctr-s-stderr"], 0, 34, 48, 18),
    ]
    d = dashboard("homelab-containers", "Home lab: container logs",
                  "Docker container logs (GELF via Logstash, json-file via Filebeat). Filter in the query bar, e.g. container.name : frigate.",
                  layout)
    return objs + [d]

which = sys.argv[1]
VERS = {"lens": "10.1.0", "dashboard": "10.3.0", "search": "10.13.0"}
for obj in {"hosts": hosts, "containers": containers}[which]():
    obj["coreMigrationVersion"] = "8.8.0"
    obj["typeMigrationVersion"] = VERS[obj["type"]]
    print(json.dumps(obj))
