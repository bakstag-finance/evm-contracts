// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

import { IOtcMarketCore } from "./IOtcMarketCore.sol";

interface IOtcMarketCancelOffer is IOtcMarketCore {
    /**
     * @dev Parameters to create an offer.
     * - offerId: The ID of the offer to be cancelled.
     */
    struct CancelOfferParams {
        bytes32 offerId;
    }

    /**
     * @notice Provides a quote for the cancelOffer() operation.
     * @param _srcSellerAddress The address of the seller on offer source chain.
     * @param _params The parameters for the cancelOffer() operation.
     * @param _payInLzToken Flag indicating whether the caller is paying in the LZ token.
     * @return fee The calculated LayerZero messaging fee from the send() operation.
     *
     * @dev MessagingReceipt: LayerZero msg receipt
     *  - guid: The unique identifier for the sent message.
     *  - nonce: The nonce of the sent message.
     *  - fee: The LayerZero fee incurred for the message.
     *
     */
    function quoteCancelOffer(
        bytes32 _srcSellerAddress,
        CancelOfferParams calldata _params,
        bool _payInLzToken
    ) external view returns (MessagingFee memory fee);

    /**
     * @notice Creates a new offer.
     * @param _params The parameters for the createOffer() operation.
     * @param _fee The fee information supplied by the caller.
     *      - nativeFee: The native fee.
     *      - lzTokenFee: The lzToken fee.
     * @return msgReceipt The LayerZero messaging receipt from the send() operation.
     * @return createOfferReceipt The CreateOffer receipt information.
     *
     * @dev MessagingReceipt: LayerZero msg receipt
     *  - guid: The unique identifier for the sent message.
     *  - nonce: The nonce of the sent message.
     *  - fee: The LayerZero fee incurred for the message.
     *
     */
    function cancelOffer(
        CancelOfferParams calldata _params,
        MessagingFee calldata _fee
    ) external payable returns (MessagingReceipt memory msgReceipt);
}
