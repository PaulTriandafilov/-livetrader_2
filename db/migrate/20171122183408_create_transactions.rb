class CreateTransactions < ActiveRecord::Migration[5.1]
  def change
    create_table :transactions do |t|
      t.string :deal_type
      t.string :symbol
      t.float :price

      t.timestamps
    end
  end
end
