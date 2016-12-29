defmodule SamsonSecretPullerTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  doctest SamsonSecretPuller

  setup do
    File.rm_rf!   "./test/secrets" # Make sure each test starts with a clean slate
    File.mkdir_p! "./test/secrets"
    File.write!   "./test/secrets/FOO", "bar"
    {:ok, []}
  end

  test "reads secrets from the given folder" do
    File.touch!   "./test/secrets/.done"

    assert SamsonSecretPuller.fetch_secrets!("./test/secrets") == [FOO: "bar"]
  end
end
