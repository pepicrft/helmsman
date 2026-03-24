defmodule Helmsman.MixProject do
  use Mix.Project

  @version "0.4.1"
  @source_url "https://github.com/pepicrft/helmsman"

  def project do
    [
      app: :helmsman,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      name: "Helmsman",
      description: "A framework for building AI agents in Elixir",
      source_url: @source_url,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {Helmsman.Application, []},
      extra_applications: [:logger]
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
      {:mimic, "~> 2.0", only: :test}
    ]
  end

  defp docs do
    [
      main: "Helmsman",
      extras: ["README.md"],
      source_ref: @version,
      source_url: @source_url,
      groups_for_modules: [
        Core: [
          Helmsman,
          Helmsman.Session,
          Helmsman.Message,
          Helmsman.SessionStore,
          Helmsman.SessionStore.Memory,
          Helmsman.SessionStore.Disk,
          Helmsman.Tool,
          Helmsman.Telemetry
        ],
        Tools: [
          Helmsman.Tools,
          Helmsman.Tools.Read,
          Helmsman.Tools.Bash,
          Helmsman.Tools.Edit,
          Helmsman.Tools.Write
        ],
        Providers: [
          Helmsman.Providers.Ollama
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
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE MIT.md)
    ]
  end

  defp aliases do
    [
      lint: ["format --check-formatted", "credo --strict", "dialyzer"]
    ]
  end
end
