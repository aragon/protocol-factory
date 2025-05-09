# Grouping networks based on the block explorer they use

ETHERSCAN_NETWORKS := mainnet sepolia holesky optimism
BLOCKSCOUT_NETWORKS := mode
SOURCIFY_NETWORKS := monadTestnet

AVAILABLE_NETWORKS = $(ETHERSCAN_NETWORKS) \
	$(BLOCKSCOUT_NETWORKS) \
	$(SOURCIFY_NETWORKS)
