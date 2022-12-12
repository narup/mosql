defmodule MS.MixProject do
  use Mix.Project

  def project do
    [
      app: :mosql,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :memento],
      mod: {MS.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
      {:postgrex, ">= 0.0.0"},
      {:mongodb_driver, "~> 1.0.0"},
      {:broadway, "~> 1.0"},
      {:decimal, "~> 2.0"},
      {:poison, "~> 5.0"},
      {:memento, "~> 0.3.2"},
      {:rustler, "~> 0.26.0"},
      {:broadway_mongo, in_umbrella: true}
    ]
  end

  defp aliases do
    [
      test: "test --no-start"
    ]
  end
end
