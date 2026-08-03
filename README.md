<p align="center">
  <img src="priv/static/images/logo-wordmark.png" alt="Agentic Realms" width="420" />
</p>

<p align="center">
  <a href="https://github.com/autodidaddict/agentic-realms/actions/workflows/ci.yml">
    <img src="https://github.com/autodidaddict/agentic-realms/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI" />
  </a>
  <a href="https://github.com/autodidaddict/agentic-realms/actions/workflows/nightly.yml">
    <img src="https://github.com/autodidaddict/agentic-realms/actions/workflows/nightly.yml/badge.svg" alt="Nightly" />
  </a>
</p>

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Tests

`mix test` runs the default suite. Three tags sit outside it. `integration`
mounts the full LiveView, `cluster` starts a second BEAM node, which is global
state that leaks into everything else in the run, and `live_llm` calls the real
Anthropic API and costs tokens.

```sh
mix test --include integration

# Scoped to the one file on purpose. Starting distribution is what leaks, so
# `--include cluster` across the whole suite fails a pile of unrelated tests.
epmd -daemon
mix test --include cluster test/agenticrealms/world/cluster_singleton_test.exs

# Its own Mix project, so the root suite doesn't reach it.
cd packages/srd_5e && mix test

ANTHROPIC_API_KEY=sk-ant-... mix test --include live_llm
```

A nightly workflow runs the suite five times over, each with its own random
seed, and picks up the first three of those. `live_llm` stays out of it, since
nothing should be spending tokens on a timer. ExUnit already randomizes the seed,
so per-push CI does vary the order; it just takes one sample per push. Five a
night is what catches a test that only fails when it happens to run after some
other one.

Each seed job prints its seed as a GitHub annotation, so a failure comes back
with the command that replays it. That is enough for an ordering bug. It is not
always enough on its own: several of the failures this job has found also needed
the runner's concurrency to appear, and did not reproduce locally at any seed.
When that happens, the seed narrows it down and the rest is bisection.

It runs at 06:00 UTC, and can be triggered by hand from the Actions tab.

## Deployment

Not spec'd yet. The plan is Fly.io, but nothing has been written down and no
deployment configuration exists in the repository: no Dockerfile, no fly.toml,
no release overlay.

One thing to settle before that work starts. Several processes are meant to be
cluster singletons, placed by Horde, and the transient-region reaper among them
hard-deletes event-store streams. They only stay singletons if the nodes can
actually see each other, which needs distribution enabled and
`DNS_CLUSTER_QUERY` set. Neither is configured today, so a second machine would
quietly get its own copy of each. A single machine is fine indefinitely.

`mix cluster.check` reports which link of that chain is missing, and works
against a deployed node:

```sh
bin/agenticrealms eval 'AgenticRealms.Cluster.Check.run()'
```

Run it after the first multi-machine deploy. It exits non-zero once clustering
is configured but not working, so it can gate a deploy.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
