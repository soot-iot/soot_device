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

## Installer

For a brand-new Nerves project, the installer scaffolds the device
module, a config helper, and the supervision tree wiring in one shot:

```bash
mix nerves.new my_device --target qemu_aarch64
cd my_device
# add {:soot_device, "~> 0.1"} (or `path:` while developing) to deps,
# then:
mix deps.get
mix soot_device.install --yes
```

This generates:

  * `lib/my_device/device.ex` — the `SootDevice` DSL module with stub
    `identity`, `shadow`, `commands`, and `telemetry` blocks.
  * `lib/my_device/soot_device_config.ex` — the runtime helper that
    reads `:my_device` Application env (env-var-overridable defaults
    seeded into `config/config.exs`) and feeds it to the supervisor.
  * `{MyDevice.Device, MyDevice.SootDeviceConfig.device_opts()}` in
    your `Application.start/2`.

Override the runtime values by setting `MY_DEVICE_CONTRACT_URL`,
`MY_DEVICE_ENROLL_URL`, `MY_DEVICE_SERIAL`, and friends. See the
notice the installer prints for the full list.

For imperative control over enrollment / contract / MQTT / shadow /
commands / telemetry instead of the DSL, use
`mix igniter.install soot_device_protocol`.
