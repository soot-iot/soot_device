defmodule Mix.Tasks.SootDevice.Install.Docs do
  @moduledoc false

  def short_doc do
    "Installs the soot_device declarative DSL into a project"
  end

  def example do
    "mix igniter.install soot_device"
  end

  def long_doc do
    """
    #{short_doc()}

    Generates a `<App>.Device` module that uses the `SootDevice` DSL
    (with stub `identity`, `shadow`, `commands`, and `telemetry` blocks),
    a `<App>.SootDeviceConfig` helper, and wires `<App>.Device` into the
    application supervision tree.

    Use this installer for the higher-level declarative DSL — a single
    `device do … end` shape on top of `soot_device_protocol`. For
    imperative control over enrollment/contract/MQTT/shadow/commands/
    telemetry, use `mix igniter.install soot_device_protocol` instead.
    The two installers are alternatives.

    ## Example

    ```bash
    mix nerves.new my_device --target qemu_aarch64
    cd my_device
    # add {:soot_device, "~> 0.1"} (or path:) to deps
    mix deps.get
    #{example()}
    ```

    ## Options

      * `--example` — currently a no-op; reserved for future use to
        seed example handlers.
      * `--yes` — answer "yes" to dependency-fetching prompts.
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.SootDevice.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"
    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :soot,
        example: __MODULE__.Docs.example(),
        only: nil,
        composes: [],
        schema: [example: :boolean, yes: :boolean],
        defaults: [example: false, yes: false],
        aliases: [y: :yes, e: :example]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app_name = Igniter.Project.Application.app_name(igniter)
      device_module = Igniter.Project.Module.module_name(igniter, "Device")
      config_module = Igniter.Project.Module.module_name(igniter, "SootDeviceConfig")
      qemu_module = Igniter.Project.Module.module_name(igniter, "QEMU")

      igniter
      |> Igniter.Project.Formatter.import_dep(:soot_device)
      |> create_config_module(config_module, app_name)
      |> create_device_module(device_module)
      |> seed_application_config(app_name)
      |> add_supervisor_child(device_module, config_module)
      |> scaffold_qemu_helper(qemu_module)
      |> note_next_steps(app_name, device_module, qemu_module)
    end

    defp create_config_module(igniter, config_module, app_name) do
      Igniter.Project.Module.create_module(
        igniter,
        config_module,
        """
        @moduledoc \"\"\"
        Reads the device-side configuration that the `SootDevice` DSL
        runtime uses at boot.

        The `SootDevice` `use` declaration takes `contract_url`,
        `enroll_url`, and `serial` at compile time. Production devices
        usually want runtime values; this helper exposes them as a
        keyword list passed to the device module's child_spec, where
        `SootDevice.Runtime` merges them over the compile-time values.

        Generated stub — adjust freely.
        \"\"\"

        @app :#{app_name}

        @doc \"\"\"
        Builds the keyword list passed as `extra_opts` to
        `<App>.Device.child_spec/1`.
        \"\"\"
        @spec device_opts(keyword()) :: keyword()
        def device_opts(overrides \\\\ []) do
          [
            serial: fetch!(:serial),
            contract_url: fetch!(:contract_url),
            enroll_url: fetch!(:enroll_url),
            storage: storage_binding(),
            enrollment_token: System.get_env("SOOT_ENROLLMENT_TOKEN")
          ]
          |> Keyword.merge(overrides)
        end

        @doc "Fetches a single config key, raising if unset."
        @spec fetch!(atom()) :: term()
        def fetch!(key) do
          case Application.fetch_env(@app, key) do
            {:ok, value} -> value
            :error -> raise "missing " <> inspect(@app) <> " config key " <> inspect(key)
          end
        end

        defp storage_binding do
          dir = fetch!(:persistence_dir)

          case fetch!(:operational_storage) do
            :memory -> SootDeviceProtocol.Storage.Memory.open!()
            :file_system -> SootDeviceProtocol.Storage.Local.open!(dir)
          end
        end
        """
      )
    end

    defp create_device_module(igniter, device_module) do
      Igniter.Project.Module.create_module(
        igniter,
        device_module,
        """
        @moduledoc \"\"\"
        Declarative device definition.

        The compile-time `contract_url` / `enroll_url` / `serial` are
        placeholders — the runtime values come from
        `<App>.SootDeviceConfig.device_opts/0` and override these via
        `Keyword.merge` inside `SootDevice.Runtime`.

        Generated stub — flesh out the four DSL sections as your
        device behavior grows.
        \"\"\"

        use SootDevice,
          contract_url: "https://placeholder.local/.well-known/soot/contract",
          enroll_url: "https://placeholder.local/enroll",
          serial: "PLACEHOLDER-SERIAL"

        identity do
          bootstrap_cert_path System.get_env("SOOT_BOOTSTRAP_CERT", "priv/pki/bootstrap.pem")
          bootstrap_key_path System.get_env("SOOT_BOOTSTRAP_KEY", "priv/pki/bootstrap.key")
          operational_storage :file_system
          storage_dir System.get_env("SOOT_PERSISTENCE_DIR", "/data/soot")
          enrollment_token_env "SOOT_ENROLLMENT_TOKEN"
        end

        shadow do
          # on_change :led, &__MODULE__.handle_led/2
        end

        commands do
          # handle :reboot, &__MODULE__.handle_reboot/2, payload_format: :empty
        end

        telemetry do
          # stream :vibration do
          #   sample interval: 1_000, source: &__MODULE__.read_vibration/0
          # end
        end

        # Stub handlers shown for reference. Uncomment + tailor as you
        # populate the DSL above.
        #
        # def handle_led(_value, _meta), do: :ok
        # def handle_reboot(_payload, _meta), do: :ok
        # def read_vibration, do: %{"x" => :rand.uniform()}
        """
      )
    end

    defp seed_application_config(igniter, app_name) do
      env_prefix = app_name |> Atom.to_string() |> String.upcase()

      igniter
      |> set_config(app_name, :contract_url, """
      System.get_env("#{env_prefix}_CONTRACT_URL", "http://localhost:4000/.well-known/soot/contract")\
      """)
      |> set_config(app_name, :enroll_url, """
      System.get_env("#{env_prefix}_ENROLL_URL", "http://localhost:4000/enroll")\
      """)
      |> set_config(app_name, :serial, """
      System.get_env("#{env_prefix}_SERIAL", "DEV-0000-000001")\
      """)
      |> set_config(app_name, :operational_storage, ":file_system")
      |> set_config(app_name, :persistence_dir, """
      System.get_env("#{env_prefix}_PERSISTENCE_DIR", "/data/soot")\
      """)
    end

    defp set_config(igniter, app_name, key, code_string) do
      Igniter.Project.Config.configure(
        igniter,
        "config.exs",
        app_name,
        [key],
        {:code, Sourceror.parse_string!(code_string)}
      )
    end

    defp add_supervisor_child(igniter, device_module, config_module) do
      child_opts_ast =
        quote do
          unquote(config_module).device_opts()
        end

      Igniter.Project.Application.add_new_child(
        igniter,
        {device_module, {:code, child_opts_ast}}
      )
    end

    # Writes a copy of the QEMU helper into the operator's
    # test/support/. Same code as soot_device's own
    # `SootDevice.Test.QEMU`, namespaced under the operator's app
    # (e.g. `MyDevice.Test.QEMU`). Operator owns the file post-install
    # — guard with `exists?` so re-running is a true no-op.
    defp scaffold_qemu_helper(igniter, qemu_module) do
      # `test/support/` is an Igniter-managed source folder, so the
      # file path is determined by the module name. `<App>.QEMU` lands
      # at `test/support/<app>/qemu.ex` — clean and convention-aligned.
      path =
        Igniter.Project.Module.proper_location(
          igniter,
          qemu_module,
          {:source_folder, "test/support"}
        )

      if Igniter.exists?(igniter, path) do
        igniter
      else
        Igniter.create_new_file(igniter, path, qemu_template(qemu_module))
      end
    end

    defp qemu_template(qemu_module) do
      """
      defmodule #{inspect(qemu_module)} do
        @moduledoc \"\"\"
        Boots a Nerves QEMU image and connects to it over Erlang
        distribution so the host-side test process can drive it via
        `:rpc.call/4`.

        Generated by `mix igniter.install soot_device`. Operator owns
        this file post-install — the framework does not re-touch it.

        Tag tests that depend on this helper with `@tag :qemu` so
        they skip cleanly when prerequisites are missing
        (`qemu-system-aarch64` not on PATH or no firmware image
        built). Add `ExUnit.start(exclude: [:qemu])` to your
        `test_helper.exs` to skip by default.
        \"\"\"

        require Logger

        defstruct [:port, :node, :tmp_dir]

        @type t :: %__MODULE__{port: port(), node: node(), tmp_dir: String.t()}

        @device_node :"soot-device@127.0.0.1"
        @cookie :soot_device_test_cookie

        @spec available?() :: :ok | {:error, term()}
        def available? do
          cond do
            System.find_executable("qemu-system-aarch64") == nil ->
              {:error, :qemu_not_installed}

            firmware_image_path() == nil ->
              {:error, :firmware_not_built}

            true ->
              :ok
          end
        end

        @spec boot(keyword()) :: {:ok, t()} | {:error, term()}
        def boot(opts \\\\ []) do
          cookie = Keyword.get(opts, :cookie, @cookie)
          device_node = Keyword.get(opts, :device_node, @device_node)

          with :ok <- available?(),
               :ok <- ensure_distribution_running(cookie) do
            image = Keyword.get(opts, :image) || firmware_image_path()
            timeout = Keyword.get(opts, :timeout, 60_000)
            extra = Keyword.get(opts, :extra_args, [])
            tmp = Path.join(System.tmp_dir!(), "soot-qemu-\#{System.unique_integer([:positive])}")
            File.mkdir_p!(tmp)

            port = open_port(image, extra)

            case wait_for_node(device_node, timeout) do
              :ok ->
                {:ok, %__MODULE__{port: port, node: device_node, tmp_dir: tmp}}

              {:error, reason} ->
                stop_port(port)
                File.rm_rf!(tmp)
                {:error, reason}
            end
          end
        end

        @spec stop(t()) :: :ok
        def stop(%__MODULE__{port: port, node: node, tmp_dir: tmp}) do
          Node.disconnect(node)
          stop_port(port)
          File.rm_rf!(tmp)
          :ok
        end

        @spec rpc(t(), module(), atom(), [term()]) :: term()
        def rpc(%__MODULE__{node: node}, mod, fun, args) do
          case :rpc.call(node, mod, fun, args) do
            {:badrpc, reason} ->
              raise "rpc to \#{inspect(node)} failed: \#{inspect(reason)}"

            result ->
              result
          end
        end

        @spec firmware_image_path() :: String.t() | nil
        def firmware_image_path do
          "_build/qemu_aarch64_*/nerves/images/*.img"
          |> Path.wildcard()
          |> Enum.sort_by(&File.stat!(&1).mtime, :desc)
          |> List.first()
        end

        defp open_port(image, extra) do
          args =
            [
              "-machine", "virt",
              "-cpu", "cortex-a72",
              "-smp", "2",
              "-m", "1024",
              "-nographic",
              "-drive", "if=virtio,file=\#{image},format=raw",
              "-netdev", "user,id=net0,hostfwd=tcp::4369-:4369,hostfwd=tcp::9100-:9100",
              "-device", "virtio-net-device,netdev=net0"
            ] ++ extra

          Port.open(
            {:spawn_executable, System.find_executable("qemu-system-aarch64")},
            [:binary, :exit_status, args: args]
          )
        end

        defp stop_port(port) when is_port(port) do
          try do
            Port.close(port)
          rescue
            ArgumentError -> :ok
          end

          :ok
        end

        defp ensure_distribution_running(cookie) do
          if Node.alive?() do
            Node.set_cookie(cookie)
            :ok
          else
            case Node.start(:"soot-device-test-host@127.0.0.1", :longnames) do
              {:ok, _} ->
                Node.set_cookie(cookie)
                :ok

              {:error, reason} ->
                {:error, {:dist_failed, reason}}
            end
          end
        end

        defp wait_for_node(node, timeout) do
          deadline = System.monotonic_time(:millisecond) + timeout
          do_wait_for_node(node, deadline)
        end

        defp do_wait_for_node(node, deadline) do
          if Node.connect(node) == true do
            :ok
          else
            if System.monotonic_time(:millisecond) > deadline do
              {:error, :node_did_not_appear}
            else
              Process.sleep(500)
              do_wait_for_node(node, deadline)
            end
          end
        end
      end
      """
    end

    defp note_next_steps(igniter, app_name, device_module, qemu_module) do
      env_prefix = app_name |> Atom.to_string() |> String.upcase()

      Igniter.add_notice(igniter, """
      soot_device installed.

      Generated:
        * `lib/#{app_name}/device.ex` — the `SootDevice` DSL module.
          Fill in `identity`, `shadow`, `commands`, and `telemetry`
          blocks. Compile-time URLs are placeholders; the runtime
          values come from `:#{app_name}` Application env via
          `<App>.SootDeviceConfig.device_opts/0`.
        * `lib/#{app_name}/soot_device_config.ex` — config helper.
        * `test/support/qemu.ex` — `#{inspect(qemu_module)}`,
          the QEMU boot + RPC helper for integration tests. Tag tests
          with `@tag :qemu` and add `ExUnit.start(exclude: [:qemu])`
          to your `test_helper.exs` so they skip cleanly when no
          firmware is built.
        * `{#{inspect(device_module)}, ...}` is now in your application
          supervision tree.
        * `config/config.exs` seeded with placeholder
          `:#{app_name}, :contract_url` etc., env-overridable via
          `#{env_prefix}_CONTRACT_URL`, `#{env_prefix}_ENROLL_URL`,
          `#{env_prefix}_SERIAL`, `#{env_prefix}_PERSISTENCE_DIR`.
          The bootstrap cert/key paths are read inside the DSL via
          `SOOT_BOOTSTRAP_CERT` / `SOOT_BOOTSTRAP_KEY`.

      Next steps:

        1. Drop a bootstrap cert + key under `priv/pki/` (or point
           `SOOT_BOOTSTRAP_CERT` / `_KEY` at the right paths on your
           target).
        2. Set `#{env_prefix}_CONTRACT_URL` and friends to your Soot
           backend URLs.
        3. Boot the app — the device supervisor blocks on enrollment,
           then starts the configured shadow/commands/telemetry.
        4. For QEMU integration tests:
             MIX_TARGET=qemu_aarch64 mix firmware
             mix test --include qemu
      """)
    end
  end
else
  defmodule Mix.Tasks.SootDevice.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"
    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task `soot_device.install` requires igniter. Add
      `{:igniter, "~> 0.6"}` to your project deps and try again, or
      invoke via:

          mix igniter.install soot_device

      For more information, see https://hexdocs.pm/igniter
      """)

      exit({:shutdown, 1})
    end
  end
end
