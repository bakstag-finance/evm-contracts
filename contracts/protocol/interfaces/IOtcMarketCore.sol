// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOtcMarketCore {
    /**
     * @dev Omnichain message types.
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
     * @dev Too small amount to create or accept offer. Amount can be expressed either in LD or SD.
     */
    error InsufficientAmount(uint256 minumum, uint256 provided);

    /**
     * @dev Supplied value is smaller than required. Value can be expressed either in LD or SD.
     */
    error InsufficientValue(uint256 required, uint256 supplied);

    /**
     * @dev Offer parameters.
     */
    struct Offer {
        bytes32 srcSellerAddress;
        bytes32 dstSellerAddress;
        uint32 srcEid;
        uint32 dstEid;
        bytes32 srcTokenAddress;
        bytes32 dstTokenAddress;
        uint64 srcAmountSD;
        uint64 exchangeRateSD; // price per source token in destination token units
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
