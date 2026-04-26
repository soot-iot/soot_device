defmodule SootDevice.InfoOptionsTest do
  use ExUnit.Case, async: true

  alias SootDevice.Dsl
  alias SootDevice.Info
  alias SootDevice.Test.TestDevice

  describe "shadow_options/1" do
    test "defaults qos and retain when the section omits them" do
      opts = Info.shadow_options(TestDevice)
      assert opts[:qos] == 1
      assert opts[:retain] == false
    end

    test "base_topic is nil when not overridden" do
      assert Info.shadow_options(TestDevice)[:base_topic] == nil
    end
  end

  describe "telemetry_options/1" do
    test "applies defaults when the section omits explicit values" do
      opts = Info.telemetry_options(TestDevice)
      assert opts[:retention_rows] == 1_000_000
      assert opts[:retention_bytes] == 64 * 1024 * 1024
      assert opts[:flush_interval_ms] == 5_000
      assert opts[:base_url] == nil
    end
  end

  describe "shadow_reports/1" do
    test "captures the every: schedule on a periodic report" do
      reports = Info.shadow_reports(TestDevice)

      assert %Dsl.Shadow.Report{key: :uptime, every: 60_000, value: value} =
               Enum.find(reports, &(&1.key == :uptime))

      assert is_function(value, 0)
    end

    test "returns reports in declaration order" do
      keys = TestDevice |> Info.shadow_reports() |> Enum.map(& &1.key)
      assert keys == [:firmware_version, :uptime]
    end
  end
end
