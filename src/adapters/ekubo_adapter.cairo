use starknet::ContractAddress;

#[derive(Serde)]
struct i129 {
    mag: u128,
    sign: bool,
}

#[inline(always)]
fn i129_eq(a: &i129, b: &i129) -> bool {
    a.mag == b.mag && (a.sign == b.sign || a.mag == 0)
}

#[derive(Serde)]
struct PoolKey {
    token0: ContractAddress,
    token1: ContractAddress,
    fee: u128,
    tick_spacing: u128,
    extension: ContractAddress,
}

#[derive(Serde)]
struct SwapParameters {
    amount: i129,
    is_token1: bool,
    sqrt_ratio_limit: u256,
    skip_ahead: u32,
}

#[derive(Serde)]
struct Delta {
    amount0: i129,
    amount1: i129,
}

#[derive(Serde, PartialEq)]
struct PoolPrice {
    sqrt_ratio: u256,
    tick: i129,
    call_points: CallPoints,
}

#[derive(Serde, PartialEq)]
struct CallPoints {
    after_initialize_pool: bool,
    before_swap: bool,
    after_swap: bool,
    before_update_position: bool,
    after_update_position: bool,
}

#[starknet::interface]
trait IEkuboRouter<TContractState> {
    fn lock(&self, data: Vec<felt252>) -> Vec<felt252>;
    fn swap(&self, pool_key: PoolKey, params: SwapParameters) -> Delta;
    fn withdraw(&self, token_address: ContractAddress, recipient: ContractAddress, amount: u128);
    fn get_pool_price(&self, pool_key: PoolKey) -> PoolPrice;
    fn pay(&self, token_address: ContractAddress);
}

#[starknet::contract]
mod EkuboAdapter {
    use array::{Array, ArrayTrait, SpanTrait};
    use avnu::adapters::ISwapAdapter;
    use avnu::interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use avnu::interfaces::locker::ISwapAfterLock;
    use avnu::math::sqrt_ratio::compute_sqrt_ratio_limit;
    use integer::{BoundedU32};
    use serde::Serde;
    use starknet::ContractAddress;
    use super::{IEkuboRouterDispatcher, PoolKey, SwapParameters, i129};

    const MIN_SQRT_RATIO: u256 = 18446748437148339061;
    const MAX_SQRT_RATIO: u256 = 6277100250585753475930931601400621808602321654880405518632;

    #[storage]
    struct Storage {}

    #[derive(Serde)]
    struct SwapAfterLockParameters {
        contract_address: ContractAddress,
        to: ContractAddress,
        token_from_address: ContractAddress,
        token_from_amount: u256,
        token_to_address: ContractAddress,
        pool_key: PoolKey,
        sqrt_ratio_distance: u256,
    }

    #[external(v0)]
    impl EkuboAdapter of ISwapAdapter<ContractState> {
        fn swap(
            &self,
            exchange_address: ContractAddress,
            token_from_address: ContractAddress,
            token_from_amount: u256,
            token_to_address: ContractAddress,
            token_to_min_amount: u256,
            to: ContractAddress,
            additional_swap_params: Vec<felt252>,
        ) {
            // Verify additional_swap_params
            assert_eq!(additional_swap_params.len(), 6, 'Invalid swap params');

            // Build callback data
            let callback = SwapAfterLockParameters {
                contract_address: exchange_address,
                to,
                token_from_address,
                token_from_amount,
                token_to_address,
                pool_key: PoolKey {
                    token0: (*additional_swap_params[0]).try_into().unwrap(),
                    token1: (*additional_swap_params[1]).try_into().unwrap(),
                    fee: (*additional_swap_params[2]).try_into().unwrap(),
                    tick_spacing: (*additional_swap_params[3]).try_into().unwrap(),
                    extension: (*additional_swap_params[4]).try_into().unwrap(),
                },
                sqrt_ratio_distance: (*additional_swap_params[5]).into(),
            };
            let mut data: Vec<felt252> = Vec::new();
            Serde::<SwapAfterLockParameters>::serialize(&callback, &mut data);

            // Lock
            let ekubo = IEkuboRouterDispatcher { contract_address: exchange_address };
            ekubo.lock(data);
        }
    }

    #[external(v0)]
    impl SwapAfterLock of ISwapAfterLock<ContractState> {
        fn swap_after_lock(&self, data: Vec<felt252>) {
            // Deserialize data
            let mut input_span = data.span();
            let mut params = Serde::<SwapAfterLockParameters>::deserialize(&mut input_span)
                .expect('Invalid callback data');

            // Init dispatcher
            let ekubo = IEkuboRouterDispatcher { contract_address: params.contract_address };
            let is_token1 = params.pool_key.token1 == params.token_from_address;

            // Swap
            assert_eq!(params.token_from_amount.high, 0, 'Overflow: Unsupported amount');
            let pool_price = ekubo.get_pool_price(params.pool_key);
            let sqrt_ratio_limit = compute_sqrt_ratio_limit(
                pool_price.sqrt_ratio,
                params.sqrt_ratio_distance,
                is_token1,
                MIN_SQRT_RATIO,
                MAX_SQRT_RATIO
            );
            let swap_params = SwapParameters {
                amount: i129 { mag: params.token_from_amount.low, sign: false },
                is_token1,
                sqrt_ratio_limit,
                skip_ahead: 100
            };
            let delta = ekubo.swap(params.pool_key, swap_params);

            // Each swap generates a "delta", but does not trigger any token transfers.
            // A negative delta indicates you are owed tokens. A positive delta indicates core owes you tokens.

            // Approve token_from to the exchange
            let token_from = IERC20Dispatcher { contract_address: params.token_from_address };
            let amount_from: i129 = if is_token1 {
                delta.amount1
            } else {
                delta.amount0
            };
            token_from.approve(ekubo.contract_address, amount_from.mag.into());
            ekubo.pay(params.token_from_address);

            // Withdraw
            let amount_to: i129 = if is_token1 {
                delta.amount0
            } else {
                delta.amount1
            };
            ekubo.withdraw(params.token_to_address, params.to, amount_to.mag);
        }
    }
}
