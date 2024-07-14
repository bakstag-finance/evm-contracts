// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

import { IOtcMarketCore } from "./IOtcMarketCore.sol";

interface IOtcMarketAcceptOffer is IOtcMarketCore {
    struct AcceptOfferParams {
        bytes32 offerId;
        uint64 srcAmountSD;
        bytes32 srcBuyerAddress;
    }

    /**
     * @dev Struct representing AcceptOffer receipt information.
     */
    struct AcceptOfferReceipt {
        uint256 dstAmountLD;
        uint256 feeLD;
    }

    /**
     * @dev Offer with provided id does not exist.
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
     * - offer is accepted on destination chain
     * - offer accepted message came to source chain.
     */
    event OfferAccepted(bytes32 offerId, uint64 srcAmountSD, bytes32 srcBuyerAddress, bytes32 dstBuyerAddress);

    function quoteAcceptOffer(
        AcceptOfferParams calldata _params,
        bool _payInLzToken
    ) external returns (MessagingFee memory fee, AcceptOfferReceipt memory acceptOfferReceipt);

    function acceptOffer(
        AcceptOfferParams calldata _params,
        MessagingFee calldata _fee
    ) external payable returns (MessagingReceipt memory msgReceipt, AcceptOfferReceipt memory acceptOfferReceipt);
}
