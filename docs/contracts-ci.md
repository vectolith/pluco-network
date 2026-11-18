# Contract and deployment verification

The repository's Foundry suite and Base deployment verifier run in GitHub Actions
through [`.github/workflows/contracts.yml`](../.github/workflows/contracts.yml).

The workflow runs when contract sources, tests, configuration, deployment
manifest, verifier script, or the workflow itself change on a pull request or on
`main`. It checks out recursive submodules, installs the stable Foundry
toolchain, and executes:

```bash
cd contracts && forge test --gas-report
bash scripts/verify-base-deployment.sh
```

The recursive checkout is required because `lib/forge-std` and
`lib/openzeppelin-contracts` are Git submodules. The working directory must
be `contracts`, where `foundry.toml` is located.

The deployment verifier uses the public Base RPC at `https://mainnet.base.org`
and requires no API key. It validates chain ID 8453, all eight manifest
transaction receipts and their expected destinations/created addresses,
executable runtime-bytecode matching against the current Foundry artifacts (compiler metadata and immutable constructor slots normalized), current owner and treasury roles, marketplace
registry, configured fee rates, max supply, mint price, active collection
registration, mint/list state, and EIP-2981 royalty receiver/rate.

A successful run establishes that those on-chain checks matched the manifest
at the checked block state. It does not establish that deployed bytecode matches
the exact repository source/compiler output, that explorer source verification
is complete, that the contracts are secure, or that the product is production
ready. An independent contract security review remains required.
