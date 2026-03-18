// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// -----------------------------------------------
// ERRORS
// -----------------------------------------------
error UnauthorizedBuyer();
error UnauthorizedSeller();
error UnauthorizedArbiter();
error UnauthorizedCaller();
error InvalidState(uint8 expected, uint8 actual);
error DisputeActive();
error InvalidAddress();
error BuyerCannotBeSeller();
error BuyerCannotBeArbiter();
error ArbiterCannotBeSeller();
error PriceMustBeGreaterThanZero();
error IncorrectDepositAmount(uint256 expected, uint256 actual);
error TransferToSellerFailed();
error RefundToBuyerFailed();

// -----------------------------------------------
// INTERFACE
// -----------------------------------------------
interface IEscrow {
    event FundsDeposited(address indexed buyer, uint256 amount);
    event DeliveryConfirmed(address indexed buyer);
    event FundsReleased(address indexed seller, uint256 amount);
    event RefundIssued(address indexed buyer, uint256 amount);
    event DisputeRaised(address indexed raisedBy);
    event DisputeResolved(address indexed resolvedBy, bool releasedToSeller);

    function deposit() external payable;
    function confirmDelivery() external;
    function confirmFulfillment() external;
    function releaseFunds() external;
    function refundBuyer() external;
    function raiseDispute() external;
    function getBalance() external view returns (uint256);
    function getState() external view returns (uint8);
    function getApprovals() external view returns (bool, bool);
}

// -----------------------------------------------
// CONTRACT
// -----------------------------------------------
contract Escrow is IEscrow, ReentrancyGuard {
    // 1. TYPE DECLARATIONS
    enum State {
        AWAITING_PAYMENT,
        AWAITING_DELIVERY,
        COMPLETE,
        DISPUTED,
        REFUNDED
    }

    // 2. STATE VARIABLES — immutables
    address public immutable BUYER;
    address public immutable SELLER;
    address public immutable ARBITER;
    uint256 public immutable PRICE;

    // 2. STATE VARIABLES — mutable
    bool public buyerApproved = false;
    bool public sellerApproved = false;
    bool public disputeRaised = false;
    State public currentState = State.AWAITING_PAYMENT;

    // 3. MODIFIERS
    modifier onlyBuyer() {
        _checkBuyer();
        _;
    }

    modifier onlySeller() {
        _checkSeller();
        _;
    }

    modifier onlyArbiter() {
        _checkArbiter();
        _;
    }

    modifier onlyBuyerOrSeller() {
        _checkBuyerOrSeller();
        _;
    }

    modifier inState(State expectedState) {
        _checkState(expectedState);
        _;
    }

    modifier noActiveDispute() {
        _noActiveDispute();
        _;
    }

    // 4. CONSTRUCTOR
    constructor(address _seller, address _arbiter, uint256 _price) {
        if (_seller == address(0)) revert InvalidAddress();
        if (_arbiter == address(0)) revert InvalidAddress();
        if (_seller == msg.sender) revert BuyerCannotBeSeller();
        if (_arbiter == msg.sender) revert BuyerCannotBeArbiter();
        if (_arbiter == _seller) revert ArbiterCannotBeSeller();
        if (_price == 0) revert PriceMustBeGreaterThanZero();

        BUYER = msg.sender;
        SELLER = _seller;
        ARBITER = _arbiter;
        PRICE = _price;
    }

    // 5. EXTERNAL FUNCTIONS

    function deposit()
        external
        payable
        onlyBuyer
        inState(State.AWAITING_PAYMENT)
    {
        if (msg.value != PRICE) {
            revert IncorrectDepositAmount(PRICE, msg.value);
        }
        currentState = State.AWAITING_DELIVERY;
        emit FundsDeposited(BUYER, msg.value);
    }

    function confirmDelivery()
        external
        onlyBuyer
        inState(State.AWAITING_DELIVERY)
        noActiveDispute
    {
        buyerApproved = true;
        emit DeliveryConfirmed(BUYER);

        if (sellerApproved) {
            _completeEscrow();
        }
    }

    function confirmFulfillment()
        external
        onlySeller
        inState(State.AWAITING_DELIVERY)
        noActiveDispute
    {
        sellerApproved = true;

        if (buyerApproved) {
            _completeEscrow();
        }
    }

    function raiseDispute()
        external
        onlyBuyerOrSeller
        inState(State.AWAITING_DELIVERY)
    {
        disputeRaised = true;
        currentState = State.DISPUTED;
        emit DisputeRaised(msg.sender);
    }

    function releaseFunds()
        external
        onlyArbiter
        inState(State.DISPUTED)
        nonReentrant
    {
        disputeRaised = false;
        currentState = State.COMPLETE;
        emit DisputeResolved(ARBITER, true);
        _releaseFundsToSeller();
    }

    function refundBuyer()
        external
        onlyArbiter
        inState(State.DISPUTED)
        nonReentrant
    {
        disputeRaised = false;
        currentState = State.REFUNDED;

        uint256 amount = address(this).balance;

        // CEI — events before transfer
        emit DisputeResolved(ARBITER, false);
        emit RefundIssued(BUYER, amount);

        // slither-disable-next-line arbitrary-send-eth,low-level-calls
        (bool success, ) = payable(BUYER).call{value: amount}("");
        if (!success) revert RefundToBuyerFailed();
    }

    // 6. EXTERNAL VIEW FUNCTIONS

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getState() external view returns (uint8) {
        return uint8(currentState);
    }

    function getApprovals() external view returns (bool _buyer, bool _seller) {
        return (buyerApproved, sellerApproved);
    }

    // 7. INTERNAL FUNCTIONS

    function _completeEscrow() internal {
        currentState = State.COMPLETE;
        _releaseFundsToSeller();
    }

    function _releaseFundsToSeller() internal {
        uint256 amount = address(this).balance;
        emit FundsReleased(SELLER, amount);
        // slither-disable-next-line arbitrary-send-eth,low-level-calls
        (bool success, ) = payable(SELLER).call{value: amount}("");
        if (!success) revert TransferToSellerFailed();
    }

    function _checkBuyer() internal view {
        if (msg.sender != BUYER) revert UnauthorizedBuyer();
    }

    function _checkSeller() internal view {
        if (msg.sender != SELLER) revert UnauthorizedSeller();
    }

    function _checkArbiter() internal view {
        if (msg.sender != ARBITER) revert UnauthorizedArbiter();
    }

    function _checkBuyerOrSeller() internal view {
        if (msg.sender != BUYER && msg.sender != SELLER) {
            revert UnauthorizedCaller();
        }
    }

    function _checkState(State expectedState) internal view {
        if (currentState != expectedState) {
            revert InvalidState(uint8(expectedState), uint8(currentState));
        }
    }

    function _noActiveDispute() internal view {
        if (disputeRaised) revert DisputeActive();
    }
}
