# EverydayDash

A Phoenix + LiveView dashboard for personal metrics. The app currently ships with:

- GitHub commits per day
- Strava activities per day
- Habitify mini-graphs for daily habits

GitHub and Strava plot the past 30 days as a trailing 7-day average. Habitify renders a compact 30-day completion grid from logged habit completions.

## Toolchain

This repo is pinned to the newest `Elixir 1.20` build available through `mise` on this machine right now:

- Erlang `28.4`
- Elixir `1.20.0-rc.2-otp-28`

If a stable `1.20.x` release is available later, update [.mise.toml](/Users/ben/Development/repos/everyday_dash/.mise.toml) and [mix.exs](/Users/ben/Development/repos/everyday_dash/mix.exs).

## Setup

1. Install the toolchain with `mise install`.
2. Create a local env file with `cp .env.example .env`.
3. Fill in the API credentials in `.env`.
4. Fetch deps and asset tooling with `mise exec -- mix setup`.
5. Start the server with `mise exec -- mix phx.server`.

Open [http://localhost:4000](http://localhost:4000).

`mise` loads `.env` automatically via [`.mise.toml`](/Users/ben/Development/repos/everyday_dash/.mise.toml), so `direnv` is not required for local startup.

## Environment

### GitHub

Required:

- `GITHUB_USERNAME`
- `GITHUB_TOKEN`

The app uses GitHub GraphQL to collect commit contributions by day.

### Habitify

Required:

- `HABITIFY_API_KEY`

The dashboard uses Habitify's habits and logs APIs to discover habits and derive daily completion state.

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

## Gigalixir

This repo is currently deployed on Gigalixir as:

- app: `bnchrch-everyday-dashboard`
- primary URL: [https://dash.ben.church](https://dash.ben.church)
- fallback URL: [https://bnchrch-everyday-dashboard.gigalixirapp.com](https://bnchrch-everyday-dashboard.gigalixirapp.com)

Gigalixir deploys are just git pushes. To deploy manually from this repo:

```sh
gigalixir login
gigalixir git:remote bnchrch-everyday-dashboard
git push gigalixir main
```

If you need to deploy a different local branch to production:

```sh
git push gigalixir my-branch:main
```

If a deploy includes new Ecto migrations, run them after the code deploy finishes:

```sh
gigalixir ps:migrate -a bnchrch-everyday-dashboard
```

### Custom domain

`dash.ben.church` should be configured at the DNS provider as:

- type: `CNAME`
- host: `dash`
- target: `dash.ben.church.gigalixirdns.com`

Production should keep:

- `PHX_HOST=dash.ben.church`
- `PHX_ADDITIONAL_HOSTS=bnchrch-everyday-dashboard.gigalixirapp.com`

## Production config

Gigalixir manages app config entirely through environment variables. Per the Gigalixir docs, changing config restarts the app.

Inspect the current production config:

```sh
gigalixir config -a bnchrch-everyday-dashboard
```

Set or update production env vars:

```sh
gigalixir config:set -a bnchrch-everyday-dashboard \
  GITHUB_USERNAME="bnchrch" \
  GITHUB_TOKEN="..." \
  HABITIFY_API_KEY="..." \
  STRAVA_CLIENT_ID="..." \
  STRAVA_CLIENT_SECRET="..." \
  STRAVA_REFRESH_TOKEN="..." \
  DASHBOARD_REFRESH_MS="60000" \
  PHX_HOST="dash.ben.church" \
  PHX_ADDITIONAL_HOSTS="bnchrch-everyday-dashboard.gigalixirapp.com"
```

Unset a production env var:

```sh
gigalixir config:unset -a bnchrch-everyday-dashboard KEY_NAME
```

Important production notes:

- `DATABASE_URL`, `PORT`, and `SECRET_KEY_BASE` are provided by Gigalixir and generally should not be edited manually.
- Strava refresh tokens rotate, so production should keep using the database-backed token store. If `DATABASE_URL` is present, the app automatically uses `STRAVA_TOKEN_STORE_BACKEND=database`.
- If you change the custom domain, update both DNS and the Phoenix host env vars together.

## CI/CD

GitHub Actions handles test-and-deploy from [deploy.yml](/Users/ben/Development/repos/everyday_dash/.github/workflows/deploy.yml).

Current behavior:

- runs on every push to `main`
- can also be triggered manually with `workflow_dispatch`
- runs `mix test`
- deploys by pushing `HEAD` to the Gigalixir git remote

Required GitHub Actions repository secrets:

- `GIGALIXIR_EMAIL`
- `GIGALIXIR_API_KEY`

`GIGALIXIR_EMAIL` should be URI-encoded, matching Gigalixir's CI docs.

The workflow currently deploys to:

- `GIGALIXIR_APP_NAME=bnchrch-everyday-dashboard`

If the Gigalixir app name changes, update [deploy.yml](/Users/ben/Development/repos/everyday_dash/.github/workflows/deploy.yml) before relying on CI again.

CI does not run `gigalixir ps:migrate` automatically. If a change adds or modifies migrations, push the code first and then run:

```sh
gigalixir ps:migrate -a bnchrch-everyday-dashboard
```

## Notes

- GitHub data is pulled from `commitContributionsByRepository`, so the card reflects commit counts rather than all contribution types.
- Habitify completion is derived from logged values, not the `status` endpoint, because logs were the reliable source for completed daily reps in this account.
- Strava data counts activities by day using `start_date_local`.
- The refresh worker keeps the last successful snapshot in memory and reuses it if one source errors.
