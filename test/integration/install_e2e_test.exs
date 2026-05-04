defmodule SootDevice.InstallE2ETest do
  @moduledoc """
  End-to-end harness for `mix igniter.install soot_device`.

  Generates a fresh `mix new --sup` project, points it at *this*
  `soot_device` checkout via a path-dep, runs the installer (which
  composes `mix soot_device.gen.tests` by default), and finally runs
  `mix test` inside the generated project. The test passes only if
  the scaffolded host-side suite passes.

  Tagged `:install_e2e` and excluded from the default test run by
  `test/test_helper.exs`. Opt in with:

      mix test --include install_e2e

  Slow (~30 seconds) — `mix deps.get` + a fresh PLT for the generated
  project dominate. Skipped automatically if `mix` is not on PATH.
  """

  use ExUnit.Case, async: false

  @moduletag :install_e2e
  @moduletag timeout: :timer.minutes(10)

  @app_name "my_device"

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "soot_device_install_e2e_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  test "scaffolded host suite passes against a freshly installed soot_device project", %{tmp: tmp} do
    soot_device_path = File.cwd!()
    project_path = Path.join(tmp, @app_name)

    run_step!(["new", @app_name, "--sup"], cd: tmp, label: "mix new --sup")

    inject_soot_device_path_dep!(project_path, soot_device_path)

    run_step!(["deps.get"], cd: project_path, label: "deps.get (post-inject)")

    run_step!(["soot_device.install", "--yes"],
      cd: project_path,
      label: "soot_device.install"
    )

    # The installer composes `soot_device.gen.tests` which adds the
    # `:duxedo` dep so the example telemetry test compiles. Fetch
    # the new transitive deps before running tests.
    run_step!(["deps.get"], cd: project_path, label: "deps.get (post-install)")

    {output, code} =
      System.cmd("mix", ["test"],
        cd: project_path,
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}]
      )

    assert code == 0, """
    Host-side tests failed in the generated project.

    cwd: #{project_path}

    --- mix test ---
    #{output}
    """

    # The scaffolded qemu_test.exs is excluded by default. Verify the
    # generator wrote the file as a sanity check.
    assert File.exists?(Path.join([project_path, "test", @app_name, "qemu_test.exs"])),
           "qemu_test.exs not generated"

    # `--example` (default ON) scaffolds the telemetry test that
    # exercises :telemetry events + Duxedo capture.
    assert File.exists?(Path.join([project_path, "test", @app_name, "telemetry_test.exs"])),
           "telemetry_test.exs not generated under --example"

    assert File.exists?(Path.join([project_path, "test/support/qemu.ex"])),
           "qemu.ex helper not generated"

    assert File.exists?(Path.join([project_path, "rel/vm.args.eex"])),
           "rel/vm.args.eex not generated"
  end

  defp run_step!(args, opts) do
    label = Keyword.fetch!(opts, :label)
    cd = Keyword.fetch!(opts, :cd)

    {output, code} = System.cmd("mix", args, cd: cd, stderr_to_stdout: true)

    if code != 0 do
      flunk("""
      Step `mix #{Enum.join(args, " ")}` failed (#{label}, exit #{code}).

      cwd: #{cd}

      --- output ---
      #{output}
      """)
    end

    output
  end

  # Adds `{:soot_device, path: <local>, override: true}` and
  # `{:igniter, "~> 0.6"}` to the operator's deps so the e2e runs
  # against *this* checkout. Igniter is needed at runtime because
  # `mix soot_device.install` is an Igniter task; it does not auto-add
  # itself to the operator's deps.
  #
  # `Application.ensure_all_started(:igniter)` is required because
  # Igniter relies on `Rewrite.TaskSupervisor` and friends which only
  # start when the `:rewrite` and `:igniter` apps are up. We run the
  # injection in a child Elixir process so the test process's
  # Mix.Project state stays clean — `mix new` does not leave Igniter
  # compiled, so we use `Mix.install/2` from inside the project.
  defp inject_soot_device_path_dep!(project_path, soot_device_path) do
    script = """
    Mix.install([
      {:igniter, "~> 0.6"},
      {:soot_device, path: #{inspect(soot_device_path)}, override: true}
    ])

    Igniter.new()
    |> Igniter.Project.Deps.add_dep(
      {:soot_device, [path: #{inspect(soot_device_path)}, override: true]},
      yes?: true
    )
    |> Igniter.Project.Deps.add_dep(
      {:igniter, "~> 0.6"},
      yes?: true
    )
    |> Igniter.do_or_dry_run(yes: true)
    """

    {output, code} =
      System.cmd("elixir", ["-e", script],
        cd: project_path,
        stderr_to_stdout: true
      )

    if code != 0 do
      flunk("""
      Failed to inject :soot_device path-dep via Igniter (exit #{code}).

      cwd: #{project_path}

      --- output ---
      #{output}
      """)
    end
  end
end
