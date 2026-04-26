defmodule SootDevice.InfoTest do
  use ExUnit.Case, async: true

  alias SootDevice.Dsl
  alias SootDevice.Info
  alias SootDevice.Test.TestDevice

  test "shadow_handlers/1 returns every on_change as a key/handler map" do
    handlers = Info.shadow_handlers(TestDevice)
    assert Map.keys(handlers) |> Enum.sort() == [:led, :sample_rate]
  end

  test "shadow_reports/1 returns every report declaration" do
    reports = Info.shadow_reports(TestDevice)
    assert [%Dsl.Shadow.Report{key: :firmware_version, value: "0.4.2"}] = reports
  end

  test "commands/1 returns every command handler entity" do
    commands = Info.commands(TestDevice)
    names = Enum.map(commands, & &1.name)
    assert :reboot in names
    assert :read_config in names

    [reboot] = Enum.filter(commands, &(&1.name == :reboot))
    assert reboot.payload_format == :empty
  end

  test "streams/1 returns every stream entity" do
    [stream] = Info.streams(TestDevice)
    assert stream.name == :vibration
  end

  test "identity/1 returns a flat keyword list with defaults" do
    identity = Info.identity(TestDevice)
    assert identity[:operational_storage] == :memory
    assert identity[:enrollment_token_env] == "SOOT_ENROLLMENT_TOKEN"
  end
end
