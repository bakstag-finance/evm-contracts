// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import { Transfer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Transfer.sol";

contract Escrow is Ownable {
    constructor(address _initialOwner) Ownable(_initialOwner) {}

    function transfer(address _token, address _to, uint256 _value) public onlyOwner {
        Transfer.nativeOrToken(_token, _to, _value);
    }

    receive() external payable {}
}
