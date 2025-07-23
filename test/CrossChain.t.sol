//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interface/IRebaseToken.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";

import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";

import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract CrossChain is Test {
    uint256 sepoliaFork;

    uint256 arbSepoliaFork;
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;
    Vault vault;
    RebaseTokenPool sepoliaPool;
    RebaseTokenPool arbSepoliaPool;

    address owner = makeAddr("owner");
    address user = makeAddr("user");
    uint256 SEND_VALUE = 1e5;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    //  struct NetworkDetails {
    //     uint64 chainSelector;
    //     address routerAddress;
    //     address linkAddress;
    //     address wrappedNativeAddress;
    //     address ccipBnMAddress;
    //     address ccipLnMAddress;
    //     address rmnProxyAddress;
    //     address registryModuleOwnerCustomAddress;
    //     address tokenAdminRegistryAddress;
    // }

    function setUp() public {
        sepoliaFork = vm.createSelectFork("sepolia-eth");
        arbSepoliaFork = vm.createFork("arb-sepolia");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork)); //make the address persist for both chain
        //now createselectfork is sepolia , so can use block.chainid

        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        //deploy and configure on Sepolia
        vm.startPrank(owner);
        sepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));
        //Owner->>RegistryModule: 1. registerAdminViaOwner(token)
        // RegistryModule->>TokenAdminRegistry: Record pendingAdmin
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(sepoliaToken)
        );
        // Owner->>TokenContract: 2. call acceptAdminRole()
        // TokenContract->>TokenAdminRegistry: Verify and confirm admin
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        // Owner->>TokenAdminRegistry: 3. setPool(token, pool)
        // TokenAdminRegistry->>TokenPool: Establish binding relationship
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(sepoliaToken), address(sepoliaPool)
        );
        vm.stopPrank();

        //deploy and configure on arbitrum, change to arbitrum chain
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        arbSepoliaToken = new RebaseToken();
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbSepoliaToken)
        );
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(arbSepoliaToken), address(arbSepoliaPool)
        );
        vm.stopPrank();

        configureTokenPool(
            sepoliaFork,
            address(sepoliaPool),
            arbSepoliaNetworkDetails.chainSelector,
            address(arbSepoliaPool),
            address(arbSepoliaToken)
        );

        configureTokenPool(
            arbSepoliaFork,
            address(arbSepoliaPool),
            sepoliaNetworkDetails.chainSelector,
            address(sepoliaPool),
            address(sepoliaToken)
        );
    }

    function configureTokenPool(
        uint256 fork,
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteTokenAddress
    ) public {
        vm.selectFork(fork);
        vm.prank(owner);

        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(address(remotePool));

        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        //           struct ChainUpdate {
        //     uint64 remoteChainSelector; // Remote chain selector
        //     bytes[] remotePoolAddresses; // Address of the remote pool, ABI encoded in the case of a remote EVM chain.
        //     bytes remoteTokenAddress; // Address of the remote token, ABI encoded in the case of a remote EVM chain.
        //     RateLimiter.Config outboundRateLimiterConfig; // Outbound rate limited config, meaning the rate limits for all of the onRamps for the given chain
        //     RateLimiter.Config inboundRateLimiterConfig; // Inbound rate limited config, meaning the rate limits for all of the offRamps for the given chain
        //   }
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        TokenPool(localPool).applyChainUpdates(new uint64[](0), chainsToAdd);
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        //action on localFork
        vm.selectFork(localFork);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user),
            data: "", //empty data
            tokenAmounts: tokenAmounts,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 500_000}))
        });

        // struct EVM2AnyMessage {
        //     bytes receiver; // abi.encode(receiver address) for dest EVM chains
        //     bytes data; // Data payload
        //     EVMTokenAmount[] tokenAmounts; // Token transfers
        //     address feeToken; // Address of feeToken. address(0) means you will send msg.value.
        //     bytes extraArgs; // Populate this with _argsToBytes(EVMExtraArgsV2)
        // }
        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);

        //get faucet link for user
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);

        //because of the faucet cannot use startPrnk and stopPrank
        vm.prank(user);
        IERC20(localNetworkDetails.linkAddress).approve(address(localNetworkDetails.routerAddress), fee);
        vm.prank(user);
        localToken.approve((address(localNetworkDetails.routerAddress)), amountToBridge);
        uint256 localBalnceBefore = localToken.balanceOf(user);
        vm.prank(user);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);

        uint256 localBalnceAfter = localToken.balanceOf(user);
        uint256 localUserInterestRate = localToken.getUserInterestRate(user);
        //check localFork balance
        assertEq(localBalnceBefore - localBalnceAfter, amountToBridge);

        //action on remoteFork
        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 20 minutes);

        uint256 remoteBalanceBefore = remoteToken.balanceOf(user);

        vm.selectFork(localFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);
        uint256 remoteBalanceAfter = remoteToken.balanceOf(user);
        uint256 remoteUserInterestRate = remoteToken.getUserInterestRate(user);
        assertEq(remoteBalanceAfter - remoteBalanceBefore, amountToBridge);
        assertEq(remoteUserInterestRate, localUserInterestRate);
    }

    function testBrodgeAllTokens() public {
        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.startPrank(user);
        //deposte
        vault.deposite{value: SEND_VALUE}();
        assertEq(sepoliaToken.balanceOf(user), SEND_VALUE);
        //bridge
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );

        //bridge back
        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 20 minutes);
        uint256 sendAmount = arbSepoliaToken.balanceOf(user);
        bridgeTokens(
            sendAmount,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            arbSepoliaToken,
            sepoliaToken
        );

        vm.stopPrank();
    }
}
