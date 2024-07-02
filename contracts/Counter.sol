// Copyright 2024 RISC Zero, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.20;

import {IRiscZeroVerifier} from "risc0/IRiscZeroVerifier.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Steel} from "risc0/steel/Steel.sol";
import {ICounter} from "./ICounter.sol";
import {ImageID} from "./ImageID.sol"; // auto-generated contract after running `cargo build`.

/// @title Counter
/// @notice Implements a counter that increments based on off-chain Steel proofs submitted to this contract.
/// @dev The contract interacts with ERC-20 tokens, using Steel proofs to verify that an account holds at least 1 token
/// before incrementing the counter. This contract leverages RISC0-zkVM for generating and verifying these proofs.
contract Counter is ICounter {
    /// @notice Image ID of the only zkVM binary to accept verification from.
    bytes32 public constant imageId = ImageID.BALANCE_OF_ID;

    /// @notice RISC Zero verifier contract address.
    IRiscZeroVerifier public immutable verifier;

    /// @notice Address of the ERC-20 token contract.
    address public immutable tokenAddress;

    /// @notice Mapping of addresses to their verification status.
    mapping(address => address) public verified;

    /// @notice Mapping of addresses to their token balances.
    mapping(address => uint256) public balances;

    /// @notice Journal that is committed to by the guest.
    struct Journal {
        Steel.Commitment commitment;
        address tokenAddress;
        uint256 tokenAmount;
    }

    /// @notice Initialize the contract, binding it to a specified RISC Zero verifier and ERC-20 token address.
    constructor(IRiscZeroVerifier _verifier, address _tokenAddress) {
        verifier = _verifier;
        tokenAddress = _tokenAddress;
    }

    function withdraw(uint256 amount) public {
        IERC20 token = IERC20(tokenAddress);
        require(
            token.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        balances[msg.sender] += amount;
    }

    /// @inheritdoc ICounter
    function verify(bytes calldata journalData, bytes calldata seal) external {
        Journal memory journal = abi.decode(journalData, (Journal));
        require(
            balances[journal.tokenAddress] == journal.tokenAmount,
            "Insufficient balance"
        );
        require(
            verified[journal.tokenAddress] == address(0),
            "Address already verified"
        );

        require(
            Steel.validateCommitment(journal.commitment),
            "Invalid commitment"
        );

        // Verify the proof
        bytes32 journalHash = sha256(journalData);
        verifier.verify(seal, imageId, journalHash);

        verified[journal.tokenAddress] = msg.sender;
    }

    /// @inheritdoc ICounter
    function checkVerified(address account) external view returns (bool) {
        return verified[account] != address(0);
    }

    function balanceOf(address account) external view returns (uint) {
        return balances[account];
    }
}
