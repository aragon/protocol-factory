// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {IPluginSetup} from "@aragon/osx/common/plugin/setup/IPluginSetup.sol";

import {ProtocolFactory} from "../src/ProtocolFactory.sol";
import {AddressBook} from "../script/AddressBook.sol";
import {ProtocolFactoryBuilder} from "./helpers/ProtocolFactoryBuilder.sol";

contract AddressBookHarness is AddressBook {
    function addressBookJson(ProtocolFactory _factory, address _conditionFactory, string memory _network)
        external
        view
        returns (string memory)
    {
        return _addressBookJson(_factory, _conditionFactory, _network);
    }
}

/// @dev The address book written by `Deploy.s.sol` must describe the deployment exactly, in the artifacts-hub
///      `AddressBook` shape (aragon/artifacts-hub `scripts/schema.ts`).
contract AddressBookTest is Test {
    address internal constant CONDITION_FACTORY = address(0xC0FFEE);

    ProtocolFactoryBuilder internal builder;
    ProtocolFactory internal factory;
    ProtocolFactory.Deployment internal d;
    AddressBookHarness internal harness;
    string internal json;

    function setUp() public {
        builder = new ProtocolFactoryBuilder();
        address[] memory members = new address[](3);
        members[0] = makeAddr("alice");
        members[1] = makeAddr("bob");
        members[2] = makeAddr("carol");
        builder.withManagementDaoMembers(members).withManagementDaoMinApprovals(2);
        // A build above 1 makes the factory publish placeholder builds first.
        builder.withAdminPlugin(1, 2, "ipfs://release", "ipfs://build", "admin");

        factory = builder.build();
        while (!factory.deployPhase()) {}
        d = factory.getDeployment();

        harness = new AddressBookHarness();
        json = harness.addressBookJson(factory, CONDITION_FACTORY, "unit-test");
    }

    function test_WhenDescribingTheChain() external view {
        // it should record the chain, the network name and the factory.
        assertEq(vm.parseJsonUint(json, ".chainId"), block.chainid, "chainId");
        assertEq(vm.parseJsonString(json, ".network"), "unit-test", "network");
        assertEq(vm.parseJsonAddress(json, ".deployers.protocolFactory"), address(factory), "factory");
        assertEq(vm.parseJsonAddress(json, ".conditions.factories[0].address"), CONDITION_FACTORY, "condition factory");
        assertTrue(vm.parseJsonBool(json, ".conditions.factories[0].current"), "condition factory current");
    }

    function test_WhenDescribingOSx() external view {
        // it should record one current OSx version with its core contracts and helpers.
        string memory v = ".osx.versions[0]";
        assertEq(vm.parseJsonString(json, string.concat(v, ".protocolVersion")), "1.4.0", "protocolVersion");
        assertTrue(vm.parseJsonBool(json, string.concat(v, ".current")), "current");
        assertEq(
            vm.parseJsonAddress(json, string.concat(v, ".core.daoBase")),
            DAOFactory(d.daoFactory).daoBase(), // the implementation DAOFactory clones (it creates its own)
            "daoBase"
        );
        assertEq(vm.parseJsonAddress(json, string.concat(v, ".core.daoFactory")), d.daoFactory, "daoFactory");
        assertEq(vm.parseJsonAddress(json, string.concat(v, ".core.daoRegistry")), d.daoRegistry, "daoRegistry");
        assertEq(
            vm.parseJsonAddress(json, string.concat(v, ".core.pluginRepoFactory")), d.pluginRepoFactory, "repo factory"
        );
        assertEq(
            vm.parseJsonAddress(json, string.concat(v, ".core.pluginRepoRegistry")),
            d.pluginRepoRegistry,
            "repo registry"
        );
        assertEq(
            vm.parseJsonAddress(json, string.concat(v, ".core.pluginSetupProcessor")), d.pluginSetupProcessor, "psp"
        );
        assertEq(vm.parseJsonAddress(json, string.concat(v, ".helpers.globalExecutor")), d.globalExecutor, "executor");
        assertFalse(vm.keyExistsJson(json, ".osx.versions[1]"), "one version");
    }

    function test_WhenDescribingTheManagementDaoAndEns() external view {
        // it should record the management DAO, its multisig and the ENS stack.
        assertEq(vm.parseJsonAddress(json, ".management.dao"), d.managementDao, "dao");
        assertEq(vm.parseJsonAddress(json, ".management.daoMultisig"), d.managementDaoMultisig, "multisig");
        assertEq(vm.parseJsonAddress(json, ".ens.registry"), d.ensRegistry, "registry");
        assertEq(vm.parseJsonAddress(json, ".ens.daoSubdomainRegistrar"), d.daoSubdomainRegistrar, "dao registrar");
        assertEq(
            vm.parseJsonAddress(json, ".ens.pluginSubdomainRegistrar"), d.pluginSubdomainRegistrar, "plugin registrar"
        );
        assertEq(vm.parseJsonAddress(json, ".ens.publicResolver"), d.publicResolver, "resolver");
    }

    function test_WhenDescribingThePlugins() external view {
        // it should record every plugin repo with its ENS name, maintainer and every published version.
        ProtocolFactory.DeploymentParameters memory p = factory.getParameters();
        _assertPlugin("admin", d.adminPluginRepo, p.corePlugins.adminPlugin.subdomain);
        _assertPlugin("multisig", d.multisigPluginRepo, p.corePlugins.multisigPlugin.subdomain);
        _assertPlugin("token-voting", d.tokenVotingPluginRepo, p.corePlugins.tokenVotingPlugin.subdomain);
        _assertPlugin("spp", d.stagedProposalProcessorPluginRepo, p.corePlugins.stagedProposalProcessorPlugin.subdomain);
        _assertPlugin("lock-to-vote", d.lockToVotePluginRepo, p.corePlugins.lockToVotePlugin.subdomain);
    }

    function test_WhenAPluginHasPlaceholderBuilds() external view {
        // it should flag them, without implementation or current, and mark only the real build as current.
        assertTrue(vm.parseJsonBool(json, ".plugins.admin.versions[0].placeholder"), "build 1 is a placeholder");
        assertEq(vm.parseJsonAddress(json, ".plugins.admin.versions[0].setup"), d.placeholderSetup, "placeholder setup");
        assertFalse(vm.keyExistsJson(json, ".plugins.admin.versions[0].implementation"), "no implementation");
        assertFalse(vm.keyExistsJson(json, ".plugins.admin.versions[0].current"), "never current");
        assertFalse(vm.keyExistsJson(json, ".plugins.admin.versions[1].placeholder"), "build 2 is real");
        assertTrue(vm.parseJsonBool(json, ".plugins.admin.versions[1].current"), "build 2 is current");
    }

    function test_WhenDescribingTokenVoting() external view {
        // it should record the governance token templates of the current setup.
        address setup = PluginRepo(d.tokenVotingPluginRepo).getLatestVersion(1).pluginSetup;
        (, bytes memory erc20) = setup.staticcall(abi.encodeWithSignature("governanceERC20Base()"));
        (, bytes memory wrapped) = setup.staticcall(abi.encodeWithSignature("governanceWrappedERC20Base()"));
        assertEq(
            vm.parseJsonAddress(json, ".plugins.token-voting.other.governanceERC20"),
            abi.decode(erc20, (address)),
            "erc20 template"
        );
        assertEq(
            vm.parseJsonAddress(json, ".plugins.token-voting.other.governanceWrappedERC20"),
            abi.decode(wrapped, (address)),
            "wrapped template"
        );
        assertFalse(vm.keyExistsJson(json, ".plugins.multisig.other"), "only token-voting has templates");
    }

    function _assertPlugin(string memory _slug, address _repo, string memory _subdomain) internal view {
        ProtocolFactory.DeploymentParameters memory p = factory.getParameters();
        string memory key = string.concat(".plugins.", _slug);
        PluginRepo repo = PluginRepo(_repo);
        assertEq(vm.parseJsonAddress(json, string.concat(key, ".repo")), _repo, string.concat(_slug, " repo"));
        assertEq(
            vm.parseJsonString(json, string.concat(key, ".ens")),
            string.concat(_subdomain, ".", p.ensParameters.pluginSubdomain, ".", p.ensParameters.daoRootDomain, ".eth"),
            string.concat(_slug, " ens")
        );
        assertEq(
            vm.parseJsonAddress(json, string.concat(key, ".maintainer")),
            d.managementDao,
            string.concat(_slug, " maintainer")
        );

        uint256 builds = repo.buildCount(1);
        assertGt(builds, 0, "published");
        for (uint256 b = 1; b <= builds; ++b) {
            string memory v = string.concat(key, ".versions[", vm.toString(b - 1), "]");
            address setup = repo.getVersion(PluginRepo.Tag(1, uint16(b))).pluginSetup;
            assertEq(vm.parseJsonUint(json, string.concat(v, ".release")), 1, "release");
            assertEq(vm.parseJsonUint(json, string.concat(v, ".build")), b, "build");
            assertEq(vm.parseJsonAddress(json, string.concat(v, ".setup")), setup, "setup");
            if (setup != d.placeholderSetup && IPluginSetup(setup).implementation() != address(0)) {
                assertEq(
                    vm.parseJsonAddress(json, string.concat(v, ".implementation")),
                    IPluginSetup(setup).implementation(),
                    "implementation"
                );
            }
        }
        assertFalse(
            vm.keyExistsJson(json, string.concat(key, ".versions[", vm.toString(builds), "]")), "every version, once"
        );
        assertTrue(
            vm.parseJsonBool(json, string.concat(key, ".versions[", vm.toString(builds - 1), "].current")),
            "last current"
        );
    }
}
