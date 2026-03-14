defmodule Glossia.Agent.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/glossia/agent"

  def project do
    [
      app: :glossia_agent,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      name: "Glossia.Agent",
      description: "A framework for building AI agents in Elixir",
      source_url: @source_url,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Glossia.Agent.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # HTTP client
      {:req, "~> 0.5"},

      # Telemetry
      {:telemetry, "~> 1.0"},

      # Development & Testing
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.1", only: :test}
    ]
  end

  defp docs do
    [
      main: "Glossia.Agent",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url: @source_url,
      groups_for_modules: [
        Core: [
          Glossia.Agent,
          Glossia.Agent.Session,
          Glossia.Agent.Message,
          Glossia.Agent.Tool,
          Glossia.Agent.Provider,
          Glossia.Agent.Telemetry
        ],
        Tools: [
          Glossia.Agent.Tools,
          Glossia.Agent.Tools.Read,
          Glossia.Agent.Tools.Bash,
          Glossia.Agent.Tools.Edit,
          Glossia.Agent.Tools.Write
        ],
        Providers: [
          Glossia.Agent.Providers.Anthropic
        ]
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp aliases do
    [
      lint: ["format --check-formatted", "credo --strict", "dialyzer"]
    ]
  end
end
