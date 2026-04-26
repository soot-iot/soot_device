defmodule SootDevice.Test.QEMU do
  @moduledoc """
  Boots a Nerves QEMU image and connects to it over Erlang distribution
  so the host-side test process can drive it via `:rpc.call/4`.

  This module lives in `test/support/` deliberately — it ships with
  the soot_device library's test code (compiled into
  `elixirc_paths(:test)`) and is also scaffolded into the operator's
  project by `mix igniter.install soot_device`. It is **never**
  compiled into the device firmware. A QEMU helper has no business
  in a Nerves rootfs.

  ## How it works

    1. Locate a `qemu_aarch64` Nerves firmware image under
       `_build/qemu_aarch64_*/nerves/images/`.
    2. Launch `qemu-system-aarch64` with user-mode networking and
       hostfwd port forwards for EPMD (4369) and the pinned
       distribution port (9100).
    3. Poll `Node.connect/1` until the device's node registers.
    4. Return a handle that callers can pass to `rpc/4` and `stop/1`.

  User-mode networking (`-netdev user`) needs no special privileges,
  so this works on developer laptops, CI runners, and Docker hosts
  alike. The trade-off: the device cannot reach the host's
  `localhost`. Test backends that need callbacks should bind
  `0.0.0.0` and use the QEMU gateway IP `10.0.2.2`.

  ## Tagging convention

  Tests that depend on this helper should be tagged `@tag :qemu` so
  they skip cleanly when prerequisites are missing
  (`qemu-system-aarch64` not on PATH, or no firmware image built).
  """

  require Logger

  defstruct [:port, :node, :tmp_dir]

  @type t :: %__MODULE__{port: port(), node: node(), tmp_dir: String.t()}

  @device_node :"soot-device@127.0.0.1"
  @cookie :soot_device_test_cookie

  @doc """
  Returns `:ok` if the prerequisites for `boot/1` are present:
  `qemu-system-aarch64` on PATH and a built firmware image.
  Otherwise returns `{:error, reason}` so test cases can `skip`
  cleanly.
  """
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

  @doc """
  Boots the QEMU image and waits for the device node to register.

  ## Options

    * `:timeout` — milliseconds to wait for distribution; default `60_000`.
    * `:image` — override the firmware image path.
    * `:extra_args` — extra args appended to the qemu command line.
    * `:cookie` — Erlang cookie; default `:#{@cookie}`. Must match the
      firmware's release configuration.
    * `:device_node` — node atom to wait for; default
      `:"#{@device_node}"`.
  """
  @spec boot(keyword()) :: {:ok, t()} | {:error, term()}
  def boot(opts \\ []) do
    cookie = Keyword.get(opts, :cookie, @cookie)
    device_node = Keyword.get(opts, :device_node, @device_node)

    with :ok <- available?(),
         :ok <- ensure_distribution_running(cookie) do
      image = Keyword.get(opts, :image) || firmware_image_path()
      timeout = Keyword.get(opts, :timeout, 60_000)
      extra = Keyword.get(opts, :extra_args, [])
      tmp = Path.join(System.tmp_dir!(), "soot-qemu-#{System.unique_integer([:positive])}")
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

  @doc "Stops the QEMU process and disconnects the device node."
  @spec stop(t()) :: :ok
  def stop(%__MODULE__{port: port, node: node, tmp_dir: tmp}) do
    Node.disconnect(node)
    stop_port(port)
    File.rm_rf!(tmp)
    :ok
  end

  @doc """
  Convenience wrapper for `:rpc.call/4` against the running device.

  Raises `RuntimeError` if the call returns `{:badrpc, _}` so test
  failures point at the actual problem rather than a confusing
  pattern-match failure downstream.
  """
  @spec rpc(t(), module(), atom(), [term()]) :: term()
  def rpc(%__MODULE__{node: node}, mod, fun, args) do
    case :rpc.call(node, mod, fun, args) do
      {:badrpc, reason} ->
        raise "rpc to #{inspect(node)} failed: #{inspect(reason)}"

      result ->
        result
    end
  end

  @doc """
  Returns the absolute path to the latest qemu_aarch64 firmware
  image, or `nil` if no image has been built. Looks in
  `_build/qemu_aarch64_*/nerves/images/`.
  """
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
        "-machine",
        "virt",
        "-cpu",
        "cortex-a72",
        "-smp",
        "2",
        "-m",
        "1024",
        "-nographic",
        "-drive",
        "if=virtio,file=#{image},format=raw",
        "-netdev",
        "user,id=net0,hostfwd=tcp::4369-:4369,hostfwd=tcp::9100-:9100",
        "-device",
        "virtio-net-device,netdev=net0"
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
