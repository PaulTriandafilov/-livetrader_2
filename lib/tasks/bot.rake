require "#{Rails.root}/app/helpers/live_helper"
include LiveHelper

namespace :bot do

  desc "test rake task"
  task run: :environment do

    # 1. Close all existed orders
    # 2. Get all currencies data and calculate trade_pairs
    # 3. Get balance
    # 4. Reject existing in balance pairs from trade_pairs
    # 5. For each cur check do we have profit? (sold or wait/remove by LOSS_TIME)
    # 6. If we have free btc => buy trade_pairs

    # 1. Close all existed orders
    # TODO

    # 2. Get all currencies data and calculate trade_pairs
    trade_pairs = ranking

    # 3. Get balance
    btc_balance = Bitcoin.first.count
    balances = Balance.all.select { |cur| cur.count > 0 }

    # 4. Reject existing in balance pairs from trade_pairs
    balances.each do |cur|
      trade_pairs.reject! { |key, value| key == cur }
    end

    # 5. Check do we have profit? (sold or wait/remove by LOSS_TIME)
    # TODO add LOSS_TIME logic
    unless balances.empty?
      balances.each do |currency|
        sold_currency(currency)
      end
    end

    # 6. If we have free btc => buy trade_pairs
    unless trade_pairs.empty?
      trade_pairs.each do |currency, value|
        buy_currency(currency)
      end
    end
  end

end
