// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Escrow} from "../src/Escrow.sol";

import {
    InvalidAddress,
    BuyerCannotBeSeller,
    BuyerCannotBeArbiter,
    ArbiterCannotBeSeller,
    PriceMustBeGreaterThanZero,
    UnauthorizedBuyer,
    UnauthorizedSeller,
    UnauthorizedArbiter,
    UnauthorizedCaller,
    InvalidState,
    IncorrectDepositAmount
} from "../src/Escrow.sol";

contract EscrowTest is Test {
    // ---- CONTRACTS & ACTORS ----
    Escrow public escrow;

    address public immutable BUYER = makeAddr("buyer");
    address public immutable SELLER = makeAddr("seller");
    address public immutable ARBITER = makeAddr("arbiter");
    address public immutable STRANGER = makeAddr("stranger");

    uint256 public constant PRICE = 1 ether;

    // ---- EVENTS ----
    event FundsDeposited(address indexed buyer, uint256 amount);
    event DeliveryConfirmed(address indexed buyer);
    event FundsReleased(address indexed seller, uint256 amount);
    event RefundIssued(address indexed buyer, uint256 amount);
    event DisputeRaised(address indexed raisedBy);
    event DisputeResolved(address indexed resolvedBy, bool releasedToSeller);

    // ---- SETUP ----
    function setUp() public {
        vm.deal(BUYER, 10 ether);
        vm.deal(SELLER, 10 ether);
        vm.deal(ARBITER, 10 ether);

        vm.prank(BUYER);
        escrow = new Escrow(SELLER, ARBITER, PRICE);
    }

    // ---- HELPERS ----
    function _deposit() internal {
        vm.prank(BUYER);
        escrow.deposit{value: PRICE}();
    }

    function _depositAndDispute() internal {
        _deposit();
        vm.prank(BUYER);
        escrow.raiseDispute();
    }

    // -----------------------------------------------
    // GROUP 1 — CONSTRUCTOR
    // -----------------------------------------------

    // Test 1
    function test_ConstructorSetsValuesCorrectly() public view {
        assertEq(escrow.BUYER(), BUYER);
        assertEq(escrow.SELLER(), SELLER);
        assertEq(escrow.ARBITER(), ARBITER);
        assertEq(escrow.PRICE(), PRICE);
        assertEq(escrow.getState(), 0);
    }

    // Test 2
    function test_RevertIf_SellerIsZeroAddress() public {
        vm.prank(BUYER);
        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector));
        new Escrow(address(0), ARBITER, PRICE);
    }

    // Test 3
    function test_RevertIf_ArbiterIsZeroAddress() public {
        vm.prank(BUYER);
        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector));
        new Escrow(SELLER, address(0), PRICE);
    }

    // Test 4
    function test_RevertIf_BuyerIsSeller() public {
        vm.prank(BUYER);
        vm.expectRevert(abi.encodeWithSelector(BuyerCannotBeSeller.selector));
        new Escrow(BUYER, ARBITER, PRICE);
    }

    // Test 5
    function test_RevertIf_BuyerIsArbiter() public {
        vm.prank(BUYER);
        vm.expectRevert(abi.encodeWithSelector(BuyerCannotBeArbiter.selector));
        new Escrow(SELLER, BUYER, PRICE);
    }

    // Test 6
    function test_RevertIf_ArbiterIsSeller() public {
        vm.prank(BUYER);
        vm.expectRevert(abi.encodeWithSelector(ArbiterCannotBeSeller.selector));
        new Escrow(SELLER, SELLER, PRICE);
    }

    // Test 7
    function test_RevertIf_PriceIsZero() public {
        vm.prank(BUYER);
        vm.expectRevert(
            abi.encodeWithSelector(PriceMustBeGreaterThanZero.selector)
        );
        new Escrow(SELLER, ARBITER, 0);
    }

    // -----------------------------------------------
    // GROUP 2 — DEPOSIT
    // -----------------------------------------------

    // Test 8
    function test_DepositSucceeds() public {
        vm.expectEmit(true, false, false, true);
        emit FundsDeposited(BUYER, PRICE);

        _deposit();

        assertEq(escrow.getState(), 1);
        assertEq(escrow.getBalance(), PRICE);
    }

    // Test 9
    function test_RevertIf_StrangerDeposits() public {
        vm.deal(STRANGER, 10 ether); // ✅
        vm.prank(STRANGER);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedBuyer.selector));
        escrow.deposit{value: PRICE}();
    }

    // Test 10
    function test_RevertIf_DepositWrongAmount() public {
        vm.prank(BUYER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IncorrectDepositAmount.selector,
                PRICE,
                0.5 ether
            )
        );
        escrow.deposit{value: 0.5 ether}();
    }

    // Test 11
    function test_RevertIf_DepositTwice() public {
        _deposit();
        vm.prank(BUYER);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidState.selector, uint8(0), uint8(1))
        );
        escrow.deposit{value: PRICE}();
    }

    // -----------------------------------------------
    // GROUP 3 — CONFIRM DELIVERY & FULFILLMENT
    // -----------------------------------------------

    // Test 12 ✅ Fixed — all references use BUYER/SELLER
    function test_BothPartiesConfirm_ReleasesFunds() public {
        _deposit();

        uint256 sellerBalanceBefore = SELLER.balance;

        vm.prank(BUYER);
        escrow.confirmDelivery();
        assertEq(escrow.getState(), 1);

        vm.expectEmit(true, false, false, true);
        emit FundsReleased(SELLER, PRICE);

        vm.prank(SELLER);
        escrow.confirmFulfillment();

        assertEq(escrow.getState(), 2);
        assertEq(SELLER.balance, sellerBalanceBefore + PRICE);
        assertEq(escrow.getBalance(), 0);
    }

    // Test 13
    function test_SellerConfirmsFirst_ThenBuyer_ReleasesFunds() public {
        _deposit();

        uint256 sellerBalanceBefore = SELLER.balance;

        vm.prank(SELLER);
        escrow.confirmFulfillment();
        assertEq(escrow.getState(), 1);

        vm.prank(BUYER);
        escrow.confirmDelivery();

        assertEq(escrow.getState(), 2);
        assertEq(SELLER.balance, sellerBalanceBefore + PRICE);
    }

    // Test 14
    function test_RevertIf_StrangerConfirmsDelivery() public {
        _deposit();
        vm.prank(STRANGER);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedBuyer.selector));
        escrow.confirmDelivery();
    }

    // Test 15
    function test_RevertIf_StrangerConfirmsFulfillment() public {
        _deposit();
        vm.prank(STRANGER);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedSeller.selector));
        escrow.confirmFulfillment();
    }

    // Test 16
    function test_GetApprovals_TracksCorrectly() public {
        _deposit();

        (bool buyerApp, bool sellerApp) = escrow.getApprovals();
        assertFalse(buyerApp);
        assertFalse(sellerApp);

        vm.prank(BUYER);
        escrow.confirmDelivery();

        (buyerApp, sellerApp) = escrow.getApprovals();
        assertTrue(buyerApp);
        assertFalse(sellerApp);
    }

    // -----------------------------------------------
    // GROUP 4 — DISPUTE
    // -----------------------------------------------

    // Test 17
    function test_BuyerCanRaiseDispute() public {
        _deposit();

        vm.expectEmit(true, false, false, false);
        emit DisputeRaised(BUYER);

        vm.prank(BUYER);
        escrow.raiseDispute();

        assertEq(escrow.getState(), 3);
        assertTrue(escrow.disputeRaised());
    }

    // Test 18
    function test_SellerCanRaiseDispute() public {
        _deposit();

        vm.expectEmit(true, false, false, false);
        emit DisputeRaised(SELLER);

        vm.prank(SELLER);
        escrow.raiseDispute();

        assertEq(escrow.getState(), 3);
    }

    // Test 19
    function test_RevertIf_StrangerRaisesDispute() public {
        _deposit();
        vm.prank(STRANGER);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector));
        escrow.raiseDispute();
    }

    // Test 20
    function test_RevertIf_ConfirmDelivery_DuringDispute() public {
        _depositAndDispute();
        vm.prank(BUYER);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidState.selector, uint8(1), uint8(3))
        );
        escrow.confirmDelivery();
    }

    // Test 21
    function test_RevertIf_ConfirmFulfillment_DuringDispute() public {
        _depositAndDispute();
        vm.prank(SELLER);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidState.selector, uint8(1), uint8(3))
        );
        escrow.confirmFulfillment();
    }
    // -----------------------------------------------
    // GROUP 5 — ARBITER RESOLUTION
    // -----------------------------------------------

    // Test 22
    function test_ArbiterReleaseFunds_ToSeller() public {
        _depositAndDispute();

        uint256 sellerBalanceBefore = SELLER.balance;

        vm.expectEmit(true, false, false, true);
        emit DisputeResolved(ARBITER, true);

        vm.prank(ARBITER);
        escrow.releaseFunds();

        assertEq(escrow.getState(), 2);
        assertFalse(escrow.disputeRaised());
        assertEq(SELLER.balance, sellerBalanceBefore + PRICE);
        assertEq(escrow.getBalance(), 0);
    }

    // Test 23
    function test_ArbiterRefundBuyer() public {
        _depositAndDispute();
        console.log("Balance before refund:", escrow.getBalance());
        console.log("Buyer balance before:", BUYER.balance);

        uint256 buyerBalanceBefore = BUYER.balance;

        vm.expectEmit(true, false, false, true);
        emit DisputeResolved(ARBITER, false);

        vm.prank(ARBITER);
        escrow.refundBuyer();

        assertEq(escrow.getState(), 4);
        assertFalse(escrow.disputeRaised());
        assertEq(BUYER.balance, buyerBalanceBefore + PRICE);
        assertEq(escrow.getBalance(), 0);
    }

    // Test 24
    function test_RevertIf_NonArbiterCallsReleaseFunds() public {
        _depositAndDispute();
        vm.prank(BUYER);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedArbiter.selector));
        escrow.releaseFunds();
    }

    // Test 25
    function test_RevertIf_NonArbiterCallsRefundBuyer() public {
        _depositAndDispute();
        vm.prank(SELLER);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedArbiter.selector));
        escrow.refundBuyer();
    }

    // Test 26
    function test_RevertIf_ReleaseFunds_WithoutDispute() public {
        _deposit();
        vm.prank(ARBITER);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidState.selector, uint8(3), uint8(1))
        );
        escrow.releaseFunds();
    }

    // -----------------------------------------------
    // GROUP 6 — FUZZ TESTS
    // -----------------------------------------------

    // Test 27
    function testFuzz_RevertIf_WrongDepositAmount(uint256 wrongAmount) public {
        wrongAmount = bound(wrongAmount, 1, 9 ether); // ✅
        vm.assume(wrongAmount != PRICE);

        vm.prank(BUYER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IncorrectDepositAmount.selector,
                PRICE,
                wrongAmount
            )
        );
        escrow.deposit{value: wrongAmount}();
    }
    // Test 28 ✅ Fixed — PRICE() uppercase
    function testFuzz_DeployWithAnyValidPrice(uint256 _price) public {
        _price = bound(_price, 1, 100 ether);

        vm.deal(BUYER, _price + 1 ether);
        vm.prank(BUYER);
        Escrow newEscrow = new Escrow(SELLER, ARBITER, _price);

        assertEq(newEscrow.PRICE(), _price); // ✅ uppercase

        vm.prank(BUYER);
        newEscrow.deposit{value: _price}();

        assertEq(newEscrow.getBalance(), _price);
    }

    // -----------------------------------------------
    // GROUP 7 — INTEGRATION TESTS
    // -----------------------------------------------

    // Test 29
    function test_FullFlow_HappyPath() public {
        uint256 sellerBalanceBefore = SELLER.balance;

        _deposit();
        assertEq(escrow.getState(), 1);

        vm.prank(BUYER);
        escrow.confirmDelivery();

        vm.prank(SELLER);
        escrow.confirmFulfillment();

        assertEq(escrow.getState(), 2);
        assertEq(escrow.getBalance(), 0);
        assertEq(SELLER.balance, sellerBalanceBefore + PRICE);
    }

    // Test 30 ✅ Fixed — balance recorded AFTER deposit
    function test_FullFlow_DisputeRefund() public {
        _deposit();
        uint256 buyerBalanceAfterDeposit = BUYER.balance; // ✅ after deposit

        vm.prank(BUYER);
        escrow.raiseDispute();
        assertEq(escrow.getState(), 3);

        vm.prank(ARBITER);
        escrow.refundBuyer();

        assertEq(escrow.getState(), 4);
        assertEq(BUYER.balance, buyerBalanceAfterDeposit + PRICE); // ✅ got refund
        assertEq(escrow.getBalance(), 0);
    }

    // Test 31
    function test_FullFlow_DisputeRelease() public {
        uint256 sellerBalanceBefore = SELLER.balance;

        _deposit();

        vm.prank(SELLER);
        escrow.raiseDispute();

        vm.prank(ARBITER);
        escrow.releaseFunds();

        assertEq(escrow.getState(), 2);
        assertEq(SELLER.balance, sellerBalanceBefore + PRICE);
        assertEq(escrow.getBalance(), 0);
    }
}
