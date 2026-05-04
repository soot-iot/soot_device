defmodule Mix.Tasks.SootDevice.Gen.TestsTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  describe "info/2" do
    test "declares the documented option schema and aliases" do
      info = Mix.Tasks.SootDevice.Gen.Tests.info([], nil)

      assert info.group == :soot
      assert info.schema == [yes: :boolean]
      assert info.aliases == [y: :yes]
      assert info.composes == []
    end
  end

  describe "test files" do
    test "creates host-side and QEMU integration tests under test/<app>/" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.gen.tests", [])

      assert_creates(result, "test/test/device_test.exs")
      assert_creates(result, "test/test/qemu_test.exs")
    end

    test "rewrites MyDevice → operator's app module" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.gen.tests", [])

      device = diff(result, only: "test/test/device_test.exs")
      assert device =~ "defmodule Test.DeviceTest"
      assert device =~ "alias Test.Device"
      assert device =~ "Test.SootDeviceConfig"
      refute device =~ "MyDevice"

      qemu_test = diff(result, only: "test/test/qemu_test.exs")
      assert qemu_test =~ "defmodule Test.QEMUTest"
      assert qemu_test =~ "alias Test.QEMU"
      assert qemu_test =~ "Test.Device"
      refute qemu_test =~ "MyDevice"
    end

    test "rewrites :my_device → operator's app atom" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.gen.tests", [])

      device = diff(result, only: "test/test/device_test.exs")
      assert device =~ ":test"
      refute device =~ ":my_device"

      qemu_test = diff(result, only: "test/test/qemu_test.exs")
      # The application-running assertion in qemu_test references the
      # operator's app atom.
      assert qemu_test =~ "name == :test"
      refute qemu_test =~ ":my_device"
    end

    test "qemu_test.exs is tagged :qemu" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.gen.tests", [])

      qemu_test = diff(result, only: "test/test/qemu_test.exs")
      assert qemu_test =~ "@moduletag :qemu"
    end
  end

  describe "QEMU helper scaffolding" do
    test "creates test/support/qemu.ex namespaced under the operator's app" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.gen.tests", [])

      assert_creates(result, "test/support/qemu.ex")

      diff = diff(result, only: "test/support/qemu.ex")
      assert diff =~ "defmodule Test.QEMU"
      assert diff =~ "@cookie :test_test_cookie"
      assert diff =~ "qemu-system-aarch64"
      assert diff =~ "hostfwd=tcp::4369-:4369"
      assert diff =~ "hostfwd=tcp::9100-:9100"
    end
  end

  describe "rel/vm.args.eex" do
    test "creates rel/vm.args.eex with MIX_ENV=test gated distribution" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.gen.tests", [])

      assert_creates(result, "rel/vm.args.eex")

      diff = diff(result, only: "rel/vm.args.eex")
      # Distribution lines must be gated so production firmware does
      # not ship with an open dist port.
      assert diff =~ "if Mix.env() == :test"
      assert diff =~ "-name soot-device@127.0.0.1"
      assert diff =~ "-setcookie test_test_cookie"
    end

    test "does not overwrite an existing rel/vm.args.eex" do
      operator_args = "## operator-customized vm.args\n+Bc\n"

      result =
        test_project(files: %{"rel/vm.args.eex" => operator_args})
        |> Igniter.compose_task("soot_device.gen.tests", [])

      assert_unchanged(result, "rel/vm.args.eex")
    end
  end

  describe "config/target.exs" do
    test "pins inet_dist_listen_min/max to 9100" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.gen.tests", [])

      diff = diff(result, only: "config/target.exs")
      assert diff =~ ":kernel"
      assert diff =~ "inet_dist_listen_min: 9100"
      assert diff =~ "inet_dist_listen_max: 9100"
    end

    test "is idempotent on config/target.exs" do
      test_project(files: %{})
      |> Igniter.compose_task("soot_device.gen.tests", [])
      |> apply_igniter!()
      |> Igniter.compose_task("soot_device.gen.tests", [])
      |> assert_unchanged("config/target.exs")
    end
  end

  describe "test/test_helper.exs" do
    test "rewrites a bare ExUnit.start() to ExUnit.start(exclude: [:qemu])" do
      result =
        test_project(files: %{"test/test_helper.exs" => "ExUnit.start()\n"})
        |> Igniter.compose_task("soot_device.gen.tests", [])

      diff = diff(result, only: "test/test_helper.exs")
      assert diff =~ "ExUnit.start(exclude: [:qemu])"
    end

    test "is a no-op when :qemu is already excluded" do
      contents = "ExUnit.start(exclude: [:qemu, :integration])\n"

      result =
        test_project(files: %{"test/test_helper.exs" => contents})
        |> Igniter.compose_task("soot_device.gen.tests", [])

      assert_unchanged(result, "test/test_helper.exs")
    end

    test "creates test/test_helper.exs when missing" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.gen.tests", [])

      diff = diff(result, only: "test/test_helper.exs")
      assert diff =~ "ExUnit.start(exclude: [:qemu])"
    end

    test "emits a notice when test_helper.exs is non-default and unpatchable" do
      contents = "ExUnit.start(capture_log: true)\n"

      igniter =
        test_project(files: %{"test/test_helper.exs" => contents})
        |> Igniter.compose_task("soot_device.gen.tests", [])

      notices = Enum.join(igniter.notices, "\n")
      assert notices =~ "non-default"
      assert notices =~ ":qemu"
    end
  end

  describe "idempotency" do
    test "re-running the generator skips files that already exist" do
      first =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.gen.tests", [])
        |> apply_igniter!()

      second = Igniter.compose_task(first, "soot_device.gen.tests", [])

      for path <- [
            "test/test/device_test.exs",
            "test/test/qemu_test.exs",
            "test/support/qemu.ex",
            "rel/vm.args.eex"
          ] do
        assert_unchanged(second, path)
      end
    end
  end

  describe "next-steps notice" do
    test "documents host-side and QEMU test invocations" do
      igniter =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.gen.tests", [])

      notices = Enum.join(igniter.notices, "\n")
      assert notices =~ "Default test scaffolding generated"
      assert notices =~ "mix test"
      assert notices =~ "MIX_TARGET=qemu_aarch64 MIX_ENV=test mix firmware"
      assert notices =~ "mix test --include qemu"
    end
  end
end
