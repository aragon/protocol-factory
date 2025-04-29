// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {IDAOHelper} from "./interfaces.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {DAORegistry} from "@aragon/osx/framework/dao/DAORegistry.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";

/// @notice This contract offloads the deployment of the DAOFactory
contract DAOHelper is IDAOHelper {
    function deployFactory(address daoRegistry, address pluginSetupProcessor) external returns (address daoFactory) {
        daoFactory = address(new DAOFactory(DAORegistry(daoRegistry), PluginSetupProcessor(pluginSetupProcessor)));
    }
}
