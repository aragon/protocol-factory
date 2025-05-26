# Grouping networks based on the block explorer they use

# Convention:
# - Production networks:     <name>
# - Test networks: 			     <name>-testnet

ETHERSCAN_NETWORKS := mainnet sepolia holesky optimism
BLOCKSCOUT_NETWORKS := mode
SOURCIFY_NETWORKS := monad-testnet
ROUTESCAN_NETWORKS := avalanche corn corn-testnet avalanche-testnet

AVAILABLE_NETWORKS = $(ETHERSCAN_NETWORKS) \
	$(BLOCKSCOUT_NETWORKS) \
	$(SOURCIFY_NETWORKS) \
	$(ROUTESCAN_NETWORKS)
