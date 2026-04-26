defmodule SootDevice.QEMUTest do
  @moduledoc """
  Smoke tests for `SootDevice.Test.QEMU`.

  Two layers:

    * Pure-Elixir unit tests run unconditionally — they exercise
      `available?/0` and `firmware_image_path/0` without booting QEMU.
    * Boot-and-RPC integration tests are tagged `@tag :qemu` and skip
      cleanly when prerequisites are missing.

  To run the full suite, build a qemu_aarch64 firmware image first:

      MIX_TARGET=qemu_aarch64 mix firmware

  Then `mix test --include qemu`.
  """

  use ExUnit.Case, async: false

  alias SootDevice.Test.QEMU

  describe "available?/0" do
    test "returns :ok or {:error, reason}" do
      case QEMU.available?() do
        :ok -> :ok
        {:error, :qemu_not_installed} -> :ok
        {:error, :firmware_not_built} -> :ok
        other -> flunk("unexpected available?/0 return: #{inspect(other)}")
      end
    end

    test "reports :qemu_not_installed when qemu-system-aarch64 missing" do
      # We can't really uninstall qemu, but we can assert that the
      # error shape is what test cases will pattern-match against.
      result = QEMU.available?()

      if System.find_executable("qemu-system-aarch64") == nil do
        assert result == {:error, :qemu_not_installed}
      end
    end

    test "reports :firmware_not_built when no image present" do
      result = QEMU.available?()

      if System.find_executable("qemu-system-aarch64") != nil and
           QEMU.firmware_image_path() == nil do
        assert result == {:error, :firmware_not_built}
      end
    end
  end

  describe "firmware_image_path/0" do
    test "returns nil when nothing built" do
      # In the soot_device library checkout, no Nerves firmware exists;
      # this should always be nil.
      assert QEMU.firmware_image_path() == nil
    end
  end

  # The :qemu tag is excluded by default in test_helper.exs. Run with
  # `mix test --include qemu` after building a firmware image:
  #     MIX_TARGET=qemu_aarch64 mix firmware
  describe "boot/1 (requires :qemu)" do
    @describetag :qemu

    setup do
      :ok = QEMU.available?()
      {:ok, qemu} = QEMU.boot(timeout: 90_000)
      on_exit(fn -> QEMU.stop(qemu) end)
      {:ok, qemu: qemu}
    end

    test "device node responds to a remote :erlang.node/0", %{qemu: qemu} do
      assert QEMU.rpc(qemu, :erlang, :node, []) == qemu.node
    end

    test "soot_device application is running on the device", %{qemu: qemu} do
      apps = QEMU.rpc(qemu, Application, :started_applications, [])
      assert is_list(apps)
      assert Enum.any?(apps, fn {name, _, _} -> name == :soot_device end)
    end
  end
end
