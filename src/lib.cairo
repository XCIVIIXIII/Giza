#[starknet::contract]
mod NotaryRecovery {
    use starknet::get_block_timestamp;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use core::pedersen::pedersen;

    // ========================================================================
    // STORAGE
    // ========================================================================
    
    #[storage]
    struct Storage {
        // Hardcoded user data
        username_hash: felt252,
        answer_hash_1: felt252,
        answer_hash_2: felt252,
        answer_hash_3: felt252,
        encrypted_key: felt252,
        
        // Recovery state
        recovery_session_start: u64,  // timestamp quando parte la canzone
        recovery_attempts_used: u8,   // tentativi usati (max 2)
        song_duration: u64,            // durata canzone in secondi
        max_attempts: u8,              // 2 tentativi
        is_key_recovered: bool,        // true se già recuperata
    }

    // ========================================================================
    // EVENTS
    // ========================================================================
    
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        RecoveryStarted: RecoveryStarted,
        RecoveryAttempt: RecoveryAttempt,
        RecoverySuccess: RecoverySuccess,
        RecoveryFailed: RecoveryFailed,
    }

    #[derive(Drop, starknet::Event)]
    struct RecoveryStarted {
        username_hash: felt252,
        start_time: u64,
        deadline: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct RecoveryAttempt {
        attempt_number: u8,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct RecoverySuccess {
        username_hash: felt252,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct RecoveryFailed {
        reason: felt252,
        timestamp: u64,
    }

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================
    
    #[constructor]
    fn constructor(
        ref self: ContractState,
        username_hash: felt252,
        answer_hash_1: felt252,
        answer_hash_2: felt252,
        answer_hash_3: felt252,
        encrypted_key: felt252,
        song_duration: u64,  // in secondi (es. 218 per Pyramids)
    ) {
        self.username_hash.write(username_hash);
        self.answer_hash_1.write(answer_hash_1);
        self.answer_hash_2.write(answer_hash_2);
        self.answer_hash_3.write(answer_hash_3);
        self.encrypted_key.write(encrypted_key);
        self.song_duration.write(song_duration);
        self.max_attempts.write(2);
        self.recovery_attempts_used.write(0);
        self.recovery_session_start.write(0);
        self.is_key_recovered.write(false);
    }

    // ========================================================================
    // EXTERNAL FUNCTIONS
    // ========================================================================
    
    #[abi(embed_v0)]
    impl NotaryRecoveryImpl of super::INotaryRecovery<ContractState> {
        
        // Inizia sessione di recovery (parte la canzone)
        fn start_recovery(ref self: ContractState, username_hash: felt252) -> bool {
            // Verifica username
            assert(username_hash == self.username_hash.read(), 'Invalid username');
            
            // Verifica che non sia già stata recuperata
            assert(!self.is_key_recovered.read(), 'Key already recovered');
            
            // Verifica che non abbia esaurito tentativi
            let attempts = self.recovery_attempts_used.read();
            assert(attempts < self.max_attempts.read(), 'No attempts left');
            
            // Verifica che non ci sia già una sessione attiva
            let current_session = self.recovery_session_start.read();
            let current_time = get_block_timestamp();
            
            if current_session > 0 {
                let elapsed = current_time - current_session;
                let duration = self.song_duration.read();
                
                // Se sessione precedente è scaduta, permetti nuova sessione
                assert(elapsed > duration, 'Session already active');
            }
            
            // Inizia nuova sessione
            let start_time = get_block_timestamp();
            self.recovery_session_start.write(start_time);
            
            let deadline = start_time + self.song_duration.read();
            
            self.emit(RecoveryStarted {
                username_hash,
                start_time,
                deadline,
            });
            
            true
        }
        
        // Tenta recovery con le risposte
        fn attempt_recovery(
            ref self: ContractState,
            username_hash: felt252,
            answer_1: felt252,
            answer_2: felt252,
            answer_3: felt252,
        ) -> felt252 {
            // Verifica username
            assert(username_hash == self.username_hash.read(), 'Invalid username');
            
            // Verifica che ci sia una sessione attiva
            let session_start = self.recovery_session_start.read();
            assert(session_start > 0, 'No active session');
            
            // Verifica che non sia scaduta (canzone finita)
            let current_time = get_block_timestamp();
            let elapsed = current_time - session_start;
            let duration = self.song_duration.read();
            assert(elapsed <= duration, 'Time expired - song ended');
            
            // Incrementa tentativi
            let attempts = self.recovery_attempts_used.read();
            self.recovery_attempts_used.write(attempts + 1);
            
            self.emit(RecoveryAttempt {
                attempt_number: attempts + 1,
                timestamp: current_time,
            });
            
            // Hash delle risposte
            let hash_1 = pedersen(answer_1, 0);
            let hash_2 = pedersen(answer_2, 1);
            let hash_3 = pedersen(answer_3, 2);
            
            // Verifica risposte (tutte e 3 devono essere corrette)
            let stored_hash_1 = self.answer_hash_1.read();
            let stored_hash_2 = self.answer_hash_2.read();
            let stored_hash_3 = self.answer_hash_3.read();
            
            if hash_1 == stored_hash_1 && hash_2 == stored_hash_2 && hash_3 == stored_hash_3 {
                // Success!
                self.is_key_recovered.write(true);
                
                self.emit(RecoverySuccess {
                    username_hash,
                    timestamp: current_time,
                });
                
                // Ritorna la chiave decriptata
                // (In realtà ritorniamo la chiave criptata, il client la decripta)
                self.encrypted_key.read()
                
            } else {
                // Failed
                let remaining = self.max_attempts.read() - self.recovery_attempts_used.read();
                
                if remaining == 0 {
                    self.emit(RecoveryFailed {
                        reason: 'No attempts left',
                        timestamp: current_time,
                    });
                } else {
                    self.emit(RecoveryFailed {
                        reason: 'Wrong answers',
                        timestamp: current_time,
                    });
                }
                
                0 // Ritorna 0 per indicare fallimento
            }
        }
        
        // View functions
        fn get_remaining_attempts(self: @ContractState) -> u8 {
            self.max_attempts.read() - self.recovery_attempts_used.read()
        }
        
        fn get_time_remaining(self: @ContractState) -> u64 {
            let session_start = self.recovery_session_start.read();
            if session_start == 0 {
                return 0;
            }
            
            let current_time = get_block_timestamp();
            let elapsed = current_time - session_start;
            let duration = self.song_duration.read();
            
            if elapsed >= duration {
                return 0;
            }
            
            duration - elapsed
        }
        
        fn is_session_active(self: @ContractState) -> bool {
            self.get_time_remaining() > 0
        }
        
        fn is_recovered(self: @ContractState) -> bool {
            self.is_key_recovered.read()
        }
    }
}

// ========================================================================
// INTERFACE
// ========================================================================

#[starknet::interface]
trait INotaryRecovery<TContractState> {
    fn start_recovery(ref self: TContractState, username_hash: felt252) -> bool;
    fn attempt_recovery(
        ref self: TContractState,
        username_hash: felt252,
        answer_1: felt252,
        answer_2: felt252,
        answer_3: felt252,
    ) -> felt252;
    fn get_remaining_attempts(self: @TContractState) -> u8;
    fn get_time_remaining(self: @TContractState) -> u64;
    fn is_session_active(self: @TContractState) -> bool;
    fn is_recovered(self: @TContractState) -> bool;
}

// ========================================================================
// NOTES
// ========================================================================

// Deploy del contract:
// 
// scarb build
// starkli declare target/dev/notary_recovery.contract_class.json
// starkli deploy <class_hash> \
//   <username_hash> \
//   <answer_hash_1> \
//   <answer_hash_2> \
//   <answer_hash_3> \
//   <encrypted_key> \
//   218  // song duration (Pyramids = 218 secondi)

// Flow:
// 1. User: start_recovery(username_hash)
//    → Contract: emette RecoveryStarted event
//    → Frontend: parte MP3
//
// 2. User: risponde alle domande mentre ascolta
//
// 3. User: attempt_recovery(username_hash, ans1, ans2, ans3)
//    → Contract: verifica timing + risposte
//    → Se ok: ritorna encrypted_key
//    → Frontend: decripta con hash(answers)
//
// 4. Se sbagliato: 1 tentativo rimanente
//    → Può rifare start_recovery() per nuovo tentativo
//
// 5. Se 2 tentativi falliti: GAME OVER