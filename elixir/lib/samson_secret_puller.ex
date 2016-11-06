defmodule SamsonSecretPuller do
  @moduledoc """
  Wait for secrets to appear from the secrets sidecar and then build a `Keyword`
  list of the secrets.
  """
  @folder "/secrets"
  @timeout 60
  @sleep_interval 0.1

  @typedoc "Options accepted"
  @type options :: [option]

  @typedoc "Option values accepted"
  @type option :: {:timeout, timeout}


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

  ## Options

  The accepted options are:

    * `:timeout` - seconds to wait for secrets to appear (default 60)

  ## Examples

      iex> SamsonSecretPuller.fetch_secrets!("./test/doc_secrets")
      [MYSQL_USER: "admin", MYSQL_PASS: "password"]

  """
  @spec fetch_secrets!(Path.t, options) :: Keyword.t | no_return
  def fetch_secrets!(folder, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @timeout) * 1000 # we use ms internally

    case wait_for_secrets_to_appear(folder, timeout) do
      {:ok, _}      -> read_secrets(folder)
      {:error, msg} -> raise msg
    end
  end

  # private

  defp wait_for_secrets_to_appear(folder, timeout) do
    done_file = folder <> "/.done"
    sleep     = round(@sleep_interval * 1000)  # erlang sleep uses integer ms

    wait_for_file_to_appear(done_file, sleep, timeout)
  end

  defp read_secrets(folder) do
    folder
    |> File.ls!
    |> Enum.reduce([], fn(file, acc) -> read_file(folder, file, acc) end)
  end

  defp read_file(_folder, ".done", acc), do: acc
  defp read_file(folder, file, acc) do
    key      = String.to_atom(file)
    contents = "#{folder}/#{file}"
      |> File.read!
      |> String.strip

    Keyword.put(acc, key, contents)
  end

  defp wait_for_file_to_appear(file, sleep, time_left),
    do: wait_for_file_to_appear(file, sleep, time_left, true)

  defp wait_for_file_to_appear(file, _sleep, time_left, false) when time_left > 0,
    do: {:ok, "#{file} is present"}

  defp wait_for_file_to_appear(_file, _sleep, time_left, _) when time_left <= 0,
    do: {:error, "Secrets didn't appear in time"}

  defp wait_for_file_to_appear(file, sleep, time_left, true) do
    IO.puts "waiting for secrets to appear"
    :timer.sleep(sleep)

    file_missing  = !File.exists?(file)
    new_time_left = time_left - sleep

    wait_for_file_to_appear(file, sleep, new_time_left, file_missing)
  end
end
