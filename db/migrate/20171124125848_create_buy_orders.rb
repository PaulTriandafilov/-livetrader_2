class CreateBuyOrders < ActiveRecord::Migration[5.1]
  def change
    create_table :buy_orders do |t|
      t.string :currency_pair
      t.float :count
      t.float :price
      t.boolean :is_done

      t.timestamps
    end
  end
end
