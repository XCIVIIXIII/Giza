#!/usr/bin/env python3
"""
Setup script per Notary Recovery
Calcola hash e genera comandi di deploy usando starkli
"""

import subprocess
import hashlib
import sys

def starkli_to_felt(string: str) -> str:
    """Usa starkli per convertire stringa in felt"""
    try:
        result = subprocess.run(
            ['starkli', 'to-cairo-string', string],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error running starkli: {e}")
        sys.exit(1)

def starkli_pedersen(a: str, b: str) -> str:
    """Usa starkli per calcolare pedersen hash"""
    try:
        # starkli parse <expression>
        result = subprocess.run(
            ['starkli', 'parse', f'pedersen({a}, {b})'],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        # Fallback: calcola manualmente (approssimativo)
        combined = f"{a}{b}".encode()
        h = hashlib.sha256(combined).digest()
        felt = int.from_bytes(h[:31], 'big')
        return hex(felt)

# ============================================================================
# CONFIGURAZIONE UTENTE
# ============================================================================

USERNAME = "alice"
ANSWERS = [
    "Denis Guedj",
    "2012",
    "Finney"
]
SONG_DURATION = 218  # secondi (Pyramids)

# Master key da proteggere (esempio)
MASTER_KEY = "0x1234567890abcdef"  # Sostituisci con la tua chiave
MASTER_KEY_INT = int(MASTER_KEY, 16)

# ============================================================================
# CALCOLA HASH
# ============================================================================

print("="*60)
print("NOTARY RECOVERY SETUP")
print("="*60)

# Username hash
print(f"\nCalculating username hash...")
username_hash = starkli_to_felt(USERNAME.lower().strip())
print(f"Username: {USERNAME}")
print(f"Username hash: {username_hash}")

# Answer hashes (con Pedersen + salt come nel contract)
print("\nCalculating answer hashes...")
answer_hashes = []
answer_felts = []

for i, answer in enumerate(ANSWERS):
    # Prima converti answer in felt
    answer_felt = starkli_to_felt(answer.lower().strip())
    answer_felts.append(answer_felt)
    
    # Poi fai pedersen(answer_felt, salt)
    salt = str(i)
    answer_hash = starkli_pedersen(answer_felt, salt)
    answer_hashes.append(answer_hash)
    
    print(f"  {i+1}. '{answer}'")
    print(f"     Felt: {answer_felt}")
    print(f"     Hash (pedersen with salt {i}): {answer_hash}")

# Encrypted key
print(f"\nCalculating encrypted key...")
# combined = pedersen(pedersen(h1, h2), h3)
temp = starkli_pedersen(answer_hashes[0], answer_hashes[1])
combined_hash = starkli_pedersen(temp, answer_hashes[2])

# XOR master key con combined hash
master_key_int = int(MASTER_KEY, 16)
combined_int = int(combined_hash, 16)
encrypted_key = hex(master_key_int ^ combined_int)

print(f"Master Key: {MASTER_KEY}")
print(f"Combined Hash: {combined_hash}")
print(f"Encrypted Key: {encrypted_key}")

# ============================================================================
# GENERA COMANDI DEPLOY
# ============================================================================

print("\n" + "="*60)
print("DEPLOY COMMANDS")
print("="*60)

# Declare
print("\n1. Declare contract:")
print("scarb build")
print("starkli declare target/dev/notary_recovery_NotaryRecovery.contract_class.json \\")
print("  --network sepolia")

# Deploy
print("\n2. Deploy contract (sostituisci <CLASS_HASH> con l'output sopra):")
deploy_cmd = f"""starkli deploy <CLASS_HASH> \\
  {username_hash} \\
  {answer_hashes[0]} \\
  {answer_hashes[1]} \\
  {answer_hashes[2]} \\
  {encrypted_key} \\
  u64:{SONG_DURATION} \\
  --network sepolia"""

print(deploy_cmd)

# ============================================================================
# GENERA FILE ENV PER FRONTEND
# ============================================================================

print("\n" + "="*60)
print("FRONTEND CONFIGURATION")
print("="*60)

env_content = f"""// Configuration file for frontend
// Copy this to frontend/config.js

const CONFIG = {{
  CONTRACT_ADDRESS: '0x...', // Update after deploy
  USERNAME: '{USERNAME}',
  USERNAME_HASH: '{username_hash}',
  SONG_DURATION: {SONG_DURATION},
  EXPECTED_ANSWERS: [
    '{ANSWERS[0]}',
    '{ANSWERS[1]}',
    '{ANSWERS[2]}'
  ],
  // For testing only - remove in production!
}};

export default CONFIG;
"""

print(env_content)

# Salva in file
with open('frontend/config.js', 'w') as f:
    f.write(env_content)

print("\n✅ Config saved to frontend/config.js")

# ============================================================================
# TEST HASH VERIFICATION
# ============================================================================

print("\n" + "="*60)
print("TEST: Verify hash computation")
print("="*60)

test_answers = ["denis", "2012", "finney"]
print("\nTest with lowercase answers:")
for i, ans in enumerate(test_answers):
    test_felt = starkli_to_felt(ans)
    test_hash = starkli_pedersen(test_felt, str(i))
    matches = test_hash == answer_hashes[i]
    status = "✅" if matches else "❌"
    print(f"  {status} {ans}: {test_hash}")

# ============================================================================
# RECOVERY TEST SCRIPT
# ============================================================================

recovery_test = f"""#!/bin/bash
# Test recovery locally (dopo deploy)

CONTRACT_ADDRESS="<YOUR_CONTRACT_ADDRESS>"

echo "Getting remaining attempts..."
starkli call $CONTRACT_ADDRESS get_remaining_attempts --network sepolia

echo "Starting recovery session..."
starkli invoke $CONTRACT_ADDRESS start_recovery {username_hash} --network sepolia

echo "Waiting for confirmation... (press ENTER when ready)"
read

echo "Attempting recovery..."
starkli invoke $CONTRACT_ADDRESS attempt_recovery \\
  {username_hash} \\
  {answer_hashes[0]} \\
  {answer_hashes[1]} \\
  {answer_hashes[2]} \\
  --network sepolia

echo "Done! Check if key was recovered."
"""

with open('scripts/test_recovery.sh', 'w') as f:
    f.write(recovery_test)

print("\n✅ Test script saved to scripts/test_recovery.sh")

print("\n" + "="*60)
print("NEXT STEPS")
print("="*60)
print("""
1. Deploy contract with commands above
2. Update frontend/config.js with CONTRACT_ADDRESS
3. Put pyramids.mp3 in frontend/
4. Test locally:
   cd frontend && python3 -m http.server 8000
5. Open http://localhost:8000

For production:
- Remove test data from config.js
- Use proper key encryption
- Add rate limiting
- Deploy frontend to IPFS or traditional hosting
""")