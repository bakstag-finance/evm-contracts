// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Escrow is Ownable {
    constructor(address _initialOwner) Ownable(_initialOwner) {}

    function transfer(address _token, address _to, uint256 _amount) public onlyOwner {
        IERC20(_token).transfer(_to, _amount);
    }
}
