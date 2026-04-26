defmodule SootDevice.Dsl.Commands do
  @moduledoc false

  defmodule Handle do
    @moduledoc false
    defstruct [:name, :handler, :payload_format, :qos, :topic, __spark_metadata__: nil]
    @type t :: %__MODULE__{}
  end

  @handle %Spark.Dsl.Entity{
    name: :handle,
    target: __MODULE__.Handle,
    args: [:name, :handler],
    schema: [
      name: [type: :atom, required: true],
      handler: [type: :any, required: true],
      payload_format: [
        type: {:in, [:json, :binary, :empty]},
        default: :binary
      ],
      qos: [type: {:in, [0, 1, 2]}, default: 1],
      topic: [
        type: :string,
        doc:
          "Override the command topic. Defaults to a value derived " <>
            "from the device's serial and the command name."
      ]
    ]
  }

  @section %Spark.Dsl.Section{
    name: :commands,
    describe: "Command handlers wired into the dispatcher at start.",
    entities: [@handle]
  }

  def section, do: @section
end
