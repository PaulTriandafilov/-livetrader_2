require 'telegram/bot'
token = '469426190:AAEmNc3nBLSzAxemTs4ovvTccjM-MSwPUHI'

Telegram::Bot::Client.run(token) do |bot|
  bot.listen do |message|
    case message.text
      when '/start'
        bot.api.send_message(chat_id: message.chat.id, text: "Hello, #{message.from.first_name}. My bot will trade on livecoin and inform you.\nThe initial data is: btc = 0,003")

        f = File.open("../../users", 'a')
        f << "#{message.chat.id}\n"
        f.close

        puts "Described #{message.from.first_name}"
    end
  end
end