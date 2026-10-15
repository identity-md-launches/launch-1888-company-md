// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Company.md (COMD)
/// @notice Fixed-supply ERC-20 with 18 decimals and no administrative powers.
contract CompanyToken is ERC20 {
    /// @notice One billion COMD, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the entire supply once to the immediate deployer.
    /// @dev When deployed through a factory, the factory receives the supply.
    constructor() ERC20("Company.md", "COMD") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
