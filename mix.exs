defmodule BlockingQueue.Mixfile do
  use Mix.Project

  def project do
    [app: :blocking_queue,
     version: "1.3.0",
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     description: description(),
     package: package()]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps() do
    [
      {:excheck, "~> 0.6", only: :test},
      {:triq, "~> 1.3", only: :test},
      {:inch_ex, github: "rrrene/inch_ex", only: [:dev, :test]},
      {:earmark, "~> 1.3.1", only: :dev},
      {:ex_doc, "~> 0.19.2", only: :dev}
    ]
  end

  defp description() do
  """
  BlockingQueue is a simple queue implemented as a GenServer.  It has a fixed maximum length established when it is created.
  """
  end

  defp package() do
    [files: ["lib", "mix.exs", "README.md", "LICENSE"],
     maintainers: ["Joseph Kain"],
     licenses: ["MIT"],
     links: %{
       "github" => "https://github.com/joekain/BlockingQueue"
     }]
  end
end
