defmodule SootDevice.Dsl.Shadow do
  @moduledoc false

  defmodule OnChange do
    @moduledoc false
    defstruct [:key, :handler, __spark_metadata__: nil]
    @type t :: %__MODULE__{key: atom(), handler: term()}
  end

  defmodule Report do
    @moduledoc false
    defstruct [:key, :value, :every, __spark_metadata__: nil]
    @type t :: %__MODULE__{key: atom(), value: term(), every: term()}
  end

  @on_change %Spark.Dsl.Entity{
    name: :on_change,
    target: __MODULE__.OnChange,
    args: [:key, :handler],
    schema: [
      key: [type: :atom, required: true],
      handler: [type: :any, required: true]
    ]
  }

  @report %Spark.Dsl.Entity{
    name: :report,
    target: __MODULE__.Report,
    args: [:key],
    schema: [
      key: [type: :atom, required: true],
      value: [type: :any],
      every: [type: :any]
    ]
  }

  @section %Spark.Dsl.Section{
    name: :shadow,
    describe: "Device-shadow handlers and reported-state schedule.",
    schema: [
      base_topic: [
        type: :string,
        doc:
          "Override the shadow base topic. Defaults to a value derived " <>
            "from the device's serial."
      ],
      qos: [type: {:in, [0, 1, 2]}, default: 1],
      retain: [type: :boolean, default: false]
    ],
    entities: [@on_change, @report]
  }

  def section, do: @section
end
