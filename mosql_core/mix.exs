defmodule Mosql.MixProject do
  use Mix.Project

  def project do
    [
      app: :mosql,
      version: "0.1.0",
      elixir: "~> 1.12",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :memento],
      mod: {Mosql.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:postgrex, ">= 0.0.0"},
      {:mongodb_driver, "~> 1.0.0"},
      {:broadway, "~> 1.0"},
      {:decimal, "~> 2.0"},
      {:poison, "~> 5.0"},
      {:memento, "~> 0.3.2"},
      {:ex_doc, "> 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp description() do
    "Mosql - MongoDB to Postgres data exporter"
  end

  defp package() do
    [
      name: "mosql",
      maintainers: ["Puran Singh"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/narup/mosql"}
    ]
  end

  defp aliases do
    [
      test: "test --no-start"
    ]
  end
end
