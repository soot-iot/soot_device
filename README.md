# soot_device

Declarative DSL on top of [`soot_device_protocol`](../soot_device_protocol).

A single `device do … end` module compiles into a fully-wired
`SootDeviceProtocol.Supervisor`: enrollment, contract refresh, MQTT,
shadow, commands, telemetry. The DSL is sugar; everything it does is
achievable by hand against the imperative layer.

```elixir
defmodule MyDevice do
  use SootDevice,
    contract_url: "https://soot.example.com/.well-known/soot/contract",
    enroll_url:   "https://soot.example.com/enroll",
    serial:       "ACME-EU-WIDGET-0001-000001"

  identity do
    bootstrap_cert_path "/data/pki/bootstrap.pem"
    bootstrap_key_path  "/data/pki/bootstrap.key"
    trust_pem_path      "/data/pki/trust.pem"
    operational_storage :file_system
    storage_dir         "/data/soot"
  end

  shadow do
    on_change :led, &MyDevice.handle_led/2
  end

  commands do
    handle :reboot, &MyDevice.handle_reboot/2, payload_format: :empty
  end

  telemetry do
    stream :vibration do
      sample interval: 100, source: &MyDevice.read_vibration/0
    end
  end

  def handle_led(_value, _meta), do: :ok
  def handle_reboot(_payload, _meta), do: :ok
  def read_vibration, do: %{"x" => :rand.uniform()}
end
```

Then in the host:

```elixir
Supervisor.start_link([MyDevice], strategy: :one_for_one)
```
