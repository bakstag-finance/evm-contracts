// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
  * @dev Converts an address to bytes32.
  * @param _addr The address to convert.
  * @return The bytes32 representation of the address.
  */
function addressToBytes32(address _addr) pure returns (bytes32) {
    return bytes32(uint256(uint160(_addr)));
}

/**
  * @dev Converts bytes32 to an address.
  * @param _b The bytes32 value to convert.
  * @return The address representation of bytes32.
  */
function bytes32ToAddress(bytes32 _b) pure returns (address) {
    return address(uint160(uint256(_b)));
}