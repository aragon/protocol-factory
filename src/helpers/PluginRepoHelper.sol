// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {IPluginRepoHelper} from "./interfaces.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";

/// @notice This contract offloads the deployment of the PluginRepoFactory
contract PluginRepoHelper is IPluginRepoHelper {
    function deployFactory(address pluginRepoRegistry) external returns (address pluginRepoFactory) {
        pluginRepoFactory = address(new PluginRepoFactory(PluginRepoRegistry(pluginRepoRegistry)));
    }
}
