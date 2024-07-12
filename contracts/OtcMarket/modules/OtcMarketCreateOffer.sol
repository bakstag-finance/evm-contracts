// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { MessagingReceipt, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

import { OtcMarketCore } from "./OtcMarketCore.sol";
import "../Utils.sol";

/**
 * @dev Module of {OtcMarket} for offer creation.
 */
abstract contract OtcMarketCreateOffer is OtcMarketCore {
    modifier _validatePricing(uint256 _srcAmountLD, uint64 _exchangeRateSD) {
        if (_srcAmountLD == 0 || _exchangeRateSD == 0) {
            revert InvalidPricing(_srcAmountLD, _exchangeRateSD);
        }
        _;
    }

    function createOffer(
        CreateOfferParams calldata _params,
        MessagingFee calldata _fee
    )
        public
        payable
        virtual
        override
        _validatePricing(_params.srcAmountLD, _params.exchangeRateSD)
        returns (MessagingReceipt memory msgReceipt, bytes32 offerId)
    {
        address _advertiser = msg.sender;
        bytes32 advertiser = addressToBytes32(_advertiser);

        if (_params.srcAmountLD == 0 || _params.exchangeRateSD == 0) {
            revert InvalidPricing(_params.srcAmountLD, _params.exchangeRateSD);
        }
        (uint64 srcAmountSD, uint256 srcAmountLD) = _removeDust(
            _params.srcAmountLD,
            bytes32ToAddress(_params.srcTokenAddress)
        );

        offerId = hashOffer(
            advertiser,
            eid,
            _params.dstEid,
            _params.srcTokenAddress,
            _params.dstTokenAddress,
            _params.exchangeRateSD
        );
        if (offers[offerId].srcAmountSD != 0) {
            revert OfferAlreadyExists(offerId);
        }

        offers[offerId] = Offer(
            advertiser,
            _params.beneficiary,
            eid,
            _params.dstEid,
            _params.srcTokenAddress,
            _params.dstTokenAddress,
            srcAmountSD,
            _params.exchangeRateSD
        );

        emit OfferCreated(offerId, offers[offerId]);

        (bytes memory payload, bytes memory options) = _buildCreateOfferMsgAndOptions(offerId, offers[offerId]);
        msgReceipt = _lzSend(_params.dstEid, payload, options, _fee, payable(_advertiser));

        ERC20(bytes32ToAddress(_params.srcTokenAddress)).transferFrom(_advertiser, address(this), srcAmountLD);
    }

    function quoteCreateOffer(
        bytes32 _advertiser,
        CreateOfferParams calldata _params,
        bool _payInLzToken
    )
        public
        payable
        virtual
        _validatePricing(_params.srcAmountLD, _params.exchangeRateSD)
        returns (MessagingFee memory fee)
    {
        (uint64 srcAmountSD, ) = _removeDust(_params.srcAmountLD, bytes32ToAddress(_params.srcTokenAddress));

        bytes32 offerId = hashOffer(
            _advertiser,
            eid,
            _params.dstEid,
            _params.srcTokenAddress,
            _params.dstTokenAddress,
            _params.exchangeRateSD
        );

        (bytes memory payload, bytes memory options) = _buildCreateOfferMsgAndOptions(
            offerId,
            Offer(
                _advertiser,
                _params.beneficiary,
                eid,
                _params.dstEid,
                _params.srcTokenAddress,
                _params.dstTokenAddress,
                srcAmountSD,
                _params.exchangeRateSD
            )
        );

        fee = _quote(_params.dstEid, payload, options, _payInLzToken);
    }

    function _receiveCreateOffer(bytes32 _offerId, Offer memory _offer) internal virtual override {
        offers[_offerId] = _offer;

        emit OfferCreated(_offerId, _offer);
    }

    function _decodeOfferCreated(
        bytes calldata _payload
    )
        internal
        pure
        override
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
        )
    {
        offerId = bytes32(_payload[:32]);
        advertiser = bytes32(_payload[32:64]);
        beneficiary = bytes32(_payload[64:96]);
        srcEid = uint32(bytes4(_payload[96:100]));
        dstEid = uint32(bytes4(_payload[100:104]));
        srcTokenAddress = bytes32(_payload[104:136]);
        dstTokenAddress = bytes32(_payload[136:168]);
        srcAmountSD = uint64(bytes8(_payload[168:176]));
        exchangeRateSD = uint64(bytes8(_payload[176:184]));
    }

    function _removeDust(
        uint256 _amountLD,
        address _tokenAddress
    ) private view returns (uint64 amountSD, uint256 amountLD) {
        uint256 decimalConversionRate = 10 ** (ERC20(_tokenAddress).decimals() - sharedDecimals);

        amountSD = toSD(_amountLD, decimalConversionRate);
        amountLD = toLD(amountSD, decimalConversionRate); // remove dust
    }

    function _buildCreateOfferMsgAndOptions(
        bytes32 _offerId,
        Offer memory _offer
    ) private view returns (bytes memory payload, bytes memory options) {
        bytes memory msgPayload = abi.encodePacked(
            _offerId,
            _offer.advertiser,
            _offer.beneficiary,
            _offer.srcEid,
            _offer.dstEid,
            _offer.srcTokenAddress,
            _offer.dstTokenAddress,
            _offer.srcAmountSD,
            _offer.exchangeRateSD
        );
        payload = abi.encodePacked(Message.OfferCreated, msgPayload);

        options = enforcedOptions[_offer.dstEid][uint16(Message.OfferCreated)];
        if (options.length == 0) {
            revert InvalidOptions(options);
        }
    }
}
