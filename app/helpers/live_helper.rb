module LiveHelper
  require "uri"
  require "net/http"
  require 'net/https'

  API_ROOT = "https://api.livecoin.net"

  SATOSHI = 0.0000001
  TRADE_PAIRS_COUNT = 10
  MIN_CURRENCY_PRICE = 0.00001 # 100 satoshi
  MIN_ORDER_PRICE = 0.0001 # 10000 satoshi
  MIN_PROFIT = 2 # 3%
  LOSS_TIME = 1.day


  def ranking
    ranks = {}

    data = currency_info
    data.select! { |cur| cur["symbol"].include?("/BTC") }
    data.reject! { |cur| cur["last"] <= MIN_CURRENCY_PRICE }

    data.each do |cur|
      rank = ((cur["best_ask"] - cur["best_bid"]) / cur["best_bid"]) * cur["volume"]
      ranks[cur["symbol"]] = rank
    end

    ranks.reject! { |k, v| v == 0.0 }
    ranks.reject! { |k, v| v == Float::INFINITY }
    ranks.reject! { |k, v| v.nan? }

    ranks.sort_by { |_key, value| -value }[0..TRADE_PAIRS_COUNT].to_h
  end

  def buy_currency(currency)
    current_btc = Bitcoin.first.count

    if will_buy?(current_btc)
      current_bid = currency_info(currency)["best_ask"] - SATOSHI
      Transaction.create(deal_type: "buy", symbol: currency, price: current_bid)

      Balance.create(symbol: currency, count: MIN_ORDER_PRICE / (current_bid), balance: MIN_ORDER_PRICE)
      current_btc = current_btc - 1.0018 * MIN_ORDER_PRICE
      Bitcoin.first.update_attributes(count: current_btc)
      puts "BUY #{currency} by #{current_bid}, btc_bank = #{current_btc}"
    end
  end

  def sold_currency(currency)
    bought_by = Transaction.where(symbol: currency.symbol).last.price
    current_best_ask = currency_info(currency.symbol)["best_bid"] + SATOSHI

    current_profit = (current_best_ask - bought_by) / bought_by * 100

    unless current_profit < MIN_PROFIT
      # create order!
      Transaction.create(deal_type: "sold", symbol: currency.symbol, price: current_best_ask)
      current_btc_balance = Balance.find_by(symbol: currency.symbol).count
      new_btc_balance = current_btc_balance + 0.9982 * Balance.find_by(symbol: currency.symbol).count * current_best_ask

      Bitcoin.first.update_attributes(count: new_btc_balance)
      Balance.find_by(symbol: currency.symbol).delete

      puts "SOLD #{currency.symbol} by #{current_best_ask}, btc_bank = #{new_btc_balance}"
    end
  end

  def will_buy?(current_btc)
    # Have enough bitcoins and free slots in Balance
    current_btc > MIN_CURRENCY_PRICE && Balance.count < TRADE_PAIRS_COUNT
  end
  
  ##### API HELP #####
  def currency_info(currency_name="")
    if currency_name.empty?
      url = "/exchange/ticker"
    else
      url = "/exchange/ticker?currencyPair=#{currency_name}"
    end

    api_get url
  end

  def api_get(url)
    uri = URI("#{API_ROOT}#{url}")
    req = Net::HTTP::Get.new(uri)
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http|
      http.request(req)
    }

    if res.code == "200"
      JSON.parse(res.body)
    elsif res.code == "401"
      return false
    elsif res.code == "404"
      return []
    else
      err = JSON.parse(res.body)
      raise "Could not make a request: #{err['Error']}"
    end
  end

end
