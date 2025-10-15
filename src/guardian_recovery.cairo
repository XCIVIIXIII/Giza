#[starknet::contract]
mod GuardianRecovery {
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    // ========================================================================
    // STORAGE
    // ========================================================================
    
    #[storage]
    struct Storage {
        // Owner che può recuperare
        owner: ContractAddress,
        
        // Guardians (3 indirizzi)
        guardian_1: ContractAddress,  // my_parent
        guardian_2: ContractAddress,  // my_bestie
        guardian_3: ContractAddress,  // my_girlfriend
        
        // Shares (Shamir): P(x) = 42 + 7x
        // Questi sono PUBBLICI (chiunque può vederli)
        // MA servono 2 per ricostruire il segreto!
        share_1_x: felt252,  // 1
        share_1_y: felt252,  // 49
        share_2_x: felt252,  // 2
        share_2_y: felt252,  // 56
        share_3_x: felt252,  // 3
        share_3_y: felt252,  // 63
        
        // Approval state (PUBBLICO per UX)
        guardian_1_approved: bool,
        guardian_2_approved: bool,
        guardian_3_approved: bool,
        
        // Recovery state
        is_recovered: bool,
        encrypted_key: felt252,
    }

    // ========================================================================
    // EVENTS
    // ========================================================================
    
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        GuardianApproved: GuardianApproved,
        RecoveryCompleted: RecoveryCompleted,
    }

    #[derive(Drop, starknet::Event)]
    struct GuardianApproved {
        guardian: ContractAddress,
        guardian_name: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct RecoveryCompleted {
        owner: ContractAddress,
        secret_recovered: felt252,
    }

    // ========================================================================
    // CONSTRUCTOR
    // ========================================================================
    
    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        guardian_1: ContractAddress,  // my_parent
        guardian_2: ContractAddress,  // my_bestie
        guardian_3: ContractAddress,  // my_girlfriend
        encrypted_key: felt252,
    ) {
        self.owner.write(owner);
        
        // Set guardians
        self.guardian_1.write(guardian_1);
        self.guardian_2.write(guardian_2);
        self.guardian_3.write(guardian_3);
        
        // Set Shamir shares: P(x) = 42 + 7x
        // Guardian 1 (my_parent): (1, 49)
        self.share_1_x.write(1);
        self.share_1_y.write(49);
        
        // Guardian 2 (my_bestie): (2, 56)
        self.share_2_x.write(2);
        self.share_2_y.write(56);
        
        // Guardian 3 (my_girlfriend): (3, 63)
        self.share_3_x.write(3);
        self.share_3_y.write(63);
        
        // Init state
        self.guardian_1_approved.write(false);
        self.guardian_2_approved.write(false);
        self.guardian_3_approved.write(false);
        self.is_recovered.write(false);
        self.encrypted_key.write(encrypted_key);
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================
    
    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        // Conta quanti guardians hanno approvato
        fn count_approvals(self: @ContractState) -> u8 {
            let mut count: u8 = 0;
            
            if self.guardian_1_approved.read() {
                count += 1;
            }
            if self.guardian_2_approved.read() {
                count += 1;
            }
            if self.guardian_3_approved.read() {
                count += 1;
            }
            
            count
        }
        
        // Ricostruisce il secret usando Shamir
        // Per semplicità in questa demo, ritorniamo il valore hardcoded
        // In produzione, useresti Lagrange interpolation vera
        fn reconstruct_secret(self: @ContractState) -> felt252 {
            // Per P(x) = 42 + 7x, il segreto è P(0) = 42
            // Qualsiasi coppia di shares ricostruisce questo valore
            
            // Per questa demo educativa, ritorniamo direttamente il segreto
            // In produzione implementeresti Lagrange interpolation:
            // P(0) = y1 * (x2/(x2-x1)) - y2 * (x1/(x2-x1))
            
            42  // Il segreto!
        }
    }

    // ========================================================================
    // EXTERNAL FUNCTIONS
    // ========================================================================
    
    #[abi(embed_v0)]
    impl GuardianRecoveryImpl of super::IGuardianRecovery<ContractState> {
        
        // ============================================================
        // WRITE FUNCTIONS (solo guardians e owner)
        // ============================================================
        
        // Guardian approva il recovery
        fn approve_recovery(ref self: ContractState) {
            let caller = get_caller_address();
            
            // Verifica che il caller sia uno dei guardians
            let g1 = self.guardian_1.read();
            let g2 = self.guardian_2.read();
            let g3 = self.guardian_3.read();
            
            let mut guardian_name: felt252 = 0;
            
            if caller == g1 {
                assert(!self.guardian_1_approved.read(), 'Already approved');
                self.guardian_1_approved.write(true);
                guardian_name = 'my_parent';
            } else if caller == g2 {
                assert(!self.guardian_2_approved.read(), 'Already approved');
                self.guardian_2_approved.write(true);
                guardian_name = 'my_bestie';
            } else if caller == g3 {
                assert(!self.guardian_3_approved.read(), 'Already approved');
                self.guardian_3_approved.write(true);
                guardian_name = 'my_girlfriend';
            } else {
                assert(false, 'Not a guardian');
            }
            
            self.emit(GuardianApproved {
                guardian: caller,
                guardian_name,
            });
        }
        
        // Owner tenta il recovery dopo che 2/3 guardians hanno approvato
        fn attempt_guardian_recovery(ref self: ContractState) -> felt252 {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'Not the owner');
            assert(!self.is_recovered.read(), 'Already recovered');
            
            // Verifica che almeno 2 guardians abbiano approvato
            let approvals = InternalFunctions::count_approvals(@self);
            assert(approvals >= 2, 'Need 2/3 approvals');
            
            // Ricostruisci il secret (42)
            let secret = InternalFunctions::reconstruct_secret(@self);
            
            self.is_recovered.write(true);
            
            self.emit(RecoveryCompleted {
                owner: caller,
                secret_recovered: secret,
            });
            
            // Ritorna la chiave encrypted
            self.encrypted_key.read()
        }
        
        // ============================================================
        // VIEW FUNCTIONS (pubbliche - chiunque può vedere)
        // ============================================================
       
        fn get_guardians(self: @ContractState) -> (ContractAddress, ContractAddress, ContractAddress) {
            (
                self.guardian_1.read(),
                self.guardian_2.read(),
                self.guardian_3.read(),
            )
        }
        
        // Vedi status approvazioni (PUBBLICO)
        fn get_approval_status(self: @ContractState) -> (bool, bool, bool) {
            (
                self.guardian_1_approved.read(),
                self.guardian_2_approved.read(),
                self.guardian_3_approved.read(),
            )
        }
        
        // Conta approvazioni (PUBBLICO)
        fn get_approval_count(self: @ContractState) -> u8 {
            InternalFunctions::count_approvals(self)
        }
        
        // Vedi se recovery completato (PUBBLICO)
        fn is_recovered(self: @ContractState) -> bool {
            self.is_recovered.read()
        }
        
        // Vedi chi è l'owner (PUBBLICO)
        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
        
        // Vedi shares (PUBBLICO per trasparenza Shamir)
        // Nota: i shares NON sono segreti! Solo la combinazione lo è
        fn get_shares(self: @ContractState) -> ((felt252, felt252), (felt252, felt252), (felt252, felt252)) {
            (
                (self.share_1_x.read(), self.share_1_y.read()),
                (self.share_2_x.read(), self.share_2_y.read()),
                (self.share_3_x.read(), self.share_3_y.read()),
            )
        }
    }
}

// ========================================================================
// INTERFACE
// ========================================================================

#[starknet::interface]
trait IGuardianRecovery<TContractState> {
    fn approve_recovery(ref self: TContractState);
    fn attempt_guardian_recovery(ref self: TContractState) -> felt252;
    fn get_guardians(self: @TContractState) -> (starknet::ContractAddress, starknet::ContractAddress, starknet::ContractAddress);
    fn get_approval_status(self: @TContractState) -> (bool, bool, bool);
    fn get_approval_count(self: @TContractState) -> u8;
    fn is_recovered(self: @TContractState) -> bool;
    fn get_owner(self: @TContractState) -> starknet::ContractAddress;
    fn get_shares(self: @TContractState) -> ((felt252, felt252), (felt252, felt252), (felt252, felt252));
}

// ========================================================================
// SPIEGAZIONE SHAMIR
// ========================================================================

// Shamir Secret Sharing (2-of-3):
//
// 1. Secret: K = 42
// 2. Polinomio random: P(x) = K + r*x = 42 + 7x
// 3. Shares (PUBBLICI!):
//    - Guardian 1 (my_parent):     (1, P(1)) = (1, 49)
//    - Guardian 2 (my_bestie):     (2, P(2)) = (2, 56)
//    - Guardian 3 (my_girlfriend): (3, P(3)) = (3, 63)
//
// 4. Recovery: Qualsiasi 2 shares possono ricostruire P(0) = 42
//    usando Lagrange interpolation
//
// Tradeoff privacy/UX:
// - Shares sono PUBBLICI (tutti vedono 49, 56, 63)
// - MA con 1 solo share NON puoi ricostruire il segreto
// - Serve 2/3 per recovery
// - UX >> Privacy assoluta
//
// Flow:
// 1. Guardian 1 chiama: approve_recovery()
// 2. Guardian 2 chiama: approve_recovery()
// 3. Ora 2/3 hanno approvato ✅
// 4. Alice (owner) chiama: attempt_guardian_recovery()
//    → Contract ricostruisce il secret (42)
//    → Ritorna encrypted_key