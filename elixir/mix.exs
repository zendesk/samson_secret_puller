defmodule SamsonSecretPuller.Mixfile do
  use Mix.Project

  def project do
    [app: :samson_secret_puller,
     version: "0.1.0",
     elixir: "~> 1.2",
     description: description(),
     package: package(),
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [{:ex_doc, ">= 0.0.0", only: :dev}]
  end

  defp description do
    """
    A simple library to wait for and load secrets that are placed into the secrets
    sidecar built by Samson.
    """
  end

  defp package do
    [name: :samson_secret_puller,
     files: ["lib", "mix.exs", "README*", "MIT-LICENSE.txt"],
     maintainers: ["Craig Day"],
     licenses: ["MIT"],
     links: %{"GitHub" => "https://github.com/zendesk/samson_secret_puller",
              "Docs" => "https://hexdocs.pm/samson_secret_puller"}]
  end
end
