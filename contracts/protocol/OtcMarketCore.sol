// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { OApp, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { OAppOptionsType3 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";

import { IOtcMarket } from "./interfaces/IOtcMarket.sol";
import { Escrow } from "./Escrow.sol";

/**
 * @dev See {IOtcMarket}.
 */
abstract contract OtcMarketCore is IOtcMarket, OApp, OAppOptionsType3 {
    uint8 public constant FEE = 100; // 1/100 = 1%
    uint8 public constant SHARED_DECIMALS = 6;
    uint32 public immutable eid;
    Escrow public immutable escrow;
    address public immutable treasury;

    constructor(address _escrow, address _treasury, address _endpoint, address _delegate) OApp(_endpoint, _delegate) {
        eid = ILayerZeroEndpointV2(endpoint).eid();
        escrow = Escrow(payable(_escrow));
        treasury = _treasury;
    }

    mapping(bytes32 offerId => Offer) public offers;

    mapping(uint32 eid => mapping(bytes32 sender => uint64 nonce)) private receivedNonce;

    function nextNonce(uint32 _srcEid, bytes32 _sender) public view virtual override returns (uint64) {
        return receivedNonce[_srcEid][_sender] + 1;
    }

    function _acceptNonce(uint32 _srcEid, bytes32 _sender, uint64 _nonce) internal virtual {
        // receivedNonce[_srcEid][_sender] += 1;
        // if (_nonce != receivedNonce[_srcEid][_sender]) {
        //     revert InvalidNonce();
        // }

        if (_nonce != ++receivedNonce[_srcEid][_sender]) {
            revert InvalidNonce();
        }
    }

    function _payNative(uint256 _nativeFee) internal virtual override returns (uint256 nativeFee) {
        if (msg.value < _nativeFee) revert NotEnoughNative(msg.value);
        return _nativeFee;
    }

    function hashOffer(
        bytes32 _advertiser,
        uint32 _srcEid,
        uint32 _dstEid,
        bytes32 _srcTokenAddress,
        bytes32 _dstTokenAddress,
        uint64 _exchangeRateSD
    ) public pure virtual override returns (bytes32 offerId) {
        return (
            keccak256(
                abi.encodePacked(_advertiser, _srcEid, _dstEid, _srcTokenAddress, _dstTokenAddress, _exchangeRateSD)
            )
        );
    }

    function _getDecimalConversionRate(
        address _tokenAddress
    ) internal view virtual returns (uint256 decimalConversionRate) {
        // TODO: revert if decimals < SHARED_DECIMALS ?
        decimalConversionRate = _tokenAddress == address(0)
            ? 10 ** 12 // native
            : 10 ** (ERC20(_tokenAddress).decimals() - SHARED_DECIMALS); // token
    }

    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid */,
        bytes calldata _payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal virtual override {
        (Message msgType, bytes calldata msgPayload) = _decodePayload(_payload);

        if (msgType == Message.OfferCreated) {
            _receiveOfferCreated(msgPayload);
        } else if (msgType == Message.OfferAccepted) {}
    }

    function _decodePayload(
        bytes calldata _payload
    ) internal pure virtual returns (Message msgType, bytes calldata msgPayload) {
        msgType = Message(uint8(bytes1(_payload[:1])));
        msgPayload = bytes(_payload[1:]);
    }

    function _receiveOfferCreated(bytes calldata _msgPayload) internal virtual;

    function _receiveOfferAccepted(bytes calldata _msgPayload) internal virtual;
}