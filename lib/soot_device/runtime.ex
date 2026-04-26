defmodule SootDevice.Runtime do
  @moduledoc """
  Compile the contents of a `SootDevice`-using module into a list of
  imperative children for `SootDeviceProtocol.Supervisor`. The runtime
  is intentionally thin: it inspects the DSL via `SootDevice.Info`,
  reads files referenced by the identity block, and hands the result
  off to the imperative layer.

  Public entry points:

    * `child_spec/2`  — returns a `%{id, start, type}` spec the host
      can drop into a supervisor list.
    * `child_specs/2` — returns the flat list the spec expands to,
      useful for hosts that want to splice in extra components.
    * `start_link/2`  — launches the supervisor directly. Mainly used
      from tests.
  """

  alias SootDevice.Info
  alias SootDeviceProtocol.{Commands, Contract, Enrollment, MQTT, Shadow, Storage, Telemetry}

  @spec child_spec(module(), keyword()) :: Supervisor.child_spec()
  def child_spec(device, extra_opts \\ []) do
    %{
      id: device,
      start: {__MODULE__, :start_link, [device, extra_opts]},
      type: :supervisor
    }
  end

  @spec start_link(module(), keyword()) :: Supervisor.on_start()
  def start_link(device, extra_opts \\ []) do
    children = child_specs(device, extra_opts)
    Supervisor.start_link(children, strategy: :rest_for_one, name: extra_opts[:name] || device)
  end

  @doc """
  Expand the DSL into a flat list of `Supervisor.child_spec/1` tuples.
  """
  @spec child_specs(module(), keyword()) :: [Supervisor.child_spec()]
  def child_specs(device, extra_opts \\ []) do
    use_opts = device.__soot_device_opts__()
    extra_opts = Keyword.merge(use_opts, extra_opts)

    serial = Keyword.fetch!(extra_opts, :serial)
    contract_url = Keyword.fetch!(extra_opts, :contract_url)
    enroll_url = Keyword.fetch!(extra_opts, :enroll_url)
    base_url = derive_base_url(contract_url)

    identity = Info.identity(device)
    storage = open_storage(identity, extra_opts)

    trust_pems = read_trust_pems(identity, extra_opts)
    bootstrap_cert = read_optional_file(identity[:bootstrap_cert_path])
    bootstrap_key = read_optional_file(identity[:bootstrap_key_path])
    enrollment_token = lookup_enrollment_token(identity, extra_opts)
    subject = identity[:subject] || "/CN=#{serial}"

    enrollment_opts = [
      storage: storage,
      enroll_url: enroll_url,
      enrollment_token: enrollment_token,
      bootstrap_cert: bootstrap_cert,
      bootstrap_key: bootstrap_key,
      trust_pems: trust_pems,
      subject: subject,
      auto_enroll: Keyword.get(extra_opts, :auto_enroll, true),
      name: name(device, :enrollment)
    ]

    mqtt_opts =
      case Keyword.get(extra_opts, :mqtt) do
        nil -> nil
        :disabled -> nil
        opts -> Keyword.put_new(opts, :name, name(device, :mqtt))
      end

    contract_opts = [
      url: contract_url,
      storage: storage,
      trust_pems: trust_pems,
      interval_ms: Keyword.get(extra_opts, :contract_interval_ms, 300_000),
      auto_refresh: Keyword.get(extra_opts, :auto_refresh, true),
      name: name(device, :contract)
    ]

    shadow_opts = build_shadow_opts(device, serial, name(device, :mqtt), storage, extra_opts)

    commands_opts =
      build_commands_opts(device, serial, name(device, :mqtt), extra_opts)

    telemetry_opts = build_telemetry_opts(device, base_url, storage, extra_opts)

    [
      {Enrollment, enrollment_opts}
    ]
    |> append_if(mqtt_opts != nil, fn -> {MQTT.Client, mqtt_opts} end)
    |> Kernel.++([{Contract.Refresh, contract_opts}])
    |> append_if(shadow_opts != nil, fn -> {Shadow.Sync, shadow_opts} end)
    |> append_if(commands_opts != nil, fn -> {Commands.Dispatcher, commands_opts} end)
    |> append_if(telemetry_opts != nil, fn -> {Telemetry.Pipeline, telemetry_opts} end)
  end

  # ─── option builders ────────────────────────────────────────────────

  defp build_shadow_opts(device, serial, mqtt_name, storage, extra_opts) do
    handlers = Info.shadow_handlers(device)
    options = Info.shadow_options(device)

    if handlers == %{} and options[:base_topic] == nil and
         not Keyword.get(extra_opts, :force_shadow?, false) do
      nil
    else
      base = options[:base_topic] || "tenants/_/devices/#{serial}/shadow"

      [
        base_topic: base,
        mqtt_client: mqtt_name,
        storage: storage,
        handlers: handlers,
        qos: options[:qos],
        retain: options[:retain],
        name: name(device, :shadow)
      ]
    end
  end

  defp build_commands_opts(device, serial, mqtt_name, extra_opts) do
    commands = Info.commands(device)

    if commands == [] and not Keyword.get(extra_opts, :force_commands?, false) do
      nil
    else
      mapped =
        Enum.map(commands, fn cmd ->
          %{
            name: Atom.to_string(cmd.name),
            topic: cmd.topic || "tenants/_/devices/#{serial}/cmd/#{cmd.name}",
            payload_format: cmd.payload_format,
            qos: cmd.qos,
            handler: cmd.handler
          }
        end)

      [
        mqtt_client: mqtt_name,
        commands: mapped,
        name: name(device, :commands)
      ]
    end
  end

  defp build_telemetry_opts(device, base_url, storage, extra_opts) do
    streams = Info.streams(device)

    if streams == [] and not Keyword.get(extra_opts, :force_telemetry?, false) do
      nil
    else
      options = Info.telemetry_options(device)

      stream_configs =
        Enum.map(streams, fn s ->
          {Atom.to_string(s.name),
           %{
             fingerprint: s.fingerprint || "pending",
             ingest_endpoint: s.ingest_endpoint || "/ingest/#{s.name}"
           }}
        end)

      [
        base_url: options[:base_url] || base_url,
        storage: storage,
        streams: stream_configs,
        retention_rows: options[:retention_rows],
        retention_bytes: options[:retention_bytes],
        flush_interval_ms: options[:flush_interval_ms],
        name: name(device, :telemetry)
      ]
    end
  end

  # ─── helpers ────────────────────────────────────────────────────────

  defp open_storage(identity, extra_opts) do
    case Keyword.get(extra_opts, :storage) do
      nil ->
        case identity[:operational_storage] do
          :memory ->
            Storage.Memory.open!()

          :file_system ->
            Storage.Local.open!(identity[:storage_dir])
        end

      binding ->
        binding
    end
  end

  defp read_trust_pems(identity, extra_opts) do
    case Keyword.get(extra_opts, :trust_pems) do
      nil ->
        case identity[:trust_pem_path] do
          nil -> []
          path -> [File.read!(path)]
        end

      pems when is_list(pems) ->
        pems
    end
  end

  defp read_optional_file(nil), do: nil
  defp read_optional_file(path) when is_binary(path), do: File.read!(path)

  defp lookup_enrollment_token(identity, extra_opts) do
    case Keyword.get(extra_opts, :enrollment_token) do
      nil ->
        case identity[:enrollment_token_env] do
          nil -> nil
          var -> System.get_env(var)
        end

      token ->
        token
    end
  end

  defp derive_base_url(contract_url) do
    uri = URI.parse(contract_url)
    "#{uri.scheme}://#{uri.host}#{port_segment(uri.port)}"
  end

  defp port_segment(nil), do: ""
  defp port_segment(80), do: ""
  defp port_segment(443), do: ""
  defp port_segment(p), do: ":#{p}"

  defp name(device, suffix), do: Module.concat([device, "Runtime", to_pascal(suffix)])

  defp to_pascal(:enrollment), do: "Enrollment"
  defp to_pascal(:mqtt), do: "MQTT"
  defp to_pascal(:contract), do: "Contract"
  defp to_pascal(:shadow), do: "Shadow"
  defp to_pascal(:commands), do: "Commands"
  defp to_pascal(:telemetry), do: "Telemetry"

  defp append_if(list, false, _fun), do: list
  defp append_if(list, true, fun), do: list ++ [fun.()]
end
