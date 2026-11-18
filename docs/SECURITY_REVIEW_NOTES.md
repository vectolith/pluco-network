# PLUCO Contract Security Review Notes

**Review type:** Internal source-level pre-audit review  
**Scope:** `VectolithRegistry`, `VectolithOriginals`, and `VectolithMarketplace` at the source revision represented by the Base deployment verifier  
**Status:** Not an independent audit; no production-safety or audit-completion claim is made

## Verified implementation properties

The public-RPC verifier confirms that all eight manifest transactions succeeded, all three deployed executable runtimes match the current Foundry artifacts after compiler metadata and immutable constructor slots are normalized, and the live ownership, treasury, fee, supply, mint-price, max-per-wallet, registry and royalty state matches the manifest.

The marketplace uses a pull-payment model: purchases credit the seller, treasury and royalty receiver, and each account withdraws its own credit. The purchase and withdrawal paths use `nonReentrant`. The contracts are non-proxy deployments; there is no upgrade mechanism.

## Findings requiring remediation or explicit acceptance

### PLUCO-MKT-001 — Royalty can consume the full sale price before protocol fee subtraction

**Severity:** Medium — sale availability / denial of service  
**Location:** `VectolithMarketplace.buy`

The marketplace clamps an EIP-2981 royalty to `price`, calculates the protocol fee afterwards, then computes `price - royalty - fee`. If a collection reports a royalty equal to the full price while the protocol fee is non-zero, the subtraction underflows and the purchase reverts. A collection can therefore make its own listed items unsellable at the configured fee.

**Future-release correction:** Calculate the protocol fee first and cap the payable royalty at `price - fee`. Add tests for 100% royalty, royalty above price, zero royalty receiver and malformed/reverting EIP-2981 responses. Do not patch the deployed contract in place; it is not upgradeable.

### PLUCO-MKT-002 — Untrusted EIP-2981 responses can block purchases

**Severity:** Low to Medium — sale availability  
**Location:** `VectolithMarketplace.buy`, `IERC165Check.supportsRoyalty`

A collection that advertises EIP-2981 but reverts or returns malformed data from `royaltyInfo` can make its own purchase revert. The ERC-165 helper also ABI-decodes the returned boolean directly after checking only the response length.

**Future-release correction:** Treat royalty discovery as a bounded optional capability. Validate the ERC-165 return word without an unsafe ABI decode, and decide/document whether a failed royalty query should revert or fall back to zero royalty. Add adversarial collection tests.

### PLUCO-MKT-003 — NFT delivery uses `transferFrom`, not `safeTransferFrom`

**Severity:** Medium — buyer asset-recovery risk  
**Location:** `VectolithMarketplace.buy`

The marketplace transfers the NFT directly to `msg.sender` without checking whether a contract buyer implements `IERC721Receiver`. A contract wallet that cannot receive or later transfer the NFT can strand the purchased token.

**Future-release correction:** Prefer `safeTransferFrom` and test both compliant and non-compliant contract buyers. Document the contract-wallet requirement.

### PLUCO-ADMIN-001 — Owner setters accept zero addresses

**Severity:** Medium — privileged misconfiguration / availability  
**Location:** `VectolithMarketplace.setRegistry`, `VectolithMarketplace.setTreasury`

The constructor rejects zero registry and treasury addresses, but the owner setters do not. Setting the registry to zero disables new listings; setting the treasury to zero can direct protocol-fee credits to an unusable address.

**Future-release correction:** Apply the constructor's non-zero checks to setters and add regression tests. Consider a multisig and timelock for owner-controlled configuration changes.

### PLUCO-REG-001 — Non-ownable collection registration does not authenticate the creator

**Severity:** Informational — attribution integrity  
**Location:** `VectolithRegistry.register`

When a collection does not expose `owner()`, any caller may register it and becomes the registry's `artist` attribution. This is explicitly allowed by the current implementation, but consumers must treat `artist` as the registrant, not proof of collection authorship.

**Future-release correction:** Keep the current behavior only if the UI and indexer label it as registrant attribution. If verified authorship is required, introduce a signed registration/ownership proof in a future version.

## Administrative and operational risks

- The three contracts are controlled by an owner address. The owner can change registry/treasury/fee settings and collection status; there is no on-chain timelock or multisig requirement in these contracts.
- The current deployment is not upgradeable. Any code correction requires a separately reviewed deployment and a deliberate migration/registry plan.
- The runtime-bytecode match is not a security audit. Explorer verified-source status and an independent specialist review remain required.
- The verifier confirms current state at the CI run; it is not a continuous monitor and does not guarantee future state.

## Review evidence

- Foundry tests and Base public-RPC verification: [run 44363495200](https://github.com/vectolith/pluco-network/actions/runs/44363495200)
- Build check: [run 44363495170](https://github.com/vectolith/pluco-network/actions/runs/44363495170)
- Deployment verifier: `contracts/scripts/verify-base-deployment.sh`
- Runtime comparison: `contracts/scripts/verify-runtime-bytecode.py`

This document is an internal pre-audit review prepared from the repository source. It must not be presented as an independent audit, formal verification, or approval for production use.
