defmodule SootDevice.Extension do
  @moduledoc """
  Spark extension that contributes the four `SootDevice` sections —
  `identity`, `shadow`, `commands`, `telemetry` — to a using module.

  This is wired up automatically via `use SootDevice, ...`; users do
  not need to reference the extension by hand.
  """

  alias SootDevice.Dsl

  @identity_section %Spark.Dsl.Section{
    name: :identity,
    describe: "Identity and persistent storage configuration.",
    schema: Dsl.Identity.schema()
  }

  use Spark.Dsl.Extension,
    sections: [
      @identity_section,
      Dsl.Shadow.section(),
      Dsl.Commands.section(),
      Dsl.Telemetry.section()
    ]
end
