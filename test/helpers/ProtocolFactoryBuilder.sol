// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAORegistry} from "@aragon/osx/framework/dao/DAORegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PlaceholderSetup} from "@aragon/osx/framework/plugin/repo/placeholder/PlaceholderSetup.sol";
import {ENSSubdomainRegistrar} from "@aragon/osx/framework/utils/ens/ENSSubdomainRegistrar.sol";
import {Executor as GlobalExecutor} from "@aragon/osx-commons-contracts/src/executors/Executor.sol";

import {ProtocolFactory} from "../../src/ProtocolFactory.sol";
import {DAOHelper} from "../../src/helpers/DAOHelper.sol";
import {PluginRepoHelper} from "../../src/helpers/PluginRepoHelper.sol";
import {PSPHelper} from "../../src/helpers/PSPHelper.sol";
import {ENSHelper} from "../../src/helpers/ENSHelper.sol";

import {AdminSetup} from "@aragon/admin-plugin/AdminSetup.sol";
import {MultisigSetup} from "@aragon/multisig-plugin/MultisigSetup.sol";
import {TokenVotingSetup} from "@aragon/token-voting-plugin/TokenVotingSetup.sol";
import {GovernanceERC20} from "@aragon/token-voting-plugin/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/token-voting-plugin/ERC20/governance/GovernanceWrappedERC20.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {StagedProposalProcessorSetup} from "@aragon/staged-proposal-processor-plugin/StagedProposalProcessorSetup.sol";

import {ALICE_ADDRESS, RANDOM_ADDRESS} from "../constants.sol";

contract ProtocolFactoryBuilder is Test {
    ProtocolFactory factory;

    string daoRootDomain = "dao-test";
    string managementDaoSubdomain = "management-test";
    string pluginSubdomain = "plugin-test";

    ProtocolFactory.CorePlugin adminPlugin =
        ProtocolFactory.CorePlugin({
            pluginSetup: new AdminSetup(),
            release: 1,
            build: 2,
            releaseMetadataUri: "admin-release-metadata",
            buildMetadataUri: "admin-build-metadata",
            subdomain: "admin-test"
        });
    ProtocolFactory.CorePlugin multisigPlugin =
        ProtocolFactory.CorePlugin({
            pluginSetup: new AdminSetup(),
            release: 1,
            build: 3,
            releaseMetadataUri: "multisig-release-metadata",
            buildMetadataUri: "multisig-build-metadata",
            subdomain: "multisig-test"
        });
    ProtocolFactory.CorePlugin tokenVotingPlugin =
        ProtocolFactory.CorePlugin({
            pluginSetup: new AdminSetup(),
            release: 1,
            build: 3,
            releaseMetadataUri: "token-voting-release-metadata",
            buildMetadataUri: "token-voting-build-metadata",
            subdomain: "token-voting-test"
        });
    ProtocolFactory.CorePlugin stagedProposalProcessorPlugin =
        ProtocolFactory.CorePlugin({
            pluginSetup: new AdminSetup(),
            release: 1,
            build: 1,
            releaseMetadataUri: "spp-release-metadata",
            buildMetadataUri: "spp-build-metadata",
            subdomain: "spp-test"
        });

    ProtocolFactory.ManagementDaoParameters managementDaoParams =
        ProtocolFactory.ManagementDaoParameters({
            metadataUri: "ipfs://mgmt-dao-metadata",
            members: new address[](0),
            minApprovals: 3
        });

    // SETTERS

    function withDaoRootDomain(
        string memory _domain
    ) public returns (ProtocolFactoryBuilder) {
        daoRootDomain = _domain;
        return this;
    }

    function withManagementDaoSubdomain(
        string memory _domain
    ) public returns (ProtocolFactoryBuilder) {
        managementDaoSubdomain = _domain;
        return this;
    }

    function withPluginsubdomain(
        string memory _domain
    ) public returns (ProtocolFactoryBuilder) {
        pluginSubdomain = _domain;
        return this;
    }

    function withAdminPlugin(
        uint8 _release,
        uint8 _build,
        string memory _releaseMetadataUri,
        string memory _buildMetadataUri,
        string memory _subdomain
    ) public returns (ProtocolFactoryBuilder) {
        adminPlugin = ProtocolFactory.CorePlugin({
            pluginSetup: new AdminSetup(),
            release: _release,
            build: _build,
            releaseMetadataUri: _releaseMetadataUri,
            buildMetadataUri: _buildMetadataUri,
            subdomain: _subdomain
        });
        return this;
    }

    function withMultisigPlugin(
        uint8 _release,
        uint8 _build,
        string memory _releaseMetadataUri,
        string memory _buildMetadataUri,
        string memory _subdomain
    ) public returns (ProtocolFactoryBuilder) {
        multisigPlugin = ProtocolFactory.CorePlugin({
            pluginSetup: new MultisigSetup(),
            release: _release,
            build: _build,
            releaseMetadataUri: _releaseMetadataUri,
            buildMetadataUri: _buildMetadataUri,
            subdomain: _subdomain
        });
        return this;
    }

    function withTokenVotingPlugin(
        uint8 _release,
        uint8 _build,
        string memory _releaseMetadataUri,
        string memory _buildMetadataUri,
        string memory _subdomain
    ) public returns (ProtocolFactoryBuilder) {
        tokenVotingPlugin = ProtocolFactory.CorePlugin({
            pluginSetup: new TokenVotingSetup(
                new GovernanceERC20(
                    IDAO(address(0)),
                    "",
                    "",
                    GovernanceERC20.MintSettings(
                        new address[](0),
                        new uint256[](0)
                    )
                ),
                new GovernanceWrappedERC20(
                    IERC20Upgradeable(address(0)),
                    "",
                    ""
                )
            ),
            release: _release,
            build: _build,
            releaseMetadataUri: _releaseMetadataUri,
            buildMetadataUri: _buildMetadataUri,
            subdomain: _subdomain
        });
        return this;
    }

    function withStagedProposalProcessorPlugin(
        uint8 _release,
        uint8 _build,
        string memory _releaseMetadataUri,
        string memory _buildMetadataUri,
        string memory _subdomain
    ) public returns (ProtocolFactoryBuilder) {
        stagedProposalProcessorPlugin = ProtocolFactory.CorePlugin({
            pluginSetup: new StagedProposalProcessorSetup(),
            release: _release,
            build: _build,
            releaseMetadataUri: _releaseMetadataUri,
            buildMetadataUri: _buildMetadataUri,
            subdomain: _subdomain
        });
        return this;
    }

    function withManagementDaoMetadataUri(
        string memory _metadataUri
    ) public returns (ProtocolFactoryBuilder) {
        managementDaoParams.metadataUri = _metadataUri;
        return this;
    }

    function withManagementDaoMembers(
        address[] memory _members
    ) public returns (ProtocolFactoryBuilder) {
        managementDaoParams.members = _members;
        return this;
    }

    function withManagementDaoMinApprovals(
        uint8 _minApprovals
    ) public returns (ProtocolFactoryBuilder) {
        managementDaoParams.minApprovals = _minApprovals;
        return this;
    }

    // BUILDER

    /// @dev Creates a DAO with the given orchestration settings.
    /// @dev The setup is done on block/timestamp 0 and tests should be made on block/timestamp 1 or later.
    function build() public returns (ProtocolFactory) {
        ProtocolFactory.DeploymentParameters memory params = getFactoryParams();
        factory = new ProtocolFactory(params);

        // Labels
        vm.label(address(factory), "ProtocolFactory");

        vm.label(address(params.osxImplementations.daoBase), "DAO_base");
        vm.label(
            address(params.osxImplementations.daoRegistryBase),
            "DAORegistry_base"
        );
        vm.label(
            address(params.osxImplementations.pluginRepoRegistryBase),
            "PluginRepoRegistry_base"
        );
        vm.label(
            address(params.osxImplementations.placeholderSetup),
            "PlaceholderSetup"
        );
        vm.label(
            address(params.osxImplementations.ensSubdomainRegistrarBase),
            "ENSSubdomainRegistrar"
        );
        vm.label(
            address(params.osxImplementations.globalExecutor),
            "GlobalExecutor"
        );
        vm.label(address(params.helperFactories.daoHelper), "DAOHelper");
        vm.label(
            address(params.helperFactories.pluginRepoHelper),
            "PluginRepoHelper"
        );
        vm.label(address(params.helperFactories.pspHelper), "PSPHelper");
        vm.label(address(params.helperFactories.ensHelper), "ENSHelper");
        vm.label(
            address(params.corePlugins.adminPlugin.pluginSetup),
            "AdminSetup"
        );
        vm.label(
            address(params.corePlugins.multisigPlugin.pluginSetup),
            "MultisigSetup"
        );
        vm.label(
            address(params.corePlugins.tokenVotingPlugin.pluginSetup),
            "TokenVotingSetup"
        );
        vm.label(
            address(
                params.corePlugins.stagedProposalProcessorPlugin.pluginSetup
            ),
            "StagedProposalProcessorSetup"
        );

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        return factory;
    }

    function getFactoryParams()
        internal
        returns (ProtocolFactory.DeploymentParameters memory params)
    {
        address[] memory mgmtDaoMembers;
        if (managementDaoParams.members.length > 0) {
            mgmtDaoMembers = managementDaoParams.members;
        } else {
            // Set 3 members when empty
            mgmtDaoMembers = new address[](3);
            mgmtDaoMembers[0] = address(
                0x0000000000111111111122222222223333333333
            );
            mgmtDaoMembers[1] = address(
                0x1111111111222222222233333333334444444444
            );
            mgmtDaoMembers[2] = address(
                0x2222222222333333333344444444445555555555
            );
        }

        params = ProtocolFactory.DeploymentParameters({
            osxImplementations: ProtocolFactory.OSxImplementations({
                daoBase: address(new DAO()),
                daoRegistryBase: address(new DAORegistry()),
                pluginRepoRegistryBase: address(new PluginRepoRegistry()),
                placeholderSetup: address(new PlaceholderSetup()),
                ensSubdomainRegistrarBase: address(new ENSSubdomainRegistrar()),
                globalExecutor: address(new GlobalExecutor())
            }),
            helperFactories: ProtocolFactory.HelperFactories({
                daoHelper: new DAOHelper(),
                pluginRepoHelper: new PluginRepoHelper(),
                pspHelper: new PSPHelper(),
                ensHelper: new ENSHelper()
            }),
            ensParameters: ProtocolFactory.EnsParameters({
                daoRootDomain: daoRootDomain,
                managementDaoSubdomain: managementDaoSubdomain,
                pluginSubdomain: pluginSubdomain
            }),
            corePlugins: ProtocolFactory.CorePlugins({
                adminPlugin: ProtocolFactory.CorePlugin({
                    pluginSetup: new AdminSetup(),
                    release: adminPlugin.release,
                    build: adminPlugin.build,
                    releaseMetadataUri: adminPlugin.releaseMetadataUri,
                    buildMetadataUri: adminPlugin.buildMetadataUri,
                    subdomain: adminPlugin.subdomain
                }),
                multisigPlugin: ProtocolFactory.CorePlugin({
                    pluginSetup: new MultisigSetup(),
                    release: multisigPlugin.release,
                    build: multisigPlugin.build,
                    releaseMetadataUri: multisigPlugin.releaseMetadataUri,
                    buildMetadataUri: multisigPlugin.buildMetadataUri,
                    subdomain: multisigPlugin.subdomain
                }),
                tokenVotingPlugin: ProtocolFactory.CorePlugin({
                    pluginSetup: new TokenVotingSetup(
                        new GovernanceERC20(
                            IDAO(address(0)),
                            "",
                            "",
                            GovernanceERC20.MintSettings(
                                new address[](0),
                                new uint256[](0)
                            )
                        ),
                        new GovernanceWrappedERC20(
                            IERC20Upgradeable(address(0)),
                            "",
                            ""
                        )
                    ),
                    release: tokenVotingPlugin.release,
                    build: tokenVotingPlugin.build,
                    releaseMetadataUri: tokenVotingPlugin.releaseMetadataUri,
                    buildMetadataUri: tokenVotingPlugin.buildMetadataUri,
                    subdomain: tokenVotingPlugin.subdomain
                }),
                stagedProposalProcessorPlugin: ProtocolFactory.CorePlugin({
                    pluginSetup: new StagedProposalProcessorSetup(),
                    release: stagedProposalProcessorPlugin.release,
                    build: stagedProposalProcessorPlugin.build,
                    releaseMetadataUri: stagedProposalProcessorPlugin
                        .releaseMetadataUri,
                    buildMetadataUri: stagedProposalProcessorPlugin
                        .buildMetadataUri,
                    subdomain: stagedProposalProcessorPlugin.subdomain
                })
            }),
            managementDao: ProtocolFactory.ManagementDaoParameters({
                metadataUri: managementDaoParams.metadataUri,
                members: managementDaoParams.members,
                minApprovals: managementDaoParams.minApprovals
            })
        });
    }
}
