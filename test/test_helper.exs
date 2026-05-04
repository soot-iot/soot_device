ExUnit.start(
  capture_log: true,
  exclude: [
    # QEMU integration tests for the soot_device library itself;
    # require `qemu-system-aarch64` + a built firmware image.
    :qemu,
    # Generates a fresh project via `mix new`, runs `mix
    # soot_device.install`, and runs `mix test` inside the generated
    # project. Slow (~30s); opt in with `--include install_e2e`.
    :install_e2e
  ]
)
