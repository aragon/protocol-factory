// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

interface IDAOHelper {
    function deployFactory(address daoRegistry, address pluginSetupProcessor) external returns (address daoFactory);
}

interface IPluginRepoHelper {
    function deployFactory(address pluginRepoRegistry) external returns (address pluginRepoFactory);
}

interface IPSPHelper {
    function deployStatic(address pluginRepoRegistry) external returns (address pluginSetupProcessor);
}

interface IENSHelper {
    function deployStatic(address owner, bytes memory daoRootDomain, bytes memory pluginSubdomain)
        external
        returns (address ensRegistry, address publicResolver, bytes32 DAO_ETH_NODE, bytes32 PLUGIN_DAO_ETH_NODE);
}
