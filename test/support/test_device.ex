defmodule SootDevice.Test.TestDevice do
  use SootDevice,
    contract_url: "https://soot.example.com/.well-known/soot/contract",
    enroll_url: "https://soot.example.com/enroll",
    serial: "ACME-WIDGET-0001-000001"

  identity do
    operational_storage(:memory)
  end

  shadow do
    on_change(:led, &__MODULE__.handle_led/2)
    on_change(:sample_rate, &__MODULE__.handle_sample_rate/2)
    report(:firmware_version, value: "0.4.2")
    report(:uptime, every: 60_000, value: &__MODULE__.read_uptime/0)
  end

  commands do
    handle(:reboot, &__MODULE__.handle_reboot/2, payload_format: :empty)
    handle(:read_config, &__MODULE__.handle_read_config/2, payload_format: :json)
  end

  telemetry do
    stream :vibration do
      sample(interval: 100, source: &__MODULE__.read_vibration/0)
    end
  end

  def handle_led(_value, _meta), do: :ok
  def handle_sample_rate(_value, _meta), do: :ok
  def handle_reboot(_payload, _meta), do: :ok
  def handle_read_config(_payload, _meta), do: {:reply, "{}"}
  def read_vibration, do: %{"x" => 1.0}
  def read_uptime, do: 42
end
