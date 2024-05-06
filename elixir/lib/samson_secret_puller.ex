defmodule SamsonSecretPuller do
  @moduledoc """
  Wait for secrets to appear from the secrets sidecar and then build a `Keyword`
  list of the secrets.
  """
  @folder "/secrets"

  # This doc is hard to give examples without clobbering your actual `/secrets`
  # directory.
  @doc """
  Waits for secrets to appear in `/secrets` then reads them into a `Keyword`
  list.

  Returns `[key: "value"]`.

  """
  @spec fetch_secrets! :: Keyword.t | no_return
  def fetch_secrets!, do: fetch_secrets!(@folder)

  @doc """
  Same as `fetch_secrets\0` but looks in `folder` instead of `/secrets`.

  Returns `[key: "value"]`.

  ## Examples

      iex> Enum.sort(SamsonSecretPuller.fetch_secrets!("./test/doc_secrets"), :desc)
      [MYSQL_USER: "admin", MYSQL_PASS: "password"]

  """
  @spec fetch_secrets!(Path.t) :: Keyword.t | no_return
  def fetch_secrets!(folder) do
    folder
    |> File.ls!
    |> Enum.reduce([], fn(file, acc) -> read_file(folder, file, acc) end)
  end

  # private

  defp read_file(_folder, ".done", acc), do: acc
  defp read_file(folder, file, acc) do
    key      = String.to_atom(file)
    contents = "#{folder}/#{file}"
      |> File.read!
      |> String.trim

    Keyword.put(acc, key, contents)
  end
end
