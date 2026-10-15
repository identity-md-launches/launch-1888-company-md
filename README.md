# Company.md (COMD)

CompanyToken is a fixed-supply ERC-20. Its constructor mints all **1,000,000,000 COMD** to its immediate deployer, once. Transfers and approvals use the unmodified OpenZeppelin Contracts v5.4.0 ERC-20 implementation.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract | `CompanyToken` |
| Source | `src/CompanyToken.sol` |
| Token name | `Company.md` |
| Symbol | `COMD` |
| Decimals | `18` |
| Total supply in whole tokens | `1,000,000,000` |
| Total supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Constructor arguments | None; empty ABI argument list `[]` |
| Constructor native value | `0` |
| Initial recipient | Constructor `msg.sender` |
| Target launch chain | Ethereum, chain ID `1` |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun |
| Optimizer | Enabled, `200` runs |
| Metadata bytecode hash | `none` |

The deployable artifact is `out/CompanyToken.sol/CompanyToken.json`. Deployment requires no external contract, address parameter, initialization call, library linking, or configuration. The constructor makes no external calls. Both CREATE and CREATE2 work. The contract identifier is 12 characters, within the launch's 32-character limit.

When the launch factory deploys this token, the factory receives the entire supply. Neither the transaction origin nor any requester wallet receives tokens directly from the constructor. The factory is then responsible for distribution. There are no application contracts, reserved allocations, or token-side distribution logic in this project. The separate launch process supplies its manifest and performs deployment; this repository does not broadcast transactions or supply a `launch.json`.

## Behavior and assumptions

- Supply is fixed for the lifetime of this deployed contract. There is no public mint or burn function, owner, role administrator, pause, blocklist, seizure, upgrade, proxy, or privileged transfer path.
- Transfers deliver the full amount. There are no transfer fees, taxes, rebases, limits, or special exemptions. The deploying factory has the same transfer rights as every other holder after construction.
- `transfer`, `approve`, and `transferFrom` return `true` on success and revert on failure with OpenZeppelin's ERC-6093 errors. Zero-value transfers between valid addresses are supported and emit `Transfer`; transfers to the zero address and approvals for a zero spender revert.
- Approvals replace the previous allowance, including revocation with `approve(spender, 0)`. Finite allowances decrease on `transferFrom`. An allowance of `type(uint256).max` is treated as unlimited and is not decreased. `transferFrom` requires allowance even when the caller is the source account.
- Construction emits one `Transfer` from the zero address for the full supply. Transfers emit `Transfer`, and explicit approvals emit `Approval`. As in OpenZeppelin v5, spending an allowance does not emit another `Approval`; integrations should query `allowance` for its current value.
- There are no recipient callbacks or other external calls during token operations. Ordinary native-currency transfers are rejected. There is no asset-recovery method: COMD or other assets sent to this token contract cannot be withdrawn through it.

## After launch

No token settings need to be configured and there is no admin wallet to operate. The launch operator is responsible for verifying the artifact and deployed address, recording the constructor mint, executing the factory's distribution, and verifying the source on the chain explorer.

The launch's stated split is 10% to its distributor, 80% to its pool, and the remaining 10% to the requester recipient supplied by the launch. These allocations and pool economics are factory/manifest responsibilities, not constructor parameters or token behavior. No pool or distributor is deployed by this project.

Holders control transfers and spender approvals. Integrations must use 18-decimal base units and check transaction success. Use the smallest practical allowance; confirm revocation before replacing a nonzero allowance to reduce the standard ERC-20 allowance-change race. Nobody can reverse a mistaken transfer, recover lost holder keys, or freeze an approved spender through an administrative token function.

## Build and check

Run from the repository root with Foundry and Solidity 0.8.26 available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x6911479fa6b2e500be4f6633311411633cadc783dcf42f8724bd0d8fd2223f63 forge test
forge fmt --check
```

The compiler version and build settings are pinned in `foundry.toml`. OpenZeppelin's five required Solidity files and the Forge standard library are vendored as ordinary files under `lib/`, with upstream licenses, version notes, and SHA-256 checksums. No dependency download, submodule initialization, RPC, wallet, environment file, FFI, or filesystem permission is needed by the build or tests. Foundry can use its preinstalled compiler offline. The seed above selects reproducible fuzz inputs; tests do not read or modify environment variables.

`test/CompanyToken.t.sol` covers metadata, supply, constructor events, direct and CREATE2 factory deployment, exact distribution/claim/return transfers, zero and self transfers, approvals, revocation, finite/infinite allowances, unauthorized spending, atomic failures, absent administrative functions, native-value rejection, and deployment bytecode restrictions. Four fuzz tests each run 1,000 inputs for conservation and balance/allowance boundaries.

`test/CompanyToken.invariant.t.sol` exercises 256 sequences of up to 64 randomized transfers, approvals, and delegated transfers among four holders. Each operation checks exact balance and allowance effects; the invariant checks that aggregate balances and total supply remain `10^27`.

The local distribution fixture checks token movement only. It does not simulate Uniswap pricing, liquidity, or swaps. The supplied protected launch checks require the separate launch harness, manifest inputs, and Uniswap dependencies; they are not represented as having been executed by these local tests.

## Security review scope

The supplied security reference was reviewed for relevant failure modes. Production behavior consists of the constructor mint and the standard ERC-20 implementation: holder/allowance authorization, zero-address rejection, atomic balance changes, and supply conservation are tested. There are no oracles, signatures, random selection, external token custody operations, callbacks, or upgrade permissions to configure.

Local validation uses Foundry unit tests, fuzzing, and a stateful invariant. Slither and Mythril were not run. This validation is not an independent security audit; the launch's independent review and on-chain deployment checks remain the operator's responsibility.
