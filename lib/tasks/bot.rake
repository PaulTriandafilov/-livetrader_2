require 'telegram/bot'
require "#{Rails.root}/app/helpers/live_helper"
include LiveHelper


namespace :bot do

  desc "test rake task"
  task :run, [:mode] => :environment do |t, args|

    RESULT = {start: ["1. ЗАПУСКАЮСЬ. #{DateTime.now.strftime("%m/%d/%Y at %I:%M%p")}. #{EXCHANGE.to_s.upcase} \n ---------------"],
              closed: ["2. ЗАКРЫВАЮ ОРДЕРА:"],
              sold: ["3. ВЫСТАВЛЯЮ ОРДЕРА НА ПРОДАЖУ:"],
              bought: ["4. ВЫСТАВЛЯЮ ОРДЕРА НА ПОКУПКУ:"],
              current_balance: ["5. ТЕКУЩЕЕ ПОЛОЖЕНИЕ ДЕЛ:"]
    }

    # 1. Close all existed orders
    # 2. Get all currencies data and calculate trade_pairs
    # 3. Get balance
    # 4. Reject existing in balance pairs from trade_pairs
    # 5. For each cur check do we have profit? (sold or wait/remove by LOSS_TIME)
    # 6. If we have free btc => buy trade_pairs

    # TODO 0. Check API availability

    ############################## 1. Close all existed orders
    current_orders = get_current_orders["data"]
    if current_orders.nil?
      RESULT[:closed] << "- Открытых ордеров нету"
    else
      close_all_orders(current_orders)
    end

    RESULT[:closed] << "--------"

    ############################## 2. Get all currencies data and calculate trade_pairs
    case EXCHANGE
      when :livecoin
        trade_pairs = ranking
      when :bittrex
        trade_pairs = ranking_bittrex
    end

    ############################## 3. Get balance
    current_btc_balance = get_available_balance("BTC")["value"]
    available_coins = get_balances.select { |cur| cur["type"] == "available" && cur["value"] > 0.0 } # array oh hashes
    available_coins.reject! { |cur| cur["currency"] == "OTN" } # reject my sweet otns
    available_coins.reject! { |cur| cur["currency"] == "BTC" } # reject btc

    ############################## 4. Reject existing in balance pairs from trade_pairs
    unless available_coins.empty?
      available_coins.each { |coins| trade_pairs.reject! { |pair, _| pair.include? "#{coins["currency"]}/" } }
    end

    ############################## 5. For each cur check do we have profit? (sold or wait/remove by LOSS_TIME)
    unless available_coins.empty?
      available_coins.each do |cur|
        bought_data = get_bought_transaction(cur) # data = {price: price, count: count}

        if bought_data.nil?
          RESULT[:sold] << "ERROR: не могу найти транзакцию на покупку"
        else
          current_ask = currency_info("#{cur["currency"]}/BTC")["best_ask"] - SATOSHI
          current_price = sprintf("%.8f", current_ask).to_f

          if do_we_have_profit?(bought_data[:price], current_price)
            resp = sell_order("#{cur["currency"]}/BTC", current_price, bought_data[:count])
            if resp["success"]
              RESULT[:sold] << "- Поставил ордер на продажу #{cur["currency"]} по цене #{current_price}"
            else
              RESULT[:sold] << "ERROR: не смог поставить ордер на продажу #{cur["currency"]}: #{resp["exception"]}"
            end
          end
        end
      end

    end
    RESULT[:sold] << "--------"

    ############################## 6. If we have free btc => buy trade_pairs
    pairs_trade = TRADE_PAIRS_COUNT
    unless trade_pairs.empty?

      trade_pairs.each do |pair, _|
        if current_btc_balance > MIN_ORDER_PRICE && available_coins.count < pairs_trade
          resp = currency_info(pair)
          current_bid = resp["best_bid"]

          if current_bid.nil?
            RESULT[:bought] << "ERROR: #{pair} - #{resp["errorMessage"]}"
          else
            bid_price = current_bid + SATOSHI

            price = sprintf("%.8f", bid_price).to_f

            quantity = sprintf("%.8f", (MIN_ORDER_PRICE / price)).to_f
            resp = buy_order(pair, price, quantity)

            if resp["success"]
              BuyOrder.create(currency_pair: pair, count: quantity, price: price, is_done: false)
              current_btc_balance = current_btc_balance - 1.0018 * MIN_ORDER_PRICE
              pairs_trade = pairs_trade - 1

              RESULT[:bought] << "- Поставил ордер на покупку #{pair} по цене #{price} в кол-ве #{quantity}. #{EXCHANGE.to_s.upcase}"
            else
              RESULT[:bought] << "ERROR: не смог поставить ордер на покупку #{pair}: #{resp["exception"]}"
            end
          end
        end
      end
      RESULT[:bought] << "--------"
    end


    ############################## Request current state of wallet
    current_state_of_wallet

    ############################## Send state into tg
    send_tg(args[:mode])
  end

  task :start do
    100.times do
      Rake::Task['bot:run'].reenable
      Rake::Task['bot:run'].invoke

      sleep 60
    end
  end
end
