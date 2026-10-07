// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {IPluginSetup} from "@aragon/osx/common/plugin/setup/IPluginSetup.sol";

import {ProtocolFactory} from "../src/ProtocolFactory.sol";

/// @notice Writes the artifacts-hub `AddressBook` (aragon/artifacts-hub `scripts/schema.ts`) of a network deployed by
///         a ProtocolFactory: OSx, management DAO, ENS, every plugin repo with all its published versions, the
///         condition factory and the factory itself. Everything is read from the deployment, on-chain.
/// @dev Plugin slugs match artifacts-hub's `scripts/lib/plugin-catalog.ts`. Placeholder builds carry
///      `placeholder: true` and no implementation; the latest non-placeholder build carries `current: true`.
abstract contract AddressBook is Script {
    /// @notice Writes `artifacts/address-book-<network>-<block.timestamp>.json` and returns its path.
    function _writeAddressBook(ProtocolFactory _factory, address _conditionFactory, string memory _network)
        internal
        returns (string memory path)
    {
        string memory dir = string.concat(vm.projectRoot(), "/artifacts");
        vm.createDir(dir, true);
        path = string.concat(dir, "/address-book-", _network, "-", vm.toString(block.timestamp), ".json");
        vm.writeFile(path, _addressBookJson(_factory, _conditionFactory, _network));
    }

    function _addressBookJson(ProtocolFactory _factory, address _conditionFactory, string memory _network)
        internal
        view
        returns (string memory)
    {
        ProtocolFactory.Deployment memory d = _factory.getDeployment();
        ProtocolFactory.DeploymentParameters memory p = _factory.getParameters();

        return string.concat(
            "{\n",
            _kv("chainId", vm.toString(block.chainid)),
            ",\n",
            _kv("network", _str(_network)),
            ",\n",
            _kv("osx", _osxJson(d)),
            ",\n",
            _kv(
                "management",
                string.concat(
                    "{",
                    _kv("dao", _addr(d.managementDao)),
                    ", ",
                    _kv("daoMultisig", _addr(d.managementDaoMultisig)),
                    "}"
                )
            ),
            ",\n",
            _kv("ens", _ensJson(d)),
            ",\n",
            _kv("plugins", _pluginsJson(d, p)),
            ",\n",
            _kv(
                "conditions",
                string.concat(
                    "{",
                    _kv(
                        "factories",
                        string.concat("[{", _kv("address", _addr(_conditionFactory)), ", \"current\": true}]")
                    ),
                    "}"
                )
            ),
            ",\n",
            _kv("deployers", string.concat("{", _kv("protocolFactory", _addr(address(_factory))), "}")),
            "\n}\n"
        );
    }

    // ==== Sections ====

    function _osxJson(ProtocolFactory.Deployment memory d) private view returns (string memory) {
        uint8[3] memory v = DAOFactory(d.daoFactory).protocolVersion();
        string memory core = string.concat(
            "{",
            _kv("daoBase", _addr(DAOFactory(d.daoFactory).daoBase())),
            ", ",
            _kv("daoFactory", _addr(d.daoFactory)),
            ", ",
            _kv("daoRegistry", _addr(d.daoRegistry)),
            ", ",
            _kv("pluginRepoFactory", _addr(d.pluginRepoFactory)),
            ", ",
            _kv("pluginRepoRegistry", _addr(d.pluginRepoRegistry)),
            ", ",
            _kv("pluginSetupProcessor", _addr(d.pluginSetupProcessor)),
            "}"
        );
        return string.concat(
            "{\"versions\": [{",
            _kv(
                "protocolVersion",
                _str(
                    string.concat(
                        vm.toString(uint256(v[0])), ".", vm.toString(uint256(v[1])), ".", vm.toString(uint256(v[2]))
                    )
                )
            ),
            ", ",
            _kv("core", core),
            ", ",
            _kv("helpers", string.concat("{", _kv("globalExecutor", _addr(d.globalExecutor)), "}")),
            ", \"current\": true}]}"
        );
    }

    function _ensJson(ProtocolFactory.Deployment memory d) private pure returns (string memory) {
        return string.concat(
            "{",
            _kv("registry", _addr(d.ensRegistry)),
            ", ",
            _kv("daoSubdomainRegistrar", _addr(d.daoSubdomainRegistrar)),
            ", ",
            _kv("pluginSubdomainRegistrar", _addr(d.pluginSubdomainRegistrar)),
            ", ",
            _kv("publicResolver", _addr(d.publicResolver)),
            "}"
        );
    }

    function _pluginsJson(ProtocolFactory.Deployment memory d, ProtocolFactory.DeploymentParameters memory p)
        private
        view
        returns (string memory)
    {
        string memory domain =
            string.concat(".", p.ensParameters.pluginSubdomain, ".", p.ensParameters.daoRootDomain, ".eth");
        return string.concat(
            "{\n",
            _kv("admin", _pluginJson(d, d.adminPluginRepo, p.corePlugins.adminPlugin.subdomain, domain, false)),
            ",\n",
            _kv(
                "multisig", _pluginJson(d, d.multisigPluginRepo, p.corePlugins.multisigPlugin.subdomain, domain, false)
            ),
            ",\n",
            _kv(
                "token-voting",
                _pluginJson(d, d.tokenVotingPluginRepo, p.corePlugins.tokenVotingPlugin.subdomain, domain, true)
            ),
            ",\n",
            _kv(
                "spp",
                _pluginJson(
                    d,
                    d.stagedProposalProcessorPluginRepo,
                    p.corePlugins.stagedProposalProcessorPlugin.subdomain,
                    domain,
                    false
                )
            ),
            ",\n",
            _kv(
                "lock-to-vote",
                _pluginJson(d, d.lockToVotePluginRepo, p.corePlugins.lockToVotePlugin.subdomain, domain, false)
            ),
            "\n}"
        );
    }

    /// @param _subdomain The subdomain the factory registered (empty: no ENS name).
    /// @param _tokenTemplates Whether to record TokenVoting's governance token templates under `other`.
    function _pluginJson(
        ProtocolFactory.Deployment memory d,
        address _repo,
        string memory _subdomain,
        string memory _domain,
        bool _tokenTemplates
    ) private view returns (string memory) {
        PluginRepo repo = PluginRepo(_repo);
        string memory json = string.concat("{", _kv("repo", _addr(_repo)));
        if (bytes(_subdomain).length != 0) {
            json = string.concat(json, ", ", _kv("ens", _str(string.concat(_subdomain, _domain))));
        }
        if (repo.isGranted(_repo, d.managementDao, repo.MAINTAINER_PERMISSION_ID(), "")) {
            json = string.concat(json, ", ", _kv("maintainer", _addr(d.managementDao)));
        }
        (string memory versions, address currentSetup) = _versionsJson(repo, d.placeholderSetup);
        json = string.concat(json, ", ", _kv("versions", versions));
        if (_tokenTemplates && currentSetup != address(0)) {
            json = string.concat(json, _tokenTemplatesJson(currentSetup));
        }
        return string.concat(json, "}");
    }

    /// @return json Every published version, ascending.
    /// @return currentSetup The setup of the latest non-placeholder version (zero if none).
    function _versionsJson(PluginRepo _repo, address _placeholderSetup)
        private
        view
        returns (string memory json, address currentSetup)
    {
        uint8 latestRelease = _repo.latestRelease();

        // The latest non-placeholder version is `current`: find it first.
        uint8 currentRelease;
        uint256 currentBuild;
        for (uint8 r = 1; r <= latestRelease; ++r) {
            uint256 builds = _repo.buildCount(r);
            for (uint256 b = 1; b <= builds; ++b) {
                address setup = _repo.getVersion(PluginRepo.Tag(r, uint16(b))).pluginSetup;
                if (setup != _placeholderSetup) {
                    (currentRelease, currentBuild, currentSetup) = (r, b, setup);
                }
            }
        }

        json = "[";
        for (uint8 r = 1; r <= latestRelease; ++r) {
            uint256 builds = _repo.buildCount(r);
            for (uint256 b = 1; b <= builds; ++b) {
                address setup = _repo.getVersion(PluginRepo.Tag(r, uint16(b))).pluginSetup;
                string memory entry = string.concat(
                    "{",
                    _kv("release", vm.toString(uint256(r))),
                    ", ",
                    _kv("build", vm.toString(b)),
                    ", ",
                    _kv("setup", _addr(setup))
                );
                if (setup == _placeholderSetup) {
                    entry = string.concat(entry, ", \"placeholder\": true");
                } else {
                    // Omitted when the setup has no implementation (constructor-based plugins, as on zkSync).
                    address implementation = IPluginSetup(setup).implementation();
                    if (implementation != address(0)) {
                        entry = string.concat(entry, ", ", _kv("implementation", _addr(implementation)));
                    }
                    if (r == currentRelease && b == currentBuild) entry = string.concat(entry, ", \"current\": true");
                }
                json = string.concat(json, bytes(json).length == 1 ? "" : ", ", entry, "}");
            }
        }
        json = string.concat(json, "]");
    }

    /// @dev TokenVoting's setup exposes the governance token templates it clones (as artifacts-hub's ingest records).
    function _tokenTemplatesJson(address _setup) private view returns (string memory) {
        address erc20 = _readAddress(_setup, "governanceERC20Base()");
        address wrapped = _readAddress(_setup, "governanceWrappedERC20Base()");
        if (erc20 == address(0) && wrapped == address(0)) return "";

        string memory other = "{";
        if (erc20 != address(0)) other = string.concat(other, _kv("governanceERC20", _addr(erc20)));
        if (wrapped != address(0)) {
            other = string.concat(other, erc20 == address(0) ? "" : ", ", _kv("governanceWrappedERC20", _addr(wrapped)));
        }
        return string.concat(", ", _kv("other", string.concat(other, "}")));
    }

    // ==== JSON helpers ====

    function _readAddress(address _target, string memory _signature) private view returns (address result) {
        (bool ok, bytes memory ret) = _target.staticcall(abi.encodeWithSignature(_signature));
        if (ok && ret.length == 32) result = abi.decode(ret, (address));
    }

    function _kv(string memory _key, string memory _jsonValue) private pure returns (string memory) {
        return string.concat("\"", _key, "\": ", _jsonValue);
    }

    function _str(string memory _value) private pure returns (string memory) {
        return string.concat("\"", _value, "\"");
    }

    function _addr(address _value) private pure returns (string memory) {
        return _str(vm.toString(_value));
    }
}
