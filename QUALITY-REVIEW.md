# soot_device — Quality Review

Findings against the playbook in `../QUALITY-REVIEW.md`. Baseline:
12 tests, 0 failures; format clean; no gate, no lint stack.

## Correctness

1. **`File.read!/1` crashes at supervisor start with no surfacing**
   `lib/soot_device/runtime.ex:204, 213` — `read_trust_pems/2` and
   `read_optional_file/1` use `File.read!` against operator-supplied
   paths. A missing `trust_pem_path` or `bootstrap_cert_path` aborts
   `child_specs/2` with a raw `File.Error`. The using module sees a
   crash trace at boot rather than a structured `{:error, reason}`.
   Acceptable for now — operators should fail loudly if trust roots
   are missing — but worth noting in the README.

2. **Telemetry stream with no `sample` block silently configures itself**
   `lib/soot_device/dsl/telemetry.ex` accepts a `stream` with no
   nested `sample`. The runtime then forwards a `nil`-sample stream
   to the Pipeline. Spark doesn't currently treat sample as required,
   and the runtime doesn't validate. Add a `sample` requirement at
   the DSL level OR document the no-sample shape explicitly.

## Test gaps

* `SootDevice.Info.shadow_options/1` — no direct test. Currently
  exercised only as a side-effect of `Runtime.child_specs`.
* `SootDevice.Info.telemetry_options/1` — same.
* `SootDevice.Info.shadow_reports/1`'s `every:` schedule — the
  reports test asserts shape but never exercises a report with a
  schedule.
* `SootDevice.Runtime.start_link/2` — no test boots the supervision
  tree end to end. **Deferred** until soot_device_protocol's quality
  branch lands: that branch promotes
  `SootDeviceProtocol.Test.{FakeHTTP, PKI, Ingest}` from `test/support/`
  to `lib/`, which is what makes them reachable from soot_device's
  test suite via the path dep. Once that merges, add a test that
  wires `Runtime.start_link/2` with FakeHTTP, the in-memory
  transport, and a PKI-built bundle and asserts every child boots.

## Tooling gaps

(Mirror of the protocol findings — same set of files missing.)

* No `.tool-versions`.
* No `LICENSE` file.
* No `CHANGELOG.md`.
* No `.credo.exs`, `.sobelow-conf`, `.dialyzer_ignore.exs`.
* No `.github/workflows/`.
* `:credo` is in deps but unconfigured; no dialyxir, sobelow,
  mix_audit.

## Stylistic

* `Runtime.child_specs/2` uses `append_if(true, fun)` for the always-on
  Contract.Refresh slot (line 98). Cleaner to add it unconditionally.
* `Runtime.to_pascal/1` is a manual map for a 6-key set. Acceptable as
  is; the alternative is `Macro.camelize/1` on the atom name, which
  would handle `:enrollment` → `"Enrollment"` correctly without the
  table.
* `Runtime.append_if/3` exists because the body of `child_specs/2`
  reads as a pipeline. Keep it.

## Commit plan

1. `mix format` (likely a no-op).
2. `LICENSE` + `.tool-versions`.
3. Re-integration follow-on: nothing — soot_device doesn't reference
   the dissolved soot_device_test.
4. Correctness: drop `append_if(true, ...)` for Contract.Refresh.
5. Test infra: `capture_log: true`.
6. New tests: shadow_options, telemetry_options, shadow_reports
   `every:`, end-to-end boot via Runtime.start_link.
7. `CHANGELOG.md`.
8. `.github/workflows/ci.yml`.
9. Lint stack — credo + sobelow + dialyxir + mix_audit + ex_doc + config.
10. Dialyzer.
