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

  test "wait for `.done` to appear" do
    assert capture_io(fn ->
      try do
        SamsonSecretPuller.fetch_secrets!("./test/secrets", timeout: 0.2)
      rescue
        e in RuntimeError -> e
      end
    end) == "waiting for secrets to appear\nwaiting for secrets to appear\n"
  end

  test "stop waiting when `.done` appears" do
    assert capture_io(fn ->
      spawn_link(fn ->
        assert SamsonSecretPuller.fetch_secrets!("./test/secrets", timeout: 1)
          == [FOO: "bar"]
      end)

      :timer.sleep(150)
      File.touch! "./test/secrets/.done"
    end) == "waiting for secrets to appear\nwaiting for secrets to appear\n"
  end

  test "raises an error on timeout" do
    assert_raise RuntimeError, fn ->
      SamsonSecretPuller.fetch_secrets!("./test/secrets", timeout: 0.1)
    end
  end
end
