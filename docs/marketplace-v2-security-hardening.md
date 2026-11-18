# Marketplace V2 security hardening

**Status:** Proposed source implementation and adversarial tests only. Not deployed, not audited, and not approved for production use.

## Why V2 is separate

The current Base mainnet marketplace is a non-proxy deployment. Its runtime bytecode cannot be changed in place. The existing V1 contract remains the deployed contract and its recorded runtime must continue to match the deployment manifest. This V2 implementation is a separate successor proposal; adding it to source does not deploy it, migrate listings, change frontend configuration, or authorize spending gas.

## V1 findings addressed

The internal pre-audit review identified the following issues in `VectolithMarketplace`:

1. A 100% EIP-2981 royalty can make a sale revert when the protocol fee is non-zero, because V1 subtracts the fee after the full royalty.
2. Malformed or reverting EIP-2981 responses can block purchases without a bounded, explicit response contract.
3. `transferFrom` can deliver an NFT to a contract that does not implement `IERC721Receiver`.
4. Owner setters accept zero registry and treasury addresses even though the constructor rejects them.

## V2 behavior

- Calculate the protocol fee first, then cap the royalty to the remaining sale proceeds. The total credited amount cannot exceed the sale price.
- Treat a failed or malformed ERC-165 royalty capability response as an error. If the collection advertises EIP-2981, a failed or malformed `royaltyInfo` response reverts the sale. This is an explicit fail-closed availability trade-off rather than silently dropping an artist royalty.
- Treat a zero royalty receiver as no payable royalty.
- Use `safeTransferFrom`; a contract buyer must implement `IERC721Receiver` or the purchase reverts atomically.
- Reject zero registry and treasury addresses in both the constructor and owner setters.
- Keep pull-payment withdrawals and `nonReentrant` guards.
- Use full-precision `Math.mulDiv` for the protocol fee calculation.

## Regression coverage

`contracts/test/VectolithMarketplaceV2.t.sol` covers:

- 100% and above-sale-price royalties without fee underflow;
- zero royalty receiver;
- malformed ERC-165 boolean responses;
- malformed and reverting EIP-2981 responses;
- zero-address registry and treasury setters;
- non-receiver contract buyers;
- normal settlement conservation.

Run from `contracts/`:

```bash
forge test --match-contract VectolithMarketplaceV2Test -vvv
forge test
```

## Deployment and migration gates

Do not deploy V2 until all of the following are completed:

1. Independent specialist review of the exact source revision and compiler configuration.
2. Full Foundry test, fuzz and invariant coverage, including adversarial NFT collections and receiver contracts.
3. A migration design for existing V1 listings, registry state, frontend configuration and indexer continuity.
4. Explicit owner authorization and a documented destination treasury/registry.
5. Independent public-RPC verification of the new deployment and its runtime bytecode.
6. A release decision after the security review; this document itself is not authorization.

No deployment, transaction, private key, wallet, paid service or real ETH was used by this source-only change.
