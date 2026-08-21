import sys
import yaml

with open(sys.argv[1]) as fh:
    try:
        data = yaml.safe_load(fh)
    except yaml.YAMLError:
        sys.exit(0)

if not isinstance(data, dict):
    sys.exit(0)

for svc in (data.get("services") or {}).values():
    if not isinstance(svc, dict):
        continue
    ef = svc.get("env_file")
    if ef is None:
        continue
    if isinstance(ef, str):
        ef = [ef]
    for item in ef:
        if isinstance(item, str):
            print(item)
        elif isinstance(item, dict) and item.get("path"):
            print(item["path"])
