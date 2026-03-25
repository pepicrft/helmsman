defmodule Condukt.MixProject do
  use Mix.Project

  @version "0.6.0"
  @source_url "https://github.com/pepicrft/condukt"

  def project do
    [
      app: :condukt,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      name: "Condukt",
      description: "A framework for building AI agents in Elixir",
      source_url: @source_url,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {Condukt.Application, []},
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
      main: "Condukt",
      extras: ["README.md"],
      source_ref: @version,
      source_url: @source_url,
      groups_for_modules: [
        Core: [
          Condukt,
          Condukt.Session,
          Condukt.Message,
          Condukt.SessionStore,
          Condukt.SessionStore.Memory,
          Condukt.SessionStore.Disk,
          Condukt.Tool,
          Condukt.Telemetry
        ],
        Tools: [
          Condukt.Tools,
          Condukt.Tools.Read,
          Condukt.Tools.Bash,
          Condukt.Tools.Edit,
          Condukt.Tools.Write
        ],
        Providers: [
          Condukt.Providers.Ollama
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
