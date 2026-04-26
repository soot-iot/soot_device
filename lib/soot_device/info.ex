defmodule SootDevice.Info do
  @moduledoc """
  Introspection helpers for modules that `use SootDevice`.

      SootDevice.Info.identity(MyDevice)
      SootDevice.Info.shadow_handlers(MyDevice)
      SootDevice.Info.commands(MyDevice)
      SootDevice.Info.streams(MyDevice)
  """

  use Spark.InfoGenerator,
    extension: SootDevice.Extension,
    sections: [:identity, :shadow, :commands, :telemetry]

  alias SootDevice.Dsl

  @doc "All `on_change` declarations as a `%{key => handler}` map."
  @spec shadow_handlers(module()) :: %{required(atom()) => term()}
  def shadow_handlers(device) do
    device
    |> Spark.Dsl.Extension.get_entities([:shadow])
    |> Enum.filter(&match?(%Dsl.Shadow.OnChange{}, &1))
    |> Map.new(fn %{key: key, handler: handler} -> {key, handler} end)
  end

  @doc "All `report` declarations."
  @spec shadow_reports(module()) :: [Dsl.Shadow.Report.t()]
  def shadow_reports(device) do
    device
    |> Spark.Dsl.Extension.get_entities([:shadow])
    |> Enum.filter(&match?(%Dsl.Shadow.Report{}, &1))
  end

  @doc "Every command handler registered in the `commands do …` block."
  @spec commands(module()) :: [Dsl.Commands.Handle.t()]
  def commands(device) do
    Spark.Dsl.Extension.get_entities(device, [:commands])
  end

  @doc "Every stream registered in the `telemetry do …` block."
  @spec streams(module()) :: [Dsl.Telemetry.Stream.t()]
  def streams(device) do
    Spark.Dsl.Extension.get_entities(device, [:telemetry])
  end

  @doc "Identity options as a flat keyword list."
  @spec identity(module()) :: keyword()
  def identity(device) do
    [
      bootstrap_cert_path: get(device, :identity, :bootstrap_cert_path),
      bootstrap_key_path: get(device, :identity, :bootstrap_key_path),
      operational_storage: get(device, :identity, :operational_storage, :file_system),
      storage_dir: get(device, :identity, :storage_dir, "/data/soot"),
      enrollment_token_env:
        get(device, :identity, :enrollment_token_env, "SOOT_ENROLLMENT_TOKEN"),
      trust_pem_path: get(device, :identity, :trust_pem_path),
      subject: get(device, :identity, :subject)
    ]
  end

  @doc "Shadow section options (qos / retain / base_topic override)."
  @spec shadow_options(module()) :: keyword()
  def shadow_options(device) do
    [
      base_topic: get(device, :shadow, :base_topic),
      qos: get(device, :shadow, :qos, 1),
      retain: get(device, :shadow, :retain, false)
    ]
  end

  @doc "Telemetry section options."
  @spec telemetry_options(module()) :: keyword()
  def telemetry_options(device) do
    [
      base_url: get(device, :telemetry, :base_url),
      retention_rows: get(device, :telemetry, :retention_rows, 1_000_000),
      retention_bytes: get(device, :telemetry, :retention_bytes, 64 * 1024 * 1024),
      flush_interval_ms: get(device, :telemetry, :flush_interval_ms, 5_000)
    ]
  end

  defp get(device, section, name, default \\ nil) do
    case Spark.Dsl.Extension.get_opt(device, [section], name) do
      nil -> default
      :error -> default
      value -> value
    end
  end
end
