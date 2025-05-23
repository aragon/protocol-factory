// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {AragonTest} from "./helpers/AragonTest.sol";
import {ProtocolFactoryBuilder} from "./helpers/ProtocolFactoryBuilder.sol";
import {ProtocolFactory} from "../src/ProtocolFactory.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {DummySetup} from "./helpers/DummySetup.sol";

// OSx Imports
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO, Action} from "@aragon/osx/core/dao/DAO.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {DAORegistry} from "@aragon/osx/framework/dao/DAORegistry.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {
    PluginSetupProcessor,
    PluginSetupRef,
    hashHelpers
} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {ENSSubdomainRegistrar} from "@aragon/osx/framework/utils/ens/ENSSubdomainRegistrar.sol";

// ENS Imports
import {ENS} from "@ensdomains/ens-contracts/contracts/registry/ENS.sol";
import {PublicResolver} from "@ensdomains/ens-contracts/contracts/resolvers/PublicResolver.sol";
import {ENSHelper} from "../src/helpers/ENSHelper.sol";

// Plugins
import {Admin} from "@aragon/admin-plugin/Admin.sol";
import {Multisig} from "@aragon/multisig-plugin/Multisig.sol";
import {TokenVoting} from "@aragon/token-voting-plugin/TokenVoting.sol";
import {MajorityVotingBase} from "@aragon/token-voting-plugin/base/MajorityVotingBase.sol";
import {IMajorityVoting} from "@aragon/token-voting-plugin/base/IMajorityVoting.sol";
import {StagedProposalProcessor} from "@aragon/staged-proposal-processor-plugin/StagedProposalProcessor.sol";
import {RuledCondition} from "@aragon/osx-commons-contracts/src/permission/condition/extensions/RuledCondition.sol";

import {AdminSetup} from "@aragon/admin-plugin/AdminSetup.sol";
import {MultisigSetup} from "@aragon/multisig-plugin/MultisigSetup.sol";
import {TokenVotingSetup} from "@aragon/token-voting-plugin/TokenVotingSetup.sol";
import {StagedProposalProcessorSetup} from "@aragon/staged-proposal-processor-plugin/StagedProposalProcessorSetup.sol";
import {GovernanceERC20} from "@aragon/token-voting-plugin/erc20/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/token-voting-plugin/erc20/GovernanceWrappedERC20.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract ProtocolFactoryTest is AragonTest {
    ProtocolFactoryBuilder builder;
    ProtocolFactory factory;
    ProtocolFactory.DeploymentParameters deploymentParams;
    ProtocolFactory.Deployment deployment;

    address[] internal mgmtDaoMembers;

    // Namehashes calculated in setUp for reuse
    bytes32 ethNode;
    bytes32 daoRootNode; // e.g., dao-test.eth
    bytes32 pluginRootNode; // e.g., plugin-test.dao-test.eth
    bytes32 managementDaoNode; // e.g., management-test.dao-test.eth

    function setUp() public {
        builder = new ProtocolFactoryBuilder();

        // Configure some basic params for testing
        mgmtDaoMembers = new address[](3);
        mgmtDaoMembers[0] = alice;
        mgmtDaoMembers[1] = bob;
        mgmtDaoMembers[2] = carol;

        builder.withManagementDaoMembers(mgmtDaoMembers).withManagementDaoMinApprovals(2);

        // Build the factory (deploys factory contract but doesn't call deployOnce yet)
        factory = builder.build();

        deploymentParams = builder.getDeploymentParams();

        // Pre-calculate namehashes based on params
        ethNode = vm.ensNamehash("eth");
        daoRootNode = vm.ensNamehash(string.concat(deploymentParams.ensParameters.daoRootDomain, ".eth"));
        pluginRootNode = vm.ensNamehash(
            string.concat(
                deploymentParams.ensParameters.pluginSubdomain,
                ".",
                deploymentParams.ensParameters.daoRootDomain,
                ".eth"
            )
        );
        managementDaoNode = vm.ensNamehash(
            string.concat(
                deploymentParams.ensParameters.managementDaoSubdomain,
                ".",
                deploymentParams.ensParameters.daoRootDomain,
                ".eth"
            )
        );

        vm.label(address(this), "TestRunner");

        // To avoid issues with clock modes (e.g., block.timestamp == block.number)
        vm.warp(block.timestamp + 1 days);
    }

    function test_WhenDeployingTheProtocolFactory() external {
        // It getParameters should return the exact same parameters as provided to the constructor
        ProtocolFactory.DeploymentParameters memory currentParams = factory.getParameters();

        // Deep comparison
        assertEq(keccak256(abi.encode(currentParams)), keccak256(abi.encode(deploymentParams)));

        // It getDeployment should return empty values (zero addresses)
        deployment = factory.getDeployment();
        assertEq(deployment.daoFactory, address(0));
        assertEq(deployment.pluginRepoFactory, address(0));
        assertEq(deployment.pluginSetupProcessor, address(0));
        assertEq(deployment.globalExecutor, address(0));
        assertEq(deployment.placeholderSetup, address(0));
        assertEq(deployment.daoRegistry, address(0));
        assertEq(deployment.pluginRepoRegistry, address(0));
        assertEq(deployment.managementDao, address(0));
        assertEq(deployment.managementDaoMultisig, address(0));
        assertEq(deployment.ensRegistry, address(0));
        assertEq(deployment.daoSubdomainRegistrar, address(0));
        assertEq(deployment.pluginSubdomainRegistrar, address(0));
        assertEq(deployment.publicResolver, address(0));
        assertEq(deployment.adminPluginRepo, address(0));
        assertEq(deployment.multisigPluginRepo, address(0));
        assertEq(deployment.tokenVotingPluginRepo, address(0));
        assertEq(deployment.stagedProposalProcessorPluginRepo, address(0));
    }

    modifier whenInvokingDeployOnce() {
        _;
    }

    function test_GivenNoPriorDeploymentOnTheFactory() external whenInvokingDeployOnce {
        // It Should emit an event with the factory address
        factory.deployStep1();
        factory.deployStep2();

        vm.expectEmit(true, true, true, true);
        emit ProtocolFactory.ProtocolDeployed(factory);

        // Deploy the protocol
        factory.deployStep3();

        // It The deployment addresses are filled with the new contracts
        deployment = factory.getDeployment();
        assertNotEq(deployment.daoFactory, address(0));
        assertNotEq(deployment.pluginRepoFactory, address(0));
        assertNotEq(deployment.pluginSetupProcessor, address(0));
        assertNotEq(deployment.globalExecutor, address(0)); // Should be the base address provided
        assertNotEq(deployment.placeholderSetup, address(0)); // Should be the base address provided
        assertNotEq(deployment.daoRegistry, address(0));
        assertNotEq(deployment.pluginRepoRegistry, address(0));
        assertNotEq(deployment.managementDao, address(0));
        assertNotEq(deployment.managementDaoMultisig, address(0));
        assertNotEq(deployment.ensRegistry, address(0));
        assertNotEq(deployment.daoSubdomainRegistrar, address(0));
        assertNotEq(deployment.pluginSubdomainRegistrar, address(0));
        assertNotEq(deployment.publicResolver, address(0));
        assertNotEq(deployment.adminPluginRepo, address(0));
        assertNotEq(deployment.multisigPluginRepo, address(0));
        assertNotEq(deployment.tokenVotingPluginRepo, address(0));
        assertNotEq(deployment.stagedProposalProcessorPluginRepo, address(0));

        // Check a few key implementations match the params
        assertEq(deployment.globalExecutor, deploymentParams.osxImplementations.globalExecutor);
        assertEq(deployment.placeholderSetup, deploymentParams.osxImplementations.placeholderSetup);

        // It Parameters should remain immutable after deployOnce is invoked
        ProtocolFactory.DeploymentParameters memory currentParams = factory.getParameters();

        assertEq(keccak256(abi.encode(currentParams)), keccak256(abi.encode(deploymentParams)));

        // It The used ENS setup matches the given parameters
        ENS ens = ENS(deployment.ensRegistry);
        ENSSubdomainRegistrar daoRegistrar = ENSSubdomainRegistrar(deployment.daoSubdomainRegistrar);
        ENSSubdomainRegistrar pluginRegistrar = ENSSubdomainRegistrar(deployment.pluginSubdomainRegistrar);
        IResolver resolver = IResolver(deployment.publicResolver); // Assuming PublicResolver implements this basic func

        // Owner of the registry contract itself is the Management DAO
        assertEq(ens.owner(bytes32(0)), deployment.managementDao, "Registry root owner mismatch");

        // 2. Check Root Domain Ownership
        assertEq(ens.owner(daoRootNode), deployment.managementDao, "DAO root domain owner mismatch");
        assertEq(ens.owner(pluginRootNode), deployment.managementDao, "Plugin root domain owner mismatch");

        // 3. Check DAO Registrar State
        assertEq(address(daoRegistrar.dao()), deployment.managementDao, "DAO Registrar: DAO mismatch");
        assertEq(address(daoRegistrar.ens()), deployment.ensRegistry, "DAO Registrar: ENS mismatch");
        assertEq(daoRegistrar.node(), daoRootNode, "DAO Registrar: Root node mismatch");

        // 4. Check Plugin Registrar State
        assertEq(address(pluginRegistrar.dao()), deployment.managementDao, "Plugin Registrar: DAO mismatch");
        assertEq(address(pluginRegistrar.ens()), deployment.ensRegistry, "Plugin Registrar: ENS mismatch");
        assertEq(pluginRegistrar.node(), pluginRootNode, "Plugin Registrar: Root node mismatch");

        // 5. Check Management DAO ENS Resolution
        assertEq(
            ens.owner(managementDaoNode), deployment.daoSubdomainRegistrar, "Management DAO ENS node owner mismatch"
        );
        assertEq(
            ens.resolver(managementDaoNode), deployment.publicResolver, "Management DAO ENS node resolver mismatch"
        );
        // Check resolution via the resolver itself
        assertEq(
            resolver.addr(managementDaoNode), deployment.managementDao, "Management DAO ENS resolver addr() mismatch"
        );

        // 6. Check Operator Approvals on ENS Registry granted by Management DAO
        // The factory executes actions via the Mgmt DAO to grant these during setup.
        assertTrue(
            ens.isApprovedForAll(deployment.managementDao, deployment.daoSubdomainRegistrar),
            "DAO Registrar not approved operator"
        );
        assertTrue(
            ens.isApprovedForAll(deployment.managementDao, deployment.pluginSubdomainRegistrar),
            "Plugin Registrar not approved operator"
        );
        // Check DAORegistry/PluginRepoRegistry permissions elsewhere if needed

        // 7. Check Implementation Address (optional sanity check)
        address daoRegImpl = _getImplementation(deployment.daoSubdomainRegistrar);
        assertEq(
            daoRegImpl, deploymentParams.osxImplementations.ensSubdomainRegistrarBase, "DAO Registrar Impl mismatch"
        );
        address pluginRegImpl = _getImplementation(deployment.pluginSubdomainRegistrar);
        assertEq(
            pluginRegImpl,
            deploymentParams.osxImplementations.ensSubdomainRegistrarBase,
            "Plugin Registrar Impl mismatch"
        );
    }

    function test_RevertGiven_TheFactoryAlreadyMadeADeployment() external whenInvokingDeployOnce {
        // Do a first deployment
        ProtocolFactory.DeploymentParameters memory params0 = factory.getParameters();
        factory.deployStep1();
        factory.deployStep2();
        factory.deployStep3();

        ProtocolFactory.DeploymentParameters memory params1 = factory.getParameters();
        ProtocolFactory.Deployment memory deployment1 = factory.getDeployment();

        // It Should revert
        vm.expectRevert(ProtocolFactory.AlreadyDeployed.selector);
        factory.deployStep1();
        vm.expectRevert(ProtocolFactory.AlreadyDeployed.selector);
        factory.deployStep2();
        vm.expectRevert(ProtocolFactory.AlreadyDeployed.selector);
        factory.deployStep3();

        // It Parameters should remain unchanged
        ProtocolFactory.DeploymentParameters memory params2 = factory.getParameters();
        assertEq(keccak256(abi.encode(params0)), keccak256(abi.encode(params1)));
        assertEq(keccak256(abi.encode(params1)), keccak256(abi.encode(params2)));

        // It Deployment addresses should remain unchanged
        ProtocolFactory.Deployment memory deployment2 = factory.getDeployment();
        assertEq(keccak256(abi.encode(deployment1)), keccak256(abi.encode(deployment2)));
    }

    function test_RevertGiven_TheManagementDAOMinApprovalsIsTooSmall() external whenInvokingDeployOnce {
        // It Should revert

        builder = new ProtocolFactoryBuilder();

        // One member, two approvals
        mgmtDaoMembers = new address[](1);
        mgmtDaoMembers[0] = alice;
        builder.withManagementDaoMembers(mgmtDaoMembers).withManagementDaoMinApprovals(2);
        factory = builder.build();

        // Fail
        factory.deployStep1();
        factory.deployStep2();
        vm.expectRevert(ProtocolFactory.MemberListIsTooSmall.selector);
        factory.deployStep3();

        // OK
        mgmtDaoMembers = new address[](2);
        mgmtDaoMembers[0] = alice;
        mgmtDaoMembers[1] = bob;
        builder.withManagementDaoMembers(mgmtDaoMembers).withManagementDaoMinApprovals(2);
        factory = builder.build();
    }

    modifier givenAProtocolDeployment() {
        factory.deployStep1();
        factory.deployStep2();
        factory.deployStep3();
        deployment = factory.getDeployment();
        deploymentParams = builder.getDeploymentParams();

        // Ensure deployment actually happened for modifier sanity
        assertNotEq(deployment.daoFactory, address(0));

        _;
    }

    function test_WhenCallingGetParameters() external givenAProtocolDeployment {
        // It Should return the given values

        // 1
        factory = builder.build();
        bytes32 hash1 = keccak256(abi.encode(factory.getParameters()));

        factory = builder.build();
        bytes32 hash2 = keccak256(abi.encode(factory.getParameters()));

        assertEq(hash1, hash2, "Equal input params should produce equal output values");

        // 2
        factory = builder.withDaoRootDomain("dao-1").build();
        hash2 = keccak256(abi.encode(factory.getParameters()));

        assertNotEq(hash1, hash2, "Different input params should produce different values");
        assertEq(factory.getParameters().ensParameters.daoRootDomain, "dao-1", "DAO root domain mismatch");
        hash1 = hash2;

        // 3
        factory = builder.withManagementDaoSubdomain("management-1").build();
        hash2 = keccak256(abi.encode(factory.getParameters()));

        assertNotEq(hash1, hash2, "Different input params should produce different values");
        assertEq(
            factory.getParameters().ensParameters.managementDaoSubdomain,
            "management-1",
            "Management DAO subdomain mismatch"
        );
        hash1 = hash2;

        // 4
        factory = builder.withPluginSubdomain("plugin-1").build();
        hash2 = keccak256(abi.encode(factory.getParameters()));

        assertNotEq(hash1, hash2, "Different input params should produce different values");
        assertEq(factory.getParameters().ensParameters.pluginSubdomain, "plugin-1", "Plugin subdomain mismatch");
        hash1 = hash2;

        // 5
        factory = builder.withAdminPlugin(1, 5, "releaseMeta", "buildMeta", "admin-1").build();
        hash2 = keccak256(abi.encode(factory.getParameters()));

        assertNotEq(hash1, hash2, "Different input params should produce different values");
        assertEq(factory.getParameters().corePlugins.adminPlugin.release, 1, "Admin plugin release mismatch");
        assertEq(factory.getParameters().corePlugins.adminPlugin.build, 5, "Admin plugin build mismatch");
        assertEq(
            factory.getParameters().corePlugins.adminPlugin.releaseMetadataUri,
            "releaseMeta",
            "Admin plugin releaseMetadataUri mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.adminPlugin.buildMetadataUri,
            "buildMeta",
            "Admin plugin buildMetadataUri mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.adminPlugin.subdomain, "admin-1", "Admin plugin subdomain mismatch"
        );
        hash1 = hash2;

        // 6
        factory = builder.withAdminPlugin(2, 10, "releaseMeta-2", "buildMeta-2", "admin-2").build();
        hash2 = keccak256(abi.encode(factory.getParameters()));

        assertNotEq(hash1, hash2, "Different input params should produce different values");
        assertEq(factory.getParameters().corePlugins.adminPlugin.release, 2, "Admin plugin release mismatch");
        assertEq(factory.getParameters().corePlugins.adminPlugin.build, 10, "Admin plugin build mismatch");
        assertEq(
            factory.getParameters().corePlugins.adminPlugin.releaseMetadataUri,
            "releaseMeta-2",
            "Admin plugin releaseMetadataUri mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.adminPlugin.buildMetadataUri,
            "buildMeta-2",
            "Admin plugin buildMetadataUri mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.adminPlugin.subdomain, "admin-2", "Admin plugin subdomain mismatch"
        );
        hash1 = hash2;

        // 7
        factory = builder.withMultisigPlugin(1, 5, "releaseMeta", "buildMeta", "multisig-1").build();
        hash2 = keccak256(abi.encode(factory.getParameters()));

        assertNotEq(hash1, hash2, "Different input params should produce different values");
        assertEq(factory.getParameters().corePlugins.multisigPlugin.release, 1, "Multisig plugin release mismatch");
        assertEq(factory.getParameters().corePlugins.multisigPlugin.build, 5, "Multisig plugin build mismatch");
        assertEq(
            factory.getParameters().corePlugins.multisigPlugin.releaseMetadataUri,
            "releaseMeta",
            "Multisig plugin releaseMetadataUri mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.multisigPlugin.buildMetadataUri,
            "buildMeta",
            "Multisig plugin buildMetadataUri mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.multisigPlugin.subdomain,
            "multisig-1",
            "Multisig plugin subdomain mismatch"
        );
        hash1 = hash2;

        // 8
        factory = builder.withMultisigPlugin(2, 10, "releaseMeta-2", "buildMeta-2", "multisig-2").build();
        hash2 = keccak256(abi.encode(factory.getParameters()));

        assertNotEq(hash1, hash2, "Different input params should produce different values");
        assertEq(factory.getParameters().corePlugins.multisigPlugin.release, 2, "Multisig plugin release mismatch");
        assertEq(factory.getParameters().corePlugins.multisigPlugin.build, 10, "Multisig plugin build mismatch");
        assertEq(
            factory.getParameters().corePlugins.multisigPlugin.releaseMetadataUri,
            "releaseMeta-2",
            "Multisig plugin releaseMetadataUri mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.multisigPlugin.buildMetadataUri,
            "buildMeta-2",
            "Multisig plugin buildMetadataUri mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.multisigPlugin.subdomain,
            "multisig-2",
            "Multisig plugin subdomain mismatch"
        );
        hash1 = hash2;

        // 9
        factory = builder.withTokenVotingPlugin(1, 5, "releaseMeta", "buildMeta", "tokenVoting-1").build();
        hash2 = keccak256(abi.encode(factory.getParameters()));

        assertNotEq(hash1, hash2, "Different input params should produce different values");
        assertEq(
            factory.getParameters().corePlugins.tokenVotingPlugin.release, 1, "TokenVoting plugin release mismatch"
        );
        assertEq(factory.getParameters().corePlugins.tokenVotingPlugin.build, 5, "TokenVoting plugin build mismatch");
        assertEq(
            factory.getParameters().corePlugins.tokenVotingPlugin.releaseMetadataUri,
            "releaseMeta",
            "TokenVoting plugin releaseMetadataUri mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.tokenVotingPlugin.buildMetadataUri,
            "buildMeta",
            "TokenVoting plugin buildMetadataUri mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.tokenVotingPlugin.subdomain,
            "tokenVoting-1",
            "TokenVoting plugin subdomain mismatch"
        );
        hash1 = hash2;

        // 10
        factory = builder.withTokenVotingPlugin(2, 10, "releaseMeta-2", "buildMeta-2", "tokenVoting-2").build();
        hash2 = keccak256(abi.encode(factory.getParameters()));

        assertNotEq(hash1, hash2, "Different input params should produce different values");
        assertEq(
            factory.getParameters().corePlugins.tokenVotingPlugin.release, 2, "TokenVoting plugin release mismatch"
        );
        assertEq(factory.getParameters().corePlugins.tokenVotingPlugin.build, 10, "TokenVoting plugin build mismatch");
        assertEq(
            factory.getParameters().corePlugins.tokenVotingPlugin.releaseMetadataUri,
            "releaseMeta-2",
            "TokenVoting plugin releaseMetadataUri mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.tokenVotingPlugin.buildMetadataUri,
            "buildMeta-2",
            "TokenVoting plugin buildMetadataUri mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.tokenVotingPlugin.subdomain,
            "tokenVoting-2",
            "TokenVoting plugin subdomain mismatch"
        );
        hash1 = hash2;

        // 11
        factory = builder.withStagedProposalProcessorPlugin(
            1, 5, "releaseMeta", "buildMeta", "stagedProposalProcessor-1"
        ).build();
        hash2 = keccak256(abi.encode(factory.getParameters()));

        assertNotEq(hash1, hash2, "Different input params should produce different values");
        assertEq(
            factory.getParameters().corePlugins.stagedProposalProcessorPlugin.release,
            1,
            "StagedProposalProcessor plugin release mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.stagedProposalProcessorPlugin.build,
            5,
            "StagedProposalProcessor plugin build mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.stagedProposalProcessorPlugin.releaseMetadataUri,
            "releaseMeta",
            "StagedProposalProcessor plugin releaseMetadataUri mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.stagedProposalProcessorPlugin.buildMetadataUri,
            "buildMeta",
            "StagedProposalProcessor plugin buildMetadataUri mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.stagedProposalProcessorPlugin.subdomain,
            "stagedProposalProcessor-1",
            "StagedProposalProcessor plugin subdomain mismatch"
        );
        hash1 = hash2;

        // 12
        factory = builder.withStagedProposalProcessorPlugin(
            2, 10, "releaseMeta-2", "buildMeta-2", "stagedProposalProcessor-2"
        ).build();
        hash2 = keccak256(abi.encode(factory.getParameters()));

        assertNotEq(hash1, hash2, "Different input params should produce different values");
        assertEq(
            factory.getParameters().corePlugins.stagedProposalProcessorPlugin.release,
            2,
            "StagedProposalProcessor plugin release mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.stagedProposalProcessorPlugin.build,
            10,
            "StagedProposalProcessor plugin build mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.stagedProposalProcessorPlugin.releaseMetadataUri,
            "releaseMeta-2",
            "StagedProposalProcessor plugin releaseMetadataUri mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.stagedProposalProcessorPlugin.buildMetadataUri,
            "buildMeta-2",
            "StagedProposalProcessor plugin buildMetadataUri mismatch"
        );
        assertEq(
            factory.getParameters().corePlugins.stagedProposalProcessorPlugin.subdomain,
            "stagedProposalProcessor-2",
            "StagedProposalProcessor plugin subdomain mismatch"
        );
        hash1 = hash2;

        // 13
        factory = builder.withManagementDaoMetadataUri("meta-1234").build();
        hash2 = keccak256(abi.encode(factory.getParameters()));

        assertNotEq(hash1, hash2, "Different input params should produce different values");
        assertEq(factory.getParameters().managementDao.metadataUri, "meta-1234", "Management DAO metadataUri mismatch");
        hash1 = hash2;

        // 14
        factory = builder.withManagementDaoMembers(new address[](1)).build();
        hash2 = keccak256(abi.encode(factory.getParameters()));

        assertNotEq(hash1, hash2, "Different input params should produce different values");
        assertEq(factory.getParameters().managementDao.members.length, 1, "Management DAO members list mismatch");
        hash1 = hash2;

        // 15
        factory = builder.withManagementDaoMinApprovals(10).build();
        hash2 = keccak256(abi.encode(factory.getParameters()));

        assertNotEq(hash1, hash2, "Different input params should produce different values");
        assertEq(factory.getParameters().managementDao.minApprovals, 10, "Management DAO minApprovals mismatch");
        hash1 = hash2;
    }

    function test_WhenCallingGetDeployment() external givenAProtocolDeployment {
        // It Should return the right values
        assertEq(
            keccak256(abi.encode(deployment)),
            keccak256(abi.encode(factory.getDeployment())),
            "Deployment addresses mismatch"
        );

        // Sanity checks
        assertNotEq(deployment.daoFactory, address(0));

        assertNotEq(deployment.pluginRepoFactory, address(0));
        assertNotEq(PluginRepoFactory(deployment.pluginRepoFactory).pluginRepoBase(), address(0));

        assertNotEq(deployment.pluginSetupProcessor, address(0));
        assertEq(
            address(PluginSetupProcessor(deployment.pluginSetupProcessor).repoRegistry()), deployment.pluginRepoRegistry
        );
        assertEq(deployment.globalExecutor, deploymentParams.osxImplementations.globalExecutor);
        assertEq(deployment.placeholderSetup, deploymentParams.osxImplementations.placeholderSetup);

        assertNotEq(deployment.daoRegistry, address(0));
        assertEq(address(DAORegistry(deployment.daoRegistry).subdomainRegistrar()), deployment.daoSubdomainRegistrar);
        assertNotEq(deployment.pluginRepoRegistry, address(0));
        assertEq(
            address(PluginRepoRegistry(deployment.pluginRepoRegistry).subdomainRegistrar()),
            deployment.pluginSubdomainRegistrar
        );
        assertNotEq(deployment.managementDao, address(0));
        assertEq(_getImplementation(deployment.managementDao), deploymentParams.osxImplementations.daoBase);
        assertNotEq(deployment.managementDaoMultisig, address(0));

        assertNotEq(deployment.ensRegistry, address(0));
        assertNotEq(deployment.daoSubdomainRegistrar, address(0));
        assertEq(address(ENSSubdomainRegistrar(deployment.daoSubdomainRegistrar).ens()), deployment.ensRegistry);
        assertEq(address(ENSSubdomainRegistrar(deployment.daoSubdomainRegistrar).resolver()), deployment.publicResolver);
        assertNotEq(deployment.pluginSubdomainRegistrar, address(0));
        assertEq(address(ENSSubdomainRegistrar(deployment.pluginSubdomainRegistrar).ens()), deployment.ensRegistry);
        assertEq(
            address(ENSSubdomainRegistrar(deployment.pluginSubdomainRegistrar).resolver()), deployment.publicResolver
        );
        assertNotEq(deployment.publicResolver, address(0));

        assertNotEq(deployment.adminPluginRepo, address(0));
        assertEq(PluginRepo(deployment.adminPluginRepo).latestRelease(), 1);
        assertEq(
            PluginRepo(deployment.adminPluginRepo).getLatestVersion(1).pluginSetup,
            address(deploymentParams.corePlugins.adminPlugin.pluginSetup)
        );
        assertNotEq(deployment.multisigPluginRepo, address(0));
        assertEq(PluginRepo(deployment.multisigPluginRepo).latestRelease(), 1);
        assertEq(
            PluginRepo(deployment.multisigPluginRepo).getLatestVersion(1).pluginSetup,
            address(deploymentParams.corePlugins.multisigPlugin.pluginSetup)
        );
        assertNotEq(deployment.tokenVotingPluginRepo, address(0));
        assertEq(PluginRepo(deployment.tokenVotingPluginRepo).latestRelease(), 1);
        assertEq(
            PluginRepo(deployment.tokenVotingPluginRepo).getLatestVersion(1).pluginSetup,
            address(deploymentParams.corePlugins.tokenVotingPlugin.pluginSetup)
        );
        assertNotEq(deployment.stagedProposalProcessorPluginRepo, address(0));
        assertEq(PluginRepo(deployment.stagedProposalProcessorPluginRepo).latestRelease(), 1);
        assertEq(
            PluginRepo(deployment.stagedProposalProcessorPluginRepo).getLatestVersion(1).pluginSetup,
            address(deploymentParams.corePlugins.stagedProposalProcessorPlugin.pluginSetup)
        );
    }

    function test_WhenUsingTheDAOFactory() external givenAProtocolDeployment {
        DAOFactory daoFactory = DAOFactory(deployment.daoFactory);
        DAORegistry daoRegistry = DAORegistry(deployment.daoRegistry);
        ENS ens = ENS(deployment.ensRegistry);
        IResolver resolver = IResolver(deployment.publicResolver);

        string memory daoSubdomain = "testdao";
        string memory metadataUri = "ipfs://dao-meta";
        DAOFactory.DAOSettings memory daoSettings = DAOFactory.DAOSettings({
            trustedForwarder: address(0),
            daoURI: "ipfs://dao-uri",
            metadata: bytes(metadataUri),
            subdomain: daoSubdomain
        });
        DAOFactory.PluginSettings[] memory plugins = new DAOFactory.PluginSettings[](0);

        // It Should deploy a valid DAO and register it
        (DAO newDao,) = daoFactory.createDao(daoSettings, plugins);
        assertNotEq(address(newDao), address(0), "DAO address is zero");
        assertTrue(daoRegistry.entries(address(newDao)), "DAO not registered in registry");

        // It New DAOs should have the right permissions on themselves
        // By default, DAOFactory grants ROOT to the DAO itself
        assertTrue(
            newDao.hasPermission(address(newDao), address(newDao), newDao.ROOT_PERMISSION_ID(), ""),
            "DAO does not have ROOT on itself"
        );

        // It New DAOs should be resolved from the requested ENS subdomain
        string memory fullDomain =
            string.concat(daoSubdomain, ".", deploymentParams.ensParameters.daoRootDomain, ".eth");
        bytes32 node = vm.ensNamehash(fullDomain);

        assertEq(ens.owner(node), deployment.daoSubdomainRegistrar, "ENS owner mismatch");
        assertEq(ens.resolver(node), deployment.publicResolver, "ENS resolver mismatch");
        assertEq(resolver.addr(node), address(newDao), "Resolver addr mismatch");
    }

    function test_WhenUsingThePluginRepoFactory() external givenAProtocolDeployment {
        PluginRepoFactory repoFactory = PluginRepoFactory(deployment.pluginRepoFactory);
        PluginRepoRegistry repoRegistry = PluginRepoRegistry(deployment.pluginRepoRegistry);
        ENS ens = ENS(deployment.ensRegistry);
        IResolver resolver = IResolver(deployment.publicResolver);

        string memory repoSubdomain = "testplugin";
        address maintainer = alice; // Let Alice be the maintainer

        // It Should deploy a valid PluginRepo and register it
        address newRepoAddress = address(repoFactory.createPluginRepo(repoSubdomain, maintainer));
        assertTrue(newRepoAddress != address(0), "Repo address is zero");
        assertTrue(repoRegistry.entries(newRepoAddress), "Repo not registered in registry");

        PluginRepo newRepo = PluginRepo(newRepoAddress);
        assertTrue(
            newRepo.isGranted(newRepoAddress, maintainer, newRepo.MAINTAINER_PERMISSION_ID(), ""),
            "Maintainer does not have MAINTAINER_PERMISSION on the plugin repo"
        );

        // It The maintainer can publish new versions
        DummySetup dummySetup = new DummySetup();
        vm.prank(maintainer);
        newRepo.createVersion(1, address(dummySetup), bytes("ipfs://build"), bytes("ipfs://release"));
        PluginRepo.Version memory latestVersion = newRepo.getLatestVersion(1);
        assertEq(latestVersion.pluginSetup, address(dummySetup), "Published version mismatch");

        // It The plugin repo should be resolved from the requested ENS subdomain
        string memory fullDomain = string.concat(
            repoSubdomain,
            ".",
            deploymentParams.ensParameters.pluginSubdomain,
            ".",
            deploymentParams.ensParameters.daoRootDomain,
            ".eth"
        );
        bytes32 node = vm.ensNamehash(fullDomain);

        assertEq(ens.owner(node), deployment.pluginSubdomainRegistrar, "ENS owner mismatch");
        assertEq(ens.resolver(node), deployment.publicResolver, "ENS resolver mismatch");
        assertEq(resolver.addr(node), newRepoAddress, "Resolver addr mismatch");
    }

    function test_WhenUsingTheManagementDAO() external givenAProtocolDeployment {
        Multisig multisig = Multisig(deployment.managementDaoMultisig);
        PluginRepo adminRepo = PluginRepo(deployment.adminPluginRepo);

        // It Should have a multisig with the given members and settings
        assertEq(multisig.addresslistLength(), mgmtDaoMembers.length, "Member count mismatch");
        for (uint256 i = 0; i < mgmtDaoMembers.length; i++) {
            assertTrue(multisig.isListed(mgmtDaoMembers[i]), "Member address mismatch");
        }
        (bool onlyListed, uint16 minApprovals) = multisig.multisigSettings();
        assertTrue(onlyListed, "OnlyListed should be true");
        assertEq(minApprovals, uint16(deploymentParams.managementDao.minApprovals), "Min approvals mismatch");

        // It Should be able to publish new core plugin versions (via multisig)
        DummySetup dummySetup = new DummySetup();
        uint8 targetRelease = deploymentParams.corePlugins.adminPlugin.release;
        bytes memory buildMeta = bytes("ipfs://new-admin-build");
        bytes memory releaseMeta = bytes("ipfs://new-admin-release"); // Usually same for build
        bytes memory actionData = abi.encodeCall(
            PluginRepo.createVersion,
            (
                targetRelease, // target release
                address(dummySetup), // new setup implementation
                buildMeta,
                releaseMeta
            )
        );

        Action[] memory actions = new Action[](1);
        actions[0] = Action({to: deployment.adminPluginRepo, value: 0, data: actionData});

        // Move 1 block forward to avoid ProposalCreationForbidden()
        vm.roll(block.number + 1);

        // Create proposal (Alice proposes)
        vm.prank(alice);
        uint256 proposalId = multisig.createProposal(
            bytes("ipfs://prop-new-admin-version"),
            actions,
            0, // startdate
            uint64(block.timestamp + 100), // enddate
            bytes("")
        );
        // Move 1 block forward to avoid missing the snapshot block
        vm.roll(block.number + 1);

        assertTrue(multisig.canApprove(proposalId, alice), "Cannot approve");
        vm.prank(alice);
        multisig.approve(proposalId, false);

        // Approve (Bob approves, reaching minApprovals = 2)
        vm.prank(bob);
        multisig.approve(proposalId, false);

        uint256 buildCountBefore = adminRepo.buildCount(targetRelease);

        // Execute (Carol executes)
        assertTrue(multisig.canExecute(proposalId), "Proposal should be executable");
        vm.prank(carol);
        multisig.execute(proposalId);

        uint256 buildCountAfter = adminRepo.buildCount(targetRelease);
        assertEq(buildCountBefore + 1, buildCountAfter, "Should have increased hte buildCount");

        // Verify new version
        PluginRepo.Version memory latestVersion = adminRepo.getLatestVersion(targetRelease);
        assertEq(latestVersion.pluginSetup, address(dummySetup), "New version setup mismatch");
        assertEq(latestVersion.buildMetadata, buildMeta, "New version build meta mismatch");
    }

    function test_WhenPreparingAnAdminPluginInstallation() external givenAProtocolDeployment {
        DAO targetDao = _createTestDao("dao-with-admin-plugin", deployment);
        PluginSetupProcessor psp = PluginSetupProcessor(deployment.pluginSetupProcessor);
        PluginSetupRef memory pluginSetupRef = PluginSetupRef(
            PluginRepo.Tag(
                deploymentParams.corePlugins.adminPlugin.release, deploymentParams.corePlugins.adminPlugin.build
            ),
            PluginRepo(deployment.adminPluginRepo)
        );
        // Custom prepareInstallation params
        IPlugin.TargetConfig memory targetConfig =
            IPlugin.TargetConfig({target: address(targetDao), operation: IPlugin.Operation.Call});
        bytes memory setupData = abi.encode(bob, targetConfig); // Initial admin and target

        // It should complete normally
        (address pluginAddress, IPluginSetup.PreparedSetupData memory preparedSetupData) = psp.prepareInstallation(
            address(targetDao), PluginSetupProcessor.PrepareInstallationParams(pluginSetupRef, setupData)
        );
        assertNotEq(pluginAddress, address(0));
        assertTrue(pluginAddress.code.length > 0, "No code at plugin address");
        assertEq(preparedSetupData.permissions.length, 3, "Wrong admin permissions");
    }

    function test_WhenApplyingAnAdminPluginInstallation() external givenAProtocolDeployment {
        DAO targetDao = _createTestDao("dao-with-admin-plugin2", deployment);
        PluginSetupRef memory pluginSetupRef = PluginSetupRef(
            PluginRepo.Tag(
                deploymentParams.corePlugins.adminPlugin.release, deploymentParams.corePlugins.adminPlugin.build
            ),
            PluginRepo(deployment.adminPluginRepo)
        );

        // Custom prepareInstallation params
        address initialAdmin = alice; // Let Alice be the admin
        IPlugin.TargetConfig memory targetConfig =
            IPlugin.TargetConfig({target: address(targetDao), operation: IPlugin.Operation.Call});
        bytes memory setupData = abi.encode(initialAdmin, targetConfig); // Initial admin and target

        address pluginAddress = _installPlugin(targetDao, pluginSetupRef, setupData);

        // It should allow the admin to execute on the DAO
        Admin adminPlugin = Admin(pluginAddress);

        string memory newDaoUri = "https://new-uri";
        assertNotEq(targetDao.daoURI(), newDaoUri, "Should not have the new value yet");
        bytes memory executeCalldata = abi.encodeCall(DAO.setDaoURI, (newDaoUri));

        Action[] memory actions = new Action[](1);
        actions[0] = Action({to: address(targetDao), value: 0, data: executeCalldata});

        // Immediately executed
        vm.prank(alice);
        adminPlugin.createProposal("ipfs://proposal-meta", actions, 0, 0, bytes(""));

        // Verify execution
        assertEq(targetDao.daoURI(), newDaoUri, "Execution failed");
    }

    function test_WhenPreparingAMultisigPluginInstallation() external givenAProtocolDeployment {
        DAO targetDao = _createTestDao("dao-with-multisig", deployment);
        PluginSetupProcessor psp = PluginSetupProcessor(deployment.pluginSetupProcessor);
        PluginSetupRef memory pluginSetupRef = PluginSetupRef(
            PluginRepo.Tag(
                deploymentParams.corePlugins.multisigPlugin.release, deploymentParams.corePlugins.multisigPlugin.build
            ),
            PluginRepo(deployment.multisigPluginRepo)
        );
        IPlugin.TargetConfig memory targetConfig =
            IPlugin.TargetConfig({target: address(targetDao), operation: IPlugin.Operation.Call});

        address[] memory members = new address[](3);
        members[0] = bob;
        members[1] = carol;
        members[2] = david;
        bytes memory setupData = abi.encode(
            members,
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 2}),
            targetConfig,
            bytes("") // metadata
        );

        // It should complete normally
        (address pluginAddress, IPluginSetup.PreparedSetupData memory preparedSetupData) = psp.prepareInstallation(
            address(targetDao), PluginSetupProcessor.PrepareInstallationParams(pluginSetupRef, setupData)
        );
        assertNotEq(pluginAddress, address(0));
        assertTrue(pluginAddress.code.length > 0, "No code at plugin address");
        assertEq(preparedSetupData.permissions.length, 6, "Wrong multisig permissions");
    }

    function test_WhenApplyingAMultisigPluginInstallation() external givenAProtocolDeployment {
        DAO targetDao = _createTestDao("dao-with-multisig2", deployment);
        PluginSetupRef memory pluginSetupRef = PluginSetupRef(
            PluginRepo.Tag(
                deploymentParams.corePlugins.multisigPlugin.release, deploymentParams.corePlugins.multisigPlugin.build
            ),
            PluginRepo(deployment.multisigPluginRepo)
        );
        IPlugin.TargetConfig memory targetConfig =
            IPlugin.TargetConfig({target: address(targetDao), operation: IPlugin.Operation.Call});

        address[] memory members = new address[](3);
        members[0] = bob;
        members[1] = carol;
        members[2] = david;
        bytes memory setupData = abi.encode(
            members,
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 2}),
            targetConfig,
            bytes("") // metadata
        );

        address pluginAddress = _installPlugin(targetDao, pluginSetupRef, setupData);
        Multisig multisigPlugin = Multisig(pluginAddress);

        // Allow this script to create proposals on the plugin
        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            to: address(targetDao),
            value: 0,
            data: abi.encodeCall(
                PermissionManager.grant, (pluginAddress, address(this), multisigPlugin.CREATE_PROPOSAL_PERMISSION_ID())
            )
        });
        targetDao.execute(bytes32(0), actions, 0);

        // Try to change the DAO URI via proposal
        string memory newDaoUri = "https://new-uri";
        assertNotEq(targetDao.daoURI(), newDaoUri, "Should not have the new value yet");
        bytes memory executeCalldata = abi.encodeCall(DAO.setDaoURI, (newDaoUri));

        actions[0] = Action({to: address(targetDao), value: 0, data: executeCalldata});

        // Create proposal
        vm.roll(block.number + 1);
        uint256 proposalId = multisigPlugin.createProposal(
            "ipfs://proposal-meta", actions, 0, uint64(block.timestamp + 20000), bytes("")
        );

        // Approve (Bob)
        vm.prank(bob);
        multisigPlugin.approve(proposalId, false);

        // Approve (Carol)
        vm.prank(carol);
        multisigPlugin.approve(proposalId, false);

        // Execute (David)
        assertTrue(multisigPlugin.canExecute(proposalId));
        vm.prank(david);
        multisigPlugin.execute(proposalId);

        // Verify execution
        assertEq(targetDao.daoURI(), newDaoUri, "Execution failed");
    }

    function test_WhenPreparingATokenVotingPluginInstallation() external givenAProtocolDeployment {
        DAO targetDao = _createTestDao("dao-with-token-voting", deployment);
        PluginSetupProcessor psp = PluginSetupProcessor(deployment.pluginSetupProcessor);
        PluginSetupRef memory pluginSetupRef = PluginSetupRef(
            PluginRepo.Tag(
                deploymentParams.corePlugins.tokenVotingPlugin.release,
                deploymentParams.corePlugins.tokenVotingPlugin.build
            ),
            PluginRepo(deployment.tokenVotingPluginRepo)
        );

        // Setup
        TokenVotingSetup.TokenSettings memory tokenSettings =
            TokenVotingSetup.TokenSettings({addr: address(0), name: "Test Token", symbol: "TST"});
        TokenVoting.VotingSettings memory votingSettings = MajorityVotingBase.VotingSettings({
            votingMode: MajorityVotingBase.VotingMode.Standard,
            supportThreshold: 500_000, // 50%
            minParticipation: 100_000, // 10%
            minDuration: 1 days,
            minProposerVotingPower: 1 // Minimal requirement
        });
        IPlugin.TargetConfig memory targetConfig =
            IPlugin.TargetConfig({target: address(targetDao), operation: IPlugin.Operation.Call});
        GovernanceERC20.MintSettings memory mintSettings =
            GovernanceERC20.MintSettings(new address[](0), new uint256[](0), true);

        bytes memory setupData = abi.encode(
            votingSettings,
            tokenSettings,
            mintSettings,
            targetConfig,
            100_000, // minApprovals ratio
            bytes("ipfs://tv-metadata")
        );

        // It should complete normally
        (address pluginAddress, IPluginSetup.PreparedSetupData memory preparedSetupData) = psp.prepareInstallation(
            address(targetDao), PluginSetupProcessor.PrepareInstallationParams(pluginSetupRef, setupData)
        );
        assertNotEq(pluginAddress, address(0));
        assertTrue(pluginAddress.code.length > 0, "No code at plugin address");
        assertEq(preparedSetupData.permissions.length, 7, "Wrong multisig permissions");
    }

    function test_WhenApplyingATokenVotingPluginInstallation() external givenAProtocolDeployment {
        DAO targetDao = _createTestDao("dao-with-token-voting2", deployment);
        PluginSetupRef memory pluginSetupRef = PluginSetupRef(
            PluginRepo.Tag(
                deploymentParams.corePlugins.tokenVotingPlugin.release,
                deploymentParams.corePlugins.tokenVotingPlugin.build
            ),
            PluginRepo(deployment.tokenVotingPluginRepo)
        );

        // Setup
        TokenVotingSetup.TokenSettings memory tokenSettings =
            TokenVotingSetup.TokenSettings({addr: address(0), name: "Test Token", symbol: "TST"});
        TokenVoting.VotingSettings memory votingSettings = MajorityVotingBase.VotingSettings({
            votingMode: MajorityVotingBase.VotingMode.EarlyExecution,
            supportThreshold: 500_000, // 50%
            minParticipation: 100_000, // 10%
            minDuration: 1 days,
            minProposerVotingPower: 1 // Minimal requirement
        });
        IPlugin.TargetConfig memory targetConfig =
            IPlugin.TargetConfig({target: address(targetDao), operation: IPlugin.Operation.Call});

        GovernanceERC20.MintSettings memory mintSettings =
            GovernanceERC20.MintSettings(new address[](2), new uint256[](2), true);
        mintSettings.receivers[0] = alice;
        mintSettings.amounts[0] = 1 ether;
        mintSettings.receivers[1] = bob;
        mintSettings.amounts[1] = 0.1 ether;

        bytes memory setupData = abi.encode(
            votingSettings,
            tokenSettings,
            mintSettings,
            targetConfig,
            100_000, // minApprovals ratio
            bytes("ipfs://tv-metadata")
        );

        address pluginAddress = _installPlugin(targetDao, pluginSetupRef, setupData);
        TokenVoting tokenVotingPlugin = TokenVoting(pluginAddress);

        // Allow this script to create proposals on the plugin
        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            to: address(targetDao),
            value: 0,
            data: abi.encodeCall(
                PermissionManager.grant, (pluginAddress, address(this), tokenVotingPlugin.CREATE_PROPOSAL_PERMISSION_ID())
            )
        });
        targetDao.execute(bytes32(0), actions, 0);

        // Try to change the DAO URI via proposal
        string memory newDaoUri = "https://another-uri";
        assertNotEq(targetDao.daoURI(), newDaoUri, "Should not have the new value yet");
        bytes memory executeCalldata = abi.encodeCall(DAO.setDaoURI, (newDaoUri));

        actions[0] = Action({to: address(targetDao), value: 0, data: executeCalldata});

        // Create proposal
        vm.roll(block.number + 1);
        uint256 proposalId = tokenVotingPlugin.createProposal(
            "ipfs://proposal-meta", actions, 0, uint64(block.timestamp + 86400), bytes("")
        );

        // Approve (Alice)
        vm.prank(alice);
        tokenVotingPlugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

        // Approve (Bob)
        vm.prank(bob);
        tokenVotingPlugin.vote(proposalId, IMajorityVoting.VoteOption.Yes, false);

        // Execute (Carol)
        assertTrue(tokenVotingPlugin.canExecute(proposalId));
        vm.prank(carol);
        tokenVotingPlugin.execute(proposalId);

        // Verify execution
        assertEq(targetDao.daoURI(), newDaoUri, "Execution failed");
    }

    function test_WhenPreparingAnSPPPluginInstallation() external givenAProtocolDeployment {
        DAO targetDao = _createTestDao("spptestdao", deployment);
        PluginSetupProcessor psp = PluginSetupProcessor(deployment.pluginSetupProcessor);

        // SPP setup
        PluginSetupRef memory pluginSetupRef = PluginSetupRef(
            PluginRepo.Tag(
                deploymentParams.corePlugins.stagedProposalProcessorPlugin.release,
                deploymentParams.corePlugins.stagedProposalProcessorPlugin.build
            ),
            PluginRepo(deployment.stagedProposalProcessorPluginRepo)
        );
        StagedProposalProcessor.Body[] memory bodies = new StagedProposalProcessor.Body[](1);
        bodies[0] = StagedProposalProcessor.Body({
            addr: address(this),
            isManual: true,
            tryAdvance: true,
            resultType: StagedProposalProcessor.ResultType.Approval
        });

        StagedProposalProcessor.Stage[] memory stages = new StagedProposalProcessor.Stage[](1);
        stages[0] = StagedProposalProcessor.Stage({
            bodies: bodies,
            maxAdvance: 1000, // uint64
            minAdvance: 0, // uint64
            voteDuration: 0, // uint64
            approvalThreshold: 1,
            vetoThreshold: 1,
            cancelable: false,
            editable: false
        });
        IPlugin.TargetConfig memory targetConfig =
            IPlugin.TargetConfig({target: address(targetDao), operation: IPlugin.Operation.Call});
        bytes memory setupData =
            abi.encode(bytes("ipfs://spp-metadata"), stages, new RuledCondition.Rule[](0), targetConfig);

        // It should complete normally
        (address pluginAddress, IPluginSetup.PreparedSetupData memory preparedSetupData) = psp.prepareInstallation(
            address(targetDao), PluginSetupProcessor.PrepareInstallationParams(pluginSetupRef, setupData)
        );
        assertNotEq(pluginAddress, address(0));
        assertTrue(pluginAddress.code.length > 0, "No code at plugin address");
        assertEq(preparedSetupData.permissions.length, 9, "Wrong multisig permissions");
    }

    function test_WhenApplyingAnSPPPluginInstallation() external givenAProtocolDeployment {
        DAO targetDao = _createTestDao("dao-with-spp2", deployment);

        // SPP setup
        PluginSetupRef memory pluginSetupRef = PluginSetupRef(
            PluginRepo.Tag(
                deploymentParams.corePlugins.stagedProposalProcessorPlugin.release,
                deploymentParams.corePlugins.stagedProposalProcessorPlugin.build
            ),
            PluginRepo(deployment.stagedProposalProcessorPluginRepo)
        );
        StagedProposalProcessor.Body[] memory bodies = new StagedProposalProcessor.Body[](1);

        // Set the address of this script as the "body"
        bodies[0] = StagedProposalProcessor.Body({
            addr: address(this),
            isManual: true,
            tryAdvance: true,
            resultType: StagedProposalProcessor.ResultType.Approval
        });

        StagedProposalProcessor.Stage[] memory stages = new StagedProposalProcessor.Stage[](1);
        stages[0] = StagedProposalProcessor.Stage({
            bodies: bodies,
            maxAdvance: 1000, // uint64
            minAdvance: 0, // uint64
            voteDuration: 0, // uint64
            approvalThreshold: 1,
            vetoThreshold: 1,
            cancelable: false,
            editable: false
        });
        IPlugin.TargetConfig memory targetConfig =
            IPlugin.TargetConfig({target: address(targetDao), operation: IPlugin.Operation.Call});
        bytes memory setupData =
            abi.encode(bytes("ipfs://spp-metadata"), stages, new RuledCondition.Rule[](0), targetConfig);

        address pluginAddress = _installPlugin(targetDao, pluginSetupRef, setupData);
        StagedProposalProcessor sppPlugin = StagedProposalProcessor(pluginAddress);
        vm.label(pluginAddress, "SPP");

        // Allow this script to create proposals on the plugin
        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            to: address(targetDao),
            value: 0,
            data: abi.encodeCall(
                PermissionManager.grant, (pluginAddress, address(this), keccak256("CREATE_PROPOSAL_PERMISSION"))
            )
        });
        targetDao.execute(bytes32(0), actions, 0);

        // Try to change the DAO URI via proposal
        string memory newDaoUri = "https://another-uri";
        assertNotEq(targetDao.daoURI(), newDaoUri, "Should not have the new value yet");
        bytes memory executeCalldata = abi.encodeCall(DAO.setDaoURI, (newDaoUri));
        actions[0] = Action({to: address(targetDao), value: 0, data: executeCalldata});

        // Create proposal
        vm.roll(block.number + 1);
        uint256 proposalId =
            sppPlugin.createProposal("ipfs://proposal-meta", actions, 0, 0, abi.encode(new bytes[][](0)));

        // Report a positive result to make it advance
        sppPlugin.reportProposalResult(proposalId, 0, StagedProposalProcessor.ResultType.Approval, false);

        assertTrue(sppPlugin.canExecute(proposalId));
        sppPlugin.execute(proposalId);

        // Verify execution
        assertEq(targetDao.daoURI(), newDaoUri, "Execution failed");
    }

    function test_WhenCallingHasPermission() external givenAProtocolDeployment {
        // It Returns true on all the permissions that the Management DAO should have on itself
        // It Returns false on all the temporary permissions granted to the factory

        DAO managementDao = DAO(payable(deployment.managementDao));

        // ROOT
        assertTrue(
            managementDao.hasPermission(
                deployment.managementDao, deployment.managementDao, managementDao.ROOT_PERMISSION_ID(), ""
            ),
            "Should have ROOT_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.managementDao, deployment.pluginSetupProcessor, managementDao.ROOT_PERMISSION_ID(), ""
            ),
            "Should not have ROOT_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.managementDao, address(factory), managementDao.ROOT_PERMISSION_ID(), ""
            ),
            "Should not have ROOT_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.managementDao,
                address(this), // Deployer
                managementDao.ROOT_PERMISSION_ID(),
                ""
            ),
            "Should not have ROOT_PERMISSION_ID"
        );

        // EXECUTE
        assertFalse(
            managementDao.hasPermission(
                deployment.managementDao, deployment.managementDao, managementDao.EXECUTE_PERMISSION_ID(), ""
            ),
            "Should not have EXECUTE_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.managementDao, address(factory), managementDao.EXECUTE_PERMISSION_ID(), ""
            ),
            "Should not have EXECUTE_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.managementDao,
                address(this), // Deployer
                managementDao.EXECUTE_PERMISSION_ID(),
                ""
            ),
            "Should not have EXECUTE_PERMISSION_ID"
        );

        // UPGRADE
        assertTrue(
            managementDao.hasPermission(
                deployment.managementDao, deployment.managementDao, managementDao.UPGRADE_DAO_PERMISSION_ID(), ""
            ),
            "Should have UPGRADE_DAO_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.managementDao, address(factory), managementDao.UPGRADE_DAO_PERMISSION_ID(), ""
            ),
            "Should not have UPGRADE_DAO_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.managementDao,
                address(this), // Deployer
                managementDao.UPGRADE_DAO_PERMISSION_ID(),
                ""
            ),
            "Should not have UPGRADE_DAO_PERMISSION_ID"
        );

        // REGISTER_STANDARD_CALLBACK
        assertTrue(
            managementDao.hasPermission(
                deployment.managementDao,
                deployment.managementDao,
                managementDao.REGISTER_STANDARD_CALLBACK_PERMISSION_ID(),
                ""
            ),
            "Should have REGISTER_STANDARD_CALLBACK_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.managementDao, address(factory), managementDao.REGISTER_STANDARD_CALLBACK_PERMISSION_ID(), ""
            ),
            "Should have REGISTER_STANDARD_CALLBACK_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.managementDao,
                address(this), // Deployer
                managementDao.REGISTER_STANDARD_CALLBACK_PERMISSION_ID(),
                ""
            ),
            "Should have REGISTER_STANDARD_CALLBACK_PERMISSION_ID"
        );

        // PSP
        assertFalse(
            managementDao.hasPermission(
                deployment.pluginSetupProcessor,
                address(factory),
                PluginSetupProcessor(deployment.pluginSetupProcessor).APPLY_INSTALLATION_PERMISSION_ID(),
                ""
            ),
            "Should have APPLY_INSTALLATION_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.pluginSetupProcessor,
                address(this), // Deployer
                PluginSetupProcessor(deployment.pluginSetupProcessor).APPLY_INSTALLATION_PERMISSION_ID(),
                ""
            ),
            "Should have APPLY_INSTALLATION_PERMISSION_ID"
        );

        // REGISTRIES

        // REGISTER_DAO_PERMISSION_ID
        assertTrue(
            managementDao.hasPermission(
                deployment.daoRegistry,
                address(deployment.daoFactory),
                DAORegistry(deployment.daoRegistry).REGISTER_DAO_PERMISSION_ID(),
                ""
            ),
            "Should have REGISTER_DAO_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.daoRegistry,
                deployment.managementDao,
                DAORegistry(deployment.daoRegistry).REGISTER_DAO_PERMISSION_ID(),
                ""
            ),
            "Should not have REGISTER_DAO_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.daoRegistry,
                address(factory),
                DAORegistry(deployment.daoRegistry).REGISTER_DAO_PERMISSION_ID(),
                ""
            ),
            "Should not have REGISTER_DAO_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.daoRegistry,
                address(this),
                DAORegistry(deployment.daoRegistry).REGISTER_DAO_PERMISSION_ID(),
                ""
            ),
            "Should not have REGISTER_DAO_PERMISSION_ID"
        );

        // UPGRADE_REGISTRY_PERMISSION_ID
        assertTrue(
            managementDao.hasPermission(
                deployment.daoRegistry,
                deployment.managementDao,
                DAORegistry(deployment.daoRegistry).UPGRADE_REGISTRY_PERMISSION_ID(),
                ""
            ),
            "Should have UPGRADE_REGISTRY_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.daoRegistry,
                address(factory),
                DAORegistry(deployment.daoRegistry).UPGRADE_REGISTRY_PERMISSION_ID(),
                ""
            ),
            "Should not have UPGRADE_REGISTRY_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.daoRegistry,
                address(this),
                DAORegistry(deployment.daoRegistry).UPGRADE_REGISTRY_PERMISSION_ID(),
                ""
            ),
            "Should not have UPGRADE_REGISTRY_PERMISSION_ID"
        );

        // REGISTER_PLUGIN_REPO_PERMISSION_ID
        assertTrue(
            managementDao.hasPermission(
                deployment.pluginRepoRegistry,
                address(deployment.pluginRepoFactory),
                PluginRepoRegistry(deployment.pluginRepoRegistry).REGISTER_PLUGIN_REPO_PERMISSION_ID(),
                ""
            ),
            "Should have REGISTER_PLUGIN_REPO_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.pluginRepoRegistry,
                deployment.managementDao,
                PluginRepoRegistry(deployment.pluginRepoRegistry).REGISTER_PLUGIN_REPO_PERMISSION_ID(),
                ""
            ),
            "Should not have REGISTER_PLUGIN_REPO_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.pluginRepoRegistry,
                address(factory),
                PluginRepoRegistry(deployment.pluginRepoRegistry).REGISTER_PLUGIN_REPO_PERMISSION_ID(),
                ""
            ),
            "Should not have REGISTER_PLUGIN_REPO_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.pluginRepoRegistry,
                address(this),
                PluginRepoRegistry(deployment.pluginRepoRegistry).REGISTER_PLUGIN_REPO_PERMISSION_ID(),
                ""
            ),
            "Should not have REGISTER_PLUGIN_REPO_PERMISSION_ID"
        );

        // UPGRADE_REGISTRY_PERMISSION_ID
        assertTrue(
            managementDao.hasPermission(
                deployment.pluginRepoRegistry,
                deployment.managementDao,
                PluginRepoRegistry(deployment.pluginRepoRegistry).UPGRADE_REGISTRY_PERMISSION_ID(),
                ""
            ),
            "Should have UPGRADE_REGISTRY_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.pluginRepoRegistry,
                address(factory),
                PluginRepoRegistry(deployment.pluginRepoRegistry).UPGRADE_REGISTRY_PERMISSION_ID(),
                ""
            ),
            "Should not have UPGRADE_REGISTRY_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.pluginRepoRegistry,
                address(this),
                PluginRepoRegistry(deployment.pluginRepoRegistry).UPGRADE_REGISTRY_PERMISSION_ID(),
                ""
            ),
            "Should not have UPGRADE_REGISTRY_PERMISSION_ID"
        );

        // ENS

        // REGISTER_ENS_SUBDOMAIN_PERMISSION_ID
        assertTrue(
            managementDao.hasPermission(
                deployment.daoSubdomainRegistrar,
                address(deployment.daoRegistry),
                ENSSubdomainRegistrar(deployment.daoSubdomainRegistrar).REGISTER_ENS_SUBDOMAIN_PERMISSION_ID(),
                ""
            ),
            "Should have REGISTER_ENS_SUBDOMAIN_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.daoSubdomainRegistrar,
                deployment.managementDao,
                ENSSubdomainRegistrar(deployment.daoSubdomainRegistrar).REGISTER_ENS_SUBDOMAIN_PERMISSION_ID(),
                ""
            ),
            "Should not have REGISTER_ENS_SUBDOMAIN_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.daoSubdomainRegistrar,
                address(factory),
                ENSSubdomainRegistrar(deployment.daoSubdomainRegistrar).REGISTER_ENS_SUBDOMAIN_PERMISSION_ID(),
                ""
            ),
            "Should not have REGISTER_ENS_SUBDOMAIN_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.daoSubdomainRegistrar,
                address(this),
                ENSSubdomainRegistrar(deployment.daoSubdomainRegistrar).REGISTER_ENS_SUBDOMAIN_PERMISSION_ID(),
                ""
            ),
            "Should not have REGISTER_ENS_SUBDOMAIN_PERMISSION_ID"
        );

        //
        assertTrue(
            managementDao.hasPermission(
                deployment.pluginSubdomainRegistrar,
                address(deployment.pluginRepoRegistry),
                ENSSubdomainRegistrar(deployment.pluginSubdomainRegistrar).REGISTER_ENS_SUBDOMAIN_PERMISSION_ID(),
                ""
            ),
            "Should have REGISTER_ENS_SUBDOMAIN_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.pluginSubdomainRegistrar,
                deployment.managementDao,
                ENSSubdomainRegistrar(deployment.pluginSubdomainRegistrar).REGISTER_ENS_SUBDOMAIN_PERMISSION_ID(),
                ""
            ),
            "Should not have REGISTER_ENS_SUBDOMAIN_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.pluginSubdomainRegistrar,
                address(factory),
                ENSSubdomainRegistrar(deployment.pluginSubdomainRegistrar).REGISTER_ENS_SUBDOMAIN_PERMISSION_ID(),
                ""
            ),
            "Should not have REGISTER_ENS_SUBDOMAIN_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.pluginSubdomainRegistrar,
                address(this),
                ENSSubdomainRegistrar(deployment.pluginSubdomainRegistrar).REGISTER_ENS_SUBDOMAIN_PERMISSION_ID(),
                ""
            ),
            "Should not have REGISTER_ENS_SUBDOMAIN_PERMISSION_ID"
        );

        // UPGRADE_REGISTRAR_PERMISSION_ID
        assertTrue(
            managementDao.hasPermission(
                deployment.daoSubdomainRegistrar,
                deployment.managementDao,
                ENSSubdomainRegistrar(deployment.daoSubdomainRegistrar).UPGRADE_REGISTRAR_PERMISSION_ID(),
                ""
            ),
            "Should have UPGRADE_REGISTRAR_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.daoSubdomainRegistrar,
                address(factory),
                ENSSubdomainRegistrar(deployment.daoSubdomainRegistrar).UPGRADE_REGISTRAR_PERMISSION_ID(),
                ""
            ),
            "Should not have UPGRADE_REGISTRAR_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.daoSubdomainRegistrar,
                address(this),
                ENSSubdomainRegistrar(deployment.daoSubdomainRegistrar).UPGRADE_REGISTRAR_PERMISSION_ID(),
                ""
            ),
            "Should not have UPGRADE_REGISTRAR_PERMISSION_ID"
        );

        //
        assertTrue(
            managementDao.hasPermission(
                deployment.pluginSubdomainRegistrar,
                deployment.managementDao,
                ENSSubdomainRegistrar(deployment.pluginSubdomainRegistrar).UPGRADE_REGISTRAR_PERMISSION_ID(),
                ""
            ),
            "Should have UPGRADE_REGISTRAR_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.pluginSubdomainRegistrar,
                address(factory),
                ENSSubdomainRegistrar(deployment.pluginSubdomainRegistrar).UPGRADE_REGISTRAR_PERMISSION_ID(),
                ""
            ),
            "Should not have UPGRADE_REGISTRAR_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.pluginSubdomainRegistrar,
                address(this),
                ENSSubdomainRegistrar(deployment.pluginSubdomainRegistrar).UPGRADE_REGISTRAR_PERMISSION_ID(),
                ""
            ),
            "Should not have UPGRADE_REGISTRAR_PERMISSION_ID"
        );

        // PLUGINS

        // ADMIN
        // MAINTAINER_PERMISSION_ID
        assertTrue(
            PluginRepo(deployment.adminPluginRepo).isGranted(
                deployment.adminPluginRepo,
                deployment.managementDao,
                PluginRepo(deployment.adminPluginRepo).MAINTAINER_PERMISSION_ID(),
                ""
            ),
            "Should have MAINTAINER_PERMISSION_ID"
        );
        assertFalse(
            PluginRepo(deployment.adminPluginRepo).isGranted(
                deployment.adminPluginRepo,
                address(factory),
                PluginRepo(deployment.adminPluginRepo).MAINTAINER_PERMISSION_ID(),
                ""
            ),
            "Should not have MAINTAINER_PERMISSION_ID"
        );
        assertFalse(
            PluginRepo(deployment.adminPluginRepo).isGranted(
                deployment.adminPluginRepo,
                address(this),
                PluginRepo(deployment.adminPluginRepo).MAINTAINER_PERMISSION_ID(),
                ""
            ),
            "Should not have MAINTAINER_PERMISSION_ID"
        );
        // UPGRADE_REPO_PERMISSION_ID
        assertTrue(
            PluginRepo(deployment.adminPluginRepo).isGranted(
                deployment.adminPluginRepo,
                deployment.managementDao,
                PluginRepo(deployment.adminPluginRepo).UPGRADE_REPO_PERMISSION_ID(),
                ""
            ),
            "Should have UPGRADE_REPO_PERMISSION_ID"
        );
        assertFalse(
            PluginRepo(deployment.adminPluginRepo).isGranted(
                deployment.adminPluginRepo,
                address(factory),
                PluginRepo(deployment.adminPluginRepo).UPGRADE_REPO_PERMISSION_ID(),
                ""
            ),
            "Should not have UPGRADE_REPO_PERMISSION_ID"
        );
        assertFalse(
            PluginRepo(deployment.adminPluginRepo).isGranted(
                deployment.adminPluginRepo,
                address(this),
                PluginRepo(deployment.adminPluginRepo).UPGRADE_REPO_PERMISSION_ID(),
                ""
            ),
            "Should not have UPGRADE_REPO_PERMISSION_ID"
        );

        // MULTISIG
        // MAINTAINER_PERMISSION_ID
        assertTrue(
            PluginRepo(deployment.multisigPluginRepo).isGranted(
                deployment.multisigPluginRepo,
                deployment.managementDao,
                PluginRepo(deployment.multisigPluginRepo).MAINTAINER_PERMISSION_ID(),
                ""
            ),
            "Should have MAINTAINER_PERMISSION_ID"
        );
        assertFalse(
            PluginRepo(deployment.multisigPluginRepo).isGranted(
                deployment.multisigPluginRepo,
                address(factory),
                PluginRepo(deployment.multisigPluginRepo).MAINTAINER_PERMISSION_ID(),
                ""
            ),
            "Should not have MAINTAINER_PERMISSION_ID"
        );
        assertFalse(
            PluginRepo(deployment.multisigPluginRepo).isGranted(
                deployment.multisigPluginRepo,
                address(this),
                PluginRepo(deployment.multisigPluginRepo).MAINTAINER_PERMISSION_ID(),
                ""
            ),
            "Should not have MAINTAINER_PERMISSION_ID"
        );
        // UPGRADE_REPO_PERMISSION_ID
        assertTrue(
            PluginRepo(deployment.multisigPluginRepo).isGranted(
                deployment.multisigPluginRepo,
                deployment.managementDao,
                PluginRepo(deployment.multisigPluginRepo).UPGRADE_REPO_PERMISSION_ID(),
                ""
            ),
            "Should have UPGRADE_REPO_PERMISSION_ID"
        );
        assertFalse(
            PluginRepo(deployment.multisigPluginRepo).isGranted(
                deployment.multisigPluginRepo,
                address(factory),
                PluginRepo(deployment.multisigPluginRepo).UPGRADE_REPO_PERMISSION_ID(),
                ""
            ),
            "Should not have UPGRADE_REPO_PERMISSION_ID"
        );
        assertFalse(
            PluginRepo(deployment.multisigPluginRepo).isGranted(
                deployment.multisigPluginRepo,
                address(this),
                PluginRepo(deployment.multisigPluginRepo).UPGRADE_REPO_PERMISSION_ID(),
                ""
            ),
            "Should not have UPGRADE_REPO_PERMISSION_ID"
        );

        // TOKEN VOTING
        // MAINTAINER_PERMISSION_ID
        assertTrue(
            PluginRepo(deployment.tokenVotingPluginRepo).isGranted(
                deployment.tokenVotingPluginRepo,
                deployment.managementDao,
                PluginRepo(deployment.tokenVotingPluginRepo).MAINTAINER_PERMISSION_ID(),
                ""
            ),
            "Should have MAINTAINER_PERMISSION_ID"
        );
        assertFalse(
            PluginRepo(deployment.tokenVotingPluginRepo).isGranted(
                deployment.tokenVotingPluginRepo,
                address(factory),
                PluginRepo(deployment.tokenVotingPluginRepo).MAINTAINER_PERMISSION_ID(),
                ""
            ),
            "Should not have MAINTAINER_PERMISSION_ID"
        );
        assertFalse(
            PluginRepo(deployment.tokenVotingPluginRepo).isGranted(
                deployment.tokenVotingPluginRepo,
                address(this),
                PluginRepo(deployment.tokenVotingPluginRepo).MAINTAINER_PERMISSION_ID(),
                ""
            ),
            "Should not have MAINTAINER_PERMISSION_ID"
        );
        // UPGRADE_REPO_PERMISSION_ID
        assertTrue(
            PluginRepo(deployment.tokenVotingPluginRepo).isGranted(
                deployment.tokenVotingPluginRepo,
                deployment.managementDao,
                PluginRepo(deployment.tokenVotingPluginRepo).UPGRADE_REPO_PERMISSION_ID(),
                ""
            ),
            "Should have UPGRADE_REPO_PERMISSION_ID"
        );
        assertFalse(
            PluginRepo(deployment.tokenVotingPluginRepo).isGranted(
                deployment.tokenVotingPluginRepo,
                address(factory),
                PluginRepo(deployment.tokenVotingPluginRepo).UPGRADE_REPO_PERMISSION_ID(),
                ""
            ),
            "Should not have UPGRADE_REPO_PERMISSION_ID"
        );
        assertFalse(
            PluginRepo(deployment.tokenVotingPluginRepo).isGranted(
                deployment.tokenVotingPluginRepo,
                address(this),
                PluginRepo(deployment.tokenVotingPluginRepo).UPGRADE_REPO_PERMISSION_ID(),
                ""
            ),
            "Should not have UPGRADE_REPO_PERMISSION_ID"
        );

        // SPP
        // MAINTAINER_PERMISSION_ID
        assertTrue(
            PluginRepo(deployment.stagedProposalProcessorPluginRepo).isGranted(
                deployment.stagedProposalProcessorPluginRepo,
                deployment.managementDao,
                PluginRepo(deployment.stagedProposalProcessorPluginRepo).MAINTAINER_PERMISSION_ID(),
                ""
            ),
            "Should have MAINTAINER_PERMISSION_ID"
        );
        assertFalse(
            PluginRepo(deployment.stagedProposalProcessorPluginRepo).isGranted(
                deployment.stagedProposalProcessorPluginRepo,
                address(factory),
                PluginRepo(deployment.stagedProposalProcessorPluginRepo).MAINTAINER_PERMISSION_ID(),
                ""
            ),
            "Should not have MAINTAINER_PERMISSION_ID"
        );
        assertFalse(
            PluginRepo(deployment.stagedProposalProcessorPluginRepo).isGranted(
                deployment.stagedProposalProcessorPluginRepo,
                address(this),
                PluginRepo(deployment.stagedProposalProcessorPluginRepo).MAINTAINER_PERMISSION_ID(),
                ""
            ),
            "Should not have MAINTAINER_PERMISSION_ID"
        );
        // UPGRADE_REPO_PERMISSION_ID
        assertTrue(
            PluginRepo(deployment.stagedProposalProcessorPluginRepo).isGranted(
                deployment.stagedProposalProcessorPluginRepo,
                deployment.managementDao,
                PluginRepo(deployment.stagedProposalProcessorPluginRepo).UPGRADE_REPO_PERMISSION_ID(),
                ""
            ),
            "Should have UPGRADE_REPO_PERMISSION_ID"
        );
        assertFalse(
            PluginRepo(deployment.stagedProposalProcessorPluginRepo).isGranted(
                deployment.stagedProposalProcessorPluginRepo,
                address(factory),
                PluginRepo(deployment.stagedProposalProcessorPluginRepo).UPGRADE_REPO_PERMISSION_ID(),
                ""
            ),
            "Should not have UPGRADE_REPO_PERMISSION_ID"
        );
        assertFalse(
            PluginRepo(deployment.stagedProposalProcessorPluginRepo).isGranted(
                deployment.stagedProposalProcessorPluginRepo,
                address(this),
                PluginRepo(deployment.stagedProposalProcessorPluginRepo).UPGRADE_REPO_PERMISSION_ID(),
                ""
            ),
            "Should not have UPGRADE_REPO_PERMISSION_ID"
        );
    }

    function test_WhenUpgradingTheProtocol() external givenAProtocolDeployment {
        // It The new protocol contracts point to the new implementations
        // It The upgrade proposal succeeds

        DAO managementDao = DAO(payable(deployment.managementDao));
        Multisig multisig = Multisig(deployment.managementDaoMultisig);
        PluginRepo adminRepo = PluginRepo(deployment.adminPluginRepo);
        PluginRepo multisigRepo = PluginRepo(deployment.multisigPluginRepo);
        PluginRepo tokenVotingRepo = PluginRepo(deployment.tokenVotingPluginRepo);
        PluginRepo sppRepo = PluginRepo(deployment.stagedProposalProcessorPluginRepo);

        // 1) NEW PLUGIN VERSIONS
        Action[] memory actions = new Action[](8);

        address newAdminSetup = address(new AdminSetup());
        actions[0] = Action({
            to: deployment.adminPluginRepo,
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
            to: deployment.multisigPluginRepo,
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
                    IDAO(address(0)), "", "", GovernanceERC20.MintSettings(new address[](0), new uint256[](0), true)
                ),
                new GovernanceWrappedERC20(IERC20Upgradeable(address(0)), "", "")
            )
        );
        actions[2] = Action({
            to: deployment.tokenVotingPluginRepo,
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
            to: deployment.stagedProposalProcessorPluginRepo,
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

        DAOFactory newDaoFactory =
            new DAOFactory(DAORegistry(deployment.daoRegistry), PluginSetupProcessor(deployment.pluginSetupProcessor));
        PluginRepoFactory newPluginRepoFactory =
            new PluginRepoFactory(PluginRepoRegistry(deployment.pluginRepoRegistry));

        // Move the REGISTER_DAO_PERMISSION_ID permission on the DAORegistry from the old DAOFactory to the new one
        PermissionLib.MultiTargetPermission[] memory newPermissions = new PermissionLib.MultiTargetPermission[](4);
        newPermissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: deployment.daoRegistry,
            who: deployment.daoFactory,
            condition: address(0),
            permissionId: keccak256("REGISTER_DAO_PERMISSION")
        });
        newPermissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: deployment.daoRegistry,
            who: address(newDaoFactory),
            condition: address(0),
            permissionId: keccak256("REGISTER_DAO_PERMISSION")
        });

        // Move the REGISTER_PLUGIN_REPO_PERMISSION_ID permission on the PluginRepoRegistry from the old PluginRepoFactory to the new PluginRepoFactory
        newPermissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: deployment.pluginRepoRegistry,
            who: deployment.pluginRepoFactory,
            condition: address(0),
            permissionId: keccak256("REGISTER_PLUGIN_REPO_PERMISSION")
        });
        newPermissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: deployment.pluginRepoRegistry,
            who: address(newPluginRepoFactory),
            condition: address(0),
            permissionId: keccak256("REGISTER_PLUGIN_REPO_PERMISSION")
        });
        actions[4] = Action({
            to: deployment.managementDao,
            value: 0,
            data: abi.encodeCall(PermissionManager.applyMultiTargetPermissions, (newPermissions))
        });

        // 3) REGISTRY IMPLEMENTATIONS

        // Upgrade the DaoRegistry to the new implementation
        address newDaoRegistryBase = address(new DAORegistry());
        actions[5] = Action({
            to: deployment.daoRegistry,
            value: 0,
            data: abi.encodeCall(UUPSUpgradeable.upgradeTo, (newDaoRegistryBase))
        });
        // Upgrade the PluginRepoRegistry to the new implementation
        address newPluginRepoRegistryBase = address(new PluginRepoRegistry());
        actions[6] = Action({
            to: deployment.pluginRepoRegistry,
            value: 0,
            data: abi.encodeCall(UUPSUpgradeable.upgradeTo, (newPluginRepoRegistryBase))
        });

        // 4) MANAGING DAO IMPLEMENTATION

        // Upgrade the management DAO to a new implementation
        address newDaoBase = address(payable(new DAO()));
        actions[7] = Action({
            to: deployment.managementDao,
            value: 0,
            data: abi.encodeCall(UUPSUpgradeable.upgradeTo, (newDaoBase))
        });

        // Before (plugin setup's)
        assertNotEq(adminRepo.getLatestVersion(1).pluginSetup, newAdminSetup, "Should not be the new version");
        assertNotEq(multisigRepo.getLatestVersion(1).pluginSetup, newMultisigSetup, "Should not be the new version");
        assertNotEq(
            tokenVotingRepo.getLatestVersion(1).pluginSetup, newTokenVotingSetup, "Should not be the new version"
        );
        assertNotEq(sppRepo.getLatestVersion(1).pluginSetup, newSppSetup, "Should not be the new version");

        // Before (registry permissions)
        assertTrue(
            managementDao.hasPermission(
                deployment.daoRegistry,
                deployment.daoFactory,
                DAORegistry(deployment.daoRegistry).REGISTER_DAO_PERMISSION_ID(),
                ""
            ),
            "Should have REGISTER_DAO_PERMISSION_ID"
        );
        assertTrue(
            managementDao.hasPermission(
                deployment.pluginRepoRegistry,
                deployment.pluginRepoFactory,
                PluginRepoRegistry(deployment.pluginRepoRegistry).REGISTER_PLUGIN_REPO_PERMISSION_ID(),
                ""
            ),
            "Should have REGISTER_PLUGIN_REPO_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.daoRegistry,
                address(newDaoFactory),
                DAORegistry(deployment.daoRegistry).REGISTER_DAO_PERMISSION_ID(),
                ""
            ),
            "Should not have REGISTER_DAO_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.pluginRepoRegistry,
                address(newPluginRepoFactory),
                PluginRepoRegistry(deployment.pluginRepoRegistry).REGISTER_PLUGIN_REPO_PERMISSION_ID(),
                ""
            ),
            "Should not have REGISTER_PLUGIN_REPO_PERMISSION_ID"
        );

        // Before (registry implementations)
        assertNotEq(
            _getImplementation(deployment.daoRegistry), newDaoRegistryBase, "Should not have the new implementation"
        );
        assertNotEq(
            _getImplementation(deployment.pluginRepoRegistry),
            newPluginRepoRegistryBase,
            "Should not have the new implementation"
        );

        // Before (Management DAO implementation)
        assertNotEq(_getImplementation(deployment.managementDao), newDaoBase, "Should not have the new implementation");

        // PROPOSAL
        // 1 block forward for the multisig settings to be effective
        vm.roll(block.number + 1);

        vm.prank(alice);
        uint256 proposalId = multisig.createProposal(
            bytes("ipfs://prop-new-mgmt-dao-impl"),
            actions,
            0, // startdate
            uint64(block.timestamp + 100), // enddate
            bytes("")
        );
        // Move 1 block forward to avoid missing the snapshot block
        vm.roll(block.number + 1);

        vm.prank(alice);
        multisig.approve(proposalId, false);
        vm.prank(bob);
        multisig.approve(proposalId, false);
        vm.prank(carol);
        multisig.execute(proposalId);

        // After (plugin setup's)
        assertEq(adminRepo.getLatestVersion(1).pluginSetup, newAdminSetup, "Should be the new version");
        assertEq(multisigRepo.getLatestVersion(1).pluginSetup, newMultisigSetup, "Should be the new version");
        assertEq(tokenVotingRepo.getLatestVersion(1).pluginSetup, newTokenVotingSetup, "Should be the new version");
        assertEq(sppRepo.getLatestVersion(1).pluginSetup, newSppSetup, "Should be the new version");

        // After (registry permissions)
        assertFalse(
            managementDao.hasPermission(
                deployment.daoRegistry,
                deployment.daoFactory,
                DAORegistry(deployment.daoRegistry).REGISTER_DAO_PERMISSION_ID(),
                ""
            ),
            "Should not have REGISTER_DAO_PERMISSION_ID"
        );
        assertFalse(
            managementDao.hasPermission(
                deployment.pluginRepoRegistry,
                deployment.pluginRepoFactory,
                PluginRepoRegistry(deployment.pluginRepoRegistry).REGISTER_PLUGIN_REPO_PERMISSION_ID(),
                ""
            ),
            "Should not have REGISTER_PLUGIN_REPO_PERMISSION_ID"
        );
        assertTrue(
            managementDao.hasPermission(
                deployment.daoRegistry,
                address(newDaoFactory),
                DAORegistry(deployment.daoRegistry).REGISTER_DAO_PERMISSION_ID(),
                ""
            ),
            "Should have REGISTER_DAO_PERMISSION_ID"
        );
        assertTrue(
            managementDao.hasPermission(
                deployment.pluginRepoRegistry,
                address(newPluginRepoFactory),
                PluginRepoRegistry(deployment.pluginRepoRegistry).REGISTER_PLUGIN_REPO_PERMISSION_ID(),
                ""
            ),
            "Should have REGISTER_PLUGIN_REPO_PERMISSION_ID"
        );

        // After (registry implementations)
        assertEq(_getImplementation(deployment.daoRegistry), newDaoRegistryBase, "Should have the new implementation");
        assertEq(
            _getImplementation(deployment.pluginRepoRegistry),
            newPluginRepoRegistryBase,
            "Should have the new implementation"
        );

        // After (Management DAO implementation)
        assertEq(_getImplementation(deployment.managementDao), newDaoBase, "Should have the new implementation");

        // 5) CREATING A NEW DAO
        // END TO END: Replicating from test_WhenUsingTheDAOFactory above

        // Use the new factory
        DAORegistry daoRegistry = DAORegistry(deployment.daoRegistry);
        ENS ens = ENS(deployment.ensRegistry);
        IResolver resolver = IResolver(deployment.publicResolver);

        string memory daoSubdomain = "testdao";
        string memory metadataUri = "ipfs://dao-meta";
        DAOFactory.DAOSettings memory daoSettings = DAOFactory.DAOSettings({
            trustedForwarder: address(0),
            daoURI: "ipfs://dao-uri",
            metadata: bytes(metadataUri),
            subdomain: daoSubdomain
        });
        DAOFactory.PluginSettings[] memory plugins = new DAOFactory.PluginSettings[](0);

        // It Should deploy a valid DAO and register it
        (DAO newDao,) = newDaoFactory.createDao(daoSettings, plugins);
        assertNotEq(address(newDao), address(0), "DAO address is zero");
        assertTrue(daoRegistry.entries(address(newDao)), "DAO not registered in registry");

        // It New DAOs should have the right permissions on themselves
        // By default, DAOFactory grants ROOT to the DAO itself
        assertTrue(
            newDao.hasPermission(address(newDao), address(newDao), newDao.ROOT_PERMISSION_ID(), ""),
            "DAO does not have ROOT on itself"
        );

        // It New DAOs should be resolved from the requested ENS subdomain
        string memory fullDomain =
            string.concat(daoSubdomain, ".", deploymentParams.ensParameters.daoRootDomain, ".eth");
        bytes32 node = vm.ensNamehash(fullDomain);

        assertEq(ens.owner(node), deployment.daoSubdomainRegistrar, "ENS owner mismatch");
        assertEq(ens.resolver(node), deployment.publicResolver, "ENS resolver mismatch");
        assertEq(resolver.addr(node), address(newDao), "Resolver addr mismatch");

        // 6) CREATING A NEW PLUGIN
        // END TO END: Replicating from test_WhenUsingThePluginRepoFactory above

        PluginRepoRegistry repoRegistry = PluginRepoRegistry(deployment.pluginRepoRegistry);

        string memory repoSubdomain = "testplugin";
        address maintainer = alice; // Let Alice be the maintainer

        // It Should deploy a valid PluginRepo and register it
        address newRepoAddress = address(newPluginRepoFactory.createPluginRepo(repoSubdomain, maintainer));
        assertTrue(newRepoAddress != address(0), "Repo address is zero");
        assertTrue(repoRegistry.entries(newRepoAddress), "Repo not registered in registry");

        PluginRepo newRepo = PluginRepo(newRepoAddress);
        assertTrue(
            newRepo.isGranted(newRepoAddress, maintainer, newRepo.MAINTAINER_PERMISSION_ID(), ""),
            "Maintainer does not have MAINTAINER_PERMISSION on the plugin repo"
        );

        // It The maintainer can publish new versions
        DummySetup dummySetup = new DummySetup();
        vm.prank(maintainer);
        newRepo.createVersion(1, address(dummySetup), bytes("ipfs://build"), bytes("ipfs://release"));
        PluginRepo.Version memory latestVersion = newRepo.getLatestVersion(1);
        assertEq(latestVersion.pluginSetup, address(dummySetup), "Published version mismatch");

        // It The plugin repo should be resolved from the requested ENS subdomain
        fullDomain = string.concat(
            repoSubdomain,
            ".",
            deploymentParams.ensParameters.pluginSubdomain,
            ".",
            deploymentParams.ensParameters.daoRootDomain,
            ".eth"
        );
        node = vm.ensNamehash(fullDomain);

        assertEq(ens.owner(node), deployment.pluginSubdomainRegistrar, "ENS owner mismatch");
        assertEq(ens.resolver(node), deployment.publicResolver, "ENS resolver mismatch");
        assertEq(resolver.addr(node), newRepoAddress, "Resolver addr mismatch");

        // 7) USING A NEW DAO WITH AN UPDATED PLUGIN
        // END TO END: Replicating from test_WhenApplyingAMultisigPluginInstallation above

        // Overriding the deployment addresses with the new factories
        deployment.daoFactory = address(newDaoFactory);
        deployment.pluginRepoFactory = address(newPluginRepoFactory);

        DAO targetDao = _createTestDao("dao-with-multisig", deployment);
        PluginSetupRef memory pluginSetupRef = PluginSetupRef(
            PluginRepo.Tag(
                deploymentParams.corePlugins.multisigPlugin.release,
                deploymentParams.corePlugins.multisigPlugin.build + 1 // new version
            ),
            PluginRepo(deployment.multisigPluginRepo)
        );
        IPlugin.TargetConfig memory targetConfig =
            IPlugin.TargetConfig({target: address(targetDao), operation: IPlugin.Operation.Call});

        address[] memory members = new address[](3);
        members[0] = bob;
        members[1] = carol;
        members[2] = david;
        bytes memory setupData = abi.encode(
            members,
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 2}),
            targetConfig,
            bytes("") // metadata
        );

        address pluginAddress = _installPlugin(targetDao, pluginSetupRef, setupData);
        Multisig multisigPlugin = Multisig(pluginAddress);

        // Allow this script to create proposals on the plugin
        actions = new Action[](1);
        actions[0] = Action({
            to: address(targetDao),
            value: 0,
            data: abi.encodeCall(
                PermissionManager.grant, (pluginAddress, address(this), multisigPlugin.CREATE_PROPOSAL_PERMISSION_ID())
            )
        });
        targetDao.execute(bytes32(0), actions, 0);

        // Try to change the DAO URI via proposal
        string memory newDaoUri = "https://new-uri";
        assertNotEq(targetDao.daoURI(), newDaoUri, "Should not have the new value yet");
        bytes memory executeCalldata = abi.encodeCall(DAO.setDaoURI, (newDaoUri));

        actions[0] = Action({to: address(targetDao), value: 0, data: executeCalldata});

        // Create proposal
        vm.roll(block.number + 1);
        proposalId = multisigPlugin.createProposal(
            "ipfs://proposal-meta", actions, 0, uint64(block.timestamp + 20000), bytes("")
        );

        vm.prank(bob);
        multisigPlugin.approve(proposalId, false);
        vm.prank(carol);
        multisigPlugin.approve(proposalId, false);
        assertTrue(multisigPlugin.canExecute(proposalId));
        vm.prank(david);
        multisigPlugin.execute(proposalId);

        // Verify execution
        assertEq(targetDao.daoURI(), newDaoUri, "Execution failed");
    }

    // Helpers

    function _getImplementation(address proxy) private view returns (address) {
        return address(
            uint160(
                uint256(
                    vm.load(proxy, bytes32(uint256(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc)))
                )
            )
        );
    }

    // Helper to create a test DAO for plugin installations
    function _createTestDao(string memory subdomain, ProtocolFactory.Deployment memory _deployment)
        internal
        returns (DAO)
    {
        DAOFactory daoFactory = DAOFactory(_deployment.daoFactory);

        DAOFactory.DAOSettings memory daoSettings = DAOFactory.DAOSettings({
            trustedForwarder: address(0),
            daoURI: "ipfs://dao-uri",
            metadata: bytes("ipfs://test-dao-meta"),
            subdomain: subdomain
        });

        (DAO newDao,) = daoFactory.createDao(daoSettings, new DAOFactory.PluginSettings[](0));
        vm.label(address(newDao), "TestDAO");
        return newDao;
    }

    // Helper to prepare and apply plugin installation
    function _installPlugin(DAO _targetDao, PluginSetupRef memory _pluginSetupRef, bytes memory _setupData)
        internal
        returns (address pluginAddress)
    {
        PluginSetupProcessor psp = PluginSetupProcessor(deployment.pluginSetupProcessor);

        // Prepare
        (address _pluginAddress, IPluginSetup.PreparedSetupData memory preparedSetupData) = psp.prepareInstallation(
            address(_targetDao), PluginSetupProcessor.PrepareInstallationParams(_pluginSetupRef, _setupData)
        );
        pluginAddress = _pluginAddress; // Store the result
        vm.label(pluginAddress, "TestPlugin");

        // Grant temporary permissions for applying
        Action[] memory actions = new Action[](2);
        actions[0] = Action({
            to: address(_targetDao),
            value: 0,
            data: abi.encodeCall(
                PermissionManager.grant, (address(_targetDao), address(psp), _targetDao.ROOT_PERMISSION_ID())
            )
        });
        actions[1] = Action({
            to: address(_targetDao),
            value: 0,
            data: abi.encodeCall(
                PermissionManager.grant,
                (
                    address(psp),
                    address(this), // Test contract applies
                    psp.APPLY_INSTALLATION_PERMISSION_ID()
                )
            )
        });
        _targetDao.execute(bytes32(0), actions, 0);

        // Apply
        psp.applyInstallation(
            address(_targetDao),
            PluginSetupProcessor.ApplyInstallationParams(
                _pluginSetupRef, pluginAddress, preparedSetupData.permissions, hashHelpers(preparedSetupData.helpers)
            )
        );
    }
}

interface IResolver {
    function addr(bytes32 node) external view returns (address);
}
