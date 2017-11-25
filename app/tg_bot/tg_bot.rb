require 'telegram/bot'
require 'pry'
token = '469426190:AAEmNc3nBLSzAxemTs4ovvTccjM-MSwPUHI'


Telegram::Bot::Client.run(token) do |bot|
  bot.listen do |message|

    answers = Telegram::Bot::Types::ReplyKeyboardMarkup.new(keyboard: [%w(Подписаться Отписаться)], one_time_keyboard: true)

    case message.text
      when '/start'
        bot.api.send_message(chat_id: message.chat.id,
                             text: "Hello, #{message.from.first_name}. My bot will trade on livecoin and inform you.\n Wanna susbscribe?",
                             reply_markup: answers
        )

      when 'Подписаться'
        f = File.open("../../users", 'a')
        f << "#{message.chat.id}\n"
        f.close

        puts "Described #{message.from.first_name}"

      when 'Отписаться'
        f = File.read("../../users")
        f.gsub!("#{message.chat.id}\n", "")

        File.open("../../users", "w") {|file| file.puts f }

        puts "Unsubscribed #{message.from.first_name}"
    end
  end
end