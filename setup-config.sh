#!/bin/bash
# OPTIONAL convenience for users of the dokploy-mcp Claude MCP server: generates
# ~/Library/Application Support/DockBar/config.json from the dokploy-* MCP server
# entries in ~/.claude.json. Everyone else: just launch DockBar once and edit the
# starter config it creates.
# Usage: ./setup-config.sh [--force]
set -euo pipefail

CONFIG_DIR="$HOME/Library/Application Support/DockBar"
CONFIG="$CONFIG_DIR/config.json"

if [[ -f "$CONFIG" && "${1:-}" != "--force" ]]; then
    echo "Config already exists at $CONFIG (use --force to overwrite)"
    exit 0
fi

mkdir -p "$CONFIG_DIR"
python3 - "$CONFIG" <<'EOF'
import json, os, sys

cfg = json.load(open(os.path.expanduser("~/.claude.json")))
orgs, server = [], None
for name, s in cfg.get("mcpServers", {}).items():
    if not name.startswith("dokploy"):
        continue
    env = s.get("env", {})
    url, key = env.get("DOKPLOY_URL"), env.get("DOKPLOY_API_KEY")
    if not url or not key:
        continue
    server = url.removesuffix("/api").rstrip("/")
    org_name = name.removeprefix("dokploy-").removesuffix("-mcp") or name
    orgs.append({"name": org_name.replace("-", " ").title(), "apiKey": key})

if not orgs:
    sys.exit("No dokploy MCP servers found in ~/.claude.json")

out = {"serverUrl": server, "pollSeconds": 30, "orgs": orgs}
with open(sys.argv[1], "w") as f:
    json.dump(out, f, indent=2)
print(f"Wrote {sys.argv[1]} with {len(orgs)} org(s), server {server}")
EOF
chmod 600 "$CONFIG"
