# Test tree definitions

Below is the graphical definition of the contract tests implemented on [the test folder](./test)

```
ProtocolFactory
├── When Deploying the ProtocolFactory
│   ├── It getParameters should return the exact same parameters as provided to the constructor
│   └── It Parameters should remain immutable after deployOnce is invoked
├── When Invoking deployOnce
│   ├── Given No prior deployment on the factory
│   │   ├── It Should emit an event with the factory address
│   │   ├── It The used ENS setup matches the given parameters
│   │   └── It The deployment addresses are filled with the new contracts
│   └── Given The factory already made a deployment
│       ├── It Should revert
│       ├── It Parameters should remain unchanged
│       └── It Deployment addresses should remain unchanged
└── Given A protocol deployment
    ├── When Calling getParameters
    │   └── It Should return the given values
    ├── When Calling getDeployment
    │   └── It Should return the right values
    ├── When Using the DAOFactory
    │   ├── It Should deploy a valid DAO and register it
    │   ├── It New DAOs should have the right permissions on themselves
    │   └── It New DAOs should be resolved from the requested ENS subdomain
    ├── When Using the PluginRepoFactory
    │   ├── It Should deploy a valid PluginRepo and register it
    │   ├── It The maintainer can publish new versions
    │   └── It The plugin repo should be resolved from the requested ENS subdomain
    ├── When Using the Management DAO
    │   ├── It Should be able to publish new core plugin versions
    │   └── It Should have a multisig with the given members and settings
    ├── When Preparing an admin plugin installation
    │   └── It It should complete normally
    ├── When Applying an admin plugin installation
    │   └── It It should allow the admin to execute on the DAO
    ├── When Preparing a multisig plugin installation
    │   └── It It should complete normally
    ├── When Applying a multisig plugin installation
    │   └── It It should allow its members to approve and execute on the DAO
    ├── When Preparing a token voting plugin installation
    │   └── It It should complete normally
    ├── When Applying a token voting plugin installation
    │   └── It It should allow its members to approve and execute on the DAO
    ├── When Preparing an SPP plugin installation
    │   └── It It should complete normally
    └── When Applying an SPP plugin installation
        └── It It should allow its bodies to execute on the DAO
```

