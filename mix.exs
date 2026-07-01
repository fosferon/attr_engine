defmodule AttrEngine.MixProject do
  use Mix.Project

  @version "0.4.0"
  @source_url "https://github.com/fosferon/attr_engine"

  def project do
    [
      app: :attr_engine,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: @source_url,
      docs: docs(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0", optional: true},
      {:jason, "~> 1.2"},
      {:slugify, "~> 1.3"},
      {:flop, "~> 0.25", optional: true},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Schema-driven content modelling with a 4-layer config cascade, " <>
      "DAG attribute set composition, multilingual resolution, " <>
      "and pluggable HTML/envelope rendering. Built on Ecto + JSONB."
  end

  defp package do
    [
      name: "attr_engine",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Leonidas"],
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
