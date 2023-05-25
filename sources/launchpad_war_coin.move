
module launchpad_war_coin::launchpad {            
    use std::signer;    
    use std::error;
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use aptos_framework::coin::{Self};
    use aptos_framework::event::{Self, EventHandle};        
    use aptos_std::type_info;

    const WAR_COIN_PUBLIC_SALE_PRICE:u64 = 120000; // 0.012 APT =: 0.01$ , APT price now: $8.5
    const MINUMUM_AMOUNT_WAR_COIN:u64 = 10; // at least 10 WAR COIN should buy at once.s
    const LOT_SIZE:u64 = 100000000; // DECIMAL OF WAR COIN
    const MAXIMUM_BUY:u64 = 1000000000000000;     // MAXIMUM 10,000,000

    const ENOT_AUTHORIZED: u64 = 1;
    const ENOT_OPENED: u64 = 2;    
    const EIS_ENDED: u64 = 3;    
    const ENO_SUFFICIENT_FUND :u64 = 4;

    const MAP_X: vector<u8> = b"W_MAP_X"; 
    const MAP_Y: vector<u8> = b"W_MAP_Y"; 
    

    struct LaunchPad has store, key {          
        signer_cap: account::SignerCapability,        
        launchpad_public_open:u64,
        launchpad_public_end:u64,
        total_cap:u64,
        minimum_amount_buy:u64,
        lot_size:u64,
        price_war_coin: u64,
        coin_address_a: address,
        coin_address_b: address,
        launchpad_state_events: EventHandle<LaunchPadStateEvent>,
        launchpad_init_events: EventHandle<LaunchPadInitEvent>            
    }

    struct LaunchPadStateEvent has store, drop {                  
        sale_amount:u64,
        left:u64,
    }

    struct LaunchPadInitEvent has store, drop {                  
        launchpad_public_open:u64,
        launchpad_public_end:u64,
        total_cap:u64,
        minimum_amount_buy:u64,
    }
    
    fun coin_address<CoinType>(): address {
       let type_info = type_info::type_of<CoinType>();
       type_info::account_address(&type_info)
    }

    fun get_resource_account_cap(minter_address : address) : signer acquires LaunchPad {
        let launchpad = borrow_global<LaunchPad>(minter_address);
        account::create_signer_with_capability(&launchpad.signer_cap)
    }

    entry fun initialize<CoinType, WarCoinType> (sender: &signer, launchpad_public_open:u64, launchpad_public_end:u64, total_cap:u64) acquires LaunchPad{
        let apt_address = coin_address<CoinType>();
        let coin_address = coin_address<WarCoinType>();        
        let sender_addr = signer::address_of(sender);                
        let (resource_signer, signer_cap) = account::create_resource_account(sender, x"02");
        if(!coin::is_account_registered<CoinType>(signer::address_of(&resource_signer))){
            coin::register<CoinType>(&resource_signer);
        };
        if(!coin::is_account_registered<WarCoinType>(signer::address_of(&resource_signer))){
            coin::register<WarCoinType>(&resource_signer);
        };
        if(!exists<LaunchPad>(sender_addr)){            
            move_to(sender, LaunchPad {                
                signer_cap,
                launchpad_public_open: launchpad_public_open,
                launchpad_public_end: launchpad_public_end,
                total_cap: total_cap,
                minimum_amount_buy: MINUMUM_AMOUNT_WAR_COIN,
                lot_size: LOT_SIZE,
                price_war_coin: WAR_COIN_PUBLIC_SALE_PRICE,
                coin_address_a: apt_address,
                coin_address_b: coin_address,
                launchpad_state_events: account::new_event_handle<LaunchPadStateEvent>(sender), 
                launchpad_init_events: account::new_event_handle<LaunchPadInitEvent>(sender), 
            });
        };
        
        let launchpad = borrow_global_mut<LaunchPad>(sender_addr);                
        event::emit_event(&mut launchpad.launchpad_init_events, LaunchPadInitEvent { 
            launchpad_public_open:launchpad_public_open,
            launchpad_public_end:launchpad_public_end,
            total_cap:total_cap,
            minimum_amount_buy:MINUMUM_AMOUNT_WAR_COIN,
        });
    }

    public entry fun buy_war_coin<CoinType, WarCoinType> (receiver:&signer, launchpad_address:address, amount:u64) acquires LaunchPad {
        if(!coin::is_account_registered<WarCoinType>(signer::address_of(receiver))){
            coin::register<WarCoinType>(receiver);
        };
        let receiver_addr = signer::address_of(receiver);
        let resource_signer = get_resource_account_cap(launchpad_address);                                        
        let launchpad = borrow_global_mut<LaunchPad>(launchpad_address);                
        let coin_address_a = coin_address<CoinType>();
        let coin_address_b = coin_address<WarCoinType>();
        if(!coin::is_account_registered<WarCoinType>(signer::address_of(receiver))){
            coin::register<WarCoinType>(receiver);
        };
        assert!(coin_address_a == launchpad.coin_address_a, error::permission_denied(ENOT_AUTHORIZED));
        assert!(coin_address_b == launchpad.coin_address_b, error::permission_denied(ENOT_AUTHORIZED));

        // time constraints
        assert!(timestamp::now_seconds() > launchpad.launchpad_public_open, ENOT_OPENED);
        assert!(timestamp::now_seconds() < launchpad.launchpad_public_end, EIS_ENDED);
        
        let price_to_pay = launchpad.price_war_coin * amount;
        assert!(coin::balance<CoinType>(receiver_addr) >= price_to_pay, error::invalid_argument(ENO_SUFFICIENT_FUND));
        let coins_to_pay = coin::withdraw<CoinType>(receiver, price_to_pay * amount);                
        coin::deposit(signer::address_of(&resource_signer), coins_to_pay);
        
        let amount_to_buy = amount * launchpad.lot_size;
        assert!(amount_to_buy <= MAXIMUM_BUY, error::permission_denied(ENOT_AUTHORIZED));        
        assert!(amount_to_buy >= launchpad.minimum_amount_buy * launchpad.lot_size, error::permission_denied(ENOT_AUTHORIZED));        
        let coins = coin::withdraw<WarCoinType>(&resource_signer, amount_to_buy);                
        coin::deposit(receiver_addr, coins);        
        
        launchpad.total_cap = launchpad.total_cap - amount_to_buy;
        
        event::emit_event(&mut launchpad.launchpad_state_events, LaunchPadStateEvent { 
            sale_amount: amount_to_buy,
            left: launchpad.total_cap,
        });
    }
    

    entry fun admin_withdraw<CoinType>(sender: &signer, amount: u64) acquires LaunchPad {
        let sender_addr = signer::address_of(sender);
        let resource_signer = get_resource_account_cap(sender_addr);                                
        let coins = coin::withdraw<CoinType>(&resource_signer, amount);                
        coin::deposit(sender_addr, coins);
    }

    entry fun admin_deposit_war<WarCoinType>(sender: &signer, amount: u64) acquires LaunchPad {
        let sender_addr = signer::address_of(sender);
        let resource_signer = get_resource_account_cap(sender_addr);
        let coins = coin::withdraw<WarCoinType>(sender, amount);        
        coin::deposit(signer::address_of(&resource_signer), coins);        
    }

    entry fun admin_withdraw_war<WarCoinType>(sender: &signer, amount: u64) acquires LaunchPad {
        let sender_addr = signer::address_of(sender);
        let resource_signer = get_resource_account_cap(sender_addr);                                
        let coins = coin::withdraw<WarCoinType>(&resource_signer, amount);                
        coin::deposit(sender_addr, coins);
    }
}
