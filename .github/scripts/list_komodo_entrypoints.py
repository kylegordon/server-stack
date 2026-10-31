import posixpath
import sys
import tomllib

with open(sys.argv[1] if len(sys.argv) > 1 else "komodo-stacks.toml", "rb") as fh:
    data = tomllib.load(fh)

paths = set()
for stack in data.get("stack", []):
    config = stack.get("config", {})
    run_dir = config.get("run_directory")
    file_paths = config.get("file_paths")
    if not run_dir or not file_paths:
        sys.exit(f"stack {stack.get('name')!r} has no run_directory or file_paths")
    for fp in file_paths:
        paths.add("./" + posixpath.normpath(posixpath.join(run_dir, fp)))

if not paths:
    sys.exit("no stacks found")

for p in sorted(paths):
    print(p)
