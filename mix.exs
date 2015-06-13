defmodule BlockingQueue.Mixfile do
  use Mix.Project

  def project do
    [app: :blocking_queue,
     version: "1.0.0",
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps,
     description: description,
     package: package]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [
      {:excheck, "~> 0.2", only: :test},
      {:triq, github: "krestenkrab/triq", only: :test},
      {:inch_ex, only: :docs}
    ]
  end

  defp description do
  """
  BlockingQueue is a simple queue implemented as a GenServer.  It has a fixed maximum length established when it is created.
  """
  end

  defp package do
    [files: ["lib", "mix.exs", "README.md", "LICENSE"],
     contributors: ["Joseph Kain"],
     licenses: ["MIT"],
     links: %{
       "github" => "https://github.com/joekain/blocking_queue"
     }]
  end
end
