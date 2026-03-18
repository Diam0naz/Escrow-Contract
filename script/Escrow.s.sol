// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Escrow} from "../src/Escrow.sol";

contract DeployEscrow is Script {

    // ---- DEPLOYMENT CONFIG ----
    // Replace these before deploying to a real network
    address public constant SELLER  = 0x0000000000000000000000000000000000000001; // TODO: replace
    address public constant ARBITER = 0x0000000000000000000000000000000000000002; // TODO: replace
    uint256 public constant PRICE   = 1 ether;

    Escrow public escrow;

    function setUp() public {}

    function run() public {
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // address SELLER = vm.envAddress("SELLER_ADDRESS");
        // address ARBITER = vm.envAddress("ARBITER_ADDRESS");
        // uint256 PRICE = 1 ether;

        vm.startBroadcast(deployerPrivateKey);
        escrow = new Escrow(SELLER, ARBITER, PRICE);

        vm.stopBroadcast();

        // Log deployment details
        console.log("=============================");
        console.log("Escrow deployed successfully");
        console.log("=============================");
        console.log("Contract address :", address(escrow));
        console.log("Buyer (deployer) :", escrow.BUYER());
        console.log("Seller           :", escrow.SELLER());
        console.log("Arbiter          :", escrow.ARBITER());
        console.log("Price (wei)      :", escrow.PRICE());
        console.log("Initial state    :", escrow.getState()); // 0 = AWAITING_PAYMENT
        console.log("=============================");
    }
}

