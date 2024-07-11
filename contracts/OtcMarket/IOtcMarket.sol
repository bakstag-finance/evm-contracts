// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

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

    struct CreateOfferParams {
        bytes32 beneficiary;
        uint32 dstEid;
        bytes32 srcTokenAddress;
        bytes32 dstTokenAddress;
        uint256 srcAmountLD;
        uint64 exchangeRateSD;
    }

    struct Offer {
        bytes32 advertiser;
        bytes32 beneficiary;
        uint32 srcEid;
        uint32 dstEid;
        bytes32 srcTokenAddress;
        bytes32 dstTokenAddress;
        uint64 srcAmountSD;
        uint64 exchangeRateSD; // price per source token in destination token units
    }

    /**
     * @dev Invalid message order. 
     */
    error InvalidNonce();

    error InvalidLocalDecimals();


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
        uint64 srcAmount,
        uint64 exchangeRate
    );

    /**
     * @notice Hashing function used to (re)build the offer id from its params.
     */
    function hashOffer(
        bytes32 _advertiser,
        uint32 _srcEid,
        uint32 _dstEid,
        bytes32 _srcTokenAddress,
        bytes32 _dstTokenAddress,
        uint64 _exchangeRate
    ) external pure returns (bytes32 offerId);

    /**
     * @notice Function to create a new offer.
     */
    function createOffer(
        CreateOfferParams calldata _params,
        MessagingFee calldata _fee    
    ) external payable returns (MessagingReceipt memory msgReceipt, bytes32 newOfferId);
}
