# Contract test automation

The repository's Foundry suite runs in GitHub Actions through
[`.github/workflows/contracts.yml`](../.github/workflows/contracts.yml).

The workflow runs when contract sources, tests, configuration, or the workflow
itself change on a pull request or on `main`. It checks out recursive submodules,
installs the stable Foundry toolchain, and executes:

```bash
cd contracts && forge test --gas-report
```

The recursive checkout is required because `lib/forge-std` and
`lib/openzeppelin-contracts` are Git submodules. The working directory must be
`contracts`, where `foundry.toml` is located.

A successful test run establishes only that the checked-in test suite passed
against that commit. It does not establish deployment, bytecode verification,
security audit completion, or production readiness.
