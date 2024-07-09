// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev Interface of the {OtcMarket}.
 */
interface IOtcMarket {
    enum Message {
        OfferCreated,
        OfferAccepted,
        OfferCancelAppeal,
        OfferCanceled
    }

    struct Offer {
        bytes32 advertiser;
        bytes32 beneficiary;
        uint32 srcEid;
        uint32 dstEid;
        bytes32 srcTokenAddress;
        bytes32 dstTokenAddress;
        // TODO: restrict
        uint128 srcAmount;
        uint128 exchangeRate; // price per source token in target token units
    }

    /**
     * @dev Invalid message order. 
     */
    error InvalidNonce();

    /**
     * @dev Cannot create the same offer. You can top up the existing offer.
     */
    error OfferAlreadyExists(bytes32 offerId);

    /**
     * @dev Emmited when
     * - offer is created on source chain
     * - offer created message came to destination chain.
     */
    event OfferCreated(
        bytes32 offerId,
        bytes32 indexed advertiser,
        bytes32 beneficiary,
        uint32 indexed srcEid,
        uint32 indexed dstEid,
        bytes32 srcTokenAddress,
        bytes32 dstTokenAddress,
        uint128 srcAmount,
        uint128 exchangeRate
    );

    /**
     * @notice Hashing function used to (re)build the offer id from its params.
     */
    function hashOffer(
        bytes32 advertiser,
        uint32 srcEid,
        uint32 dstEid,
        bytes32 srcTokenAddress,
        bytes32 dstTokenAddress,
        uint128 exchangeRate
    ) external pure returns (bytes32 offerId);

    /**
     * @notice Function to create a new offer.
     */
    function createOffer(
        bytes32 beneficiary,
        uint32 dstEid,
        bytes32 srcTokenAddress,
        bytes32 dstTokenAddress,
        uint128 srcAmount,
        uint128 exchangeRate
    ) external payable returns (bytes32 newOfferId);
}
