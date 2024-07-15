// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

import { IOtcMarketCore } from "./IOtcMarketCore.sol";

interface IOtcMarketAcceptOffer is IOtcMarketCore {
    /**
     * @dev Parameters to accept the offer.
     * - offerId: The offer ID.
     * - srcAmountSD: The amount to buy in shared decimals.
     * - srcBuyerAddress: The address of the buyer on offer source chain.
     */
    struct AcceptOfferParams {
        bytes32 offerId;
        uint64 srcAmountSD;
        bytes32 srcBuyerAddress;
    }

    /**
     * @dev BF OtcMarket accept offer receipt.
     * - dstAmountLD: The amount actually taken from the buyer in local decimals.
     * - feeLD: The BF OtcMarket fee in local decimals.
     */
    struct AcceptOfferReceipt {
        uint256 dstAmountLD;
        uint256 feeLD;
    }

    /**
     * @dev Offer with the provided ID does not exist.
     */
    error NonexistentOffer(bytes32 offerId);

    /**
     * @dev Tried to accept an offer for an amount exceeding the available offer amount.
     */
    error ExcessiveAmount(uint64 available, uint64 desired);

    /**
     * @dev Provided Endpoint ID does not match the required one.
     */
    error InvalidEid(uint32 required, uint32 provided);

    /**
     * @dev Emmited when
     * - offer is accepted on offer destination chain
     * - offer accepted message came to offer source chain.
     */
    event OfferAccepted(bytes32 offerId, uint64 srcAmountSD, bytes32 srcBuyerAddress, bytes32 dstBuyerAddress);

    /**
     * @notice Provides a quote for the acceptOffer() operation.
     * @param _dstBuyerAddress The address of the buyer on offer destination chain.
     * @param _params The parameters for the acceptOffer() operation.
     * @param _payInLzToken Flag indicating whether the caller is paying in the LZ token.
     * @return fee The calculated LayerZero messaging fee from the send() operation.
     *
     * @dev MessagingReceipt: LayerZero msg receipt
     *  - guid: The unique identifier for the sent message.
     *  - nonce: The nonce of the sent message.
     *  - fee: The LayerZero fee incurred for the message.
     *
     * @dev AcceptOfferReceipt: BF OtcMarket accept offer receipt
     * - dstAmountLD: The amount actually taken from the buyer in local decimals.
     * - feeLD: The BF OtcMarket fee in local decimals.
     */
    function quoteAcceptOffer(
        bytes32 _dstBuyerAddress,
        AcceptOfferParams calldata _params,
        bool _payInLzToken
    ) external returns (MessagingFee memory fee, AcceptOfferReceipt memory acceptOfferReceipt);

    /**
     * @notice Accepts the offer.
     * @param _params The parameters for the acceptOffer() operation.
     * @param _fee The fee information supplied by the caller.
     *      - nativeFee: The native fee.
     *      - lzTokenFee: The lzToken fee.
     * @return msgReceipt The LayerZero messaging receipt from the send() operation.
     * @return acceptOfferReceipt The AcceptOffer receipt information.
     *
     * @dev MessagingReceipt: LayerZero msg receipt
     *  - guid: The unique identifier for the sent message.
     *  - nonce: The nonce of the sent message.
     *  - fee: The LayerZero fee incurred for the message.
     *
     * @dev AcceptOfferReceipt: BF OtcMarket accept offer receipt
     * - dstAmountLD: The amount actually taken from the buyer in local decimals.
     * - feeLD: The BF OtcMarket fee in local decimals.
     */
    function acceptOffer(
        AcceptOfferParams calldata _params,
        MessagingFee calldata _fee
    ) external payable returns (MessagingReceipt memory msgReceipt, AcceptOfferReceipt memory acceptOfferReceipt);
}
