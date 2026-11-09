# Home lab Kibana dashboards

`gen.py` builds the Kibana saved objects for two dashboards; `apply.sh` imports them.

| Dashboard | id | Data view |
|---|---|---|
| Home lab: host system logs | `homelab-hosts` | `filebeat-*` (Filebeat system module, journald) |
| Home lab: container logs | `homelab-containers` | `docker-container-logs` (`logs-docker-default`) |

```bash
elk-stack/kibana-dashboards/apply.sh          # both
elk-stack/kibana-dashboards/apply.sh hosts    # one
```

All objects have fixed `homelab-*` ids and are imported with overwrite, so the code here is the
source of truth: edits made in the Kibana UI are lost on the next apply. Change `gen.py` instead.

Kibana 9.5 import gotchas:
- Each object needs `coreMigrationVersion` and `typeMigrationVersion` set to the current
  versions (`VERS` in `gen.py`); without them Kibana runs old migrations and the import fails
  with a 500 ("reading 'layers'"). After a Kibana upgrade, check
  `GET /api/saved_objects/_find?type=lens&per_page=1` and bump `VERS` if needed.
- Saved searches keep columns, sort and query under `attributes.tabs[]`.
