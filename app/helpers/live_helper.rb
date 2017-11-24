module LiveHelper
  require 'openssl'
  require "base64"
  require "uri"
  require "net/http"
  require 'net/https'

  API_ROOT = "https://api.livecoin.net"

  API_KEY = "bsTGqan5wbXXTvKHq14GYSdB3GmEdPBr"
  SECRET_KEY = "7AhKzGKUeSSZu6TxHYEZfVn6wjyuS3zW"

  SATOSHI = 0.00000001
  TRADE_PAIRS_COUNT = 5
  MIN_CURRENCY_PRICE = 0.00001 # 1000 satoshi
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

    ranks.sort_by { |_key, value| -value }[0..TRADE_PAIRS_COUNT-1].to_h
  end
  
  ##### API HELP #####
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
    params = {"openClosed": "open"}
    url = "/exchange/client_orders?openClosed=open"
    api_get(url, true, params)
  end

  def sell_order(currencyPair, price, quantity)
    url = "/exchange/selllimit"

    params = { "currencyPair": currencyPair,
               "price": price,
               "quantity": quantity
    }

    api_post(url, params)
  end

  def buy_order(currencyPair, price, quantity)
    url = "/exchange/buylimit"

    params = { "currencyPair": currencyPair,
               "price": price,
               "quantity": quantity
    }

    api_post(url, params)
  end

  def cancel_order(currencyPair, order_id)
    url = "/exchange/cancellimit"

    params = { "currencyPair": currencyPair,
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

end
