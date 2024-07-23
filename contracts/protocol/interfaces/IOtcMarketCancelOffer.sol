// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

import { IOtcMarketCore } from "./IOtcMarketCore.sol";

interface IOtcMarketCancelOffer is IOtcMarketCore {
    /**
     * @dev The account is not the offer seller.
     */
    error OnlySeller(bytes32 seller, bytes32 account);

    /**
     * @dev Emmited when
     * - cancel offer appeal message came to the offer destination chain
     * - cancel offer message came back to the offer source chain.
     */
    event OfferCanceled(bytes32 indexed offerId);

    /**
     * @notice Orders the offer to be canceled.
     * @param _offerId The ID of the offer to be canceled.
     * @param _fee The fee information supplied by the caller.
     *  - nativeFee: The native fee.
     *  - lzTokenFee: The lzToken fee.
     * @param _extraSendOptions The extra send options for return cancel offer message.
     * @return msgReceipt The LayerZero messaging receipt from the send() operation.
     *
     * @dev MessagingReceipt: LayerZero msg receipt
     *  - guid: The unique identifier for the sent message.
     *  - nonce: The nonce of the sent message.
     *  - fee: The LayerZero fee incurred for the message.
     *
     */
    function cancelOffer(
        bytes32 _offerId,
        MessagingFee calldata _fee,
        bytes calldata _extraSendOptions
    ) external payable returns (MessagingReceipt memory msgReceipt);
}
