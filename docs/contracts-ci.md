# Contract and deployment verification

The repository's Foundry suite and Base deployment verifier run in GitHub Actions
through [`.github/workflows/contracts-ci.yml`](../.github/workflows/contracts-ci.yml).

The workflow runs for contract, test, configuration, deployment-manifest,
verifier-script, and workflow changes on pull requests and on `main`. It checks
out recursive submodules, installs Foundry, and runs:

```bash
cd contracts && forge test --gas-report
bash scripts/verify-base-deployment.sh
python3 -m unittest discover -s scripts -p 'test_*.py'
```

The recursive checkout is required because `lib/forge-std` and
`lib/openzeppelin-contracts` are Git submodules. Commands run from
`contracts/`, where `foundry.toml` is located.

The deployment verifier uses the public Base RPC at
`https://mainnet.base.org` and requires no API key. It validates chain ID 8453,
all eight manifest transaction receipts and their expected destinations/created
addresses, deployed executable runtime logic against current Foundry artifacts
(after normalizing compiler metadata and constructor immutables), current owner
and treasury roles, marketplace registry, configured fee rates, max supply,
mint price, active collection registration, mint/list state, and EIP-2981
royalty receiver/rate.

A successful run establishes that these checks matched the manifest and
deployed contracts at the checked block state. It does not establish explorer
verified-source status, prove the contracts secure, or replace an independent
contract security review.

The verifier is scoped to the immutable deployed V1 contract addresses and
artifacts. V2 successor contracts are source-only, are not deployed, and are
not included in the V1 manifest. Do not modify V1 source without a separately
reviewed successor/versioning and migration decision.

The Foundry suite currently contains 91 tests: 65 V1 regression tests and 26
adversarial V2 successor tests. The latest recorded successful Base RPC
verification is
[run 44363495200](https://github.com/vectolith/pluco-network/actions/runs/44363495200).


The Foundry test command includes both the 65 V1 regression tests and the 26 V2 successor tests. The Base RPC verifier remains scoped to the immutable V1 addresses and artifacts; it does not claim that V2 is deployed. The workflow must continue to fail if a V1 source change makes its normalized runtime diverge from Base.
