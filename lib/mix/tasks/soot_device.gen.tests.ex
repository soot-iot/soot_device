defmodule Mix.Tasks.SootDevice.Gen.Tests.Docs do
  @moduledoc false

  def short_doc do
    "Generates a default ExUnit suite (host + QEMU integration) for a soot_device project"
  end

  def example do
    "mix soot_device.gen.tests"
  end

  def long_doc do
    """
    #{short_doc()}

    Copies a set of test templates into the operator's project:

      * `test/<app>/device_test.exs` — host-side smoke tests for the
        `<App>.Device` DSL module and `<App>.SootDeviceConfig`
        helper. Run with `mix test`.
      * `test/<app>/qemu_test.exs` — QEMU integration tests tagged
        `@moduletag :qemu`. Run with `mix test --include qemu` after
        `MIX_TARGET=qemu_aarch64 MIX_ENV=test mix firmware`.
      * `test/support/qemu.ex` — `<App>.QEMU`, the QEMU boot + RPC
        helper the integration suite drives.
      * `rel/vm.args.eex` — bakes long-name distribution + cookie
        into the firmware **only** when built with `MIX_ENV=test`,
        so the QEMU helper can connect over Erlang distribution.

    Also patches:

      * `config/target.exs` — pins `inet_dist_listen_min/max` to
        `9100` to match the QEMU port forward.
      * `test/test_helper.exs` — adds `exclude: [:qemu]` so QEMU
        tests skip cleanly when no firmware image is built.

    The templates are maintained as plain Elixir source files in
    `priv/templates/tests/` of the `soot_device` package — the
    placeholder substitution scheme is documented in the README
    alongside them.

    The generator is composed by default from `mix igniter.install
    soot_device`. Pass `--no-tests` to that installer to opt out, or
    invoke this task manually.

    The generator is idempotent: re-running it skips files that
    already exist (operators own them post-install).

    ## Example

    ```bash
    #{example()}
    ```

    ## Options

      * `--yes` — answer yes to dependency-fetching prompts.
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.SootDevice.Gen.Tests do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"
    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @base_test_files ~w(device_test.exs qemu_test.exs)
    @example_test_files ~w(telemetry_test.exs)

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :soot,
        example: __MODULE__.Docs.example(),
        only: nil,
        composes: [],
        schema: [yes: :boolean, example: :boolean],
        # `--example` defaults to true here so a standalone
        # `mix soot_device.gen.tests` matches the experience of
        # `mix soot_device.install` (which also defaults to ON).
        defaults: [yes: false, example: true],
        aliases: [y: :yes, e: :example]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      options = igniter.args.options
      app_name = Igniter.Project.Application.app_name(igniter)
      app_module = Igniter.Project.Module.module_name_prefix(igniter)
      qemu_module = Igniter.Project.Module.module_name(igniter, "QEMU")

      igniter
      |> copy_test_files(app_name, app_module, options)
      |> maybe_add_duxedo_dep(options)
      |> scaffold_qemu_helper(qemu_module, app_module, app_name)
      |> scaffold_vm_args(app_name, app_module)
      |> patch_target_dist_config()
      |> patch_test_helper()
      |> note_next_steps(app_name, qemu_module, options)
    end

    defp copy_test_files(igniter, app_name, app_module, options) do
      app_subdir = Atom.to_string(app_name)

      files =
        if options[:example] do
          @base_test_files ++ @example_test_files
        else
          @base_test_files
        end

      Enum.reduce(files, igniter, fn filename, igniter ->
        contents =
          filename
          |> template_path()
          |> File.read!()
          |> rewrite_placeholders(app_module, app_name)

        destination = Path.join(["test", app_subdir, filename])

        Igniter.create_new_file(igniter, destination, contents, on_exists: :skip)
      end)
    end

    # The example telemetry test exercises the SootDeviceProtocol →
    # Duxedo capture path; that requires `:duxedo` in the operator's
    # deps so `Buffer.Duxedo` (which is gated on
    # `Code.ensure_loaded?(Duxedo.Streams)` at compile time) is
    # available. The dep is published only as a github-tracked branch
    # in the soot ecosystem today, matching the convention used by
    # soot_device_protocol's optional Duxedo backend.
    defp maybe_add_duxedo_dep(igniter, options) do
      if options[:example] do
        Igniter.Project.Deps.add_dep(
          igniter,
          {:duxedo, github: "soot-iot/duxedo", branch: "main"}
        )
      else
        igniter
      end
    end

    # `<App>.QEMU` lives in `test/support/`, namespaced under the
    # operator's app. `proper_location` with `module_location:
    # :outside_matching_folder` (the default) strips the matching app
    # prefix, so `Test.QEMU` lands at `test/support/qemu.ex` rather
    # than `test/support/test/qemu.ex`.
    defp scaffold_qemu_helper(igniter, qemu_module, app_module, app_name) do
      path =
        Igniter.Project.Module.proper_location(
          igniter,
          qemu_module,
          {:source_folder, "test/support"}
        )

      contents =
        "qemu.ex"
        |> template_path()
        |> File.read!()
        |> rewrite_placeholders(app_module, app_name)

      Igniter.create_new_file(igniter, path, contents, on_exists: :skip)
    end

    # `rel/vm.args.eex` overrides the Nerves system's default. Only
    # create it if the operator does not already have one — they may
    # have customized it for board-specific reasons we don't want to
    # clobber.
    defp scaffold_vm_args(igniter, app_name, app_module) do
      path = "rel/vm.args.eex"

      contents =
        "vm_args.eex"
        |> template_path()
        |> File.read!()
        |> rewrite_placeholders(app_module, app_name)

      Igniter.create_new_file(igniter, path, contents, on_exists: :skip)
    end

    # Pin Erlang distribution to port 9100 in target builds so the
    # QEMU port forward (`hostfwd=tcp::9100-:9100`) lines up.
    # Idempotent — re-running the generator no-ops once both keys
    # are set.
    defp patch_target_dist_config(igniter) do
      igniter
      |> Igniter.Project.Config.configure(
        "target.exs",
        :kernel,
        [:inet_dist_listen_min],
        9100
      )
      |> Igniter.Project.Config.configure(
        "target.exs",
        :kernel,
        [:inet_dist_listen_max],
        9100
      )
    end

    # If `test/test_helper.exs` is the bare `mix new` default
    # (`ExUnit.start()`), replace it with an explicit `exclude:
    # [:qemu]`. Anything already-customized is left alone with a
    # notice — operators own the file. Idempotent on the patched
    # form because the second pass sees `:qemu` and bails out.
    defp patch_test_helper(igniter) do
      path = "test/test_helper.exs"
      default_contents = "ExUnit.start(exclude: [:qemu])\n"

      Igniter.create_or_update_file(igniter, path, default_contents, fn source ->
        contents = Rewrite.Source.get(source, :content)

        cond do
          String.contains?(contents, ":qemu") ->
            source

          String.contains?(contents, "ExUnit.start()") ->
            new_contents =
              String.replace(
                contents,
                "ExUnit.start()",
                "ExUnit.start(exclude: [:qemu])"
              )

            Rewrite.Source.update(source, :content, new_contents)

          true ->
            {:notice,
             """
             test/test_helper.exs is non-default; skipped automatic
             patch. Add `exclude: [:qemu]` to its `ExUnit.start/1`
             call so the generated QEMU integration tests skip
             cleanly when no firmware image is built.
             """}
        end
      end)
    end

    # Order matters:
    #
    #   1. Rewrite `:my_device` → `:<app_atom>` first so the bare
    #      `my_device` rule doesn't strip the colon by accident.
    #   2. Rewrite the bare `my_device` token next — used in
    #      `vm.args.eex` as `-setcookie my_device_test_cookie`, where
    #      Erlang's cookie syntax has no leading colon.
    #   3. Rewrite `MyDevice` → operator's app module last; it does
    #      not overlap with the atom forms.
    defp rewrite_placeholders(contents, app_module, app_name) do
      app_module_str = inspect(app_module)
      app_atom_str = inspect(app_name)
      app_string = Atom.to_string(app_name)

      contents
      |> String.replace(":my_device", app_atom_str)
      |> String.replace("my_device", app_string)
      |> String.replace("MyDevice", app_module_str)
    end

    defp template_path(filename) do
      priv = :soot_device |> :code.priv_dir() |> to_string()
      Path.join([priv, "templates", "tests", filename])
    end

    defp note_next_steps(igniter, app_name, qemu_module, options) do
      telemetry_lines =
        if options[:example] do
          """

            * `test/#{app_name}/telemetry_test.exs` — `:telemetry` event
              emission + local Duxedo capture/query (added under
              `--example`).
            * `:duxedo` added to `mix.exs` deps (github main branch),
              required by the telemetry test's Duxedo describe block.
              Run `mix deps.get` once the install completes.
          """
        else
          ""
        end

      Igniter.add_notice(igniter, """
      Default test scaffolding generated.

      Files copied:
        * `test/#{app_name}/device_test.exs` — host-side smoke tests.
        * `test/#{app_name}/qemu_test.exs` — QEMU integration tests
          (tagged `:qemu`).
        * `test/support/qemu.ex` — `#{inspect(qemu_module)}` boot/RPC helper.
        * `rel/vm.args.eex` — distribution flags gated on
          `MIX_ENV=test`.
      #{telemetry_lines}
      Patched:
        * `config/target.exs` — `:kernel, inet_dist_listen_min/max:
          9100` so the QEMU port forward matches the dist port.
        * `test/test_helper.exs` — `exclude: [:qemu]`.

      Next steps:

        mix test                         # host-side tests only

        MIX_TARGET=qemu_aarch64 MIX_ENV=test mix firmware
        mix test --include qemu          # full suite incl. QEMU

      Operators own the generated files — re-running this task will
      not overwrite them.
      """)
    end
  end
else
  defmodule Mix.Tasks.SootDevice.Gen.Tests do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"
    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task `soot_device.gen.tests` requires igniter. Add
      `{:igniter, "~> 0.6"}` to your project deps and try again, or
      invoke via:

          mix igniter.install soot_device

      For more information, see https://hexdocs.pm/igniter
      """)

      exit({:shutdown, 1})
    end
  end
end
