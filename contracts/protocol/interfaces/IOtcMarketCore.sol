// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOtcMarketCore {
    /**
     * @dev Omnichain message types.
     * - OfferCreated: The offer is created.
     * - OfferAccepted: The offer is accepted.
     * - OfferCancelAppeal: The offer is appealed to be canceled.
     * - OfferCanceled: The offer is canceled.
     */
    enum Message {
        OfferCreated,
        OfferAccepted,
        OfferCancelAppeal,
        OfferCanceled
    }

    /**
     * @dev Invalid message order.
     */
    error InvalidNonce();

    /**
     * @dev The srcAmountSD and exchangeRateSD are too small to fulfill the offer.
     */
    error InvalidPricing(uint64 srcAmountSD, uint64 exchangeRateSD, uint256 dstDecimalConversionRate);

    /**
     * @dev Supplied value (in LD) is smaller than required.
     */
    error InsufficientValue(uint256 required, uint256 supplied);

    /**
     * @dev Offer parameters.
     * - srcSellerAddress: The address of the seller on source chain.
     * - dstSellerAddress: The address of the seller on destination chain.
     * - srcEid: The source Endoint ID.
     * - dstEid: The destination Endoint ID.
     * - srcTokenAddress: The source token address.
     * - dstTokenAddress: The destination token address.
     * - srcAmountSD: The source amount in shared decimals.
     * - exchangeRateSD: The price per source token in destination token units in shared decimals.
     */
    struct Offer {
        bytes32 srcSellerAddress;
        bytes32 dstSellerAddress;
        uint32 srcEid;
        uint32 dstEid;
        bytes32 srcTokenAddress;
        bytes32 dstTokenAddress;
        uint64 srcAmountSD;
        uint64 exchangeRateSD;
    }

    /**
     * @notice Hashing function used to (re)build the offer ID from its params.
     * @param _srcSellerAddress The advertiser.
     * @param _srcEid The source Endoint ID.
     * @param _dstEid The destination Endoint ID.
     * @param _srcTokenAddress The source token address.
     * @param _dstTokenAddress The destination token address.
     * @param _exchangeRateSD The exchange rate
     * @return offerId The unique global identifier of the created offer.
     */
    function hashOffer(
        bytes32 _srcSellerAddress,
        uint32 _srcEid,
        uint32 _dstEid,
        bytes32 _srcTokenAddress,
        bytes32 _dstTokenAddress,
        uint64 _exchangeRateSD
    ) external pure returns (bytes32 offerId);
}
