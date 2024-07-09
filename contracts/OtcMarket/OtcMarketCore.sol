// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { OApp, MessagingFee, MessagingReceipt } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import { IOtcMarket } from "./IOtcMarket.sol";
import "./Utils.sol";

/**
 * @dev See {IOtcMarket}.
 */
abstract contract OtcMarketCore is IOtcMarket, OApp {
    uint32 public immutable eid;

    constructor(address _endpoint, address _delegate) OApp(_endpoint, _delegate) Ownable(_delegate) {
        eid = ILayerZeroEndpointV2(endpoint).eid();
    }

    mapping(bytes32 offerId => Offer) public offers;

    // Mapping to track the maximum received nonce for each source endpoint and sender
    mapping(uint32 eid => mapping(bytes32 sender => uint64 nonce)) private receivedNonce;

    /**
     * @dev Public function to get the next expected nonce for a given source endpoint and sender.
     * @param _srcEid Source endpoint ID.
     * @param _sender Sender's address in bytes32 format.
     * @return uint64 Next expected nonce.
     */
    function nextNonce(uint32 _srcEid, bytes32 _sender) public view virtual override returns (uint64) {
        return receivedNonce[_srcEid][_sender] + 1;
    }

    /**
     * @dev Internal function to accept nonce from the specified source endpoint and sender.
     * @param _srcEid Source endpoint ID.
     * @param _sender Sender's address in bytes32 format.
     * @param _nonce The nonce to be accepted.
     */
    function _acceptNonce(uint32 _srcEid, bytes32 _sender, uint64 _nonce) internal virtual {
        // receivedNonce[_srcEid][_sender] += 1;
        // if (_nonce != receivedNonce[_srcEid][_sender]) {
        //     revert InvalidNonce();
        // }

        if (_nonce != ++receivedNonce[_srcEid][_sender]) {
            revert InvalidNonce();
        }
    }

    /**
     * @dev Quotes the gas needed to pay for the full omnichain transaction in native gas or ZRO token.
     * @param _dstEid The destination endpoint ID.
     * @param _message The message payload.
     * @param _options Additional options for the message.
     * @param _payInLzToken Flag indicating whether to pay the fee in LZ tokens.
     * @return fee The calculated MessagingFee for the message.
     *      - nativeFee: The native fee for the message.
     *      - lzTokenFee: The LZ token fee for the message.
     */
    function quote(
        uint32 _dstEid,
        bytes memory _message,
        bytes memory _options,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {
        fee = _quote(_dstEid, _message, _options, _payInLzToken);
    }

    function hashOffer(
        bytes32 _advertiser,
        uint32 _srcEid,
        uint32 _dstEid,
        bytes32 _srcTokenAddress,
        bytes32 _dstTokenAddress,
        uint128 _exchangeRate
    ) public pure virtual override returns (bytes32 offerId) {
        return (
            keccak256(
                abi.encodePacked(_advertiser, _srcEid, _dstEid, _srcTokenAddress, _dstTokenAddress, _exchangeRate)
            )
        );
    }

    function createOffer(
        bytes32 _beneficiary,
        uint32 _dstEid,
        bytes32 _srcTokenAddress,
        bytes32 _dstTokenAddress,
        uint128 _srcAmount,
        uint128 _exchangeRate
    ) public payable virtual override returns (bytes32 newOfferId) {
        address _advertiser = msg.sender;
        bytes32 advertiser = addressToBytes32(_advertiser);

        // TODO: remove dust

        newOfferId = hashOffer(advertiser, eid, _dstEid, _srcTokenAddress, _dstTokenAddress, _exchangeRate);
        if (offers[newOfferId].advertiser != bytes32("")) {
            revert OfferAlreadyExists(newOfferId);
        }

        offers[newOfferId] = Offer(
            advertiser,
            _beneficiary,
            eid,
            _dstEid,
            _srcTokenAddress,
            _dstTokenAddress,
            _srcAmount,
            _exchangeRate
        );
        emit OfferCreated(
            newOfferId,
            advertiser,
            _beneficiary,
            eid,
            _dstEid,
            _srcTokenAddress,
            _dstTokenAddress,
            _srcAmount,
            _exchangeRate
        );

        IERC20(bytes32ToAddress(_srcTokenAddress)).transferFrom(_advertiser, address(this), _srcAmount);

        bytes memory messagePayload = abi.encodePacked(
            newOfferId,
            advertiser,
            _beneficiary,
            eid,
            _dstEid,
            _srcTokenAddress,
            _dstTokenAddress,
            _srcAmount,
            _exchangeRate
        );
        bytes memory payload = abi.encodePacked(Message.OfferCreated, messagePayload);

        // TODO: deal with options
        // MessagingReceipt memory receipt = _lzSend(_dstEid, payload, _options, MessagingFee(msg.value, 0), payable(_advertiser));
    }
}
