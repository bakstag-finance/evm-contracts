// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { OApp, MessagingFee, MessagingReceipt, Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { OAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";

import { IOtcMarket } from "../IOtcMarket.sol";

/**
 * @dev See {IOtcMarket}.
 */
abstract contract OtcMarketCore is IOtcMarket, OApp, OAppOptionsType3 {
    uint8 public constant sharedDecimals = 6;
    uint32 public immutable eid;

    constructor(address _endpoint, address _delegate) OApp(_endpoint, _delegate) {
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
        uint64 _exchangeRate
    ) public pure virtual override returns (bytes32 offerId) {
        return (
            keccak256(
                abi.encodePacked(_advertiser, _srcEid, _dstEid, _srcTokenAddress, _dstTokenAddress, _exchangeRate)
            )
        );
    }

    function _decodePayload(bytes calldata _payload) private pure returns (Message msgType, bytes calldata msgPayload) {
        msgType = Message(uint8(bytes1(_payload[:1])));
        msgPayload = bytes(_payload[1:]);
    }

    /**
     * @dev Internal function override to handle incoming messages from another chain.
     * @dev _origin A struct containing information about the message sender.
     * @dev _guid A unique global packet identifier for the message.
     * @param _payload The encoded message payload being received.
     *
     * @dev The following params are unused in the current implementation of the OApp.
     * @dev _executor The address of the Executor responsible for processing the message.
     * @dev _extraData Arbitrary data appended by the Executor to the message.
     *
     * Decodes the received payload and processes it as per the business logic defined in the function.
     */
    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid */,
        bytes calldata _payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal virtual override {
        (Message msgType, bytes calldata msgPayload) = _decodePayload(_payload);

        if (msgType == Message.OfferCreated) {
            (
                bytes32 offerId,
                bytes32 advertiser,
                bytes32 beneficiary,
                uint32 srcEid,
                uint32 dstEid,
                bytes32 srcTokenAddress,
                bytes32 dstTokenAddress,
                uint64 srcAmountSD,
                uint64 exchangeRateSD
            ) = _decodeOfferCreated(msgPayload);

            _receiveCreateOffer(
                offerId,
                Offer(
                    advertiser,
                    beneficiary,
                    srcEid,
                    dstEid,
                    srcTokenAddress,
                    dstTokenAddress,
                    srcAmountSD,
                    exchangeRateSD
                )
            );
        }
    }

    function _receiveCreateOffer(bytes32 offerId, Offer memory offer) internal virtual;
    function _decodeOfferCreated(
        bytes calldata _payload
    )
        internal
        pure
        virtual
        returns (
            bytes32 offerId,
            bytes32 advertiser,
            bytes32 beneficiary,
            uint32 srcEid,
            uint32 dstEid,
            bytes32 srcTokenAddress,
            bytes32 dstTokenAddress,
            uint64 srcAmountSD,
            uint64 exchangeRateSD
        );
}
