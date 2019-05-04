module LiveHelper
  require 'openssl'
  require "base64"
  require "uri"
  require "net/http"
  require 'net/https'

  TG_TOKEN = '535589013:AAF_Bm3KEcRMpUZ3A7jKN0SJxWGrctIqyGA'

  API_ROOT = 'https://api.livecoin.net'

  API_KEY = 'sJeBmPvCeumBfSN5ZHzEaFDpAyDtbn8z'
  SECRET_KEY = 'xREPFc23szdPDHKbgDz3QeE3uUXre29Z'

  EXCHANGE = :livecoin
  BTC_INIT = 0.00298066
  SATOSHI = 0.00000001
  TRADE_PAIRS_COUNT = 12
  MIN_CURRENCY_PRICE = 0.000001 # 100 satoshi
  MAX_CURRENCY_PRICE = 0.01 # 10000 satoshi
  MIN_ORDER_PRICE = 0.00015 # 10000 satoshi
  MIN_PROFIT = 2 # 3%
  MIN_LOSS = -5 # 10%
  MAX_LOSS = -100 # 15%
  LOSS_TIME = 1.day

  def ranking
    ranks = {}

    data = currency_info
    data.select! { |cur| cur["symbol"].include?("/BTC") }
    data.reject! { |cur| cur["last"] <= MIN_CURRENCY_PRICE }
    data.reject! { |cur| cur["last"] >= MAX_CURRENCY_PRICE }
    data.reject! { |cur| cur["symbol"] == "OTN/BTC" } # Reject OTN

    data.each do |cur|
      rank = ((cur["best_ask"] - cur["best_bid"]) / cur["best_bid"]) * (cur["volume"] * cur["last"])
      ranks[cur["symbol"]] = rank
    end

    ranks.reject! { |_, v| v == 0.0 }
    ranks.reject! { |_, v| v == Float::INFINITY }
    ranks.reject! { |_, v| v.nan? }

    ranks.sort_by { |_key, value| -value }[0..TRADE_PAIRS_COUNT-1].to_h
  end

  def ranking_bittrex
    url = "https://bittrex.com/api/v1.1/public/getmarketsummaries"
    uri = URI(url)

    request = Net::HTTP::Get.new(uri)

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    if res.code == "200"
      data = JSON.parse(res.body)["result"]
      ranks = {}

      data.select!{ |cur| cur["MarketName"].include?("BTC") }
      data.reject! { |cur| cur["Last"] <= MIN_CURRENCY_PRICE }
      data.reject! { |cur| cur["MarketName"] == "OTN-BTC" } # Reject OTN
      data.reject! { |cur| cur["MarketName"] == "USDT-BTC" } # Reject USDT

      data.each do |cur|
        rank = ((cur["Ask"] - cur["Bid"]) / cur["Bid"]) * (cur["BaseVolume"])
        ranks[cur["MarketName"]] = rank
      end

      ranks.reject! { |_, v| v == 0.0 }
      ranks.reject! { |_, v| v == Float::INFINITY }
      ranks.reject! { |_, v| v.nan? }

      limited_ranks = ranks.sort_by { |_key, value| -value }[0..TRADE_PAIRS_COUNT-1].to_h

      limited_ranks.keys.map{|s| s.split("-").reverse.join("/")}.zip(limited_ranks.values).to_h
    else
      err = JSON.parse(res.body)
      raise "Could not make a request: #{err['Error']}"
    end

  end

  def close_all_orders(current_orders)
    current_orders.each do |order|
      cancel_order(order["currencyPair"], order["id"])
      RESULT[:closed] << "- Отменил #{order["currencyPair"]} ордер - #{order["type"]}"
    end
    RESULT[:closed] << "ИТОГО ОТМЕНЕНО #{current_orders.count} ОРДЕРОВ."
  end

  def do_we_have_profit?(bought_price, current_price)
    ((current_price - bought_price)/bought_price * 100) > MIN_PROFIT
  end

  def do_we_have_loss?(bought_price, current_price)
    ((current_price - bought_price)/bought_price * 100) < MIN_LOSS &&
        ((current_price - bought_price)/bought_price * 100) > MAX_LOSS
  end

  def get_bought_transaction(cur)
    transaction = BuyOrder.where(currency_pair: "#{cur["currency"]}/BTC").last

    {price: transaction.price, count: transaction.count} unless transaction.nil?
  end

  def get_current_balance_in_btc(total_balance)
    total_btc_count = total_balance.find { |cur| cur["currency"] == "BTC" }["value"]

    total_balance.reject { |cur| cur["currency"] == "BTC" }.reject { |cur| cur["currency"] == "USD" }.each do |cur|
      current_cur_price = currency_info("#{cur["currency"]}/BTC")["last"]
      current_cur_balance = current_cur_price * cur["value"]
      total_btc_count = total_btc_count + current_cur_balance
    end
    total_btc_count
  end

  def current_state_of_wallet
    total_balance = get_balances.select { |coins| coins["type"] == "total" && coins["value"] > 0.0 }
    total_balance.each do |balance|
      bought_data = get_bought_transaction(balance)
      if bought_data.nil?
        profit = "-"
      else
        current_ask = currency_info("#{balance["currency"]}/BTC")["best_ask"] - SATOSHI
        current_price = sprintf("%.8f", current_ask).to_f
        profit = ((current_price - bought_data[:price])/bought_data[:price] * 100).round(2)
      end

      RESULT[:current_balance] << "#{balance["currency"]} в кол-ве #{balance["value"]} (#{profit}%)"
    end

    RESULT[:current_balance] << "--------"
    btc_balance = get_current_balance_in_btc(total_balance)
    RESULT[:current_balance] << "ВСЕГО В КОШЕЛЬКЕ #{btc_balance} BTC (БЫЛО #{BTC_INIT})"
    RESULT[:current_balance] << "НАВАР СОСТАВЛЯЕТ: #{btc_balance - BTC_INIT}"
  end

  ############################## API HELPERS ##############################
  def currency_info(currency_name="")
    if currency_name.empty?
      url = "/exchange/ticker"
    else
      url = "/exchange/ticker?currencyPair=#{currency_name}"
    end

    api_get(url)
  end

  # BALANCE HELPER
  def get_balances(currency="")
    if currency.empty?
      url = "/payment/balances"
      api_get(url, true)
    else
      url = "/payment/balances?currency=#{currency}"
      params = {currency: currency}
      api_get(url, true, params)
    end
  end

  def get_available_balance(currency)
    params = {currency: currency}
    url = "/payment/balance?currency=#{currency}"
    api_get(url, true, params)
  end

  # Orders helper
  def get_current_orders
    params = {"openClosed": "OPEN"}
    url = "/exchange/client_orders?openClosed=OPEN"
    api_get(url, true, params)
  end

  def sell_order(currencyPair, price, quantity)
    url = "/exchange/selllimit"

    params = {"currencyPair": currencyPair,
              "price": price,
              "quantity": quantity
    }

    api_post(url, params)
  end

  def buy_order(currencyPair, price, quantity)
    url = "/exchange/buylimit"

    params = {"currencyPair": currencyPair,
              "price": price,
              "quantity": quantity
    }

    api_post(url, params)
  end

  def cancel_order(currencyPair, order_id)
    url = "/exchange/cancellimit"

    params = {"currencyPair": currencyPair,
              "orderId": order_id
    }

    api_post(url, params)
  end


  # Common api helpers
  def api_get(url, need_auth = false, params = {})
    uri = URI("#{API_ROOT}#{url}")

    request = Net::HTTP::Get.new(uri)
    if need_auth == true
      request.add_field("Api-key", API_KEY)
      request.add_field("Sign", signature(params))
    end

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http|
      http.request(request)
    }

    if res.code == "200"
      JSON.parse(res.body)
    else
      err = JSON.parse(res.body)
      raise "Could not make a request: #{err['Error']}"
    end
  end

  def api_post(url, params)
    uri = URI("#{API_ROOT}#{url}")

    request = Net::HTTP::Post.new(uri)
    request.set_form_data(params)
    request.add_field("Api-key", API_KEY)
    request.add_field("Sign", signature(params))

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http|
      http.request(request)
    }

    if res.code == "200"
      JSON.parse(res.body)
    else
      err = JSON.parse(res.body)
      "Could not make a request: #{err['Error']}"
    end
  end

  def signature(params={})
    hz = params.empty? ? "" : URI.encode_www_form(params)
    sha256 = OpenSSL::Digest::SHA256.new
    OpenSSL::HMAC.hexdigest(sha256, SECRET_KEY, hz).upcase
  end


  # TG BOT
  def send_tg(mode="")
    msg = ''
    RESULT.each do |_, value|
      value.each { |message| msg << message + "\n" }
    end

    if mode == "test"
      chat_ids = [291846123]
    else
      f = File.open("users", "r")
      str = f.read
      f.close
      users = str.split("\n").uniq
      chat_ids = users.collect(&:to_i)
    end

    chat_ids.each do |chat_id|
      Telegram::Bot::Client.run(TG_TOKEN) do |bot|
        bot.api.send_message(chat_id: chat_id, text: msg)
        puts "#{chat_id} - ok"
      end
    end
  end

end
