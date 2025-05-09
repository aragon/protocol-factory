// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import {DAO, Action} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {DAORegistry} from "@aragon/osx/framework/dao/DAORegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {
    PluginSetupProcessor,
    PluginSetupRef,
    hashHelpers
} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PlaceholderSetup} from "@aragon/osx/framework/plugin/repo/placeholder/PlaceholderSetup.sol";
import {ENSSubdomainRegistrar} from "@aragon/osx/framework/utils/ens/ENSSubdomainRegistrar.sol";
import {Executor as GlobalExecutor} from "@aragon/osx-commons-contracts/src/executors/Executor.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {AdminSetup} from "@aragon/admin-plugin/AdminSetup.sol";
import {Multisig} from "@aragon/multisig-plugin/Multisig.sol";
import {MultisigSetup} from "@aragon/multisig-plugin/MultisigSetup.sol";
import {TokenVotingSetup} from "@aragon/token-voting-plugin/TokenVotingSetup.sol";
import {GovernanceERC20} from "@aragon/token-voting-plugin/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/token-voting-plugin/ERC20/governance/GovernanceWrappedERC20.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {StagedProposalProcessorSetup} from "@aragon/staged-proposal-processor-plugin/StagedProposalProcessorSetup.sol";

import {ProtocolFactory} from "../src/ProtocolFactory.sol";
import {DAOHelper} from "../src/helpers/DAOHelper.sol";
import {PluginRepoHelper} from "../src/helpers/PluginRepoHelper.sol";
import {PSPHelper} from "../src/helpers/PSPHelper.sol";
import {ENSHelper} from "../src/helpers/ENSHelper.sol";

/// @notice This local script triggers a full deploy of OSx, along with the core Aragon plugins and the Management DAO
/// @dev No privileged actions are performed within this file. All of them take place within the ProtocolFactory contract, on-chain.
/// @dev Given that deploying the factory with all contracts embedded would hit the gas limit, the deployment has two stages:
/// @dev 1) Deploy the raw contracts and store their addresses locally (this file)
/// @dev 2) Deploy the factory with the addresses above and tell it to orchestrate the protocol deployment
contract TestUpgradeScript is Script {
    using stdJson for string;

    // Constants
    string constant VERSION = "1.4.x";

    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("OSX version", VERSION);
        console.log("- Deployment wallet:", vm.addr(privKey));
        console.log("- Chain ID:", block.chainid);
        console.log();

        _;

        vm.stopBroadcast();
    }

    function run() public broadcast {
        DAO managementDao = DAO(payable(address(0x0)));
        Multisig managementDaoMultisig = Multisig(address(0x0));
        PluginRepo adminRepo = PluginRepo(address(0x0));
        PluginRepo multisigRepo = PluginRepo(address(0x0));
        PluginRepo tokenVotingRepo = PluginRepo(address(0x0));
        PluginRepo sppRepo = PluginRepo(address(0x0));
        DAORegistry daoRegistry = DAORegistry(address(0x0));
        PluginRepoRegistry pluginRepoRegistry = PluginRepoRegistry(address(0x0));
        PluginSetupProcessor pluginSetupProcessor = PluginSetupProcessor(address(0x0));
        DAOFactory daoFactory = DAOFactory(address(0x0));
        PluginRepoFactory pluginRepoFactory = PluginRepoFactory(address(0x0));

        // 1) NEW PLUGIN VERSIONS
        Action[] memory actions = new Action[](8);

        address newAdminSetup = address(new AdminSetup());
        actions[0] = Action({
            to: address(adminRepo),
            value: 0,
            data: abi.encodeCall(
                PluginRepo.createVersion,
                (
                    1, // target release
                    newAdminSetup,
                    bytes("ipfs://new-build"),
                    bytes("ipfs://new-release")
                )
            )
        });
        address newMultisigSetup = address(new MultisigSetup());
        actions[1] = Action({
            to: address(multisigRepo),
            value: 0,
            data: abi.encodeCall(
                PluginRepo.createVersion,
                (
                    1, // target release
                    newMultisigSetup,
                    bytes("ipfs://new-build"),
                    bytes("ipfs://new-release")
                )
            )
        });
        address newTokenVotingSetup = address(
            new TokenVotingSetup(
                new GovernanceERC20(
                    IDAO(address(0)), "", "", GovernanceERC20.MintSettings(new address[](0), new uint256[](0))
                ),
                new GovernanceWrappedERC20(IERC20Upgradeable(address(0)), "", "")
            )
        );
        actions[2] = Action({
            to: address(tokenVotingRepo),
            value: 0,
            data: abi.encodeCall(
                PluginRepo.createVersion,
                (
                    1, // target release
                    newTokenVotingSetup,
                    bytes("ipfs://new-build"),
                    bytes("ipfs://new-release")
                )
            )
        });
        address newSppSetup = address(new StagedProposalProcessorSetup());
        actions[3] = Action({
            to: address(sppRepo),
            value: 0,
            data: abi.encodeCall(
                PluginRepo.createVersion,
                (
                    1, // target release
                    newSppSetup,
                    bytes("ipfs://new-build"),
                    bytes("ipfs://new-release")
                )
            )
        });

        // 2) REGISTRY PERMISSIONS

        DAOFactory newDaoFactory = new DAOFactory(daoRegistry, pluginSetupProcessor);
        PluginRepoFactory newPluginRepoFactory = new PluginRepoFactory(pluginRepoRegistry);

        // Move the REGISTER_DAO_PERMISSION_ID permission on the DAORegistry from the old DAOFactory to the new one
        PermissionLib.MultiTargetPermission[] memory newPermissions = new PermissionLib.MultiTargetPermission[](4);
        newPermissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: address(daoRegistry),
            who: address(daoFactory),
            condition: address(0),
            permissionId: keccak256("REGISTER_DAO_PERMISSION")
        });
        newPermissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(daoRegistry),
            who: address(newDaoFactory),
            condition: address(0),
            permissionId: keccak256("REGISTER_DAO_PERMISSION")
        });

        // Move the REGISTER_PLUGIN_REPO_PERMISSION_ID permission on the PluginRepoRegistry from the old PluginRepoFactory to the new PluginRepoFactory
        newPermissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: address(pluginRepoRegistry),
            who: address(pluginRepoFactory),
            condition: address(0),
            permissionId: keccak256("REGISTER_PLUGIN_REPO_PERMISSION")
        });
        newPermissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(pluginRepoRegistry),
            who: address(newPluginRepoFactory),
            condition: address(0),
            permissionId: keccak256("REGISTER_PLUGIN_REPO_PERMISSION")
        });
        actions[4] = Action({
            to: address(managementDao),
            value: 0,
            data: abi.encodeCall(PermissionManager.applyMultiTargetPermissions, (newPermissions))
        });

        // 3) REGISTRY IMPLEMENTATIONS

        // Upgrade the DaoRegistry to the new implementation
        address newDaoRegistryBase = address(new DAORegistry());
        actions[5] = Action({
            to: address(daoRegistry),
            value: 0,
            data: abi.encodeCall(UUPSUpgradeable.upgradeTo, (newDaoRegistryBase))
        });
        // Upgrade the PluginRepoRegistry to the new implementation
        address newPluginRepoRegistryBase = address(new PluginRepoRegistry());
        actions[6] = Action({
            to: address(pluginRepoRegistry),
            value: 0,
            data: abi.encodeCall(UUPSUpgradeable.upgradeTo, (newPluginRepoRegistryBase))
        });

        // 4) MANAGING DAO IMPLEMENTATION

        // Upgrade the management DAO to a new implementation
        address newDaoBase = address(payable(new DAO()));
        actions[7] = Action({
            to: address(managementDao),
            value: 0,
            data: abi.encodeCall(UUPSUpgradeable.upgradeTo, (newDaoBase))
        });

        // PROPOSAL

        uint256 proposalId = managementDaoMultisig.createProposal(
            bytes("ipfs://prop-new-mgmt-dao-impl"),
            actions,
            0, // startdate
            uint64(block.timestamp + 60 * 60), // enddate
            bytes("")
        );

        console.log("Proposal ID:", proposalId);
        console.log();

        // uint256 proposalId = 0x9627ccf8c5d4d80162a81e6b7a03584b3c6b0beeaa6342780b33e5b0fcb4cdf1;
        // managementDaoMultisig.approve(proposalId, true);

        // Done

        console.log("OSx contracts:");
        console.log("- New DAOFactory", address(newDaoFactory));
        console.log("- New PluginRepoFactory", address(newPluginRepoFactory));
        console.log("- New DAO implementation", address(newDaoBase));
        console.log();

        console.log("Registries (proxy):");
        console.log("- DAORegistry", address(daoRegistry));
        console.log("- PluginRepoRegistry", address(pluginRepoRegistry));
        console.log();

        console.log("Protocol helpers:");
        console.log("- Management DAO", address(managementDao));
        console.log("- Management DAO multisig", address(managementDaoMultisig));
        console.log();

        console.log("Plugin setup's:");
        console.log("- New Admin Setup", address(newAdminSetup));
        console.log("- New Multisig Setup", address(newMultisigSetup));
        console.log("- New TokenVoting Setup", address(newTokenVotingSetup));
        console.log("- New SPP Setup", address(newSppSetup));
        console.log();
    }
}
