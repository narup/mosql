defmodule MosqlCli.MixProject do
  use Mix.Project

  def project do
    [
      app: :mosql_cli,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [main_module: MosqlCLI],

      releases: [
        mosql_cli: [
          steps: [:assemble, &Bakeware.assemble/1]
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {MosqlCLI, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:bakeware, "~> 0.2.4"}
    ]
  end
end
