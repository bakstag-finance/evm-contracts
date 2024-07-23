// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

import { IOtcMarketCore } from "./IOtcMarketCore.sol";

interface IOtcMarketCreateOffer is IOtcMarketCore {
    /**
     * @dev Parameters to create an offer.
     * - dstSellerAddress: The address of the seller on destination chain.
     * - dstEid: The destination Endpoint ID.
     * - srcTokenAddress: The source token address.
     * - dstTokenAddress: The destination token address.
     * - srcAmountLD: The source token amount for sale (in LD).
     * - exchangeRateSD: The price per source token in destination token units (in SD).
     */
    struct CreateOfferParams {
        bytes32 dstSellerAddress;
        uint32 dstEid;
        bytes32 srcTokenAddress;
        bytes32 dstTokenAddress;
        uint256 srcAmountLD;
        uint64 exchangeRateSD;
    }

    /**
     * @dev BF OtcMarket create offer receipt.
     * - offerId: The ID of the offer.
     * - srcAmountLD: The amount actually taken from the seller (in LD).
     */
    struct CreateOfferReceipt {
        bytes32 offerId;
        uint256 srcAmountLD;
    }

    /**
     * @dev Cannot recreate the same offer. Top up or cancel the existing offer.
     */
    error OfferAlreadyExists(bytes32 offerId);

    /**
     * @dev Emmited when
     * - offer is created on the offer source chain
     * - offer created message came to the offer destination chain.
     */
    event OfferCreated(bytes32 indexed offerId, Offer offer);

    /**
     * @notice Provides a quote for the createOffer() operation.
     * @param _srcSellerAddress The address of the seller on offer source chain.
     * @param _params The parameters for the createOffer() operation.
     * @param _payInLzToken Flag indicating whether the caller is paying in the LZ token.
     * @return fee The calculated LayerZero messaging fee from the send() operation.
     *
     * @dev MessagingReceipt: LayerZero msg receipt
     *  - guid: The unique identifier for the sent message.
     *  - nonce: The nonce of the sent message.
     *  - fee: The LayerZero fee incurred for the message.
     *
     * @dev CreateOfferReceipt: BF OtcMarket create offer receipt
     *  - offerId: The unique global identifier of the created offer.
     *  - amountLD: The amount actually taken from the seller (in LD).
     */
    function quoteCreateOffer(
        bytes32 _srcSellerAddress,
        CreateOfferParams calldata _params,
        bool _payInLzToken
    ) external view returns (MessagingFee memory fee, CreateOfferReceipt memory createOfferReceipt);

    /**
     * @notice Creates a new offer.
     * @param _params The parameters for the createOffer() operation.
     * @param _fee The fee information supplied by the caller.
     *  - nativeFee: The native fee.
     *  - lzTokenFee: The lzToken fee.
     * @return msgReceipt The LayerZero messaging receipt from the send() operation.
     * @return createOfferReceipt The CreateOffer receipt information.
     *
     * @dev MessagingReceipt: LayerZero msg receipt
     *  - guid: The unique identifier for the sent message.
     *  - nonce: The nonce of the sent message.
     *  - fee: The LayerZero fee incurred for the message.
     *
     * @dev CreateOfferReceipt: BF OtcMarket create offer receipt
     *  - offerId: The unique global identifier of the created offer.
     *  - amountLD: The amount actually taken from the seller (in LD).
     */
    function createOffer(
        CreateOfferParams calldata _params,
        MessagingFee calldata _fee
    ) external payable returns (MessagingReceipt memory msgReceipt, CreateOfferReceipt memory createOfferReceipt);
}
