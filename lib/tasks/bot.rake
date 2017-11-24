require 'telegram/bot'
require "#{Rails.root}/app/helpers/live_helper"
include LiveHelper

token = '469426190:AAEmNc3nBLSzAxemTs4ovvTccjM-MSwPUHI'

namespace :bot do

  desc "test rake task"
  task run: :environment do

    results = {closed: ["2. ЗАКРЫВАЮ ОРДЕРА:"], sold: ["3. ВЫСТАВЛЯЮ ОРДЕРА НА ПРОДАЖУ:"], bought: ["4. ВЫСТАВЛЯЮ ОРДЕРА НА ПОКУПКУ:"], current_balance: ["5. ТЕКУЩЕЕ ПОЛОЖЕНИЕ ДЕЛ:"]}

    # 1. Close all existed orders
    # 2. Get all currencies data and calculate trade_pairs
    # 3. Get balance
    # 4. Reject existing in balance pairs from trade_pairs
    # 5. For each cur check do we have profit? (sold or wait/remove by LOSS_TIME)
    # 6. If we have free btc => buy trade_pairs

    # 0. Check API
    if !currency_info.include?("Could not make a request")

      # 1. Close all existed orders
      current_orders = get_current_orders["data"]
      if current_orders.nil?
        results[:closed] << "- Открытых ордеров нету"
      else
        current_orders.each do |order|
          cancel_order(order["currencyPair"], order["id"])
          results[:closed] << "- Отменил #{order["currencyPair"]} ордер - #{order["type"]}"
        end
        results[:closed] << "ИТОГО ОТМЕНЕНО #{current_orders.count} ОРДЕРОВ."
      end
      results[:closed] << "--------"

      # 2. Get all currencies data and calculate trade_pairs
      trade_pairs = ranking

      # 3. Get balance
      current_btc_balance = get_available_balance("BTC")["value"]
      available_coins = get_balances.select { |coins| coins["type"] == "available" && coins["value"] > 0.0 } # array oh hashes
      available_coins.reject! { |coin| coin["currency"] == "OTN" } # reject my sweet otns
      available_coins.reject! { |coin| coin["currency"] == "BTC" } # reject btc

      # 4. Reject existing in balance pairs from trade_pairs
      unless available_coins.empty?
        available_coins.each do |coins|
          trade_pairs.reject! { |pair, value| pair.include? coins["currency"] }
        end
      end

      # 5. For each cur check do we have profit? (sold or wait/remove by LOSS_TIME)
      unless available_coins.empty?
        available_coins.each do |cur|
          buy_transaction = BuyOrder.where(currency_pair: cur["currency"]).last

          unless buy_transaction.nil?
            bought_by = buy_transaction.price
            current_ask = currency_info("#{cur["currency"]}/BTC")["best_ask"] - SATOSHI

            if ((current_ask - bought_by)/bought_by * 100) > MIN_PROFIT
              resp = sell_order("#{cur["currency"]}/BTC", current_ask, buy_transaction.count)
              if resp["success"]
                results[:sold] << "- Поставил ордер на продажу #{cur["currency"]} по цене #{current_ask}"
              else
                results[:sold] << "ERROR: не смог поставить ордер на продажу #{cur["currency"]}: #{resp["exception"]}"
              end
            end
          end
        end
      end
      results[:sold] << "--------"

      # 6. If we have free btc => buy trade_pairs
      pairs_trade = TRADE_PAIRS_COUNT
      unless trade_pairs.empty?

        trade_pairs.each do |pair, value|

          if current_btc_balance > MIN_ORDER_PRICE && available_coins.count < pairs_trade
            bid_price = currency_info(pair)["best_bid"] + SATOSHI
            quantity = MIN_ORDER_PRICE / bid_price

            resp = buy_order(pair, bid_price, quantity)

            if resp["success"]
              BuyOrder.create(currency_pair: pair, count: quantity, price: bid_price, is_done: false)
              current_btc_balance = current_btc_balance - 1.0018 * MIN_ORDER_PRICE
              pairs_trade = pairs_trade + 1

              results[:bought] << "- Поставил ордер на покупку #{pair} по цене #{bid_price} в кол-ве #{quantity}"
            else
              results[:bought] << "ERROR: не смог поставить ордер на покупку #{pair}: #{resp["exception"]}"
            end
          end
        end
        results[:bought] << "--------"
      end


      # Request current balance

      current_balance = get_balances.select { |coins| coins["type"] == "available" && coins["value"] > 0.0 }
      current_balance.each do |balance|
        results[:current_balance] << "#{balance["currency"]} в кол-ве #{balance["value"]}"
      end

      # TG
      msg = "1. ЗАПУСКАЮСЬ. #{DateTime.now.strftime("%m/%d/%Y at %I:%M%p")} \n --------------- \n"
      results.each do |key, value|
        value.each do |message|
          msg << message + "\n"
        end
      end

    else
      # TG
      msg = "1. ЗАПУСКАЮСЬ. #{DateTime.now.strftime("%m/%d/%Y at %I:%M%p")} \n --------------- \n"
      msg << "АПИ ОПЯТЬ В ГОВНЕ"
    end

    # TG BOT
    f = File.open("users", "r")
    str = f.read
    f.close
    users = str.split("\n").uniq

    users.each do |user|
      Telegram::Bot::Client.run(token) do |bot|
        bot.api.send_message(chat_id: user.to_i, text: msg)
      end
    end

  end
end
