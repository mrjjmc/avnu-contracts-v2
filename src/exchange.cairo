// Import statements unchanged

// Constants unchanged

#[storage]
struct Storage {
    Ownable_owner: ContractAddress,
    AdapterClassHash: LegacyMap<ContractAddress, ClassHash>,
    fees_active: bool,
    fees_bps_0: u128,
    fees_bps_1: u128,
    fees_recipient: ContractAddress,
}

// Events unchanged

#[external(v0)]
impl ExchangeLocker of ILocker<ContractState> {
    fn locked(ref self: ContractState, id: u32, data: Array<felt252>) -> Array<felt252> {
        // Implementation unchanged
    }
}

#[constructor]
fn constructor(
    ref self: ContractState, owner: ContractAddress, fee_recipient: ContractAddress
) {
    // Set owner & fee collector address
    self.Ownable_owner.write(owner);
    self.fees_recipient.write(fee_recipient);
}

#[external(v0)]
impl Exchange of IExchange<ContractState> {
    // Implementation unchanged
}

#[generate_trait]
impl Internal of InternalTrait {
    // Implementation unchanged
}
