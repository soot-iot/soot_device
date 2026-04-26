defmodule SootDevice.RuntimeTest do
  use ExUnit.Case, async: true

  alias SootDevice.Runtime
  alias SootDevice.Test.TestDevice
  alias SootDeviceProtocol.{Commands, Contract, Enrollment, MQTT, Shadow, Telemetry}

  test "child_specs/2 expands a TestDevice into the expected imperative children" do
    specs = Runtime.child_specs(TestDevice, enrollment_token: "TOKEN")

    modules = Enum.map(specs, fn {mod, _opts} -> mod end)

    assert Enrollment in modules
    assert Contract.Refresh in modules
    assert Shadow.Sync in modules
    assert Commands.Dispatcher in modules
    assert Telemetry.Pipeline in modules
    refute MQTT.Client in modules
  end

  test "child_spec/2 returns a supervisor child spec" do
    spec = Runtime.child_spec(TestDevice, enrollment_token: "TOKEN")
    assert spec.id == TestDevice
    assert spec.type == :supervisor
  end

  test "shadow opts wire handlers from the DSL", _ctx do
    [_enroll | rest] = Runtime.child_specs(TestDevice, enrollment_token: "TOKEN")
    {Shadow.Sync, opts} = Enum.find(rest, fn {mod, _} -> mod == Shadow.Sync end)
    assert opts[:handlers][:led]
    assert opts[:base_topic] =~ "ACME-WIDGET-0001-000001"
  end

  test "commands opts wire DSL declarations into the dispatcher" do
    [_enroll | rest] = Runtime.child_specs(TestDevice, enrollment_token: "TOKEN")
    {Commands.Dispatcher, opts} = Enum.find(rest, fn {mod, _} -> mod == Commands.Dispatcher end)
    names = Enum.map(opts[:commands], & &1.name)
    assert "reboot" in names
    assert "read_config" in names
  end

  test "telemetry opts use the contract url's host as base_url" do
    [_enroll | rest] = Runtime.child_specs(TestDevice, enrollment_token: "TOKEN")
    {Telemetry.Pipeline, opts} = Enum.find(rest, fn {mod, _} -> mod == Telemetry.Pipeline end)
    assert opts[:base_url] == "https://soot.example.com"
    [{"vibration", _}] = opts[:streams]
  end

  test "use SootDevice without :contract_url raises" do
    assert_raise Spark.Options.ValidationError, ~r/contract_url/, fn ->
      defmodule BadDevice do
        use SootDevice, enroll_url: "https://x", serial: "x"
      end
    end
  end

  test "use SootDevice without :serial raises" do
    assert_raise Spark.Options.ValidationError, ~r/serial/, fn ->
      defmodule BadDevice2 do
        use SootDevice, contract_url: "https://x", enroll_url: "https://y"
      end
    end
  end
end
