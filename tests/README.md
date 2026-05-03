# Tests

Two layers of verification for ghostinthewires:

## Static tests (`tests/static/`)

Run on a developer machine. Cheap and fast. Catch syntax errors, contract violations, and regressions in shared library functions.

```bash
bash tests/static/run-all.sh
```

This runs:

- `bash -n` on every shell script (syntax check)
- `shellcheck` on every shell script (if installed; produces actionable warnings)
- `tests/static/test-gitw-log.sh` (exercises every verifier in the logging library)

To install shellcheck:

```bash
sudo pacman -S shellcheck     # Arch
sudo emerge dev-util/shellcheck  # Gentoo
```

## Runtime validation (built into install/harden/software)

The "real" test for this project. Each phase script verifies its actions as it runs and writes the results to `/var/log/gitw-install.log`. See [`docs/dev/logging.md`](../docs/dev/logging.md).

A clean run produces all `ok` entries. Any `warn` or `fail` is a bug worth investigating — typically because:

- A command targeted a config file pattern that doesn't match the current system
- A `sed` regex didn't match anything (silent no-op)
- A package name has changed in the upstream repo
- A systemd unit name has been renamed
- A behavior we expected didn't happen

The static tests don't catch these. The validation logging does.

## Adding a test

For static tests, add a new file under `tests/static/` and have `run-all.sh` invoke it. Keep tests fast and self-contained — no network, no destructive operations, no expectations about installed packages on the developer machine.

For runtime validation, add a `gitw_verify_*` call in the appropriate phase script after the action you want to verify. Use existing verifiers where possible; add new verifier types to `shared/lib/gitw-log.sh` if needed (and update `tests/static/test-gitw-log.sh` to exercise them).

## VM and bare-metal tests

These don't live here yet. They will live in `docs/dev/testing.md` once the VM-test recipe is documented (next task).

The intent is to have:

- A QEMU + OVMF + swtpm recipe that produces a known-clean test environment
- An expected-log baseline that future runs are diffed against
- Clear separation between what VM testing covers and what requires bare-metal validation (NVIDIA proprietary driver, FIDO2 USB, real Secure Boot firmware, suspend/resume, Wi-Fi/Bluetooth)
