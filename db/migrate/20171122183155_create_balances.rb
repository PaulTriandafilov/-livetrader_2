class CreateBalances < ActiveRecord::Migration[5.1]
  def change
    create_table :balances do |t|
      t.string :symbol
      t.float :count
      t.float :balance

      t.timestamps
    end
  end
end
