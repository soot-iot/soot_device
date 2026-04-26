# Changelog

## v0.1.0 — Unreleased

Initial public release. Declarative DSL on top of `soot_device_protocol`.

### Added

* `use SootDevice, contract_url:, enroll_url:, serial:` macro that
  installs the four DSL sections via `SootDevice.Extension`.
* `identity do … end` — bootstrap cert/key paths, persistent storage
  backend, enrollment-token environment variable, optional CSR
  subject.
* `shadow do … end` — `on_change` handlers and `report` schedules,
  with optional `base_topic` / `qos` / `retain` overrides.
* `commands do … end` — `handle` entries that compile into the
  imperative dispatcher with payload-format hints.
* `telemetry do … end` — per-stream `sample` blocks plus retention
  and flush-interval knobs.
* `SootDevice.Info` introspection helpers (`identity/1`,
  `shadow_handlers/1`, `shadow_reports/1`, `shadow_options/1`,
  `commands/1`, `streams/1`, `telemetry_options/1`).
* `SootDevice.Runtime.{child_spec, child_specs, start_link}/2` —
  expand the DSL into a `:rest_for_one` tree of
  `SootDeviceProtocol.*` children.
