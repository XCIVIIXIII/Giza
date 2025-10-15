#!/bin/bash
# Test recovery locally (dopo deploy)

CONTRACT_ADDRESS="<YOUR_CONTRACT_ADDRESS>"

echo "Getting remaining attempts..."
starkli call $CONTRACT_ADDRESS get_remaining_attempts --network sepolia

echo "Starting recovery session..."
starkli invoke $CONTRACT_ADDRESS start_recovery 0x616c696365 --network sepolia

echo "Waiting for confirmation... (press ENTER when ready)"
read

echo "Attempting recovery..."
starkli invoke $CONTRACT_ADDRESS attempt_recovery \
  0x616c696365 \
  0x6ba01debc71e90b15eb33c94965f04987712acfa6240c9a4c330e5e2b25ac2 \
  0x859a4925b199166e3249203cc6aae2c6f9cdc74826485160d3bd21aa5901b7 \
  0xb5e9f2c9a43d67eca33cc8bb130906149cbdd4dc3edb9b537e766f53edc26b \
  --network sepolia

echo "Done! Check if key was recovered."
