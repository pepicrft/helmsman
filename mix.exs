defmodule Glossia.Agent.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/glossia/agent"

  def project do
    [
      app: :agent,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      name: "Agent",
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

  defp elixirc_paths(:test), do: ["lib"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # LLM client (supports Anthropic, OpenAI, Google, and 15+ more providers)
      {:req_llm, "~> 1.6"},

      # Command execution with child process shutdown propagation
      {:muontrap, "~> 1.7"},

      # Telemetry
      {:telemetry, "~> 1.0"},

      # Development & Testing
      {:quokka, "~> 2.12", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.1", only: :test}
    ]
  end

  defp docs do
    [
      main: "Glossia.Agent",
      extras: ["README.md"],
      source_ref: "v#{@version}",
      source_url: @source_url,
      groups_for_modules: [
        Core: [
          Glossia.Agent,
          Glossia.Agent.Session,
          Glossia.Agent.Message,
          Glossia.Agent.Tool,
          Glossia.Agent.Telemetry
        ],
        Tools: [
          Glossia.Agent.Tools,
          Glossia.Agent.Tools.Read,
          Glossia.Agent.Tools.Bash,
          Glossia.Agent.Tools.Edit,
          Glossia.Agent.Tools.Write
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
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp aliases do
    [
      lint: ["format --check-formatted", "credo --strict", "dialyzer"]
    ]
  end
end
