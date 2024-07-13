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
    function _validatePricing(address _srcTokenAddress, uint256 _srcAmountLD, uint64 _exchangeRateSD) private {
        if (_srcAmountLD == 0 || _exchangeRateSD == 0) {
            revert InvalidPricing(_srcAmountLD, _exchangeRateSD);
        }

        if (_srcTokenAddress == address(0) && _srcAmountLD > msg.value) {
            revert InsufficientValue(_srcAmountLD, msg.value);
        }
    }

    function createOffer(
        CreateOfferParams calldata _params,
        MessagingFee calldata _fee
    )
        public
        payable
        virtual
        override
        returns (MessagingReceipt memory msgReceipt, CreateOfferReceipt memory createOfferReceipt)
    {
        bytes32 advertiser = addressToBytes32(msg.sender);
        address srcTokenAddress = bytes32ToAddress(_params.srcTokenAddress);

        (uint64 srcAmountSD, uint256 srcAmountLD) = _removeDust(_params.srcAmountLD, srcTokenAddress);
        _validatePricing(srcTokenAddress, srcAmountLD, _params.exchangeRateSD);

        bytes32 offerId = hashOffer(
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
        msgReceipt = _lzSend(_params.dstEid, payload, options, _fee, payable(msg.sender));

        createOfferReceipt = CreateOfferReceipt(offerId, srcAmountLD);

        transferFrom(srcTokenAddress, msg.sender, escrow, srcAmountLD);
    }

    function quoteCreateOffer(
        bytes32 _advertiser,
        CreateOfferParams calldata _params,
        bool _payInLzToken
    ) public view virtual returns (MessagingFee memory fee) {
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
        uint256 decimalConversionRate = _tokenAddress == address(0)
            ? 10 ** 12 // native
            : 10 ** (ERC20(_tokenAddress).decimals() - sharedDecimals); // token

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
