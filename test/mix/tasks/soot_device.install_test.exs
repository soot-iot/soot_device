defmodule Mix.Tasks.SootDevice.InstallTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  describe "info/2" do
    test "exposes the documented option schema" do
      info = Mix.Tasks.SootDevice.Install.info([], nil)
      assert info.group == :soot

      assert info.schema == [
               example: :boolean,
               yes: :boolean,
               bootstrap_cert: :string,
               bootstrap_key: :string
             ]

      assert info.aliases == [
               y: :yes,
               e: :example,
               c: :bootstrap_cert,
               k: :bootstrap_key
             ]

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

  describe "bootstrap credential baking" do
    @tmp Path.join(System.tmp_dir!(), "soot_device_install_bootstrap_test")

    setup do
      File.rm_rf!(@tmp)
      File.mkdir_p!(@tmp)
      on_exit(fn -> File.rm_rf!(@tmp) end)
      :ok
    end

    defp write_pem!(name, contents) do
      path = Path.join(@tmp, name)
      File.write!(path, contents)
      path
    end

    test "device.ex defaults bootstrap_*_path to /etc/soot/" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.install", [])

      diff = diff(result, only: "lib/test/device.ex")
      assert diff =~ ~s|"SOOT_BOOTSTRAP_CERT", "/etc/soot/bootstrap.pem"|
      assert diff =~ ~s|"SOOT_BOOTSTRAP_KEY", "/etc/soot/bootstrap.key"|
    end

    test "without --bootstrap-cert flags, no rootfs_overlay files are baked" do
      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.install", [])

      assert {:error, %Rewrite.Error{reason: :nosource}} =
               Rewrite.source(result.rewrite, "rootfs_overlay/etc/soot/bootstrap.pem")

      assert {:error, %Rewrite.Error{reason: :nosource}} =
               Rewrite.source(result.rewrite, "rootfs_overlay/etc/soot/bootstrap.key")
    end

    test "with --bootstrap-cert and --bootstrap-key, bakes both into rootfs_overlay" do
      cert_path = write_pem!("bootstrap.pem", "-----BEGIN CERTIFICATE-----\nFAKECERT\n-----END CERTIFICATE-----\n")
      key_path = write_pem!("bootstrap.key", "-----BEGIN PRIVATE KEY-----\nFAKEKEY\n-----END PRIVATE KEY-----\n")

      result =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.install", [
          "--bootstrap-cert",
          cert_path,
          "--bootstrap-key",
          key_path
        ])

      assert_creates(result, "rootfs_overlay/etc/soot/bootstrap.pem")
      assert_creates(result, "rootfs_overlay/etc/soot/bootstrap.key")

      cert_diff = diff(result, only: "rootfs_overlay/etc/soot/bootstrap.pem")
      assert cert_diff =~ "BEGIN CERTIFICATE"
      assert cert_diff =~ "FAKECERT"

      key_diff = diff(result, only: "rootfs_overlay/etc/soot/bootstrap.key")
      assert key_diff =~ "BEGIN PRIVATE KEY"
      assert key_diff =~ "FAKEKEY"
    end

    test "warns when only one of --bootstrap-cert / --bootstrap-key is given" do
      cert_path = write_pem!("bootstrap.pem", "x")

      igniter =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.install", [
          "--bootstrap-cert",
          cert_path
        ])

      assert Enum.any?(
               igniter.warnings,
               &(&1 =~ "must be passed together")
             )
    end

    test "raises when --bootstrap-cert path does not exist" do
      assert_raise Mix.Error, ~r/path does not exist/, fn ->
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.install", [
          "--bootstrap-cert",
          Path.join(@tmp, "nope.pem"),
          "--bootstrap-key",
          Path.join(@tmp, "nope.key")
        ])
      end
    end

    test "is idempotent on rootfs_overlay files (operator-owned)" do
      cert_path = write_pem!("bootstrap.pem", "cert-v1")
      key_path = write_pem!("bootstrap.key", "key-v1")

      argv = [
        "--bootstrap-cert",
        cert_path,
        "--bootstrap-key",
        key_path
      ]

      test_project(files: %{})
      |> Igniter.compose_task("soot_device.install", argv)
      |> apply_igniter!()
      |> Igniter.compose_task("soot_device.install", argv)
      |> assert_unchanged("rootfs_overlay/etc/soot/bootstrap.pem")
    end

    test "next-steps notice reflects whether credentials were baked" do
      cert_path = write_pem!("bootstrap.pem", "x")
      key_path = write_pem!("bootstrap.key", "y")

      with_baked =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.install", [
          "--bootstrap-cert",
          cert_path,
          "--bootstrap-key",
          key_path
        ])

      without_baked =
        test_project(files: %{})
        |> Igniter.compose_task("soot_device.install", [])

      baked_notices = Enum.join(with_baked.notices, "\n")
      bare_notices = Enum.join(without_baked.notices, "\n")

      assert baked_notices =~ "baked into the firmware"
      assert bare_notices =~ "NOT baked"
    end
  end
end
