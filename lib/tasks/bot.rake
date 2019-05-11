require 'telegram/bot'
require "#{Rails.root}/app/helpers/live_helper"
include LiveHelper


namespace :bot do

  desc "test rake task"
  task :run, [:mode] => :environment do |t, args|
    starting = Time.now

    RESULT = {start: [],
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
    available_coins.reject! { |cur| cur["currency"] == "USD" }

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
          real_coins_count = cur["value"]
          if real_coins_count != bought_data[:count]
            BuyOrder.where(currency_pair: "#{cur["currency"]}/BTC").last.update_attributes(count: real_coins_count)
            bought_data[:count] = real_coins_count
          end

          resp = currency_info("#{cur["currency"]}/BTC")
          current_ask = resp["best_ask"] - SATOSHI
          current_bid = resp["best_bid"] + SATOSHI
          current_ask_price = sprintf("%.8f", current_ask).to_f
          current_bid_price = sprintf("%.8f", current_bid).to_f

          if do_we_have_profit?(bought_data[:price], current_ask_price) || do_we_have_loss?(bought_data[:price], current_ask_price)
            resp = sell_order("#{cur["currency"]}/BTC", '%.8f' % (current_ask_price), bought_data[:count])
            if resp["success"]
              RESULT[:sold] << "- Поставил ордер на продажу #{cur["currency"]} по цене #{current_ask_price}"

            elsif resp["exception"] == "insufficient funds" || resp["exception"] == "|Minimal amount is {PARAM:0} BTC|0.0001"
              quantity = sprintf("%.8f", (MIN_ORDER_PRICE / current_bid_price)).to_f
              resp = buy_order("#{cur["currency"]}/BTC", current_bid_price, quantity)
              if resp["success"]
                buy_tran = BuyOrder.where(currency_pair: "#{cur["currency"]}/BTC").last
                buy_tran_count = buy_tran.count
                buy_tran.update_attributes(count: quantity + buy_tran_count)
                RESULT[:bought] << "- Поставил ордер на докупку #{cur["currency"]} по цене #{current_bid_price} в кол-ве #{quantity}"
              else
                RESULT[:bought] << "- ERROR: не смог поставить ордер на докупку #{cur["currency"]}: #{resp["exception"]}"
              end
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
              BuyOrder.where(currency_pair: pair).delete_all
              BuyOrder.create(currency_pair: pair, count: quantity, price: price, is_done: false)
              current_btc_balance = current_btc_balance - 1.0018 * MIN_ORDER_PRICE
              pairs_trade = pairs_trade - 1

              RESULT[:bought] << "- Поставил ордер на покупку #{pair} по цене #{price} в кол-ве #{quantity}"
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

    ending = Time.now

    elapsed = (ending - starting)

    RESULT[:current_balance] << "elapsed time = #{elapsed}"
    ############################## Send state into tg
    send_tg(args[:mode])
  end

  task :updater, :environment do
    current_orders = get_current_orders["data"]

    if !current_orders.empty?
      sell_orders = current_orders.select { |order| order["type"] == "LIMIT_SELL" }

      if sell_orders.empty?
        puts "Нету открытых ордеров на продажу"
      else
        sell_orders.each do |order|
          order_id = order["id"]
          order_market = order["currencyPair"]
          order_price = order["price"]
          order_count = order["quantity"]

          cur_inf_ = currency_info(order_market)

          unless cur_inf_.nil?
            cur_inf = cur_inf_

            current_price = cur_inf["best_ask"]
            current_ask_price = sprintf("%.8f", current_price).to_f

            profit = (current_ask_price + SATOSHI) * order_count

            if profit > 1.02 * MIN_ORDER_PRICE || (profit < 0.95 * MIN_ORDER_PRICE)
              if order_price > current_ask_price
                cancel_order(order_market, order_id)

                resp = sell_order(order_market, '%.8f' % (current_ask_price - SATOSHI), order_count)

                if resp["success"]
                  puts "Успешно выставил новый ордер на #{order_market} по #{(current_ask_price - SATOSHI)}"
                else
                  puts "ERROR: не смог поставить ордер на докупку #{order_market}: #{resp["exception"]}"
                end
              else
                puts "Цена и так лучшая"
              end
            else
              puts "Уже нет смысла что-то менять"
            end
          end
        end
      end
    else
      puts "Нету открытых ордеров"
    end
  end

  task :start do
    Rake::Task['bot:run'].reenable
    Rake::Task['bot:run'].invoke

    10.times do
      Rake::Task['bot:updater'].reenable
      Rake::Task['bot:updater'].invoke
    end
  end
end
