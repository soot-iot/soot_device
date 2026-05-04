# Default test scaffolding templates

Source files copied verbatim (with module-name substitution) into an
operator's project by `mix soot_device.gen.tests`. The generator is
composed by default from `mix igniter.install soot_device`, so a
freshly-installed device project ships with this suite.

These files **do not compile** as part of the `soot_device` library —
they live in `priv/` so they can be authored and reviewed as plain
Elixir rather than as strings inside an Igniter task. Once copied
into the operator's project, the placeholders are rewritten to the
operator's module / atom and the result is valid Elixir.

## Placeholder names

The igniter rewrites these tokens at copy time:

| Token         | Replaced with                                     |
| ------------- | ------------------------------------------------- |
| `MyDevice`    | Operator's app module (e.g., `MyIotDevice`)       |
| `:my_device`  | Operator's app atom (e.g., `:my_iot_device`)      |

Substitution preserves substring boundaries — both tokens are
distinctive enough that there are no collisions across the templates.

## What's covered

- `device_test.exs` — host-side unit tests for `<App>.Device`. Asserts
  the SootDevice DSL module compiles, exports `__soot_device_opts__/0`
  with the configured contract URL / enroll URL / serial, and that
  `child_spec/1` returns a valid Supervisor child spec map. Run with
  `mix test`.

- `qemu_test.exs` — QEMU integration tests tagged `@moduletag :qemu`.
  Boots the firmware image, connects to it over Erlang distribution,
  and asserts the operator's application + DSL module are loaded on
  the device. Run with `mix test --include qemu` after building the
  firmware (`MIX_TARGET=qemu_aarch64 mix firmware`).

- `qemu.ex` — `<App>.QEMU` helper that the QEMU integration test
  uses. Locates the firmware image, launches `qemu-system-aarch64`
  with user-mode networking + EPMD/dist port forwards, and exposes
  `boot/1`, `stop/1`, and `rpc/4`.

- `vm_args.eex` — `rel/vm.args.eex` baking long-name distribution
  + the cookie into the firmware so the QEMU test process can
  connect. Generated only when the operator does not already have
  one (Nerves systems bundle a default that omits distribution).

## What gets patched

In addition to creating new files, the generator patches:

- `config/target.exs` (Nerves projects only) — pins
  `inet_dist_listen_min/max` to `9100` so the QEMU port forward
  matches the Erlang distribution port.

- `test/test_helper.exs` — replaces a bare `ExUnit.start()` with
  `ExUnit.start(exclude: [:qemu])` so QEMU tests skip cleanly when
  no firmware image is built.

The generator is idempotent: re-running it skips files that already
exist (operators own them post-install).
