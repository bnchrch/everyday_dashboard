# EverydayDash

A Phoenix + LiveView dashboard for personal metrics. The current app ships with two cards:

- GitHub commits per day
- Strava activities per day

Each card plots the past 30 days as a trailing 7-day average and overlays the current average in the middle of the graph.

## Toolchain

This repo is pinned to the newest `Elixir 1.20` build available through `mise` on this machine right now:

- Erlang `28.4`
- Elixir `1.20.0-rc.2`

If a stable `1.20.x` release is available later, update [.mise.toml](/Users/ben/Development/repos/everyday_dash/.mise.toml) and [mix.exs](/Users/ben/Development/repos/everyday_dash/mix.exs).

## Setup

1. Install the toolchain with `mise install`.
2. Fetch deps and asset tooling with `mise exec -- mix setup`.
3. Export the API credentials below.
4. Start the server with `mise exec -- mix phx.server`.

Open [http://localhost:4000](http://localhost:4000).

## Environment

### GitHub

Required:

- `GITHUB_USERNAME`
- `GITHUB_TOKEN`

The app uses GitHub GraphQL to collect commit contributions by day.

### Strava

Required:

- `STRAVA_CLIENT_ID`
- `STRAVA_CLIENT_SECRET`
- `STRAVA_REFRESH_TOKEN`

Optional:

- `STRAVA_TOKEN_STORE_PATH`
- `DASHBOARD_REFRESH_MS`
- `DASHBOARD_GRAPH_DAYS`

The Strava refresh token is rotated and the newest token is persisted locally at `tmp/strava_tokens.json` by default so restarts keep working.

## Notes

- GitHub data is pulled from `commitContributionsByRepository`, so the card reflects commit counts rather than all contribution types.
- Strava data counts activities by day using `start_date_local`.
- The refresh worker keeps the last successful snapshot in memory and reuses it if one source errors.
