defmodule SootDevice do
  @moduledoc """
  Declarative DSL on top of `soot_device_protocol`.

  Any module that `use SootDevice, contract_url: ..., enroll_url:
  ..., serial: ...` gets the four sections defined by
  `SootDevice.Extension`:

    * `identity do … end`   — bootstrap cert/key paths and storage
                              strategy.
    * `shadow do … end`     — `on_change` handlers and `report`
                              schedules.
    * `commands do … end`   — command-name → handler dispatch,
                              with payload format hints.
    * `telemetry do … end`  — per-stream sample + ingest configuration.

  The using module also gains `child_spec/1` (so it slots into a
  supervision tree) and `child_specs/1` (so a host can splice in extra
  imperative children).

  ## Example

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

  And, in the host application:

      Supervisor.start_link([MyDevice], strategy: :one_for_one)

  ## DSL ↔ imperative

  The DSL is sugar; everything it does is achievable by hand against
  the `SootDeviceProtocol.*` modules. Mix the two by overriding the
  generated `child_specs/1` or by registering extra commands /
  streams from a regular GenServer that runs alongside.
  """

  use Spark.Dsl,
    default_extensions: [extensions: [SootDevice.Extension]],
    opt_schema: [
      contract_url: [type: :string, required: true, doc: "URL of the contract bundle endpoint."],
      enroll_url: [type: :string, required: true, doc: "URL of the enrollment endpoint."],
      serial: [
        type: :string,
        required: true,
        doc: "Stable serial number identifying this device."
      ]
    ]

  @impl Spark.Dsl
  def handle_opts(opts) do
    quote bind_quoted: [opts: opts] do
      @soot_device_opts opts

      def __soot_device_opts__, do: @soot_device_opts

      def child_spec(extra_opts \\ []) do
        SootDevice.Runtime.child_spec(__MODULE__, extra_opts)
      end

      def child_specs(extra_opts \\ []) do
        SootDevice.Runtime.child_specs(__MODULE__, extra_opts)
      end

      def start_link(extra_opts \\ []) do
        SootDevice.Runtime.start_link(__MODULE__, extra_opts)
      end

      defoverridable child_spec: 1, child_specs: 1, start_link: 1
    end
  end
end
