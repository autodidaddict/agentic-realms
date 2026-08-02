<p align="center">
  <img src="priv/static/images/logo-wordmark.png" alt="Agentic Realms" width="420" />
</p>

<p align="center">
  <a href="https://github.com/autodidaddict/agentic-realms/actions/workflows/ci.yml">
    <img src="https://github.com/autodidaddict/agentic-realms/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI" />
  </a>
</p>

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

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
