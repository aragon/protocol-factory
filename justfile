import? 'lib/just-foundry/justfile'

default:
    @just help 2>/dev/null || echo "Run 'just init <network>' first"

# DEPLOY_SCRIPT := "script/Deploy.s.sol:DeployScript"

# Fetch dependencies, scaffold .env and select the active network
[group('setup')]
init network="mainnet":
    git submodule update --init
    @[ -f .env ] || { cp .env.example .env && echo "Created .env from .env.example — edit it with your settings."; }
    just setup
    just switch {{ network }}
