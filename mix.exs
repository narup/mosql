defmodule Mosql.MixProject do
  use Mix.Project

  def project do
    [
      app: :mosql,
      version: "0.1.0",
      elixir: "~> 1.16.2",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      package: package(),
      aliases: aliases(),
      deps: deps(),
      description: description()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Mosql.Application, []},
      extra_applications: [:logger, :memento, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.7.12"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.20.2"},
      {:postgrex, ">= 0.17.5"},
      {:mongodb_driver, "~> 1.4.0"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.5"},
      {:finch, "~> 0.13"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:memento, "~> 0.3.2"},
      {:broadway, "~> 1.0.7"},
      {:poison, "~> 5.0"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.2"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind mosql", "esbuild mosql"],
      "assets.deploy": [
        "tailwind mosql --minify",
        "esbuild mosql --minify",
        "phx.digest"
      ]
    ]
  end

  defp package() do
    [
      name: "mosql",
      maintainers: ["Puran Singh"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/narup/mosql"}
    ]
  end

  defp description() do
    "Mosql - MongoDB to Postgres data exporter"
  end
end
