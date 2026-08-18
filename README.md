# DockBar

A macOS menubar app that shows live deploy status for your self-hosted
[Dokploy](https://dokploy.com) server — across every organization on it.

> DockBar is an unofficial community project and is not affiliated with or endorsed by
> Dokploy Technology, Inc. The Dokploy logo is from the
> [Dokploy project](https://github.com/Dokploy/dokploy) (Apache-2.0).

## What it does

- **Idle**: the Dokploy logo sits quietly in your menubar (it becomes a warning triangle
  if any service is in an `error` state).
- **Deploying**: a spinning icon plus "`<app name>` deploying" ("N deploying" if several at
  once). Polling speeds up to every 5 seconds while a deploy is in flight, so the spinner
  appears and clears promptly.
- **Click**: a menu with anything currently deploying, plus the last 10 deployments across
  all your organizations (✅ done / ❌ error / 🔄 running, with relative timestamps).
  Clicking an entry opens that service in the Dokploy dashboard; hover a row for the
  deployment title.

Works with both **applications** and **Docker Compose** services, on any Dokploy instance
you have API access to.

## Install

No prebuilt binaries yet (an unsigned download would just fight Gatekeeper), so build from
source — it takes a few seconds and needs only the Xcode Command Line Tools
(`xcode-select --install`):

```bash
git clone https://github.com/noahcoffey/DockBar.git
cd DockBar
./build.sh            # builds DockBar.app in this directory
./build.sh --install  # also copies it to /Applications
open DockBar.app
```

To launch at login: System Settings → General → Login Items → add DockBar.

## Setup

On first launch DockBar creates a starter config at
`~/Library/Application Support/DockBar/config.json` and opens it for you:

```json
{
  "serverUrl": "https://dokploy.example.com",
  "pollSeconds": 30,
  "orgs": [
    { "name": "My Org", "apiKey": "..." }
  ]
}
```

- **serverUrl** — your Dokploy instance, no trailing slash.
- **orgs** — Dokploy API keys are scoped to a single organization, so add one entry per
  org you want to watch (generate keys in the Dokploy dashboard's settings, once per org).
  A single-org setup is just one entry.
- **pollSeconds** — idle polling interval (optional, default 30).

Fill it in, then choose **Reload Config** from the DockBar menu. The file is created with
`600` permissions; your keys never leave your machine except to talk to your own server.

## How it works

Each poll cycle calls `GET /api/project.all` per organization; Dokploy sets each service's
`applicationStatus`/`composeStatus` to `running` while a deployment is building, which is
what drives the spinner. Deployment history comes from `GET /api/deployment.all` (and
`deployment.allByCompose` for compose services), merged across all orgs and sorted by date.
All UI is native AppKit — no Electron, no dependencies.

## License

MIT — see [LICENSE](LICENSE). The bundled `Resources/dokploy-icon.svg` is from the Dokploy
project, © Dokploy Technology, Inc., licensed under Apache-2.0.
