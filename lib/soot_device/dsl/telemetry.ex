defmodule SootDevice.Dsl.Telemetry do
  @moduledoc false

  defmodule Sample do
    @moduledoc false
    defstruct [:interval, :source, __spark_metadata__: nil]
    @type t :: %__MODULE__{}
  end

  defmodule Stream do
    @moduledoc false
    defstruct [
      :name,
      :sample,
      :sequence_persist,
      :ingest_endpoint,
      :fingerprint,
      __spark_metadata__: nil
    ]

    @type t :: %__MODULE__{}
  end

  @sample %Spark.Dsl.Entity{
    name: :sample,
    target: __MODULE__.Sample,
    schema: [
      interval: [type: :pos_integer, doc: "Milliseconds between samples."],
      source: [type: :any, required: true, doc: "Zero-arity function returning the next row."]
    ]
  }

  @stream %Spark.Dsl.Entity{
    name: :stream,
    target: __MODULE__.Stream,
    args: [:name],
    entities: [sample: [@sample]],
    schema: [
      name: [type: :atom, required: true],
      sequence_persist: [
        type: {:in, [:file_system, :memory]},
        default: :file_system
      ],
      ingest_endpoint: [
        type: :string,
        doc: "Override the ingest endpoint. Defaults to /ingest/<name>."
      ],
      fingerprint: [
        type: :string,
        doc:
          "Static fingerprint pin. Optional; if absent the contract bundle " <>
            "supplies the fingerprint at runtime."
      ]
    ]
  }

  @section %Spark.Dsl.Section{
    name: :telemetry,
    describe: "Telemetry stream definitions for the local pipeline.",
    schema: [
      base_url: [
        type: :string,
        doc:
          "Override the ingest base URL. Defaults to the same host the " <>
            "device fetches its contract bundle from."
      ],
      retention_rows: [type: :pos_integer, default: 1_000_000],
      retention_bytes: [type: :pos_integer, default: 64 * 1024 * 1024],
      flush_interval_ms: [type: :pos_integer, default: 5_000]
    ],
    entities: [@stream]
  }

  def section, do: @section
end
