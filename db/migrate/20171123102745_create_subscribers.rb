class CreateSubscribers < ActiveRecord::Migration[5.1]
  def change
    create_table :subscribers do |t|
      t.integer :chat_id
      t.string :name

      t.timestamps
    end
  end
end
