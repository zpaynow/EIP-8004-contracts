// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title MinimalUUPS
 * @dev Placeholder implementation the vanity proxies are created with.
 *
 * Why a placeholder at all:
 *   A proxy's CREATE2 address depends on its constructor args, i.e. on the
 *   implementation address and the init calldata. Pinning the proxies to this
 *   tiny, frozen contract means the registry implementations can keep changing
 *   without invalidating the mined vanity salts.
 *
 * Why `owner_` is a parameter and not a hardcoded constant:
 *   The owner ends up inside the proxy's init calldata, so it is still baked
 *   into the proxy address. Anyone re-deploying the same init code on a new
 *   chain therefore reproduces *our* owner, which is what makes the vanity
 *   addresses safe to squat. Deriving the owner from `msg.sender`/`tx.origin`
 *   instead would hand ownership to whoever deploys first on a new chain.
 *
 * Storage: slot 0 is left reserved for `_identityRegistry`, which the real
 * Reputation/Validation implementations declare outside their ERC-7201
 * namespace. The placeholder never writes it; `initialize(identityRegistry_)`
 * on the real implementation sets it during the upgrade.
 */
contract MinimalUUPS is OwnableUpgradeable, UUPSUpgradeable {
    /// @dev Reserved: `_identityRegistry` in the real implementations.
    address private _identityRegistry;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner_) public initializer {
        require(owner_ != address(0), "bad owner");
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getVersion() external pure returns (string memory) {
        return "0.0.1-placeholder";
    }
}
