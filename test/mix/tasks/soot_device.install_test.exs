defmodule Mix.Tasks.SootDevice.InstallTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  describe "info/2" do
    test "exposes the documented option schema" do
      info = Mix.Tasks.SootDevice.Install.info([], nil)
      assert info.group == :soot
      assert info.schema == [example: :boolean, yes: :boolean]
      assert info.aliases == [y: :yes, e: :example]
      assert info.composes == []
    end
  end

  describe "formatter" do
    test "imports :soot_device in .formatter.exs" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_device.install", [])
      |> assert_has_patch(".formatter.exs", """
      + |  import_deps: [:soot_device]
      """)
    end

    test "is idempotent on .formatter.exs" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_device.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("soot_device.install", [])
      |> assert_unchanged(".formatter.exs")
    end
  end

  describe "device DSL module" do
    test "creates lib/<app>/device.ex" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_device.install", [])
      |> assert_creates("lib/test/device.ex")
    end

    test "the generated module uses the SootDevice DSL with stub sections" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.install", [])

      diff = diff(result, only: "lib/test/device.ex")
      assert diff =~ "use SootDevice"
      assert diff =~ "contract_url:"
      assert diff =~ "enroll_url:"
      assert diff =~ "serial:"
      assert diff =~ "identity do"
      assert diff =~ "shadow do"
      assert diff =~ "commands do"
      assert diff =~ "telemetry do"
    end
  end

  describe "config helper module" do
    test "creates lib/<app>/soot_device_config.ex" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_device.install", [])
      |> assert_creates("lib/test/soot_device_config.ex")
    end

    test "the generated module exposes device_opts/1" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.install", [])

      diff = diff(result, only: "lib/test/soot_device_config.ex")
      assert diff =~ "def device_opts"
      assert diff =~ "fetch!(:contract_url)"
      assert diff =~ "fetch!(:enroll_url)"
      assert diff =~ "fetch!(:serial)"
    end
  end

  describe "config seed" do
    test "seeds :contract_url, :enroll_url, :serial, storage, persistence_dir" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.install", [])

      diff = diff(result, only: "config/config.exs")
      assert diff =~ "contract_url:"
      assert diff =~ "enroll_url:"
      assert diff =~ "serial:"
      assert diff =~ "operational_storage:"
      assert diff =~ "persistence_dir:"
      assert diff =~ "TEST_CONTRACT_URL"
    end

    test "is idempotent on config.exs" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_device.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("soot_device.install", [])
      |> assert_unchanged("config/config.exs")
    end
  end

  describe "supervision tree" do
    test "adds <App>.Device to the application" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.install", [])

      diff = diff(result)
      assert diff =~ "Test.Device"
      assert diff =~ "Test.SootDeviceConfig.device_opts()"
    end

    test "is idempotent on the application module" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_device.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("soot_device.install", [])
      |> assert_unchanged("lib/test/application.ex")
    end
  end

  describe "next-steps notice" do
    test "always emits a soot_device installed notice" do
      igniter =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.install", [])

      assert Enum.any?(igniter.notices, &(&1 =~ "soot_device installed"))
    end

    test "mentions the scaffolded QEMU helper and the :qemu tag convention" do
      igniter =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.install", [])

      notices = Enum.join(igniter.notices, "\n")
      # See the QEMU scaffolding tests for why the path lacks the
      # repeated app segment.
      assert notices =~ "test/support/qemu.ex"
      assert notices =~ ":qemu"
      assert notices =~ "MIX_TARGET=qemu_aarch64 mix firmware"
    end
  end

  describe "QEMU test helper scaffolding" do
    # `proper_location` with `module_location: :outside_matching_folder`
    # (the default) strips the app prefix when it matches the source
    # folder's parent, so `Test.QEMU` under `test/support` lands at
    # `test/support/qemu.ex` rather than `test/support/test/qemu.ex`.
    test "creates test/support/qemu.ex" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_device.install", [])
      |> assert_creates("test/support/qemu.ex")
    end

    test "scaffolded module is namespaced under the operator's app" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.install", [])

      diff = diff(result, only: "test/support/qemu.ex")
      assert diff =~ "defmodule Test.QEMU"
      assert diff =~ "@spec available?()"
      assert diff =~ "@spec boot(keyword())"
      assert diff =~ "@spec rpc"
      assert diff =~ "qemu-system-aarch64"
      assert diff =~ "hostfwd=tcp::4369-:4369"
    end

    test "scaffolded helper is operator-owned (idempotent skip on re-run)" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_device.install", [])
      |> apply_igniter!()
      |> Igniter.compose_task("soot_device.install", [])
      |> assert_unchanged("test/support/qemu.ex")
    end
  end
end
