defmodule SootDevice.Dsl.Identity do
  @moduledoc false

  @schema [
    bootstrap_cert_path: [
      type: :string,
      doc: "Path to the bootstrap cert PEM read at runtime."
    ],
    bootstrap_key_path: [
      type: :string,
      doc: "Path to the bootstrap private-key PEM read at runtime."
    ],
    operational_storage: [
      type: {:in, [:file_system, :memory]},
      default: :file_system,
      doc:
        "Where the device's operational identity, contract bundle, " <>
          "and shadow state are persisted across reboots."
    ],
    storage_dir: [
      type: :string,
      doc:
        "Filesystem root for persistent storage when operational_storage " <>
          "is :file_system. Default: \"/data/soot\"."
    ],
    enrollment_token_env: [
      type: :string,
      default: "SOOT_ENROLLMENT_TOKEN",
      doc: "Environment variable holding the enrollment token, read on first boot."
    ],
    trust_pem_path: [
      type: :string,
      doc:
        "Path to the firmware-burned trust PEM bundle used to validate " <>
          "the backend's TLS chain *before* the first contract refresh."
    ],
    subject: [
      type: :string,
      doc: "X.509 subject DN used in the CSR submitted to /enroll."
    ]
  ]

  def schema, do: @schema
end
