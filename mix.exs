defmodule BlockingQueue.Mixfile do
  use Mix.Project

  def project do
    [app: :blocking_queue,
     version: "1.3.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     description: description(),
     package: package()]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [
      {:excheck, "~> 0.5", only: :test},
      {:triq, github: "triqng/triq", only: :test},
      {:inch_ex, "~> 0.5.4", only: :docs},
      {:earmark, "~> 1.1.0", only: :dev},
      {:ex_doc, "~> 0.14", only: :dev}
    ]
  end

  defp description do
  """
  BlockingQueue is a simple queue implemented as a GenServer.  It has a fixed maximum length established when it is created.
  """
  end

  defp package do
    [files: ["lib", "mix.exs", "README.md", "LICENSE"],
     maintainers: ["Joseph Kain"],
     licenses: ["MIT"],
     links: %{
       "github" => "https://github.com/joekain/BlockingQueue"
     }]
  end
end
