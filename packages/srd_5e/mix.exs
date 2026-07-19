defmodule Srd.MixProject do
  use Mix.Project

  @version "0.1.0"
  @repo_url "https://github.com/autodidaddict/agentic-realms"
  @package_url "https://github.com/autodidaddict/agentic-realms/tree/main/packages/srd_5e"

  def project do
    [
      app: :srd_5e,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "srd_5e",
      description: description(),
      package: package(),
      source_url: @package_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Pure-Elixir tabletop RPG game support and rules modeled on the " <>
      "System Reference Document (SRD) 5.2 with opt-in support for some 5.1 rules."
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      maintainers: ["Kevin Hoffman"],
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md .formatter.exs),
      links: %{
        "GitHub" => @package_url,
        "Changelog" => "#{@repo_url}/blob/main/packages/srd_5e/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/logo.png",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      source_url: @repo_url,
      source_ref: "main"
    ]
  end
end
