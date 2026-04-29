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

      * `--example` / `--no-example` — when set (default: ON),
        generates a `<App>.Telemetry.SystemHealth` module that samples
        CPU load + utilization, memory, and disk usage on Linux /
        Nerves targets, and wires three telemetry streams (`:cpu`,
        `:memory`, `:disk`) in the generated device module pointing
        at it. Adapted from
        `NervesHubLink.Extensions.Health.MetricSet`. Field names
        match the backend's `soot_telemetry` default streams of the
        same names so the data lands in ClickHouse without further
        mapping. Pass `--no-example` to leave the `telemetry do …
        end` block empty.
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
        schema: [
          example: :boolean,
          yes: :boolean,
          bootstrap_cert: :string,
          bootstrap_key: :string
        ],
        defaults: [example: true, yes: false],
        aliases: [y: :yes, e: :example, c: :bootstrap_cert, k: :bootstrap_key]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options
      app_name = Igniter.Project.Application.app_name(igniter)
      device_module = Igniter.Project.Module.module_name(igniter, "Device")
      config_module = Igniter.Project.Module.module_name(igniter, "SootDeviceConfig")
      qemu_module = Igniter.Project.Module.module_name(igniter, "QEMU")
      health_module = Igniter.Project.Module.module_name(igniter, "Telemetry.SystemHealth")

      igniter
      |> Igniter.Project.Formatter.import_dep(:soot_device)
      |> create_config_module(config_module, app_name)
      |> create_device_module(device_module, health_module, options)
      |> maybe_create_health_module(health_module, options)
      |> maybe_add_os_mon(options)
      |> seed_application_config(app_name)
      |> add_supervisor_child(device_module, config_module)
      |> scaffold_qemu_helper(qemu_module)
      |> bake_bootstrap_credentials(options)
      |> note_next_steps(app_name, device_module, qemu_module, options)
    end

    # When the operator passes `--bootstrap-cert <path>` and
    # `--bootstrap-key <path>`, copy the supplied PEMs into the
    # project's `rootfs_overlay/etc/soot/` so Nerves bakes them
    # into the firmware. The default env-var paths in
    # `lib/<app>/device.ex` already point at /etc/soot/bootstrap.{pem,key}
    # — the files just need to exist on the rootfs.
    #
    # Both flags must be present together; one without the other is a
    # configuration error.
    defp bake_bootstrap_credentials(igniter, options) do
      cert = options[:bootstrap_cert]
      key = options[:bootstrap_key]

      cond do
        cert && key ->
          igniter
          |> bake_pem!("rootfs_overlay/etc/soot/bootstrap.pem", cert)
          |> bake_pem!("rootfs_overlay/etc/soot/bootstrap.key", key)

        cert || key ->
          Igniter.add_warning(igniter, """
          --bootstrap-cert and --bootstrap-key must be passed together.
          Neither was baked into the rootfs_overlay. Provide both flags
          or omit both (and set SOOT_BOOTSTRAP_CERT / _KEY at runtime).
          """)

        true ->
          igniter
      end
    end

    defp bake_pem!(igniter, target, source_path) do
      if !File.exists?(source_path) do
        Mix.raise("--bootstrap-* path does not exist: #{source_path}")
      end

      contents = File.read!(source_path)

      if Igniter.exists?(igniter, target) do
        # Operator already has a baked cert/key. Don't overwrite.
        igniter
      else
        Igniter.create_new_file(igniter, target, contents)
      end
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

    defp create_device_module(igniter, device_module, health_module, options) do
      Igniter.Project.Module.create_module(
        igniter,
        device_module,
        device_module_body(health_module, options)
      )
    end

    defp device_module_body(health_module, options) do
      health_inspect = inspect(health_module)

      telemetry_body =
        if options[:example] do
          """
            stream :cpu do
              sample interval: 60_000, source: &#{health_inspect}.cpu_sample/0
            end

            stream :memory do
              sample interval: 60_000, source: &#{health_inspect}.memory_sample/0
            end

            stream :disk do
              sample interval: 300_000, source: &#{health_inspect}.disk_sample/0
            end
          """
        else
          """
            # stream :vibration do
            #   sample interval: 1_000, source: &__MODULE__.read_vibration/0
            # end
          """
        end

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
        bootstrap_cert_path System.get_env("SOOT_BOOTSTRAP_CERT", "/etc/soot/bootstrap.pem")
        bootstrap_key_path System.get_env("SOOT_BOOTSTRAP_KEY", "/etc/soot/bootstrap.key")
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
      #{telemetry_body}end

      # Stub handlers shown for reference. Uncomment + tailor as you
      # populate the DSL above.
      #
      # def handle_led(_value, _meta), do: :ok
      # def handle_reboot(_payload, _meta), do: :ok
      # def read_vibration, do: %{"x" => :rand.uniform()}
      """
    end

    defp maybe_create_health_module(igniter, health_module, options) do
      if options[:example] do
        Igniter.Project.Module.create_module(
          igniter,
          health_module,
          health_module_body()
        )
      else
        igniter
      end
    end

    # Adapted from `NervesHubLink.Extensions.Health.MetricSet.{CPU,Memory,Disk}`.
    # Each sampler returns a map keyed by the field names declared in
    # the matching `:cpu` / `:memory` / `:disk` telemetry stream on
    # the backend (`SootTelemetry.Stream.Definition` defaults from
    # `mix soot_telemetry.install`). Numbers come from /proc on Linux
    # and `:os_mon`'s `:cpu_sup` / `:disksup` for portable CPU + disk
    # data; the operator owns this file post-install and can swap in
    # board-specific probes (RPi `vcgencmd`, BMP-style sensors, etc.)
    # without re-running the installer.
    defp health_module_body do
      ~S'''
      @moduledoc """
      Default device health metric collection — CPU load + utilization,
      memory, and disk usage. Generated by
      `mix soot_device.install --example`. Adapted from
      `NervesHubLink.Extensions.Health.MetricSet`. Operators own this
      file; tailor the samplers as your device behavior grows.

      The map keys returned by `cpu_sample/0`, `memory_sample/0`, and
      `disk_sample/0` match the field names of the matching default
      streams in `soot_telemetry`, so the data lands in ClickHouse
      without an explicit field mapping.
      """

      @doc "CPU sample — load averages from /proc/loadavg + utilization from :cpu_sup."
      @spec cpu_sample() :: map()
      def cpu_sample do
        Map.merge(load_averages(), cpu_utilization())
      end

      @doc "Memory sample — parsed from /proc/meminfo on Linux."
      @spec memory_sample() :: map()
      def memory_sample do
        case File.read("/proc/meminfo") do
          {:ok, content} -> parse_meminfo(content)
          _ -> %{}
        end
      end

      @doc "Disk sample for the root mount, via :disksup.get_disk_data/0."
      @spec disk_sample() :: map()
      def disk_sample do
        ensure_os_mon_started()

        case find_root_mount() do
          {_mount, total_kb, capacity_pct} ->
            total_bytes = total_kb * 1024
            used_bytes = round(capacity_pct / 100 * total_bytes)

            %{
              mount_point: "/",
              total_bytes: total_bytes,
              used_bytes: used_bytes,
              available_bytes: total_bytes - used_bytes,
              # :disksup doesn't expose inode counts; left at zero.
              # Override with `stat -f` or similar if the backend cares.
              inode_total: 0,
              inode_used: 0
            }

          _ ->
            %{}
        end
      end

      defp load_averages do
        with {:ok, content} <- File.read("/proc/loadavg"),
             [m1, m5, m15, _, _] <- String.split(content, " "),
             {f1, _} <- Float.parse(m1),
             {f5, _} <- Float.parse(m5),
             {f15, _} <- Float.parse(m15) do
          %{load_1m: f1, load_5m: f5, load_15m: f15}
        else
          _ -> %{}
        end
      end

      defp cpu_utilization do
        ensure_os_mon_started()

        case :cpu_sup.util([:detailed]) do
          {:all, _busy_pct, _idle_pct, kw} when is_list(kw) ->
            %{
              user_pct: Keyword.get(kw, :user, 0.0) * 1.0,
              system_pct: Keyword.get(kw, :kernel, 0.0) * 1.0,
              iowait_pct: Keyword.get(kw, :wait, 0.0) * 1.0
            }

          _ ->
            %{}
        end
      rescue
        _ -> %{}
      end

      defp parse_meminfo(content) do
        kb_by_key =
          content
          |> String.split("\n", trim: true)
          |> Enum.reduce(%{}, fn line, acc ->
            with [key, value] <- String.split(line, ~r/:\s+/, parts: 2),
                 {kb, _} <- Integer.parse(value) do
              Map.put(acc, key, kb * 1024)
            else
              _ -> acc
            end
          end)

        total = Map.get(kb_by_key, "MemTotal", 0)
        available = Map.get(kb_by_key, "MemAvailable", 0)
        swap_total = Map.get(kb_by_key, "SwapTotal", 0)
        swap_free = Map.get(kb_by_key, "SwapFree", 0)

        %{
          total_bytes: total,
          available_bytes: available,
          used_bytes: max(total - available, 0),
          cached_bytes: Map.get(kb_by_key, "Cached", 0),
          swap_total_bytes: swap_total,
          swap_used_bytes: max(swap_total - swap_free, 0)
        }
      end

      defp find_root_mount do
        Enum.find(:disksup.get_disk_data(), fn {key, _, _} ->
          key in [~c"/", ~c"/root"]
        end)
      end

      defp ensure_os_mon_started do
        case Application.ensure_all_started(:os_mon) do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
          _ -> :error
        end
      end
      '''
    end

    defp maybe_add_os_mon(igniter, options) do
      if options[:example] do
        Igniter.Project.MixProject.update(igniter, :application, [:extra_applications], fn
          nil ->
            {:ok, {:code, [:logger, :os_mon]}}

          zipper ->
            Igniter.Code.List.append_new_to_list(zipper, :os_mon)
        end)
      else
        igniter
      end
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

    defp note_next_steps(igniter, app_name, device_module, qemu_module, options) do
      env_prefix = app_name |> Atom.to_string() |> String.upcase()

      bootstrap_lines =
        if options[:bootstrap_cert] && options[:bootstrap_key] do
          """

          Bootstrap credentials baked into the firmware:
            * `rootfs_overlay/etc/soot/bootstrap.pem`
            * `rootfs_overlay/etc/soot/bootstrap.key`

          The DSL defaults to reading these from `/etc/soot/`. Override
          at runtime via `SOOT_BOOTSTRAP_CERT` / `SOOT_BOOTSTRAP_KEY`.
          """
        else
          """

          Bootstrap credentials NOT baked. The DSL defaults to reading
          from `/etc/soot/bootstrap.{pem,key}`; either:

            * Re-run with `--bootstrap-cert <path> --bootstrap-key <path>`
              to bake them into the firmware via `rootfs_overlay/`.
            * Set `SOOT_BOOTSTRAP_CERT` / `SOOT_BOOTSTRAP_KEY` at runtime
              to point at writable paths on your target.
          """
        end

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
      #{bootstrap_lines}
      Next steps:

        1. Set `#{env_prefix}_CONTRACT_URL` and friends to your Soot
           backend URLs.
        2. Boot the app — the device supervisor blocks on enrollment,
           then starts the configured shadow/commands/telemetry.
        3. For QEMU integration tests:
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
