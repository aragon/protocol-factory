# Aragon Protocol Factory

This reposity contains a factory contract and a set of scripts to deploy OSx and the core Aragon plugins to a wide range of EVM compatible networks.

## Get Started

To get started, ensure that [Foundry](https://getfoundry.sh/) and [just](https://just.systems/) are installed on your computer.

For local testing, see [Using the Factory for local tests](#using-the-factory-for-local-tests) below.

### Task runner

`just` is the task runner for this project. Run `just` or `just help` to see the available commands:

```
$ just help
Available recipes:
    default
    help                                    # Show available commands

    [setup]
    init network="mainnet"                  # Initialize the project for a given network (default: mainnet)
    switch network                          # Select the active network
    setup                                   # Install Foundry

    [script]
    predeploy                               # Simulate the deploy script
    deploy                                  # Deploy: run tests, broadcast, tee to log
    resume-deploy                           # Resume a pending deployment
    run script *args                        # Run a forge script (broadcast)
    simulate script                         # Simulate a forge script (no broadcast)

    [helpers]
    env                                     # Show current environment (resolved values + sources)
    balance                                 # Show current wallet balance

    [test]
    test *args                              # Run all unit tests
    test-fork *args                         # Run fork tests (requires RPC_URL)
    test-coverage                           # Generate HTML coverage report under ./report

    [develop]
    clean                                   # Clean compiler artifacts and coverage reports
    storage-info contract                   # Show the storage layout of a contract
    anvil                                   # Start a forked EVM (set FORK_BLOCK_NUMBER in .env to pin a block)

    [verification]
    verify verifier="" script=DEPLOY_SCRIPT # Verify all contracts from the latest broadcast

```

### Environment setup

Initialize for your target network:

```sh
just init sepolia
just test
```

This selects the active network and pulls all submodules. Then set up your environment variables.

There are two types of variables, handled differently:

**Secrets** (e.g. `DEPLOYER_KEY`, `ETHERSCAN_API_KEY`). Use [`vars`](https://github.com/vars-cli/vars) (recommended) or add them to the project `.env` file:

```sh
# With vars
vars set DEPLOYER_KEY           # for production networks
vars set dev/DEPLOYER_KEY       # for testnets
vars set ETHERSCAN_API_KEY
# just env

# Plain .env file
cp .env.example .env
# then edit .env and fill in DEPLOYER_KEY and ETHERSCAN_API_KEY
```

**Deployment parameters**: specific values that are not secrets but vary per deployment. These should live in the root `.env` file and cannot be stored in `vars`:

```sh
# .env (deployment parameters)
MANAGEMENT_DAO_MIN_APPROVALS=3
MANAGEMENT_DAO_MEMBERS_FILE_NAME="multisig-members.json"
MANAGEMENT_DAO_METADATA_URI="ipfs://..."

# Optional ENS overrides (defaults are set in the network config)
# DAO_ENS_DOMAIN="dao"
# MANAGEMENT_DAO_SUBDOMAIN="management"
# PLUGIN_ENS_SUBDOMAIN="plugin"

# Optional plugin metadata overrides
# ADMIN_PLUGIN_RELEASE_METADATA_URI="ipfs://..."
# ADMIN_PLUGIN_BUILD_METADATA_URI="ipfs://..."
# MULTISIG_PLUGIN_RELEASE_METADATA_URI="ipfs://..."
# ...
```

Run `just env` to verify the full resolved environment before deploying.

## Deployment

Use `just` to simulate and deploy:

```sh
just predeploy    # simulate — no broadcast
just deploy       # run tests, broadcast, verify, tee to log/*
```

### Deployment Checklist

- [ ] I have cloned the official repository on my computer and I have checked out the `main` branch
- [ ] I am using the latest official docker engine, running a Debian Linux (stable) image
  - [ ] I have run `docker run --rm -it -v .:/deployment --env-file  <(vars resolve --partial --dotenv 2>/dev/null) debian:trixie-slim`
  - [ ] I have run `apt update && apt install -y just curl git vim neovim bc jq`
  - [ ] I have run `curl -L https://foundry.paradigm.xyz | bash && source /root/.bashrc && foundryup`
  - [ ] I have run `cd /deployment`
  - [ ] I have run `just init <network>`
- [ ] I am opening an editor on the `/deployment` folder, within the Docker container
- [ ] I have run `just env` and verified that all parameters are correct
  - [ ] `DEPLOYER_KEY` is set (via `vars set DEPLOYER_KEY` or in root `.env`)
  - [ ] `ETHERSCAN_API_KEY` is set (via `vars set ETHERSCAN_API_KEY` or in root `.env`)
  - [ ] I have set the deployment parameters in the root `.env` file:
    - [ ] `MANAGEMENT_DAO_MIN_APPROVALS` has the right value
    - [ ] `MANAGEMENT_DAO_MEMBERS_FILE_NAME` points to a file containing the correct multisig addresses
    - [ ] `MANAGEMENT_DAO_METADATA_URI` is set to the correct IPFS URI
    - [ ] Plugin metadata URIs are set (if overriding the defaults)
  - [ ] I have created a new burner wallet with `cast wallet new` and used its private key as `DEPLOYER_KEY`
  - [ ] I am the only person of the ceremony that will operate the deployment wallet
- [ ] All the tests run clean (`just test`)
- My computer:
  - [ ] Is running in a safe location and using a trusted network
  - [ ] It exposes no services or ports
    - MacOS: `sudo lsof -iTCP -sTCP:LISTEN -nP`
    - Linux: `netstat -tulpn`
    - Windows: `netstat -nao -p tcp`
  - [ ] The wifi or wired network in use does not expose any ports to a WAN
- [ ] I have run `just predeploy` and the simulation completes with no errors
- [ ] I have run `just balance` and the deployment wallet has sufficient funds
  - At least, 15% more than the amount estimated during the simulation
- [ ] `just test` still runs clean
- [ ] I have run `git status` and it reports no local changes
- [ ] The current local git branch (`main`) corresponds to its counterpart on `origin`
  - [ ] I confirm that the rest of members of the ceremony pulled the last git commit on `main` and reported the same commit hash as my output for `git log -n 1`
- [ ] I have initiated the production deployment with `just deploy`

### Post deployment checklist

- [ ] The deployment process completed with no errors
- [ ] The factory contract was deployed by the deployment address
- [ ] All the project's smart contracts are correctly verified on the reference block explorer of the target network.
- [ ] The output of the latest `logs/deployment-<network>-<date>.log` file corresponds to the console output
- [ ] A file called `artifacts/addresses-<network>-<timestamp>.json` has been created, and the addresses match those logged to the screen
- [ ] I have uploaded the following files to a shared location:
  - `logs/deployment-<network>.log` (the last one)
  - `artifacts/addresses-<network>-<timestamp>.json`  (the last one)
  - `broadcast/Deploy.s.sol/<chain-id>/run-<timestamp>.json` (the last one)
- [ ] The rest of members confirm that the values are correct
- [ ] I have transferred the remaining funds of the deployment wallet to the address that originally funded it
  - `just refund`
- [ ] I have cloned https://github.com/aragon/diffyscan-workspace/
  - [ ] I have copied the deployed addresses to a new config file for the network
  - [ ] I have run the source code verification and the code matches the [audited commits](https://github.com/aragon/osx/tree/main/audits)

This concludes the deployment ceremony.

### Post deployment (external packages)

This is optional if you are deploying to a custom network.

- [ ] I have followed [these instructions](https://github.com/aragon/osx-commons/tree/main/configs#generating-the-json-files) to generate the JSON file with the addresses for the new network
  - [ ] If needed, I have added the new network settings
- [ ] I have followed [these instructions](https://github.com/aragon/osx/tree/main/packages/artifacts#syncing-the-deployment-addresses) for OSx
- [ ] For each plugin, I have followed the equivalent instructions
  - https://github.com/aragon/admin-plugin/tree/main/packages/artifacts#syncing-the-deployment-addresses
  - https://github.com/aragon/multisig-plugin/tree/main/packages/artifacts#syncing-the-deployment-addresses
  - https://github.com/aragon/token-voting-plugin/tree/main/packages/artifacts#syncing-the-deployment-addresses
  - https://github.com/aragon/staged-proposal-processor-plugin/tree/main/packages/artifacts#syncing-the-deployment-addresses
- [ ] I have created a pull request with the updated addresses files on every repository

## Using the Factory for local tests

If you are building an OSx plugin and need a fresh OSx deployment on your test suite, your best option is by using the `ProtocolFactoryBuilder` with Foundry.

### Foundry

Add the Protocol Factory as a dependency:

```sh
forge install aragon/protocol-factory
```

Given that this repository already depends on OSx, you may want to replace the existing `remappings.txt` entry and use the OSx path provided by `protocol-factory` itself.

```diff
-@aragon/osx/=lib/osx/packages/contracts/src/

+@aragon/protocol-factory/=lib/protocol-factory/
+@aragon/osx/=lib/protocol-factory/lib/osx/packages/contracts/src/
```

#### The simplest example

```solidity
// Adjust the path according to your remappings.txt file
import {ProtocolFactoryBuilder} from "@aragon/protocol-factory/test/helpers/ProtocolFactoryBuilder.sol";

// Using the default parameters
ProtocolFactory factory = new ProtocolFactoryBuilder().build();
factory.deployOnce();

// Get the deployed addresses
ProtocolFactory.Deployment memory deployment = factory.getDeployment();
console.log("DaoFactory", deployment.daoFactory);
```

#### If you need to override some parameters

```solidity
// Adjust the path according to your remappings.txt file
import {ProtocolFactoryBuilder} from "@aragon/protocol-factory/test/helpers/ProtocolFactoryBuilder.sol";

ProtocolFactoryBuilder builder = new ProtocolFactoryBuilder();

// Using custom parameters
ProtocolFactory factory = builder
    .withAdminPlugin(
        1, // plugin release
        2, // plugin build
        "ipfs://release-metadata-uri",
        "ipfs://build-metadata-uri",
        "admin" // admin.plugin.dao.eth (subdomain)
    )
    // .withMultisigPlugin(...)
    // .withTokenVotingPlugin(...)
    // .withStagedProposalProcessorPlugin(...)
    .withDaoRootDomain("dao") // dao.eth
    .withManagementDaoSubdomain("mgmt") // mgmt.dao.eth
    .withPluginSubdomain("plugin") // plugin.dao.eth
    .withManagementDaoMetadataUri("ipfs://new-metadata-uri")
    .withManagementDaoMembers(new address[](3))
    .withManagementDaoMinApprovals(2)
    .build();

factory.deployOnce();

// Get the deployed addresses
ProtocolFactory.Deployment memory deployment = factory.getDeployment();
console.log("DaoFactory", deployment.daoFactory);
```

The ProtocolFactoryBuilder needs Foundry in order to work, as it makes use of the Std cheat codes.

### Testing with other Solidity frameworks

Due to the code size limitations, the ProtocolFactory needs to split things into two steps:
- The raw deployment of the (stateless) implementations
- The orchestration of the final protocol contracts (stateful)

The raw deployment is offloaded to [Deploy.s.sol](./script/Deploy.s.sol) and to the following helper factories:
- DAOHelper
- ENSHelper
- PluginRepoHelper
- PSPHelper

To test locally, you need to replicate the logic of [Deploy.s.sol](./script/Deploy.s.sol), and pass both the deployment parameters as well as the helper factory addresses to the constructor.

```solidity
// Implementations
DAO daoBase = new DAO();
DAORegistry daoRegistryBase = new DAORegistry();
PluginRepoRegistry pluginRepoRegistryBase = new PluginRepoRegistry();
ENSSubdomainRegistrar ensSubdomainRegistrarBase = new ENSSubdomainRegistrar();

PlaceholderSetup placeholderSetup = new PlaceholderSetup();
GlobalExecutor globalExecutor = new GlobalExecutor();

DAOHelper daoHelper = new DAOHelper();
PluginRepoHelper pluginRepoHelper = new PluginRepoHelper();
PSPHelper pspHelper = new PSPHelper();
ENSHelper ensHelper = new ENSHelper();

AdminSetup adminSetup = new AdminSetup();
MultisigSetup multisigSetup = new MultisigSetup();
TokenVotingSetup tokenVotingSetup = new TokenVotingSetup(
    new GovernanceERC20(
        IDAO(address(0)), "", "",
        GovernanceERC20.MintSettings(new address[](0), new uint256[](0), true)
    ),
    new GovernanceWrappedERC20(IERC20Upgradeable(address(0)), "", "")
);
StagedProposalProcessorSetup stagedProposalProcessorSetup = new StagedProposalProcessorSetup(new SPP());

// Parameters
ProtocolFactory.DeploymentParameters memory params = ProtocolFactory.DeploymentParameters({
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
        daoRootDomain: daoRootDomain,
        managementDaoSubdomain: managementDaoSubdomain,
        pluginSubdomain: pluginSubdomain
    }),
    corePlugins: ProtocolFactory.CorePlugins({
        adminPlugin: ProtocolFactory.CorePlugin({
            pluginSetup: adminSetup,
            release: 1,
            build: 2,
            releaseMetadataUri: releaseMetadataUri,
            buildMetadataUri: buildMetadataUri,
            subdomain: subdomain
        }),
        multisigPlugin: ProtocolFactory.CorePlugin({
            pluginSetup: multisigSetup,
            release: 1,
            build: 3,
            releaseMetadataUri: releaseMetadataUri,
            buildMetadataUri: buildMetadataUri,
            subdomain: subdomain
        }),
        tokenVotingPlugin: ProtocolFactory.CorePlugin({
            pluginSetup: tokenVotingSetup,
            release: 1,
            build: 4,
            releaseMetadataUri: releaseMetadataUri,
            buildMetadataUri: buildMetadataUri,
            subdomain: subdomain
        }),
        stagedProposalProcessorPlugin: ProtocolFactory.CorePlugin({
            pluginSetup: stagedProposalProcessorSetup,
            release: 1,
            build: 1,
            releaseMetadataUri: releaseMetadataUri,
            buildMetadataUri: buildMetadataUri,
            subdomain: subdomain
        })
    }),
    managementDao: ProtocolFactory.ManagementDaoParameters({
        metadataUri: metadataUri,
        members: members,
        minApprovals: minApprovals
    })
});

ProtocolFactory factory = new ProtocolFactory(params);
factory.deployOnce();
```

## Security
If you believe you've found a security issue, we encourage you to notify us. We welcome working with you to resolve the issue promptly.

Security Contact Email: sirt@aragon.org

Please do not use the issue tracker to report security issues.
