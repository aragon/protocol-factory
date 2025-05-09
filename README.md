# Aragon Protocol Factory

This reposity contains a factory contract and a set of scripts to deploy OSx and the core Aragon plugins to a wide range of EVM compatible networks.

## Get Started

To get started, ensure that [Foundry](https://getfoundry.sh/), [Make](https://www.gnu.org/software/make/) and [Docker](https://www.docker.com) are installed on your computer.

For local testing, see [Using the Factory for local tests](#using-the-factory-for-local-tests) below.

### Using the Makefile

The `Makefile` is the target launcher of the project. It's the recommended way to work with the factory for protocol deployments. It manages the env variables of common tasks and executes only the steps that need to be run.

```
$ make
Available targets:

- make help             Display the available targets

- make init             Check the dependencies and prompt to install if needed
- make clean            Clean the build artifacts

Testing lifecycle:

- make test             Run unit tests, locally
- make test-coverage    Generate an HTML coverage report under ./report

- make sync-tests       Scaffold or sync tree files into solidity tests
- make check-tests      Checks if solidity files are out of sync
- make markdown-tests   Generates a markdown file with the test definitions rendered as a tree

Deployment targets:

- make predeploy        Simulate a protocol deployment
- make deploy           Deploy the protocol, verify the source code and write to ./artifacts

- make refund           Refund the remaining balance left on the deployment account
```

Copy `.env.example` into `.env`:

```sh
cp .env.example .env
```

Run `make init`:
- It ensures that Foundry is installed
- It runs a first compilation of the project

Next, set the values of `.env` according to your environment.

## Deployment

Check the available make targets to simulate and deploy the smart contracts:

```
- make predeploy        Simulate a protocol deployment
- make deploy           Deploy the protocol and verify the source code
```

### Deployment Checklist

- [ ] I have cloned the official repository on my computer and I have checked out the `main` branch
- [ ] I am using the latest official docker engine, running a Debian Linux (stable) image
  - [ ] I have run `docker run --rm -it -v .:/deployment debian:bookworm-slim`
  - [ ] I have run `apt update && apt install -y make curl git vim neovim bc`
  - [ ] I have run `curl -L https://foundry.paradigm.xyz | bash`
  - [ ] I have run `source /root/.bashrc && foundryup`
  - [ ] I have run `cd /deployment`
  - [ ] I have run `cp .env.example .env`
  - [ ] I have run `make init`
- [ ] I am opening an editor on the `/deployment` folder, within the Docker container
- [ ] The `.env` file contains the correct parameters for the deployment
  - [ ] I have created a brand new burner wallet with `cast wallet new` and copied the private key to `DEPLOYMENT_PRIVATE_KEY` within `.env`
  - [ ] I have set the correct `RPC_URL` for the network
  - [ ] I have set `ETHERSCAN_API_KEY` (if relevant to the target network)
  - [ ] I have printed the contents of `.env` on the screen
  - [ ] I am the only person of the ceremony that will operate the deployment wallet
- [ ] All the tests run clean (`make test`)
- My computer:
  - [ ] Is running in a safe location and using a trusted network
  - [ ] It exposes no services or ports
    - MacOS: `sudo lsof -iTCP -sTCP:LISTEN -nP`
    - Linux: `netstat -tulpn`
    - Windows: `netstat -nao -p tcp`
  - [ ] The wifi or wired network in use does not expose any ports to a WAN
- [ ] I have run `make predeploy` and the simulation completes with no errors
- [ ] The deployment wallet has sufficient native token for gas
  - At least, 15% more than the amount estimated during the simulation
- [ ] `make test` still runs clean
- [ ] I have run `git status` and it reports no local changes
- [ ] The current local git branch (`main`) corresponds to its counterpart on `origin`
  - [ ] I confirm that the rest of members of the ceremony pulled the last git commit on `main` and reported the same commit hash as my output for `git log -n 1`
- [ ] I have initiated the production deployment with `make deploy`

### Post deployment checklist

- [ ] The deployment process completed with no errors
- [ ] The factory contract was deployed by the deployment address
- [ ] All the project's smart contracts are correctly verified on the reference block explorer of the target network.
- [ ] The output of the latest `logs/deployment-<network>.log` file corresponds to the console output
- [ ] A file called `artifacts/addresses-<network>-<timestamp>.json` has been created, and the addresses match those logged to the screen
- [ ] I have uploaded these two files to a shared location
    - [ ] The rest of members confirm that the values are correct
- [ ] I have transferred the remaining funds of the deployment wallet to the address that originally funded it
  - `make refund`

This concludes the deployment ceremony.

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
        GovernanceERC20.MintSettings(new address[](0), new uint256[](0))
    ),
    new GovernanceWrappedERC20(IERC20Upgradeable(address(0)), "", "")
);
StagedProposalProcessorSetup stagedProposalProcessorSetup = new StagedProposalProcessorSetup();

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
            build: 3,
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

## Deployment troubleshooting (CLI)

If you get the error Failed to get EIP-1559 fees, add `--legacy` to the command:

```sh
forge script --chain "$NETWORK" script/DeployGauges.s.sol:Deploy --rpc-url "$RPC_URL" --broadcast --verify --legacy
```

If some contracts fail to verify on Etherscan, retry with this command:

```sh
forge script --chain "$NETWORK" script/DeployGauges.s.sol:Deploy --rpc-url "$RPC_URL" --verify --legacy --private-key "$DEPLOYMENT_PRIVATE_KEY" --resume
```

## Testing

Using make:

```
Testing lifecycle:

- make test             Run unit tests, locally
- make test-coverage    Generate an HTML coverage report under ./report
```

Run `make test` or `forge test -vvv` to check the logic's accordance to the specs.

See the [TEST_TREE.md](./TEST_TREE.md) file for a visual summary of the implemented tests.

### Writing tests

Tests are described using yaml files like [ProtocolFactory.t.yaml](./test/ProtocolFactory.t.yaml). `make sync-tests` will transform them into solidity tests using [bulloak](https://github.com/alexfertel/bulloak).

Create a file with `.t.yaml` extension within the `test` folder and describe a hierarchy of test cases:

```yaml
# MyTest.t.yaml

MyContractTest:
- given: proposal exists
  comment: Comment here
  and:
  - given: proposal is in the last stage
    and:

    - when: proposal can advance
      then:
      - it: Should return true

    - when: proposal cannot advance
      then:
      - it: Should return false

  - when: proposal is not in the last stage
    then:
    - it: should do A
      comment: This is an important remark
    - it: should do B
    - it: should do C

- when: proposal doesn't exist
  comment: Testing edge cases here
  then:
  - it: should revert
```

Then use `make` to automatically sync the described branches into solidity test files.

```sh
$ make
Testing lifecycle:
# ...
- make sync-tests       Scaffold or sync tree files into solidity tests
- make check-tests      Checks if solidity files are out of sync
- make markdown-tests   Generates a markdown file with the test definitions rendered as a tree

$ make sync-tests
```

Each yaml file will produce a human readable tree like below, followed by a solidity test scaffold:

```
# MyTest.tree

MyContractTest
├── Given proposal exists // Comment here
│   ├── Given proposal is in the last stage
│   │   ├── When proposal can advance
│   │   │   └── It Should return true
│   │   └── When proposal cannot advance
│   │       └── It Should return false
│   └── When proposal is not in the last stage
│       ├── It should do A // Careful here
│       ├── It should do B
│       └── It should do C
└── When proposal doesn't exist // Testing edge cases here
    └── It should revert
```

## Security
If you believe you've found a security issue, we encourage you to notify us. We welcome working with you to resolve the issue promptly.

Security Contact Email: sirt@aragon.org

Please do not use the issue tracker to report security issues.
