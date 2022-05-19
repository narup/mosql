defmodule Pipeline.MixProject do
  use Mix.Project

  def project do
    [
      app: :pipeline,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :observer],
      mod: {MS.Pipeline.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:broadway_mongo, in_umbrella: true},
      {:core, in_umbrella: true},
      {:broadway, "~> 1.0"}
    ]
  end
end
