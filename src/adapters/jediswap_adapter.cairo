use starknet::ContractAddress;

#[starknet::interface]
trait IJediSwapRouter<TContractState> {
    fn swap_exact_tokens_for_tokens(
        self: @TContractState,
        amountIn: u256,
        amountOutMin: u256,
        path: Array<ContractAddress>,
        to: ContractAddress,
        deadline: u64
    ) -> Array<u256>;
}

#[starknet::contract]
mod JediswapAdapter {
    use avnu::adapters::ISwapAdapter;
    use avnu::interfaces::erc20::IERC20Dispatcher;
    use starknet::{get_block_timestamp, ContractAddress};
    use array::ArrayTrait;

    #[storage]
    struct Storage {}

    #[external(v0)]
    impl JediswapAdapter of ISwapAdapter<ContractState> {
        fn swap(
            self: @ContractState,
            exchange_address: ContractAddress,
            token_from_address: ContractAddress,
            token_from_amount: u256,
            token_to_address: ContractAddress,
            token_to_min_amount: u256,
            to: ContractAddress,
            additional_swap_params: Array<felt252>,
        ) {
            // Ensure no additional parameters are provided
            assert(additional_swap_params.len() == 0, 'Invalid swap params');

            // Define the swap path
            let path = array![token_from_address, token_to_address];

            // Set the deadline to the current block timestamp
            let deadline = get_block_timestamp();

            // Approve the exchange to spend tokens
            IERC20Dispatcher { contract_address: token_from_address }
                .approve(exchange_address, token_from_amount);

            // Initiate the swap
            IJediSwapRouterDispatcher { contract_address: exchange_address }
                .swap_exact_tokens_for_tokens(
                    token_from_amount, token_to_min_amount, path, to, deadline
                );
        }
    }
}
