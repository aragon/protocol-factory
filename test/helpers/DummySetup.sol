// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {PluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginSetup.sol";

contract DummySetup is PluginSetup {
    constructor() PluginSetup(address(0)) {}

    function prepareInstallation(
        address,
        /*_dao*/
        bytes calldata /*_data*/
    )
        external
        pure
        returns (
            address, /*plugin*/
            PreparedSetupData memory /*preparedSetupData*/
        )
    {}

    function prepareUninstallation(
        address,
        /*_dao*/
        SetupPayload calldata /*_payload*/
    )
        external
        pure
        returns (
            PermissionLib.MultiTargetPermission[] memory /*permissions*/
        )
    {}
}
