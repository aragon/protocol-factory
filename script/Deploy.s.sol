// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAORegistry} from "@aragon/osx/framework/dao/DAORegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PlaceholderSetup} from "@aragon/osx/framework/plugin/repo/placeholder/PlaceholderSetup.sol";
import {ENSSubdomainRegistrar} from "@aragon/osx/framework/utils/ens/ENSSubdomainRegistrar.sol";
import {Executor as GlobalExecutor} from "@aragon/osx-commons-contracts/src/executors/Executor.sol";

import {AdminSetup} from "@aragon/admin-plugin/AdminSetup.sol";
import {MultisigSetup} from "@aragon/multisig-plugin/MultisigSetup.sol";
import {TokenVotingSetup} from "@aragon/token-voting-plugin/TokenVotingSetup.sol";
import {GovernanceERC20} from "@aragon/token-voting-plugin/erc20/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/token-voting-plugin/erc20/GovernanceWrappedERC20.sol";
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
contract DeployScript is Script {
    using stdJson for string;

    // Constants
    string constant VERSION = "1.4";
    string constant DEFAULT_DAO_ENS_DOMAIN = "dao";
    string constant DEFAULT_MANAGEMENT_DAO_SUBDOMAIN = "management";
    string constant DEFAULT_PLUGIN_ENS_SUBDOMAIN = "plugin";
    string constant DEFAULT_MANAGEMENT_DAO_MEMBERS_FILE_NAME = "multisig-members.json";

    string DEFAULT_ADMIN_RELEASE_METADATA = "ipfs://bafkreifbwooo3h36htzscftwm3kouoktcvkqyhaxluodo6xkyprnon3r54";
    string DEFAULT_ADMIN_BUILD_METADATA = "ipfs://bafkreifijshftf47q5mtoibfvwkzv42reqf4uddi46i7kcblt6bpsvgii4";
    string DEFAULT_MULTISIG_RELEASE_METADATA = "ipfs://bafkreiesxfvwf7qphbpw2epmabrrz2alwo66fso7tjx3cbt63k4xzec3ma";
    string DEFAULT_MULTISIG_BUILD_METADATA = "ipfs://bafkreiaipjj2ryy2ui77crwmgbamjkmr6xbdvrviylh4z4kf54sq2etvgu";
    string DEFAULT_TOKEN_VOTING_RELEASE_METADATA = "ipfs://QmWjZArvePnMPgbfKAMW3TidbqHEy68UV6SvRBhiaygGta";
    string DEFAULT_TOKEN_VOTING_BUILD_METADATA = "ipfs://QmfXUy5Lc4iqg8DvgWdSSD2ZhCmCGvE2WTdWYFE9sosCRc";
    string DEFAULT_SPP_RELEASE_METADATA = "ipfs://bafkreif23p6yw325rkwwlhgkudiasvq64lonqmfnt7ls5ksfam5hedcb4m";
    string DEFAULT_SPP_BUILD_METADATA = "ipfs://bafkreifia6hhz7klfbaqawd4vcplkoiesycbmrf5c2x24zfuivyn35mfsu";
    string DEFAULT_MANAGEMENT_DAO_METADATA = "ipfs://bafkreibemfrxeuwfaono6k37vbi66fctcwtioiyctrl4fvqtqmiodt2mle";

    DAO daoBase;
    DAORegistry daoRegistryBase;
    PluginRepoRegistry pluginRepoRegistryBase;
    PlaceholderSetup placeholderSetup;
    ENSSubdomainRegistrar ensSubdomainRegistrarBase;
    GlobalExecutor globalExecutor;

    AdminSetup adminSetup;
    MultisigSetup multisigSetup;
    TokenVotingSetup tokenVotingSetup;
    StagedProposalProcessorSetup stagedProposalProcessorSetup;

    ProtocolFactory factory;
    DAOHelper daoHelper;
    PluginRepoHelper pluginRepoHelper;
    PSPHelper pspHelper;
    ENSHelper ensHelper;

    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("OSx version", VERSION);
        console.log("- Deployment wallet:", vm.addr(privKey));
        console.log("- Chain ID:", block.chainid);
        console.log();

        _;

        vm.stopBroadcast();
    }

    function run() public broadcast {
        // Deploy the raw implementation contracts
        deployOSxImplementations();
        deployHelperFactories();

        deployAdminSetup();
        deployMultisigSetup();
        deployTokenVotingSetup();
        deployStagedProposalProcessorSetup();

        // Deploy the factory with immutable parameters and trigger the protocol deployment

        factory = new ProtocolFactory(buildFactoryParams());
        vm.label(address(factory), "ProtocolFactory");
        factory.deployOnce();

        // Done
        printDeployment();

        if (!vm.envOr("SIMULATE", false)) {
            writeJsonAddresses();
        }
    }

    // Internal helpers

    function deployOSxImplementations() internal {
        /// @dev Deploy implementations with empty values. They will be used to create proxies and to verify the source code.
        daoBase = new DAO();
        vm.label(address(daoBase), "DAO Base");

        daoRegistryBase = new DAORegistry();
        vm.label(address(daoRegistryBase), "DAORegistry Base");

        pluginRepoRegistryBase = new PluginRepoRegistry();
        vm.label(address(pluginRepoRegistryBase), "PluginRepoRegistry Base");

        placeholderSetup = new PlaceholderSetup();
        vm.label(address(placeholderSetup), "PlaceholderSetup");

        ensSubdomainRegistrarBase = new ENSSubdomainRegistrar();
        vm.label(address(ensSubdomainRegistrarBase), "ENSSubdomainRegistrar Base");

        globalExecutor = new GlobalExecutor();
        vm.label(address(globalExecutor), "GlobalExecutor");

        /// @dev The DAOFactory, PluginRepoFactory and PluginSetupProcessor are static.
        /// @dev These contracts will be deployed by the DAOHelper, the PluginRepoHelper and the PSPHelper.
    }

    function deployHelperFactories() internal {
        daoHelper = new DAOHelper();
        vm.label(address(daoHelper), "DAOHelper");

        pluginRepoHelper = new PluginRepoHelper();
        vm.label(address(pluginRepoHelper), "PluginRepoHelper");

        pspHelper = new PSPHelper();
        vm.label(address(pspHelper), "PSPHelper");

        ensHelper = new ENSHelper();
        vm.label(address(ensHelper), "ENSHelper");
    }

    function deployAdminSetup() internal {
        adminSetup = new AdminSetup();
        vm.label(address(adminSetup), "AdminSetup");
    }

    function deployMultisigSetup() internal {
        multisigSetup = new MultisigSetup();
        vm.label(address(multisigSetup), "MultisigSetup");
    }

    function deployTokenVotingSetup() internal {
        tokenVotingSetup = new TokenVotingSetup(
            new GovernanceERC20(
                IDAO(address(0)), "", "", GovernanceERC20.MintSettings(new address[](0), new uint256[](0), true)
            ),
            new GovernanceWrappedERC20(IERC20Upgradeable(address(0)), "", "")
        );
        vm.label(address(tokenVotingSetup), "TokenVotingSetup");
    }

    function deployStagedProposalProcessorSetup() internal {
        stagedProposalProcessorSetup = new StagedProposalProcessorSetup();
        vm.label(address(stagedProposalProcessorSetup), "StagedProposalProcessorSetup");
    }

    function readManagementDaoMembers() public view returns (address[] memory result) {
        // JSON list of members
        string memory membersFileName =
            vm.envOr("MANAGEMENT_DAO_MEMBERS_FILE_NAME", DEFAULT_MANAGEMENT_DAO_MEMBERS_FILE_NAME);
        string memory path = string.concat(vm.projectRoot(), "/", membersFileName);
        string memory strJson = vm.readFile(path);

        bool exists = vm.keyExistsJson(strJson, "$.members");
        if (!exists) {
            revert("The file pointed by MANAGEMENT_DAO_MEMBERS_FILE_NAME does not contain any members");
        }

        result = vm.parseJsonAddressArray(strJson, "$.members");

        if (result.length == 0) {
            revert("The file pointed by MANAGEMENT_DAO_MEMBERS_FILE_NAME needs to contain at least one member");
        }
    }

    function buildFactoryParams() internal view returns (ProtocolFactory.DeploymentParameters memory params) {
        params = ProtocolFactory.DeploymentParameters({
            osxImplementations: ProtocolFactory.OSxImplementations({
                daoBase: address(daoBase),
                daoRegistryBase: address(daoRegistryBase),
                pluginRepoRegistryBase: address(pluginRepoRegistryBase),
                placeholderSetup: address(placeholderSetup),
                ensSubdomainRegistrarBase: address(ensSubdomainRegistrarBase),
                globalExecutor: address(globalExecutor)
            }),
            helperFactories: ProtocolFactory.HelperFactories({
                daoHelper: daoHelper,
                pluginRepoHelper: pluginRepoHelper,
                pspHelper: pspHelper,
                ensHelper: ensHelper
            }),
            ensParameters: ProtocolFactory.EnsParameters({
                daoRootDomain: vm.envOr("DAO_ENS_DOMAIN", DEFAULT_DAO_ENS_DOMAIN),
                managementDaoSubdomain: vm.envOr("MANAGEMENT_DAO_SUBDOMAIN", DEFAULT_MANAGEMENT_DAO_SUBDOMAIN),
                pluginSubdomain: vm.envOr("PLUGIN_ENS_SUBDOMAIN", DEFAULT_PLUGIN_ENS_SUBDOMAIN)
            }),
            corePlugins: ProtocolFactory.CorePlugins({
                adminPlugin: ProtocolFactory.CorePlugin({
                    pluginSetup: adminSetup,
                    release: 1,
                    build: 2,
                    releaseMetadataUri: vm.envOr("ADMIN_PLUGIN_RELEASE_METADATA_URI", DEFAULT_ADMIN_RELEASE_METADATA),
                    buildMetadataUri: vm.envOr("ADMIN_PLUGIN_BUILD_METADATA_URI", DEFAULT_ADMIN_BUILD_METADATA),
                    subdomain: vm.envOr("ADMIN_PLUGIN_SUBDOMAIN", string("admin"))
                }),
                multisigPlugin: ProtocolFactory.CorePlugin({
                    pluginSetup: multisigSetup,
                    release: 1,
                    build: 3,
                    releaseMetadataUri: vm.envOr("MULTISIG_PLUGIN_RELEASE_METADATA_URI", DEFAULT_MULTISIG_RELEASE_METADATA),
                    buildMetadataUri: vm.envOr("MULTISIG_PLUGIN_BUILD_METADATA_URI", DEFAULT_MULTISIG_BUILD_METADATA),
                    subdomain: vm.envOr("MULTISIG_PLUGIN_SUBDOMAIN", string("multisig"))
                }),
                tokenVotingPlugin: ProtocolFactory.CorePlugin({
                    pluginSetup: tokenVotingSetup,
                    release: 1,
                    build: 3,
                    releaseMetadataUri: vm.envOr("TOKEN_VOTING_PLUGIN_RELEASE_METADATA_URI", DEFAULT_TOKEN_VOTING_RELEASE_METADATA),
                    buildMetadataUri: vm.envOr("TOKEN_VOTING_PLUGIN_BUILD_METADATA_URI", DEFAULT_TOKEN_VOTING_BUILD_METADATA),
                    subdomain: vm.envOr("TOKEN_VOTING_PLUGIN_SUBDOMAIN", string("token-voting"))
                }),
                stagedProposalProcessorPlugin: ProtocolFactory.CorePlugin({
                    pluginSetup: stagedProposalProcessorSetup,
                    release: 1,
                    build: 1,
                    releaseMetadataUri: vm.envOr(
                        "STAGED_PROPOSAL_PROCESSOR_PLUGIN_RELEASE_METADATA_URI", DEFAULT_SPP_RELEASE_METADATA
                    ),
                    buildMetadataUri: vm.envOr("STAGED_PROPOSAL_PROCESSOR_PLUGIN_BUILD_METADATA_URI", DEFAULT_SPP_BUILD_METADATA),
                    subdomain: vm.envOr("STAGED_PROPOSAL_PROCESSOR_PLUGIN_SUBDOMAIN", string("spp"))
                })
            }),
            managementDao: ProtocolFactory.ManagementDaoParameters({
                metadataUri: vm.envOr("MANAGEMENT_DAO_METADATA_URI", DEFAULT_MANAGEMENT_DAO_METADATA),
                members: readManagementDaoMembers(),
                minApprovals: uint8(vm.envUint("MANAGEMENT_DAO_MIN_APPROVALS"))
            })
        });
    }

    function printDeployment() internal view {
        ProtocolFactory.Deployment memory deployment = factory.getDeployment();

        console.log("General:");
        console.log("- ProtocolFactory:", address(factory));
        console.log();

        console.log("OSx contracts:");
        console.log("- DAOFactory", deployment.daoFactory);
        console.log("- PluginRepoFactory", deployment.pluginRepoFactory);
        console.log("- PluginSetupProcessor", deployment.pluginSetupProcessor);
        console.log();

        console.log("Registries (proxy):");
        console.log("- DAORegistry", deployment.daoRegistry);
        console.log("- PluginRepoRegistry", deployment.pluginRepoRegistry);
        console.log();

        console.log("Protocol helpers:");
        console.log("- Management DAO", deployment.managementDao);
        console.log("- Management DAO multisig", deployment.managementDaoMultisig);
        address[] memory members = readManagementDaoMembers();
        console.log("- Management DAO members");
        for (uint256 i = 0; i < members.length; i++) {
            console.log("  -", members[i]);
        }
        console.log();

        console.log("ENS:");
        console.log("- ENSRegistry", deployment.ensRegistry);
        console.log("- PublicResolver", deployment.publicResolver);
        console.log("- ENSSubdomainRegistrar (DAOs)", deployment.daoSubdomainRegistrar);
        console.log("- ENSSubdomainRegistrar (plugins)", deployment.pluginSubdomainRegistrar);
        console.log();

        console.log("Plugin repositories:");
        console.log("- Admin PluginRepo", deployment.adminPluginRepo);
        console.log("- Multisig PluginRepo", deployment.multisigPluginRepo);
        console.log("- TokenVoting PluginRepo", deployment.tokenVotingPluginRepo);
        console.log("- SPP PluginRepo", deployment.stagedProposalProcessorPluginRepo);
        console.log();

        console.log("Other OSx contracts:");
        console.log("- GlobalExecutor", deployment.globalExecutor);
        console.log("- PlaceholderSetup", deployment.placeholderSetup);
        console.log();
    }

    function writeJsonAddresses() internal {
        ProtocolFactory.Deployment memory deployment = factory.getDeployment();

        string memory osxAddresses = "osxAddresses";
        string memory ensAddresses = "ensAddresses";
        string memory corePluginsAddresses = "corePluginsAddresses";

        // OSx static contracts
        osxAddresses.serialize("daoFactory", deployment.daoFactory);
        osxAddresses.serialize("pluginRepoFactory", deployment.pluginRepoFactory);
        osxAddresses.serialize("pluginSetupProcessor", deployment.pluginSetupProcessor);
        osxAddresses.serialize("globalExecutor", deployment.globalExecutor);
        osxAddresses.serialize("placeholderSetup", deployment.placeholderSetup);

        // OSx proxies
        osxAddresses.serialize("daoRegistry", deployment.daoRegistry);
        osxAddresses.serialize("pluginRepoRegistry", deployment.pluginRepoRegistry);
        osxAddresses.serialize("managementDao", deployment.managementDao);
        osxAddresses = osxAddresses.serialize("managementDaoMultisig", deployment.managementDaoMultisig);

        // ENS
        ensAddresses.serialize("ensRegistry", deployment.ensRegistry);
        ensAddresses.serialize("daoSubdomainRegistrar", deployment.daoSubdomainRegistrar);
        ensAddresses.serialize("pluginSubdomainRegistrar", deployment.pluginSubdomainRegistrar);
        ensAddresses = ensAddresses.serialize("publicResolver", deployment.publicResolver);

        // Plugin Repo's
        corePluginsAddresses.serialize("adminPluginRepo", deployment.adminPluginRepo);
        corePluginsAddresses.serialize("multisigPluginRepo", deployment.multisigPluginRepo);
        corePluginsAddresses.serialize("tokenVotingPluginRepo", deployment.tokenVotingPluginRepo);
        corePluginsAddresses = corePluginsAddresses.serialize(
            "stagedProposalProcessorPluginRepo", deployment.stagedProposalProcessorPluginRepo
        );

        // Store the stringified JSON to the variable, as we won't need the key any longer
        string memory version = "versionObject";
        version.serialize("osx", osxAddresses);
        version.serialize("ens", ensAddresses);
        version.serialize("corePlugins", corePluginsAddresses);
        version = version.serialize("protocolFactory", address(factory));

        string memory networkName = vm.envString("NETWORK_NAME");
        string memory filePath = string.concat(
            vm.projectRoot(), "/artifacts/addresses-", networkName, "-", Strings.toString(block.timestamp), ".json"
        );
        version.write(filePath);

        console.log("Deployment addresses written to", filePath);
    }
}
