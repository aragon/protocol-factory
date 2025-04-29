// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {IDAOHelper, IPluginRepoHelper, IPSPHelper, IENSHelper} from "./helpers/interfaces.sol";

import {DAO, Action} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {DAORegistry} from "@aragon/osx/framework/dao/DAORegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {
    PluginSetupProcessor,
    PluginSetupRef,
    hashHelpers
} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";

import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {Multisig} from "@aragon/multisig-plugin/Multisig.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ENS} from "@ensdomains/ens-contracts/contracts/registry/ENS.sol";
import {ENSSubdomainRegistrar} from "@aragon/osx/framework/utils/ens/ENSSubdomainRegistrar.sol";

/// @notice This contract orchestrates the full protocol deployment, including the Managing DAO, OSx and Aragon's core plugins.
/// @dev Given that deploying the factory with all contracts embedded would hit the gas limit, the deployment has two stages:
/// @dev 1) Deploy the raw contracts and store their addresses locally
/// @dev 2) Deploy the factory with the addresses above and tell it to orchestrate the protocol deployment (this file)
contract ProtocolFactory {
    /// @notice The struct containing all the parameters to deploy the protocol
    struct DeploymentParameters {
        // OSx
        OSxImplementations osxImplementations;
        // Helper factories
        HelperFactories helperFactories;
        // ENS
        EnsParameters ensParameters;
        // Plugins
        CorePlugins corePlugins;
        // Management DAO
        ManagementDaoParameters managementDao;
    }

    /// @notice The struct containing the implementation addresses for OSx
    struct OSxImplementations {
        address daoBase;
        address daoRegistryBase;
        address pluginRepoRegistryBase;
        address placeholderSetup;
        address ensSubdomainRegistrarBase;
        address globalExecutor;
    }

    /// @notice The struct containing the addresses of the auxiliary factories
    struct HelperFactories {
        IDAOHelper daoHelper;
        IPluginRepoHelper pluginRepoHelper;
        IPSPHelper pspHelper;
        IENSHelper ensHelper;
    }

    /// @notice The struct containing the ENS related parameters
    struct EnsParameters {
        /// @notice The root domain to use for DAO's on the DaoRegistry (example: "dao" => dao.eth)
        string daoRootDomain;
        /// @notice The subdomain to use for the Management DAO (example: "management" => management.dao.eth)
        string managementDaoSubdomain;
        /// @notice The subdomain name to use for the PluginRepoRegistry (example: "plugin" => plugin.dao.eth)
        string pluginSubdomain;
    }

    /// @notice Encapsulates the parameters for each core plugin
    struct CorePlugin {
        IPluginSetup pluginSetup;
        uint8 release;
        uint8 build;
        string releaseMetadataUri;
        string buildMetadataUri;
        string subdomain;
    }

    /// @notice The struct containing the deployed plugin setup's for the Aragon core plugins
    struct CorePlugins {
        CorePlugin adminPlugin;
        CorePlugin multisigPlugin;
        CorePlugin tokenVotingPlugin;
        CorePlugin stagedProposalProcessorPlugin;
    }

    /// @notice A struct with the voting settings and metadata of the Management DAO
    struct ManagementDaoParameters {
        string metadataUri;
        address[] members;
        uint8 minApprovals;
    }

    /// @notice The struct containing the deployed protocol addresses
    struct Deployment {
        // OSx static contracts
        address daoFactory;
        address pluginRepoFactory;
        address pluginSetupProcessor;
        address globalExecutor;
        address placeholderSetup;
        // OSx proxies
        address daoRegistry;
        address pluginRepoRegistry;
        address managementDao;
        address managementDaoMultisig;
        // ENS
        address ensRegistry;
        address daoSubdomainRegistrar;
        address pluginSubdomainRegistrar;
        address publicResolver;
        // Plugin Repo's
        address adminPluginRepo;
        address multisigPluginRepo;
        address tokenVotingPluginRepo;
        address stagedProposalProcessorPluginRepo;
    }

    /// @notice Emitted when deployOnce() has been called and the deployment is complete.
    /// @param factory The address of the factory contract where the parameters and addresses can be retrieved.
    event ProtocolDeployed(ProtocolFactory factory);

    /// @notice Thrown when attempting to call deployOnce() when the protocol is already deployed.
    error AlreadyDeployed();

    /// @notice Thrown when the Management DAO has less members than minApprovals
    error MemberListIsTooSmall();

    DeploymentParameters private parameters;
    Deployment private deployment;

    /// @notice Initializes the factory and performs the full deployment. Values become read-only after that.
    /// @param _parameters The parameters of the one-time deployment.
    constructor(DeploymentParameters memory _parameters) {
        parameters = _parameters;
    }

    function deployOnce() external {
        if (address(deployment.daoFactory) != address(0)) {
            revert AlreadyDeployed();
        }

        // Create the DAO that will own the registries and the core plugin repo's
        prepareRawManagementDao();

        // Set up the ENS registry and the requested domains
        prepareEnsRegistry();

        // Deploy the OSx core contracts
        prepareOSx();

        preparePermissions();

        // Prepare the plugin repo's and their versions
        prepareCorePluginRepos();

        // Drop the factory's permissions on the management DAO
        concludeManagementDao();
        removePermissions();

        emit ProtocolDeployed(this);
    }

    /// @notice Returns the parameters used by the factory to deploy the protocol
    function getParameters() external view returns (DeploymentParameters memory) {
        return parameters;
    }

    /// @notice Returns the addresses of the OSx contracts as well as the the core plugins
    function getDeployment() external view returns (Deployment memory) {
        return deployment;
    }

    // Internal helpers

    function prepareRawManagementDao() internal {
        DAO managementDao = DAO(
            payable(
                createProxyAndCall(
                    parameters.osxImplementations.daoBase,
                    abi.encodeCall(
                        DAO.initialize,
                        (
                            bytes(parameters.managementDao.metadataUri), // Metadata URI
                            address(this), // initialOwner
                            address(0), // Trusted forwarder
                            "" // DAO URI
                        )
                    )
                )
            )
        );
        deployment.managementDao = address(managementDao);

        // Grant the DAO the required permissions on itself

        // Available:
        // - ROOT_PERMISSION
        // - UPGRADE_DAO_PERMISSION
        // - REGISTER_STANDARD_CALLBACK_PERMISSION
        // - SET_SIGNATURE_VALIDATOR_PERMISSION      [skipped]
        // - SET_TRUSTED_FORWARDER_PERMISSION        [skipped]
        // - SET_METADATA_PERMISSION                 [skipped]

        PermissionLib.SingleTargetPermission[] memory items = new PermissionLib.SingleTargetPermission[](3);
        items[0] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant, deployment.managementDao, managementDao.ROOT_PERMISSION_ID()
        );
        items[1] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant, deployment.managementDao, managementDao.UPGRADE_DAO_PERMISSION_ID()
        );
        items[2] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant,
            deployment.managementDao,
            managementDao.REGISTER_STANDARD_CALLBACK_PERMISSION_ID()
        );

        managementDao.applySingleTargetPermissions(deployment.managementDao, items);

        // Grant the factory execute permission on the Management DAO
        managementDao.grant(deployment.managementDao, address(this), managementDao.EXECUTE_PERMISSION_ID());
    }

    function prepareEnsRegistry() internal {
        bytes32 DAO_ETH_NODE;
        bytes32 PLUGIN_DAO_ETH_NODE;

        // Set up an ENS environment
        (deployment.ensRegistry, deployment.publicResolver, DAO_ETH_NODE, PLUGIN_DAO_ETH_NODE) = parameters
            .helperFactories
            .ensHelper
            .deployStatic(
            address(deployment.managementDao), // ENSRegistry owner
            bytes(parameters.ensParameters.daoRootDomain),
            bytes(parameters.ensParameters.pluginSubdomain)
        );

        // Deploy the dao.eth ENSSubdomainRegistrar
        deployment.daoSubdomainRegistrar = createProxyAndCall(
            parameters.osxImplementations.ensSubdomainRegistrarBase,
            abi.encodeCall(
                ENSSubdomainRegistrar.initialize,
                (IDAO(deployment.managementDao), ENS(deployment.ensRegistry), DAO_ETH_NODE)
            )
        );

        // Deploy the plugin.dao.eth ENSSubdomainRegistrar
        deployment.pluginSubdomainRegistrar = createProxyAndCall(
            parameters.osxImplementations.ensSubdomainRegistrarBase,
            abi.encodeCall(
                ENSSubdomainRegistrar.initialize,
                (IDAO(deployment.managementDao), ENS(deployment.ensRegistry), PLUGIN_DAO_ETH_NODE)
            )
        );

        // Allow the registrars to register subdomains

        /// @dev Registrars need to be set as the "operator" by the effective owner (the Management DAO).
        /// @dev Doing it from the factory wouldn't work.

        Action[] memory actions = new Action[](2);
        actions[0].to = deployment.ensRegistry;
        actions[0].data = abi.encodeCall(ENS.setApprovalForAll, (deployment.daoSubdomainRegistrar, true));
        actions[1].to = deployment.ensRegistry;
        actions[1].data = abi.encodeCall(ENS.setApprovalForAll, (deployment.pluginSubdomainRegistrar, true));

        DAO(payable(deployment.managementDao)).execute(bytes32(0), actions, 0);
    }

    function prepareOSx() internal {
        // Deploy the DAORegistry proxy
        deployment.daoRegistry = createProxyAndCall(
            parameters.osxImplementations.daoRegistryBase,
            abi.encodeCall(
                DAORegistry.initialize,
                (IDAO(deployment.managementDao), ENSSubdomainRegistrar(deployment.daoSubdomainRegistrar))
            )
        );

        // Deploy PluginRepoRegistry proxy
        deployment.pluginRepoRegistry = createProxyAndCall(
            parameters.osxImplementations.pluginRepoRegistryBase,
            abi.encodeCall(
                PluginRepoRegistry.initialize,
                (IDAO(deployment.managementDao), ENSSubdomainRegistrar(deployment.pluginSubdomainRegistrar))
            )
        );

        // Static contract deployments
        /// @dev Offloaded to separate factories to avoid hitting code size limits.

        deployment.pluginSetupProcessor =
            parameters.helperFactories.pspHelper.deployStatic(deployment.pluginRepoRegistry);
        deployment.daoFactory =
            parameters.helperFactories.daoHelper.deployFactory(deployment.daoRegistry, deployment.pluginSetupProcessor);
        deployment.pluginRepoFactory =
            parameters.helperFactories.pluginRepoHelper.deployFactory(deployment.pluginRepoRegistry);

        // Store the plain implementation addresses

        deployment.globalExecutor = parameters.osxImplementations.globalExecutor;
        deployment.placeholderSetup = parameters.osxImplementations.placeholderSetup;
    }

    function preparePermissions() internal {
        DAO managementDao = DAO(payable(deployment.managementDao));

        // ENS registrar permissions

        // Allow to register subdomains
        managementDao.grant(
            deployment.daoSubdomainRegistrar,
            deployment.daoRegistry,
            ENSSubdomainRegistrar(deployment.daoSubdomainRegistrar).REGISTER_ENS_SUBDOMAIN_PERMISSION_ID()
        );
        managementDao.grant(
            deployment.pluginSubdomainRegistrar,
            deployment.pluginRepoRegistry,
            ENSSubdomainRegistrar(deployment.pluginSubdomainRegistrar).REGISTER_ENS_SUBDOMAIN_PERMISSION_ID()
        );

        // Allow to perform upgrades
        managementDao.grant(
            deployment.daoSubdomainRegistrar,
            deployment.managementDao,
            ENSSubdomainRegistrar(deployment.daoSubdomainRegistrar).UPGRADE_REGISTRAR_PERMISSION_ID()
        );
        managementDao.grant(
            deployment.pluginSubdomainRegistrar,
            deployment.managementDao,
            ENSSubdomainRegistrar(deployment.pluginSubdomainRegistrar).UPGRADE_REGISTRAR_PERMISSION_ID()
        );

        // DAORegistry permissions

        // Register DAO's
        managementDao.grant(
            deployment.daoRegistry,
            deployment.daoFactory,
            DAORegistry(deployment.daoRegistry).REGISTER_DAO_PERMISSION_ID()
        );
        // Upgrade the implementation
        managementDao.grant(
            deployment.daoRegistry,
            deployment.managementDao,
            DAORegistry(deployment.daoRegistry).UPGRADE_REGISTRY_PERMISSION_ID()
        );

        // PluginRepoRegistry permissions

        // Register plugins
        managementDao.grant(
            deployment.pluginRepoRegistry,
            deployment.pluginRepoFactory,
            PluginRepoRegistry(deployment.pluginRepoRegistry).REGISTER_PLUGIN_REPO_PERMISSION_ID()
        );
        // Upgrade the implementation
        managementDao.grant(
            deployment.pluginRepoRegistry,
            deployment.managementDao,
            PluginRepoRegistry(deployment.pluginRepoRegistry).UPGRADE_REGISTRY_PERMISSION_ID()
        );
    }

    function prepareCorePluginRepos() internal {
        deployment.adminPluginRepo = preparePluginRepo(parameters.corePlugins.adminPlugin);
        deployment.multisigPluginRepo = preparePluginRepo(parameters.corePlugins.multisigPlugin);
        deployment.tokenVotingPluginRepo = preparePluginRepo(parameters.corePlugins.tokenVotingPlugin);
        deployment.stagedProposalProcessorPluginRepo =
            preparePluginRepo(parameters.corePlugins.stagedProposalProcessorPlugin);
    }

    function preparePluginRepo(CorePlugin memory corePlugin) internal returns (address pluginRepo) {
        // Make it owned by the Management DAO upfront
        pluginRepo = address(
            PluginRepoFactory(deployment.pluginRepoFactory).createPluginRepo(
                corePlugin.subdomain, deployment.managementDao
            )
        );

        // Make the Management DAO publish the initial version(s)

        Action[] memory actions = new Action[](1);
        actions[0].to = pluginRepo;

        // Publish a placeholder on older builds
        if (corePlugin.build > 1) {
            actions[0].data = abi.encodeCall(
                PluginRepo.createVersion,
                (
                    corePlugin.release,
                    address(parameters.osxImplementations.placeholderSetup),
                    bytes(corePlugin.buildMetadataUri),
                    bytes(corePlugin.releaseMetadataUri)
                )
            );

            for (uint256 i = 1; i < corePlugin.build; i++) {
                DAO(payable(deployment.managementDao)).execute(bytes32(0), actions, 0);
            }
        }

        // The actual plugin setup
        actions[0].data = abi.encodeCall(
            PluginRepo.createVersion,
            (
                corePlugin.release,
                address(corePlugin.pluginSetup),
                bytes(corePlugin.buildMetadataUri),
                bytes(corePlugin.releaseMetadataUri)
            )
        );

        DAO(payable(deployment.managementDao)).execute(bytes32(0), actions, 0);
    }

    function concludeManagementDao() internal {
        DAO managementDao = DAO(payable(deployment.managementDao));

        // Grant temporary permissions for the factory to register the Management DAO
        managementDao.grant(
            deployment.daoRegistry, address(this), DAORegistry(deployment.daoRegistry).REGISTER_DAO_PERMISSION_ID()
        );

        // Register the ManagementDAO on the DaoRegistry
        DAORegistry(deployment.daoRegistry).register(
            managementDao, address(this), parameters.ensParameters.managementDaoSubdomain
        );

        // Revoke the temporary permission
        managementDao.revoke(
            deployment.daoRegistry, address(this), DAORegistry(deployment.daoRegistry).REGISTER_DAO_PERMISSION_ID()
        );

        // Management DAO Multisig Plugin

        // Check the members length
        if (parameters.managementDao.members.length < parameters.managementDao.minApprovals) {
            revert MemberListIsTooSmall();
        }

        // Prepare the installation
        bytes memory setupData = abi.encode(
            parameters.managementDao.members,
            Multisig.MultisigSettings({onlyListed: true, minApprovals: parameters.managementDao.minApprovals}),
            IPlugin.TargetConfig({target: deployment.managementDao, operation: IPlugin.Operation.Call}),
            bytes("") // metadata
        );

        PluginSetupRef memory pluginSetupRef = PluginSetupRef(
            PluginRepo.Tag(parameters.corePlugins.multisigPlugin.release, parameters.corePlugins.multisigPlugin.build),
            PluginRepo(deployment.multisigPluginRepo)
        );
        IPluginSetup.PreparedSetupData memory preparedSetupData;
        (deployment.managementDaoMultisig, preparedSetupData) = PluginSetupProcessor(deployment.pluginSetupProcessor)
            .prepareInstallation(
            deployment.managementDao, PluginSetupProcessor.PrepareInstallationParams(pluginSetupRef, setupData)
        );

        // Grant temporary permissions to apply the installation
        managementDao.grant(address(managementDao), deployment.pluginSetupProcessor, managementDao.ROOT_PERMISSION_ID());
        managementDao.grant(
            deployment.pluginSetupProcessor,
            address(this),
            PluginSetupProcessor(deployment.pluginSetupProcessor).APPLY_INSTALLATION_PERMISSION_ID()
        );

        // Install the plugin
        PluginSetupProcessor(deployment.pluginSetupProcessor).applyInstallation(
            address(managementDao),
            PluginSetupProcessor.ApplyInstallationParams(
                pluginSetupRef,
                deployment.managementDaoMultisig,
                preparedSetupData.permissions,
                hashHelpers(preparedSetupData.helpers)
            )
        );

        // Remove the temporary permissions
        managementDao.revoke(
            address(managementDao), deployment.pluginSetupProcessor, managementDao.ROOT_PERMISSION_ID()
        );
        managementDao.revoke(
            deployment.pluginSetupProcessor,
            address(this),
            PluginSetupProcessor(deployment.pluginSetupProcessor).APPLY_INSTALLATION_PERMISSION_ID()
        );
    }

    function removePermissions() internal {
        // Remove the execute permission from the factory
        DAO(payable(deployment.managementDao)).revoke(
            deployment.managementDao, // where
            address(this), // who
            DAO(payable(deployment.managementDao)).EXECUTE_PERMISSION_ID() // permission
        );
        // Remove the ROOT permission from the factory
        DAO(payable(deployment.managementDao)).revoke(
            deployment.managementDao, // where
            address(this), // who
            DAO(payable(deployment.managementDao)).ROOT_PERMISSION_ID() // permission
        );
    }

    function createProxyAndCall(address _logic, bytes memory _data) internal returns (address) {
        return address(new ERC1967Proxy(_logic, _data));
    }
}
